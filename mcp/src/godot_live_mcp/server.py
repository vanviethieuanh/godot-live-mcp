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
def log_read(since: int = 0, limit: int = 0) -> dict[str, Any]:
    """Return captured engine log messages newer than sequence number `since` (start at 0 for everything buffered). Each entry has `seq`, `level` (info/warning/error), and `message`. Delta-based: pass back the returned `seq` as the next `since`. `limit` caps how many entries are returned (0 = unlimited). Requires Godot >= 4.5."""
    args: dict[str, Any] = {"since": since, "limit": limit}
    return _bridge("log", args)


@mcp.tool()
def log_probe(message: str = "probe", level: str = "info") -> dict[str, Any]:
    """Emit a standard output/error log from the editor process (`print`/`push_error`/`push_warning`) so it can be observed via `log_read`. Useful for testing log capture. `level` is `info`, `warning`, or `error`."""
    args: dict[str, Any] = {"message": message, "level": level}
    return _bridge("log_probe", args)


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
def create_scene(
    root_type: str,
    root_name: str,
    save_path: str,
    children: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Build a complete new scene in-memory from a declarative spec and save it to `save_path` as a .tscn, then return the serialized tree. Detached from the currently edited scene (no new-scene editor entry): it does not become the active scene and is not undoable. `children` is a nested list of `{"node_type", "node_name", "properties"?, "children"?}` dicts (properties follow the same values as `tree_set`). Overwrites an existing file at `save_path`."""
    args: dict[str, Any] = {"root_type": root_type, "root_name": root_name, "save_path": save_path}
    if children:
        args["children"] = children
    return _bridge("create_scene", args)


@mcp.tool()
def tree_move(path: str, parent_path: str = "/", index: int | None = None) -> dict[str, Any]:
    """Reparent the node at `path` under `parent_path`, optionally at child `index`. Undoable and marks the scene unsaved."""
    args: dict[str, Any] = {"path": path, "parent_path": parent_path}
    if index is not None:
        args["index"] = index
    return _bridge("move", args)


@mcp.tool()
def get_uid(path: str = "", uid: str = "") -> dict[str, Any]:
    """Look up a resource UID (Godot 4.4+). Pass exactly one of `path` (a res:// path) or `uid` (a uid:// string). Returns `{"path", "uid"}` for either direction; a path without a UID yields `"uid": null`."""
    args: dict[str, Any] = {}
    if path:
        args["path"] = path
    if uid:
        args["uid"] = uid
    return _bridge("get_uid", args)


@mcp.tool()
def update_project_uids(dry_run: bool = False) -> dict[str, Any]:
    """Assign a UID to every resource file in the project (res://) that lacks one, persisting `.uid` sidecar files (Godot 4.4+). Mirrors the editor's Project > Tools > 'Update UIDs'. `dry_run` previews the scan without writing. Returns `{"scanned", "already_had_uid", "generated", "skipped"}`."""
    args: dict[str, Any] = {"dry_run": dry_run}
    return _bridge("update_project_uids", args)


@mcp.tool()
def project_get_setting(path: str) -> dict[str, Any]:
    """Read a project setting from the live editor's project.godot. `path` is either an exact setting name (e.g. "application/config/name", returns `{"path", "value"}`) or a simple filter — a prefix or `*` glob (e.g. "application/*", returns `{"path", "count", "settings"}` for every match). Writing settings (project_set_setting) is intentionally not implemented (unsafe to mutate project.godot)."""
    return _bridge("get_setting", {"path": path})


def main() -> None:
    mcp.run()
