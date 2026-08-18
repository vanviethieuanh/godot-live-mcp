extends SceneTree

## TreeMutator.create_scene tests: builds a nested scene spec, verifies the tree,
## owner propagation, node count, the saved .tscn exists and can be instantiated.
## Run: godot --headless -s tests/tree_builder_test.gd

const TreeMutatorScript := preload("res://addons/godot_tree/tree_mutator.gd")
const SAVE_PATH := "/tmp/godot-test/tmp_create_scene_test.tscn"


func _init() -> void:
	var failed := false
	failed = _test_build_and_save() or failed
	failed = _test_error_cases() or failed
	_cleanup()
	print("TREE BUILDER TEST ", "PASS" if not failed else "FAIL")
	quit(0 if not failed else 1)


func _check(condition: bool, message: String, failed: Array) -> void:
	if not condition:
		push_error("FAIL: " + message)
		failed[0] = true


func _cleanup() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _test_build_and_save() -> bool:
	var failed := [false]
	var outcome: Array = TreeMutatorScript.create_scene({
		"root_type": "Node2D",
		"root_name": "City",
		"save_path": SAVE_PATH,
		"children": [
			{
				"node_type": "Node2D",
				"node_name": "Plaza",
				"properties": {"position": [10.0, 20.0]},
				"children": [
					{"node_type": "Sprite2D", "node_name": "Fountain"},
				],
			},
			{"node_type": "Node2D", "node_name": "Road"},
		],
	})
	_check(outcome[0].is_empty(), "create_scene should succeed: %s" % str(outcome[0]), failed)
	var result: Dictionary = outcome[1]
	_check(str(result.get("save_path", "")) == SAVE_PATH, "result reports save_path", failed)
	_check(int(result.get("node_count", -1)) == 4, "node_count includes root: %s" % str(result.get("node_count")), failed)
	_check(str(result.get("root", "")) == "Node2D", "result reports root type", failed)
	var tree: Dictionary = result.get("tree", {})
	_check(str(tree.get("name", "")) == "City", "tree root name", failed)
	var tree_children: Array = tree.get("children", [])
	_check(tree_children.size() == 2, "tree has two top-level children", failed)

	# The packed scene should load from disk and instantiate with owner set.
	_check(ResourceLoader.exists(SAVE_PATH), "saved .tscn exists", failed)
	var loaded: PackedScene = load(SAVE_PATH)
	_check(loaded != null, "saved .tscn loads", failed)
	if loaded != null:
		var inst: Node = loaded.instantiate()
		_check(inst != null, "saved scene instantiates", failed)
		if inst != null:
			var plaza: Node2D = inst.get_node_or_null("Plaza")
			_check(plaza != null, "Plaza child present", failed)
			if plaza != null:
				_check(plaza.position == Vector2(10, 20), "Plaza position applied: %s" % str(plaza.position), failed)
				_check(plaza.owner == inst, "Plaza owner is scene root", failed)
				_check(inst.get_node_or_null("Plaza/Fountain") != null, "nested Fountain present", failed)
		inst.free()
	return failed[0]


func _test_error_cases() -> bool:
	var failed := [false]
	_check(not TreeMutatorScript.create_scene({"root_type": "Node2D", "root_name": "X", "save_path": "res://x.gd"})[0].is_empty(),
		"non-tscn save_path errors", failed)
	_check(not TreeMutatorScript.create_scene({"root_type": "Node2D", "root_name": "", "save_path": SAVE_PATH})[0].is_empty(),
		"empty root_name errors", failed)
	_check(not TreeMutatorScript.create_scene({"root_type": "NotARealClass", "root_name": "X", "save_path": SAVE_PATH})[0].is_empty(),
		"unknown root_type errors", failed)
	var bad_children := TreeMutatorScript.create_scene({
		"root_type": "Node2D",
		"root_name": "X",
		"save_path": SAVE_PATH,
		"children": [{"node_type": "NotARealClass", "node_name": "Nope"}],
	})
	_check(not bad_children[0].is_empty(), "invalid child type errors: %s" % str(bad_children[0]), failed)
	return failed[0]
