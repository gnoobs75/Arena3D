extends Control
class_name DraggableWrapper
## Wraps any Control with a draggable title bar and resize handle.
## Registers with DevLayoutManager for persistence across sessions.

signal layout_changed(panel_id: String, pos: Vector2, sz: Vector2)

const TITLE_BAR_HEIGHT := 26
const RESIZE_HANDLE_SIZE := 14
const MIN_SIZE := Vector2(150, 100)

var panel_id: String = ""
var _content: Control = null
var _title_bar: Control = null
var _title_label: Label = null
var _resize_handle: Control = null
var _default_pos := Vector2.ZERO
var _default_size := Vector2.ZERO

# Drag state
var _dragging := false
var _drag_offset := Vector2.ZERO
var _resizing := false
var _resize_start_mouse := Vector2.ZERO
var _resize_start_size := Vector2.ZERO


static func wrap(content: Control, id: String, display_name: String, default_pos: Vector2, default_size: Vector2) -> DraggableWrapper:
	"""Create a DraggableWrapper around a control. Call BEFORE adding to scene tree."""
	var wrapper := DraggableWrapper.new()
	wrapper.panel_id = id
	wrapper.name = "Wrap_" + id
	wrapper._content = content
	wrapper._default_pos = default_pos
	wrapper._default_size = default_size

	# Apply saved layout or defaults
	var saved := _get_saved_layout(id)
	var pos: Vector2 = saved.get("position", default_pos)
	var sz: Vector2 = saved.get("size", default_size)
	wrapper.position = pos
	wrapper.size = sz
	wrapper.custom_minimum_size = MIN_SIZE

	wrapper._build(display_name)
	return wrapper


static func wrap_existing(content: Control, id: String, display_name: String, default_size: Vector2) -> DraggableWrapper:
	"""Wrap an existing in-tree control. Reparents it into the wrapper.
	The wrapper takes the content's current position as its default."""
	var parent := content.get_parent()
	var default_pos := Vector2(content.global_position) if content.is_inside_tree() else content.position

	var wrapper := DraggableWrapper.new()
	wrapper.panel_id = id
	wrapper.name = "Wrap_" + id
	wrapper._content = content
	wrapper._default_pos = default_pos
	wrapper._default_size = default_size

	# Remove content from old parent
	if parent:
		parent.remove_child(content)

	# Clear any anchor-based positioning on the content
	content.anchor_left = 0
	content.anchor_top = 0
	content.anchor_right = 0
	content.anchor_bottom = 0
	content.offset_left = 0
	content.offset_top = 0
	content.offset_right = 0
	content.offset_bottom = 0

	# Apply saved layout or defaults
	var saved := _get_saved_layout(id)
	var pos: Vector2 = saved.get("position", default_pos)
	var sz: Vector2 = saved.get("size", default_size)
	wrapper.position = pos
	wrapper.size = sz
	wrapper.custom_minimum_size = MIN_SIZE

	wrapper._build(display_name)

	# Add wrapper where content was
	if parent:
		parent.add_child(wrapper)

	return wrapper


static func _get_saved_layout(id: String) -> Dictionary:
	if DevLayout and DevLayout.has_layout(id):
		return DevLayout.get_layout(id)
	return {}


func _build(display_name: String) -> void:
	"""Build title bar, content area, and resize handle."""
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

	# Title bar
	_title_bar = PanelContainer.new()
	_title_bar.custom_minimum_size = Vector2(0, TITLE_BAR_HEIGHT)
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title_bar.offset_bottom = TITLE_BAR_HEIGHT
	_title_bar.gui_input.connect(_on_title_bar_input)
	add_child(_title_bar)

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.18, 0.16, 0.22, 0.95)
	bar_style.border_color = Color(0.4, 0.35, 0.5)
	bar_style.border_width_bottom = 1
	bar_style.corner_radius_top_left = 4
	bar_style.corner_radius_top_right = 4
	_title_bar.add_theme_stylebox_override("panel", bar_style)

	_title_label = Label.new()
	_title_label.text = "  ⠿  " + display_name
	_title_label.add_theme_font_size_override("font_size", 12)
	_title_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_margin := MarginContainer.new()
	bar_margin.add_theme_constant_override("margin_left", 4)
	bar_margin.add_theme_constant_override("margin_top", 2)
	bar_margin.add_theme_constant_override("margin_bottom", 2)
	_title_bar.add_child(bar_margin)
	bar_margin.add_child(_title_label)

	# Content area — fills below title bar
	if _content:
		_content.set_anchors_preset(Control.PRESET_FULL_RECT)
		_content.offset_top = TITLE_BAR_HEIGHT
		_content.offset_bottom = 0
		_content.offset_left = 0
		_content.offset_right = 0
		add_child(_content)

	# Resize handle (bottom-right corner)
	_resize_handle = Control.new()
	_resize_handle.custom_minimum_size = Vector2(RESIZE_HANDLE_SIZE, RESIZE_HANDLE_SIZE)
	_resize_handle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_resize_handle.offset_left = -RESIZE_HANDLE_SIZE
	_resize_handle.offset_top = -RESIZE_HANDLE_SIZE
	_resize_handle.offset_right = 0
	_resize_handle.offset_bottom = 0
	_resize_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_resize_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_resize_handle.gui_input.connect(_on_resize_input)
	_resize_handle.draw.connect(_draw_resize_handle)
	add_child(_resize_handle)


func _draw_resize_handle() -> void:
	var s := RESIZE_HANDLE_SIZE
	var c := Color(0.5, 0.45, 0.55, 0.7)
	for i in range(3):
		for j in range(3 - i):
			var x := s - 4 - j * 4
			var y := s - 4 - i * 4
			_resize_handle.draw_circle(Vector2(x, y), 1.5, c)


func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
			# Bring to front
			var parent := get_parent()
			if parent:
				parent.move_child(self, -1)
		else:
			_dragging = false
			_persist_layout()
	elif event is InputEventMouseMotion and _dragging:
		var new_pos := get_global_mouse_position() - _drag_offset
		var vp := get_viewport_rect().size
		new_pos.x = clampf(new_pos.x, -size.x + 60, vp.x - 60)
		new_pos.y = clampf(new_pos.y, 0, vp.y - TITLE_BAR_HEIGHT)
		global_position = new_pos


func _on_resize_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_resizing = true
			_resize_start_mouse = get_global_mouse_position()
			_resize_start_size = size
		else:
			_resizing = false
			_persist_layout()
	elif event is InputEventMouseMotion and _resizing:
		var delta := get_global_mouse_position() - _resize_start_mouse
		var new_size := _resize_start_size + delta
		new_size.x = maxf(new_size.x, MIN_SIZE.x)
		new_size.y = maxf(new_size.y, MIN_SIZE.y)
		size = new_size


func _persist_layout() -> void:
	if panel_id != "" and DevLayout:
		DevLayout.save_layout(panel_id, position, size)
		layout_changed.emit(panel_id, position, size)


func set_panel_title(text: String) -> void:
	if _title_label:
		_title_label.text = "  ⠿  " + text


func restore_default() -> void:
	"""Reset to default position and size."""
	position = _default_pos
	size = _default_size
	_persist_layout()
