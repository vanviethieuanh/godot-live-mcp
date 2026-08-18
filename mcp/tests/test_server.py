"""MCP server tests using the SDK's in-memory Client, with the bridge mocked.

These verify each tool's op/arg mapping and result passing over the real MCP
protocol, without needing the Godot editor.
"""

from __future__ import annotations

from typing import Any, Callable

import pytest
from mcp import Client

from godot_live_mcp import tree_client
from godot_live_mcp.server import mcp


def _stub(result: Any = None) -> Callable[..., Any]:
    return lambda *args, **kwargs: result


@pytest.mark.anyio
async def test_tree_ping(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tree_client, "request", _stub({"pong": True}))
    async with Client(mcp) as client:
        result = await client.call_tool("tree_ping", {})
    assert result.structured_content == {"pong": True}


@pytest.mark.anyio
async def test_tree_query_passes_path(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["op"] = op
        captured["args"] = args
        return {"name": "Chapel"}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        result = await client.call_tool("tree_query", {"path": "/City/Chapel"})
    assert captured == {"op": "query", "args": {"path": "/City/Chapel"}}
    assert result.structured_content == {"name": "Chapel"}


@pytest.mark.anyio
async def test_tree_find_omits_unset_filters(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["op"] = op
        captured["args"] = args
        return []

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("tree_find", {"type": "Node2D"})
    assert captured == {"op": "find", "args": {"path": "/", "type": "Node2D"}}


@pytest.mark.anyio
async def test_tree_find_with_all_filters(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["args"] = args
        return []

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool(
            "tree_find",
            {"path": "/City", "type": "Node2D", "name": "Office*", "script": "office.gd", "has_prop": "speed"},
        )
    assert captured["args"] == {
        "path": "/City",
        "type": "Node2D",
        "name": "Office*",
        "script": "office.gd",
        "has_prop": "speed",
    }


@pytest.mark.anyio
async def test_bridge_error_surfaces(monkeypatch: pytest.MonkeyPatch) -> None:
    def boom(*args: Any, **kwargs: Any) -> Any:
        raise tree_client.BridgeError("node not found: /Nope")

    monkeypatch.setattr(tree_client, "request", boom)
    async with Client(mcp) as client:
        result = await client.call_tool("tree_query", {"path": "/Nope"})
    assert result.is_error
    text = "".join(str(part.text) for part in result.content if getattr(part, "type", "") == "text")
    assert "node not found" in text


@pytest.mark.anyio
async def test_tools_are_listed() -> None:
    async with Client(mcp) as client:
        names = {tool.name for tool in (await client.list_tools()).tools}
    assert names == {
        "tree_ping",
        "tree_scene",
        "tree_query",
        "tree_children",
        "tree_props",
        "tree_find",
        "tree_inspect",
    }
