"""Async Supabase access for the parent app.

The parent signs in with email/password; all data access then goes through
Row-Level Security as an authenticated parent. Auth-admin operations (creating
child/parent accounts, passwords, bans) run in the 'admin' Edge Function, which
holds the service_role key server-side.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import httpx
from supabase import AsyncClient, acreate_client

from kabanchiki_admin.config import public_config
from kabanchiki_admin.models import parse_ts

log = logging.getLogger(__name__)

EMAIL_DOMAIN = "kabanchiki.local"

TASK_PHOTOS_BUCKET = "task-photos"
PROOF_PHOTOS_BUCKET = "proof-photos"
AVATARS_BUCKET = "avatars"


class SupabaseError(RuntimeError):
    """User-presentable error from the backend."""


class AuthError(SupabaseError):
    """Sign-in failed / session invalid."""


@dataclass
class TimeSync:
    """Server clock offset: server_now ~= local_utc_now + offset."""

    offset_seconds: float = 0.0

    def now_server(self) -> datetime:
        from datetime import timedelta

        return datetime.now(UTC) + timedelta(seconds=self.offset_seconds)


class SupabaseService:
    def __init__(self, url: str = "", anon_key: str = "") -> None:
        self.client: AsyncClient | None = None
        self.time = TimeSync()
        defaults = public_config()
        # An empty configuration is valid: the app shows the connection wizard
        # on first run instead of crashing (the values are entered there).
        self._url = url or defaults.get("supabase_url", "")
        self._anon = anon_key or defaults.get("supabase_anon_key", "")

    @property
    def connected(self) -> bool:
        return self.client is not None

    @property
    def is_configured(self) -> bool:
        return bool(self._url and self._anon)

    @property
    def supabase_url(self) -> str:
        return self._url

    def configure(self, url: str, anon_key: str) -> None:
        """Point the service at a (new) Supabase project. Drops any live client."""
        self._url = url.strip()
        self._anon = anon_key.strip()
        self.client = None

    async def check_connection(self, url: str, anon_key: str) -> None:
        """Validate a Supabase URL + anon key against a fresh, un-authenticated
        client by calling the public server_now() RPC. Raises SupabaseError on
        any failure so the wizard can show a clear, secret-free message."""
        url = url.strip()
        anon_key = anon_key.strip()
        if not url.startswith("https://"):
            raise SupabaseError("The Supabase URL must start with https://")
        if not anon_key:
            raise SupabaseError("The anon (publishable) key is required")
        try:
            probe = await acreate_client(url, anon_key)
            await probe.rpc("server_now").execute()
        except Exception as exc:  # noqa: BLE001 - classified into a friendly message
            text = str(exc)
            if "getaddrinfo" in text or "Name or service" in text or "nodename" in text:
                raise SupabaseError("NO_HOST") from exc
            if "401" in text or "Invalid API key" in text or "JWSError" in text:
                raise SupabaseError("BAD_ANON_KEY") from exc
            if "PGRST202" in text or "server_now" in text or "404" in text:
                raise SupabaseError("SCHEMA_MISSING") from exc
            raise SupabaseError(text) from exc

    async def _new_client(self) -> AsyncClient:
        if not self.is_configured:
            raise SupabaseError("Supabase connection is not configured")
        return await acreate_client(self._url, self._anon)

    async def login(self, email: str, password: str) -> dict:
        """Sign in as a parent. Returns the session tokens to persist."""
        client = await self._new_client()
        try:
            res = await client.auth.sign_in_with_password(
                {"email": email.strip(), "password": password}
            )
        except Exception as exc:  # noqa: BLE001
            raise AuthError(str(exc)) from exc
        session = res.session
        if session is None:
            raise AuthError("no session")
        await self._verify_parent(client)
        self.client = client
        await self.sync_clock()
        return {"access_token": session.access_token, "refresh_token": session.refresh_token}

    async def restore(self, access_token: str, refresh_token: str) -> dict:
        """Resume a stored parent session (refreshing the access token)."""
        client = await self._new_client()
        try:
            res = await client.auth.set_session(access_token, refresh_token)
        except Exception as exc:  # noqa: BLE001
            raise AuthError(str(exc)) from exc
        session = res.session
        if session is None:
            raise AuthError("session expired")
        await self._verify_parent(client)
        self.client = client
        await self.sync_clock()
        return {"access_token": session.access_token, "refresh_token": session.refresh_token}

    async def _verify_parent(self, client: AsyncClient) -> None:
        uid = (await client.auth.get_user()).user.id
        rows = await client.table("parents").select("id").eq("id", uid).execute()
        if not rows.data:
            raise AuthError("this account is not a parent")

    async def logout(self) -> None:
        if self.client is not None:
            try:
                await self.client.auth.sign_out()
            except Exception:  # noqa: BLE001 - best-effort: drop the client anyway
                log.debug("sign_out failed during logout", exc_info=True)
        self.client = None

    async def _access_token(self) -> str:
        assert self.client is not None
        session = await self.client.auth.get_session()
        return session.access_token if session else ""

    async def call_admin(self, payload: dict) -> dict:
        """Invoke the privileged 'admin' Edge Function as the current parent."""
        token = await self._access_token()
        async with httpx.AsyncClient(timeout=60) as http:
            resp = await http.post(
                f"{self._url}/functions/v1/admin",
                headers={"Authorization": f"Bearer {token}", "apikey": self._anon},
                json=payload,
            )
        data = resp.json() if resp.content else {}
        if resp.status_code >= 400:
            raise SupabaseError(data.get("error", f"admin error {resp.status_code}"))
        return data

    async def sync_clock(self) -> None:
        assert self.client is not None
        response = await self.client.rpc("server_now", {}).execute()
        server = parse_ts(response.data)
        if server is not None:
            self.time.offset_seconds = (server - datetime.now(UTC)).total_seconds()

    # ------------------------------------------------------------- children

    async def list_children(self) -> list[dict]:
        assert self.client is not None
        response = await self.client.table("profiles").select("*").order("created_at").execute()
        return response.data or []

    async def create_child(
        self, username: str, display_name: str, password: str, avatar_color: str
    ) -> None:
        await self.call_admin(
            {
                "action": "create_child",
                "username": username.strip().lower(),
                "display_name": display_name.strip(),
                "password": password,
                "avatar_color": avatar_color,
            }
        )

    async def set_child_password(self, child_id: str, password: str) -> None:
        await self.call_admin(
            {
                "action": "set_child_password",
                "child_id": child_id,
                "password": password,
            }
        )

    async def update_child(self, child_id: str, display_name: str, avatar_color: str) -> None:
        assert self.client is not None
        await (
            self.client.table("profiles")
            .update({"display_name": display_name.strip(), "avatar_color": avatar_color})
            .eq("id", child_id)
            .execute()
        )

    async def set_child_blocked(self, child_id: str, blocked: bool) -> None:
        await self.call_admin(
            {
                "action": "set_child_blocked",
                "child_id": child_id,
                "blocked": blocked,
            }
        )

    # ------------------------------------------------------------- owners

    async def list_parents(self) -> list[dict]:
        assert self.client is not None
        response = await self.client.table("parents").select("*").order("created_at").execute()
        return response.data or []

    async def current_parent_id(self) -> str:
        assert self.client is not None
        return (await self.client.auth.get_user()).user.id

    async def create_owner(self, email: str, password: str, display_name: str) -> None:
        await self.call_admin(
            {
                "action": "create_parent",
                "email": email.strip(),
                "password": password,
                "display_name": display_name.strip(),
                "is_owner": True,
            }
        )

    async def delete_owner(self, parent_id: str) -> None:
        await self.call_admin({"action": "delete_parent", "parent_id": parent_id})

    async def update_parent(
        self, parent_id: str, display_name: str, email: str, phone: str, note: str
    ) -> None:
        await self.call_admin(
            {
                "action": "update_parent",
                "parent_id": parent_id,
                "display_name": display_name.strip(),
                "email": email.strip(),
                "phone": phone.strip(),
                "note": note.strip(),
            }
        )

    async def set_parent_disabled(self, parent_id: str, disabled: bool) -> None:
        await self.call_admin(
            {
                "action": "set_parent_disabled",
                "parent_id": parent_id,
                "disabled": disabled,
            }
        )

    async def set_own_password(self, password: str) -> None:
        await self.call_admin({"action": "set_parent_password", "password": password})

    async def delete_child(self, child_id: str) -> None:
        """Delete the auth user; the profile and all their data cascade away."""
        await self.call_admin({"action": "delete_child", "child_id": child_id})

    # ------------------------------------------------------------- telegram

    async def get_app_config(self) -> dict:
        assert self.client is not None
        response = await self.client.table("app_config").select("*").limit(1).execute()
        rows = response.data or []
        return rows[0] if rows else {}

    async def set_app_config(self, bot_username: str, miniapp_url: str) -> None:
        """Owner-only (RLS enforces it): shared Telegram bot settings."""
        assert self.client is not None
        await (
            self.client.table("app_config")
            .update(
                {
                    "telegram_bot_username": bot_username.strip(),
                    "telegram_miniapp_url": miniapp_url.strip(),
                }
            )
            .eq("id", True)
            .execute()
        )

    async def start_telegram_link(self) -> str:
        """Generate a one-time code binding this parent's Telegram on first open."""
        assert self.client is not None
        response = await self.client.rpc("parent_start_link", {}).execute()
        return response.data or ""

    async def unlink_telegram(self) -> None:
        assert self.client is not None
        await self.client.rpc("parent_unlink_telegram", {}).execute()

    async def register_tg_webhook(self) -> None:
        """Point the bot's webhook at tg-bot so quick-action buttons work."""
        await self.call_admin({"action": "register_tg_webhook"})

    async def set_bot_token(self, token: str) -> None:
        """Owner-only: store the bot token server-side (never read back)."""
        assert self.client is not None
        await self.client.rpc("set_telegram_bot_token", {"p_token": token}).execute()

    async def bot_token_configured(self) -> bool:
        assert self.client is not None
        response = await self.client.rpc("telegram_bot_configured", {}).execute()
        return bool(response.data)

    # ------------------------------------------------------------- bonuses

    async def list_bonuses(self) -> list[dict]:
        assert self.client is not None
        response = await (
            self.client.table("bonuses")
            .select("*, profiles(username, display_name, avatar_color)")
            .order("created_at", desc=True)
            .limit(300)
            .execute()
        )
        return response.data or []

    async def list_locations(self, limit: int = 400) -> list[dict]:
        """Latest points first; the server keeps at most 50 per child."""
        assert self.client is not None
        response = await (
            self.client.table("locations").select("*").order("id", desc=True).limit(limit).execute()
        )
        return response.data or []

    async def set_location_place(self, location_id: int, locality: str) -> None:
        """Parent-only: fill a point's place name resolved from coordinates."""
        assert self.client is not None
        await self.client.rpc(
            "set_location_place",
            {"p_location_id": location_id, "p_locality": locality},
        ).execute()

    async def list_events(self, limit: int = 400) -> list[dict]:
        assert self.client is not None
        response = await (
            self.client.table("events").select("*").order("id", desc=True).limit(limit).execute()
        )
        return response.data or []

    async def create_bonus(self, child_id: str, amount: float, note: str) -> None:
        assert self.client is not None
        await (
            self.client.table("bonuses")
            .insert({"child_id": child_id, "amount": amount, "note": note.strip()})
            .execute()
        )

    async def update_bonus(self, bonus_id: str, amount: float, note: str) -> None:
        assert self.client is not None
        await (
            self.client.table("bonuses")
            .update({"amount": amount, "note": note.strip()})
            .eq("id", bonus_id)
            .execute()
        )

    async def delete_bonus(self, bonus_id: str) -> None:
        assert self.client is not None
        await self.client.table("bonuses").delete().eq("id", bonus_id).execute()

    # ------------------------------------------------------------- app updates

    async def latest_release(self, platform: str = "android") -> dict | None:
        assert self.client is not None
        response = (
            await self.client.table("app_releases")
            .select("*")
            .eq("platform", platform)
            .order("version_code", desc=True)
            .limit(1)
            .execute()
        )
        rows = response.data or []
        return rows[0] if rows else None

    async def publish_release(
        self,
        apk_file: str,
        version_name: str,
        version_code: int,
        notes: str,
        mandatory: bool,
        platform: str = "android",
    ) -> None:
        """Upload the APK to the app-releases bucket and register the release."""
        assert self.client is not None
        path = Path(apk_file)
        if not path.is_file():
            raise SupabaseError(f"file not found: {apk_file}")
        object_path = f"{platform}/{version_code}/{path.name}"
        await self.client.storage.from_("app-releases").upload(
            object_path,
            path.read_bytes(),
            file_options={
                "content-type": "application/vnd.android.package-archive",
                "upsert": "true",
            },
        )
        await (
            self.client.table("app_releases")
            .insert(
                {
                    "platform": platform,
                    "version_name": version_name.strip(),
                    "version_code": version_code,
                    "apk_path": object_path,
                    "notes": notes.strip(),
                    "mandatory": mandatory,
                }
            )
            .execute()
        )

    # ------------------------------------------------------------- devices / presence

    async def list_devices(self) -> list[dict]:
        """Registered push devices: owner, last update and reported app version."""
        assert self.client is not None
        response = await (
            self.client.table("devices")
            .select("profile_id, updated_at, platform, app_version, app_version_code")
            .execute()
        )
        return response.data or []

    # ------------------------------------------------------------- tasks

    async def list_tasks(self) -> list[dict]:
        assert self.client is not None
        response = await (
            self.client.table("tasks")
            .select("*, profiles(username, display_name, avatar_color)")
            .order("created_at", desc=True)
            .execute()
        )
        return response.data or []

    async def insert_task(self, row: dict[str, Any]) -> str:
        """Insert one task row; returns its id (photos attach separately)."""
        assert self.client is not None
        response = await self.client.table("tasks").insert(row).execute()
        return response.data[0]["id"]

    async def delete_task(self, task_id: str) -> None:
        assert self.client is not None
        await self.client.table("tasks").delete().eq("id", task_id).execute()

    async def update_task(self, task_id: str, fields: dict[str, Any]) -> None:
        assert self.client is not None
        await self.client.table("tasks").update(fields).eq("id", task_id).execute()

    async def review_task(self, task_id: str, action: str, note: str = "") -> None:
        assert self.client is not None
        await self.client.rpc(
            "task_review",
            {"p_task_id": task_id, "p_action": action, "p_note": note or None},
        ).execute()

    async def duplicate_task(self, task_id: str) -> None:
        """Re-issue a task: same content, fresh 'new' status (child gets a push)."""
        assert self.client is not None
        response = await self.client.table("tasks").select("*").eq("id", task_id).execute()
        if not response.data:
            raise SupabaseError("task not found")
        src = response.data[0]
        inserted = (
            await self.client.table("tasks")
            .insert(
                {
                    "child_id": src["child_id"],
                    "title": src["title"],
                    "description": src["description"],
                    "photo_path": src.get("photo_path"),
                    "reward_type": src["reward_type"],
                    "reward_amount": src["reward_amount"],
                    "difficulty": src["difficulty"],
                    "requirements": src["requirements"],
                    "proof_text": src["proof_text"],
                    "proof_photo": src["proof_photo"],
                    "completion_mode": src.get("completion_mode", "timer"),
                }
            )
            .execute()
        )
        # Carry the reference photos over (same files, new rows).
        fresh_id = inserted.data[0]["id"]
        atts = (
            await self.client.table("attachments")
            .select("*")
            .eq("task_id", task_id)
            .eq("role", "task")
            .execute()
        )
        for a in atts.data or []:
            await self.insert_attachment(fresh_id, "task", a)

    async def signed_url(self, bucket: str, object_path: str, expires: int = 3600) -> str:
        assert self.client is not None
        if not object_path:
            return ""
        data = await self.client.storage.from_(bucket).create_signed_url(object_path, expires)
        if isinstance(data, dict):
            return data.get("signedURL") or data.get("signedUrl") or ""
        return ""

    def public_url(self, bucket: str, object_path: str) -> str:
        if not object_path:
            return ""
        return f"{self._url}/storage/v1/object/public/{bucket}/{object_path}"

    async def upload_bytes(self, bucket: str, object_path: str, data: bytes, mime: str) -> str:
        assert self.client is not None
        await self.client.storage.from_(bucket).upload(
            object_path, data, file_options={"content-type": mime}
        )
        return object_path

    async def remove_objects(self, bucket: str, paths: list[str]) -> None:
        assert self.client is not None
        paths = [p for p in paths if p]
        if paths:
            await self.client.storage.from_(bucket).remove(paths)

    # ------------------------------------------------------------- attachments

    async def list_attachments(self) -> list[dict]:
        assert self.client is not None
        response = await self.client.table("attachments").select("*").order("created_at").execute()
        return response.data or []

    async def insert_attachment(self, task_id: str, role: str, info: dict) -> None:
        assert self.client is not None
        await (
            self.client.table("attachments")
            .insert(
                {
                    "task_id": task_id,
                    "role": role,
                    "storage": info["storage"],
                    "path": info["path"],
                    "thumb_path": info.get("thumb_path"),
                    "mime": info.get("mime") or "image/jpeg",
                    "size_bytes": int(info.get("size_bytes") or 0),
                }
            )
            .execute()
        )

    async def delete_attachment_row(self, attachment_id: str) -> None:
        assert self.client is not None
        await self.client.table("attachments").delete().eq("id", attachment_id).execute()

    async def set_profile_avatar(
        self, profile_id: str, storage: str | None, path: str | None
    ) -> None:
        assert self.client is not None
        await (
            self.client.table("profiles")
            .update(
                {
                    "avatar_storage": storage,
                    "avatar_path": path,
                    "avatar_updated_at": datetime.now(UTC).isoformat(),
                }
            )
            .eq("id", profile_id)
            .execute()
        )

    # ------------------------------------------------------------- google drive

    async def set_gdrive_credentials(self, client_id: str, client_secret: str) -> None:
        assert self.client is not None
        await self.client.rpc(
            "set_gdrive_credentials",
            {
                "p_client_id": client_id,
                "p_client_secret": client_secret,
            },
        ).execute()

    async def set_gdrive_tokens(self, refresh_token: str, email: str) -> None:
        assert self.client is not None
        await self.client.rpc(
            "set_gdrive_tokens",
            {
                "p_refresh_token": refresh_token,
                "p_email": email,
            },
        ).execute()

    async def gdrive_disconnect(self) -> None:
        assert self.client is not None
        await self.client.rpc("gdrive_disconnect", {}).execute()

    async def gdrive_status(self) -> dict:
        assert self.client is not None
        response = await self.client.rpc("gdrive_status", {}).execute()
        return response.data or {}

    async def set_gdrive_folders(self, folders: dict) -> None:
        """Owner-only: publish the shared Kabanchiki folder ids to the DB cache."""
        assert self.client is not None
        await self.client.rpc("set_gdrive_folders", {"p_folders": folders}).execute()

    async def set_storage_backend(self, backend: str) -> None:
        """Owner-only via RLS: where NEW files go ('supabase' | 'drive')."""
        assert self.client is not None
        await (
            self.client.table("app_config")
            .update({"storage_backend": backend})
            .eq("id", True)
            .execute()
        )

    # ------------------------------------------------------------- jobs

    async def list_jobs(self) -> list[dict]:
        assert self.client is not None
        response = await (
            self.client.table("jobs")
            .select("*")
            .neq("status", "archived")
            .order("created_at", desc=True)
            .execute()
        )
        return response.data or []

    async def list_job_member_stats(self) -> list[dict]:
        assert self.client is not None
        response = await self.client.table("job_member_stats").select("*").execute()
        return response.data or []

    async def create_job(self, fields: dict[str, Any], child_ids: list[str]) -> None:
        assert self.client is not None
        response = await self.client.table("jobs").insert(fields).execute()
        job_id = response.data[0]["id"]
        members = [{"job_id": job_id, "child_id": child_id} for child_id in child_ids]
        if members:
            await self.client.table("job_members").insert(members).execute()

    async def update_job(self, job_id: str, fields: dict[str, Any], child_ids: list[str]) -> None:
        """Update job fields and reconcile the member list."""
        assert self.client is not None
        await self.client.table("jobs").update(fields).eq("id", job_id).execute()
        current = await (
            self.client.table("job_members").select("child_id").eq("job_id", job_id).execute()
        )
        existing = {row["child_id"] for row in current.data or []}
        wanted = set(child_ids)
        to_add = [{"job_id": job_id, "child_id": c} for c in wanted - existing]
        to_remove = list(existing - wanted)
        if to_add:
            await self.client.table("job_members").insert(to_add).execute()
        if to_remove:
            await (
                self.client.table("job_members")
                .delete()
                .eq("job_id", job_id)
                .in_("child_id", to_remove)
                .execute()
            )

    async def delete_job(self, job_id: str) -> None:
        assert self.client is not None
        await self.client.table("jobs").delete().eq("id", job_id).execute()

    async def job_start(self, job_id: str) -> None:
        assert self.client is not None
        await self.client.rpc("admin_job_start", {"p_job_id": job_id}).execute()

    async def job_stop(self, job_id: str) -> None:
        assert self.client is not None
        await self.client.rpc("admin_job_stop", {"p_job_id": job_id}).execute()

    async def job_archive(self, job_id: str) -> None:
        assert self.client is not None
        await self.client.rpc("admin_job_archive", {"p_job_id": job_id}).execute()

    # ------------------------------------------------------------- balance / ledger

    async def list_ledger(self, limit: int = 1000) -> list[dict]:
        """Every balance operation, newest first (append-only journal)."""
        assert self.client is not None
        response = await (
            self.client.table("ledger_entries")
            .select("*, profiles(username, display_name, avatar_color)")
            .order("id", desc=True)
            .limit(limit)
            .execute()
        )
        return response.data or []

    async def adjust_balance(self, child_id: str, amount: float, note: str) -> None:
        """Manual bonus / penalty / correction — a signed ledger entry with a note."""
        assert self.client is not None
        await self.client.rpc(
            "admin_adjust_balance",
            {"p_child": child_id, "p_amount": amount, "p_note": note.strip()},
        ).execute()

    async def set_balance_settings(
        self,
        min_withdrawal: float,
        withdrawals_enabled: bool,
        auto_approve_below: float,
        require_receipt_for_card: bool,
    ) -> None:
        """Owner-only via RLS: the global money settings."""
        assert self.client is not None
        await (
            self.client.table("app_config")
            .update(
                {
                    "min_withdrawal": min_withdrawal,
                    "withdrawals_enabled": withdrawals_enabled,
                    "auto_approve_below": auto_approve_below,
                    "require_receipt_for_card": require_receipt_for_card,
                }
            )
            .eq("id", True)
            .execute()
        )

    # ------------------------------------------------------------- withdrawals (payouts)

    async def list_withdrawals(self) -> list[dict]:
        assert self.client is not None
        response = await (
            self.client.table("withdrawals")
            .select("*, profiles(username, display_name, avatar_color)")
            .order("requested_at", desc=True)
            .limit(300)
            .execute()
        )
        return response.data or []

    async def create_withdrawal(self, child_id: str, amount: float | None) -> str:
        """Owner-initiated payout: create an approved withdrawal (reserved).
        amount == None pays out the whole balance. Returns the new id."""
        assert self.client is not None
        result = await self.client.rpc(
            "admin_create_withdrawal", {"p_child": child_id, "p_amount": amount}
        ).execute()
        return str(result.data).strip().strip('"')

    async def withdrawal_approve(self, withdrawal_id: str) -> None:
        assert self.client is not None
        await self.client.rpc("admin_withdrawal_approve", {"p_id": withdrawal_id}).execute()

    async def withdrawal_reject(self, withdrawal_id: str, reason: str) -> None:
        assert self.client is not None
        await self.client.rpc(
            "admin_withdrawal_reject", {"p_id": withdrawal_id, "p_reason": reason or None}
        ).execute()

    async def withdrawal_pay(self, withdrawal_id: str, method: str, comment: str) -> None:
        assert self.client is not None
        await self.client.rpc(
            "admin_withdrawal_pay",
            {"p_id": withdrawal_id, "p_method": method, "p_comment": comment or None},
        ).execute()

    async def attach_receipt(self, withdrawal_id: str, info: dict) -> None:
        """Attach a payout receipt (parent inserts directly via RLS)."""
        assert self.client is not None
        await (
            self.client.table("attachments")
            .insert(
                {
                    "withdrawal_id": withdrawal_id,
                    "role": "receipt",
                    "storage": info["storage"],
                    "path": info["path"],
                    "thumb_path": info.get("thumb_path"),
                    "mime": info.get("mime") or "image/jpeg",
                    "size_bytes": int(info.get("size_bytes") or 0),
                }
            )
            .execute()
        )
