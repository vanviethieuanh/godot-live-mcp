extends SceneTree

## Dock smoke test: instantiates the minimal TreeDock headless with a real
## TreeServer and checks the status dot + label react to listen state.
## Run: godot --headless -s tests/tree_dock_test.gd

const Dock := preload("res://addons/godot_tree/tree_dock.gd")
const Server := preload("res://addons/godot_tree/tree_server.gd")
const TEST_PORT := 41843


func _init() -> void:
	process_frame.connect(_on_first_frame)


func _on_first_frame() -> void:
	process_frame.disconnect(_on_first_frame)
	var failed := false
	var scene := Node.new()
	scene.name = "Scene"
	var server := Server.new()
	server.root_provider = func() -> Node: return scene
	server.port = TEST_PORT
	root.add_child(server)
	if server.start() != OK:
		push_error("FAIL: server start")
		failed = true

	var dock := Dock.new()
	dock.server = server
	root.add_child(dock)

	if not _label_contains(dock, str(TEST_PORT)):
		push_error("FAIL: label missing port %d (got: %s)" % [TEST_PORT, _label_text(dock)])
		failed = true
	if not _dot_is_green(dock):
		push_error("FAIL: dot not green while listening")
		failed = true

	server.stop()
	dock.refresh()

	if _dot_is_green(dock):
		push_error("FAIL: dot still green after stop")
		failed = true
	if not _label_contains(dock, "off") and not _label_contains(dock, "in use"):
		push_error("FAIL: label not updated after stop (got: %s)" % _label_text(dock))
		failed = true

	dock.queue_free()
	server.queue_free()
	print("TREE DOCK TEST ", "PASS" if not failed else "FAIL")
	quit(0 if not failed else 1)


func _label(dock: Dock) -> Label:
	for child: Node in dock.get_children():
		var box := child as HBoxContainer
		if box == null:
			continue
		for item: Node in box.get_children():
			if item is Label:
				return item as Label
	return null


func _label_text(dock: Dock) -> String:
	var lbl := _label(dock)
	return lbl.text if lbl != null else ""


func _label_contains(dock: Dock, needle: String) -> bool:
	return _label_text(dock).contains(needle)


func _dot_is_green(dock: Dock) -> bool:
	for child: Node in dock.get_children():
		var box := child as HBoxContainer
		if box == null:
			continue
		for item: Node in box.get_children():
			var panel := item as PanelContainer
			if panel == null:
				continue
			var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
			if style != null and style.bg_color.g > 0.6 and style.bg_color.r < 0.6:
				return true
	return false
