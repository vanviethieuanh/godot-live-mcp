class_name TreeProjectFiles
extends RefCounted

## Read-only project file inventory. Editor-independent core that can walk a
## `res://` directory tree and return structured metadata for resource files.
##
## This is intentionally a disk scan without editor-specific metadata when used
## headlessly. It should never start/import resources or trigger rescans.

const SKIP_DIRS: Array[String] = [".godot", ".git"]

const KIND_MAP: Dictionary = {
	"scene": ["tscn", "scn"],
	"script": ["gd", "cs"],
	"resource": ["tres", "res", "cfg"],
	"texture": ["png", "jpg", "jpeg", "svg", "bmp", "webp", "dds", "exr", "hdr", "ktx"],
	"audio": ["wav", "ogg", "mp3", "opus"],
	"font": ["otf", "ttf", "woff", "woff2"],
	"shader": ["gdshader", "shader"],
	"model": ["glb", "gltf", "obj", "fbx", "blend"],
	"animation": ["anim", "tres", "res"],
}

static func project_files(params: Dictionary) -> Array:
	var root := str(params.get("path", "res://")).strip_edges()
	if root.is_empty():
		root = "res://"
	if not root.begins_with("res://"):
		return ["path must start with res://", null]
	var kind := str(params.get("kind", "all")).strip_edges().to_lower()
	var pattern := str(params.get("pattern", "")).strip_edges()
	var recursive := bool(params.get("recursive", true))
	var limit := clampi(int(params.get("limit", 500)), 1, 2000)
	if not _kind_supported(kind):
		return ["unsupported kind: %s" % kind, null]
	if not _dir_exists(root):
		return ["directory not found: %s" % root, null]
	var allowed_exts := _allowed_exts_for_kind(kind)
	var files: Array = []
	_scan(root, allowed_exts, pattern, recursive, limit, files)
	return ["", {
		"path": root,
		"kind": kind,
		"pattern": pattern,
		"recursive": recursive,
		"count": files.size(),
		"truncated": files.size() >= limit,
		"files": files,
	}]


static func _kind_supported(kind: String) -> bool:
	return kind == "all" or KIND_MAP.has(kind)


static func _allowed_exts_for_kind(kind: String) -> Dictionary:
	if kind == "all":
		return {}
	var out := {}
	for ext: String in KIND_MAP[kind]:
		out[ext] = true
	return out


static func _scan(dir_path: String, allowed_exts: Dictionary, pattern: String, recursive: bool, limit: int, out: Array) -> void:
	if out.size() >= limit:
		return
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
			if not recursive:
				continue
			if entry.begins_with("."):
				continue
			if SKIP_DIRS.has(entry):
				continue
			_scan(full + "/", allowed_exts, pattern, recursive, limit, out)
			continue
		if _should_include(full, allowed_exts, pattern):
			out.append(_file_entry(full))
		if out.size() >= limit:
			break
	dir.list_dir_end()


static func _should_include(path: String, allowed_exts: Dictionary, pattern: String) -> bool:
	if not allowed_exts.is_empty():
		var ext := path.get_extension().to_lower()
		if not allowed_exts.has(ext):
			return false
	if pattern.is_empty():
		return true
	return path.get_file().match(pattern) or path.match(pattern)


static func _file_entry(path: String) -> Dictionary:
	var res: Variant = load(path)
	var type := ""
	var uid := _uid_for_path(path)
	if res != null and res is Resource:
		type = str((res as Resource).get_class())
	elif path.ends_with(".uid"):
		type = "UID"
	return {
		"path": path,
		"name": path.get_file(),
		"extension": path.get_extension().to_lower(),
		"type": type,
		"uid": uid,
	}


static func _uid_for_path(path: String) -> Variant:
	if not ResourceUID.has_method("path_to_uid"):
		return null
	var uid := ResourceUID.path_to_uid(path)
	if uid == path:
		return null
	return uid


static func _dir_exists(res_path: String) -> bool:
	if not res_path.begins_with("res://"):
		return false
	return DirAccess.dir_exists_absolute(res_path)
