class_name TreeProjectSummary
extends RefCounted

## Read-only semantic summary for scenes and resources. Editor-independent core
## that loads the requested resource from disk (never saves) and extracts a
## bounded semantic view.
##
## The goal is a high-level helper that complements, but never replaces, the
## existing low-level scene tree inspection tools.

const TreeEngineScript := preload("res://addons/godot_tree/tree_engine.gd")

static func resource_summary(params: Dictionary) -> Array:
	var path := str(params.get("path", "")).strip_edges()
	if path.is_empty():
		return ["path is required", null]
	if not path.begins_with("res://"):
		return ["path must start with res://", null]
	if not ResourceLoader.exists(path):
		return ["resource not found: %s" % path, null]
	var depth := clampi(int(params.get("depth", 2)), 0, 10)
	var limit := clampi(int(params.get("limit", 500)), 1, 4000)
	var include_deps := bool(params.get("include_dependencies", true))
	var include_props := bool(params.get("include_properties", true))
	var res: Variant = load(path)
	if res == null:
		return ["failed to load resource: %s" % path, null]
	if res is PackedScene:
		return ["", _scene_summary(path, res as PackedScene, depth, limit, include_deps, include_props)]
	if res is Resource:
		return ["", _resource_summary(path, res as Resource, include_deps, include_props)]
	return ["unsupported resource type for summary: %s" % path, null]


static func _scene_summary(path: String, scene: PackedScene, depth: int, limit: int, include_deps: bool, include_props: bool) -> Dictionary:
	var root: Node = scene.instantiate()
	var node_list := _bounded_nodes(root, depth, limit)
	var groups: Array = root.get_groups()
	var signal_defs: Array = _scene_signal_defs(root)
	var deps: Array = ResourceLoader.get_dependencies(path) if include_deps else []
	var external_resources: Array = _collect_external_resource_paths(root) if include_deps else []
	return {
		"path": path,
		"kind": "scene",
		"source": "disk",
		"exists": true,
		"root": TreeEngineScript.node_summary(root, root),
		"node_count": TreeEngineScript.node_count(root),
		"nodes": node_list,
		"groups": groups,
		"signals": signal_defs,
		"dependencies": deps,
		"external_resources": external_resources,
		"truncated": node_list.size() >= limit,
	}


static func _resource_summary(path: String, res: Resource, include_deps: bool, include_props: bool) -> Dictionary:
	var props: Dictionary = {}
	if include_props:
		for prop: Dictionary in res.get_property_list():
			var pname := str(prop.get("name", ""))
			var usage := int(prop.get("usage", 0))
			if usage & PROPERTY_USAGE_INTERNAL:
				continue
			if usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
				continue
			if pname.is_empty():
				continue
			props[pname] = _json_value(res.get(pname))
	var deps: Array = ResourceLoader.get_dependencies(path) if include_deps else []
	return {
		"path": path,
		"kind": "resource",
		"source": "disk",
		"exists": true,
		"type": str(res.get_class()),
		"script": _script_path(res),
		"script_class": _script_class(res),
		"properties": props,
		"dependencies": deps,
	}


static func _bounded_nodes(root: Node, depth: int, limit: int) -> Array:
	var out: Array = []
	_walk_nodes(root, root, 0, depth, limit, out)
	return out


static func _walk_nodes(root: Node, node: Node, at: int, depth: int, limit: int, out: Array) -> void:
	if out.size() >= limit:
		return
	var info := TreeEngineScript.node_summary(node, root)
	if at > 0:
		out.append(info)
	if at >= depth:
		return
	for child: Node in node.get_children():
		_walk_nodes(root, child, at + 1, depth, limit, out)
		if out.size() >= limit:
			return


static func _scene_signal_defs(root: Node) -> Array:
	var out: Array = []
	for sig: Dictionary in root.get_signal_list():
		var sig_name := str(sig.get("name", ""))
		if sig_name.is_empty():
			continue
		out.append(sig_name)
	return out


static func _collect_external_resource_paths(root: Node) -> Array:
	var out: Array = []
	_collect_refs_from_node(root, out)
	return _dedupe(out)


static func _collect_refs_from_node(node: Node, out: Array) -> void:
	for prop: Dictionary in node.get_property_list():
		var usage := int(prop.get("usage", 0))
		if not usage & PROPERTY_USAGE_STORAGE:
			continue
		_collect_refs_from_variant(node.get(prop.get("name", "")), out)
	for child: Node in node.get_children():
		_collect_refs_from_node(child, out)


static func _collect_refs_from_variant(value: Variant, out: Array) -> void:
	match typeof(value):
		TYPE_OBJECT:
			if value is Resource:
				var r := value as Resource
				if not r.resource_path.is_empty():
					out.append(r.resource_path)
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			for item: Variant in value:
				_collect_refs_from_variant(item, out)
		TYPE_DICTIONARY:
			for key: Variant in value:
				_collect_refs_from_variant(key, out)
				_collect_refs_from_variant(value[key], out)


static func _script_path(res: Resource) -> String:
	var script: Script = res.get("script")
	if script == null:
		return ""
	return script.resource_path


static func _script_class(res: Resource) -> String:
	var script: Script = res.get("script")
	if script == null:
		return ""
	if script is GDScript:
		return (script as GDScript).get_global_name()
	return ""


static func _dedupe(values: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for v: Variant in values:
		var s := str(v)
		if s.is_empty() or seen.has(s):
			continue
		seen[s] = true
		out.append(v)
	return out


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
		TYPE_OBJECT:
			if value is Resource:
				var r := value as Resource
				if not r.resource_path.is_empty():
					return r.resource_path
			return str(value)
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
