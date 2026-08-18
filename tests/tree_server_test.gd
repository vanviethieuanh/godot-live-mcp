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
var _uid_path := "res://server_uid_probe.gd"
var _uid_id := -1


func _init() -> void:
	# Register a synthetic UID into the in-memory cache so get_uid has a
	# deterministic happy path without touching the real filesystem.
	_uid_id = ResourceUID.create_id()
	ResourceUID.add_id(_uid_id, _uid_path)
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
			_server.undo_redo_provider = func() -> Variant: return UndoRedo.new()
			_server.modified_provider = func() -> bool: return true
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
		{"id": 10, "op": "add", "args": {"parent_path": "/", "node_type": "Node2D", "node_name": "NewNode"}},
		{"id": 11, "op": "query", "args": {"path": "/NewNode"}},
		{"id": 12, "op": "set", "args": {"path": "/Building", "property": "position", "value": [10.0, 20.0]}},
		{"id": 13, "op": "props", "args": {"path": "/Building"}},
		{"id": 14, "op": "move", "args": {"path": "/Agent", "parent_path": "/Building"}},
		{"id": 15, "op": "query", "args": {"path": "/Building/Agent"}},
		{"id": 16, "op": "remove", "args": {"path": "/NewNode"}},
		{"id": 17, "op": "query", "args": {"path": "/NewNode"}},
		{"id": 18, "op": "editor", "args": {}},
		{"id": 19, "op": "tree", "args": {"path": "/", "depth": 2}},
		{"id": 20, "op": "scene", "args": {}},
		{"id": 21, "op": "add", "args": {"parent_path": "/Building", "node_type": "Node2D", "node_name": "Sub"}},
		{"id": 22, "op": "find", "args": {"path": "/Building", "type": "Node2D"}},
		{"id": 23, "op": "get_uid", "args": {"path": _uid_path}},
		{"id": 24, "op": "get_uid", "args": {"uid": ResourceUID.id_to_text(_uid_id)}},
		{"id": 25, "op": "get_uid", "args": {}},
		{"id": 26, "op": "get_uid", "args": {"uid": "res://not_a_uid"}},
		{"id": 27, "op": "get_uid", "args": {"uid": "uid://doesnotexist"}},
		{"id": 28, "op": "update_project_uids", "args": {"dry_run": true}},
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
		10:
			if not bool(resp.get("ok", false)):
				push_error("FAIL: add: %s" % str(resp.get("error", "")))
				_failed = true
		11:
			if str((resp.get("result") as Dictionary).class) != "Node2D":
				push_error("FAIL: add visible via query: %s" % str(resp.get("result")))
				_failed = true
		12:
			if not bool(resp.get("ok", false)):
				push_error("FAIL: set: %s" % str(resp.get("error", "")))
				_failed = true
		13:
			if not str(resp.get("result", {}).get("position", "")).contains("10, 20"):
				push_error("FAIL: set visible via props: %s" % str(resp.get("result")))
				_failed = true
		14:
			if not bool(resp.get("ok", false)):
				push_error("FAIL: move: %s" % str(resp.get("error", "")))
				_failed = true
		15:
			if not bool(resp.get("ok", false)) or str((resp.get("result") as Dictionary).name) != "Agent":
				push_error("FAIL: move visible via query: %s" % str(resp.get("result")))
				_failed = true
		16:
			if not bool(resp.get("ok", false)):
				push_error("FAIL: remove: %s" % str(resp.get("error", "")))
				_failed = true
		17:
			if bool(resp.get("ok", true)) or str(resp.get("error", "")).is_empty():
				push_error("FAIL: removed node should be gone")
				_failed = true
		18:
			var editor_info: Dictionary = resp.get("result")
			if not bool(resp.get("ok", false)) or str(editor_info.get("godot_version", "")).is_empty() \
					or str(editor_info.get("project_name", "")).is_empty():
				push_error("FAIL: editor info %s" % JSON.stringify(editor_info))
				_failed = true
		19:
			var dump: Dictionary = resp.get("result")
			var dump_children: Array = dump.get("children", [])
			if not bool(resp.get("ok", false)) or str(dump.get("path", "")) != "/" or dump_children.size() != 2:
				push_error("FAIL: tree dump %s" % JSON.stringify(dump))
				_failed = true
		20:
			if not bool((resp.get("result") as Dictionary).modified):
				push_error("FAIL: scene modified flag should be true")
				_failed = true
		21:
			if not bool(resp.get("ok", false)):
				push_error("FAIL: add Sub: %s" % str(resp.get("error", "")))
				_failed = true
		22:
			var sub_found: Array = resp.get("result")
			if sub_found.size() != 1 or str((sub_found[0] as Dictionary).path) != "/Building/Sub":
				push_error("FAIL: find under sub-root uses absolute paths: %s" % JSON.stringify(sub_found))
				_failed = true
		23:
			var g23: Dictionary = resp.get("result")
			if not bool(resp.get("ok", false)) or str(g23.get("uid", "")) != ResourceUID.id_to_text(_uid_id):
				push_error("FAIL: get_uid by path %s" % JSON.stringify(resp))
				_failed = true
		24:
			var g24: Dictionary = resp.get("result")
			if not bool(resp.get("ok", false)) or str(g24.get("path", "")) != _uid_path:
				push_error("FAIL: get_uid by uid %s" % JSON.stringify(resp))
				_failed = true
		25:
			if bool(resp.get("ok", true)) or str(resp.get("error", "")).is_empty():
				push_error("FAIL: get_uid with no args should error")
				_failed = true
		26:
			if bool(resp.get("ok", true)) or str(resp.get("error", "")).is_empty():
				push_error("FAIL: get_uid with non-uid string should error")
				_failed = true
		27:
			if bool(resp.get("ok", true)) or str(resp.get("error", "")).is_empty():
				push_error("FAIL: get_uid with unknown uid should error")
				_failed = true
		28:
			var stats: Dictionary = resp.get("result")
			if not bool(resp.get("ok", false)):
				push_error("FAIL: update_project_uids: %s" % str(resp.get("error", "")))
				_failed = true
			elif not stats.has("scanned") or not stats.has("generated"):
				push_error("FAIL: update_project_uids stats %s" % JSON.stringify(stats))
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
