class_name TreeHandlerInfo
extends RefCounted

## Bridge ops for high-level status/info: ping, scene and editor. Reads shared
## state off the TreeServer (root + modified flag) and formats the responses.

const TreeEngineScript := preload("res://addons/godot_tree/tree_engine.gd")


static func op_names() -> Array[String]:
	return ["ping", "scene", "editor"]


static func handle(server, op: String, args: Dictionary) -> Array:
	var root: Node = server.current_root()
	match op:
		"ping":
			return ["", {"pong": true, "scene": _scene_info(server, root)}]
		"scene":
			return ["", _scene_info(server, root)]
		"editor":
			return ["", _editor_info(root)]
	return ["unknown op: %s" % op, null]


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
