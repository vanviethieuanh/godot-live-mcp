# godot-live-mcp (MCP server)

Node-side MCP server for the [godot-live-mcp](../../) Godot Tree bridge. It
connects to the live scene-tree TCP bridge served by the Godot editor plugin
(default `127.0.0.1:41234`) and exposes the bridge ops as agent-facing MCP
tools over stdio.

Built with the official [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk).

## Tools

| Tool | Args | Bridge op |
|------|------|-----------|
| `tree_ping` | – | `ping` |
| `tree_editor` | – | `editor` |
| `tree_scene` | – | `scene` |
| `tree_query` | `path` | `query` |
| `tree_children` | `path` | `children` |
| `tree_props` | `path` | `props` |
| `tree_find` | `path? type? name? script? has_prop? path_pattern?` | `find` |
| `tree_inspect` | `path` | `inspect` |
| `tree_dump` | `path? depth?` | `tree` |
| `tree_set` | `path property value` | `set` |
| `tree_add` | `parent_path node_type node_name properties?` | `add` |
| `tree_remove` | `path` | `remove` |
| `tree_move` | `path parent_path index?` | `move` |
| `create_scene` | `root_type root_name save_path children?` | `create_scene` |

Mutations go through the editor's `EditorUndoRedoManager` (undoable with
Ctrl+Z, and the scene is automatically marked unsaved). Agent-made mutations
are tagged in the editor's History panel with `[agent]` (configurable via
Editor Settings → `addons/godot_tree/agent_undo_prefix`).

`create_scene` is the exception: it builds a new scene **detached** from the
currently edited scene (in-memory, saved straight to disk via `ResourceSaver`),
so it is not undoable, does not mark a scene unsaved, and is not opened as a new
editor scene (no new-scene entry point). `children` is a nested list of
`{"node_type", "node_name", "properties"?, "children"?}` dicts.

In opencode the tools are prefixed with the server name: `godot-live_tree_query`, etc.

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `GODOT_TREE_HOST` | `127.0.0.1` | Bridge host |
| `GODOT_TREE_PORT` | `41234` | Bridge port (must match the addon's Editor Setting) |
| `GODOT_TREE_TIMEOUT_MS` | `5000` | Per-request timeout |

## Development

```sh
uv sync          # create .venv and install deps (incl. dev)
uv run pytest    # run tests (fake TCP server, no Godot needed)
uv run godot-live-mcp   # run the stdio MCP server
uv run mcp dev src/godot_live_mcp/server.py  # MCP Inspector
```

## Publishing

```sh
uv build
uv publish      # publish to PyPI; then `uvx godot-live-mcp` works anywhere
```
