## Bounded, thread-safe ring buffer for the engine's message/error stream.
##
## The editor plugin registers an inner ``CaptureLogger`` (a ``Logger`` subclass,
## Godot >= 4.5 only) that captures ``print``/``push_error``/``push_warning``
## output from *other threads* and appends it here. The TreeServer reads it on
## the main thread via ``read_since()``, giving delta-based (since an offset)
## reads backed by a fixed-size ring buffer so memory stays bounded.
##
## No ``class_name`` is used on purpose: the inner ``CaptureLogger extends
## Logger`` must only be parsed on Godot >= 4.5, so it stays an on-demand inner
## class and never breaks older editors that lack ``Logger``.

extends RefCounted

const MAX_ENTRIES: int = 2000

var _mutex := Mutex.new()
var _entries: Array = []
var _base_seq := 0  # seq of the first retained entry (0 when empty)
var _next_seq := 1  # seq to assign to the next appended entry


## Append a captured log entry. Safe to call from any thread.
func append(level: String, message: String) -> void:
	var entry := {"seq": _next_seq, "level": level, "message": message}
	_next_seq += 1
	_mutex.lock()
	_entries.append(entry)
	var over := _entries.size() - MAX_ENTRIES
	if over > 0:
		_entries = _entries.slice(over)
	if not _entries.is_empty():
		_base_seq = int(_entries[0].seq)
	_mutex.unlock()


## Return entries with seq > `since` (up to `limit`, 0 = unlimited) plus the
## current cursor. Thread-safe; cheap for the main thread to call per request.
func read_since(since: int, limit: int = 0) -> Dictionary:
	_mutex.lock()
	var out: Array = []
	for entry in _entries:
		if int(entry.seq) > since:
			out.append(entry)
			if limit > 0 and out.size() >= limit:
				break
	var base := _base_seq
	var next := _next_seq
	_mutex.unlock()
	return {"seq": next, "base_seq": base, "entries": out}


## Captures the engine's message/error stream into a LogBuffer.
## Only instantiate when Godot supports Logger (>= 4.5).
class CaptureLogger extends Logger:
	var buffer: RefCounted = null

	## print()/push_print and stdout/stderr-style messages. error=true => stderr.
	func _log_message(message: String, error: bool) -> void:
		if buffer == null:
			return
		buffer.append("error" if error else "info", message)

	## push_error()/push_warning() and engine warnings/errors.
	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		editor_notify: bool,
		error_type: int,
		script_backtraces: Array
	) -> void:
		if buffer == null:
			return
		var level := "warning" if error_type == Logger.ERROR_TYPE_WARNING else "error"
		var detail := rationale if not rationale.is_empty() else code
		var location := ""
		if not file.is_empty():
			location = "%s:%d" % [file, line]
		var text := ""
		if location != "" and detail != "":
			text = "%s %s" % [location, detail]
		elif location != "":
			text = location
		else:
			text = detail
		if not function.is_empty():
			text = "%s(): %s" % [function, text] if text != "" else "%s()" % function
		buffer.append(level, text)
