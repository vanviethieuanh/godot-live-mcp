extends SceneTree

## Headless (no-editor) scene editor. Loads a .tscn from disk, runs one
## bridge-style op against it via TreeMutator/TreeEngine, re-packs and saves the
## scene for write ops, then prints an NDJSON result line. Used by the MCP
## server to read/mutate scenes that are not currently open in the editor.
##
## Run: godot --headless --path <project> -s addons/godot_tree/tree_headless.gd -- <scene_path> <op> [--args <json>]
## Ops: scene | tree | query | children | props | inspect | find |
##      set | add | remove | move | attach_script
## When `--args` is omitted, positional args build the op args (see _parse_args).

const TreeMutatorScript := preload("res://addons/godot_tree/tree_mutator.gd")
const TreeEngineScript := preload("res://addons/godot_tree/tree_engine.gd")
const TreeProjectFilesScript := preload("res://addons/godot_tree/tree_project_files.gd")
const TreeProjectSummaryScript := preload("res://addons/godot_tree/tree_project_summary.gd")

var _scene_path := ""
var _op := "scene"
var _args: Dictionary = {}


func _init() -> void:
	if not _parse_args():
		return
	var outcome := _run()
	var resp := {"id": 1, "ok": outcome[0].is_empty()}
	if outcome[0].is_empty():
		resp["result"] = outcome[1]
	else:
		resp["error"] = outcome[0]
	print(JSON.stringify(resp))
	quit(0 if outcome[0].is_empty() else 1)


func _parse_args() -> bool:
	var args := OS.get_cmdline_user_args()
	var positional: Array[String] = []
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg == "--args" and i + 1 < args.size():
			var parsed: Variant = JSON.parse_string(args[i + 1])
			if parsed is Dictionary:
				_args = parsed
			else:
				printerr("ERROR: --args must be a JSON object")
				quit(1)
				return false
			i += 2
			continue
		if arg == "--path" and i + 1 < args.size():
			_args["path"] = args[i + 1]
			i += 2
			continue
		if arg == "--kind" and i + 1 < args.size():
			_args["kind"] = args[i + 1]
			i += 2
			continue
		if arg == "--pattern" and i + 1 < args.size():
			_args["pattern"] = args[i + 1]
			i += 2
			continue
		if arg == "--depth" and i + 1 < args.size():
			_args["depth"] = int(args[i + 1])
			i += 2
			continue
		if arg == "--recursive":
			_args["recursive"] = true
			i += 1
			continue
		if arg == "--no-recursive":
			_args["recursive"] = false
			i += 1
			continue
		if arg == "--include-dependencies":
			_args["include_dependencies"] = true
			i += 1
			continue
		if arg == "--no-include-dependencies":
			_args["include_dependencies"] = false
			i += 1
			continue
		if arg.begins_with("--"):
			printerr("ERROR: unknown flag: %s" % arg)
			quit(1)
			return false
		positional.append(arg)
		i += 1
	if positional.size() < 1:
		printerr("ERROR: first positional argument is required (scene_path for scene ops, or operation name)")
		quit(1)
		return false
	# Scene ops require a scene path first; resource/project ops may start with the
	# operation name and omit the scene path entirely.
	_op = positional[0]
	if _scene_op_requires_scene(_op):
		if positional.size() < 2:
			printerr("ERROR: scene_path is required for %s" % _op)
			quit(1)
			return false
		_scene_path = positional[0]
		_op = positional[1] if positional.size() > 1 else "scene"
		if _args.is_empty() and positional.size() > 2:
			_build_args_from_positional(positional.slice(2))
	else:
		if _args.is_empty():
			_build_args_from_positional(positional.slice(1))
	return true


static func _scene_op_requires_scene(op: String) -> bool:
	return op not in ["project_files", "resource_summary"]


## Build op args from trailing positional values when --args was not given,
## mirroring tree_cli's positional layout for the common ops.
func _build_args_from_positional(pos: Array[String]) -> void:
	match _op:
		"set":
			_args["path"] = pos[0] if pos.size() > 0 else "/"
			_args["property"] = pos[1] if pos.size() > 1 else ""
		"add":
			_args["parent_path"] = pos[0] if pos.size() > 0 else "/"
			_args["node_type"] = pos[1] if pos.size() > 1 else ""
			_args["node_name"] = pos[2] if pos.size() > 2 else ""
		"remove", "move", "query", "children", "props", "inspect":
			_args["path"] = pos[0] if pos.size() > 0 else "/"
		"attach_script":
			_args["path"] = pos[0] if pos.size() > 0 else "/"
			_args["script"] = pos[1] if pos.size() > 1 else ""
		"tree":
			_args["path"] = pos[0] if pos.size() > 0 else "/"
			if pos.size() > 1:
				_args["depth"] = int(pos[1])
		"move":
			_args["parent_path"] = pos[1] if pos.size() > 1 else "/"
		"project_files":
			if pos.size() > 0:
				_args["path"] = pos[0]
		"resource_summary":
			if pos.size() > 0:
				_args["path"] = pos[0]


func _run() -> Array:
	if _op == "project_files":
		return TreeProjectFilesScript.project_files(_args)
	if _op == "resource_summary":
		return TreeProjectSummaryScript.resource_summary(_args)
	var scene: PackedScene = load(_scene_path)
	if scene == null:
		return ["cannot load scene: %s" % _scene_path, null]
	var root := scene.instantiate()
	if root == null:
		return ["cannot instantiate scene: %s" % _scene_path, null]
	match _op:
		"scene":
			return ["", _scene_info(root)]
		"tree":
			var tree_root: Node = TreeEngineScript.resolve(root, str(_args.get("path", "/")))
			if tree_root == null:
				return ["node not found: %s" % str(_args.get("path", "/")), null]
			var depth := clampi(int(_args.get("depth", 2)), 0, 10)
			return ["", TreeEngineScript.tree(root, tree_root, depth, 0)]
		"query":
			return _read(root, func(node: Node) -> Variant: return TreeEngineScript.node_summary(node, root))
		"children":
			return _read(root, func(node: Node) -> Variant: return TreeEngineScript.children(node, root))
		"props":
			return _read(root, func(node: Node) -> Variant: return TreeEngineScript.props(node))
		"inspect":
			var outcome: Array = _read(root, func(node: Node) -> Variant: return TreeEngineScript.inspect(node))
			if outcome[0].is_empty() and outcome[1] == null:
				return ["", {"agent_inspect": false}]
			return outcome
		"find":
			var search_root: Node = TreeEngineScript.resolve(root, str(_args.get("path", "/")))
			if search_root == null:
				return ["search root not found: %s" % str(_args.get("path", "/")), null]
			var filters: Dictionary = {}
			for key: String in TreeEngineScript.FILTER_KEYS:
				if _args.has(key):
					filters[key] = str(_args[key])
			return ["", TreeEngineScript.find_nodes(root, search_root, filters)]
		"set":
			return _write(root, TreeMutatorScript.set_property(root, null, _args))
		"add":
			return _write(root, TreeMutatorScript.add(root, null, _args))
		"remove":
			return _write(root, TreeMutatorScript.remove(root, null, _args))
		"move":
			return _write(root, TreeMutatorScript.move(root, null, _args))
		"attach_script":
			return _write(root, TreeMutatorScript.attach_script(root, null, _args))
	return ["unknown op: %s" % _op, null]


func _read(root: Node, fn: Callable) -> Array:
	var node: Node = TreeEngineScript.resolve(root, str(_args.get("path", "/")))
	if node == null:
		return ["node not found: %s" % str(_args.get("path", "/")), null]
	return ["", fn.call(node)]


## Run a mutation, save the scene back to disk, and enrich the result with the
## saved path and serialized tree so the response matches the live bridge shape.
func _write(root: Node, outcome: Array) -> Array:
	if not outcome[0].is_empty():
		return outcome
	var save_err := TreeMutatorScript.save_scene(root, _scene_path)
	if not save_err.is_empty():
		return [save_err, null]
	var result: Dictionary = outcome[1] if outcome[1] is Dictionary else {}
	result["saved"] = _scene_path
	result["tree"] = TreeEngineScript.tree(root, root, 32, 0)
	return ["", result]


func _scene_info(root: Node) -> Dictionary:
	return {
		"loaded": true,
		"name": str(root.name),
		"scene_file_path": _scene_path,
		"root": {
			"name": str(root.name),
			"type": root.get_class(),
		},
		"node_count": TreeEngineScript.node_count(root),
		"modified": false,
		"tree": TreeEngineScript.tree(root, root, 32, 0),
	}
