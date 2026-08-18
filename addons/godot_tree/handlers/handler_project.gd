class_name TreeHandlerProject
extends RefCounted

## Bridge op for reading project settings: get_setting. Supports a simple path
## filter so an agent can read a single value or a whole subtree of
## ProjectSettings (project.godot). Writing settings (project_set_setting) is
## intentionally NOT implemented yet: mutating project.godot is unsafe and easy
## to get wrong, so it is left out for now (see README).


static func op_names() -> Array[String]:
	return ["get_setting"]


static func handle(server, op: String, args: Dictionary) -> Array:
	match op:
		"get_setting":
			return get_setting(str(args.get("path", "")))
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
