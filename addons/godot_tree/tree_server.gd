class_name TreeServer
extends Node

## Loopback TCP host for the Godot Tree bridge. Polls non-blockingly in
## _process (main thread) and dispatches NDJSON requests to TreeEngine.
## The scene root is fetched live through `root_provider`, so the editor's
## in-memory scene is always the source of truth.

const TreeEngineScript := preload("res://addons/godot_tree/tree_engine.gd")
const MAX_READS_PER_FRAME: int = 256

var root_provider: Callable = Callable()
var port: int = 41234
var bind_address: String = "127.0.0.1"

var _tcp: TCPServer = null
var _conn: StreamPeerTCP = null
var _buffer: String = ""


func start() -> Error:
	stop()
	_tcp = TCPServer.new()
	var err := _tcp.listen(port, bind_address)
	if err != OK:
		push_error("[GodotTree] cannot listen on %s:%d (%s)" % [bind_address, port, error_string(err)])
		_tcp = null
		return err
	print("[GodotTree] bridge listening on %s:%d" % [bind_address, port])
	return OK


func is_listening() -> bool:
	return _tcp != null and _tcp.is_listening()


func restart(new_port: int) -> Error:
	stop()
	port = new_port
	return start()


func stop() -> void:
	if _conn != null:
		_conn.disconnect_from_host()
		_conn = null
	if _tcp != null:
		_tcp.stop()
		_tcp = null
	_buffer = ""


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if _tcp == null:
		return
	if _conn == null:
		if _tcp.is_connection_available():
			_conn = _tcp.take_connection()
			_buffer = ""
		return
	if _conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_conn = null
		_buffer = ""
		return
	_conn.poll()
	if _conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_conn = null
		_buffer = ""
		return
	var reads := 0
	while reads < MAX_READS_PER_FRAME and _conn.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var available := _conn.get_available_bytes()
		if available <= 0:
			break
		var data := _conn.get_partial_data(4096)
		if data[0] != OK:
			break
		_buffer += (data[1] as PackedByteArray).get_string_from_utf8()
		reads += 1
	while true:
		var nl := _buffer.find("\n")
		if nl < 0:
			break
		var line := _buffer.substr(0, nl)
		_buffer = _buffer.substr(nl + 1)
		line = line.strip_edges()
		if line.is_empty():
			continue
		var response := _handle(line)
		if not response.is_empty():
			_conn.put_data((response + "\n").to_utf8_buffer())


func _handle(line: String) -> String:
	var request: Variant = JSON.parse_string(line)
	var req_id: Variant = null
	if request is Dictionary:
		req_id = (request as Dictionary).get("id")
	var error := ""
	var result: Variant = null
	if not request is Dictionary:
		error = "invalid JSON request"
	else:
		var req := request as Dictionary
		var outcome: Array = _dispatch(str(req.get("op", "")), req.get("args", {}))
		if not str(outcome[0]).is_empty():
			error = str(outcome[0])
		else:
			result = outcome[1]
	var response: Dictionary = {"id": req_id, "ok": error.is_empty()}
	if error.is_empty():
		response["result"] = result
	else:
		response["error"] = error
	return JSON.stringify(response)


func _dispatch(op: String, args: Dictionary) -> Array:
	var root: Node = root_provider.call() if root_provider.is_valid() else null
	match op:
		"ping":
			return ["", {"pong": true, "scene": _scene_info(root)}]
		"scene":
			return ["", _scene_info(root)]
		"find":
			var search_root: Node = TreeEngineScript.resolve(root, str(args.get("path", "/")))
			if search_root == null:
				return ["search root not found: %s" % str(args.get("path", "/")), null]
			var filters: Dictionary = {}
			for key: String in TreeEngineScript.FILTER_KEYS:
				if args.has(key):
					filters[key] = str(args[key])
			return ["", TreeEngineScript.find_nodes(search_root, filters)]
		_:
			if op not in ["query", "children", "props", "inspect"]:
				return ["unknown op: %s" % op, null]
			var node: Node = TreeEngineScript.resolve(root, str(args.get("path", "/")))
			if node == null:
				return ["node not found: %s" % str(args.get("path", "/")), null]
			match op:
				"query":
					return ["", TreeEngineScript.node_summary(node, root)]
				"children":
					return ["", TreeEngineScript.children(node, root)]
				"props":
					return ["", TreeEngineScript.props(node)]
				"inspect":
					return ["", TreeEngineScript.inspect(node)]
	return ["unknown op: %s" % op, null]


func _scene_info(root: Node) -> Dictionary:
	if root == null:
		return {"loaded": false}
	return {
		"loaded": true,
		"name": str(root.name),
		"scene_file_path": root.scene_file_path,
		"children_count": root.get_child_count(),
	}
