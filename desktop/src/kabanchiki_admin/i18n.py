"""Runtime language switching (en source strings, uk translation).

Translations live in i18n/uk_UA.ts; the compiled .qm is produced by
pyside6-lrelease. ensure_qm() compiles it on first run / when the .ts is
newer, so the developer never has to run lrelease by hand.
"""

from __future__ import annotations

import logging
import subprocess
import sys
from pathlib import Path

from PySide6.QtCore import QCoreApplication, QTranslator

log = logging.getLogger(__name__)

I18N_DIR = Path(__file__).parent / "i18n"

_current_translator: QTranslator | None = None


def ensure_qm() -> None:
    # Frozen builds ship a pre-compiled .qm and have no lrelease to run.
    if getattr(sys, "frozen", False):
        return
    ts = I18N_DIR / "uk_UA.ts"
    qm = I18N_DIR / "uk_UA.qm"
    if not ts.exists():
        return
    if qm.exists() and qm.stat().st_mtime >= ts.stat().st_mtime:
        return
    lrelease = Path(sys.executable).parent / "pyside6-lrelease.exe"
    command = [str(lrelease) if lrelease.exists() else "pyside6-lrelease", str(ts), "-qm", str(qm)]
    try:
        subprocess.run(command, check=True, capture_output=True, timeout=60)
        log.info("compiled %s", qm.name)
    except Exception:  # noqa: BLE001 - the app still works, just untranslated
        log.exception("lrelease failed")


def apply_language(language: str, engine=None) -> None:
    global _current_translator
    app = QCoreApplication.instance()
    if app is None:
        return
    if _current_translator is not None:
        app.removeTranslator(_current_translator)
        _current_translator = None
    if language == "uk":
        translator = QTranslator()
        if translator.load(str(I18N_DIR / "uk_UA.qm")):
            app.installTranslator(translator)
            _current_translator = translator
        else:
            log.warning("uk_UA.qm not found or invalid")
    if engine is not None:
        engine.retranslate()
