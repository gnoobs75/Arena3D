extends Node
class_name DevLayoutManagerClass
## DevLayoutManager - Persists UI panel positions and sizes across sessions.
## Saves to user://dev_layout.cfg

const CONFIG_PATH := "user://dev_layout.cfg"

var _layouts: Dictionary = {}  # panel_id -> { "position": Vector2, "size": Vector2 }
var _config := ConfigFile.new()


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	"""Load saved layout from disk."""
	var err := _config.load(CONFIG_PATH)
	if err != OK:
		return  # No saved config, use defaults

	for key in _config.get_section_keys("layouts"):
		var data: Dictionary = _config.get_value("layouts", key, {})
		if data.has("px") and data.has("py") and data.has("sx") and data.has("sy"):
			_layouts[key] = {
				"position": Vector2(data["px"], data["py"]),
				"size": Vector2(data["sx"], data["sy"]),
			}


func _save_config() -> void:
	"""Save all layouts to disk."""
	for key in _layouts:
		var layout: Dictionary = _layouts[key]
		var pos: Vector2 = layout["position"]
		var sz: Vector2 = layout["size"]
		_config.set_value("layouts", key, {
			"px": pos.x, "py": pos.y,
			"sx": sz.x, "sy": sz.y,
		})
	_config.save(CONFIG_PATH)


func has_layout(panel_id: String) -> bool:
	return _layouts.has(panel_id)


func get_layout(panel_id: String) -> Dictionary:
	"""Returns { "position": Vector2, "size": Vector2 } or empty dict."""
	return _layouts.get(panel_id, {})


func save_layout(panel_id: String, pos: Vector2, sz: Vector2) -> void:
	"""Save a panel's position and size, and persist to disk."""
	_layouts[panel_id] = {"position": pos, "size": sz}
	_save_config()


func clear_all() -> void:
	"""Reset all saved layouts."""
	_layouts.clear()
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists("dev_layout.cfg"):
		dir.remove("dev_layout.cfg")
	_config = ConfigFile.new()
