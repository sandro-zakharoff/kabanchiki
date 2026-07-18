"""Native Windows toast notifications (WinRT via windows-toasts).

The toast's own audio is silenced and the custom brand sound
(assets/notification.ogg) is played through Qt Multimedia instead — WinRT
cannot play arbitrary files for unpackaged apps.

Toast button clicks arrive on a WinRT thread; we forward them through a Qt
signal so the backend handles them on the GUI thread.
"""

from __future__ import annotations

import logging

from PySide6.QtCore import QObject, QUrl, Signal
from PySide6.QtMultimedia import QAudioOutput, QMediaPlayer

from kabanchiki_admin.app_identity import APP_AUMID, APP_DISPLAY_NAME
from kabanchiki_admin.config import assets_dir

log = logging.getLogger(__name__)

SOUND_FILE = assets_dir() / "notification.ogg"

try:
    from windows_toasts import (
        InteractableWindowsToaster,
        Toast,
        ToastActivatedEventArgs,
        ToastAudio,
        ToastButton,
    )

    _TOASTS_AVAILABLE = True
except Exception:  # noqa: BLE001 - stay usable without toasts
    _TOASTS_AVAILABLE = False


class NotificationService(QObject):
    # argument string from the clicked toast button, e.g. "approve:<uuid>"
    actionTriggered = Signal(str)

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._toaster = None
        if _TOASTS_AVAILABLE:
            try:
                # Our registered AUMID makes toasts show as "Kabanchiki" with
                # the brand icon instead of "Command Prompt".
                self._toaster = InteractableWindowsToaster(
                    APP_DISPLAY_NAME, notifierAUMID=APP_AUMID
                )
            except Exception:  # noqa: BLE001
                log.exception("toaster init failed")

        self._player: QMediaPlayer | None = None
        self._audio_out: QAudioOutput | None = None
        if SOUND_FILE.exists():
            try:
                self._audio_out = QAudioOutput(self)
                self._audio_out.setVolume(1.0)
                self._player = QMediaPlayer(self)
                self._player.setAudioOutput(self._audio_out)
                self._player.setSource(QUrl.fromLocalFile(str(SOUND_FILE)))
            except Exception:  # noqa: BLE001
                log.exception("sound init failed")
                self._player = None

    def _play_sound(self) -> None:
        if self._player is None:
            return
        try:
            self._player.stop()
            self._player.setPosition(0)
            self._player.play()
        except Exception:  # noqa: BLE001
            log.exception("sound play failed")

    def _silence(self, toast: Toast) -> None:
        try:
            toast.audio = ToastAudio(silent=True)
        except Exception:  # noqa: BLE001 - toast still shows, just with sound
            log.debug("could not silence toast", exc_info=True)

    def show(self, title: str, body: str) -> None:
        log.info("toast: %s | %s (toaster=%s)", title, body, self._toaster is not None)
        if self._toaster is None:
            return
        try:
            toast = Toast([title, body])
            self._silence(toast)
            self._toaster.show_toast(toast)
            self._play_sound()
        except Exception:  # noqa: BLE001
            log.exception("toast failed")

    def show_withdrawal_request(
        self,
        title: str,
        body: str,
        withdrawal_id: str,
        approve_label: str,
        decline_label: str,
    ) -> None:
        log.info("toast(withdrawal): %s | %s (toaster=%s)", title, body, self._toaster is not None)
        if self._toaster is None:
            return
        try:
            toast = Toast([title, body])
            self._silence(toast)
            toast.AddAction(ToastButton(approve_label, arguments=f"approve:{withdrawal_id}"))
            toast.AddAction(ToastButton(decline_label, arguments=f"decline:{withdrawal_id}"))

            def on_activated(args: ToastActivatedEventArgs) -> None:
                arguments = getattr(args, "arguments", "") or ""
                if arguments:
                    # Cross-thread emit; Qt delivers it queued on the GUI thread.
                    self.actionTriggered.emit(arguments)

            toast.on_activated = on_activated
            self._toaster.show_toast(toast)
            self._play_sound()
        except Exception:  # noqa: BLE001
            log.exception("interactive toast failed")
