extends SceneTree

## TreeProjectFiles headless tests: disk-based project file discovery
## and semantic summary for scenes/resources.
## Run: godot --headless -s tests/tree_project_files_test.gd

const TreeProjectFilesScript := preload("res://addons/godot_tree/tree_project_files.gd")
const TreeProjectSummaryScript := preload("res://addons/godot_tree/tree_project_summary.gd")
const TreeMutatorScript := preload("res://addons/godot_tree/tree_mutator.gd")

const TMP_ROOT := "res://tmp_project_files_root"
const TMP_SCENE := "res://tmp_project_files_root/summary_scene.tscn"
const TMP_RESOURCE := "res://tmp_project_files_root/example.tres"


func _init() -> void:
	var failed := false
	failed = _test_project_files_scene_filter() or failed
	failed = _test_project_files_pattern_and_truncation() or failed
	failed = _test_resource_summary_scene() or failed
	failed = _test_resource_summary_resource() or failed
	_cleanup()
	print("TREE PROJECT FILES TEST ", "PASS" if not failed else "FAIL")
	quit(0 if not failed else 1)


func _check(condition: bool, message: String, failed: Array) -> void:
	if not condition:
		push_error("FAIL: " + message)
		failed[0] = true


func _test_project_files_scene_filter() -> bool:
	var failed := [false]
	_setup_project()
	var out: Array = TreeProjectFilesScript.project_files({
		"path": TMP_ROOT,
		"kind": "scene",
		"recursive": true,
	})
	_check(str(out[0]).is_empty(), "project_files scene succeeds: %s" % str(out[0]), failed)
	var result: Dictionary = out[1] as Dictionary
	_check(result.get("path") == TMP_ROOT, "project_files returns root path", failed)
	var files: Array = result.get("files") as Array
	var names: Array = []
	for f: Dictionary in files:
		names.append(str(f.get("name", "")))
	_check(names.has("summary_scene.tscn"), "project_files finds scene fixture", failed)
	_check(not names.has("example.gd"), "project_files excludes scripts for kind=scene", failed)
	return failed[0]


func _test_project_files_pattern_and_truncation() -> bool:
	var failed := [false]
	_setup_project()
	var out: Array = TreeProjectFilesScript.project_files({
		"path": TMP_ROOT,
		"kind": "all",
		"pattern": "summary*",
		"recursive": true,
		"limit": 1,
	})
	_check(str(out[0]).is_empty(), "project_files pattern succeeds: %s" % str(out[0]), failed)
	var result: Dictionary = out[1] as Dictionary
	_check(int(result.get("count", 0)) == 1, "project_files limit caps count", failed)
	_check(bool(result.get("truncated", false)), "project_files reports truncated", failed)
	return failed[0]


func _test_resource_summary_scene() -> bool:
	var failed := [false]
	_setup_project()
	var out: Array = TreeProjectSummaryScript.resource_summary({"path": TMP_SCENE, "depth": 1, "include_dependencies": true})
	_check(str(out[0]).is_empty(), "resource_summary scene succeeds: %s" % str(out[0]), failed)
	var result: Dictionary = out[1] as Dictionary
	_check(str(result.get("kind", "")) == "scene", "resource_summary reports kind=scene", failed)
	_check(int(result.get("node_count", 0)) >= 2, "resource_summary counts nodes", failed)
	var nodes: Array = result.get("nodes") as Array
	var paths: Array = []
	for n: Dictionary in nodes:
		paths.append(str(n.get("path", "")))
	_check(paths.has("/Child"), "resource_summary includes child node path", failed)
	return failed[0]


func _test_resource_summary_resource() -> bool:
	var failed := [false]
	_setup_project()
	var out: Array = TreeProjectSummaryScript.resource_summary({"path": TMP_RESOURCE})
	_check(str(out[0]).is_empty(), "resource_summary resource succeeds: %s" % str(out[0]), failed)
	var result: Dictionary = out[1] as Dictionary
	_check(str(result.get("kind", "")) == "resource", "resource_summary reports kind=resource", failed)
	return failed[0]


func _setup_project() -> void:
	_cleanup()
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_ROOT))
	_check(err == OK, "create temp project files root", [false])
	TreeMutatorScript.create_scene({
		"root_type": "Node2D",
		"root_name": "Root",
		"save_path": TMP_SCENE,
		"children": [{"node_type": "Node2D", "node_name": "Child"}],
	})
	var tres_text := "[gd_resource type=\"Resource\" load_steps=2 format=3]\n\n"
	tres_text += "[ext_resource type=\"Script\" path=\"res://tests/fixture_agent_node.gd\" id=\"dep_script\"]\n\n"
	tres_text += "[resource]\nscript = ExtResource(\"dep_script\")\n"
	var tres := FileAccess.open(TMP_RESOURCE, FileAccess.WRITE)
	if tres != null:
		tres.store_string(tres_text)
		tres.close()


func _cleanup() -> void:
	_remove_dir_recursive(TMP_ROOT)


func _remove_dir_recursive(res_dir: String) -> void:
	var global_path := ProjectSettings.globalize_path(res_dir)
	var dir := DirAccess.open(global_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var full := global_path.path_join(entry)
		if dir.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
	dir.list_dir_end()
	DirAccess.remove_absolute(global_path)
