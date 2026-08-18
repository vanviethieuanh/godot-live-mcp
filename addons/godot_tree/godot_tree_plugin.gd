@tool
extends EditorPlugin

const TreeServerScript := preload("res://addons/godot_tree/tree_server.gd")
const TreeMutatorScript := preload("res://addons/godot_tree/tree_mutator.gd")
const TreeDockScript := preload("res://addons/godot_tree/tree_dock.gd")
const PORT_SETTING := "addons/godot_tree/port"
const AGENT_PREFIX_SETTING := "addons/godot_tree/agent_undo_prefix"
const DEFAULT_AGENT_PREFIX := "[agent] "

var _server: TreeServerScript = null
var _dock: Variant = null
var _saved_version := -1


func _enter_tree() -> void:
	TreeMutatorScript.agent_action_prefix = _agent_prefix()
	_server = TreeServerScript.new()
	_server.root_provider = Callable(self, "_edited_scene_root")
	_server.undo_redo_provider = Callable(self, "_undo_manager")
	_server.modified_provider = Callable(self, "_scene_modified")
	_server.port = _bridge_port()
	add_child(_server)
	_server.start()
	_reset_saved_version()

	if _has_editor_dock():
		_create_dock()
	else:
		print("[GodotTree] EditorDock unavailable (Godot < 4.5); running bridge-only")

	scene_changed.connect(func(_path: String) -> void: _reset_saved_version())
	scene_changed.connect(_refresh_dock)
	scene_closed.connect(func(_path: String) -> void: _reset_saved_version())
	scene_closed.connect(func(_path: String) -> void: _refresh_dock())
	scene_saved.connect(func(_path: String) -> void: _reset_saved_version())
	scene_saved.connect(func(_path: String) -> void: _refresh_dock())


func _exit_tree() -> void:
	if _dock != null:
		remove_dock(_dock)
		remove_tool_menu_item("Scene Tree")
		_dock.queue_free()
		_dock = null
	if _server != null:
		_server.stop()
		_server.queue_free()
		_server = null


func _has_editor_dock() -> bool:
	return ClassDB.class_exists("EditorDock")


func _create_dock() -> void:
	var icon: Texture2D = load("res://addons/godot_tree/icon.svg")
	_dock = ClassDB.instantiate("EditorDock")
	_dock.title = "Scene Tree"
	if icon != null:
		_dock.dock_icon = icon
	_dock.default_slot = _dock.DOCK_SLOT_RIGHT_BL
	var content := TreeDockScript.new()
	content.server = _server
	_dock.add_child(content)
	add_dock(_dock)
	add_tool_menu_item("Scene Tree", Callable(self, "_open_dock"))


func _bridge_port() -> int:
	var settings := EditorInterface.get_editor_settings()
	if settings != null and settings.has_setting(PORT_SETTING):
		return int(settings.get_setting(PORT_SETTING))
	return 41234


func _agent_prefix() -> String:
	var settings := EditorInterface.get_editor_settings()
	if settings != null and settings.has_setting(AGENT_PREFIX_SETTING):
		return str(settings.get_setting(AGENT_PREFIX_SETTING))
	return DEFAULT_AGENT_PREFIX


func _edited_scene_root() -> Node:
	return get_editor_interface().get_edited_scene_root()


func _undo_manager() -> Variant:
	return get_editor_interface().get_editor_undo_redo()


func _scene_modified() -> bool:
	return _current_version() != _saved_version


func _reset_saved_version() -> void:
	_saved_version = _current_version()


func _current_version() -> int:
	var ur: Variant = get_editor_interface().get_editor_undo_redo()
	if ur == null:
		return 0
	var root: Node = _edited_scene_root()
	if root != null and ur.has_method("get_object_history_id") and ur.has_method("get_history_undo_redo"):
		var history_id: int = ur.get_object_history_id(root)
		var scene_ur: Variant = ur.get_history_undo_redo(history_id)
		if scene_ur != null and scene_ur.has_method("get_version"):
			return int(scene_ur.get_version())
	if ur.has_method("get_version"):
		return int(ur.get_version())
	return 0


func _refresh_dock(_arg: Variant = null) -> void:
	if _dock != null and _dock.get_child_count() > 0:
		var content: Node = _dock.get_child(0)
		if content.has_method("refresh"):
			content.call("refresh")


func _open_dock() -> void:
	if _dock != null:
		_dock.make_visible()
