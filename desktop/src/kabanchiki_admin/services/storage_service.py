"""Storage facade: Supabase Storage and Google Drive, interchangeable.

Every attachment/avatar row records where its file lives (`storage` +
`path`), so READS always work for both backends. WRITES follow
app_config.storage_backend; if Drive is selected but fails, the upload
falls back to Supabase so a photo never blocks the family.
"""

from __future__ import annotations

import logging
import uuid
from pathlib import Path

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
    RECEIPTS_BUCKET,
    TASK_PHOTOS_BUCKET,
    SupabaseService,
)

log = logging.getLogger(__name__)

BUCKET_BY_ROLE = {
    "task": TASK_PHOTOS_BUCKET,
    "proof": PROOF_PHOTOS_BUCKET,
    "receipt": RECEIPTS_BUCKET,
}

PDF_MIME = "application/pdf"


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

    async def upload_photo(self, child_id: str, photo: OptimizedPhoto, kind: str = "task") -> dict:
        """Returns the attachment info dict {storage, path, thumb_path, ...}.

        `kind` picks where the file belongs — "task" or "receipt" — so a
        receipt photo is filed with the receipts rather than in the task
        gallery the owner scrolls through.
        """
        bucket = RECEIPTS_BUCKET if kind == "receipt" else TASK_PHOTOS_BUCKET
        if self.backend == "drive":
            drive = self.drive()
            if drive is not None:
                try:
                    file_id = await drive.upload(
                        kind,
                        f"{uuid.uuid4().hex}.{photo.full.ext}",
                        photo.full.mime,
                        photo.full.data,
                    )
                    thumb_id = await drive.upload(
                        kind,
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
            bucket, f"{base}.{photo.full.ext}", photo.full.data, photo.full.mime
        )
        thumb = await self.supabase.upload_bytes(
            bucket, f"{base}_t.{photo.thumb.ext}", photo.thumb.data, photo.thumb.mime
        )
        return {
            "storage": "supabase",
            "path": path,
            "thumb_path": thumb,
            "mime": photo.full.mime,
            "size_bytes": len(photo.full.data),
        }

    async def upload_document(self, child_id: str, path: str) -> dict:
        """Upload a receipt that is not an image (a PDF) exactly as it is.

        There is nothing to re-encode and no thumbnail to make, so this is the
        photo path minus both — the attachment row simply carries a null
        thumb_path and the clients show a document tile instead of a preview.
        """
        src = Path(path)
        data = src.read_bytes()
        # Trust the bytes, not the extension: the bucket enforces its MIME list
        # server-side, so a mislabelled file would fail late and confusingly.
        if not data.startswith(b"%PDF-"):
            raise ValueError("NOT_A_PDF")

        if self.backend == "drive":
            drive = self.drive()
            if drive is not None:
                try:
                    file_id = await drive.upload(
                        "receipt", f"{uuid.uuid4().hex}.pdf", PDF_MIME, data
                    )
                    return {
                        "storage": "drive",
                        "path": file_id,
                        "thumb_path": None,
                        "mime": PDF_MIME,
                        "size_bytes": len(data),
                    }
                except GDriveError:
                    log.warning("drive upload failed, falling back to supabase", exc_info=True)

        stored = await self.supabase.upload_bytes(
            RECEIPTS_BUCKET, f"{child_id}/{uuid.uuid4().hex}.pdf", data, PDF_MIME
        )
        return {
            "storage": "supabase",
            "path": stored,
            "thumb_path": None,
            "mime": PDF_MIME,
            "size_bytes": len(data),
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
