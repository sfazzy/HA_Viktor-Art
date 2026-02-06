# Panna Telnet (Hargassner)

Small YAML-only sensor platform which polls a Hargassner boiler controller over Telnet/TCP.

Why this exists:
- Home Assistant's built-in `tcp` sensor can fail on some systems with `filedescriptor out of range in select()`.
- This implementation uses asyncio sockets instead.

