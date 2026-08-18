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
            {"path": "/City", "type": "Node2D", "name": "Office*", "script": "office.gd", "has_prop": "speed",
             "path_pattern": "/City/*/Fountain"},
        )
    assert captured["args"] == {
        "path": "/City",
        "type": "Node2D",
        "name": "Office*",
        "script": "office.gd",
        "has_prop": "speed",
        "path_pattern": "/City/*/Fountain",
    }


@pytest.mark.anyio
async def test_tree_find_path_pattern_alone(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["args"] = args
        return []

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("tree_find", {"path_pattern": "/*/Plaza/*"})
    assert captured["args"] == {"path": "/", "path_pattern": "/*/Plaza/*"}


@pytest.mark.anyio
async def test_bridge_error_surfaces(monkeypatch: pytest.MonkeyPatch) -> None:
    def boom(*args: Any, **kwargs: Any) -> Any:
        raise tree_client.BridgeError("node not found: /Nope")

    monkeypatch.setattr(tree_client, "request", boom)
    async with Client(mcp) as client:
        result = await client.call_tool("tree_query", {"path": "/Nope"})
    assert result.is_error
    text = "".join(part.text for part in result.content if part.type == "text")
    assert "node not found" in text


@pytest.mark.anyio
async def test_tree_set_passes_args(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["op"] = op
        captured["args"] = args
        return {"path": "/Node", "property": "position", "value": "(10, 20)"}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        result = await client.call_tool("tree_set", {"path": "/Node", "property": "position", "value": [10, 20]})
    assert captured == {"op": "set", "args": {"path": "/Node", "property": "position", "value": [10, 20]}}
    assert result.structured_content == {"path": "/Node", "property": "position", "value": "(10, 20)"}


@pytest.mark.anyio
async def test_tree_add_passes_args(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["args"] = args
        return {"path": "/City"}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool(
            "tree_add",
            {"parent_path": "/", "node_type": "Node2D", "node_name": "City", "properties": {"position": [1, 2]}},
        )
    assert captured["args"] == {
        "parent_path": "/",
        "node_type": "Node2D",
        "node_name": "City",
        "properties": {"position": [1, 2]},
    }


@pytest.mark.anyio
async def test_tree_add_omits_empty_properties(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["args"] = args
        return {}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("tree_add", {"node_type": "Node", "node_name": "X"})
    assert captured["args"] == {"parent_path": "/", "node_type": "Node", "node_name": "X"}


@pytest.mark.anyio
async def test_tree_remove_and_move(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: list[Any] = []

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured.append((op, args))
        return {"path": "/Node"}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("tree_remove", {"path": "/Node"})
        await client.call_tool("tree_move", {"path": "/Node", "parent_path": "/City", "index": 2})
    assert captured == [
        ("remove", {"path": "/Node"}),
        ("move", {"path": "/Node", "parent_path": "/City", "index": 2}),
    ]


@pytest.mark.anyio
async def test_tree_inspect_no_hook(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tree_client, "request", _stub(None))
    async with Client(mcp) as client:
        result = await client.call_tool("tree_inspect", {"path": "/Node"})
    assert result.structured_content == {"agent_inspect": False}


@pytest.mark.anyio
async def test_tree_editor(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["op"] = op
        captured["args"] = args
        return {"godot_version": "4.7.1.stable"}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        result = await client.call_tool("tree_editor", {})
    assert captured == {"op": "editor", "args": None}  # None is normalized to {} on the wire
    assert result.structured_content == {"godot_version": "4.7.1.stable"}


@pytest.mark.anyio
async def test_tree_dump(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: list[Any] = []

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured.append((op, args))
        return {}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("tree_dump", {"path": "/City", "depth": 3})
        await client.call_tool("tree_dump", {})
    assert captured == [
        ("tree", {"path": "/City", "depth": 3}),
        ("tree", {"path": "/", "depth": 2}),
    ]


@pytest.mark.anyio
async def test_log_read_passes_since_and_limit(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["op"] = op
        captured["args"] = args
        return {"seq": 5, "base_seq": 0, "entries": [{"seq": 4, "level": "info", "message": "hello"}]}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        result = await client.call_tool("log_read", {"since": 3, "limit": 10})
    assert captured == {"op": "log", "args": {"since": 3, "limit": 10}}
    assert result.structured_content == {
        "seq": 5,
        "base_seq": 0,
        "entries": [{"seq": 4, "level": "info", "message": "hello"}],
    }


@pytest.mark.anyio
async def test_log_read_defaults(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["args"] = args
        return {"seq": 0, "base_seq": 0, "entries": []}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("log_read", {})
    assert captured["args"] == {"since": 0, "limit": 0}


@pytest.mark.anyio
async def test_log_probe_passes_args(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["op"] = op
        captured["args"] = args
        return {"ok": True}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("log_probe", {"message": "hi", "level": "error"})
    assert captured == {"op": "log_probe", "args": {"message": "hi", "level": "error"}}


@pytest.mark.anyio
async def test_log_probe_defaults(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["args"] = args
        return {"ok": True}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("log_probe", {})
    assert captured["args"] == {"message": "probe", "level": "info"}


@pytest.mark.anyio
async def test_create_scene_passes_args(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["op"] = op
        captured["args"] = args
        return {"save_path": "res://scenes/city.tscn", "node_count": 4}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool(
            "create_scene",
            {
                "root_type": "Node2D",
                "root_name": "City",
                "save_path": "res://scenes/city.tscn",
                "children": [{"node_type": "Node2D", "node_name": "Plaza", "properties": {"position": [1, 2]}}],
            },
        )
    assert captured["op"] == "create_scene"
    assert captured["args"] == {
        "root_type": "Node2D",
        "root_name": "City",
        "save_path": "res://scenes/city.tscn",
        "children": [{"node_type": "Node2D", "node_name": "Plaza", "properties": {"position": [1, 2]}}],
    }


@pytest.mark.anyio
async def test_create_scene_omits_empty_children(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["args"] = args
        return {}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("create_scene", {"root_type": "Node", "root_name": "X", "save_path": "res://x.tscn"})
    assert captured["args"] == {"root_type": "Node", "root_name": "X", "save_path": "res://x.tscn"}


@pytest.mark.anyio
async def test_get_uid_by_path(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["op"] = op
        captured["args"] = args
        return {"path": "res://a.gd", "uid": "uid://abc"}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        result = await client.call_tool("get_uid", {"path": "res://a.gd"})
    assert captured == {"op": "get_uid", "args": {"path": "res://a.gd"}}
    assert result.structured_content == {"path": "res://a.gd", "uid": "uid://abc"}


@pytest.mark.anyio
async def test_get_uid_by_uid(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["args"] = args
        return {"path": "res://a.gd", "uid": "uid://abc"}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("get_uid", {"uid": "uid://abc"})
    assert captured["args"] == {"uid": "uid://abc"}


@pytest.mark.anyio
async def test_get_uid_no_args_omits_keys(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["args"] = args
        return {"path": "", "uid": None}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("get_uid", {})
    assert captured["args"] == {}


@pytest.mark.anyio
async def test_update_project_uids_passes_dry_run(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["op"] = op
        captured["args"] = args
        return {"scanned": 10, "already_had_uid": 3, "generated": 7, "skipped": 2}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        result = await client.call_tool("update_project_uids", {"dry_run": True})
    assert captured == {"op": "update_project_uids", "args": {"dry_run": True}}
    assert result.structured_content == {"scanned": 10, "already_had_uid": 3, "generated": 7, "skipped": 2}


@pytest.mark.anyio
async def test_update_project_uids_defaults(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["args"] = args
        return {"scanned": 0, "already_had_uid": 0, "generated": 0, "skipped": 0}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        await client.call_tool("update_project_uids", {})
    assert captured["args"] == {"dry_run": False}


@pytest.mark.anyio
async def test_project_get_setting_exact(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake(op: str, args: dict[str, Any] | None = None, **kwargs: Any) -> Any:
        captured["op"] = op
        captured["args"] = args
        return {"path": "application/config/name", "value": "my-project"}

    monkeypatch.setattr(tree_client, "request", fake)
    async with Client(mcp) as client:
        result = await client.call_tool("project_get_setting", {"path": "application/config/name"})
    assert captured == {"op": "get_setting", "args": {"path": "application/config/name"}}
    assert result.structured_content == {"path": "application/config/name", "value": "my-project"}


@pytest.mark.anyio
async def test_tools_are_listed() -> None:
    async with Client(mcp) as client:
        names = {tool.name for tool in (await client.list_tools()).tools}
    assert names == {
        "tree_ping",
        "tree_scene",
        "tree_editor",
        "tree_query",
        "tree_children",
        "tree_props",
        "tree_find",
        "tree_inspect",
        "tree_dump",
        "tree_set",
        "tree_add",
        "tree_remove",
        "tree_move",
        "create_scene",
        "log_read",
        "log_probe",
        "get_uid",
        "update_project_uids",
        "project_get_setting",
    }
