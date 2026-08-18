"""Tests for tree_client against a fake TCP server (no Godot needed)."""

from __future__ import annotations

import json
import socket
import threading

import pytest

from godot_live_mcp import tree_client


class FakeBridge:
    """Tiny threaded TCP server that responds with canned NDJSON lines."""

    def __init__(self, responses: list[dict[str, object]]) -> None:
        self.responses = responses
        self.received: list[str] = []
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.bind(("127.0.0.1", 0))
        self._sock.listen(1)
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self.port = self._sock.getsockname()[1]

    def start(self) -> "FakeBridge":
        self._thread.start()
        return self

    def stop(self) -> None:
        self._sock.close()

    def _serve(self) -> None:
        conn, _ = self._sock.accept()
        with conn:
            data = b""
            while b"\n" not in data:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            if data:
                self.received.append(data.decode("utf-8"))
            for response in self.responses:
                conn.sendall((json.dumps(response) + "\n").encode("utf-8"))


@pytest.fixture()
def client_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GODOT_TREE_HOST", "127.0.0.1")
    monkeypatch.setenv("GODOT_TREE_TIMEOUT_MS", "2000")


def _with_port(monkeypatch: pytest.MonkeyPatch, bridge: FakeBridge) -> None:
    monkeypatch.setenv("GODOT_TREE_PORT", str(bridge.port))


def test_request_framing_and_result(client_env: None, monkeypatch: pytest.MonkeyPatch) -> None:
    bridge = FakeBridge([{"id": 1, "ok": True, "result": {"pong": True}}]).start()
    try:
        _with_port(monkeypatch, bridge)
        result = tree_client.request("ping")
        assert result == {"pong": True}
        request = json.loads(bridge.received[0])
        assert request == {"id": 1, "op": "ping", "args": {}}
    finally:
        bridge.stop()


def test_request_sends_args_and_id(client_env: None, monkeypatch: pytest.MonkeyPatch) -> None:
    bridge = FakeBridge([{"id": 7, "ok": True, "result": []}]).start()
    try:
        _with_port(monkeypatch, bridge)
        result = tree_client.request("find", {"type": "Node2D"}, req_id=7)
        assert result == []
        request = json.loads(bridge.received[0])
        assert request == {"id": 7, "op": "find", "args": {"type": "Node2D"}}
    finally:
        bridge.stop()


def test_error_response_raises(client_env: None, monkeypatch: pytest.MonkeyPatch) -> None:
    bridge = FakeBridge([{"id": 1, "ok": False, "error": "node not found: /Nope"}]).start()
    try:
        _with_port(monkeypatch, bridge)
        with pytest.raises(tree_client.BridgeError, match="node not found"):
            tree_client.request("query", {"path": "/Nope"})
    finally:
        bridge.stop()


def test_unreachable_raises(client_env: None, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GODOT_TREE_PORT", "1")  # nothing listens here
    with pytest.raises(tree_client.BridgeUnreachable):
        tree_client.request("ping")
