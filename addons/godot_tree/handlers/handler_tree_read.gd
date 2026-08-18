class_name TreeHandlerRead
extends RefCounted

## Bridge ops for read-only scene tree inspection: query, children, props,
## inspect, find and tree. Resolves the target node against the scene root and
## delegates the actual work to TreeEngine.

const TreeEngineScript := preload("res://addons/godot_tree/tree_engine.gd")


static func op_names() -> Array[String]:
	return ["query", "children", "props", "inspect", "find", "tree"]


static func handle(server, op: String, args: Dictionary) -> Array:
	var root: Node = server.current_root()
	match op:
		"tree":
			var tree_root: Node = TreeEngineScript.resolve(root, str(args.get("path", "/")))
			if tree_root == null:
				return ["node not found: %s" % str(args.get("path", "/")), null]
			var depth := clampi(int(args.get("depth", 2)), 0, 10)
			return ["", TreeEngineScript.tree(root, tree_root, depth, 0)]
		"find":
			var search_root: Node = TreeEngineScript.resolve(root, str(args.get("path", "/")))
			if search_root == null:
				return ["search root not found: %s" % str(args.get("path", "/")), null]
			var filters: Dictionary = {}
			for key: String in TreeEngineScript.FILTER_KEYS:
				if args.has(key):
					filters[key] = str(args[key])
			return ["", TreeEngineScript.find_nodes(root, search_root, filters)]
		"query":
			return _on_node(root, args, func(node: Node) -> Variant: return TreeEngineScript.node_summary(node, root))
		"children":
			return _on_node(root, args, func(node: Node) -> Variant: return TreeEngineScript.children(node, root))
		"props":
			return _on_node(root, args, func(node: Node) -> Variant: return TreeEngineScript.props(node))
		"inspect":
			return _on_node(root, args, func(node: Node) -> Variant: return TreeEngineScript.inspect(node))
	return ["unknown op: %s" % op, null]


## Resolve the node at args.path (erroring when missing) and pass it to `fn`.
static func _on_node(root: Node, args: Dictionary, fn: Callable) -> Array:
	var node: Node = TreeEngineScript.resolve(root, str(args.get("path", "/")))
	if node == null:
		return ["node not found: %s" % str(args.get("path", "/")), null]
	return ["", fn.call(node)]
