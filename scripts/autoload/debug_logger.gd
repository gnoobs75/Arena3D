class_name DebugLogger
extends Node
## Writes all debug output to a log file for external viewing

const LOG_PATH := "res://debug_log.txt"
const MAX_LOG_SIZE := 100000  # Truncate if too large

var _log_file: FileAccess
var _buffer: PackedStringArray = []


func _ready() -> void:
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
	_write_to_file(message)


func log_error(message: String) -> void:
	"""Log an error message."""
	push_error(message)
	_write_to_file("[ERROR] " + message)


func log_warning(message: String) -> void:
	"""Log a warning message."""
	push_warning(message)
	_write_to_file("[WARN] " + message)


func _write_to_file(message: String) -> void:
	_buffer.append("[%s] %s" % [Time.get_time_string_from_system(), message])

	# Flush every 10 messages for near-real-time viewing
	if _buffer.size() >= 10:
		_flush_buffer()


func _flush_buffer() -> void:
	if _buffer.is_empty():
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
	_log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _log_file:
		_log_file.store_string("=== Log Cleared - %s ===\n\n" % Time.get_datetime_string_from_system())
		_log_file.close()
