extends SceneTree

## TreeHeadless tests: the headless scene-edit core used by tree_headless.gd —
## load a .tscn, mutate it through TreeMutator with a null UndoRedo (no editor),
## save it back with save_scene, then reload and confirm the change persisted.
## Run: godot --headless -s tests/tree_headless_test.gd

const TreeMutatorScript := preload("res://addons/godot_tree/tree_mutator.gd")
const TreeEngineScript := preload("res://addons/godot_tree/tree_engine.gd")
const TEST_PATH := "res://tmp_headless_test.tscn"


func _init() -> void:
	var failed := false
	failed = _test_mutate_and_save() or failed
	failed = _test_attach_script() or failed
	failed = _test_preserves_uid() or failed
	_cleanup()
	print("TREE HEADLESS TEST ", "PASS" if not failed else "FAIL")
	quit(0 if not failed else 1)


func _check(condition: bool, message: String, failed: Array) -> void:
	if not condition:
		push_error("FAIL: " + message)
		failed[0] = true


func _test_mutate_and_save() -> bool:
	var failed := [false]
	_cleanup()
	var created: Array = TreeMutatorScript.create_scene({
		"root_type": "Node2D",
		"root_name": "Level",
		"save_path": TEST_PATH,
		"children": [
			{"node_type": "Node2D", "node_name": "Enemies"},
			{"node_type": "Sprite2D", "node_name": "Banner"},
		],
	})
	_check(created[0].is_empty(), "create temp scene: %s" % str(created[0]), failed)

	# Mutate with a null UndoRedo (exactly how tree_headless invokes the mutator),
	# then save through the shared save_scene helper.
	var loaded: PackedScene = load(TEST_PATH)
	_check(loaded != null, "temp scene loads from disk", failed)
	if loaded == null:
		return failed[0]
	var root: Node = loaded.instantiate()
	var set_out: Array = TreeMutatorScript.set_property(root, null, {"path": "/Enemies", "property": "position", "value": [5.0, 7.0]})
	_check(set_out[0].is_empty(), "headless set: %s" % str(set_out[0]), failed)
	var add_out: Array = TreeMutatorScript.add(root, null, {"parent_path": "/Enemies", "node_type": "Node2D", "node_name": "Boss"})
	_check(add_out[0].is_empty(), "headless add: %s" % str(add_out[0]), failed)
	_check(TreeMutatorScript.save_scene(root, TEST_PATH).is_empty(), "save_scene succeeds", failed)

	# Reload from disk (bypassing the resource cache so we read the new file)
	# and confirm the mutations persisted.
	var reloaded: PackedScene = ResourceLoader.load(TEST_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
	_check(reloaded != null, "scene reloads after save", failed)
	if reloaded == null:
		return failed[0]
	var reloaded_root: Node = reloaded.instantiate()
	var enemies: Node2D = reloaded_root.get_node_or_null("Enemies")
	_check(enemies != null and enemies.position == Vector2(5, 7), "position persisted: %s" % str(enemies.get("position") if enemies else "missing"), failed)
	_check(reloaded_root.get_node_or_null("Enemies/Boss") != null, "added node persisted", failed)
	return failed[0]


func _test_attach_script() -> bool:
	var failed := [false]
	_cleanup()
	var created: Array = TreeMutatorScript.create_scene({
		"root_type": "Node2D",
		"root_name": "Level",
		"save_path": TEST_PATH,
		"children": [{"node_type": "Node", "node_name": "Marker"}],
	})
	_check(created[0].is_empty(), "create temp scene for attach: %s" % str(created[0]), failed)

	var loaded: PackedScene = load(TEST_PATH)
	if loaded == null:
		_check(false, "temp scene loads for attach", failed)
		return failed[0]
	var root: Node = loaded.instantiate()
	var out: Array = TreeMutatorScript.attach_script(root, null, {"path": "/Marker", "script": "res://tests/fixture_agent_node.gd"})
	_check(out[0].is_empty(), "headless attach_script: %s" % str(out[0]), failed)
	_check(TreeMutatorScript.save_scene(root, TEST_PATH).is_empty(), "save_scene after attach", failed)

	var reloaded: PackedScene = ResourceLoader.load(TEST_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
	var reloaded_root: Node = reloaded.instantiate() if reloaded != null else null
	var marker: Node = reloaded_root.get_node_or_null("Marker") if reloaded_root != null else null
	_check(marker != null and marker.get_script() != null, "script persisted after reload", failed)
	return failed[0]


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var uid_id := ResourceLoader.get_resource_uid(TEST_PATH)
	if uid_id != ResourceUID.INVALID_ID and ResourceUID.has_id(uid_id):
		ResourceUID.remove_id(uid_id)


## save_scene re-packs a fresh PackedScene, which would otherwise drop the scene's
## UID from the .tscn header. Register a UID for the test path, save through
## save_scene, and confirm the header still carries it.
func _test_preserves_uid() -> bool:
	var failed := [false]
	_cleanup()
	var created: Array = TreeMutatorScript.create_scene({
		"root_type": "Node2D",
		"root_name": "Level",
		"save_path": TEST_PATH,
		"children": [{"node_type": "Node2D", "node_name": "Child"}],
	})
	_check(created[0].is_empty(), "create uid scene: %s" % str(created[0]), failed)

	var uid_id := ResourceUID.create_id()
	ResourceUID.add_id(uid_id, TEST_PATH)
	var uid_text := ResourceUID.id_to_text(uid_id)

	var loaded: PackedScene = load(TEST_PATH)
	var root: Node = loaded.instantiate()
	var out: Array = TreeMutatorScript.set_property(root, null, {"path": "/Child", "property": "position", "value": [3.0, 4.0]})
	_check(out[0].is_empty(), "headless set for uid: %s" % str(out[0]), failed)
	_check(TreeMutatorScript.save_scene(root, TEST_PATH).is_empty(), "save_scene for uid succeeds", failed)

	var f := FileAccess.open(TEST_PATH, FileAccess.READ)
	var first_line := f.get_line() if f != null else ""
	_check(first_line.contains("uid="), "header preserves uid: %s" % first_line, failed)
	_check(first_line.contains(uid_text), "header uses the scene's uid: %s" % first_line, failed)
	return failed[0]
