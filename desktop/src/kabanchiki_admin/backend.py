"""Qt bridge: list models + slots the QML UI calls.

All I/O is async (qasync); the tick timer only re-derives displayed values
from the last server snapshot, it never invents time on its own.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timedelta
from typing import Any

from PySide6.QtCore import (
    Property,
    QAbstractListModel,
    QModelIndex,
    QObject,
    Qt,
    QTimer,
    QUrl,
    Signal,
    Slot,
)
from PySide6.QtGui import QAction, QIcon
from PySide6.QtQml import QJSValue
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon
from qasync import asyncSlot

from kabanchiki_admin.config import (
    SUPPORTED_LANGUAGES,
    Settings,
    assets_dir,
    clear_session,
    load_session,
    store_session,
)
from kabanchiki_admin.models import (
    DIFFICULTY_COLORS,
    fmt_acorns,
    fmt_acorns_words,
    fmt_date_local,
    fmt_datetime_local,
    fmt_deadline,
    fmt_duration,
    live_acorns,
    parse_ts,
)
from kabanchiki_admin.services import gdrive_service, image_service
from kabanchiki_admin.services.geocode_service import GeocodeService
from kabanchiki_admin.services.notification_service import NotificationService
from kabanchiki_admin.services.realtime_service import RealtimeService
from kabanchiki_admin.services.storage_service import StorageService
from kabanchiki_admin.services.supabase_service import (
    PROOF_PHOTOS_BUCKET,
    TASK_PHOTOS_BUCKET,
    SupabaseError,
    SupabaseService,
)

log = logging.getLogger(__name__)

ASSETS_DIR = assets_dir()
PRESENCE_ONLINE_WINDOW = timedelta(seconds=50)
LOCATION_STALE_WINDOW = timedelta(minutes=30)

# Fallback only: the latest Android versionCode is normally read live from the
# app_releases table (whatever was last published), so the desktop never needs a
# manual bump. This constant is used only when no release has been published yet.
FALLBACK_ANDROID_VERSION_CODE = 9


def js_value(value: Any) -> Any:
    """QML passes JS objects/arrays as QJSValue; unwrap to plain Python."""
    if isinstance(value, QJSValue):
        return value.toVariant()
    return value


class DictListModel(QAbstractListModel):
    """Generic list model over rows of dicts with a fixed role set."""

    def __init__(self, roles: list[str], parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._role_names = {Qt.UserRole + i: name.encode() for i, name in enumerate(roles)}
        self._roles = {name: Qt.UserRole + i for i, name in enumerate(roles)}
        self._rows: list[dict] = []

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:  # noqa: N802
        return 0 if parent.isValid() else len(self._rows)

    def roleNames(self):  # noqa: N802
        return self._role_names

    def data(self, index: QModelIndex, role: int = Qt.DisplayRole):
        if not index.isValid() or not (0 <= index.row() < len(self._rows)):
            return None
        name = self._role_names.get(role)
        if name is None:
            return None
        return self._rows[index.row()].get(name.decode())

    def set_rows(self, rows: list[dict]) -> None:
        self.beginResetModel()
        self._rows = rows
        self.endResetModel()

    def update_row(self, row_index: int, updates: dict) -> None:
        if not (0 <= row_index < len(self._rows)):
            return
        self._rows[row_index].update(updates)
        idx = self.index(row_index, 0)
        self.dataChanged.emit(idx, idx, [self._roles[k] for k in updates if k in self._roles])

    @Slot(result="QVariantList")
    def all(self) -> list[dict]:
        """Plain rows for QML code that needs the data outside a view."""
        return self._rows

    @property
    def rows(self) -> list[dict]:
        return self._rows


class Backend(QObject):
    connectedChanged = Signal()
    configuredChanged = Signal()
    connectionReadyChanged = Signal()
    busyChanged = Signal()
    languageChanged = Signal()
    pendingCountChanged = Signal()
    reviewCountChanged = Signal()
    toastRequested = Signal(str, str)  # message, kind: info|success|error

    def __init__(self, settings: Settings, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.settings = settings
        self.supabase = SupabaseService(settings.supabase_url, settings.supabase_anon_key)
        self.storage = StorageService(self.supabase)
        self.geocode = GeocodeService()
        self.realtime = RealtimeService()
        self.notifications = NotificationService(self)
        self.notifications.actionTriggered.connect(self._on_toast_action)

        self._connected = False
        self._busy = False
        self._pending_count = 0
        self._review_count = 0
        self._engine = None
        self._translator = None

        self._childrenModel = DictListModel(
            [
                "childId",
                "username",
                "displayName",
                "color",
                "activeCount",
                "doneCount",
                "balance",
                "balanceText",
                "presence",
                "currentTask",
                "blocked",
                "lastSeenText",
                "appVersion",
                "versionOutdated",
                "locationText",
                "hasLocation",
                "locationStale",
                "avatarUrl",
            ],
            self,
        )
        self._tasksModel = DictListModel(
            [
                "taskId",
                "childId",
                "childName",
                "childColor",
                "title",
                "description",
                "photoUrl",
                "rewardType",
                "rewardAmount",
                "rewardText",
                "difficulty",
                "diffColor",
                "requirements",
                "proofText",
                "proofPhoto",
                "status",
                "proofTextContent",
                "proofPhotoUrl",
                "totalText",
                "earnedAmount",
                "earnedText",
                "createdAtText",
                "dateSection",
                "completedAtText",
                "declineReason",
                "completionMode",
                "createdBy",
                "createdById",
                "deadlineText",
                "deadlineState",
                "deadlineIso",
                "childAvatarUrl",
                "photosVar",
                "proofsVar",
            ],
            self,
        )
        self._jobsModel = DictListModel(
            [
                "jobId",
                "title",
                "description",
                "rate",
                "rateText",
                "status",
                "running",
                "totalText",
                "membersVar",
            ],
            self,
        )
        # Audit feed from public.events (filled by DB triggers on all platforms).
        self._journalModel = DictListModel(
            [
                "eventId",
                "action",
                "entity",
                "actorName",
                "actorKind",
                "entityTitle",
                "childName",
                "childColor",
                "childAvatarUrl",
                "amountText",
                "noteText",
                "timeText",
                "dateText",
                "refId",
                "isTask",
                "bonusAlive",
                "bonusAmount",
                "bonusNote",
            ],
            self,
        )
        # Per-assignee personal balances (list on the Balances page).
        self._balancesModel = DictListModel(
            [
                "childId",
                "name",
                "color",
                "avatarUrl",
                "balance",
                "balanceText",
                "weekText",
                "monthText",
                "blocked",
            ],
            self,
        )
        # The ledger — every balance operation, newest first.
        self._ledgerModel = DictListModel(
            [
                "entryId",
                "childId",
                "childName",
                "kind",
                "amount",
                "amountText",
                "positive",
                "note",
                "title",
                "timeText",
                "dateText",
                "actorName",
                "sourceEntity",
                "sourceId",
            ],
            self,
        )
        # Payout registry (withdrawals) with the full lifecycle.
        self._withdrawalsModel = DictListModel(
            [
                "wId",
                "childId",
                "childName",
                "childColor",
                "childAvatarUrl",
                "amount",
                "amountText",
                "status",
                "method",
                "comment",
                "rejectReason",
                "requestedAtText",
                "approvedAtText",
                "paidAtText",
                "confirmedAtText",
                "receiptsVar",
            ],
            self,
        )
        # Withdrawals that need the owner's action (approve / pay).
        self._attentionModel = DictListModel(
            [
                "wId",
                "childId",
                "childName",
                "childColor",
                "childAvatarUrl",
                "amount",
                "amountText",
                "status",
                "method",
                "requestedAtText",
            ],
            self,
        )
        self._events_raw: list[dict] = []
        self._locations_raw: list[dict] = []
        self._attachments_raw: list[dict] = []
        self._ledger_raw: list[dict] = []
        self._withdrawals_raw: list[dict] = []
        self._ledger_child = ""  # selected assignee for the balance-card history
        self._withdrawal_filter = {"child": "", "status": "", "method": "", "period": ""}
        self._balance_settings = {
            "min_withdrawal": 0.0,
            "withdrawals_enabled": True,
            "auto_approve_below": 0.0,
            "require_receipt_for_card": False,
        }
        self._journal_filter = {"entity": "", "child": "", "period": "", "query": ""}
        self._gdrive = {"has_credentials": False, "connected": False, "email": "", "client_id": ""}

        # raw snapshots used by the tick timer
        self._jobs_raw: list[dict] = []
        self._stats_raw: list[dict] = []
        self._children_raw: list[dict] = []
        self._bonuses_raw: list[dict] = []
        self._devices_raw: list[dict] = []
        self._snapshot_server: datetime | None = None
        self._snapshot_local: datetime | None = None
        self._signed_url_cache: dict[str, str] = {}
        self._refresh_task: asyncio.Task | None = None
        self._geocode_task: asyncio.Task | None = None

        self._tick_timer = QTimer(self)
        self._tick_timer.setInterval(1000)
        self._tick_timer.timeout.connect(self._tick)

        self._periodic_timer = QTimer(self)
        self._periodic_timer.setInterval(45_000)
        self._periodic_timer.timeout.connect(lambda: self._schedule_refresh(0))

        # Lightweight presence poll: only the profiles table, every 15 s.
        self._presence_timer = QTimer(self)
        self._presence_timer.setInterval(15_000)
        self._presence_timer.timeout.connect(self._presence_tick)
        self._tasks_raw: list[dict] = []

        self._parent_email = ""
        self._owners: list[dict] = []
        self._is_owner = False
        self._telegram = {
            "bot_username": "",
            "miniapp_url": "",
            "linked": False,
            "bot_configured": False,
        }
        self._latest_android_code = FALLBACK_ANDROID_VERSION_CODE

        self._window = None
        self._allow_quit = False
        self._tray: QSystemTrayIcon | None = None
        self._setup_tray()

    # ------------------------------------------------------------- tray / window

    def _setup_tray(self) -> None:
        icon = QIcon(str(ASSETS_DIR / "app.png"))
        self._tray = QSystemTrayIcon(icon, self)
        menu = QMenu()
        show_action = QAction(self.tr("Show Kabanchiki"), self)
        show_action.triggered.connect(self.bringToFront)
        quit_action = QAction(self.tr("Exit"), self)
        quit_action.triggered.connect(self.quitFromTray)
        menu.addAction(show_action)
        menu.addSeparator()
        menu.addAction(quit_action)
        self._tray.setContextMenu(menu)
        self._tray.setToolTip("Kabanchiki")
        self._tray.activated.connect(self._on_tray_activated)
        self._tray.show()

    def _on_tray_activated(self, reason) -> None:
        if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick):
            self.bringToFront()

    @Slot("QVariant")
    def attachWindow(self, window) -> None:  # noqa: N802
        self._window = window

    @Slot()
    def bringToFront(self) -> None:  # noqa: N802
        if self._window is None:
            return
        self._window.show()
        self._window.raise_()
        self._window.requestActivate()

    @Slot()
    def quitFromTray(self) -> None:  # noqa: N802
        self._allow_quit = True
        self.allowQuitChanged.emit()
        if self._tray:
            self._tray.hide()
        QApplication.quit()

    @Slot()
    def notifyMinimizedToTray(self) -> None:  # noqa: N802
        if self._tray:
            self._tray.showMessage(
                self.tr("Kabanchiki is still running"),
                self.tr("Affordable earnings"),
                QIcon(str(ASSETS_DIR / "app.png")),
                2500,
            )

    allowQuitChanged = Signal()

    def _get_allow_quit(self) -> bool:
        return self._allow_quit

    allowQuit = Property(bool, _get_allow_quit, notify=allowQuitChanged)

    # ------------------------------------------------------------- properties

    def set_engine(self, engine) -> None:
        self._engine = engine

    def _get_connected(self) -> bool:
        return self._connected

    def _get_configured(self) -> bool:
        return load_session() is not None

    def _get_connection_ready(self) -> bool:
        return self.supabase.is_configured

    def _get_supabase_url(self) -> str:
        return self.supabase.supabase_url

    def _get_busy(self) -> bool:
        return self._busy

    def _get_language(self) -> str:
        return self.settings.language

    def _get_pending_count(self) -> int:
        return self._pending_count

    def _get_review_count(self) -> int:
        return self._review_count

    connected = Property(bool, _get_connected, notify=connectedChanged)
    configured = Property(bool, _get_configured, notify=configuredChanged)
    connectionReady = Property(bool, _get_connection_ready, notify=connectionReadyChanged)
    supabaseUrl = Property(str, _get_supabase_url, notify=connectionReadyChanged)
    busy = Property(bool, _get_busy, notify=busyChanged)
    language = Property(str, _get_language, notify=languageChanged)
    pendingCount = Property(int, _get_pending_count, notify=pendingCountChanged)
    reviewCount = Property(int, _get_review_count, notify=reviewCountChanged)

    def _get_children_model(self) -> QObject:
        return self._childrenModel

    def _get_tasks_model(self) -> QObject:
        return self._tasksModel

    def _get_jobs_model(self) -> QObject:
        return self._jobsModel

    def _get_journal_model(self) -> QObject:
        return self._journalModel

    def _get_attention_model(self) -> QObject:
        return self._attentionModel

    def _get_balances_model(self) -> QObject:
        return self._balancesModel

    def _get_ledger_model(self) -> QObject:
        return self._ledgerModel

    def _get_withdrawals_model(self) -> QObject:
        return self._withdrawalsModel

    childrenModel = Property(QObject, _get_children_model, constant=True)
    tasksModel = Property(QObject, _get_tasks_model, constant=True)
    jobsModel = Property(QObject, _get_jobs_model, constant=True)
    journalModel = Property(QObject, _get_journal_model, constant=True)
    attentionModel = Property(QObject, _get_attention_model, constant=True)
    balancesModel = Property(QObject, _get_balances_model, constant=True)
    ledgerModel = Property(QObject, _get_ledger_model, constant=True)
    withdrawalsModel = Property(QObject, _get_withdrawals_model, constant=True)

    childOptionsChanged = Signal()

    def _get_child_options(self) -> list:
        return [
            {"id": row["childId"], "name": row["displayName"], "color": row["color"]}
            for row in self._childrenModel.rows
        ]

    childOptions = Property("QVariantList", _get_child_options, notify=childOptionsChanged)

    def _get_app_icon_url(self) -> str:
        return QUrl.fromLocalFile(str(ASSETS_DIR / "app.png")).toString()

    appIconUrl = Property(str, _get_app_icon_url, constant=True)

    # The acorn mark, resolved here rather than by a relative path in QML so it
    # keeps working from the frozen bundle, where assets move into _internal.
    def _get_acorn_icon_url(self) -> str:
        return QUrl.fromLocalFile(str(ASSETS_DIR / "acorn.svg")).toString()

    acornIconUrl = Property(str, _get_acorn_icon_url, constant=True)

    @Slot(float, result=str)
    def acornWords(self, amount: float) -> str:  # noqa: N802
        """'5 жолудів' — for sentences, where an icon cannot sit inline."""
        return fmt_acorns_words(amount, self.settings.language)

    def _set_busy(self, value: bool) -> None:
        if self._busy != value:
            self._busy = value
            self.busyChanged.emit()

    def _set_connected(self, value: bool) -> None:
        if self._connected != value:
            self._connected = value
            self.connectedChanged.emit()

    # ------------------------------------------------------------- lifecycle

    async def start(self) -> None:
        session = load_session()
        if session is None:
            return
        try:
            tokens = await self.supabase.restore(session["access_token"], session["refresh_token"])
        except Exception:  # noqa: BLE001 - stored session invalid: fall back to login
            log.info("stored session invalid, need login")
            clear_session()
            self.configuredChanged.emit()
            return
        # Persist the refreshed tokens so the rotated refresh token stays valid.
        store_session(tokens["access_token"], tokens["refresh_token"])
        await self._after_auth()

    async def _after_auth(self) -> None:
        """Wire up realtime + timers once a parent session is active."""
        self._set_busy(True)
        try:
            user = await self.supabase.client.auth.get_user()
            self._parent_email = (user.user.email or "") if user and user.user else ""
            self.parentEmailChanged.emit()
            self._watch_session()
            await self.realtime.start(self.supabase.client, self._on_change)
            self._set_connected(True)
            await self.refresh_all()
            self._tick_timer.start()
            self._periodic_timer.start()
            self._presence_timer.start()
        except Exception as exc:  # noqa: BLE001
            log.exception("post-auth setup failed")
            self.toastRequested.emit(
                self.tr("Connection failed: %1").replace("%1", str(exc)), "error"
            )
        finally:
            self._set_busy(False)

    def _watch_session(self) -> None:
        """Persist rotated tokens so the login survives app restarts long-term."""
        client = self.supabase.client
        if client is None:
            return

        def _on_auth(event, session) -> None:
            try:
                ev = str(event).upper()
                if session and ("REFRESH" in ev or "SIGNED_IN" in ev):
                    store_session(session.access_token, session.refresh_token)
            except Exception:  # noqa: BLE001
                log.exception("persist session failed")

        try:
            client.auth.on_auth_state_change(_on_auth)
        except Exception:  # noqa: BLE001
            log.exception("on_auth_state_change failed")

    @asyncSlot(str, str)
    async def saveConnection(self, url: str, anon_key: str) -> None:  # noqa: N802
        """First-run wizard: validate a Supabase project, then remember it.

        The connection is only saved once server_now() answers, so a wrong URL
        or key never leaves the user on a dead screen. The anon key is a
        publishable value; it is stored in %APPDATA%/config.json, never logged.
        """
        url = url.strip()
        anon_key = anon_key.strip()
        self._set_busy(True)
        try:
            await self.supabase.check_connection(url, anon_key)
        except Exception as exc:  # noqa: BLE001
            self._set_busy(False)
            log.info("connection check failed for %s", url)
            self.toastRequested.emit(self._human_error(exc), "error")
            return
        self._set_busy(False)
        self.supabase.configure(url, anon_key)
        self.settings.supabase_url = url
        self.settings.supabase_anon_key = anon_key
        self.settings.save()
        self.connectionReadyChanged.emit()
        self.toastRequested.emit(self.tr("Connected. Sign in to continue."), "success")

    @asyncSlot(str, str)
    async def changeConnection(self, url: str, anon_key: str) -> None:  # noqa: N802
        """Switch to a different Supabase project from Settings. Validates first,
        then signs the current session out so the owner re-authenticates there."""
        url = url.strip()
        anon_key = anon_key.strip()
        if url == self.supabase.supabase_url and not anon_key:
            return
        self._set_busy(True)
        try:
            await self.supabase.check_connection(url, anon_key)
        except Exception as exc:  # noqa: BLE001
            self._set_busy(False)
            self.toastRequested.emit(self._human_error(exc), "error")
            return
        self._set_busy(False)
        if self._connected:
            await self.logout()
        self.supabase.configure(url, anon_key)
        self.settings.supabase_url = url
        self.settings.supabase_anon_key = anon_key
        self.settings.save()
        self.connectionReadyChanged.emit()
        self.configuredChanged.emit()
        self.toastRequested.emit(self.tr("Project changed. Sign in to continue."), "success")

    @asyncSlot(str, str)
    async def login(self, email: str, password: str) -> None:  # noqa: N802
        email = email.strip()
        if not email or not password:
            self.toastRequested.emit(self.tr("Enter email and password"), "error")
            return
        self._set_busy(True)
        try:
            session = await self.supabase.login(email, password)
        except Exception:  # noqa: BLE001
            self._set_busy(False)
            self.toastRequested.emit(self.tr("Wrong email or password"), "error")
            return
        self._set_busy(False)
        store_session(session["access_token"], session["refresh_token"])
        self.configuredChanged.emit()
        await self._after_auth()
        self.toastRequested.emit(self.tr("Signed in"), "success")

    @asyncSlot()
    async def logout(self) -> None:  # noqa: N802
        self._tick_timer.stop()
        self._periodic_timer.stop()
        self._presence_timer.stop()
        await self.realtime.stop()
        await self.supabase.logout()
        clear_session()
        self._set_connected(False)
        self.configuredChanged.emit()

    @asyncSlot(str, str, str)
    async def createOwner(self, email: str, password: str, display_name: str) -> None:  # noqa: N802
        try:
            if len(password) < 6 or "@" not in email:
                self.toastRequested.emit(
                    self.tr("Enter a valid email and password (min. 6)"), "error"
                )
                return
            await self.supabase.create_owner(email, password, display_name)
            self.toastRequested.emit(self.tr("Owner added"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("createOwner")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str)
    async def deleteOwner(self, parent_id: str) -> None:  # noqa: N802
        try:
            await self.supabase.delete_owner(parent_id)
            self.toastRequested.emit(self.tr("Owner removed"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str)
    async def changeOwnPassword(self, password: str) -> None:  # noqa: N802
        try:
            if len(password) < 6:
                self.toastRequested.emit(self.tr("Password too short"), "error")
                return
            await self.supabase.set_own_password(password)
            self.toastRequested.emit(self.tr("Password updated"), "success")
        except Exception as exc:  # noqa: BLE001
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str, str, str, str, str)
    async def updateOwner(  # noqa: N802
        self, parent_id: str, display_name: str, email: str, phone: str, note: str
    ) -> None:
        try:
            if "@" not in email:
                self.toastRequested.emit(self.tr("Enter a valid email"), "error")
                return
            await self.supabase.update_parent(parent_id, display_name, email, phone, note)
            self.toastRequested.emit(self.tr("Owner updated"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("updateOwner")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str, bool)
    async def setOwnerDisabled(self, parent_id: str, disabled: bool) -> None:  # noqa: N802
        try:
            await self.supabase.set_parent_disabled(parent_id, disabled)
            self.toastRequested.emit(
                self.tr("Owner disabled") if disabled else self.tr("Owner enabled"), "success"
            )
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("setOwnerDisabled")
            self.toastRequested.emit(self._human_error(exc), "error")

    @Slot(str, result="QVariantList")
    def locationHistory(self, child_id: str) -> list:  # noqa: N802
        """Recent points (newest first) for the location dialog."""
        rows = []
        for point in self._locations_raw:
            if point["child_id"] != child_id:
                continue
            rows.append(
                {
                    "lat": float(point["lat"]),
                    "lng": float(point["lng"]),
                    "accuracy": float(point["accuracy"] or 0),
                    "locality": point.get("locality") or "",
                    "timeText": fmt_datetime_local(parse_ts(point.get("created_at"))),
                }
            )
        return rows

    # ------------------------------------------------------------- refresh

    def _schedule_refresh(self, delay_ms: int = 400) -> None:
        if self._refresh_task and not self._refresh_task.done():
            self._refresh_task.cancel()

        async def _run() -> None:
            try:
                await asyncio.sleep(delay_ms / 1000)
                await self.refresh_all()
            except asyncio.CancelledError:
                pass
            except Exception:  # noqa: BLE001
                log.exception("refresh failed")

        self._refresh_task = asyncio.create_task(_run())

    async def refresh_all(self) -> None:
        if not self.supabase.connected:
            return
        (
            children,
            tasks,
            jobs,
            stats,
            withdrawals,
            bonuses,
            devices,
            latest_rel,
            events,
            locations,
            attachments,
            ledger,
        ) = await asyncio.gather(
            self.supabase.list_children(),
            self.supabase.list_tasks(),
            self.supabase.list_jobs(),
            self.supabase.list_job_member_stats(),
            self.supabase.list_withdrawals(),
            self.supabase.list_bonuses(),
            self.supabase.list_devices(),
            self.supabase.latest_release("android"),
            self.supabase.list_events(),
            self.supabase.list_locations(),
            self.supabase.list_attachments(),
            self.supabase.list_ledger(),
        )
        await self.supabase.sync_clock()
        # Latest published Android build drives the "outdated" badge — read live.
        if latest_rel and latest_rel.get("version_code"):
            self._latest_android_code = int(latest_rel["version_code"])
        self._children_raw = children
        self._tasks_raw = tasks
        self._jobs_raw = jobs
        self._stats_raw = stats
        self._bonuses_raw = bonuses
        self._devices_raw = devices
        self._ledger_raw = ledger
        self._withdrawals_raw = withdrawals
        self._snapshot_server = self._max_snapshot(stats)
        self._snapshot_local = datetime.now().astimezone()

        self._events_raw = events
        self._locations_raw = locations
        self._attachments_raw = attachments
        self._schedule_locality_backfill()
        await self._rebuild_children(children, tasks)
        await self._rebuild_tasks(tasks)
        self._rebuild_jobs()
        self._rebuild_attention(withdrawals)
        self._rebuild_balances()
        self._rebuild_ledger()
        await self._rebuild_withdrawals()
        self._rebuild_journal()
        self.childOptionsChanged.emit()

        try:
            self._owners = await self.supabase.list_parents()
            self.ownersChanged.emit()
            me = next(
                (o for o in self._owners if (o.get("email") or "") == self._parent_email), None
            )
            self._is_owner = bool(me and me.get("is_owner"))
            self._telegram["linked"] = bool(me and me.get("telegram_id"))
            cfg = await self.supabase.get_app_config()
            self._telegram["bot_username"] = cfg.get("telegram_bot_username") or ""
            self._telegram["miniapp_url"] = cfg.get("telegram_miniapp_url") or ""
            self._telegram["bot_configured"] = await self.supabase.bot_token_configured()
            self.telegramChanged.emit()
            self._balance_settings = {
                "min_withdrawal": float(cfg.get("min_withdrawal") or 0),
                "withdrawals_enabled": bool(cfg.get("withdrawals_enabled", True)),
                "auto_approve_below": float(cfg.get("auto_approve_below") or 0),
                "require_receipt_for_card": bool(cfg.get("require_receipt_for_card")),
            }
            self.balanceSettingsChanged.emit()
            self.storage.backend = cfg.get("storage_backend") or "supabase"
            self._gdrive = await self.supabase.gdrive_status()
            # Seed the shared Drive folder ids so uploads reuse one Kabanchiki tree.
            self.storage.shared_folders = self._gdrive.get("folders") or {}
            self.gdriveChanged.emit()
        except Exception:  # noqa: BLE001 - settings metadata is non-critical for the refresh
            log.warning("owners/telegram refresh failed", exc_info=True)

        # Payouts awaiting an owner action: requested (approve/reject) or approved (pay).
        pending = sum(1 for w in withdrawals if w.get("status") in ("requested", "approved"))
        if pending != self._pending_count:
            self._pending_count = pending
            self.pendingCountChanged.emit()

        review = sum(1 for t in tasks if t.get("status") == "submitted")
        if review != self._review_count:
            self._review_count = review
            self.reviewCountChanged.emit()

    # ------------------------------------------------------------- locality backfill

    def _schedule_locality_backfill(self) -> None:
        """Resolve place names for points the phone left blank, once each, and
        write them back so every client sees the name from the DB."""
        if self._geocode_task is not None and not self._geocode_task.done():
            return  # one pass at a time
        # One representative empty point per rounded coordinate (dedupe).
        seen: set[str] = set()
        todo: list[dict] = []
        for loc in self._locations_raw:
            if (loc.get("locality") or "").strip():
                continue
            key = "%.4f,%.4f" % (float(loc["lat"]), float(loc["lng"]))
            if key in seen:
                continue
            seen.add(key)
            todo.append(loc)
        if not todo:
            return

        async def _run() -> None:
            try:
                for loc in todo[:8]:  # a few per cycle; the cache covers repeats
                    name = await self.geocode.resolve(float(loc["lat"]), float(loc["lng"]))
                    if not name:
                        continue
                    try:
                        await self.supabase.set_location_place(int(loc["id"]), name)
                    except Exception:  # noqa: BLE001
                        log.debug("set_location_place failed", exc_info=True)
                        continue
                    # Reflect it locally so the sidebar/header update without a
                    # round-trip; the next refresh reads the same value from DB.
                    changed = False
                    for row in self._locations_raw:
                        if not (row.get("locality") or "").strip() and "%.4f,%.4f" % (
                            float(row["lat"]),
                            float(row["lng"]),
                        ) == "%.4f,%.4f" % (float(loc["lat"]), float(loc["lng"])):
                            row["locality"] = name
                            changed = True
                    if changed:
                        await self._rebuild_children(self._children_raw, self._tasks_raw)
            except asyncio.CancelledError:
                pass
            except Exception:  # noqa: BLE001
                log.exception("locality backfill failed")

        self._geocode_task = asyncio.create_task(_run())

    def _presence_tick(self) -> None:
        async def _run() -> None:
            try:
                children = await self.supabase.list_children()
                self._children_raw = children
                await self._rebuild_children(children, self._tasks_raw)
            except Exception:  # noqa: BLE001
                log.exception("presence tick failed")

        if self.supabase.connected:
            asyncio.create_task(_run())

    @staticmethod
    def _max_snapshot(stats: list[dict]) -> datetime | None:
        values = [parse_ts(s.get("snapshot_at")) for s in stats]
        values = [v for v in values if v is not None]
        return max(values) if values else None

    async def _signed(self, bucket: str, path: str | None) -> str:
        if not path:
            return ""
        cache_key = f"{bucket}/{path}"
        if cache_key in self._signed_url_cache:
            return self._signed_url_cache[cache_key]
        try:
            url = await self.supabase.signed_url(bucket, path)
        except Exception:  # noqa: BLE001
            log.exception("signed url failed")
            url = ""
        self._signed_url_cache[cache_key] = url
        return url

    # ------------------------------------------------------------- balance math
    #
    # balance(child) = sum(ledger) + live job tail (earned_total - credited).
    # Mirrors public.assignee_balance(); the server stays the source of truth.

    def _ledger_sum(self, child_id: str) -> int:
        return sum(
            int(e.get("amount") or 0) for e in self._ledger_raw if e.get("child_id") == child_id
        )

    def _job_tail(self, child_id: str, extra_seconds: float = 0.0) -> int:
        """Uncredited whole acorns, optionally advanced by extra_seconds (live tick).

        The tick works off accrued_acorn_seconds — the server's exact, un-rounded
        accumulator — so a ticking balance shows exactly what the next settlement
        will credit, and never jumps when the settle cron lands.
        """
        tail = 0
        for s in self._stats_raw:
            if s["child_id"] != child_id:
                continue
            ticking = extra_seconds if s.get("running_since") else 0.0
            earned = live_acorns(
                int(s.get("accrued_acorn_seconds") or 0),
                ticking,
                int(s.get("hourly_rate") or 0),
            )
            # Non-negative by construction (credited_amount is floor(accrued/3600)
            # at the last settlement, and accrued only grows), so a negative value
            # means the snapshot and the ledger disagree — clamp rather than
            # quietly subtracting it from the balance.
            tail += max(0, earned - int(s.get("credited_amount") or 0))
        return tail

    def _live_balance(self, child_id: str, extra_seconds: float = 0.0) -> int:
        return self._ledger_sum(child_id) + self._job_tail(child_id, extra_seconds)

    def _earned_window(self, child_id: str, days: int) -> int:
        """Positive earnings (task/job/bonus/positive adjustment) in the last N days."""
        cutoff = self.supabase.time.now_server() - timedelta(days=days)
        total = 0
        for e in self._ledger_raw:
            if e.get("child_id") != child_id:
                continue
            if e.get("kind") not in ("task", "job", "bonus", "adjustment"):
                continue
            amount = int(e.get("amount") or 0)
            if amount <= 0:
                continue
            when = parse_ts(e.get("created_at"))
            if when is not None and when >= cutoff:
                total += amount
        return total

    async def _rebuild_children(self, children: list[dict], tasks: list[dict]) -> None:
        now_server = self.supabase.time.now_server()
        # Children that have at least one registered push device are reachable
        # (a notification will arrive even when the app is closed).
        reachable_ids = {d["profile_id"] for d in self._devices_raw}
        # Best (highest versionCode) device per child for the version badge.
        best_device: dict[str, dict] = {}
        for d in self._devices_raw:
            cur = best_device.get(d["profile_id"])
            if cur is None or int(d.get("app_version_code") or 0) >= int(
                cur.get("app_version_code") or 0
            ):
                best_device[d["profile_id"]] = d
        rows = []
        for child in children:
            child_tasks = [t for t in tasks if t["child_id"] == child["id"]]
            done = [t for t in child_tasks if t["status"] == "done"]
            active_tasks = [
                t for t in child_tasks if t["status"] in ("new", "in_progress", "paused")
            ]
            in_progress = [t for t in child_tasks if t["status"] == "in_progress"]
            balance = self._live_balance(child["id"])
            last_seen = parse_ts(child.get("last_seen_at"))
            active = last_seen is not None and (now_server - last_seen) < PRESENCE_ONLINE_WINDOW
            if active:
                presence = "active"
            elif child["id"] in reachable_ids:
                presence = "reachable"
            else:
                presence = "offline"

            device = best_device.get(child["id"])
            version_name = (device or {}).get("app_version")
            version_code = int((device or {}).get("app_version_code") or 0)
            app_version = f"v{version_name}" if version_name else ""
            version_outdated = bool(version_name) and version_code < self._latest_android_code

            # Latest reported location (list arrives newest-first).
            loc = next((p for p in self._locations_raw if p["child_id"] == child["id"]), None)
            location_stale = False
            if loc:
                place = loc.get("locality") or "%.5f, %.5f" % (loc["lat"], loc["lng"])
                loc_when = parse_ts(loc.get("created_at"))
                location_text = "%s · %s" % (place, fmt_datetime_local(loc_when))
                # No fresh point for over 30 minutes -> flag it in the UI.
                location_stale = (
                    loc_when is not None and (now_server - loc_when) > LOCATION_STALE_WINDOW
                )
            else:
                location_text = ""
            rows.append(
                {
                    "childId": child["id"],
                    "username": child["username"],
                    "displayName": child["display_name"],
                    "color": child.get("avatar_color") or "#CDB1B1",
                    "activeCount": len(active_tasks),
                    "doneCount": len(done),
                    "balance": balance,
                    "balanceText": fmt_acorns(balance),
                    "presence": presence,
                    "currentTask": in_progress[0]["title"] if in_progress else "",
                    "blocked": bool(child.get("blocked")),
                    "lastSeenText": fmt_datetime_local(last_seen),
                    "appVersion": app_version,
                    "versionOutdated": version_outdated,
                    "locationText": location_text,
                    "hasLocation": loc is not None,
                    "locationStale": location_stale,
                    "avatarUrl": self.storage.avatar_url(child),
                }
            )
        self._childrenModel.set_rows(rows)

    async def _rebuild_tasks(self, tasks: list[dict]) -> None:
        # Active tasks with a deadline float to the top by soonest deadline;
        # everything else keeps the server's newest-first order.
        def sort_key(t: dict):
            active = t.get("status") in ("new", "in_progress", "paused", "submitted")
            dl = parse_ts(t.get("deadline_at"))
            has_dl = active and dl is not None
            return (0 if has_dl else 1, dl.timestamp() if has_dl else 0)

        tasks = sorted(tasks, key=sort_key)

        # Attachment galleries per task: [{attId, url, thumbUrl}], newest last.
        atts_by_task: dict[tuple[str, str], list[dict]] = {}
        for a in self._attachments_raw:
            entry = {
                "attId": a["id"],
                "url": await self.storage.attachment_url(a, thumb=False),
                "thumbUrl": await self.storage.attachment_url(a, thumb=True),
            }
            atts_by_task.setdefault((a["task_id"], a["role"]), []).append(entry)

        rows = []
        for t in tasks:
            profile = t.get("profiles") or {}
            created = parse_ts(t.get("created_at"))
            deadline_dt = parse_ts(t.get("deadline_at"))
            deadline_text, deadline_state = fmt_deadline(deadline_dt)
            reward = int(t.get("reward_amount") or 0)
            reward_text = fmt_acorns(reward)
            earned = t.get("earned_amount")
            rows.append(
                {
                    "taskId": t["id"],
                    "childId": t["child_id"],
                    "childName": profile.get("display_name") or "",
                    "childColor": profile.get("avatar_color") or "#CDB1B1",
                    "title": t["title"],
                    "description": t.get("description") or "",
                    "photoUrl": await self._signed(TASK_PHOTOS_BUCKET, t.get("photo_path")),
                    "rewardType": t["reward_type"],
                    "rewardAmount": reward,
                    "rewardText": reward_text,
                    "difficulty": int(t.get("difficulty") or 1),
                    "diffColor": DIFFICULTY_COLORS.get(int(t.get("difficulty") or 1), "#CDB1B1"),
                    "requirements": t.get("requirements") or "",
                    "proofText": t.get("proof_text") or "none",
                    "proofPhoto": t.get("proof_photo") or "none",
                    "status": t["status"],
                    "proofTextContent": t.get("proof_text_content") or "",
                    "proofPhotoUrl": await self._signed(
                        PROOF_PHOTOS_BUCKET, t.get("proof_photo_path")
                    ),
                    "totalText": fmt_duration(int(t.get("total_seconds") or 0)),
                    "earnedAmount": int(earned) if earned is not None else 0,
                    "earnedText": fmt_acorns(int(earned)) if earned is not None else "",
                    "createdAtText": fmt_datetime_local(created),
                    "dateSection": fmt_date_local(created),
                    "completedAtText": fmt_datetime_local(parse_ts(t.get("completed_at"))),
                    "declineReason": t.get("decline_reason") or "",
                    "completionMode": t.get("completion_mode") or "timer",
                    "createdBy": t.get("created_by_name") or "",
                    "createdById": t.get("created_by") or "",
                    "deadlineText": deadline_text,
                    "deadlineState": deadline_state,
                    "deadlineIso": t.get("deadline_at") or "",
                    "childAvatarUrl": self.storage.avatar_url(profile),
                    "photosVar": atts_by_task.get((t["id"], "task"), []),
                    "proofsVar": atts_by_task.get((t["id"], "proof"), []),
                }
            )
        self._tasksModel.set_rows(rows)

    def _rebuild_jobs(self) -> None:
        children_by_id = {c["id"]: c for c in self._children_raw}
        rows = []
        for job in self._jobs_raw:
            stats = [s for s in self._stats_raw if s["job_id"] == job["id"]]
            members = []
            for s in stats:
                child = children_by_id.get(s["child_id"], {})
                earned = int(s.get("earned_total") or 0)
                members.append(
                    {
                        "childId": s["child_id"],
                        "name": child.get("display_name") or "",
                        "color": child.get("avatar_color") or "#CDB1B1",
                        "avatarUrl": self.storage.avatar_url(child),
                        "earnedSeconds": int(s.get("earned_seconds") or 0),
                        # Earned on THIS job (flows to the personal balance).
                        "earned": earned,
                        "earnedText": fmt_acorns(earned),
                    }
                )
            total = max((int(s.get("total_seconds") or 0) for s in stats), default=0)
            rows.append(
                {
                    "jobId": job["id"],
                    "title": job["title"],
                    "description": job.get("description") or "",
                    "rate": int(job["hourly_rate"]),
                    "rateText": fmt_acorns(int(job["hourly_rate"])),
                    "status": job["status"],
                    "running": job["status"] == "running",
                    "totalText": fmt_duration(total),
                    "membersVar": members,
                }
            )
        self._jobsModel.set_rows(rows)

    def _rebuild_attention(self, withdrawals: list[dict]) -> None:
        """Payouts waiting for the owner: requested (approve/reject) or approved (pay)."""
        rows = []
        for w in withdrawals:
            if w.get("status") not in ("requested", "approved"):
                continue
            profile = w.get("profiles") or {}
            rows.append(
                {
                    "wId": w["id"],
                    "childId": w.get("child_id") or "",
                    "childName": profile.get("display_name") or "",
                    "childColor": profile.get("avatar_color") or "#CDB1B1",
                    "childAvatarUrl": self.storage.avatar_url(profile),
                    "amount": int(w["amount"]),
                    "amountText": fmt_acorns(int(w["amount"])),
                    "status": w["status"],
                    "method": w.get("method") or "",
                    "requestedAtText": fmt_datetime_local(parse_ts(w.get("requested_at"))),
                }
            )
        self._attentionModel.set_rows(rows)

    def _rebuild_balances(self) -> None:
        rows = []
        for child in self._children_raw:
            cid = child["id"]
            rows.append(
                {
                    "childId": cid,
                    "name": child.get("display_name") or "",
                    "color": child.get("avatar_color") or "#CDB1B1",
                    "avatarUrl": self.storage.avatar_url(child),
                    "balance": self._live_balance(cid),
                    "balanceText": fmt_acorns(self._live_balance(cid)),
                    "weekText": fmt_acorns_words(
                        self._earned_window(cid, 7), self.settings.language
                    ),
                    "monthText": fmt_acorns_words(
                        self._earned_window(cid, 30), self.settings.language
                    ),
                    "blocked": bool(child.get("blocked")),
                }
            )
        rows.sort(key=lambda r: r["balance"], reverse=True)
        self._balancesModel.set_rows(rows)

    # Human labels for a ledger entry's kind.
    LEDGER_LABELS = {
        "task": "Завдання",
        "job": "Робота",
        "bonus": "Бонус",
        "adjustment": "Коригування",
        "withdrawal": "Вивід",
        "reversal": "Повернення",
    }

    def _rebuild_ledger(self) -> None:
        """The ledger feed; when an assignee is selected, only their entries."""
        rows = []
        for e in self._ledger_raw:
            cid = e.get("child_id") or ""
            if self._ledger_child and cid != self._ledger_child:
                continue
            profile = e.get("profiles") or {}
            amount = float(e.get("amount") or 0)
            when = parse_ts(e.get("created_at"))
            rows.append(
                {
                    "entryId": int(e["id"]),
                    "childId": cid,
                    "childName": profile.get("display_name") or "",
                    "kind": e.get("kind") or "",
                    "amount": amount,
                    "amountText": ("+" if amount >= 0 else "") + fmt_acorns(amount),
                    "positive": amount >= 0,
                    "note": e.get("note") or "",
                    "title": self.LEDGER_LABELS.get(e.get("kind") or "", e.get("kind") or ""),
                    "timeText": fmt_datetime_local(when),
                    "dateText": fmt_date_local(when),
                    "actorName": e.get("actor_name") or "",
                    # Lets a transaction open the story of whatever produced it.
                    "sourceEntity": (
                        e.get("source_type") or ""
                        if (e.get("source_type") or "") in ("task", "job", "withdrawal", "bonus")
                        else ""
                    ),
                    "sourceId": e.get("source_id") or "",
                }
            )
        self._ledgerModel.set_rows(rows)

    @Slot(str)
    def selectLedgerChild(self, child_id: str) -> None:  # noqa: N802
        self._ledger_child = child_id or ""
        self._rebuild_ledger()

    @asyncSlot(str, str, str, str)
    async def setWithdrawalFilter(  # noqa: N802
        self, child_id: str, status: str, method: str, period: str
    ) -> None:
        self._withdrawal_filter = {
            "child": child_id,
            "status": status,
            "method": method,
            "period": period,
        }
        await self._rebuild_withdrawals()

    async def _rebuild_withdrawals(self) -> None:
        receipts_by_wd: dict[str, list[dict]] = {}
        for a in self._attachments_raw:
            if a.get("role") == "receipt" and a.get("withdrawal_id"):
                receipts_by_wd.setdefault(a["withdrawal_id"], []).append(a)
        f = self._withdrawal_filter
        cutoff: datetime | None = None
        if f["period"]:
            days = {"today": 1, "7d": 7, "30d": 30}.get(f["period"], 0)
            if days:
                now_local = datetime.now().astimezone()
                cutoff = (
                    now_local - timedelta(days=days)
                    if f["period"] != "today"
                    else now_local.replace(hour=0, minute=0, second=0, microsecond=0)
                )
        rows = []
        for w in self._withdrawals_raw:
            if f["child"] and (w.get("child_id") or "") != f["child"]:
                continue
            if f["status"] and (w.get("status") or "") != f["status"]:
                continue
            if f["method"] and (w.get("method") or "") != f["method"]:
                continue
            if cutoff is not None:
                when = parse_ts(w.get("requested_at"))
                if when is None or when < cutoff:
                    continue
            profile = w.get("profiles") or {}
            wid = w["id"]
            receipts = [
                {
                    "attId": a["id"],
                    "url": await self.storage.attachment_url(a, thumb=False),
                    "thumbUrl": await self.storage.attachment_url(a, thumb=True),
                }
                for a in receipts_by_wd.get(wid, [])
            ]
            rows.append(
                {
                    "wId": wid,
                    "childId": w.get("child_id") or "",
                    "childName": profile.get("display_name") or "",
                    "childColor": profile.get("avatar_color") or "#CDB1B1",
                    "childAvatarUrl": self.storage.avatar_url(profile),
                    "amount": int(w["amount"]),
                    "amountText": fmt_acorns(int(w["amount"])),
                    "status": w.get("status") or "",
                    "method": w.get("method") or "",
                    "comment": w.get("comment") or "",
                    "rejectReason": w.get("reject_reason") or "",
                    "requestedAtText": fmt_datetime_local(parse_ts(w.get("requested_at"))),
                    "approvedAtText": fmt_datetime_local(parse_ts(w.get("approved_at"))),
                    "paidAtText": fmt_datetime_local(parse_ts(w.get("paid_at"))),
                    "confirmedAtText": fmt_datetime_local(parse_ts(w.get("confirmed_at"))),
                    "receiptsVar": receipts,
                }
            )
        self._withdrawalsModel.set_rows(rows)

    def _rebuild_journal(self) -> None:
        """Filtered audit feed from public.events."""
        f = self._journal_filter
        children = {c["id"]: c for c in self._children_raw}
        query = f["query"].strip().lower()
        cutoff: datetime | None = None
        if f["period"]:
            days = {"today": 1, "7d": 7, "30d": 30}.get(f["period"], 0)
            if days:
                now_local = datetime.now().astimezone()
                cutoff = (
                    now_local - timedelta(days=days)
                    if f["period"] != "today"
                    else now_local.replace(hour=0, minute=0, second=0, microsecond=0)
                )

        rows = []
        for e in self._events_raw:
            if f["entity"] and e.get("entity") != f["entity"]:
                continue
            if f["child"] and (e.get("child_id") or "") != f["child"]:
                continue
            when = parse_ts(e.get("created_at"))
            if cutoff is not None and (when is None or when < cutoff):
                continue
            child = children.get(e.get("child_id") or "", {})
            details = e.get("details") or {}
            if isinstance(details, str):
                try:
                    details = json.loads(details)
                except ValueError:
                    details = {}
            amount = details.get("amount", details.get("earned"))
            note = details.get("note") or ""
            actor = e.get("actor_name") or ""
            if query:
                haystack = " ".join(
                    [
                        e.get("entity_title") or "",
                        actor,
                        child.get("display_name") or "",
                        note,
                    ]
                ).lower()
                if query not in haystack:
                    continue
            # Bonus events stay editable: pull the live bonus row if it exists.
            live_bonus = None
            if e.get("entity") == "bonus":
                live_bonus = next(
                    (b for b in self._bonuses_raw if b["id"] == e.get("entity_id")), None
                )
            rows.append(
                {
                    "eventId": int(e["id"]),
                    "action": e.get("action") or "",
                    "entity": e.get("entity") or "",
                    "actorName": actor,
                    "actorKind": e.get("actor_kind") or "system",
                    "entityTitle": e.get("entity_title") or "",
                    "childName": child.get("display_name") or "",
                    "childColor": child.get("avatar_color") or "#CDB1B1",
                    "childAvatarUrl": self.storage.avatar_url(child),
                    "amountText": fmt_acorns(float(amount)) if amount is not None else "",
                    "noteText": note,
                    "timeText": fmt_datetime_local(when),
                    "dateText": fmt_date_local(when),
                    "refId": e.get("entity_id") or "",
                    "isTask": e.get("entity") == "task" and e.get("action") != "deleted",
                    "bonusAlive": live_bonus is not None,
                    "bonusAmount": float(live_bonus["amount"]) if live_bonus else 0.0,
                    "bonusNote": (live_bonus.get("note") or "") if live_bonus else "",
                }
            )
        self._journalModel.set_rows(rows)

    @Slot(str, str, str, str)
    def setJournalFilter(self, entity: str, child_id: str, period: str, query: str) -> None:  # noqa: N802
        self._journal_filter = {
            "entity": entity,
            "child": child_id,
            "period": period,
            "query": query,
        }
        self._rebuild_journal()

    # ------------------------------------------------------------- live tick

    def _tick(self) -> None:
        if self._snapshot_local is None:
            return
        elapsed = (datetime.now().astimezone() - self._snapshot_local).total_seconds()
        running = any(row["running"] for row in self._jobsModel.rows)
        if not running:
            return

        # Jobs: earned per member and the shared timer keep ticking.
        for i, row in enumerate(self._jobsModel.rows):
            if not row["running"]:
                continue
            job_stats = [s for s in self._stats_raw if s["job_id"] == row["jobId"]]
            total = max((int(s.get("total_seconds") or 0) for s in job_stats), default=0)
            members = []
            for m, s in zip(row["membersVar"], job_stats):
                earned = live_acorns(int(s.get("accrued_acorn_seconds") or 0), elapsed, row["rate"])
                m = dict(m)
                m["earned"] = earned
                m["earnedText"] = fmt_acorns(earned)
                members.append(m)
            self._jobsModel.update_row(
                i, {"totalText": fmt_duration(total + int(elapsed)), "membersVar": members}
            )

        # Balances tick live too (ledger + growing job tail).
        for i, row in enumerate(self._childrenModel.rows):
            bal = self._live_balance(row["childId"], extra_seconds=elapsed)
            self._childrenModel.update_row(i, {"balance": bal, "balanceText": fmt_acorns(bal)})
        for i, row in enumerate(self._balancesModel.rows):
            bal = self._live_balance(row["childId"], extra_seconds=elapsed)
            self._balancesModel.update_row(i, {"balance": bal, "balanceText": fmt_acorns(bal)})

    # ------------------------------------------------------------- realtime

    def _on_change(self, table: str, event: str, record: dict, old: dict) -> None:
        # Runs on the asyncio loop thread (same as Qt loop under qasync).
        log.info(
            "realtime: %s %s status=%s->%s",
            table,
            event,
            (old or {}).get("status"),
            (record or {}).get("status"),
        )
        # Presence updates (last_seen) arrive as profile UPDATEs — do a light
        # rebuild instead of a full refresh so "online" reacts in real time.
        if table == "profiles":
            self._presence_tick()
            return
        if table == "withdrawals" and event == "INSERT" and record.get("status") == "requested":
            child = next((c for c in self._children_raw if c["id"] == record.get("child_id")), None)
            name = (child or {}).get("display_name") or self.tr("Assignee")
            amount = fmt_acorns_words(float(record.get("amount") or 0), self.settings.language)
            self.notifications.show_withdrawal_request(
                self.tr("Withdrawal request"),
                self.tr("%1 asks to withdraw %2").replace("%1", name).replace("%2", amount),
                str(record.get("id")),
                self.tr("Approve"),
                self.tr("Decline"),
            )
        if table == "tasks" and event == "UPDATE":
            new_status = record.get("status")
            if new_status == "submitted" and old.get("status") != "submitted":
                child = next(
                    (c for c in self._children_raw if c["id"] == record.get("child_id")), None
                )
                name = (child or {}).get("display_name") or self.tr("Assignee")
                self.notifications.show(
                    self.tr("Task to review"),
                    self.tr("%1 submitted the task “%2” for review")
                    .replace("%1", name)
                    .replace("%2", str(record.get("title"))),
                )
            elif new_status == "declined" and old.get("status") == "new":
                # Child declined a brand-new task.
                child = next(
                    (c for c in self._children_raw if c["id"] == record.get("child_id")), None
                )
                name = (child or {}).get("display_name") or self.tr("Assignee")
                self.notifications.show(
                    self.tr("Tasks"),
                    self.tr("%1 declined the task “%2”")
                    .replace("%1", name)
                    .replace("%2", str(record.get("title"))),
                )
        self._schedule_refresh()

    def _on_toast_action(self, arguments: str) -> None:
        action, _, withdrawal_id = arguments.partition(":")
        if not withdrawal_id:
            return
        if action == "approve":
            asyncio.create_task(
                self._run_withdrawal(
                    self.supabase.withdrawal_approve(withdrawal_id), self.tr("Withdrawal approved")
                )
            )
        elif action == "decline":
            asyncio.create_task(
                self._run_withdrawal(
                    self.supabase.withdrawal_reject(withdrawal_id, ""),
                    self.tr("Withdrawal declined"),
                    "info",
                )
            )

    # ------------------------------------------------------------- slots

    @staticmethod
    def _local_file(path: str) -> str:
        if path.startswith("file:"):
            return QUrl(path).toLocalFile()
        return path

    async def _apply_avatar(
        self, child_id: str, avatar_file: str, cx: float, cy: float, cs: float
    ) -> None:
        """Crop (source-pixel rect from the QML crop UI), optimize, upload."""
        path = self._local_file(avatar_file)
        crop = (cx, cy, cs, cs) if cs > 0 else None
        img = await asyncio.to_thread(image_service.optimize_avatar, path, crop)
        storage, obj_path = await self.storage.upload_avatar(child_id, img)
        await self.supabase.set_profile_avatar(child_id, storage, obj_path)

    @Slot(str, result="QVariantList")
    def imageSize(self, file_url: str) -> list:  # noqa: N802
        """Orientation-corrected source dimensions for the crop dialog."""
        try:
            w, h = image_service.image_size(self._local_file(file_url))
            return [w, h]
        except Exception:  # noqa: BLE001
            log.exception("imageSize")
            return [0, 0]

    @asyncSlot(str, str, str, str, str, float, float, float)
    async def createChild(  # noqa: N802
        self,
        username: str,
        display_name: str,
        password: str,
        color: str,
        avatar_file: str = "",
        crop_x: float = 0,
        crop_y: float = 0,
        crop_size: float = 0,
    ) -> None:
        try:
            await self.supabase.create_child(username, display_name, password, color)
            if avatar_file:
                children = await self.supabase.list_children()
                fresh = next(
                    (c for c in children if c["username"] == username.strip().lower()), None
                )
                if fresh:
                    await self._apply_avatar(fresh["id"], avatar_file, crop_x, crop_y, crop_size)
            self.toastRequested.emit(self.tr("Assignee account created"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("createChild")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str, str)
    async def setChildPassword(self, child_id: str, password: str) -> None:  # noqa: N802
        try:
            await self.supabase.set_child_password(child_id, password)
            self.toastRequested.emit(self.tr("Password updated"), "success")
        except Exception as exc:  # noqa: BLE001
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str, str, str, str, float, float, float, bool)
    async def updateChild(  # noqa: N802
        self,
        child_id: str,
        display_name: str,
        color: str,
        avatar_file: str = "",
        crop_x: float = 0,
        crop_y: float = 0,
        crop_size: float = 0,
        clear_avatar: bool = False,
    ) -> None:
        try:
            await self.supabase.update_child(child_id, display_name, color)
            if avatar_file:
                await self._apply_avatar(child_id, avatar_file, crop_x, crop_y, crop_size)
            elif clear_avatar:
                await self.supabase.set_profile_avatar(child_id, None, None)
            self.toastRequested.emit(self.tr("Assignee updated"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("updateChild")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str, bool)
    async def setChildBlocked(self, child_id: str, blocked: bool) -> None:  # noqa: N802
        try:
            await self.supabase.set_child_blocked(child_id, blocked)
            self.toastRequested.emit(
                self.tr("Assignee blocked") if blocked else self.tr("Assignee unblocked"),
                "info" if blocked else "success",
            )
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str)
    async def deleteChild(self, child_id: str) -> None:  # noqa: N802
        try:
            await self.supabase.delete_child(child_id)
            self.toastRequested.emit(self.tr("Assignee deleted"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("deleteChild")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str, float, str)
    async def giveBonus(self, child_id: str, amount: float, note: str) -> None:  # noqa: N802
        try:
            if amount <= 0:
                self.toastRequested.emit(self.tr("Enter an amount"), "error")
                return
            await self.supabase.create_bonus(child_id, amount, note)
            self.toastRequested.emit(self.tr("Bonus granted"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("giveBonus")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str, float, str)
    async def updateBonus(self, bonus_id: str, amount: float, note: str) -> None:  # noqa: N802
        try:
            if amount <= 0:
                self.toastRequested.emit(self.tr("Enter an amount"), "error")
                return
            await self.supabase.update_bonus(bonus_id, amount, note)
            self.toastRequested.emit(self.tr("Bonus updated"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("updateBonus")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str)
    async def deleteBonus(self, bonus_id: str) -> None:  # noqa: N802
        try:
            await self.supabase.delete_bonus(bonus_id)
            self.toastRequested.emit(self.tr("Bonus deleted"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot("QVariant")
    async def createTask(self, fields) -> None:  # noqa: N802
        try:
            data = dict(js_value(fields) or {})
            photo_files = [self._local_file(p) for p in (data.pop("photo_files", None) or [])]
            child_ids: list[str] = data.pop("child_ids")
            self._set_busy(True)

            optimized = [
                await asyncio.to_thread(image_service.optimize_photo, p) for p in photo_files
            ]
            # On Drive one shared upload serves every child; on Supabase each
            # child gets a copy in their read-scoped folder.
            shared_infos: list[dict | None] = [None] * len(optimized)
            if self.storage.backend == "drive" and optimized:
                for i, photo in enumerate(optimized):
                    info = await self.storage.upload_task_photo(child_ids[0], photo)
                    if info["storage"] == "drive":
                        shared_infos[i] = info

            for child_id in child_ids:
                row = dict(data)
                row["child_id"] = child_id
                task_id = await self.supabase.insert_task(row)
                for i, photo in enumerate(optimized):
                    info = shared_infos[i] or await self.storage.upload_task_photo(child_id, photo)
                    await self.supabase.insert_attachment(task_id, "task", info)

            self.toastRequested.emit(self.tr("Task created"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("createTask")
            self.toastRequested.emit(self._human_error(exc), "error")
        finally:
            self._set_busy(False)

    @asyncSlot(str)
    async def deleteTask(self, task_id: str) -> None:  # noqa: N802
        try:
            await self.supabase.delete_task(task_id)
            self.toastRequested.emit(self.tr("Task deleted"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str, str, str)
    async def reviewTask(self, task_id: str, action: str, note: str) -> None:  # noqa: N802
        try:
            await self.supabase.review_task(task_id, action, note)
            msg = {
                "approve": self.tr("Task accepted"),
                "reject": self.tr("Task rejected"),
                "rework": self.tr("Sent for rework"),
            }.get(action, self.tr("Done"))
            self.toastRequested.emit(msg, "success" if action == "approve" else "info")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("reviewTask")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str)
    async def duplicateTask(self, task_id: str) -> None:  # noqa: N802
        try:
            await self.supabase.duplicate_task(task_id)
            self.toastRequested.emit(self.tr("Task re-issued"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("duplicateTask")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str, "QVariant")
    async def updateTask(self, task_id: str, fields) -> None:  # noqa: N802
        try:
            data = dict(js_value(fields) or {})
            data.pop("child_ids", None)
            data.pop("photo_file", None)
            added = [self._local_file(p) for p in (data.pop("photo_files", None) or [])]
            removed_ids = list(data.pop("attachments_remove", None) or [])
            self._set_busy(True)
            await self.supabase.update_task(task_id, data)

            for att_id in removed_ids:
                att = next((a for a in self._attachments_raw if a["id"] == att_id), None)
                await self.supabase.delete_attachment_row(att_id)
                if att:
                    await self.storage.delete_attachment_files(att)

            if added:
                task = next((t for t in self._tasks_raw if t["id"] == task_id), None)
                child_id = (task or {}).get("child_id") or ""
                for p in added:
                    photo = await asyncio.to_thread(image_service.optimize_photo, p)
                    info = await self.storage.upload_task_photo(child_id, photo)
                    await self.supabase.insert_attachment(task_id, "task", info)

            self.toastRequested.emit(self.tr("Task updated"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("updateTask")
            self.toastRequested.emit(self._human_error(exc), "error")
        finally:
            self._set_busy(False)

    @asyncSlot(str, "QVariant", "QVariant")
    async def updateJob(self, job_id: str, fields, child_ids) -> None:  # noqa: N802
        try:
            data = dict(js_value(fields) or {})
            ids = list(js_value(child_ids) or [])
            if not ids:
                self.toastRequested.emit(self.tr("Choose at least one assignee"), "error")
                return
            await self.supabase.update_job(job_id, data, ids)
            self.toastRequested.emit(self.tr("Job updated"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("updateJob")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str)
    async def deleteJob(self, job_id: str) -> None:  # noqa: N802
        try:
            await self.supabase.delete_job(job_id)
            self.toastRequested.emit(self.tr("Job deleted"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot("QVariant", "QVariant")
    async def createJob(self, fields, child_ids) -> None:  # noqa: N802
        try:
            data = dict(js_value(fields) or {})
            ids = list(js_value(child_ids) or [])
            if not ids:
                self.toastRequested.emit(self.tr("Choose at least one assignee"), "error")
                return
            await self.supabase.create_job(data, ids)
            self.toastRequested.emit(self.tr("Job created"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("createJob")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str)
    async def jobStart(self, job_id: str) -> None:  # noqa: N802
        await self._job_action(self.supabase.job_start, job_id)

    @asyncSlot(str)
    async def jobStop(self, job_id: str) -> None:  # noqa: N802
        await self._job_action(self.supabase.job_stop, job_id)

    @asyncSlot(str)
    async def jobArchive(self, job_id: str) -> None:  # noqa: N802
        await self._job_action(self.supabase.job_archive, job_id)

    async def _job_action(self, fn, job_id: str) -> None:
        try:
            await fn(job_id)
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("job action")
            self.toastRequested.emit(self._human_error(exc), "error")

    # ------------------------------------------------------------- balance / payouts

    async def _run_withdrawal(self, coro, ok_message: str, kind: str = "success") -> None:
        try:
            await coro
            self.toastRequested.emit(ok_message, kind)
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("withdrawal action")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str, float, str)
    async def adjustBalance(self, child_id: str, amount: float, note: str) -> None:  # noqa: N802
        if amount == 0:
            self.toastRequested.emit(self.tr("Enter an amount"), "error")
            return
        if not note.strip():
            self.toastRequested.emit(self.tr("Add a comment"), "error")
            return
        await self._run_withdrawal(
            self.supabase.adjust_balance(child_id, amount, note), self.tr("Balance adjusted")
        )

    @asyncSlot(str)
    async def withdrawalApprove(self, withdrawal_id: str) -> None:  # noqa: N802
        await self._run_withdrawal(
            self.supabase.withdrawal_approve(withdrawal_id), self.tr("Withdrawal approved")
        )

    @asyncSlot(str, str)
    async def withdrawalReject(self, withdrawal_id: str, reason: str) -> None:  # noqa: N802
        await self._run_withdrawal(
            self.supabase.withdrawal_reject(withdrawal_id, reason),
            self.tr("Withdrawal declined"),
            "info",
        )

    @asyncSlot(str, str)
    async def withdrawalPayCash(self, withdrawal_id: str, comment: str) -> None:  # noqa: N802
        await self._run_withdrawal(
            self.supabase.withdrawal_pay(withdrawal_id, "cash", comment),
            self.tr("Marked as paid in cash — awaiting confirmation"),
            "info",
        )

    @asyncSlot(str, str, str)
    async def withdrawalPayCard(self, withdrawal_id: str, comment: str, receipt_file: str) -> None:  # noqa: N802
        try:
            self._set_busy(True)
            receipt = self._local_file(receipt_file) if receipt_file else ""
            if receipt:
                wd = next((w for w in self._withdrawals_raw if w["id"] == withdrawal_id), None)
                child_id = (wd or {}).get("child_id") or ""
                photo = await asyncio.to_thread(image_service.optimize_photo, receipt)
                info = await self.storage.upload_task_photo(child_id, photo)
                await self.supabase.attach_receipt(withdrawal_id, info)
            await self.supabase.withdrawal_pay(withdrawal_id, "card", comment)
            self.toastRequested.emit(self.tr("Paid to card"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("withdrawalPayCard")
            self.toastRequested.emit(self._human_error(exc), "error")
        finally:
            self._set_busy(False)

    @asyncSlot(str, float, str, str, str)
    async def payoutToChild(  # noqa: N802
        self,
        child_id: str,
        amount: float,
        method: str,
        comment: str,
        receipt_file: str,
    ) -> None:
        """Owner-initiated payout: create an approved withdrawal from the
        assignee's balance and pay it (card+receipt / cash+confirmation)."""
        try:
            self._set_busy(True)
            amt = None if amount <= 0 else amount  # 0 = whole balance
            wid = await self.supabase.create_withdrawal(child_id, amt)
            if method == "card":
                receipt = self._local_file(receipt_file) if receipt_file else ""
                if receipt:
                    photo = await asyncio.to_thread(image_service.optimize_photo, receipt)
                    info = await self.storage.upload_task_photo(child_id, photo)
                    await self.supabase.attach_receipt(wid, info)
            await self.supabase.withdrawal_pay(wid, method, comment)
            self.toastRequested.emit(
                self.tr("Paid to card")
                if method == "card"
                else self.tr("Marked as paid in cash — awaiting confirmation"),
                "success" if method == "card" else "info",
            )
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("payoutToChild")
            self.toastRequested.emit(self._human_error(exc), "error")
        finally:
            self._set_busy(False)

    # ------------------------------------------------------------- balance settings

    balanceSettingsChanged = Signal()

    def _get_min_withdrawal(self) -> float:
        return self._balance_settings["min_withdrawal"]

    def _get_withdrawals_enabled(self) -> bool:
        return self._balance_settings["withdrawals_enabled"]

    def _get_auto_approve_below(self) -> float:
        return self._balance_settings["auto_approve_below"]

    def _get_require_receipt(self) -> bool:
        return self._balance_settings["require_receipt_for_card"]

    minWithdrawal = Property(float, _get_min_withdrawal, notify=balanceSettingsChanged)
    withdrawalsEnabled = Property(bool, _get_withdrawals_enabled, notify=balanceSettingsChanged)
    autoApproveBelow = Property(float, _get_auto_approve_below, notify=balanceSettingsChanged)
    requireReceiptForCard = Property(bool, _get_require_receipt, notify=balanceSettingsChanged)

    @asyncSlot(float, bool, float, bool)
    async def setBalanceSettings(  # noqa: N802
        self,
        min_withdrawal: float,
        withdrawals_enabled: bool,
        auto_approve_below: float,
        require_receipt_for_card: bool,
    ) -> None:
        try:
            await self.supabase.set_balance_settings(
                min_withdrawal, withdrawals_enabled, auto_approve_below, require_receipt_for_card
            )
            self._balance_settings = {
                "min_withdrawal": min_withdrawal,
                "withdrawals_enabled": withdrawals_enabled,
                "auto_approve_below": auto_approve_below,
                "require_receipt_for_card": require_receipt_for_card,
            }
            self.balanceSettingsChanged.emit()
            self.toastRequested.emit(self.tr("Balance settings saved"), "success")
        except Exception as exc:  # noqa: BLE001
            log.exception("setBalanceSettings")
            self.toastRequested.emit(self._human_error(exc), "error")

    # ------------------------------------------------------------- timeline

    timelineReady = Signal("QVariant", str, str)  # steps, entity label, subtitle

    def _timeline_detail(self, row: dict) -> str:
        """One readable line under a step: who did it, plus what it carried."""
        details = row.get("details") or {}
        bits: list[str] = []
        if row.get("actor_kind") == "system":
            bits.append(self.tr("System"))
        elif row.get("actor_name"):
            bits.append(row["actor_name"])

        amount = details.get("amount", details.get("earned"))
        if amount is not None:
            bits.append(fmt_acorns_words(float(amount), self.settings.language))
        method = details.get("method")
        if method:
            bits.append(self.tr("to card") if method == "card" else self.tr("cash"))
        if details.get("note"):
            bits.append(f"«{details['note']}»")
        reason = details.get("reason")
        if reason:
            human = {
                "not_received": self.tr("not received"),
                "cancelled": self.tr("cancelled by the assignee"),
            }.get(reason, reason)
            bits.append(f"«{human}»")
        if details.get("old_name"):
            bits.append(self.tr("was: %1").replace("%1", str(details["old_name"])))
        return " · ".join(bits)

    @asyncSlot(str, str, str)
    async def openTimeline(self, entity: str, entity_id: str, subtitle: str) -> None:  # noqa: N802
        """Fetch one entity's full story and hand it to the dialog."""
        try:
            rows = await self.supabase.entity_timeline(entity, entity_id)
        except Exception as exc:  # noqa: BLE001
            log.exception("openTimeline")
            self.toastRequested.emit(self._human_error(exc), "error")
            return
        steps = [
            {
                "action": r.get("action") or "",
                "timeText": fmt_datetime_local(parse_ts(r.get("created_at"))),
                "detailText": self._timeline_detail(r),
                "title": r.get("entity_title") or "",
            }
            for r in rows
        ]
        title = steps[-1]["title"] if steps else ""
        sub = " — ".join(x for x in (title, subtitle) if x)
        self.timelineReady.emit(steps, entity, sub)

    # ------------------------------------------------------------- maintenance

    def _maintenance_cutoff(self, days: int) -> str | None:
        """0 = clear everything; N = keep the last N days."""
        if days <= 0:
            return None
        from datetime import timedelta

        return (self.supabase.time.now_server() - timedelta(days=days)).isoformat()

    @asyncSlot(int)
    async def clearJournal(self, keep_days: int) -> None:  # noqa: N802
        try:
            removed = await self.supabase.clear_journal(self._maintenance_cutoff(keep_days))
            self.toastRequested.emit(
                self.tr("Journal cleared (%1 entries)").replace("%1", str(removed)), "success"
            )
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("clearJournal")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(int)
    async def clearLocations(self, keep_days: int) -> None:  # noqa: N802
        try:
            removed = await self.supabase.clear_locations(self._maintenance_cutoff(keep_days))
            self.toastRequested.emit(
                self.tr("Location history cleared (%1 points)").replace("%1", str(removed)),
                "success",
            )
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            log.exception("clearLocations")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot()
    async def clearDeliveredQueue(self) -> None:  # noqa: N802
        try:
            removed = await self.supabase.clear_delivered_queue()
            self.toastRequested.emit(
                self.tr("Delivered notifications cleared (%1)").replace("%1", str(removed)),
                "success",
            )
        except Exception as exc:  # noqa: BLE001
            log.exception("clearDeliveredQueue")
            self.toastRequested.emit(self._human_error(exc), "error")

    @Slot(str)
    def setLanguage(self, language: str) -> None:  # noqa: N802
        if language not in SUPPORTED_LANGUAGES or language == self.settings.language:
            return
        self.settings.language = language
        self.settings.save()
        self.languageChanged.emit()
        from kabanchiki_admin.i18n import apply_language

        apply_language(language, self._engine)

    @Slot(result=str)
    def appVersion(self) -> str:  # noqa: N802
        from kabanchiki_admin import __version__

        return __version__

    def _get_supabase_url(self) -> str:
        return self.supabase.supabase_url

    supabaseUrl = Property(str, _get_supabase_url, notify=configuredChanged)

    parentEmailChanged = Signal()

    def _get_parent_email(self) -> str:
        return self._parent_email

    parentEmail = Property(str, _get_parent_email, notify=parentEmailChanged)

    def _get_owners(self) -> list:
        return self._owners

    ownersChanged = Signal()
    owners = Property("QVariantList", _get_owners, notify=ownersChanged)

    # ------------------------------------------------------------- telegram

    telegramChanged = Signal()
    telegramLinkReady = Signal(str, str)  # code, deep link

    def _get_is_owner(self) -> bool:
        return self._is_owner

    def _get_tg_bot(self) -> str:
        return self._telegram["bot_username"]

    def _get_tg_url(self) -> str:
        return self._telegram["miniapp_url"]

    def _get_tg_linked(self) -> bool:
        return self._telegram["linked"]

    def _get_tg_bot_configured(self) -> bool:
        return self._telegram["bot_configured"]

    isOwner = Property(bool, _get_is_owner, notify=telegramChanged)
    telegramBotUsername = Property(str, _get_tg_bot, notify=telegramChanged)
    telegramMiniappUrl = Property(str, _get_tg_url, notify=telegramChanged)
    telegramLinked = Property(bool, _get_tg_linked, notify=telegramChanged)
    telegramBotConfigured = Property(bool, _get_tg_bot_configured, notify=telegramChanged)

    @asyncSlot()
    async def clearBotToken(self) -> None:  # noqa: N802
        try:
            await self.supabase.set_bot_token("")
            self._telegram["bot_configured"] = False
            self.telegramChanged.emit()
            self.toastRequested.emit(self.tr("Bot token removed"), "info")
        except Exception as exc:  # noqa: BLE001
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str, str, str)
    async def saveTelegramSettings(self, bot_username: str, miniapp_url: str, token: str) -> None:  # noqa: N802
        """One save for the whole Telegram section; the token only when provided."""
        # Accept "@name", "name" or a full t.me link — store the bare username.
        name = bot_username.strip().lstrip("@")
        for prefix in ("https://t.me/", "http://t.me/", "t.me/"):
            if name.lower().startswith(prefix):
                name = name[len(prefix) :]
        name = name.split("/")[0].split("?")[0]
        try:
            await self.supabase.set_app_config(name, miniapp_url.strip())
            if token.strip():
                await self.supabase.set_bot_token(token.strip())
                self._telegram["bot_configured"] = True
            self._telegram["bot_username"] = name
            self._telegram["miniapp_url"] = miniapp_url.strip()
            self.telegramChanged.emit()
            self.toastRequested.emit(self.tr("Telegram settings saved"), "success")
        except Exception as exc:  # noqa: BLE001
            log.exception("saveTelegramSettings")
            self.toastRequested.emit(self._human_error(exc), "error")
            return
        # Keep the bot's webhook current so notification buttons keep working.
        if self._telegram["bot_configured"]:
            try:
                await self.supabase.register_tg_webhook()
                self.toastRequested.emit(self.tr("Bot notifications connected"), "success")
            except Exception as exc:  # noqa: BLE001
                log.exception("register_tg_webhook")
                self.toastRequested.emit(
                    self.tr("Settings saved, but bot notifications failed: %1").replace(
                        "%1", self._human_error(exc)
                    ),
                    "error",
                )

    @asyncSlot()
    async def startTelegramLink(self) -> None:  # noqa: N802
        bot = self._telegram["bot_username"]
        if not bot:
            self.toastRequested.emit(self.tr("Set the bot username first"), "error")
            return
        try:
            code = await self.supabase.start_telegram_link()
            deep_link = "https://t.me/%s?startapp=%s" % (bot, code)
            self.telegramLinkReady.emit(code, deep_link)
        except Exception as exc:  # noqa: BLE001
            log.exception("startTelegramLink")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot()
    async def unlinkTelegram(self) -> None:  # noqa: N802
        try:
            await self.supabase.unlink_telegram()
            self._telegram["linked"] = False
            self.telegramChanged.emit()
            self.toastRequested.emit(self.tr("Telegram unlinked"), "success")
            await self.refresh_all()
        except Exception as exc:  # noqa: BLE001
            self.toastRequested.emit(self._human_error(exc), "error")

    # ------------------------------------------------------------- google drive

    gdriveChanged = Signal()

    def _get_gdrive_connected(self) -> bool:
        return bool(self._gdrive.get("connected"))

    def _get_gdrive_email(self) -> str:
        return self._gdrive.get("email") or ""

    def _get_gdrive_client_id(self) -> str:
        return self._gdrive.get("client_id") or ""

    def _get_storage_backend(self) -> str:
        return self.storage.backend

    gdriveConnected = Property(bool, _get_gdrive_connected, notify=gdriveChanged)
    gdriveEmail = Property(str, _get_gdrive_email, notify=gdriveChanged)
    gdriveClientId = Property(str, _get_gdrive_client_id, notify=gdriveChanged)
    storageBackend = Property(str, _get_storage_backend, notify=gdriveChanged)

    @asyncSlot(str, str)
    async def connectGdrive(self, client_id: str, client_secret: str) -> None:  # noqa: N802
        """Save credentials, run the browser OAuth flow, push the refresh token."""
        client_id = client_id.strip()
        client_secret = client_secret.strip()
        if not client_secret:
            # Reconnecting: reuse the stored secret for the same client id.
            stored = gdrive_service.load_tokens()
            if stored and stored.client_id == client_id:
                client_secret = stored.client_secret
        if not client_id or not client_secret:
            self.toastRequested.emit(self.tr("Enter the Client ID and Client Secret"), "error")
            return
        self._set_busy(True)
        try:
            await self.supabase.set_gdrive_credentials(client_id, client_secret)
            self.toastRequested.emit(self.tr("Waiting for Google sign-in in the browser…"), "info")
            tokens = await gdrive_service.oauth_connect(client_id, client_secret)
            await self.supabase.set_gdrive_tokens(tokens.refresh_token, tokens.email)
            self.storage.reset_drive()
            self._gdrive = await self.supabase.gdrive_status()
            self.storage.shared_folders = self._gdrive.get("folders") or {}
            self.gdriveChanged.emit()
            self.toastRequested.emit(
                self.tr("Google Drive connected: %1").replace("%1", tokens.email), "success"
            )
        except Exception as exc:  # noqa: BLE001
            log.exception("connectGdrive")
            self.toastRequested.emit(self._human_error(exc), "error")
        finally:
            self._set_busy(False)

    @asyncSlot()
    async def disconnectGdrive(self) -> None:  # noqa: N802
        try:
            await self.supabase.gdrive_disconnect()
            gdrive_service.clear_tokens()
            self.storage.reset_drive()
            self.storage.backend = "supabase"
            self._gdrive = await self.supabase.gdrive_status()
            self.gdriveChanged.emit()
            self.toastRequested.emit(self.tr("Google Drive disconnected"), "info")
        except Exception as exc:  # noqa: BLE001
            log.exception("disconnectGdrive")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot()
    async def testGdrive(self) -> None:  # noqa: N802
        try:
            drive = self.storage.drive()
            if drive is None:
                self.toastRequested.emit(self.tr("Google Drive is not connected"), "error")
                return
            info = await drive.status()
            used = info["usage"] / (1024**3)
            total = info["limit"] / (1024**3) if info["limit"] else 0
            quota = (" · %.1f / %.0f GB" % (used, total)) if total else ""
            self.toastRequested.emit(
                self.tr("Google Drive works: %1").replace("%1", info["email"]) + quota, "success"
            )
        except Exception as exc:  # noqa: BLE001
            log.exception("testGdrive")
            self.toastRequested.emit(self._human_error(exc), "error")

    @asyncSlot(str)
    async def setStorageBackend(self, backend: str) -> None:  # noqa: N802
        try:
            if backend == "drive" and not self._gdrive.get("connected"):
                self.toastRequested.emit(self.tr("Connect Google Drive first"), "error")
                self.gdriveChanged.emit()
                return
            await self.supabase.set_storage_backend(backend)
            self.storage.backend = backend
            self.gdriveChanged.emit()
            self.toastRequested.emit(
                self.tr("New photos now go to Google Drive")
                if backend == "drive"
                else self.tr("New photos now go to Supabase"),
                "success",
            )
        except Exception as exc:  # noqa: BLE001
            log.exception("setStorageBackend")
            self.toastRequested.emit(self._human_error(exc), "error")
            self.gdriveChanged.emit()

    @Slot(str)
    def copyToClipboard(self, text: str) -> None:  # noqa: N802
        QApplication.clipboard().setText(text)
        self.toastRequested.emit(self.tr("Copied"), "info")

    @Slot(result=int)
    def latestAndroidVersionCode(self) -> int:  # noqa: N802
        return self._latest_android_code

    @asyncSlot("QVariant")
    async def publishUpdate(self, fields) -> None:  # noqa: N802
        try:
            data = dict(js_value(fields) or {})
            apk_file = data.get("apk_file", "")
            if apk_file.startswith("file:///"):
                apk_file = QUrl(apk_file).toLocalFile()
            version_name = str(data.get("version_name", "")).strip()
            version_code = int(data.get("version_code") or 0)
            if not apk_file or not version_name or version_code <= 0:
                self.toastRequested.emit(self.tr("Fill in the APK, version and code"), "error")
                return
            self._set_busy(True)
            await self.supabase.publish_release(
                apk_file,
                version_name,
                version_code,
                str(data.get("notes", "")),
                bool(data.get("mandatory", False)),
            )
            self.toastRequested.emit(self.tr("Update published"), "success")
        except Exception as exc:  # noqa: BLE001
            log.exception("publishUpdate")
            self.toastRequested.emit(self._human_error(exc), "error")
        finally:
            self._set_busy(False)

    @Slot()
    def openDataFolder(self) -> None:  # noqa: N802
        import subprocess

        from kabanchiki_admin.config import app_data_dir

        subprocess.Popen(["explorer", str(app_data_dir())])

    # ------------------------------------------------------------- helpers

    def _human_error(self, exc: Exception) -> str:
        text = str(exc)
        known = {
            "WITHDRAWAL_PENDING": self.tr("There is already a pending withdrawal"),
            "BELOW_MINIMUM": self.tr("Amount is below the minimum"),
            "ABOVE_BALANCE": self.tr("Amount exceeds the available balance"),
            "WITHDRAWALS_DISABLED": self.tr("Withdrawals are disabled"),
            "RECEIPT_REQUIRED": self.tr("Attach a receipt first"),
            "NOTE_REQUIRED": self.tr("A comment is required"),
            "INVALID_AMOUNT": self.tr("Enter a valid amount"),
            "INVALID_METHOD": self.tr("Choose a payout method"),
            "ALREADY_DECIDED": self.tr("Already decided"),
            "INVALID_STATUS": self.tr("Action is not allowed in the current status"),
            "last active owner": self.tr("The family must keep at least one active owner"),
            "cannot disable yourself": self.tr("You cannot disable your own account"),
            "cannot delete yourself": self.tr("You cannot delete your own account"),
            "owner only": self.tr("Only an owner can do this"),
            "NOT_OWNER": self.tr("Only an owner can do this"),
            # Connection wizard: classified codes from check_connection().
            "SCHEMA_MISSING": self.tr(
                "Connected, but the Kabanchiki schema is missing. Deploy the database first."
            ),
            "NO_HOST": self.tr("Could not reach that address. Check the Supabase URL."),
            "BAD_ANON_KEY": self.tr("The anon key is not valid for this project."),
        }
        for key, message in known.items():
            if key in text:
                return message
        if isinstance(exc, SupabaseError):
            return text
        return self.tr("Error: %1").replace("%1", text)
