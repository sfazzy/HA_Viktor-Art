"""Panna (Hargassner) raw telnet/TCP poller.

Exposes a single sensor whose state is the raw response from the device.
Implemented with asyncio sockets to avoid issues seen with the built-in `tcp`
sensor (which uses `select()` internally).
"""

from __future__ import annotations

import asyncio
from datetime import timedelta
import logging

import voluptuous as vol

from homeassistant.components.sensor import PLATFORM_SCHEMA, SensorEntity
from homeassistant.const import CONF_HOST, CONF_NAME, CONF_PORT, CONF_TIMEOUT
from homeassistant.core import HomeAssistant
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.event import async_track_time_interval

_LOGGER = logging.getLogger(__name__)

DOMAIN = "panna_telnet"

CONF_PAYLOAD = "payload"
CONF_SCAN_INTERVAL = "scan_interval"
CONF_MAX_BYTES = "max_bytes"

DEFAULT_NAME = "panna_telnet"
DEFAULT_PORT = 23
DEFAULT_PAYLOAD = "\n"
DEFAULT_TIMEOUT = 5
DEFAULT_SCAN_INTERVAL = 60
DEFAULT_MAX_BYTES = 4096

PLATFORM_SCHEMA = PLATFORM_SCHEMA.extend(
    {
        vol.Required(CONF_HOST): cv.string,
        vol.Optional(CONF_PORT, default=DEFAULT_PORT): cv.port,
        vol.Optional(CONF_NAME, default=DEFAULT_NAME): cv.string,
        vol.Optional(CONF_PAYLOAD, default=DEFAULT_PAYLOAD): cv.string,
        vol.Optional(CONF_TIMEOUT, default=DEFAULT_TIMEOUT): cv.positive_int,
        vol.Optional(CONF_SCAN_INTERVAL, default=DEFAULT_SCAN_INTERVAL): cv.positive_int,
        vol.Optional(CONF_MAX_BYTES, default=DEFAULT_MAX_BYTES): cv.positive_int,
    }
)


async def async_setup_platform(
    hass: HomeAssistant,
    config: dict,
    async_add_entities: AddEntitiesCallback,
    discovery_info=None,
) -> None:
    name: str = config[CONF_NAME]
    host: str = config[CONF_HOST]
    port: int = config[CONF_PORT]
    payload: str = config[CONF_PAYLOAD]
    timeout: int = config[CONF_TIMEOUT]
    scan_interval: int = config[CONF_SCAN_INTERVAL]
    max_bytes: int = config[CONF_MAX_BYTES]

    _LOGGER.warning(
        "panna_telnet: setting up sensor '%s' (%s:%s)", name, host, port
    )

    async_add_entities(
        [
            PannaTelnetRawSensor(
                name=name,
                host=host,
                port=port,
                payload=payload,
                timeout=timeout,
                scan_interval=scan_interval,
                max_bytes=max_bytes,
            )
        ],
        update_before_add=True,
    )


class PannaTelnetRawSensor(SensorEntity):
    _attr_has_entity_name = False
    # We manage our own polling interval so we can respect a YAML-configured scan_interval.
    _attr_should_poll = False

    def __init__(
        self,
        *,
        name: str,
        host: str,
        port: int,
        payload: str,
        timeout: int,
        scan_interval: int,
        max_bytes: int,
    ) -> None:
        self._attr_name = name
        self._host = host
        self._port = port
        self._payload = payload.encode("utf-8", errors="ignore")
        self._timeout = timeout
        self._scan_interval = timedelta(seconds=scan_interval)
        self._max_bytes = max_bytes
        self._attr_native_value: str | None = None
        self._attr_available = True
        self._unsub_timer = None
        self._logged_first_ok = False
        self._attrs: dict[str, object] = {
            "raw_len": None,
            "tokens_len": 0,
            "tokens": [],
            "last_error": "Not updated yet",
        }

    @property
    def extra_state_attributes(self) -> dict[str, object]:
        return self._attrs

    async def async_added_to_hass(self) -> None:
        async def _scheduled_update(_now=None) -> None:
            await self._async_fetch_update()
            self.async_write_ha_state()

        # Populate immediately at startup, then poll regularly.
        await _scheduled_update()
        self._unsub_timer = async_track_time_interval(
            self.hass, _scheduled_update, self._scan_interval
        )

    async def async_will_remove_from_hass(self) -> None:
        if self._unsub_timer:
            self._unsub_timer()
            self._unsub_timer = None

    async def _async_fetch_update(self) -> None:
        try:
            data = await _fetch_tcp(
                host=self._host,
                port=self._port,
                payload=self._payload,
                timeout=self._timeout,
                max_bytes=self._max_bytes,
            )
        except Exception as err:
            self._attr_available = False
            # Expose the error so it is visible in HA (and not only in logs).
            self._attrs = {
                **self._attrs,
                "last_error": str(err),
            }
            _LOGGER.warning("Panna telnet fetch failed: %s", err)
            return

        self._attr_available = True

        # Keep state short (HA has a hard limit of 255 chars), but expose full parsed values via
        # attributes for template sensors.
        tokens = data.split()
        self._attrs = {
            "raw_len": len(data),
            "tokens_len": len(tokens),
            "tokens": tokens,
            "last_error": None,
        }
        self._attr_native_value = data[:254]

        if not self._logged_first_ok:
            self._logged_first_ok = True
            _LOGGER.warning(
                "panna_telnet: first update OK (tokens=%s, raw_len=%s)",
                len(tokens),
                len(data),
            )


async def _fetch_tcp(
    *,
    host: str,
    port: int,
    payload: bytes,
    timeout: int,
    max_bytes: int,
) -> str:
    async def _do() -> str:
        reader, writer = await asyncio.open_connection(host=host, port=port)
        try:
            if payload:
                writer.write(payload)
                await writer.drain()

            # Hargassner telnet often does NOT terminate the payload with '\n' and can keep the
            # connection open. Therefore `readuntil(b"\n")` can hang until timeout.
            # We instead read whatever arrives:
            # - wait a bit longer for the first bytes (device can be slow)
            # - then stop after a short idle period
            raw = bytearray()
            first_read = True
            while len(raw) < max_bytes:
                try:
                    read_timeout = min(2.0, float(timeout)) if first_read else 0.3
                    chunk = await asyncio.wait_for(
                        reader.read(max_bytes - len(raw)), timeout=read_timeout
                    )
                except asyncio.TimeoutError:
                    break

                if not chunk:
                    break

                raw += chunk
                first_read = False
                if b"\n" in chunk:
                    break

            if not raw:
                raise TimeoutError("No data received from panna telnet")

            # Home Assistant entity state strings are limited (255 chars); always cap the raw bytes
            # so this sensor remains valid even if the boiler returns a long line.
            raw_bytes = bytes(raw[:max_bytes])
            return raw_bytes.decode("utf-8", errors="ignore").strip()
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

    return await asyncio.wait_for(_do(), timeout=timeout)
