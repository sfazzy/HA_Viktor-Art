"""DataUpdateCoordinator for SAJ inverter."""
from __future__ import annotations

import logging
from datetime import timedelta

import aiohttp
from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .api import SAJApi, SAJApiError
from .const import DOMAIN, UPDATE_INTERVAL

_LOGGER = logging.getLogger(__name__)


class SAJCoordinator(DataUpdateCoordinator[dict[str, float | int | str]]):
    """Shared single fetcher for all entities."""

    def __init__(self, hass: HomeAssistant, host: str) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name=DOMAIN,
            update_interval=timedelta(seconds=UPDATE_INTERVAL),
        )
        self.api = SAJApi(host, aiohttp.ClientSession())

    async def _async_update_data(self) -> dict[str, float | int | str]:
        try:
            return await self.api.fetch()
        except SAJApiError as err:
            raise UpdateFailed(str(err)) from err