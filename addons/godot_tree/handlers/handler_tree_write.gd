class_name TreeHandlerWrite
extends RefCounted

## Bridge ops that mutate the scene tree: set, add, remove, move and
## create_scene. Pulls the live root and UndoRedo off the TreeServer and
## delegates to TreeMutator.

const TreeMutatorScript := preload("res://addons/godot_tree/tree_mutator.gd")


static func op_names() -> Array[String]:
	return ["set", "add", "remove", "move", "attach_script", "create_scene"]


static func handle(server, op: String, args: Dictionary) -> Array:
	var root: Node = server.current_root()
	var ur: Variant = server.current_undo_redo()
	match op:
		"set":
			return TreeMutatorScript.set_property(root, ur, args)
		"add":
			return TreeMutatorScript.add(root, ur, args)
		"remove":
			return TreeMutatorScript.remove(root, ur, args)
		"move":
			return TreeMutatorScript.move(root, ur, args)
		"attach_script":
			return TreeMutatorScript.attach_script(root, ur, args)
		"create_scene":
			return TreeMutatorScript.create_scene(args)
	return ["unknown op: %s" % op, null]
