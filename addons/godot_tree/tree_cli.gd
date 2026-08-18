extends SceneTree

## Headless client for the Godot Tree bridge. Sends one NDJSON request to the
## running editor's TreeServer over loopback TCP and prints the result.
## Run: godot --headless -s addons/godot_tree/tree_cli.gd -- [--port N] [--host H] <op> [args]
## Ops: ping | scene | editor | tree <path> [depth] |
##      query <path> | children <path> | props <path> |
##      inspect <path> | find [--path P] [--type T] [--name N] [--script S] [--has-prop P] |
##      set <path> <property> [--value <json>] |
##      add <parent> <type> <name> [--properties <json>] |
##      create_scene <root_type> <root_name> <save_path> [--children <json>] |
##      remove <path> | move <path> <new-parent> [--index N] |
##      attach_script <path> <script> |
##      get_uid <path> | get_uid --uid <uid> | update_project_uids [--dry-run]

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 41234

var _host := DEFAULT_HOST
var _port := DEFAULT_PORT
var _timeout_ms := 3000
var _op := "ping"
var _op_args: Array[String] = []
var _filters: Dictionary = {}

var _peer: StreamPeerTCP = null
var _buffer := ""
var _request := ""
var _done := false
var _start_ms := 0


func _init() -> void:
	_parse_args()
	_peer = StreamPeerTCP.new()
	var err := _peer.connect_to_host(_host, _port)
	if err != OK:
		printerr("ERROR: cannot connect to %s:%d (%s)" % [_host, _port, error_string(err)])
		quit(1)
		return
	_start_ms = Time.get_ticks_msec()
	_request = JSON.stringify(_build_request())


func _process(_delta: float) -> bool:
	if _done:
		return false
	_peer.poll()
	if Time.get_ticks_msec() - _start_ms > _timeout_ms:
		printerr("ERROR: timeout waiting for %s:%d" % [_host, _port])
		quit(1)
		return true
	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTING:
			return false
		StreamPeerTCP.STATUS_ERROR:
			printerr("ERROR: connection to %s:%d failed" % [_host, _port])
			quit(1)
			return true
		StreamPeerTCP.STATUS_CONNECTED:
			pass
		_:
			return false
	if _request != "":
		_peer.put_data((_request + "\n").to_utf8_buffer())
		_request = ""
		return false
	while _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var available := _peer.get_available_bytes()
		if available <= 0:
			break
		var data := _peer.get_partial_data(4096)
		if data[0] != OK:
			break
		_buffer += (data[1] as PackedByteArray).get_string_from_utf8()
	var nl := _buffer.find("\n")
	if nl >= 0:
		_done = true
		_finish(_buffer.substr(0, nl))
		return true
	return false


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var positional: Array[String] = []
	var i := 0
	while i < args.size():
		var arg := args[i]
		match arg:
			"--host":
				if i + 1 < args.size():
					_host = args[i + 1]
					i += 1
			"--port":
				if i + 1 < args.size():
					_port = int(args[i + 1])
					i += 1
			"--timeout":
				if i + 1 < args.size():
					_timeout_ms = int(args[i + 1])
					i += 1
			"--path", "--type", "--name", "--script", "--has-prop", "--path-pattern", "--properties", "--index", "--value", "--children":
				if i + 1 < args.size():
					_filters[arg.trim_prefix("--").replace("-", "_")] = args[i + 1]
					i += 1
			"--dry-run":
				_filters["dry_run"] = "true"
			_:
				if arg.begins_with("--"):
					printerr("ERROR: unknown flag: %s" % arg)
					quit(1)
					return
				positional.append(arg)
		i += 1
	if positional.size() > 0:
		_op = positional[0]
		_op_args = positional.slice(1)


func _build_request() -> Dictionary:
	var args: Dictionary = {}
	match _op:
		"query", "children", "props", "inspect":
			args["path"] = _op_args[0] if _op_args.size() > 0 else "/"
		"tree":
			args["path"] = _op_args[0] if _op_args.size() > 0 else "/"
			if _op_args.size() > 1:
				args["depth"] = int(_op_args[1])
		"find":
			for key: String in ["path", "type", "name", "script", "has_prop", "path_pattern"]:
				if _filters.has(key):
					args[key] = _filters[key]
		"set":
			args["path"] = _op_args[0] if _op_args.size() > 0 else "/"
			args["property"] = _op_args[1] if _op_args.size() > 1 else ""
			if _filters.has("value"):
				var raw_value := _filters["value"] as String
				var parsed_value: Variant = JSON.parse_string(raw_value)
				args["value"] = parsed_value if parsed_value != null else raw_value
			else:
				args["value"] = null
		"add":
			args["parent_path"] = _op_args[0] if _op_args.size() > 0 else "/"
			args["node_type"] = _op_args[1] if _op_args.size() > 1 else ""
			args["node_name"] = _op_args[2] if _op_args.size() > 2 else ""
			if _filters.has("properties"):
				var parsed_props: Variant = JSON.parse_string(_filters["properties"] as String)
				if parsed_props is Dictionary:
					args["properties"] = parsed_props
		"create_scene":
			args["root_type"] = _op_args[0] if _op_args.size() > 0 else ""
			args["root_name"] = _op_args[1] if _op_args.size() > 1 else ""
			args["save_path"] = _op_args[2] if _op_args.size() > 2 else ""
			if _filters.has("children"):
				var parsed_children: Variant = JSON.parse_string(_filters["children"] as String)
				if parsed_children is Array:
					args["children"] = parsed_children
		"remove":
			args["path"] = _op_args[0] if _op_args.size() > 0 else "/"
		"attach_script":
			args["path"] = _op_args[0] if _op_args.size() > 0 else "/"
			args["script"] = _op_args[1] if _op_args.size() > 1 else ""
		"get_uid":
			if _filters.has("uid"):
				args["uid"] = _filters["uid"]
			else:
				args["path"] = _op_args[0] if _op_args.size() > 0 else ""
		"update_project_uids":
			if _filters.has("dry_run"):
				args["dry_run"] = true
		"move":
			args["path"] = _op_args[0] if _op_args.size() > 0 else "/"
			args["parent_path"] = _op_args[1] if _op_args.size() > 1 else "/"
			if _filters.has("index"):
				args["index"] = int(_filters["index"] as String)
	return {"id": 1, "op": _op, "args": args}


func _finish(line: String) -> void:
	var response: Variant = JSON.parse_string(line)
	if not response is Dictionary:
		printerr("ERROR: invalid response: %s" % line)
		quit(1)
		return
	var resp := response as Dictionary
	if not bool(resp.get("ok", false)):
		printerr("ERROR: %s" % str(resp.get("error", "unknown")))
		quit(1)
		return
	_print_result(resp.get("result"))
	quit(0)


func _print_result(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value:
			print("%s: %s" % [key, _fmt(value[key])])
	elif value is Array:
		for item: Variant in value:
			if item is Dictionary and (item as Dictionary).has("path"):
				print(_row(item as Dictionary))
			else:
				print(_fmt(item))
	else:
		print(_fmt(value))


func _fmt(value: Variant) -> String:
	if value is Dictionary or value is Array:
		return JSON.stringify(value)
	return str(value)


func _row(row: Dictionary) -> String:
	var cols: PackedStringArray = PackedStringArray()
	for key: String in ["path", "name", "class", "class_name", "script", "children_count"]:
		if row.has(key):
			cols.append(str(row[key]))
	return "\t".join(cols)
