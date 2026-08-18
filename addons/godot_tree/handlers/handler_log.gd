class_name TreeHandlerLog
extends RefCounted

## Bridge ops for the log stream: log (delta read) and log_probe (emit a probe
## message). Reads the ring buffer held on the TreeServer (`log_buffer`, only
## present on Godot >= 4.5).


static func op_names() -> Array[String]:
	return ["log", "log_probe"]


static func handle(server, op: String, args: Dictionary) -> Array:
	match op:
		"log":
			if server.log_buffer == null:
				return ["logging not available (requires Godot >= 4.5)", null]
			var since := int(args.get("since", 0))
			var limit := int(args.get("limit", 0))
			return ["", server.log_buffer.call("read_since", since, maxi(limit, 0))]
		"log_probe":
			_emit_probe(str(args.get("message", "probe")), str(args.get("level", "info")))
			return ["", {"ok": true}]
	return ["unknown op: %s" % op, null]


## Emit a std output/error log from the editor process for testing log_read.
## print()/push_error()/push_warning() go through the global logger stream, so
## the CaptureLogger captures them and they show up on the next log_read.
static func _emit_probe(message: String, level: String) -> void:
	match level:
		"error":
			push_error("[GodotTree probe] %s" % message)
		"warning":
			push_warning("[GodotTree probe] %s" % message)
		_:
			print("[GodotTree probe] %s" % message)
