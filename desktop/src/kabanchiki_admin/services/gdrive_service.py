"""Google Drive access for the desktop (owner's personal account).

Scope is drive.file: the app only ever sees files it created itself, which is
non-sensitive — no Google verification is required and refresh tokens do not
expire for apps published to production. The desktop runs the OAuth flow with
a loopback redirect + PKCE, uploads directly with its own tokens, and pushes
the refresh token to app_secrets so the `drive` Edge Function can serve the
Android/Mini App clients that have no Google session.

Files are uploaded into Kabanchiki/{tasks,proofs,avatars} and link-shared
(reader, anyone-with-link) so every client renders them via Google's CDN
thumbnail endpoint without tokens.
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import logging
import secrets
import socket
import threading
import webbrowser
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlencode, urlparse

import httpx
import keyring

log = logging.getLogger(__name__)

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
API = "https://www.googleapis.com/drive/v3"
UPLOAD_API = "https://www.googleapis.com/upload/drive/v3"
SCOPE = "https://www.googleapis.com/auth/drive.file"

KEYRING_SERVICE = "Kabanchiki"
KEYRING_GDRIVE = "gdrive_tokens"

FOLDER_NAMES = {"task": "tasks", "proof": "proofs", "avatar": "avatars"}


class GDriveError(RuntimeError):
    """User-presentable Drive failure."""


@dataclass
class GDriveTokens:
    client_id: str
    client_secret: str
    refresh_token: str
    email: str = ""
    folders: dict = field(default_factory=dict)


def load_tokens() -> GDriveTokens | None:
    raw = keyring.get_password(KEYRING_SERVICE, KEYRING_GDRIVE)
    if not raw:
        return None
    try:
        data = json.loads(raw)
        return GDriveTokens(**data)
    except Exception:  # noqa: BLE001 - corrupt entry: treat as disconnected
        log.warning("stored gdrive tokens unreadable", exc_info=True)
        return None


def store_tokens(tokens: GDriveTokens) -> None:
    keyring.set_password(KEYRING_SERVICE, KEYRING_GDRIVE, json.dumps(tokens.__dict__))


def clear_tokens() -> None:
    try:
        keyring.delete_password(KEYRING_SERVICE, KEYRING_GDRIVE)
    except Exception:  # noqa: BLE001
        pass


# ---------------------------------------------------------------- OAuth flow


class _CodeCatcher(BaseHTTPRequestHandler):
    """One-shot loopback endpoint that captures ?code= from Google."""

    result: dict = {}

    def do_GET(self) -> None:  # noqa: N802
        query = parse_qs(urlparse(self.path).query)
        _CodeCatcher.result = {k: v[0] for k, v in query.items()}
        ok = "code" in _CodeCatcher.result
        body = (
            "<html><body style='font-family:sans-serif;text-align:center;padding-top:80px'>"
            + (
                "<h2>Kabanchiki: Google Drive підключено ✔</h2>"
                "<p>Поверніться до програми — це вікно можна закрити.</p>"
                if ok
                else "<h2>Не вдалося підключити Google Drive</h2>"
                "<p>Поверніться до програми та спробуйте ще раз.</p>"
            )
            + "</body></html>"
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args) -> None:  # silence the default stderr logging
        pass


async def oauth_connect(client_id: str, client_secret: str) -> GDriveTokens:
    """Run the browser OAuth flow; returns tokens (also stored in keyring)."""
    # free loopback port
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    redirect = f"http://127.0.0.1:{port}"

    verifier = secrets.token_urlsafe(64)[:100]
    challenge = (
        base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    )

    params = {
        "client_id": client_id,
        "redirect_uri": redirect,
        "response_type": "code",
        "scope": SCOPE + " email",
        "access_type": "offline",
        "prompt": "consent",  # always mint a refresh token
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }

    _CodeCatcher.result = {}
    server = HTTPServer(("127.0.0.1", port), _CodeCatcher)

    def _serve() -> None:
        # one request is all we need, but allow a favicon probe too
        server.timeout = 240
        while not _CodeCatcher.result:
            server.handle_request()

    thread = threading.Thread(target=_serve, daemon=True)
    thread.start()
    webbrowser.open(f"{AUTH_URL}?{urlencode(params)}")

    # Wait for the browser round-trip without blocking the Qt loop.
    for _ in range(240):
        if _CodeCatcher.result:
            break
        await asyncio.sleep(1)
    server.server_close()

    code = _CodeCatcher.result.get("code")
    if not code:
        raise GDriveError(_CodeCatcher.result.get("error") or "authorization timed out")

    async with httpx.AsyncClient(timeout=30) as http:
        resp = await http.post(
            TOKEN_URL,
            data={
                "client_id": client_id,
                "client_secret": client_secret,
                "code": code,
                "code_verifier": verifier,
                "grant_type": "authorization_code",
                "redirect_uri": redirect,
            },
        )
    data = resp.json()
    if resp.status_code != 200 or "refresh_token" not in data:
        log.error("token exchange failed: %s %s", resp.status_code, data)
        raise GDriveError(
            data.get("error_description") or data.get("error") or "token exchange failed"
        )

    tokens = GDriveTokens(
        client_id=client_id,
        client_secret=client_secret,
        refresh_token=data["refresh_token"],
    )
    service = GDriveService(tokens)
    service._access_token = data.get("access_token", "")
    tokens.email = await service.account_email()
    store_tokens(tokens)
    return tokens


# ---------------------------------------------------------------- service


class GDriveService:
    def __init__(self, tokens: GDriveTokens, on_folders_created=None) -> None:
        self.tokens = tokens
        # Called with the folder map after this service creates it, so the ids
        # can be published to the shared DB cache (app_secrets.gdrive_folders).
        self._on_folders_created = on_folders_created
        self._access_token = ""
        self._lock = asyncio.Lock()

    async def _token(self) -> str:
        async with self._lock:
            if self._access_token:
                return self._access_token
            async with httpx.AsyncClient(timeout=30) as http:
                resp = await http.post(
                    TOKEN_URL,
                    data={
                        "client_id": self.tokens.client_id,
                        "client_secret": self.tokens.client_secret,
                        "refresh_token": self.tokens.refresh_token,
                        "grant_type": "refresh_token",
                    },
                )
            data = resp.json()
            if resp.status_code != 200 or "access_token" not in data:
                log.error("token refresh failed: %s %s", resp.status_code, data)
                if data.get("error") == "invalid_grant":
                    raise GDriveError("reauth_needed")
                raise GDriveError(data.get("error_description") or "token refresh failed")
            self._access_token = data["access_token"]
            # drop the cached token slightly before it expires
            loop = asyncio.get_running_loop()
            loop.call_later(max(60, int(data.get("expires_in", 3600)) - 120), self._drop_token)
            return self._access_token

    def _drop_token(self) -> None:
        self._access_token = ""

    async def _request(self, method: str, url: str, **kwargs) -> httpx.Response:
        token = await self._token()
        headers = kwargs.pop("headers", {})
        headers["Authorization"] = f"Bearer {token}"
        async with httpx.AsyncClient(timeout=90) as http:
            resp = await http.request(method, url, headers=headers, **kwargs)
        if resp.status_code == 401:
            self._drop_token()
            token = await self._token()
            headers["Authorization"] = f"Bearer {token}"
            async with httpx.AsyncClient(timeout=90) as http:
                resp = await http.request(method, url, headers=headers, **kwargs)
        return resp

    async def account_email(self) -> str:
        resp = await self._request("GET", f"{API}/about?fields=user(emailAddress)")
        if resp.status_code != 200:
            return ""
        return (resp.json().get("user") or {}).get("emailAddress") or ""

    async def status(self) -> dict:
        resp = await self._request(
            "GET", f"{API}/about?fields=user(emailAddress),storageQuota(usage,limit)"
        )
        if resp.status_code != 200:
            raise GDriveError(f"drive unreachable ({resp.status_code})")
        data = resp.json()
        quota = data.get("storageQuota") or {}
        return {
            "email": (data.get("user") or {}).get("emailAddress") or "",
            "usage": int(quota.get("usage") or 0),
            "limit": int(quota.get("limit") or 0),
        }

    async def _folder_alive(self, folder_id: str) -> bool:
        resp = await self._request("GET", f"{API}/files/{folder_id}?fields=id,trashed")
        return resp.status_code == 200 and not resp.json().get("trashed")

    async def _create_folder(self, name: str, parent: str | None = None) -> str:
        meta = {"name": name, "mimeType": "application/vnd.google-apps.folder"}
        if parent:
            meta["parents"] = [parent]
        resp = await self._request(
            "POST",
            f"{API}/files?fields=id",
            headers={"Content-Type": "application/json"},
            content=json.dumps(meta),
        )
        if resp.status_code != 200:
            raise GDriveError(f"folder create failed ({resp.status_code})")
        return resp.json()["id"]

    async def ensure_folders(self) -> dict:
        # Reuse the shared folder map (seeded from the DB) whenever it is still
        # alive, so the desktop and the Edge Function share one Kabanchiki tree.
        folders = dict(self.tokens.folders or {})
        if folders.get("root") and await self._folder_alive(folders["root"]):
            return folders
        root = await self._create_folder("Kabanchiki")
        folders = {"root": root}
        for sub in FOLDER_NAMES.values():
            folders[sub] = await self._create_folder(sub, root)
        self.tokens.folders = folders
        store_tokens(self.tokens)
        if self._on_folders_created is not None:
            await self._on_folders_created(folders)
        return folders

    async def upload(self, kind: str, filename: str, mime: str, data: bytes) -> str:
        """Upload + link-share; returns the Drive file id."""
        folders = await self.ensure_folders()
        folder_id = folders[FOLDER_NAMES[kind]]
        boundary = f"kab{secrets.token_hex(12)}"
        meta = json.dumps({"name": filename, "parents": [folder_id]})
        body = (
            (
                f"--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{meta}\r\n"
                f"--{boundary}\r\nContent-Type: {mime}\r\n\r\n"
            ).encode()
            + data
            + f"\r\n--{boundary}--".encode()
        )
        resp = await self._request(
            "POST",
            f"{UPLOAD_API}/files?uploadType=multipart&fields=id",
            headers={"Content-Type": f"multipart/related; boundary={boundary}"},
            content=body,
        )
        if resp.status_code != 200:
            log.error("drive upload failed: %s %s", resp.status_code, resp.text[:300])
            raise GDriveError(f"upload failed ({resp.status_code})")
        file_id = resp.json()["id"]

        perm = await self._request(
            "POST",
            f"{API}/files/{file_id}/permissions",
            headers={"Content-Type": "application/json"},
            content=json.dumps({"role": "reader", "type": "anyone"}),
        )
        if perm.status_code not in (200, 204):
            log.error("drive share failed: %s %s", perm.status_code, perm.text[:300])
            raise GDriveError("share failed")
        return file_id

    async def delete(self, file_id: str) -> None:
        resp = await self._request("DELETE", f"{API}/files/{file_id}")
        if resp.status_code not in (200, 204, 404):
            raise GDriveError(f"delete failed ({resp.status_code})")


def cdn_url(file_id: str, width: int = 1920) -> str:
    """Public CDN rendition of a link-shared Drive image."""
    return f"https://drive.google.com/thumbnail?id={file_id}&sz=w{width}"
