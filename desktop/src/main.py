"""Kabanchiki parent desktop app entry point."""

from __future__ import annotations

import asyncio
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import qasync
from PySide6.QtGui import QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtWidgets import QApplication

from kabanchiki_admin.app_identity import ensure_app_identity
from kabanchiki_admin.backend import Backend
from kabanchiki_admin.config import Settings, assets_dir
from kabanchiki_admin.i18n import apply_language, ensure_qm


def _setup_logging() -> None:
    """Console + rotating file: the windowed exe has no stderr, so errors
    must land somewhere the user can send us (%APPDATA%/Kabanchiki/logs)."""
    from logging.handlers import RotatingFileHandler

    from kabanchiki_admin.config import app_data_dir

    fmt = logging.Formatter("%(asctime)s %(name)s %(levelname)s %(message)s")
    root = logging.getLogger()
    root.setLevel(logging.INFO)

    console = logging.StreamHandler()
    console.setFormatter(fmt)
    root.addHandler(console)

    try:
        log_dir = app_data_dir() / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        file_handler = RotatingFileHandler(
            log_dir / "kabanchiki.log", maxBytes=1_000_000, backupCount=3, encoding="utf-8"
        )
        file_handler.setFormatter(fmt)
        root.addHandler(file_handler)
    except OSError:
        root.exception("file logging unavailable")


_setup_logging()


def main() -> int:
    # Must run before any window/toast so Windows attributes them to "Kabanchiki".
    ensure_app_identity()

    QQuickStyle.setStyle("Basic")
    app = QApplication(sys.argv)
    app.setApplicationName("Kabanchiki")
    app.setOrganizationName("Kabanchiki")
    app.setWindowIcon(QIcon(str(assets_dir() / "app.png")))
    # Closing the window hides to tray; only the tray menu really quits.
    app.setQuitOnLastWindowClosed(False)

    # Single instance: if one is already running, tell it to show its window
    # (it may be hidden in the tray) and exit this second launch.
    from PySide6.QtNetwork import QLocalServer, QLocalSocket

    socket_name = "Kabanchiki-single-instance"
    probe = QLocalSocket()
    probe.connectToServer(socket_name)
    if probe.waitForConnected(300):
        probe.write(b"show")
        probe.flush()
        probe.waitForBytesWritten(300)
        probe.disconnectFromServer()
        return 0
    probe.abort()
    QLocalServer.removeServer(socket_name)  # clear a stale socket after a crash
    instance_server = QLocalServer()
    instance_server.listen(socket_name)

    loop = qasync.QEventLoop(app)
    asyncio.set_event_loop(loop)

    settings = Settings.load()
    ensure_qm()
    apply_language(settings.language)

    backend = Backend(settings)

    engine = QQmlApplicationEngine()
    backend.set_engine(engine)
    engine.rootContext().setContextProperty("backend", backend)

    qml_dir = Path(__file__).parent / "kabanchiki_admin" / "qml"
    engine.addImportPath(str(qml_dir.parent))
    engine.load(str(qml_dir / "Main.qml"))
    if not engine.rootObjects():
        return 1

    # A second launch connects here → raise our (possibly tray-hidden) window.
    def _on_second_launch() -> None:
        conn = instance_server.nextPendingConnection()
        backend.bringToFront()
        if conn is not None:
            conn.disconnectFromServer()

    instance_server.newConnection.connect(_on_second_launch)

    with loop:
        loop.create_task(backend.start())
        loop.run_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
