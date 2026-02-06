"""SAJ Inverter – config‑ and options‑flow."""

from __future__ import annotations

import voluptuous as vol
from homeassistant import config_entries
from homeassistant.const import CONF_HOST
from homeassistant.core import callback

from .const import DOMAIN

CONF_DEBUG = "debug_logging"


# --------------------------------------------------------------------------- #
#                            CONFIG  (first install)                          #
# --------------------------------------------------------------------------- #
class ConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    """UI setup for a new SAJ inverter."""

    VERSION = 1

    async def async_step_user(self, user_input=None):
        """Initial form: ask only for the inverter’s IP/host."""
        if user_input is not None:
            return self.async_create_entry(
                title=user_input[CONF_HOST], data=user_input
            )

        schema = vol.Schema({vol.Required(CONF_HOST): str})
        return self.async_show_form(step_id="user", data_schema=schema)

    # Home Assistant calls this *on the class*, so it must be @staticmethod
    @staticmethod
    @callback
    def async_get_options_flow(config_entry):
        """Return the handler for the Options UI."""
        return OptionsFlowHandler(config_entry)


# --------------------------------------------------------------------------- #
#                               OPTIONS  (edit)                               #
# --------------------------------------------------------------------------- #
class OptionsFlowHandler(config_entries.OptionsFlow):
    """Present a single checkbox: Enable debug logging."""

    def __init__(self, entry: config_entries.ConfigEntry) -> None:
        self.entry = entry

    async def async_step_init(self, user_input=None):
        if user_input is not None:
            # Persist options → triggers reload with new settings
            return self.async_create_entry(title="", data=user_input)

        schema = vol.Schema(
            {
                vol.Optional(
                    CONF_DEBUG, default=self.entry.options.get(CONF_DEBUG, False)
                ): bool
            }
        )
        return self.async_show_form(step_id="init", data_schema=schema)