"""Application paths, persisted settings and the parent session.

Non-secret settings live in %APPDATA%/Kabanchiki/config.json.
The parent's Supabase session (refresh token) lives in Windows Credential
Manager (keyring) — the master service_role key is no longer used on the PC.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

import keyring

APP_NAME = "Kabanchiki"
KEYRING_SERVICE = "Kabanchiki"
KEYRING_SESSION = "supabase_session"

# Publishable connection details (the anon key is safe to ship in a client —
# every table is protected by RLS). The parent then signs in with email/password.
SUPPORTED_LANGUAGES = ("en", "uk")


def bundled_config_path() -> Path:
    """Public bootstrap config shipped beside the app, never a secret store."""
    if getattr(sys, "frozen", False):
        return Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent)) / "config.example.json"
    return Path(__file__).resolve().parents[2] / "config.example.json"


def public_config() -> dict[str, str]:
    """Load publishable connection settings from env or the bundled example."""
    values: dict[str, str] = {}
    path = bundled_config_path()
    if path.exists():
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            values.update({key: str(value) for key, value in raw.items() if value})
        except (OSError, json.JSONDecodeError):
            pass
    values["supabase_url"] = os.environ.get(
        "KABANCHIKI_SUPABASE_URL", values.get("supabase_url", "")
    )
    values["supabase_anon_key"] = os.environ.get(
        "KABANCHIKI_SUPABASE_ANON_KEY", values.get("supabase_anon_key", "")
    )
    return values


def assets_dir() -> Path:
    """Bundled assets: next to the sources in dev, inside _internal when frozen."""
    if getattr(sys, "frozen", False):
        return Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent)) / "assets"
    return Path(__file__).resolve().parents[2] / "assets"


def app_data_dir() -> Path:
    base = os.environ.get("APPDATA") or str(Path.home())
    path = Path(base) / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


def config_path() -> Path:
    return app_data_dir() / "config.json"


@dataclass
class Settings:
    supabase_url: str = ""
    supabase_anon_key: str = ""
    language: str = "uk"
    extra: dict = field(default_factory=dict)

    @classmethod
    def load(cls) -> Settings:
        path = config_path()
        if not path.exists():
            return cls()
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return cls()
        settings = cls(
            supabase_url=raw.get("supabase_url") or public_config().get("supabase_url", ""),
            supabase_anon_key=raw.get("supabase_anon_key")
            or public_config().get("supabase_anon_key", ""),
            language=raw.get("language", "uk"),
            extra={
                k: v
                for k, v in raw.items()
                if k not in ("supabase_url", "supabase_anon_key", "language")
            },
        )
        if settings.language not in SUPPORTED_LANGUAGES:
            settings.language = "uk"
        return settings

    def save(self) -> None:
        data = {
            "supabase_url": self.supabase_url,
            "supabase_anon_key": self.supabase_anon_key,
            "language": self.language,
            **self.extra,
        }
        config_path().write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def load_session() -> dict | None:
    """Stored parent session: {"access_token", "refresh_token"} or None."""
    raw = keyring.get_password(KEYRING_SERVICE, KEYRING_SESSION)
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    return data if data.get("refresh_token") else None


def store_session(access_token: str, refresh_token: str) -> None:
    keyring.set_password(
        KEYRING_SERVICE,
        KEYRING_SESSION,
        json.dumps({"access_token": access_token, "refresh_token": refresh_token}),
    )


def clear_session() -> None:
    try:
        keyring.delete_password(KEYRING_SERVICE, KEYRING_SESSION)
    except keyring.errors.PasswordDeleteError:
        pass
