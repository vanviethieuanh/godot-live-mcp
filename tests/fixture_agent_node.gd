extends Node

## Test fixture: a node with exported props and an agent_inspect() hook.

@export var speed: int = 5
@export var label: String = "roof"
var _internal := 1


func agent_inspect() -> Dictionary:
	return {"kind": "fixture", "speed": speed, "label": label}
