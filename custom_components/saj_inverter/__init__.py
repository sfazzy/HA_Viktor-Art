"""SAJ Inverter – Home Assistant custom integration."""
from __future__ import annotations

import logging
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant

from .const import DOMAIN
from .coordinator import SAJCoordinator

_LOGGER = logging.getLogger(__name__)
COMP_LOGGER = logging.getLogger("custom_components.saj_inverter")

PLATFORMS: list[str] = ["sensor"]


# -----------------------------------------------------------------------------


async def async_setup(hass: HomeAssistant, _config: dict) -> bool:
    """Stub for old‑style YAML (unused but must return True)."""
    return True


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Set up a SAJ inverter from the UI config‑flow."""
    coordinator = SAJCoordinator(hass, entry.data["host"])
    await coordinator.async_config_entry_first_refresh()

    # ── Apply debug toggle ---------------------------------------------
    if entry.options.get("debug_logging", False):
        COMP_LOGGER.setLevel(logging.DEBUG)
    else:
        COMP_LOGGER.setLevel(logging.INFO)

    # Store and forward to platforms
    hass.data.setdefault(DOMAIN, {})[entry.entry_id] = coordinator
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload the integration (called on remove / reload)."""
    unload_ok = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unload_ok:
        hass.data[DOMAIN].pop(entry.entry_id, None)
    return unload_ok