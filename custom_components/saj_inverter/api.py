"""SAJ inverter – network interface (robust encoding + clean session)."""
from __future__ import annotations

import asyncio
import logging
from typing import Final
from xml.etree import ElementTree as ET

import aiohttp
import async_timeout

_LOGGER = logging.getLogger(__name__)

PARAM_JS: Final = "/param.js"
REALTIME: Final = "/real_time_data.xml"
TIMEOUT: Final = 10


class SAJApiError(RuntimeError):
    """Network or parse problem."""


class SAJApi:
    """Fetch order array (once) and live XML (repeat)."""

    def __init__(self, host: str, session: aiohttp.ClientSession | None = None):
        self._base = f"http://{host}"
        # allow injector session for easier unit‑testing
        self._session = session or aiohttp.ClientSession()
        self._order: list[str] | None = None

    async def async_close(self) -> None:
        """Close the underlying aiohttp session."""
        if not self._session.closed:
            await self._session.close()

    # ------------------------------------------------------------------
    async def fetch(self) -> dict[str, float | int | str]:
        """Public API – always returns {tag: value} dict."""
        try:
            if self._order is None:
                await self._load_order()          # may end up empty
        except SAJApiError:
            _LOGGER.debug("param.js had no Array(…); falling back to tag mode")

        return await self._load_realtime()        # now returns dict

    # ------------------------------------------------------------------
    async def _load_order(self) -> None:
        """Try to extract an Array(…) from param.js, else leave list empty."""
        text = await self._get_text(PARAM_JS)
        import re

        m = re.search(r"new\s+Array\s*\((.*?)\)", text, re.S)
        if not m:
            self._order = []          # tells _load_realtime() to use tag mode
            return

        self._order = re.findall(r'"([^"]+)"', m.group(1))
        _LOGGER.debug("param.js order loaded: %s", self._order)

    # ------------------------------------------------------------------
    async def _load_realtime(self) -> dict[str, str]:
        """Return dict from <tag>value</tag> **or** zipped array mode."""
        xml = await self._get_text(f"{REALTIME}?t=0")
        from xml.etree import ElementTree as ET

        root = ET.fromstring(xml)

        # ── Mode A – each child already has its tag name (your firmware) ----
        if not self._order:
            return {child.tag: child.text or "" for child in root}

        # ── Mode B – ‘<value>…’ list & order array (newer firmware) ---------
        values = [e.text or "" for e in root.iter() if e.tag.lower() == "value"]
        if len(values) != len(self._order):
            raise SAJApiError(
                f"Length mismatch: {len(values)} values vs {len(self._order)} ids"
            )

        return dict(zip(self._order, values, strict=True))

    # ------------------------------------------------------------------ core I/O
    async def _get_text(self, path: str) -> str:
        """GET <base><path> and decode safely (UTF‑8, UTF‑16, Latin‑1)."""
        url = f"{self._base}{path}"
        _LOGGER.debug("GET %s", url)

        try:
            async with async_timeout.timeout(TIMEOUT):
                async with self._session.get(url) as resp:
                    raw: bytes = await resp.read()  # *** always raw bytes ***
        except (aiohttp.ClientError, asyncio.TimeoutError) as err:
            raise SAJApiError(f"Request {url} failed: {err}") from err

        # ---- manual decode -------------------------------------------
        if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
            return raw.decode("utf-16")
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            return raw.decode("latin-1", errors="replace")

    @staticmethod
    def _auto(value: str) -> float | int | str:
        """Convert numeric strings, leave others untouched. """
        v = value.strip()
        try:
            if "." in v:
                return float(v)
            return int(v)
        except ValueError:
            return v