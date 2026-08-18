class_name TreeMutator
extends RefCounted

## Mutation core for the live scene bridge. Editor-independent: every function
## takes the scene root and an UndoRedo, so headless tests use a plain UndoRedo
## while the editor injects EditorUndoRedoManager (which also marks the scene
## unsaved). All mutations go through the undo/redo system.

const TreeEngineScript := preload("res://addons/godot_tree/tree_engine.gd")

## Prefix added to every undo action created through the bridge, so the editor's
## History panel distinguishes agent-made changes from human edits. Set from
## Editor Settings (`addons/godot_tree/agent_undo_prefix`); empty disables.
static var agent_action_prefix: String = "[agent] "

## Name of the most recently committed action (including prefix), for tests/tools.
static var last_action_name := ""


static func set_property(root: Node, undo_redo, params: Dictionary) -> Array:
	var node: Node = TreeEngineScript.resolve(root, str(params.get("path", "/")))
	if node == null:
		return ["node not found: %s" % str(params.get("path", "/")), null]
	var property := str(params.get("property", ""))
	if property.is_empty():
		return ["property is required", null]
	if not _is_settable(node, property):
		return ["property is not settable: %s" % property, null]
	var value: Variant
	if params.has("value"):
		value = _json_to_variant(node, property, params["value"])
	else:
		value = null
	var old_value: Variant = node.get(property)
	var ur := _undo_redo(undo_redo)
	_create_action(ur, "Set %s.%s" % [node.name, property])
	ur.add_do_property(node, property, value)
	ur.add_undo_property(node, property, old_value)
	ur.commit_action()
	return ["", {
		"path": TreeEngineScript.path_of(root, node),
		"property": property,
		"value": TreeEngineScript._json_value(value),
	}]


static func add(root: Node, undo_redo, params: Dictionary) -> Array:
	var parent_path := str(params.get("parent_path", "/"))
	var parent := TreeEngineScript.resolve(root, parent_path)
	if parent == null:
		return ["parent node not found: %s" % parent_path, null]
	var node_type := str(params.get("node_type", ""))
	if not _valid_type_name(node_type):
		return ["invalid node type: %s" % node_type, null]
	var node_name := str(params.get("node_name", ""))
	if node_name.is_empty():
		return ["node name is required", null]
	var new_node := _instantiate(node_type)
	if new_node == null:
		return ["could not instantiate node type: %s" % node_type, null]
	new_node.name = node_name
	if params.has("properties") and params["properties"] is Dictionary:
		var props := params["properties"] as Dictionary
		for key: String in props:
			if _is_settable(new_node, key):
				new_node.set(key, _json_to_variant(new_node, key, props[key]))
	var ur := _undo_redo(undo_redo)
	_create_action(ur, "Add %s" % node_name)
	_do_method(ur, parent, "add_child", [new_node])
	_do_method(ur, new_node, "set_owner", [root])
	_undo_method(ur, parent, "remove_child", [new_node])
	ur.add_do_reference(new_node)
	ur.add_undo_reference(new_node)
	ur.commit_action()
	return ["", {"path": TreeEngineScript.path_of(root, new_node)}]


static func remove(root: Node, undo_redo, params: Dictionary) -> Array:
	var path := str(params.get("path", ""))
	var node: Node = TreeEngineScript.resolve(root, path)
	if node == null:
		return ["node not found: %s" % path, null]
	if node == root:
		return ["cannot remove scene root", null]
	var parent: Node = node.get_parent()
	if parent == null:
		return ["node has no parent", null]
	var index: int = node.get_index()
	var result_path := TreeEngineScript.path_of(root, node)
	var ur := _undo_redo(undo_redo)
	_create_action(ur, "Remove %s" % node.name)
	_do_method(ur, parent, "remove_child", [node])
	_undo_method(ur, parent, "add_child", [node])
	_undo_method(ur, parent, "move_child", [node, index])
	_undo_method(ur, node, "set_owner", [root])
	ur.add_do_reference(node)
	ur.add_undo_reference(node)
	ur.commit_action()
	return ["", {"path": result_path, "removed": true}]


static func move(root: Node, undo_redo, params: Dictionary) -> Array:
	var path := str(params.get("path", ""))
	var node: Node = TreeEngineScript.resolve(root, path)
	if node == null:
		return ["node not found: %s" % path, null]
	if node == root:
		return ["cannot move scene root", null]
	var parent_path := str(params.get("parent_path", "/"))
	var new_parent: Node = TreeEngineScript.resolve(root, parent_path)
	if new_parent == null:
		return ["parent node not found: %s" % parent_path, null]
	if new_parent == node or node.is_ancestor_of(new_parent):
		return ["cannot move node into itself or its own descendant", null]
	var old_parent: Node = node.get_parent()
	if old_parent == null:
		return ["node has no parent", null]
	var old_index: int = node.get_index()
	var index: Variant = params.get("index", null)
	if index != null:
		index = int(index)
	var ur := _undo_redo(undo_redo)
	_create_action(ur, "Move %s" % node.name)
	_do_method(ur, old_parent, "remove_child", [node])
	_do_method(ur, new_parent, "add_child", [node])
	if index != null:
		_do_method(ur, new_parent, "move_child", [node, int(index)])
	_undo_method(ur, new_parent, "remove_child", [node])
	_undo_method(ur, old_parent, "add_child", [node])
	_undo_method(ur, old_parent, "move_child", [node, old_index])
	ur.add_do_reference(node)
	ur.add_undo_reference(node)
	ur.commit_action()
	return ["", {"path": TreeEngineScript.path_of(root, node), "parent": parent_path}]


static func _undo_redo(ur) -> Variant:
	if ur != null:
		return ur
	return UndoRedo.new()


static func _create_action(ur, name: String) -> void:
	var display_name := agent_action_prefix + name
	if ur is EditorUndoRedoManager:
		ur.create_action(display_name)  # mark_unsaved defaults to true
	else:
		ur.create_action(display_name)
	last_action_name = display_name


static func _do_method(ur, object: Object, method: String, args: Array = []) -> void:
	var urm := ur as EditorUndoRedoManager
	if urm != null:
		var call_args: Array = [object, method]
		call_args.append_array(args)
		urm.callv("add_do_method", call_args)
	else:
		ur.add_do_method(Callable(object, method).bindv(args))


static func _undo_method(ur, object: Object, method: String, args: Array = []) -> void:
	var urm := ur as EditorUndoRedoManager
	if urm != null:
		var call_args: Array = [object, method]
		call_args.append_array(args)
		urm.callv("add_undo_method", call_args)
	else:
		ur.add_undo_method(Callable(object, method).bindv(args))


static func _valid_type_name(name: String) -> bool:
	if name.is_empty():
		return false
	var first := name.substr(0, 1)
	if not _is_id_char(first, false):
		return false
	for i in range(1, name.length()):
		if not _is_id_char(name[i], true):
			return false
	return true


static func _is_id_char(ch: String, allow_digit: bool) -> bool:
	if ch >= "A" and ch <= "Z":
		return true
	if ch >= "a" and ch <= "z":
		return true
	if ch == "_":
		return true
	if allow_digit and ch >= "0" and ch <= "9":
		return true
	return false


static func _instantiate(node_type: String) -> Node:
	if ClassDB.class_exists(node_type) and ClassDB.can_instantiate(node_type):
		var obj: Object = ClassDB.instantiate(node_type)
		if obj is Node:
			return obj
	var script := _script_by_class(node_type)
	if script is GDScript:
		var instance: Variant = script.new()
		if instance is Node:
			return instance
	return null


static func _script_by_class(class_name_value: String) -> Script:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if str(entry.get("class", "")) == class_name_value:
			return load(str(entry.get("path", ""))) as Script
	return null


static func _is_settable(node: Node, property: String) -> bool:
	if property == "script" or property == "owner":
		return false
	for entry: Dictionary in node.get_property_list():
		if str(entry.get("name", "")) == property:
			var usage: int = int(entry.get("usage", 0))
			if not usage & PROPERTY_USAGE_EDITOR:
				return false
			return not bool(usage & PROPERTY_USAGE_READ_ONLY)
	return false


static func _json_to_variant(node: Node, property: String, value: Variant) -> Variant:
	if value is String:
		var s := value as String
		if s.begins_with("res://"):
			var res: Variant = load(s)
			if res != null:
				return res
	var current: Variant = node.get(property)
	match typeof(current):
		TYPE_VECTOR2:
			return _as_vector2(value)
		TYPE_VECTOR3:
			return _as_vector3(value)
		TYPE_COLOR:
			return _as_color(value)
		TYPE_NODE_PATH:
			return NodePath(str(value))
		TYPE_INT:
			return _as_int(value)
		TYPE_FLOAT:
			return _as_float(value)
		TYPE_BOOL:
			if value is String:
				return str(value).to_lower() in ["true", "1", "yes"]
			return bool(value)
	return value


static func _as_int(value: Variant) -> int:
	if value is String:
		return int(str(value).strip_edges())
	return int(value)


static func _as_float(value: Variant) -> float:
	if value is String:
		return float(str(value).strip_edges())
	return float(value)


static func _as_vector2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() == 2:
		var arr := value as Array
		return Vector2(float(arr[0]), float(arr[1]))
	var parsed: Variant = str_to_var(str(value))
	if parsed is Vector2:
		return parsed
	return Vector2.ZERO


static func _as_vector3(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() == 3:
		var arr := value as Array
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	var parsed: Variant = str_to_var(str(value))
	if parsed is Vector3:
		return parsed
	return Vector3.ZERO


static func _as_color(value: Variant) -> Color:
	if value is Array:
		var arr := value as Array
		if arr.size() == 3:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]))
		if arr.size() == 4:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
	return Color(str(value))
