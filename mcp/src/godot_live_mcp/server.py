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
    """Return info about the scene currently open in the Godot editor."""
    return _bridge("scene")


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
) -> list[dict[str, Any]]:
    """Find nodes under `path` matching the given filters. `name` and `script` accept glob patterns."""
    args: dict[str, Any] = {"path": path}
    if type is not None:
        args["type"] = type
    if name is not None:
        args["name"] = name
    if script is not None:
        args["script"] = script
    if has_prop is not None:
        args["has_prop"] = has_prop
    return _bridge("find", args)


@mcp.tool()
def tree_inspect(path: str = "/") -> dict[str, Any]:
    """Return semantic output for the node at `path` if it implements `agent_inspect()`."""
    return _bridge("inspect", {"path": path})


def main() -> None:
    mcp.run()
