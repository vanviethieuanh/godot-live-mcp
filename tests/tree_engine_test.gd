extends SceneTree

## TreeEngine tests: query/children/props/find/inspect on a hand-built tree.
## Run: godot --headless -s tests/tree_engine_test.gd

const TreeEngineScript := preload("res://addons/godot_tree/tree_engine.gd")
const AgentFixture := preload("res://tests/fixture_agent_node.gd")


func _init() -> void:
	var failed := false
	failed = _test_children_summary() or failed
	failed = _test_props_filtering() or failed
	failed = _test_find_filters() or failed
	failed = _test_inspect_hook() or failed
	failed = _test_path_resolution() or failed
	print("TREE ENGINE TEST ", "PASS" if not failed else "FAIL")
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


func _test_children_summary() -> bool:
	var failed := false
	var scene := _build_scene()
	var rows: Array = TreeEngineScript.children(scene, scene)
	if rows.size() != 2:
		push_error("FAIL: children count %d != 2" % rows.size())
		failed = true
	var names: Array[String] = []
	for row: Variant in rows:
		names.append(str((row as Dictionary).name))
	if names != ["Building", "Agent"]:
		push_error("FAIL: children order %s" % str(names))
		failed = true
	var building: Node = scene.get_node("Building")
	var summary: Dictionary = TreeEngineScript.node_summary(building, scene)
	if summary.class != "Node2D" or int(summary.children_count) != 1 or str(summary.path) != "/Building":
		push_error("FAIL: bad summary %s" % JSON.stringify(summary))
		failed = true
	var roof_rows: Array = TreeEngineScript.children(building, scene)
	if str((roof_rows[0] as Dictionary).path) != "/Building/Roof":
		push_error("FAIL: child path %s" % str((roof_rows[0] as Dictionary).path))
		failed = true
	return failed


func _test_props_filtering() -> bool:
	var failed := false
	var scene := _build_scene()
	var agent: Node = scene.get_node("Agent")
	var p: Dictionary = TreeEngineScript.props(agent)
	if int(p.speed) != 5:
		push_error("FAIL: exported prop speed missing: %s" % JSON.stringify(p))
		failed = true
	if p.has("_internal"):
		push_error("FAIL: internal prop leaked into props")
		failed = true
	if p.has("script"):
		push_error("FAIL: script prop leaked into props")
		failed = true
	if p.has("owner"):
		push_error("FAIL: owner prop leaked into props")
		failed = true
	return failed


func _test_find_filters() -> bool:
	var failed := false
	var scene := _build_scene()
	var by_type: Array = TreeEngineScript.find_nodes(scene, {"type": "Node2D"})
	if by_type.size() != 1 or str((by_type[0] as Dictionary).path) != "/Building":
		push_error("FAIL: find by type %s" % JSON.stringify(by_type))
		failed = true
	var by_name: Array = TreeEngineScript.find_nodes(scene, {"name": "R*"})
	if by_name.size() != 1 or str((by_name[0] as Dictionary).name) != "Roof":
		push_error("FAIL: find by name glob %s" % JSON.stringify(by_name))
		failed = true
	var by_script: Array = TreeEngineScript.find_nodes(scene, {"script": "fixture_agent_node.gd"})
	if by_script.size() != 1 or str((by_script[0] as Dictionary).name) != "Agent":
		push_error("FAIL: find by script %s" % JSON.stringify(by_script))
		failed = true
	var by_prop: Array = TreeEngineScript.find_nodes(scene, {"has_prop": "speed"})
	if by_prop.size() != 1 or str((by_prop[0] as Dictionary).name) != "Agent":
		push_error("FAIL: find by has_prop %s" % JSON.stringify(by_prop))
		failed = true
	return failed


func _test_inspect_hook() -> bool:
	var failed := false
	var scene := _build_scene()
	var semantic: Variant = TreeEngineScript.inspect(scene.get_node("Agent"))
	if semantic == null or (semantic as Dictionary).kind != "fixture":
		push_error("FAIL: agent_inspect not returned: %s" % str(semantic))
		failed = true
	if TreeEngineScript.inspect(scene.get_node("Building")) != null:
		push_error("FAIL: inspect returned data for node without hook")
		failed = true
	return failed


func _test_path_resolution() -> bool:
	var failed := false
	var scene := _build_scene()
	var roof: Node = scene.get_node("Building/Roof")
	if TreeEngineScript.resolve(scene, "/Building/Roof") != roof:
		push_error("FAIL: absolute path resolve")
		failed = true
	if TreeEngineScript.resolve(scene, "Building/Roof") != roof:
		push_error("FAIL: relative path resolve")
		failed = true
	if TreeEngineScript.resolve(scene, "/") != scene or TreeEngineScript.resolve(scene, "") != scene:
		push_error("FAIL: root resolve")
		failed = true
	if TreeEngineScript.resolve(scene, "/Missing") != null:
		push_error("FAIL: missing path should resolve to null")
		failed = true
	var round_trip := TreeEngineScript.resolve(scene, TreeEngineScript.path_of(scene, roof))
	if round_trip != roof:
		push_error("FAIL: path_of/resolve round trip")
		failed = true
	return failed
