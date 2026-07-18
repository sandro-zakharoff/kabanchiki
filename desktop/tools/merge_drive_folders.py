"""Merge duplicate "Kabanchiki" folders on Google Drive into one.

Two independent folder caches used to create two "Kabanchiki" trees (one from
the desktop, one from the Edge Function). Files still work regardless — they
are served by file id, not by path — but this tidies Drive into a single tree.

It keeps ONE Kabanchiki (the one recorded in app_secrets, or the oldest),
moves every file from the other trees' tasks/proofs/avatars into the keeper's
matching subfolder, then trashes the now-empty duplicates. File ids never
change, so the DB links stay valid.

Run from the desktop folder (signed in + Drive connected):
    .venv\\Scripts\\python.exe tools\\merge_drive_folders.py --dry-run
    .venv\\Scripts\\python.exe tools\\merge_drive_folders.py
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from kabanchiki_admin.config import load_session
from kabanchiki_admin.services.gdrive_service import (
    API,
    FOLDER_NAMES,
    GDriveService,
    load_tokens,
)
from kabanchiki_admin.services.supabase_service import SupabaseService

SUBFOLDERS = list(FOLDER_NAMES.values())  # tasks, proofs, avatars


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

    async def find(query: str, fields: str = "files(id,name)") -> list[dict]:
        resp = await drive._request(
            "GET", f"{API}/files?q={query}&fields={fields}&pageSize=1000"
            "&orderBy=createdTime")
        resp.raise_for_status() if hasattr(resp, "raise_for_status") else None
        return resp.json().get("files", []) if resp.status_code == 200 else []

    roots = await find(
        "mimeType='application/vnd.google-apps.folder' and name='Kabanchiki'"
        " and trashed=false and 'me' in owners")
    if len(roots) <= 1:
        print(f"Only {len(roots)} Kabanchiki folder — nothing to merge.")
        return 0

    status = await supabase.gdrive_status()
    keeper_id = (status.get("folders") or {}).get("root")
    keeper = next((r for r in roots if r["id"] == keeper_id), roots[0])
    others = [r for r in roots if r["id"] != keeper["id"]]
    print(f"Keeping Kabanchiki {keeper['id']}, merging {len(others)} duplicate(s).")

    async def subfolders(parent_id: str) -> dict:
        kids = await find(
            f"mimeType='application/vnd.google-apps.folder' and '{parent_id}' in parents"
            " and trashed=false")
        return {k["name"]: k["id"] for k in kids if k["name"] in SUBFOLDERS}

    keeper_subs = await subfolders(keeper["id"])
    # Make sure the keeper has all three subfolders.
    for name in SUBFOLDERS:
        if name not in keeper_subs and not dry_run:
            keeper_subs[name] = await drive._create_folder(name, keeper["id"])

    moved = 0
    for dup in others:
        dup_subs = await subfolders(dup["id"])
        for name, dup_sub_id in dup_subs.items():
            dest = keeper_subs.get(name)
            files = await find(f"'{dup_sub_id}' in parents and trashed=false")
            for f in files:
                if dry_run:
                    print(f"  [dry] move {name}/{f['name']} -> keeper/{name}")
                    continue
                resp = await drive._request(
                    "PATCH",
                    f"{API}/files/{f['id']}?addParents={dest}&removeParents={dup_sub_id}")
                if resp.status_code == 200:
                    moved += 1
                else:
                    print(f"  FAIL move {f['id']}: {resp.status_code}")
        if not dry_run:
            # Trash the emptied duplicate tree.
            await drive._request(
                "PATCH", f"{API}/files/{dup['id']}",
                headers={"Content-Type": "application/json"}, content='{"trashed": true}')
            print(f"  trashed duplicate {dup['id']}")

    # Record the keeper's folder ids as the shared cache.
    if not dry_run:
        keeper_subs = await subfolders(keeper["id"])
        await supabase.set_gdrive_folders({"root": keeper["id"], **keeper_subs})

    print(f"\ndone: moved {moved} file(s). "
          "Duplicates are in Drive Trash — delete them after a quick check.")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="show the plan, change nothing")
    args = parser.parse_args()
    raise SystemExit(asyncio.run(main(args.dry_run)))
