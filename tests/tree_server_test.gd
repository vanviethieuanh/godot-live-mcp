extends SceneTree

## TreeServer tests: full TCP round trip against a headless TreeServer with a
## fake scene root (no editor involved).
## Run: godot --headless -s tests/tree_server_test.gd

const Server := preload("res://addons/godot_tree/tree_server.gd")
const AgentFixture := preload("res://tests/fixture_agent_node.gd")
const TEST_PORT := 41827

var _server: Node = null
var _client: StreamPeerTCP = null
var _buffer := ""
var _phase := 0
var _failed := false
var _requests: Array = []


func _init() -> void:
	_build_requests()


func _process(_delta: float) -> bool:
	if _client != null:
		_client.poll()
	match _phase:
		0:
			_phase = 1
			var scene := _build_scene()
			_server = Server.new()
			_server.root_provider = func() -> Node: return scene
			_server.port = TEST_PORT
			root.add_child(_server)
			var err: int = _server.start()
			if err != OK:
				push_error("FAIL: server start (%s)" % error_string(err))
				_finish()
				return false
			if not _server.is_listening():
				push_error("FAIL: is_listening false after start")
				_failed = true
				_finish()
				return false
			_client = StreamPeerTCP.new()
			_client.connect_to_host("127.0.0.1", TEST_PORT)
		1:
			if _client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				_send_next()
			elif _client.get_status() == StreamPeerTCP.STATUS_ERROR:
				push_error("FAIL: client connect failed")
				_finish()
		2:
			while _client.get_available_bytes() > 0:
				var data := _client.get_partial_data(4096)
				if data[0] != OK:
					break
				_buffer += (data[1] as PackedByteArray).get_string_from_utf8()
			var nl := _buffer.find("\n")
			if nl < 0:
				return false
			_handle_response(_buffer.substr(0, nl))
			_buffer = _buffer.substr(nl + 1)

	return false


func _build_scene() -> Node:
	var scene := Node.new()
	scene.name = "Scene"
	var building := Node2D.new()
	building.name = "Building"
	scene.add_child(building)
	var agent := AgentFixture.new()
	agent.name = "Agent"
	scene.add_child(agent)
	return scene


func _build_requests() -> void:
	_requests = [
		{"id": 1, "op": "ping", "args": {}},
		{"id": 2, "op": "scene", "args": {}},
		{"id": 3, "op": "children", "args": {"path": "/"}},
		{"id": 4, "op": "query", "args": {"path": "/Building"}},
		{"id": 5, "op": "props", "args": {"path": "/Agent"}},
		{"id": 6, "op": "inspect", "args": {"path": "/Agent"}},
		{"id": 7, "op": "find", "args": {"type": "Node2D"}},
		{"id": 8, "op": "query", "args": {"path": "/Missing"}},
		{"id": 9, "op": "bogus", "args": {}},
	]


func _send_next() -> void:
	if _requests.is_empty():
		_finish()
		return
	_client.put_data((JSON.stringify(_requests.pop_front()) + "\n").to_utf8_buffer())


func _handle_response(line: String) -> void:
	var response: Variant = JSON.parse_string(line)
	if not response is Dictionary:
		push_error("FAIL: invalid response %s" % line)
		_failed = true
		_send_next()
		return
	var resp := response as Dictionary
	var req_id := int(resp.get("id", -1))
	match req_id:
		1:
			if not bool((resp.get("result") as Dictionary).pong):
				push_error("FAIL: ping")
				_failed = true
		2:
			if not bool((resp.get("result") as Dictionary).loaded):
				push_error("FAIL: scene info")
				_failed = true
		3:
			var rows: Array = resp.get("result")
			if rows.size() != 2 or str((rows[0] as Dictionary).path) != "/Building":
				push_error("FAIL: children %s" % JSON.stringify(rows))
				_failed = true
		4:
			if str((resp.get("result") as Dictionary).class) != "Node2D":
				push_error("FAIL: query")
				_failed = true
		5:
			if int((resp.get("result") as Dictionary).speed) != 5:
				push_error("FAIL: props")
				_failed = true
		6:
			if str((resp.get("result") as Dictionary).kind) != "fixture":
				push_error("FAIL: inspect")
				_failed = true
		7:
			var found: Array = resp.get("result")
			if found.size() != 1 or str((found[0] as Dictionary).path) != "/Building":
				push_error("FAIL: find %s" % JSON.stringify(found))
				_failed = true
		8:
			if bool(resp.get("ok", true)) or str(resp.get("error", "")).is_empty():
				push_error("FAIL: missing node should error")
				_failed = true
		9:
			if bool(resp.get("ok", true)) or str(resp.get("error", "")).is_empty():
				push_error("FAIL: unknown op should error")
				_failed = true
		_:
			push_error("FAIL: unexpected response id %d" % req_id)
			_failed = true
	_send_next()


func _finish() -> void:
	if not _failed and _server.restart(TEST_PORT + 1) != OK:
		push_error("FAIL: restart failed")
		_failed = true
	elif not _failed and not _server.is_listening():
		push_error("FAIL: is_listening false after restart")
		_failed = true
	_server.stop()
	if not _failed and _server.is_listening():
		push_error("FAIL: is_listening true after stop")
		_failed = true
	print("TREE SERVER TEST ", "PASS" if not _failed else "FAIL")
	quit(0 if not _failed else 1)
