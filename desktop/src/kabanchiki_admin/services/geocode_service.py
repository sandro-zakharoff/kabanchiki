"""Reverse geocoding for location points whose phone stored no place name.

The assignee's phone fills locality on-device; on rural points or offline
maintenance-window wakes it can be empty. This resolves the name once from
OpenStreetMap Nominatim and the caller writes it back to the DB, so every
client reads the resolved name and the lookup happens once per point.

Respects Nominatim's usage policy: a valid User-Agent, at most one request per
second (serialized), and an in-memory cache keyed by rounded coordinate so
nearby points in the same locality never trigger a second call.
"""

from __future__ import annotations

import asyncio
import logging
import time

import httpx

log = logging.getLogger(__name__)

NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse"
# Nominatim asks for a descriptive UA identifying the application + contact.
USER_AGENT = "Kabanchiki/desktop (https://github.com/sandro-zakharoff/kabanchiki)"
MIN_INTERVAL = 1.1  # seconds between requests (policy: max 1/sec)

# Address fields from most to least specific — first non-empty wins.
_FIELDS = (
    "village",
    "town",
    "city",
    "hamlet",
    "municipality",
    "suburb",
    "county",
    "state",
)


class GeocodeService:
    def __init__(self) -> None:
        self._cache: dict[str, str] = {}
        self._lock = asyncio.Lock()
        self._last_call = 0.0

    @staticmethod
    def _key(lat: float, lng: float) -> str:
        # ~11 m grid: neighbouring points in one locality share a cache entry.
        return f"{lat:.4f},{lng:.4f}"

    async def resolve(self, lat: float, lng: float) -> str:
        """Place name for a coordinate, or '' if it can't be resolved."""
        key = self._key(lat, lng)
        if key in self._cache:
            return self._cache[key]
        # Serialize + rate-limit: one request per second, app-wide.
        async with self._lock:
            if key in self._cache:  # filled while we waited for the lock
                return self._cache[key]
            wait = MIN_INTERVAL - (time.monotonic() - self._last_call)
            if wait > 0:
                await asyncio.sleep(wait)
            name = await self._request(lat, lng)
            self._last_call = time.monotonic()
            self._cache[key] = name
            return name

    async def _request(self, lat: float, lng: float) -> str:
        params = {
            "format": "jsonv2",
            "lat": f"{lat}",
            "lon": f"{lng}",
            "zoom": "13",
            "accept-language": "uk",
        }
        try:
            async with httpx.AsyncClient(timeout=15) as http:
                resp = await http.get(
                    NOMINATIM_URL,
                    params=params,
                    headers={"User-Agent": USER_AGENT},
                )
            if resp.status_code != 200:
                log.info("nominatim %s for %s,%s", resp.status_code, lat, lng)
                return ""
            data = resp.json()
            address = data.get("address") or {}
            for field in _FIELDS:
                value = address.get(field)
                if value:
                    return str(value)
            return str(data.get("name") or "")
        except Exception:  # noqa: BLE001 - a failed lookup just leaves coordinates
            log.debug("nominatim request failed", exc_info=True)
            return ""
