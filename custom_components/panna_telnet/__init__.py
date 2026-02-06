"""Panna (Hargassner) telnet poller."""

from __future__ import annotations

from homeassistant.core import HomeAssistant

DOMAIN = "panna_telnet"


async def async_setup(hass: HomeAssistant, config: dict) -> bool:
    """Set up from YAML."""
    return True

