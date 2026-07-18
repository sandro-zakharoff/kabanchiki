"""Windows app identity (AppUserModelID).

Without a registered AUMID, Windows attributes toast notifications to
whatever host it can find ("Command Prompt", "Kabanchiki.exe", …). We
register our own identity under HKCU with a display name and icon, and stamp
the current process with it, so every notification shows as "Kabanchiki"
with the brand icon — both windows-toasts toasts and the tray balloon.
"""

from __future__ import annotations

import ctypes
import logging
import sys
import winreg

from kabanchiki_admin.config import assets_dir

log = logging.getLogger(__name__)

APP_AUMID = "Kabanchiki.Desktop"
APP_DISPLAY_NAME = "Kabanchiki"


def ensure_app_identity() -> None:
    """Register the AUMID (idempotent) and assign it to this process."""
    try:
        key_path = rf"SOFTWARE\Classes\AppUserModelId\{APP_AUMID}"
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, key_path) as key:
            winreg.SetValueEx(key, "DisplayName", 0, winreg.REG_SZ, APP_DISPLAY_NAME)
            icon = assets_dir() / "app.ico"
            if icon.exists():
                winreg.SetValueEx(key, "IconUri", 0, winreg.REG_SZ, str(icon))
            winreg.SetValueEx(key, "IconBackgroundColor", 0, winreg.REG_SZ, "0")
    except OSError:
        log.exception("AUMID registration failed")

    if sys.platform == "win32":
        try:
            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(APP_AUMID)
        except Exception:  # noqa: BLE001
            log.exception("SetCurrentProcessExplicitAppUserModelID failed")
