"""Expose every DOM id from param.js as a HA sensor."""
from __future__ import annotations

from homeassistant.components.sensor import (
    SensorEntity,
    SensorEntityDescription,
    SensorStateClass,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .coordinator import SAJCoordinator


def _friendly(key: str) -> str:
    return (
        key.replace("v-", "Voltage ")
        .replace("i-", "Current ")
        .replace("p-", "Power ")
        .replace("e-", "Energy ")
        .replace("-", " ")
        .title()
    )


def _unit(key: str) -> str | None:
    if key.startswith(("v-", "vbus", "vac")):
        return "V"
    if key.startswith(("i-", "iac")):
        return "A"
    if key.startswith(("p-", "pac")):
        return "W"
    if key.startswith("e-"):
        return "kWh"
    return None


class SAJSensor(SensorEntity):
    _attr_has_entity_name = True

    def __init__(self, coordinator: SAJCoordinator, key: str) -> None:
        self.coordinator = coordinator
        self.entity_description = SensorEntityDescription(
            key=key,
            name=_friendly(key),
            native_unit_of_measurement=_unit(key),
            state_class=SensorStateClass.MEASUREMENT
            if _unit(key) in ("V", "A", "W")
            else SensorStateClass.TOTAL_INCREASING
            if _unit(key) == "kWh"
            else None,
        )
        self._attr_unique_id = f"{DOMAIN}_{key}"

        # ── NEW: force object_id “sajinv_<key>” ────────────────────────
        self._attr_entity_id = f"sensor.sajinv_{key}"

    @callback
    def _handle_coordinator_update(self) -> None:
        self._attr_native_value = self.coordinator.data.get(self.entity_description.key)
        self.async_write_ha_state()

    async def async_added_to_hass(self) -> None:
        self._handle_coordinator_update()
        self.coordinator.async_add_listener(self._handle_coordinator_update)


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator: SAJCoordinator = hass.data[DOMAIN][entry.entry_id]

    # Make one entity per key the API discovered
    async_add_entities([SAJSensor(coordinator, k) for k in coordinator.data], True)