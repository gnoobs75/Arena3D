class_name ReplayPanel
extends Control
## Panel for replaying recorded matches

signal replay_started(match_result: MatchResult)
signal replay_ended()
signal action_played(action_index: int, action: MatchResult.ReplayAction)

var current_match: MatchResult
var current_action_index: int = -1
var is_playing: bool = false
var playback_speed: float = 1.0
var playback_timer: float = 0.0

# UI Elements
var board_display: Control
var controls_container: HBoxContainer
var play_button: Button
var step_forward_button: Button
var step_back_button: Button
var speed_slider: HSlider
var speed_label: Label
var action_label: Label
var progress_bar: ProgressBar
var match_selector: OptionButton
var info_panel: RichTextLabel

# Board state for display
var champion_positions: Dictionary = {}  # champion_id -> Vector2i
var champion_hp: Dictionary = {}  # champion_id -> int
var champion_names: Dictionary = {}  # champion_id -> String
var champion_player: Dictionary = {}  # champion_id -> player_id (1 or 2)

# Available matches to replay
var available_matches: Array[MatchResult] = []


func _ready() -> void:
	_build_ui()


func _process(delta: float) -> void:
	if is_playing and current_match != null:
		playback_timer += delta * playback_speed
		if playback_timer >= 0.5:  # Action every 0.5 seconds at 1x speed
			playback_timer = 0.0
			_step_forward()


func _build_ui() -> void:
	# Main vertical layout
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	# Header with match selector
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	var select_label := Label.new()
	select_label.text = "Select Match:"
	select_label.add_theme_font_size_override("font_size", 16)
	header.add_child(select_label)

	match_selector = OptionButton.new()
	match_selector.custom_minimum_size.x = 300
	match_selector.item_selected.connect(_on_match_selected)
	header.add_child(match_selector)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# Main content area (board + info)
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(content_hbox)

	# Board display
	var board_container := PanelContainer.new()
	board_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var board_style := StyleBoxFlat.new()
	board_style.bg_color = Color(0.1, 0.12, 0.15)
	board_style.set_corner_radius_all(5)
	board_container.add_theme_stylebox_override("panel", board_style)
	content_hbox.add_child(board_container)

	board_display = Control.new()
	board_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_display.draw.connect(_draw_board)
	board_container.add_child(board_display)

	# Info panel
	var info_container := PanelContainer.new()
	info_container.custom_minimum_size.x = 250
	info_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.08, 0.08, 0.1)
	info_style.set_corner_radius_all(5)
	info_style.set_content_margin_all(10)
	info_container.add_theme_stylebox_override("panel", info_style)
	content_hbox.add_child(info_container)

	info_panel = RichTextLabel.new()
	info_panel.bbcode_enabled = true
	info_panel.add_theme_font_size_override("normal_font_size", 14)
	info_container.add_child(info_panel)

	# Action display
	action_label = Label.new()
	action_label.text = "No match loaded"
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_label.add_theme_font_size_override("font_size", 16)
	action_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
	vbox.add_child(action_label)

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 20
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	vbox.add_child(progress_bar)

	# Controls
	controls_container = HBoxContainer.new()
	controls_container.add_theme_constant_override("separation", 10)
	controls_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(controls_container)

	# Step back button
	step_back_button = Button.new()
	step_back_button.text = "< Step"
	step_back_button.custom_minimum_size = Vector2(80, 35)
	step_back_button.pressed.connect(_step_back)
	controls_container.add_child(step_back_button)

	# Play/Pause button
	play_button = Button.new()
	play_button.text = "Play"
	play_button.custom_minimum_size = Vector2(80, 35)
	play_button.pressed.connect(_toggle_playback)
	controls_container.add_child(play_button)

	# Step forward button
	step_forward_button = Button.new()
	step_forward_button.text = "Step >"
	step_forward_button.custom_minimum_size = Vector2(80, 35)
	step_forward_button.pressed.connect(_step_forward)
	controls_container.add_child(step_forward_button)

	# Speed control
	var speed_container := HBoxContainer.new()
	speed_container.add_theme_constant_override("separation", 5)
	controls_container.add_child(speed_container)

	var speed_text := Label.new()
	speed_text.text = "Speed:"
	speed_container.add_child(speed_text)

	speed_slider = HSlider.new()
	speed_slider.min_value = 0.25
	speed_slider.max_value = 4.0
	speed_slider.step = 0.25
	speed_slider.value = 1.0
	speed_slider.custom_minimum_size.x = 100
	speed_slider.value_changed.connect(_on_speed_changed)
	speed_container.add_child(speed_slider)

	speed_label = Label.new()
	speed_label.text = "1.0x"
	speed_label.custom_minimum_size.x = 40
	speed_container.add_child(speed_label)

	# Restart button
	var restart_btn := Button.new()
	restart_btn.text = "Restart"
	restart_btn.custom_minimum_size = Vector2(80, 35)
	restart_btn.pressed.connect(_restart_replay)
	controls_container.add_child(restart_btn)

	_update_controls()


func set_available_matches(matches: Array[MatchResult]) -> void:
	available_matches = matches
	match_selector.clear()

	if matches.is_empty():
		match_selector.add_item("No matches available")
		match_selector.disabled = true
		return

	match_selector.disabled = false
	for i in range(matches.size()):
		var m := matches[i]
		var p1 := "/".join(m.p1_champions)
		var p2 := "/".join(m.p2_champions)
		var winner_str := "Draw" if m.winner == 0 else ("P1 Win" if m.winner == 1 else "P2 Win")
		match_selector.add_item("Match %d: %s vs %s (%s)" % [i + 1, p1, p2, winner_str])


func _on_match_selected(index: int) -> void:
	if index >= 0 and index < available_matches.size():
		load_match(available_matches[index])


func load_match(match_result: MatchResult) -> void:
	current_match = match_result
	current_action_index = -1
	is_playing = false
	playback_timer = 0.0

	# Initialize board state
	_init_board_state()

	# Update progress
	if current_match.replay_actions.size() > 0:
		progress_bar.max_value = current_match.replay_actions.size()
	else:
		progress_bar.max_value = 1
	progress_bar.value = 0

	_update_controls()
	_update_info_panel()
	board_display.queue_redraw()
	replay_started.emit(match_result)


func _init_board_state() -> void:
	"""Initialize board to starting positions."""
	champion_positions.clear()
	champion_hp.clear()
	champion_names.clear()
	champion_player.clear()

	if current_match == null:
		return

	# Set initial positions (standard starting positions)
	# P1 champions at bottom (y=8), P2 at top (y=1)
	var p1_x := [2, 7]
	var p2_x := [2, 7]

	for i in range(current_match.p1_champions.size()):
		var champ_name: String = current_match.p1_champions[i]
		var champ_id := "%s_p1_%d" % [champ_name.to_lower(), i]
		champion_positions[champ_id] = Vector2i(p1_x[i], 8)
		champion_hp[champ_id] = 20
		champion_names[champ_id] = champ_name
		champion_player[champ_id] = 1

	for i in range(current_match.p2_champions.size()):
		var champ_name: String = current_match.p2_champions[i]
		var champ_id := "%s_p2_%d" % [champ_name.to_lower(), i]
		champion_positions[champ_id] = Vector2i(p2_x[i], 1)
		champion_hp[champ_id] = 20
		champion_names[champ_id] = champ_name
		champion_player[champ_id] = 2

	action_label.text = "Match loaded - Press Play or Step to begin"


func _toggle_playback() -> void:
	is_playing = not is_playing
	play_button.text = "Pause" if is_playing else "Play"


func _step_forward() -> void:
	if current_match == null or current_match.replay_actions.is_empty():
		return

	current_action_index += 1

	if current_action_index >= current_match.replay_actions.size():
		current_action_index = current_match.replay_actions.size() - 1
		is_playing = false
		play_button.text = "Play"
		action_label.text = "Replay complete"
		replay_ended.emit()
		return

	var action := current_match.replay_actions[current_action_index]
	_apply_action(action)
	_update_controls()
	action_played.emit(current_action_index, action)


func _step_back() -> void:
	if current_match == null or current_action_index <= 0:
		return

	# Reset and replay up to previous action
	current_action_index -= 1
	_init_board_state()

	for i in range(current_action_index + 1):
		var action := current_match.replay_actions[i]
		_apply_action(action, false)  # Don't update display for each

	_update_controls()
	_update_info_panel()
	board_display.queue_redraw()


func _restart_replay() -> void:
	if current_match == null:
		return

	current_action_index = -1
	is_playing = false
	play_button.text = "Play"
	playback_timer = 0.0
	_init_board_state()
	_update_controls()
	_update_info_panel()
	board_display.queue_redraw()


func _apply_action(action: MatchResult.ReplayAction, update_display: bool = true) -> void:
	"""Apply a single action to the board state."""
	var action_data: Dictionary = action.action_data
	var result_data: Dictionary = action.result_data

	match action.action_type:
		"move":
			var champ_id: String = action_data.get("champion", "")
			var target = action_data.get("target")
			if target is Vector2i:
				champion_positions[champ_id] = target
			elif target is Array and target.size() >= 2:
				champion_positions[champ_id] = Vector2i(target[0], target[1])

			if update_display:
				var champ_name: String = champion_names.get(champ_id, champ_id)
				action_label.text = "P%d: %s moved to (%d, %d)" % [
					action.player_id, champ_name,
					champion_positions[champ_id].x, champion_positions[champ_id].y
				]

		"attack":
			var attacker_id: String = action_data.get("champion", "")
			var target_id: String = action_data.get("target", "")
			var damage: int = result_data.get("damage", 0)

			if champion_hp.has(target_id):
				champion_hp[target_id] = maxi(0, champion_hp[target_id] - damage)

			if update_display:
				var attacker_name: String = champion_names.get(attacker_id, attacker_id)
				var target_name: String = champion_names.get(target_id, target_id)
				action_label.text = "P%d: %s attacks %s for %d damage" % [
					action.player_id, attacker_name, target_name, damage
				]

		"cast":
			var caster_id: String = action_data.get("champion", "")
			var card_name: String = action_data.get("card", "")
			var targets: Array = action_data.get("targets", [])

			# Apply damage/healing from result if available
			var total_damage: int = result_data.get("damage", 0)
			var total_healing: int = result_data.get("healing", 0)

			# Try to update HP for targets
			for target in targets:
				if target is String and champion_hp.has(target):
					if total_damage > 0:
						champion_hp[target] = maxi(0, champion_hp[target] - total_damage)
					if total_healing > 0:
						champion_hp[target] = mini(20, champion_hp[target] + total_healing)

			if update_display:
				var caster_name: String = champion_names.get(caster_id, caster_id)
				action_label.text = "P%d: %s casts %s" % [action.player_id, caster_name, card_name]

	progress_bar.value = current_action_index + 1

	if update_display:
		_update_info_panel()
		board_display.queue_redraw()


func _on_speed_changed(value: float) -> void:
	playback_speed = value
	speed_label.text = "%.1fx" % value


func _update_controls() -> void:
	var has_match := current_match != null and not current_match.replay_actions.is_empty()
	play_button.disabled = not has_match
	step_forward_button.disabled = not has_match or (current_action_index >= current_match.replay_actions.size() - 1 if has_match else true)
	step_back_button.disabled = not has_match or current_action_index <= 0


func _update_info_panel() -> void:
	if info_panel == null:
		return

	var text := "[b]Match Info[/b]\n"

	if current_match == null:
		text += "No match loaded"
		info_panel.text = text
		return

	text += "\n[color=#88f]P1 Team:[/color]\n"
	for champ_id: String in champion_positions:
		if champion_player.get(champ_id, 0) == 1:
			var name: String = champion_names.get(champ_id, "?")
			var hp: int = champion_hp.get(champ_id, 0)
			var pos: Vector2i = champion_positions.get(champ_id, Vector2i.ZERO)
			var hp_color := "green" if hp > 10 else ("yellow" if hp > 5 else "red")
			text += "  %s: [color=%s]%d HP[/color] at (%d,%d)\n" % [name, hp_color, hp, pos.x, pos.y]

	text += "\n[color=#f88]P2 Team:[/color]\n"
	for champ_id: String in champion_positions:
		if champion_player.get(champ_id, 0) == 2:
			var name: String = champion_names.get(champ_id, "?")
			var hp: int = champion_hp.get(champ_id, 0)
			var pos: Vector2i = champion_positions.get(champ_id, Vector2i.ZERO)
			var hp_color := "green" if hp > 10 else ("yellow" if hp > 5 else "red")
			text += "  %s: [color=%s]%d HP[/color] at (%d,%d)\n" % [name, hp_color, hp, pos.x, pos.y]

	if current_action_index >= 0:
		var action := current_match.replay_actions[current_action_index]
		text += "\n[b]Action %d/%d[/b]\n" % [current_action_index + 1, current_match.replay_actions.size()]
		text += "Round: %d, Turn: %d\n" % [action.round_number, action.turn_number]
		text += "Player: %d\n" % action.player_id

	info_panel.text = text


func _draw_board() -> void:
	if board_display == null:
		return

	var rect := board_display.get_rect()
	var board_size := 10
	var margin := 20.0
	var available := Vector2(rect.size.x - margin * 2, rect.size.y - margin * 2)
	var tile_size := minf(available.x / board_size, available.y / board_size)
	var board_offset := Vector2(
		margin + (available.x - tile_size * board_size) / 2,
		margin + (available.y - tile_size * board_size) / 2
	)

	# Draw grid
	for x in range(board_size):
		for y in range(board_size):
			var tile_rect := Rect2(
				board_offset + Vector2(x * tile_size, y * tile_size),
				Vector2(tile_size - 1, tile_size - 1)
			)

			# Checkerboard pattern
			var is_light := (x + y) % 2 == 0
			var color := Color(0.25, 0.27, 0.3) if is_light else Color(0.18, 0.2, 0.22)

			# Pit in center
			if x >= 4 and x <= 5 and y >= 4 and y <= 5:
				color = Color(0.1, 0.1, 0.1)

			board_display.draw_rect(tile_rect, color)

	# Draw champions
	for champ_id: String in champion_positions:
		var pos: Vector2i = champion_positions[champ_id]
		var hp: int = champion_hp.get(champ_id, 0)
		var player: int = champion_player.get(champ_id, 1)
		var name: String = champion_names.get(champ_id, "?")

		if hp <= 0:
			continue  # Skip dead champions

		var center := board_offset + Vector2(
			pos.x * tile_size + tile_size / 2,
			pos.y * tile_size + tile_size / 2
		)
		var radius := tile_size * 0.35

		# Player color
		var champ_color := Color(0.3, 0.5, 1.0) if player == 1 else Color(1.0, 0.3, 0.3)

		# Draw champion circle
		board_display.draw_circle(center, radius, champ_color)
		board_display.draw_arc(center, radius, 0, TAU, 32, Color.WHITE, 2.0)

		# Draw HP bar
		var hp_bar_width := tile_size * 0.7
		var hp_bar_height := 4.0
		var hp_bar_pos := center + Vector2(-hp_bar_width / 2, radius + 3)
		var hp_pct := float(hp) / 20.0

		board_display.draw_rect(Rect2(hp_bar_pos, Vector2(hp_bar_width, hp_bar_height)), Color(0.2, 0.2, 0.2))
		var hp_color := Color(0.2, 0.8, 0.2) if hp_pct > 0.5 else (Color(0.8, 0.8, 0.2) if hp_pct > 0.25 else Color(0.8, 0.2, 0.2))
		board_display.draw_rect(Rect2(hp_bar_pos, Vector2(hp_bar_width * hp_pct, hp_bar_height)), hp_color)

		# Draw name initial
		var initial := name.substr(0, 2)
		board_display.draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-6, 4),
			initial,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1, 10, Color.WHITE
		)

	# Draw coordinate labels
	for i in range(board_size):
		# X labels (top)
		board_display.draw_string(
			ThemeDB.fallback_font,
			board_offset + Vector2(i * tile_size + tile_size / 2 - 3, -5),
			str(i),
			HORIZONTAL_ALIGNMENT_CENTER,
			-1, 10, Color(0.4, 0.4, 0.4)
		)
		# Y labels (left)
		board_display.draw_string(
			ThemeDB.fallback_font,
			board_offset + Vector2(-12, i * tile_size + tile_size / 2 + 3),
			str(i),
			HORIZONTAL_ALIGNMENT_CENTER,
			-1, 10, Color(0.4, 0.4, 0.4)
		)
