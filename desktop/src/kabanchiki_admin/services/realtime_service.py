"""Realtime subscriptions: postgres changes -> Qt-friendly callbacks.

The parent app listens to every table it renders. A single callback receives
(table, event_type, record, old_record); the backend debounces refreshes and
raises toasts. A watchdog resubscribes with backoff if the channel dies and a
periodic full refresh acts as the safety net.
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Callable

from supabase import AsyncClient

log = logging.getLogger(__name__)

TABLES = ("tasks", "jobs", "job_members", "job_sessions", "withdrawals", "bonuses", "profiles")

ChangeCallback = Callable[[str, str, dict, dict], None]


class RealtimeService:
    def __init__(self) -> None:
        self._client: AsyncClient | None = None
        self._callback: ChangeCallback | None = None
        self._channel = None
        self._watchdog: asyncio.Task | None = None
        self._alive = False

    async def start(self, client: AsyncClient, callback: ChangeCallback) -> None:
        self._client = client
        self._callback = callback
        await self._subscribe()
        if self._watchdog is None:
            self._watchdog = asyncio.create_task(self._watchdog_loop())

    async def stop(self) -> None:
        self._alive = False
        if self._watchdog:
            self._watchdog.cancel()
            self._watchdog = None
        await self._unsubscribe()

    # ------------------------------------------------------------------

    async def _subscribe(self) -> None:
        assert self._client is not None
        await self._unsubscribe()
        channel = self._client.channel("kabanchiki-admin")
        for table in TABLES:
            channel = channel.on_postgres_changes(
                event="*",
                schema="public",
                table=table,
                callback=self._make_handler(table),
            )
        await channel.subscribe()
        self._channel = channel
        self._alive = True
        log.info("realtime subscribed")

    async def _unsubscribe(self) -> None:
        if self._channel is not None and self._client is not None:
            try:
                await self._client.remove_channel(self._channel)
            except Exception:  # noqa: BLE001 - best effort teardown
                log.debug("channel teardown failed", exc_info=True)
            self._channel = None

    def _make_handler(self, table: str):
        def handler(payload) -> None:
            try:
                data = payload.get("data", payload) if isinstance(payload, dict) else {}
                # realtime-py delivers the type as a str-Enum whose str() is
                # "RealtimePostgresChangesListenEvent.UPDATE" — normalize to
                # a bare "INSERT"/"UPDATE"/"DELETE".
                raw = data.get("type") or data.get("eventType") or ""
                event = str(getattr(raw, "value", raw)).split(".")[-1].upper()
                record = data.get("record") or data.get("new") or {}
                old = data.get("old_record") or data.get("old") or {}
                if self._callback:
                    self._callback(table, event, record, old)
            except Exception:  # noqa: BLE001 - callbacks must never kill the socket
                log.exception("realtime callback failed")

        return handler

    async def _watchdog_loop(self) -> None:
        backoff = 5
        while True:
            await asyncio.sleep(15)
            if self._client is None:
                continue
            socket = getattr(self._client.realtime, "is_connected", None)
            connected = bool(socket) if not callable(socket) else bool(socket())
            if connected:
                backoff = 5
                continue
            log.warning("realtime disconnected; resubscribing in %ss", backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 120)
            try:
                await self._subscribe()
            except Exception:  # noqa: BLE001
                log.exception("resubscribe failed")
