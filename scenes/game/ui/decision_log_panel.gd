class_name DecisionLogPanel
extends PanelContainer
## DecisionLogPanel - Displays AI reasoning in Developer Mode
## Shows decision breakdowns, scores, and provides step controls

signal step_requested()
signal execute_all_requested()

# UI Elements
var title_label: Label
var status_label: Label
var scroll_container: ScrollContainer
var log_container: VBoxContainer
var step_button: Button
var execute_all_button: Button
var clear_button: Button

# Configuration
const MAX_LOG_ENTRIES := 100
const PANEL_WIDTH := 380
const PANEL_HEIGHT := 700

# Player colors
const PLAYER1_COLOR := Color(0.3, 0.5, 0.9)  # Blue
const PLAYER2_COLOR := Color(0.9, 0.35, 0.35)  # Red

var current_entry_count := 0


func _ready() -> void:
	_build_ui()
	_style_panel()


func _build_ui() -> void:
	"""Build the UI programmatically."""
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	title_label = Label.new()
	title_label.text = "AI Decision Log"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	clear_button = Button.new()
	clear_button.text = "Clear"
	clear_button.custom_minimum_size = Vector2(60, 28)
	clear_button.pressed.connect(clear_log)
	header.add_child(clear_button)
	_style_small_button(clear_button)

	# Status line
	status_label = Label.new()
	status_label.text = "Waiting for game to start..."
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
	vbox.add_child(status_label)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scrollable log area
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll_container)

	log_container = VBoxContainer.new()
	log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_container.add_theme_constant_override("separation", 6)
	scroll_container.add_child(log_container)

	# Control buttons
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(controls)

	step_button = Button.new()
	step_button.text = "Step >"
	step_button.custom_minimum_size = Vector2(100, 40)
	step_button.pressed.connect(_on_step_pressed)
	step_button.disabled = true
	controls.add_child(step_button)
	_style_action_button(step_button, Color(0.2, 0.4, 0.3))

	execute_all_button = Button.new()
	execute_all_button.text = "Execute All >>"
	execute_all_button.custom_minimum_size = Vector2(120, 40)
	execute_all_button.pressed.connect(_on_execute_all_pressed)
	execute_all_button.disabled = true
	controls.add_child(execute_all_button)
	_style_action_button(execute_all_button, Color(0.3, 0.25, 0.4))


func _style_panel() -> void:
	"""Apply styling to the panel."""
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.border_color = Color(0.3, 0.28, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)


func _style_action_button(button: Button, base_color: Color) -> void:
	"""Style an action button with hover/pressed states."""
	var normal := StyleBoxFlat.new()
	normal.bg_color = base_color
	normal.border_color = base_color.lightened(0.3)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(5)

	var hover := StyleBoxFlat.new()
	hover.bg_color = base_color.lightened(0.15)
	hover.border_color = base_color.lightened(0.45)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(5)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = base_color.darkened(0.15)
	pressed.border_color = base_color
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(5)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.15, 0.15, 0.15)
	disabled.border_color = Color(0.25, 0.25, 0.25)
	disabled.set_border_width_all(2)
	disabled.set_corner_radius_all(5)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)

	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))


func _style_small_button(button: Button) -> void:
	"""Style a small utility button."""
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.2, 0.2, 0.22)
	normal.border_color = Color(0.35, 0.35, 0.38)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.28, 0.28, 0.3)
	hover.border_color = Color(0.45, 0.45, 0.48)
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(3)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_font_size_override("font_size", 12)


func _on_step_pressed() -> void:
	step_requested.emit()
	set_buttons_enabled(false)


func _on_execute_all_pressed() -> void:
	execute_all_requested.emit()
	set_buttons_enabled(false)


func set_buttons_enabled(enabled: bool) -> void:
	"""Enable or disable the step/execute buttons."""
	step_button.disabled = not enabled
	execute_all_button.disabled = not enabled


func set_status(text: String) -> void:
	"""Update the status label."""
	status_label.text = text


func clear_log() -> void:
	"""Clear all log entries."""
	for child in log_container.get_children():
		child.queue_free()
	current_entry_count = 0


func add_turn_header(player_id: int, champion_name: String) -> void:
	"""Add a header for a new AI turn."""
	_trim_old_entries()

	var header := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	var player_color := PLAYER1_COLOR if player_id == 1 else PLAYER2_COLOR
	header_style.bg_color = player_color.darkened(0.6)
	header_style.border_color = player_color
	header_style.set_border_width_all(1)
	header_style.border_width_left = 4
	header_style.set_corner_radius_all(3)
	header.add_theme_stylebox_override("panel", header_style)

	var hdr_margin := MarginContainer.new()
	hdr_margin.add_theme_constant_override("margin_left", 8)
	hdr_margin.add_theme_constant_override("margin_right", 8)
	hdr_margin.add_theme_constant_override("margin_top", 4)
	hdr_margin.add_theme_constant_override("margin_bottom", 4)
	header.add_child(hdr_margin)

	var label := Label.new()
	var player_name := "Player 1 (Blue)" if player_id == 1 else "Player 2 (Red)"
	label.text = "%s - %s's Turn" % [player_name, champion_name]
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", player_color.lightened(0.3))
	hdr_margin.add_child(label)

	log_container.add_child(header)
	current_entry_count += 1
	_scroll_to_bottom()


func add_decision(player_id: int, action_data: Dictionary) -> void:
	"""Add an AI decision entry to the log."""
	_trim_old_entries()

	var entry := _create_decision_entry(player_id, action_data)
	log_container.add_child(entry)
	current_entry_count += 1
	_scroll_to_bottom()


func _create_decision_entry(player_id: int, action_data: Dictionary) -> Control:
	"""Create a visual entry for an AI decision."""
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var player_color := PLAYER1_COLOR if player_id == 1 else PLAYER2_COLOR

	# Action description
	var action_label := RichTextLabel.new()
	action_label.bbcode_enabled = true
	action_label.fit_content = true
	action_label.scroll_active = false

	var reasoning: Dictionary = action_data.get("reasoning", {})
	var action_desc: String = reasoning.get("action_description", "Unknown action")
	var total_score: float = reasoning.get("total_score", 0.0)

	var color_hex := "#%s" % player_color.lightened(0.2).to_html(false)
	action_label.text = "[color=%s][b]▶ %s[/b][/color] [color=#888](%.1f)[/color]" % [color_hex, action_desc, total_score]
	container.add_child(action_label)

	# Reasoning breakdown
	var breakdown: Array = reasoning.get("breakdown", [])
	if not breakdown.is_empty():
		var breakdown_text := RichTextLabel.new()
		breakdown_text.bbcode_enabled = true
		breakdown_text.fit_content = true
		breakdown_text.scroll_active = false

		var parts: Array[String] = []
		for item: Dictionary in breakdown:
			var factor: String = item.get("factor", "?")
			var value: float = item.get("value", 0.0)
			var value_color := "#8a8" if value >= 0 else "#a88"
			var sign := "+" if value >= 0 else ""
			parts.append("  [color=#666]•[/color] %s: [color=%s]%s%.1f[/color]" % [factor, value_color, sign, value])

		breakdown_text.text = "\n".join(parts)
		breakdown_text.add_theme_font_size_override("normal_font_size", 11)
		container.add_child(breakdown_text)

	return container


func add_action_result(success: bool, message: String) -> void:
	"""Add a result entry showing what happened after execution."""
	var label := Label.new()
	label.text = "  → %s" % message
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5) if success else Color(0.7, 0.5, 0.5))
	log_container.add_child(label)
	_scroll_to_bottom()


func add_alternatives(alternatives: Array, max_show: int = 3) -> void:
	"""Show top alternative actions that weren't chosen."""
	if alternatives.size() <= 1:
		return

	var label := Label.new()
	label.text = "  Other options considered:"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	log_container.add_child(label)

	var count := 0
	for i in range(1, alternatives.size()):
		if count >= max_show:
			break

		var alt: Dictionary = alternatives[i]
		var alt_reasoning: Dictionary = alt.get("reasoning", {})
		var alt_desc: String = alt_reasoning.get("action_description", "?")
		var alt_score: float = alt.get("randomized_score", 0.0)

		var alt_label := Label.new()
		alt_label.text = "    • %s (%.1f)" % [alt_desc, alt_score]
		alt_label.add_theme_font_size_override("font_size", 10)
		alt_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
		log_container.add_child(alt_label)
		count += 1

	_scroll_to_bottom()


func _trim_old_entries() -> void:
	"""Remove old entries if we exceed the max."""
	while current_entry_count >= MAX_LOG_ENTRIES:
		var first_child := log_container.get_child(0)
		if first_child:
			first_child.queue_free()
			current_entry_count -= 1
		else:
			break


func _scroll_to_bottom() -> void:
	"""Scroll to the bottom of the log."""
	await get_tree().process_frame
	scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)
