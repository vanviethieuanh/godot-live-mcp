extends SceneTree

## TreeUID tests: resource UID lookup (path<->uid) and the project-wide UID
## scan. Run: godot --headless -s tests/tree_uid_test.gd

const TreeUidScript := preload("res://addons/godot_tree/tree_uid.gd")


func _init() -> void:
	var failed := false
	failed = _test_get_uid_roundtrip() or failed
	failed = _test_get_uid_errors() or failed
	failed = _test_get_uid_no_uid() or failed
	failed = _test_update_project_uids_scan() or failed
	print("TREE UID TEST ", "PASS" if not failed else "FAIL")
	quit(0 if not failed else 1)


## Create a throwaway resource on disk and register a UID in the cache, then
## verify both look-up directions resolve. UID *persistence* to `.uid` sidecar
## files is editor-only, so here the mapping is registered directly via the
## ResourceUID singleton (which also works headless).
func _test_get_uid_roundtrip() -> bool:
	var failed := false
	var path := "user://tree_uid_test.tres"
	var res := Resource.new()
	if ResourceSaver.save(res, path) != OK:
		push_error("FAIL: could not save temp resource")
		return true
	var id := ResourceUID.create_id()
	ResourceUID.add_id(id, path)
	if not ResourceUID.has_id(id):
		push_error("FAIL: could not register UID for %s" % path)
		failed = true
	else:
		var by_path: Array = TreeUidScript.get_uid({"path": path})
		if not by_path[0].is_empty():
			push_error("FAIL: get_uid path error: %s" % str(by_path[0]))
			failed = true
		elif (by_path[1] as Dictionary).get("path", "") != path:
			push_error("FAIL: get_uid path result %s" % JSON.stringify(by_path[1]))
			failed = true
		elif str((by_path[1] as Dictionary).get("uid", "")).is_empty():
			push_error("FAIL: get_uid path -> uid empty")
			failed = true
		var uid := str((by_path[1] as Dictionary).get("uid", ""))
		var by_uid: Array = TreeUidScript.get_uid({"uid": uid})
		if not by_uid[0].is_empty():
			push_error("FAIL: get_uid uid error: %s" % str(by_uid[0]))
			failed = true
		elif str((by_uid[1] as Dictionary).get("path", "")) != path:
			push_error("FAIL: get_uid uid -> path %s" % JSON.stringify(by_uid[1]))
			failed = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return failed


func _test_get_uid_errors() -> bool:
	var failed := false
	var both: Array = TreeUidScript.get_uid({"path": "res://x.tres", "uid": "uid://abc"})
	if both[0].is_empty():
		push_error("FAIL: both path and uid should error")
		failed = true
	var neither: Array = TreeUidScript.get_uid({})
	if neither[0].is_empty():
		push_error("FAIL: neither path nor uid should error")
		failed = true
	var bad_prefix: Array = TreeUidScript.get_uid({"uid": "res://x.tres"})
	if bad_prefix[0].is_empty():
		push_error("FAIL: non-uid:// string should error")
		failed = true
	var unknown: Array = TreeUidScript.get_uid({"uid": "uid://doesnotexist"})
	if unknown[0].is_empty():
		push_error("FAIL: unknown uid should error")
		failed = true
	return failed


## A path with no UID should resolve to a null uid rather than erroring.
func _test_get_uid_no_uid() -> bool:
	var failed := false
	var result: Array = TreeUidScript.get_uid({"path": "res://definitely_missing_file.tres"})
	if not result[0].is_empty():
		push_error("FAIL: missing-path lookup should not error: %s" % str(result[0]))
		failed = true
	elif (result[1] as Dictionary).get("uid") != null:
		push_error("FAIL: missing-path uid should be null: %s" % JSON.stringify(result[1]))
		failed = true
	return failed


## update_project_uids should return a stats dictionary for both dry-run and
## live modes without erroring. Exact counts depend on the scanned project, so
## only the shape is asserted here.
func _test_update_project_uids_scan() -> bool:
	var failed := false
	var dry: Array = TreeUidScript.update_project_uids({"dry_run": true})
	if not dry[0].is_empty():
		push_error("FAIL: update_project_uids dry_run error: %s" % str(dry[0]))
		failed = true
	elif not _has_stats_keys(dry[1]):
		push_error("FAIL: dry_run result missing stats keys: %s" % JSON.stringify(dry[1]))
		failed = true
	var live: Array = TreeUidScript.update_project_uids({})
	if not live[0].is_empty():
		push_error("FAIL: update_project_uids error: %s" % str(live[0]))
		failed = true
	elif not _has_stats_keys(live[1]):
		push_error("FAIL: live result missing stats keys: %s" % JSON.stringify(live[1]))
		failed = true
	return failed


func _has_stats_keys(result: Variant) -> bool:
	if not result is Dictionary:
		return false
	for key: String in ["scanned", "already_had_uid", "generated", "skipped"]:
		if not (result as Dictionary).has(key):
			return false
	return true
