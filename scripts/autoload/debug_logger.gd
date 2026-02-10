class_name DebugLogger
extends Node
## Writes all debug output to a log file for external viewing.
## On web exports, file I/O is unavailable so all output goes to browser console.

const LOG_PATH := "res://debug_log.txt"
const MAX_LOG_SIZE := 100000  # Truncate if too large

var _log_file: FileAccess
var _buffer: PackedStringArray = []
var _is_web: bool = false


func _ready() -> void:
	_is_web = OS.has_feature("web")

	if _is_web:
		print("DebugLogger: Running in browser - logging to console only")
		return

	# Clear previous log
	_log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _log_file:
		_log_file.store_string("=== Arena Debug Log - %s ===\n\n" % Time.get_datetime_string_from_system())
		_log_file.close()

	print("DebugLogger: Logging to %s" % ProjectSettings.globalize_path(LOG_PATH))


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_flush_buffer()


func log(message: String) -> void:
	"""Log a message to both console and file."""
	print(message)
	if not _is_web:
		_write_to_file(message)


func log_error(message: String) -> void:
	"""Log an error message."""
	push_error(message)
	if not _is_web:
		_write_to_file("[ERROR] " + message)


func log_warning(message: String) -> void:
	"""Log a warning message."""
	push_warning(message)
	if not _is_web:
		_write_to_file("[WARN] " + message)


func _write_to_file(message: String) -> void:
	_buffer.append("[%s] %s" % [Time.get_time_string_from_system(), message])

	# Flush every 10 messages for near-real-time viewing
	if _buffer.size() >= 10:
		_flush_buffer()


func _flush_buffer() -> void:
	if _is_web or _buffer.is_empty():
		return

	_log_file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if _log_file:
		_log_file.seek_end()
		for line in _buffer:
			_log_file.store_string(line + "\n")
		_log_file.close()

	_buffer.clear()


func clear_log() -> void:
	"""Clear the log file."""
	if _is_web:
		print("=== Log Cleared - %s ===" % Time.get_datetime_string_from_system())
		return

	_log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _log_file:
		_log_file.store_string("=== Log Cleared - %s ===\n\n" % Time.get_datetime_string_from_system())
		_log_file.close()
