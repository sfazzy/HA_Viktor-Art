#!/usr/bin/env python3
"""Panna (Hargassner) telnet poller for Home Assistant command_line sensor.

Outputs JSON with:
- state: "ok" or "error"
- tokens: list[str]
- tokens_len: int
- raw_len: int
- last_error: str | null
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
from typing import Final


DEFAULT_HOST: Final[str] = "192.168.2.3"
DEFAULT_PORT: Final[int] = 23
DEFAULT_PAYLOAD: Final[bytes] = b"\n"
DEFAULT_TIMEOUT_S: Final[float] = 5.0
DEFAULT_MAX_BYTES: Final[int] = 4096


def _poll(*, host: str, port: int, timeout_s: float, payload: bytes, max_bytes: int) -> str:
    sock = socket.socket()
    sock.settimeout(timeout_s)
    try:
        sock.connect((host, port))
        if payload:
            sock.sendall(payload)

        data = bytearray()
        while len(data) < max_bytes:
            try:
                chunk = sock.recv(max_bytes - len(data))
            except socket.timeout:
                break
            if not chunk:
                break
            data += chunk
            if b"\n" in chunk:
                break

        if not data:
            raise TimeoutError("No data received")

        return bytes(data[:max_bytes]).decode("utf-8", errors="ignore").strip()
    finally:
        try:
            sock.close()
        except Exception:
            pass


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_S)
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    args = parser.parse_args(argv)

    try:
        raw = _poll(
            host=args.host,
            port=args.port,
            timeout_s=args.timeout,
            payload=DEFAULT_PAYLOAD,
            max_bytes=args.max_bytes,
        )
        tokens = raw.split()
        payload = {
            "state": "ok",
            "tokens": tokens,
            "tokens_len": len(tokens),
            "raw_len": len(raw),
            "last_error": None,
        }
    except Exception as err:
        payload = {
            "state": "error",
            "tokens": [],
            "tokens_len": 0,
            "raw_len": 0,
            "last_error": str(err),
        }

    sys.stdout.write(json.dumps(payload, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

