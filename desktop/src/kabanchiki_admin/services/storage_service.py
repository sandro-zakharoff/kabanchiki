"""Storage facade: Supabase Storage and Google Drive, interchangeable.

Every attachment/avatar row records where its file lives (`storage` +
`path`), so READS always work for both backends. WRITES follow
app_config.storage_backend; if Drive is selected but fails, the upload
falls back to Supabase so a photo never blocks the family.
"""

from __future__ import annotations

import logging
import uuid

from kabanchiki_admin.services.gdrive_service import (
    GDriveError,
    GDriveService,
    cdn_url,
    load_tokens,
)
from kabanchiki_admin.services.image_service import OptimizedImage, OptimizedPhoto
from kabanchiki_admin.services.supabase_service import (
    AVATARS_BUCKET,
    PROOF_PHOTOS_BUCKET,
    TASK_PHOTOS_BUCKET,
    SupabaseService,
)

log = logging.getLogger(__name__)

BUCKET_BY_ROLE = {"task": TASK_PHOTOS_BUCKET, "proof": PROOF_PHOTOS_BUCKET}


class StorageService:
    def __init__(self, supabase: SupabaseService) -> None:
        self.supabase = supabase
        self.backend = "supabase"  # refreshed from app_config
        self._drive: GDriveService | None = None
        self._url_cache: dict[str, str] = {}  # signed URLs (refresh cycles reuse them)
        # Shared Kabanchiki folder ids, from app_secrets.gdrive_folders (set by
        # the backend after gdrive_status). Seeds the GDriveService so both the
        # desktop and the Edge Function use the same folders.
        self.shared_folders: dict = {}

    def drive(self) -> GDriveService | None:
        if self._drive is None:
            tokens = load_tokens()
            if tokens:
                # The DB cache wins over the local one so we never fork a new
                # Kabanchiki folder that the Edge Function already created.
                if self.shared_folders.get("root"):
                    tokens.folders = dict(self.shared_folders)
                self._drive = GDriveService(tokens, on_folders_created=self._publish_folders)
        return self._drive

    async def _publish_folders(self, folders: dict) -> None:
        self.shared_folders = dict(folders)
        try:
            await self.supabase.set_gdrive_folders(folders)
        except Exception:  # noqa: BLE001 - non-fatal: local cache still works
            log.warning("could not publish gdrive folders to DB", exc_info=True)

    def reset_drive(self) -> None:
        self._drive = None

    # ------------------------------------------------------------- uploads

    async def upload_task_photo(self, child_id: str, photo: OptimizedPhoto) -> dict:
        """Returns the attachment info dict {storage, path, thumb_path, ...}."""
        if self.backend == "drive":
            drive = self.drive()
            if drive is not None:
                try:
                    file_id = await drive.upload(
                        "task",
                        f"{uuid.uuid4().hex}.{photo.full.ext}",
                        photo.full.mime,
                        photo.full.data,
                    )
                    thumb_id = await drive.upload(
                        "task",
                        f"{uuid.uuid4().hex}_t.{photo.thumb.ext}",
                        photo.thumb.mime,
                        photo.thumb.data,
                    )
                    return {
                        "storage": "drive",
                        "path": file_id,
                        "thumb_path": thumb_id,
                        "mime": photo.full.mime,
                        "size_bytes": len(photo.full.data),
                    }
                except GDriveError:
                    log.warning("drive upload failed, falling back to supabase", exc_info=True)
        base = f"{child_id}/{uuid.uuid4().hex}"
        path = await self.supabase.upload_bytes(
            TASK_PHOTOS_BUCKET, f"{base}.{photo.full.ext}", photo.full.data, photo.full.mime
        )
        thumb = await self.supabase.upload_bytes(
            TASK_PHOTOS_BUCKET, f"{base}_t.{photo.thumb.ext}", photo.thumb.data, photo.thumb.mime
        )
        return {
            "storage": "supabase",
            "path": path,
            "thumb_path": thumb,
            "mime": photo.full.mime,
            "size_bytes": len(photo.full.data),
        }

    async def upload_avatar(self, profile_id: str, img: OptimizedImage) -> tuple[str, str]:
        """Returns (storage, path)."""
        if self.backend == "drive":
            drive = self.drive()
            if drive is not None:
                try:
                    file_id = await drive.upload(
                        "avatar", f"{uuid.uuid4().hex}.{img.ext}", img.mime, img.data
                    )
                    return "drive", file_id
                except GDriveError:
                    log.warning("drive avatar failed, falling back", exc_info=True)
        path = await self.supabase.upload_bytes(
            AVATARS_BUCKET, f"{profile_id}/{uuid.uuid4().hex}.{img.ext}", img.data, img.mime
        )
        return "supabase", path

    async def delete_attachment_files(self, att: dict) -> None:
        """Best-effort cleanup of a removed attachment's files."""
        try:
            if att.get("storage") == "drive":
                drive = self.drive()
                if drive is not None:
                    await drive.delete(att["path"])
                    if att.get("thumb_path"):
                        await drive.delete(att["thumb_path"])
            else:
                bucket = BUCKET_BY_ROLE.get(att.get("role") or "task", TASK_PHOTOS_BUCKET)
                await self.supabase.remove_objects(
                    bucket, [att.get("path") or "", att.get("thumb_path") or ""]
                )
        except Exception:  # noqa: BLE001 - orphan files are harmless
            log.warning("attachment file cleanup failed", exc_info=True)

    # ------------------------------------------------------------- display URLs

    async def attachment_url(self, att: dict, thumb: bool = False) -> str:
        if not att.get("path"):
            return ""
        if att.get("storage") == "drive":
            file_id = att.get("thumb_path") if (thumb and att.get("thumb_path")) else att["path"]
            return cdn_url(file_id, 480 if thumb else 1920)
        bucket = BUCKET_BY_ROLE.get(att.get("role") or "task", TASK_PHOTOS_BUCKET)
        path = att.get("thumb_path") if (thumb and att.get("thumb_path")) else att["path"]
        key = f"{bucket}/{path}"
        if key not in self._url_cache:
            try:
                self._url_cache[key] = await self.supabase.signed_url(bucket, path)
            except Exception:  # noqa: BLE001
                log.exception("signed url failed")
                return ""
        return self._url_cache[key]

    def avatar_url(self, profile: dict, width: int = 320) -> str:
        path = profile.get("avatar_path")
        if not path:
            return ""
        if profile.get("avatar_storage") == "drive":
            return cdn_url(path, width)
        return self.supabase.public_url(AVATARS_BUCKET, path)
