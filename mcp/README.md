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
| `tree_scene` | – | `scene` |
| `tree_query` | `path` | `query` |
| `tree_children` | `path` | `children` |
| `tree_props` | `path` | `props` |
| `tree_find` | `path? type? name? script? has_prop?` | `find` |
| `tree_inspect` | `path` | `inspect` |

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
