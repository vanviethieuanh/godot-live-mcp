class_name TreeHandlerInfo
extends RefCounted

## Bridge ops for high-level status/info: ping, scene and editor. Reads shared
## state off the TreeServer (root + modified flag) and formats the responses.

const TreeEngineScript := preload("res://addons/godot_tree/tree_engine.gd")


static func op_names() -> Array[String]:
	return ["ping", "scene", "editor", "open_scenes", "focus_scene"]


static func handle(server, op: String, args: Dictionary) -> Array:
	var root: Node = server.current_root()
	match op:
		"ping":
			return ["", {"pong": true, "scene": _scene_info(server, root)}]
		"scene":
			return ["", _scene_info(server, root)]
		"editor":
			return ["", _editor_info(root)]
		"open_scenes":
			return ["", _open_scenes()]
		"focus_scene":
			return ["", _focus_scene(str(args.get("path", "")))]
	return ["unknown op: %s" % op, null]


## Make the scene at `path` the edited scene so the bridge operates on it (its
## in-memory copy becomes the source of truth). Editor-only; no-op headless.
static func _focus_scene(path: String) -> Dictionary:
	if path.is_empty() or not Engine.is_editor_hint():
		return {"scene": path, "focused": false}
	EditorInterface.open_scene_from_path(path)
	return {"scene": path, "focused": true}


## List every scene currently open in the editor as a path -> summary map, plus
## the raw paths. Only meaningful in the editor (EditorInterface is unavailable
## headless); degrades to an empty list otherwise.
static func _open_scenes() -> Dictionary:
	if not Engine.is_editor_hint():
		return {"paths": [], "scenes": {}}
	var paths: PackedStringArray = EditorInterface.get_open_scenes()
	var roots: Array = EditorInterface.get_open_scene_roots()
	var scenes: Dictionary = {}
	for i in paths.size():
		var root: Node = roots[i] if i < roots.size() else null
		var summary := {"name": "", "node_count": 0}
		if root != null:
			summary = {
				"name": str(root.name),
				"node_count": TreeEngineScript.node_count(root),
			}
		scenes[paths[i]] = summary
	return {"paths": paths, "scenes": scenes}


static func _scene_info(server, root: Node) -> Dictionary:
	if root == null:
		return {"loaded": false}
	var out := {
		"loaded": true,
		"name": str(root.name),
		"scene_file_path": root.scene_file_path,
		"children_count": root.get_child_count(),
		"root": {
			"name": str(root.name),
			"type": root.get_class(),
		},
		"node_count": TreeEngineScript.node_count(root),
		"modified": server.is_modified(),
	}
	return out


static func _editor_info(root: Node) -> Dictionary:
	var version: Dictionary = Engine.get_version_info()
	var current_scene := ""
	if root != null:
		current_scene = root.scene_file_path
	return {
		"godot_version": str(version.get("string", "")),
		"project_name": str(ProjectSettings.get_setting("application/config/name", "")),
		"project_path": ProjectSettings.globalize_path("res://"),
		"current_scene": current_scene,
	}
