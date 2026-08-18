# godot-live-mcp

Agent-facing scene tree inspector for the Godot editor: query the **live,
in-memory** edited scene over a loopback TCP bridge, so the editor's RAM is
always the source of truth (the `.tscn` file only changes on explicit save).

## Architecture

```
agent / CLI  ──TCP NDJSON 127.0.0.1:41234──▶  Godot editor (running)
    tree_cli.gd                                   addons/godot_tree/
                                                   ├─ tree_engine.gd   query core (editor-independent)
                                                   ├─ tree_server.gd   loopback TCP host + dispatch
                                                   ├─ tree_dock.gd     minimal status dock (dot + port)
                                                   └─ godot_tree_plugin.gd
```

## Usage

Open this project in the Godot editor (plugin auto-starts the bridge on
`127.0.0.1:41234`), then from any terminal:

```sh
godot --headless -s addons/godot_tree/tree_cli.gd -- ping
godot --headless -s addons/godot_tree/tree_cli.gd -- scene
godot --headless -s addons/godot_tree/tree_cli.gd -- children /City
godot --headless -s addons/godot_tree/tree_cli.gd -- query /City/Chapel 8
godot --headless -s addons/godot_tree/tree_cli.gd -- find --type Node2D
godot --headless -s addons/godot_tree/tree_cli.gd -- find --name "Office*"
godot --headless -s addons/godot_tree/tree_cli.gd -- props /City/Office 0
godot --headless -s addons/godot_tree/tree_cli.gd -- inspect /City/Chapel 8
```

Port override: Editor Settings → `addons/godot_tree/port`, or restart the
bridge from the dock ("Port..." button). Nodes that implement
`agent_inspect() -> Dictionary` get semantic output via the `inspect` op.

## Tests

```sh
godot --headless -s tests/tree_engine_test.gd   # query core
godot --headless -s tests/tree_server_test.gd   # TCP round trip + lifecycle
godot --headless -s tests/tree_dock_test.gd     # dock status smoke test
```

## Protocol

Newline-delimited JSON over TCP. Request:

```json
{"id": 1, "op": "query", "args": {"path": "/City"}}
```

Response: `{"id": 1, "ok": true, "result": {...}}` or `{"id": 1, "ok": false, "error": "..."}`.

Ops: `ping`, `scene`, `query`, `children`, `props`, `find`, `inspect`.

## Next steps

- Mutations (`set`/`add`/`remove`) via `EditorUndoRedoManager` + `mark_scene_as_unsaved()`
- MCP adapter (thin bridge over the same TCP protocol)
