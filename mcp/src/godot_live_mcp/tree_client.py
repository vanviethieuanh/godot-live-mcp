"""TCP NDJSON client for the Godot Tree bridge.

Speaks the same protocol as the addon's ``tree_cli.gd``/``tree_server.gd``:
one NDJSON request per connection, e.g.::

    {"id": 1, "op": "query", "args": {"path": "/City"}}``

and expects::

    {"id": 1, "ok": true, "result": {...}}

or::

    {"id": 1, "ok": false, "error": "..."}

The editor's TreeServer lives on loopback (default 127.0.0.1:41234) and is
started by the editor plugin when a project is open.
"""

from __future__ import annotations

import json
import os
import socket
from typing import Any

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 41234
DEFAULT_TIMEOUT_MS = 5000

_MAX_BUFFER = 1 << 20


class BridgeError(RuntimeError):
    """The Godot Tree bridge reported an error."""


class BridgeUnreachable(BridgeError):
    """Could not reach the Godot Tree bridge (editor not running?)."""


def host() -> str:
    return os.environ.get("GODOT_TREE_HOST", DEFAULT_HOST)


def port() -> int:
    try:
        return int(os.environ.get("GODOT_TREE_PORT", str(DEFAULT_PORT)))
    except ValueError:
        return DEFAULT_PORT


def timeout_seconds() -> float:
    try:
        return float(os.environ.get("GODOT_TREE_TIMEOUT_MS", str(DEFAULT_TIMEOUT_MS))) / 1000.0
    except ValueError:
        return DEFAULT_TIMEOUT_MS / 1000.0


def request(op: str, args: dict[str, Any] | None = None, req_id: int = 1) -> Any:
    """Send one request to the editor bridge and return the ``result``.

    Raises:
        BridgeUnreachable: if the editor bridge is not listening.
        BridgeError: if the bridge answered ``ok: false``.
    """
    payload = json.dumps({"id": req_id, "op": op, "args": args or {}})
    host_, port_, timeout = host(), port(), timeout_seconds()

    sock: socket.socket | None = None
    try:
        sock = socket.create_connection((host_, port_), timeout=timeout)
        sock.settimeout(timeout)
        sock.sendall((payload + "\n").encode("utf-8"))
        buffer = b""
        while b"\n" not in buffer:
            if len(buffer) > _MAX_BUFFER:
                raise BridgeError("bridge response exceeded maximum size")
            chunk = sock.recv(4096)
            if not chunk:
                break
            buffer += chunk
    except OSError as exc:
        raise BridgeUnreachable(
            f"cannot reach Godot Tree bridge at {host_}:{port_}: {exc}; "
            "open the project in the Godot editor (plugin starts the bridge)"
        ) from exc
    finally:
        if sock is not None:
            sock.close()

    if b"\n" not in buffer:
        raise BridgeUnreachable(
            f"no response from Godot Tree bridge at {host_}:{port_}; "
            "open the project in the Godot editor (plugin starts the bridge)"
        )

    line = buffer.split(b"\n", 1)[0].decode("utf-8")
    response: Any = json.loads(line)
    if not isinstance(response, dict):
        raise BridgeError("invalid bridge response")
    if bool(response.get("ok")):
        return response.get("result")
    raise BridgeError(str(response.get("error", "unknown bridge error")))
