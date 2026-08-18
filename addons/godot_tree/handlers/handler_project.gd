class_name TreeHandlerProject
extends RefCounted

## Bridge ops for project settings: get_setting and set_main_scene. Reading any
## setting is supported; general writes are intentionally NOT implemented
## (mutating project.godot is unsafe and easy to get wrong). set_main_scene is
## the one narrow, auditable exception: a targeted single-key write of
## application/run/main_scene that validates the scene before persisting.
const MAIN_SCENE_SETTING := "application/run/main_scene"


static func op_names() -> Array[String]:
	return ["get_setting", "set_main_scene"]


static func handle(server, op: String, args: Dictionary) -> Array:
	match op:
		"get_setting":
			return get_setting(str(args.get("path", "")))
		"set_main_scene":
			return set_main_scene(str(args.get("scene", "")))
	return ["unknown op: %s" % op, null]


## Read one project setting, or all matching a simple filter. `path` is either:
##  - an exact setting name -> returns {"path", "value"} for that single value;
##  - otherwise treated as a filter -> a prefix (e.g. "application/config") or
##    a `*` glob (e.g. "application/*") -> returns {"path", "count", "settings"}
##    with every matching setting.
static func get_setting(path: String) -> Array:
	if path.is_empty():
		return ["path is required", null]
	if ProjectSettings.has_setting(path):
		return ["", {"path": path, "value": _json_value(ProjectSettings.get_setting(path))}]
	var values := {}
	var pattern := path.strip_edges()
	for entry: Dictionary in ProjectSettings.get_property_list():
		var name := str(entry.get("name", ""))
		if not _matches(name, pattern):
			continue
		values[name] = _json_value(ProjectSettings.get_setting(name))
	return ["", {"path": path, "count": values.size(), "settings": values}]


## Set the project's main scene (application/run/main_scene) and persist it to
## project.godot. Validates that `scene` is a res:// .tscn that loads as a
## PackedScene before writing. This is the project's single auditable write op.
static func set_main_scene(scene: String) -> Array:
	scene = scene.strip_edges()
	if scene.is_empty():
		return ["scene (res:// path) is required", null]
	if not scene.begins_with("res://") or not scene.ends_with(".tscn"):
		return ["scene must be a res:// .tscn path: %s" % scene, null]
	if ResourceLoader.exists(scene):
		var res: Variant = load(scene)
		if res == null or not res is PackedScene:
			return ["scene does not load as a PackedScene: %s" % scene, null]
	else:
		return ["scene not found: %s" % scene, null]
	var previous := ProjectSettings.get_setting(MAIN_SCENE_SETTING, "")
	ProjectSettings.set_setting(MAIN_SCENE_SETTING, scene)
	var err := ProjectSettings.save()
	if err != OK:
		return ["failed to save project.godot (%s)" % error_string(err), null]
	return ["", {"path": scene, "previous": str(previous)}]


static func _matches(name: String, pattern: String) -> bool:
	if name == pattern:
		return true
	if name.begins_with(pattern + "/"):
		return true
	if pattern.contains("*") and name.match(pattern):
		return true
	return false


## Mirror TreeEngine._json_value so settings round-trip as JSON-safe values.
static func _json_value(value: Variant) -> Variant:
	if value == null:
		return null
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_COLOR:
			return Color(value).to_html(true)
		TYPE_ARRAY:
			var out: Array = []
			for item: Variant in value:
				out.append(_json_value(item))
			return out
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key: Variant in value:
				out[str(key)] = _json_value(value[key])
			return out
		_:
			return str(value)
