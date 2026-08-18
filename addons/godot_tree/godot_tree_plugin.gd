@tool
extends EditorPlugin

const TreeServerScript := preload("res://addons/godot_tree/tree_server.gd")
const TreeDockScript := preload("res://addons/godot_tree/tree_dock.gd")
const PORT_SETTING := "addons/godot_tree/port"

var _server: TreeServerScript = null
var _dock: EditorDock = null


func _enter_tree() -> void:
	_server = TreeServerScript.new()
	_server.root_provider = Callable(self, "_edited_scene_root")
	_server.port = _bridge_port()
	add_child(_server)
	_server.start()

	var icon: Texture2D = load("res://addons/godot_tree/icon.svg")
	_dock = EditorDock.new()
	_dock.title = "Scene Tree"
	if icon != null:
		_dock.dock_icon = icon
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	var content := TreeDockScript.new()
	content.server = _server
	_dock.add_child(content)
	add_dock(_dock)
	add_tool_menu_item("Scene Tree", Callable(self, "_open_dock"))

	scene_changed.connect(_refresh_dock)
	scene_closed.connect(func(_path: String) -> void: _refresh_dock())
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


func _bridge_port() -> int:
	var settings := EditorInterface.get_editor_settings()
	if settings != null and settings.has_setting(PORT_SETTING):
		return int(settings.get_setting(PORT_SETTING))
	return 41234


func _edited_scene_root() -> Node:
	return get_editor_interface().get_edited_scene_root()


func _refresh_dock(_arg: Variant = null) -> void:
	if _dock != null and _dock.get_child_count() > 0:
		var content: Node = _dock.get_child(0)
		if content.has_method("refresh"):
			content.call("refresh")


func _open_dock() -> void:
	if _dock != null:
		_dock.make_visible()
