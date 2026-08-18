class_name TreeUID
extends RefCounted

## Resource UID / project-analysis core (Godot 4.4+). Editor-independent: each
## function takes a params Dictionary and returns an Array [error, result], so
## the TCP bridge and headless tests share one implementation. Backed by the
## ResourceUID singleton and ResourceSaver UID primitives.

## Directories always excluded from a project-wide UID scan.
const SKIP_DIRS: Array[String] = [".godot", ".git"]


static func get_uid(params: Dictionary) -> Array:
	if not _uid_supported():
		return ["resource UIDs require Godot 4.4+", null]
	var path := str(params.get("path", ""))
	var uid := str(params.get("uid", ""))
	if path.is_empty() and uid.is_empty():
		return ["path or uid is required", null]
	if not path.is_empty() and not uid.is_empty():
		return ["provide only one of path or uid", null]
	if not uid.is_empty():
		return _uid_to_path(uid)
	return _path_to_uid(path)


static func _path_to_uid(path: String) -> Array:
	var uid := ResourceUID.path_to_uid(path)
	if uid == path:
		return ["", {"path": path, "uid": null}]
	return ["", {"path": path, "uid": uid}]


static func _uid_to_path(uid: String) -> Array:
	if not uid.begins_with("uid://"):
		return ["uid must start with uid://", null]
	var id := ResourceUID.text_to_id(uid)
	if not ResourceUID.has_id(id):
		return ["unknown uid: %s" % uid, null]
	return ["", {"path": ResourceUID.uid_to_path(uid), "uid": uid}]


## Assign a UID to every resource file under the project (res://) that does not
## already have one, persisting `.uid` sidecar files. Mirrors the editor's
## Project > Tools > "Update UIDs". When `dry_run` is true, no files are
## written; only the scan/decision statistics are returned.
static func update_project_uids(params: Dictionary) -> Array:
	if not _uid_supported():
		return ["resource UIDs require Godot 4.4+", null]
	var dry_run := bool(params.get("dry_run", false))
	var recognized := _resource_extensions()
	if recognized.is_empty():
		return ["no recognized resource extensions available", null]
	var counts := {"scanned": 0, "already_had_uid": 0, "generated": 0, "skipped": 0}
	_scan_dir("res://", recognized, dry_run, counts)
	return ["", counts]


static func _scan_dir(dir_path: String, recognized: Dictionary, dry_run: bool, counts: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var full := dir_path.trim_suffix("/") + "/" + entry
		if dir.current_is_dir():
			if entry.begins_with("."):
				continue
			if SKIP_DIRS.has(entry):
				continue
			_scan_dir(full + "/", recognized, dry_run, counts)
			continue
		_maybe_assign_uid(full, recognized, dry_run, counts)
	dir.list_dir_end()


static func _maybe_assign_uid(path: String, recognized: Dictionary, dry_run: bool, counts: Dictionary) -> void:
	var ext := path.get_extension().to_lower()
	if ext.is_empty() or not recognized.has(ext):
		counts["skipped"] = int(counts["skipped"]) + 1
		return
	if ext == "uid":
		counts["skipped"] = int(counts["skipped"]) + 1
		return
	counts["scanned"] = int(counts["scanned"]) + 1
	if ResourceUID.path_to_uid(path) != path:
		counts["already_had_uid"] = int(counts["already_had_uid"]) + 1
		return
	if dry_run:
		counts["generated"] = int(counts["generated"]) + 1
		return
	ResourceSaver.get_resource_id_for_path(path, true)
	counts["generated"] = int(counts["generated"]) + 1


## Map of recognized resource extensions -> true, from the resource loader.
static func _resource_extensions() -> Dictionary:
	var out := {}
	var exts: PackedStringArray = ResourceLoader.get_recognized_extensions_for_type("")
	for ext: String in exts:
		out[ext.to_lower()] = true
	return out


static func _uid_supported() -> bool:
	var version := Engine.get_version_info()
	return int(version.get("major", 4)) >= 4 and int(version.get("minor", 0)) >= 4
