class_name TreeServer
extends Node

## Loopback TCP host for the Godot Tree bridge. Polls non-blockingly in
## _process (main thread) and dispatches NDJSON requests to per-group handlers
## (handlers/handler_*.gd). The scene root is fetched live through
## `root_provider`, so the editor's in-memory scene is always the source of
## truth. This file keeps only the general logic: communications, server
## lifecycle and request parsing; how each op is executed lives in the handler
## modules.

const HANDLER_MODULES: Array = [
	preload("res://addons/godot_tree/handlers/handler_info.gd"),
	preload("res://addons/godot_tree/handlers/handler_log.gd"),
	preload("res://addons/godot_tree/handlers/handler_tree_read.gd"),
	preload("res://addons/godot_tree/handlers/handler_tree_write.gd"),
	preload("res://addons/godot_tree/handlers/handler_uid.gd"),
]
const MAX_READS_PER_FRAME: int = 256

var root_provider: Callable = Callable()
var undo_redo_provider: Callable = Callable()
var modified_provider: Callable = Callable()
var port: int = 41234
var bind_address: String = "127.0.0.1"

## Optional LogBuffer fed by the plugin's CaptureLogger (Godot >= 4.5). When
## null the "log" op reports logging unavailable instead of erroring.
var log_buffer: RefCounted = null

var _tcp: TCPServer = null
var _conn: StreamPeerTCP = null
var _buffer: String = ""

## op name -> Callable(handler_module, "handle").bind(self)
var _handlers: Dictionary = {}


func start() -> Error:
	stop()
	_register_handlers()
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


## Build the op -> handler map. Each handler module declares the op names it
## owns and a static `handle(server, op, args)` returning [error, result]. A
## closure over `module` + `self` gives the handler the shared provider state.
func _register_handlers() -> void:
	_handlers.clear()
	for module: GDScript in HANDLER_MODULES:
		for op: String in module.op_names():
			_handlers[op] = func(_op: String, _args: Dictionary) -> Array:
				return module.handle(self, _op, _args)


## Route one op to its registered handler module; unknown ops error.
func _dispatch(op: String, args: Dictionary) -> Array:
	if not _handlers.has(op):
		return ["unknown op: %s" % op, null]
	return (_handlers[op] as Callable).call(op, args)


## Shared context helpers for handlers.

func current_root() -> Node:
	return root_provider.call() if root_provider.is_valid() else null


func current_undo_redo() -> Variant:
	if undo_redo_provider.is_valid():
		var ur: Variant = undo_redo_provider.call()
		if ur != null:
			return ur
	return UndoRedo.new()


func is_modified() -> bool:
	if modified_provider.is_valid():
		return bool(modified_provider.call())
	return false
