"""MCP server exposing the Godot Tree bridge as agent-facing tools.

Run with: ``godot-live-mcp`` (stdio). All bridge communication goes over the
loopback TCP bridge served by the Godot editor plugin.
"""

from __future__ import annotations

from typing import Any

from mcp.server import MCPServer

from . import tree_client

mcp = MCPServer("godot-live")


def _bridge(op: str, args: dict[str, Any] | None = None) -> Any:
    try:
        return tree_client.request(op, args)
    except tree_client.BridgeError as exc:
        raise RuntimeError(str(exc)) from exc


@mcp.tool()
def tree_ping() -> dict[str, Any]:
    """Check the live bridge: returns a pong plus the scene currently open in the editor."""
    return _bridge("ping")


@mcp.tool()
def tree_scene() -> dict[str, Any]:
    """Return info about the scene currently open in the Godot editor: root name/type, node count, and whether it has unsaved changes."""
    return _bridge("scene")


@mcp.tool()
def tree_editor() -> dict[str, Any]:
    """Return basic info about the running engine/project: Godot version, project name, project path, and the current scene."""
    return _bridge("editor")


@mcp.tool()
def tree_dump(path: str = "/", depth: int = 2) -> dict[str, Any]:
    """Return a nested dump of the scene tree under `path`, up to `depth` levels deep (0 = node only)."""
    return _bridge("tree", {"path": path, "depth": depth})


@mcp.tool()
def tree_query(path: str = "/") -> dict[str, Any]:
    """Return a summary of the node at `path` (e.g. /City/Chapel). "/" is the scene root."""
    return _bridge("query", {"path": path})


@mcp.tool()
def tree_children(path: str = "/") -> list[dict[str, Any]]:
    """Return summaries of the direct children of the node at `path`."""
    return _bridge("children", {"path": path})


@mcp.tool()
def tree_props(path: str = "/") -> dict[str, Any]:
    """Return the exported (editor-visible) properties of the node at `path`."""
    return _bridge("props", {"path": path})


@mcp.tool()
def tree_find(
    path: str = "/",
    type: str | None = None,
    name: str | None = None,
    script: str | None = None,
    has_prop: str | None = None,
    path_pattern: str | None = None,
) -> list[dict[str, Any]]:
    """Find nodes under `path` matching the given filters. `name`, `script`, and `path_pattern` accept glob patterns; `path_pattern` matches absolute paths segment-wise (e.g. /A/*/C)."""
    args: dict[str, Any] = {"path": path}
    if type is not None:
        args["type"] = type
    if name is not None:
        args["name"] = name
    if script is not None:
        args["script"] = script
    if has_prop is not None:
        args["has_prop"] = has_prop
    if path_pattern is not None:
        args["path_pattern"] = path_pattern
    return _bridge("find", args)


@mcp.tool()
def tree_inspect(path: str = "/") -> dict[str, Any]:
    """Return semantic output for the node at `path` if it implements `agent_inspect()`, else `{"agent_inspect": false}`."""
    result = _bridge("inspect", {"path": path})
    if result is None:
        return {"agent_inspect": False}
    return result


@mcp.tool()
def tree_set(path: str, property: str, value: Any = None) -> dict[str, Any]:
    """Set `property` on the node at `path`. Undoable and marks the scene unsaved. `value` accepts scalars, arrays for vectors/colors, or res:// paths for resources."""
    return _bridge("set", {"path": path, "property": property, "value": value})


@mcp.tool()
def tree_add(
    parent_path: str = "/",
    node_type: str = "",
    node_name: str = "",
    properties: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Add a node of `node_type` named `node_name` under `parent_path`, optionally applying `properties`. Undoable and marks the scene unsaved."""
    args: dict[str, Any] = {"parent_path": parent_path, "node_type": node_type, "node_name": node_name}
    if properties:
        args["properties"] = properties
    return _bridge("add", args)


@mcp.tool()
def tree_remove(path: str) -> dict[str, Any]:
    """Remove the node at `path`. Undoable and marks the scene unsaved."""
    return _bridge("remove", {"path": path})


@mcp.tool()
def tree_move(path: str, parent_path: str = "/", index: int | None = None) -> dict[str, Any]:
    """Reparent the node at `path` under `parent_path`, optionally at child `index`. Undoable and marks the scene unsaved."""
    args: dict[str, Any] = {"path": path, "parent_path": parent_path}
    if index is not None:
        args["index"] = index
    return _bridge("move", args)


def main() -> None:
    mcp.run()
