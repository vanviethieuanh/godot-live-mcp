extends SceneTree

## TreeMutator tests: set/add/remove/move with do/undo/redo on a hand-built tree
## using a plain UndoRedo (the editor injects EditorUndoRedoManager instead).
## Run: godot --headless -s tests/tree_mutator_test.gd

const TreeMutatorScript := preload("res://addons/godot_tree/tree_mutator.gd")
const TreeEngineScript := preload("res://addons/godot_tree/tree_engine.gd")
const AgentFixture := preload("res://tests/fixture_agent_node.gd")


func _init() -> void:
	var failed := false
	failed = _test_add() or failed
	failed = _test_add_with_properties() or failed
	failed = _test_set() or failed
	failed = _test_remove() or failed
	failed = _test_move() or failed
	failed = _test_errors() or failed
	failed = _test_action_naming() or failed
	print("TREE MUTATOR TEST ", "PASS" if not failed else "FAIL")
	quit(0 if not failed else 1)


func _build_scene() -> Node:
	var scene := Node.new()
	scene.name = "Scene"
	var building := Node2D.new()
	building.name = "Building"
	scene.add_child(building)
	var roof := Node.new()
	roof.name = "Roof"
	building.add_child(roof)
	var agent := AgentFixture.new()
	agent.name = "Agent"
	scene.add_child(agent)
	return scene


func _check(condition: bool, message: String, failed: Array) -> void:
	if not condition:
		push_error("FAIL: " + message)
		failed[0] = true


func _test_add() -> bool:
	var failed := [false]
	var scene := _build_scene()
	var ur := UndoRedo.new()
	var outcome: Array = TreeMutatorScript.add(scene, ur, {
		"parent_path": "/",
		"node_type": "Node2D",
		"node_name": "NewNode",
	})
	_check(outcome[0].is_empty(), "add should succeed: %s" % str(outcome[0]), failed)
	var new_node: Node = scene.get_node_or_null("NewNode")
	_check(new_node != null, "added node exists", failed)
	_check(new_node.owner == scene, "added node owner is root", failed)
	ur.undo()
	_check(scene.get_node_or_null("NewNode") == null, "undo removes node", failed)
	ur.redo()
	new_node = scene.get_node_or_null("NewNode")
	_check(new_node != null and new_node.owner == scene, "redo restores node with owner", failed)
	return failed[0]


func _test_add_with_properties() -> bool:
	var failed := [false]
	var scene := _build_scene()
	var ur := UndoRedo.new()
	var outcome: Array = TreeMutatorScript.add(scene, ur, {
		"parent_path": "/",
		"node_type": "Node2D",
		"node_name": "Moved",
		"properties": {"position": [10.0, 20.0]},
	})
	_check(outcome[0].is_empty(), "add with properties should succeed: %s" % str(outcome[0]), failed)
	var new_node: Node = scene.get_node_or_null("Moved")
	_check(new_node != null and (new_node as Node2D).position == Vector2(10, 20),
		"properties applied on add: %s" % str(new_node.get("position") if new_node else "missing"), failed)
	return failed[0]


func _test_set() -> bool:
	var failed := [false]
	var scene := _build_scene()
	var ur := UndoRedo.new()
	var outcome: Array = TreeMutatorScript.set_property(scene, ur, {
		"path": "/Building",
		"property": "position",
		"value": [5.0, 6.0],
	})
	_check(outcome[0].is_empty(), "set should succeed: %s" % str(outcome[0]), failed)
	var building: Node2D = scene.get_node("Building")
	_check(building.position == Vector2(5, 6), "set applied: %s" % str(building.position), failed)
	ur.undo()
	_check(building.position == Vector2.ZERO, "undo restores old value: %s" % str(building.position), failed)
	ur.redo()
	_check(building.position == Vector2(5, 6), "redo reapplies value", failed)

	var agent: Node = scene.get_node("Agent")
	outcome = TreeMutatorScript.set_property(scene, ur, {"path": "/Agent", "property": "speed", "value": 42})
	_check(outcome[0].is_empty(), "set int should succeed: %s" % str(outcome[0]), failed)
	_check(int(agent.get("speed")) == 42, "int property set", failed)
	ur.undo()
	_check(int(agent.get("speed")) == 5, "int property undo restores", failed)
	return failed[0]


func _test_remove() -> bool:
	var failed := [false]
	var scene := _build_scene()
	var ur := UndoRedo.new()
	var outcome: Array = TreeMutatorScript.remove(scene, ur, {"path": "/Building/Roof"})
	_check(outcome[0].is_empty(), "remove should succeed: %s" % str(outcome[0]), failed)
	_check(scene.get_node_or_null("Building/Roof") == null, "node removed", failed)
	ur.undo()
	var roof: Node = scene.get_node_or_null("Building/Roof")
	_check(roof != null, "undo restores node", failed)
	if roof != null:
		_check(roof.owner == scene, "undo restores owner", failed)
	return failed[0]


func _test_move() -> bool:
	var failed := [false]
	var scene := _build_scene()
	var ur := UndoRedo.new()
	var outcome: Array = TreeMutatorScript.move(scene, ur, {"path": "/Building/Roof", "parent_path": "/"})
	_check(outcome[0].is_empty(), "move should succeed: %s" % str(outcome[0]), failed)
	var roof: Node = scene.get_node_or_null("Roof")
	_check(roof != null and roof.get_parent() == scene, "node moved to root", failed)
	ur.undo()
	roof = scene.get_node_or_null("Building/Roof")
	_check(roof != null, "undo restores parent", failed)
	ur.redo()
	_check(scene.get_node_or_null("Roof") != null, "redo reapplies move", failed)
	return failed[0]


func _test_action_naming() -> bool:
	var failed := [false]
	var scene := _build_scene()
	var ur := UndoRedo.new()
	TreeMutatorScript.agent_action_prefix = "[agent] "
	TreeMutatorScript.add(scene, ur, {"parent_path": "/", "node_type": "Node2D", "node_name": "Named"})
	_check(TreeMutatorScript.last_action_name == "[agent] Add Named",
		"action name prefixed: %s" % TreeMutatorScript.last_action_name, failed)
	TreeMutatorScript.set_property(scene, ur, {"path": "/Building", "property": "position", "value": [1.0, 2.0]})
	_check(TreeMutatorScript.last_action_name.begins_with("[agent] Set "),
		"set action prefixed: %s" % TreeMutatorScript.last_action_name, failed)
	TreeMutatorScript.agent_action_prefix = ""
	TreeMutatorScript.remove(scene, ur, {"path": "/Building/Roof"})
	_check(TreeMutatorScript.last_action_name == "Remove Roof",
		"empty prefix disables tagging: %s" % TreeMutatorScript.last_action_name, failed)
	TreeMutatorScript.agent_action_prefix = "[agent] "
	return failed[0]


func _test_errors() -> bool:
	var failed := [false]
	var scene := _build_scene()
	var ur := UndoRedo.new()
	_check(not TreeMutatorScript.set_property(scene, ur, {"path": "/Missing", "property": "x", "value": 1})[0].is_empty(),
		"set on missing path errors", failed)
	_check(not TreeMutatorScript.set_property(scene, ur, {"path": "/Building", "property": "nope", "value": 1})[0].is_empty(),
		"set on unknown property errors", failed)
	_check(not TreeMutatorScript.add(scene, ur, {"parent_path": "/Missing", "node_type": "Node2D", "node_name": "X"})[0].is_empty(),
		"add to missing parent errors", failed)
	_check(not TreeMutatorScript.add(scene, ur, {"parent_path": "/", "node_type": "../evil", "node_name": "X"})[0].is_empty(),
		"add with invalid type errors", failed)
	_check(not TreeMutatorScript.add(scene, ur, {"parent_path": "/", "node_type": "NotARealClass", "node_name": "X"})[0].is_empty(),
		"add with unknown type errors", failed)
	_check(not TreeMutatorScript.remove(scene, ur, {"path": "/"})[0].is_empty(),
		"remove scene root errors", failed)
	_check(not TreeMutatorScript.move(scene, ur, {"path": "/Building", "parent_path": "/Building/Roof"})[0].is_empty(),
		"move into descendant errors", failed)
	return failed[0]
