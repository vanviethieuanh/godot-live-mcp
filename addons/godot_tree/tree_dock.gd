class_name TreeDock
extends VBoxContainer

const TreeServerScript := preload("res://addons/godot_tree/tree_server.gd")
const PORT_SETTING := "addons/godot_tree/port"
const DEFAULT_PORT := 41234
const POLL_INTERVAL_MSEC := 500

var server: TreeServerScript = null

var _dot: PanelContainer = null
var _dot_style: StyleBoxFlat = null
var _label: Label = null
var _port_dialog: ConfirmationDialog = null
var _port_spin: SpinBox = null
var _last_poll_ms: int = 0


func _ready() -> void:
	_dot_style = StyleBoxFlat.new()
	_dot_style.set_corner_radius_all(6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_dot = PanelContainer.new()
	_dot.custom_minimum_size = Vector2(12, 12)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_dot)
	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_label)
	var port_button := Button.new()
	port_button.text = "Port..."
	port_button.pressed.connect(_open_port_dialog)
	row.add_child(port_button)
	add_child(row)
	_build_port_dialog()
	_sync()


func _build_port_dialog() -> void:
	_port_dialog = ConfirmationDialog.new()
	_port_dialog.title = "Bridge Port"
	_port_dialog.ok_button_text = "Restart"
	_port_dialog.min_size = Vector2i(190, 100)
	var spin_box := SpinBox.new()
	spin_box.min_value = 1024
	spin_box.max_value = 65535
	spin_box.value = _current_port()
	spin_box.custom_minimum_size = Vector2(150, 0)
	_port_spin = spin_box
	_port_dialog.add_child(spin_box)
	_port_dialog.confirmed.connect(_on_port_confirmed)
	add_child(_port_dialog)


func _current_port() -> int:
	var settings := EditorInterface.get_editor_settings()
	if settings != null and settings.has_setting(PORT_SETTING):
		return int(settings.get_setting(PORT_SETTING))
	return DEFAULT_PORT


func _open_port_dialog() -> void:
	_port_spin.value = _current_port()
	_port_dialog.popup_centered(_port_dialog.min_size)


func _on_port_confirmed() -> void:
	var new_port := int(_port_spin.value)
	var settings := EditorInterface.get_editor_settings()
	if settings != null:
		settings.set_setting(PORT_SETTING, new_port)
	if server != null:
		server.restart(new_port)
	_sync()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_poll_ms < POLL_INTERVAL_MSEC:
		return
	_last_poll_ms = now
	_sync()


func refresh() -> void:
	_sync()


func _sync() -> void:
	if _dot == null or _dot_style == null or _label == null:
		return
	var listening := server != null and server.is_listening()
	var text := "Bridge: off"
	if server != null:
		text = "Bridge: %s:%d" % [server.bind_address, server.port]
		if not listening:
			text += " (in use)"
	_dot_style.bg_color = Color(0.36, 0.8, 0.36) if listening else Color(0.85, 0.3, 0.3)
	_dot.add_theme_stylebox_override("panel", _dot_style)
	_label.text = text
