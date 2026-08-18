class_name TreeEngine
extends RefCounted

## Read-only scene tree query core. Editor-independent: every function takes a
## Node root, so the dock, the TCP bridge and headless tests share one engine.

const FILTER_KEYS: Array[String] = ["type", "name", "script", "has_prop", "path_pattern"]


static func node_summary(node: Node, root: Node) -> Dictionary:
	var info := _script_info(node)
	return {
		"path": path_of(root, node),
		"name": str(node.name),
		"class": node.get_class(),
		"script": info.path,
		"class_name": info.class_name,
		"children_count": node.get_child_count(),
	}


static func children(node: Node, root: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		out.append(node_summary(child, root))
	return out


static func props(node: Node) -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in node.get_property_list():
		var usage: int = int(entry.get("usage", 0))
		if usage & PROPERTY_USAGE_INTERNAL:
			continue
		if usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		if not usage & PROPERTY_USAGE_EDITOR:
			continue
		var pname := str(entry.get("name", ""))
		if pname.is_empty() or pname == "script" or pname == "owner":
			continue
		out[pname] = _json_value(node.get(pname))
	return out


static func find_nodes(root: Node, search_root: Node, filters: Dictionary) -> Array:
	var out: Array = []
	_walk_find(root, search_root, filters, out)
	return out


static func _walk_find(root: Node, node: Node, filters: Dictionary, out: Array) -> void:
	if _match_filters(root, node, filters):
		out.append(node_summary(node, root))
	for child in node.get_children():
		_walk_find(root, child, filters, out)


static func _match_filters(root: Node, node: Node, filters: Dictionary) -> bool:
	for key: String in FILTER_KEYS:
		if not filters.has(key):
			continue
		var pattern := str(filters[key])
		match key:
			"type":
				if not _type_matches(node, pattern):
					return false
			"name":
				if not node.name.match(pattern):
					return false
			"script":
				var info := _script_info(node)
				if not (info.path.match(pattern) or info.path.contains(pattern) or info.class_name == pattern):
					return false
			"has_prop":
				if not _has_prop(node, pattern):
					return false
			"path_pattern":
				if not _path_matches(pattern, path_of(root, node)):
					return false
	return true


# Match an absolute path against a segment-wise glob pattern (e.g. /A/*/C).
# `*` matches one path segment, `?` one character within a segment.
static func _path_matches(pattern: String, path: String) -> bool:
	var p := pattern.strip_edges()
	var a := path.strip_edges()
	while p.begins_with("/"):
		p = p.substr(1)
	while a.begins_with("/"):
		a = a.substr(1)
	var pattern_segments := p.split("/")
	var path_segments := a.split("/")
	if pattern_segments.size() != path_segments.size():
		return false
	for i in pattern_segments.size():
		if not path_segments[i].match(pattern_segments[i]):
			return false
	return true


static func _type_matches(node: Node, type: String) -> bool:
	if node.get_class() == type or node.is_class(type):
		return true
	return _script_info(node).class_name == type


static func _has_prop(node: Node, pname: String) -> bool:
	for entry: Dictionary in node.get_property_list():
		if str(entry.get("name", "")) == pname:
			return true
	return false


static func inspect(node: Node) -> Variant:
	if node.has_method("agent_inspect"):
		return _json_value(node.call("agent_inspect"))
	return null


static func node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += node_count(child)
	return count


static func tree(root: Node, node: Node, max_depth: int, depth: int) -> Dictionary:
	var out := node_summary(node, root)
	if depth < max_depth and node.get_child_count() > 0:
		var children_arr: Array = []
		for child in node.get_children():
			children_arr.append(tree(root, child, max_depth, depth + 1))
		out["children"] = children_arr
	return out


static func _script_info(node: Node) -> Dictionary:
	var script: Script = node.get_script()
	if script == null:
		return {"path": "", "class_name": ""}
	var class_name_value := ""
	if script is GDScript:
		class_name_value = (script as GDScript).get_global_name()
	return {"path": script.resource_path, "class_name": class_name_value}


static func resolve(root: Node, path: String) -> Node:
	if root == null:
		return null
	var clean := path.strip_edges()
	if clean.is_empty() or clean == "/" or clean == ".":
		return root
	var rel := clean
	if rel.begins_with("/"):
		rel = rel.substr(1)
	if rel.is_empty():
		return root
	return root.get_node_or_null(NodePath(rel))


static func path_of(root: Node, node: Node) -> String:
	if node == root:
		return "/"
	return "/" + str(root.get_path_to(node))


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
			var obj := value as Object
			if obj is Resource and not (obj as Resource).resource_path.is_empty():
				return (obj as Resource).resource_path
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
