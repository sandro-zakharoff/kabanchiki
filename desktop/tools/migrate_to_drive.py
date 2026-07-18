"""One-shot migration: copy every Supabase-stored photo to Google Drive.

Prerequisites (both are done inside the Kabanchiki desktop app):
  1. you are signed in (the script reuses the stored session), and
  2. Google Drive is connected in Settings -> Google Drive.

For every attachment/avatar with storage='supabase' the file is downloaded,
uploaded to Drive (link-shared), missing thumbnails are generated, and the DB
row is repointed. NOTHING is deleted from Supabase — clean it up manually
after you verify every client shows the photos.

Run from the desktop folder:
    .venv\\Scripts\\python.exe tools\\migrate_to_drive.py [--dry-run]
"""

from __future__ import annotations

import argparse
import asyncio
import io
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from PIL import Image

from kabanchiki_admin.config import load_session
from kabanchiki_admin.services.gdrive_service import GDriveService, load_tokens
from kabanchiki_admin.services.supabase_service import (
    AVATARS_BUCKET,
    PROOF_PHOTOS_BUCKET,
    TASK_PHOTOS_BUCKET,
    SupabaseService,
)

BUCKET_BY_ROLE = {"task": TASK_PHOTOS_BUCKET, "proof": PROOF_PHOTOS_BUCKET}
KIND_BY_ROLE = {"task": "task", "proof": "proof"}


def make_thumb(data: bytes) -> tuple[bytes, str, str]:
    """480px thumbnail for files migrated from the single-photo era."""
    img = Image.open(io.BytesIO(data))
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGB")
    k = min(1.0, 480 / max(img.width, img.height))
    if k < 1.0:
        img = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
    if img.mode == "RGBA":
        img = img.convert("RGB")
    buf = io.BytesIO()
    try:
        img.save(buf, "WEBP", quality=75, method=4)
        return buf.getvalue(), "image/webp", "webp"
    except Exception:  # noqa: BLE001
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=80)
        return buf.getvalue(), "image/jpeg", "jpg"


async def main(dry_run: bool) -> int:
    session = load_session()
    if session is None:
        print("ERROR: sign in from the Kabanchiki app first.")
        return 2
    tokens = load_tokens()
    if tokens is None:
        print("ERROR: connect Google Drive in Settings -> Google Drive first.")
        return 2

    supabase = SupabaseService()
    await supabase.restore(session["access_token"], session["refresh_token"])
    drive = GDriveService(tokens)
    info = await drive.status()
    print(f"Drive account: {info['email']}")

    client = supabase.client
    assert client is not None

    async def download(bucket: str, path: str) -> bytes:
        return await client.storage.from_(bucket).download(path)

    moved = failed = 0

    # ---- attachments ---------------------------------------------------
    rows = (await client.table("attachments").select("*")
            .eq("storage", "supabase").execute()).data or []
    print(f"attachments to migrate: {len(rows)}")
    for att in rows:
        bucket = BUCKET_BY_ROLE.get(att["role"], TASK_PHOTOS_BUCKET)
        kind = KIND_BY_ROLE.get(att["role"], "task")
        try:
            data = await download(bucket, att["path"])
            ext = Path(att["path"]).suffix.lstrip(".") or "jpg"
            mime = att.get("mime") or ("image/webp" if ext == "webp" else "image/jpeg")
            if dry_run:
                print(f"  [dry] {att['role']} {att['path']} ({len(data)/1024:.0f} KB)")
                continue
            new_id = await drive.upload(kind, f"{uuid.uuid4().hex}.{ext}", mime, data)
            if att.get("thumb_path"):
                tdata = await download(bucket, att["thumb_path"])
                text = Path(att["thumb_path"]).suffix.lstrip(".") or "jpg"
                thumb_id = await drive.upload(
                    kind, f"{uuid.uuid4().hex}_t.{text}",
                    "image/webp" if text == "webp" else "image/jpeg", tdata)
            else:
                tdata, tmime, text = make_thumb(data)
                thumb_id = await drive.upload(kind, f"{uuid.uuid4().hex}_t.{text}", tmime, tdata)
            await client.table("attachments").update({
                "storage": "drive", "path": new_id, "thumb_path": thumb_id,
            }).eq("id", att["id"]).execute()
            moved += 1
            print(f"  ok {att['role']} {att['id']}")
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"  FAIL {att['id']}: {exc}")

    # ---- avatars --------------------------------------------------------
    profiles = (await client.table("profiles").select("id, avatar_storage, avatar_path")
                .eq("avatar_storage", "supabase").execute()).data or []
    print(f"avatars to migrate: {len(profiles)}")
    for p in profiles:
        try:
            data = await download(AVATARS_BUCKET, p["avatar_path"])
            ext = Path(p["avatar_path"]).suffix.lstrip(".") or "webp"
            if dry_run:
                print(f"  [dry] avatar {p['id']} ({len(data)/1024:.0f} KB)")
                continue
            new_id = await drive.upload(
                "avatar", f"{uuid.uuid4().hex}.{ext}",
                "image/webp" if ext == "webp" else "image/jpeg", data)
            await client.table("profiles").update({
                "avatar_storage": "drive", "avatar_path": new_id,
            }).eq("id", p["id"]).execute()
            moved += 1
            print(f"  ok avatar {p['id']}")
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"  FAIL avatar {p['id']}: {exc}")

    print(f"\ndone: migrated {moved}, failed {failed}."
          "\nSupabase files were NOT deleted — remove them after checking the clients."
          "\nTo store NEW photos on Drive, switch it in Settings -> Google Drive.")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="list what would move, change nothing")
    args = parser.parse_args()
    raise SystemExit(asyncio.run(main(args.dry_run)))
