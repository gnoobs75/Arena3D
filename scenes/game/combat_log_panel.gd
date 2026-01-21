extends PanelContainer
class_name CombatLogPanel
## CombatLogPanel - Scrollable UI panel showing combat log entries
## Can be toggled open/closed, supports filtering and export

signal visibility_toggled(is_visible: bool)

const PANEL_WIDTH := 350
const PANEL_HEIGHT := 400
const ENTRY_HEIGHT := 20

var _scroll_container: ScrollContainer
var _entries_container: VBoxContainer
var _header: HBoxContainer
var _title_label: Label
var _close_button: Button
var _clear_button: Button
var _save_button: Button
var _auto_scroll: bool = true
var _filter_type: int = -1  # -1 = show all


func _ready() -> void:
	_setup_panel()
	_setup_header()
	_setup_scroll_area()
	_connect_signals()

	# Start hidden
	visible = false


func _setup_panel() -> void:
	"""Configure panel appearance."""
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# Position in bottom-left
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 10
	offset_bottom = -10
	offset_right = offset_left + PANEL_WIDTH
	offset_top = offset_bottom - PANEL_HEIGHT

	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.border_color = Color(0.3, 0.3, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)


func _setup_header() -> void:
	"""Create header with title and buttons."""
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 8)
	vbox.add_child(_header)

	_title_label = Label.new()
	_title_label.text = "Combat Log"
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_title_label)

	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.custom_minimum_size = Vector2(50, 24)
	_save_button.pressed.connect(_on_save_pressed)
	_style_button(_save_button, Color(0.3, 0.4, 0.5))
	_header.add_child(_save_button)

	_clear_button = Button.new()
	_clear_button.text = "Clear"
	_clear_button.custom_minimum_size = Vector2(50, 24)
	_clear_button.pressed.connect(_on_clear_pressed)
	_style_button(_clear_button, Color(0.4, 0.35, 0.3))
	_header.add_child(_clear_button)

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.custom_minimum_size = Vector2(24, 24)
	_close_button.pressed.connect(_on_close_pressed)
	_style_button(_close_button, Color(0.5, 0.3, 0.3))
	_header.add_child(_close_button)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scroll area goes in the vbox
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll_container)

	_entries_container = VBoxContainer.new()
	_entries_container.add_theme_constant_override("separation", 2)
	_entries_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.add_child(_entries_container)


func _setup_scroll_area() -> void:
	"""Scroll area is set up in _setup_header now."""
	pass


func _style_button(button: Button, base_color: Color) -> void:
	"""Apply styling to a button."""
	var normal := StyleBoxFlat.new()
	normal.bg_color = base_color
	normal.set_border_width_all(1)
	normal.border_color = base_color.lerp(Color.WHITE, 0.2)
	normal.set_corner_radius_all(3)

	var hover := StyleBoxFlat.new()
	hover.bg_color = base_color.lerp(Color.WHITE, 0.15)
	hover.set_border_width_all(1)
	hover.border_color = base_color.lerp(Color.WHITE, 0.4)
	hover.set_corner_radius_all(3)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", Color.WHITE)


func _connect_signals() -> void:
	"""Connect to CombatLog signals."""
	# CombatLog is an autoload, access it directly
	if CombatLog:
		CombatLog.entry_added.connect(_on_entry_added)
		CombatLog.log_cleared.connect(_on_log_cleared)
	else:
		# Connect after a frame to ensure autoload is ready
		call_deferred("_deferred_connect")


func _deferred_connect() -> void:
	"""Connect to CombatLog after autoloads are ready."""
	if CombatLog:
		CombatLog.entry_added.connect(_on_entry_added)
		CombatLog.log_cleared.connect(_on_log_cleared)
		# Load existing entries
		for entry in CombatLog.entries:
			_add_entry_label(entry)


func _on_entry_added(entry: Dictionary) -> void:
	"""Handle new log entry."""
	# Check filter
	if _filter_type >= 0 and entry.type != _filter_type:
		return

	_add_entry_label(entry)

	# Auto-scroll to bottom
	if _auto_scroll and visible:
		await get_tree().process_frame
		_scroll_container.scroll_vertical = int(_scroll_container.get_v_scroll_bar().max_value)


func _add_entry_label(entry: Dictionary) -> void:
	"""Create a label for a log entry."""
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(PANEL_WIDTH - 30, 0)
	label.add_theme_font_size_override("normal_font_size", 10)

	# Format with color
	var color: Color = entry.get("color", Color.WHITE)
	var hex_color := color.to_html(false)
	var message: String = entry.get("message", "")

	# Add round prefix
	var round_num: int = entry.get("round", 0)
	var prefix := "[color=#666666][R%d][/color] " % round_num if round_num > 0 else ""

	label.text = "%s[color=#%s]%s[/color]" % [prefix, hex_color, message]

	_entries_container.add_child(label)


func _on_log_cleared() -> void:
	"""Handle log clear."""
	for child in _entries_container.get_children():
		child.queue_free()


func _on_close_pressed() -> void:
	"""Close the panel."""
	visible = false
	visibility_toggled.emit(false)


func _on_clear_pressed() -> void:
	"""Clear the log."""
	if CombatLog:
		CombatLog.clear()


func _on_save_pressed() -> void:
	"""Save log to file."""
	if CombatLog:
		CombatLog.save_to_file()


func toggle() -> void:
	"""Toggle panel visibility."""
	visible = not visible
	visibility_toggled.emit(visible)

	# Scroll to bottom when opened
	if visible and _auto_scroll:
		await get_tree().process_frame
		_scroll_container.scroll_vertical = int(_scroll_container.get_v_scroll_bar().max_value)


func show_log() -> void:
	"""Show the panel."""
	visible = true
	visibility_toggled.emit(true)


func hide_log() -> void:
	"""Hide the panel."""
	visible = false
	visibility_toggled.emit(false)
