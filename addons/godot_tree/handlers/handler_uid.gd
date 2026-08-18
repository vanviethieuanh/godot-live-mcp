class_name TreeHandlerUid
extends RefCounted

## Bridge ops for resource UIDs / project analysis: get_uid and
## update_project_uids. Stateless, delegating straight to TreeUID.

const TreeUidScript := preload("res://addons/godot_tree/tree_uid.gd")


static func op_names() -> Array[String]:
	return ["get_uid", "update_project_uids"]


static func handle(server, op: String, args: Dictionary) -> Array:
	match op:
		"get_uid":
			return TreeUidScript.get_uid(args)
		"update_project_uids":
			return TreeUidScript.update_project_uids(args)
	return ["unknown op: %s" % op, null]
