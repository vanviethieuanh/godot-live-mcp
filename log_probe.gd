@tool
extends Node

func _ready() -> void:
	print("LogProbe _ready fired")
	push_warning("LogProbe warning probe")
