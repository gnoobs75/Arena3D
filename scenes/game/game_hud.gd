extends CanvasLayer
class_name GameHUD
## GameHUD - Enhanced game interface overlay
## Features styled panels, mana gems, and champion HP bars

signal end_turn_pressed()
signal undo_pressed()
signal menu_pressed()
signal pass_priority_pressed()

const MAX_MANA := 5

# Custom UI elements
var player1_panel: Control
var player2_panel: Control

# Turn info
var turn_info_panel: Control
var turn_label: Label
var phase_label: Label
var round_label: Label

# Action buttons
var end_turn_button: Button
var undo_button: Button

# Response window
var response_panel: Control
var response_label: Label
var pass_button: Button

# Message display
var message_label: Label

var game_state: GameState
var _is_ready: bool = false


func _ready() -> void:
	_create_ui()
	_is_ready = true


func _create_ui() -> void:
	"""Create all UI elements programmatically."""
	# Top bar container
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 100
	add_child(top_bar)

	# Player 1 Panel
	player1_panel = _create_player_panel(1)
	player1_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(player1_panel)

	# Turn Info Panel (center)
	turn_info_panel = _create_turn_info_panel()
	turn_info_panel.custom_minimum_size = Vector2(200, 0)
	top_bar.add_child(turn_info_panel)

	# Player 2 Panel
	player2_panel = _create_player_panel(2)
	player2_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(player2_panel)

	# Action buttons (below turn info)
	var action_container := HBoxContainer.new()
	action_container.name = "ActionButtons"
	action_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	action_container.offset_top = 105
	action_container.offset_bottom = 145
	action_container.offset_left = -100
	action_container.offset_right = 100
	add_child(action_container)

	undo_button = Button.new()
	undo_button.text = "Undo"
	undo_button.custom_minimum_size = Vector2(80, 35)
	undo_button.pressed.connect(_on_undo_pressed)
	action_container.add_child(undo_button)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	action_container.add_child(spacer)

	end_turn_button = Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.custom_minimum_size = Vector2(100, 35)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	action_container.add_child(end_turn_button)

	# Response Panel
	response_panel = _create_response_panel()
	add_child(response_panel)

	# Message Label
	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.offset_top = 150
	message_label.offset_bottom = 180
	message_label.offset_left = -200
	message_label.offset_right = 200
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_color", VisualTheme.UI_TEXT_HIGHLIGHT)
	message_label.visible = false
	add_child(message_label)


func _create_player_panel(player_id: int) -> Control:
	"""Create a styled player info panel."""
	var panel := PanelContainer.new()
	panel.name = "Player%dPanel" % player_id
	panel.custom_minimum_size = Vector2(320, 95)

	# Style the panel
	var style := VisualTheme.create_panel_stylebox()
	var team_color := VisualTheme.get_player_color(player_id)
	style.border_color = team_color.lerp(Color.BLACK, 0.3)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	panel.add_child(vbox)

	# Player name header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = "Player %d" % player_id if player_id == 1 else "Player 2 (AI)"
	name_label.add_theme_font_size_override("font_size", VisualTheme.FONT_TITLE)
	name_label.add_theme_color_override("font_color", team_color)
	header.add_child(name_label)

	# Mana display
	var mana_container := HBoxContainer.new()
	mana_container.name = "ManaContainer"
	vbox.add_child(mana_container)

	var mana_label := Label.new()
	mana_label.text = "Mana: "
	mana_label.add_theme_color_override("font_color", VisualTheme.UI_TEXT)
	mana_container.add_child(mana_label)

	var gems_container := HBoxContainer.new()
	gems_container.name = "GemsContainer"
	mana_container.add_child(gems_container)

	# Create 5 mana gem slots
	for i in range(MAX_MANA):
		var gem := ManaGem.new()
		gem.name = "Gem%d" % i
		gems_container.add_child(gem)

	# Hand/Deck info
	var info_label := Label.new()
	info_label.name = "InfoLabel"
	info_label.text = "Hand: 5 | Deck: 35"
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.add_theme_color_override("font_color", VisualTheme.UI_TEXT_DIM)
	vbox.add_child(info_label)

	# Champions HP
	var champs_container := HBoxContainer.new()
	champs_container.name = "ChampsContainer"
	vbox.add_child(champs_container)

	return panel


func _create_turn_info_panel() -> Control:
	"""Create the center turn info panel."""
	var panel := PanelContainer.new()
	panel.name = "TurnInfoPanel"

	var style := VisualTheme.create_panel_stylebox()
	style.bg_color = VisualTheme.UI_PANEL_BG.lerp(Color.BLACK, 0.2)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	turn_label = Label.new()
	turn_label.name = "TurnLabel"
	turn_label.text = "Player 1's Turn"
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.add_theme_font_size_override("font_size", VisualTheme.FONT_TITLE)
	turn_label.add_theme_color_override("font_color", VisualTheme.UI_TEXT)
	vbox.add_child(turn_label)

	phase_label = Label.new()
	phase_label.name = "PhaseLabel"
	phase_label.text = "Phase: ACTION"
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_color_override("font_color", VisualTheme.UI_ACCENT)
	vbox.add_child(phase_label)

	round_label = Label.new()
	round_label.name = "RoundLabel"
	round_label.text = "Round 1"
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.add_theme_color_override("font_color", VisualTheme.UI_TEXT_DIM)
	vbox.add_child(round_label)

	return panel


func _create_response_panel() -> Control:
	"""Create the response priority panel."""
	var panel := PanelContainer.new()
	panel.name = "ResponsePanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -150
	panel.offset_right = 150
	panel.offset_top = -75
	panel.offset_bottom = 75
	panel.visible = false

	var style := VisualTheme.create_panel_stylebox()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = VisualTheme.UI_ACCENT
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	response_label = Label.new()
	response_label.name = "ResponseLabel"
	response_label.text = "Response Window\nYou have priority"
	response_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	response_label.add_theme_color_override("font_color", VisualTheme.UI_TEXT)
	vbox.add_child(response_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	pass_button = Button.new()
	pass_button.name = "PassButton"
	pass_button.text = "Pass"
	pass_button.custom_minimum_size = Vector2(100, 35)
	pass_button.pressed.connect(_on_pass_pressed)
	vbox.add_child(pass_button)

	return panel


func initialize(state: GameState) -> void:
	"""Initialize HUD with game state."""
	game_state = state
	if _is_ready:
		update_display()


func update_display() -> void:
	"""Update all HUD elements."""
	if game_state == null or not _is_ready:
		return

	_update_player_panel(player1_panel, 1)
	_update_player_panel(player2_panel, 2)
	_update_turn_info()


func _update_player_panel(panel: Control, player_id: int) -> void:
	"""Update a player panel with current game state."""
	if panel == null:
		return

	var mana: int
	var hand_size: int
	var deck_size: int
	var champions: Array

	if player_id == 1:
		mana = game_state.player1_mana
		hand_size = game_state.player1_hand.size()
		deck_size = game_state.player1_deck.size()
		champions = game_state.player1_champions
	else:
		mana = game_state.player2_mana
		hand_size = game_state.player2_hand.size()
		deck_size = game_state.player2_deck.size()
		champions = game_state.player2_champions

	var vbox: VBoxContainer = panel.get_node_or_null("VBox")
	if vbox == null:
		return

	# Update mana gems
	var gems_container: HBoxContainer = vbox.get_node_or_null("ManaContainer/GemsContainer")
	if gems_container:
		for i in range(MAX_MANA):
			var gem: ManaGem = gems_container.get_node_or_null("Gem%d" % i)
			if gem:
				gem.set_filled(i < mana)

	# Update info label
	var info_label: Label = vbox.get_node_or_null("InfoLabel")
	if info_label:
		info_label.text = "Hand: %d | Deck: %d" % [hand_size, deck_size]

	# Update champions display
	var champs_container: HBoxContainer = vbox.get_node_or_null("ChampsContainer")
	if champs_container:
		# Clear existing
		for child in champs_container.get_children():
			child.queue_free()

		# Add champion boxes
		for champ: ChampionState in champions:
			var champ_box := ChampionBox.new()
			champ_box.setup(champ)
			champs_container.add_child(champ_box)

	# Highlight active player
	var is_active := game_state.active_player == player_id
	panel.modulate = Color.WHITE if is_active else Color(0.7, 0.7, 0.7)


func _update_turn_info() -> void:
	"""Update turn and phase display."""
	var player_name := "Player 1" if game_state.active_player == 1 else "Player 2"
	var team_color := VisualTheme.get_player_color(game_state.active_player)

	if turn_label:
		turn_label.text = "%s's Turn" % player_name
		turn_label.add_theme_color_override("font_color", team_color)
	if phase_label:
		phase_label.text = "Phase: %s" % game_state.current_phase
	if round_label:
		round_label.text = "Round %d" % game_state.round_number


func show_response_window(trigger: String, player_id: int) -> void:
	"""Show response window."""
	if response_panel:
		response_panel.visible = true
	if response_label:
		var priority_text := "You" if player_id == 1 else "Opponent"
		response_label.text = "Response: %s\n%s has priority" % [trigger, priority_text]
	if pass_button:
		pass_button.disabled = player_id != 1


func hide_response_window() -> void:
	"""Hide response window."""
	if response_panel:
		response_panel.visible = false


func show_message(text: String, duration: float = 2.0) -> void:
	"""Show temporary message."""
	if message_label:
		message_label.text = text
		message_label.visible = true

		await get_tree().create_timer(duration).timeout
		message_label.visible = false


func set_action_buttons_enabled(enabled: bool) -> void:
	"""Enable/disable action buttons."""
	if end_turn_button:
		end_turn_button.disabled = not enabled
	if undo_button:
		undo_button.disabled = not enabled


func _on_end_turn_pressed() -> void:
	end_turn_pressed.emit()


func _on_undo_pressed() -> void:
	undo_pressed.emit()


func _on_pass_pressed() -> void:
	pass_priority_pressed.emit()


# === Inner Classes ===

class ManaGem extends Control:
	"""A single mana gem display."""
	var is_filled: bool = true

	func _init() -> void:
		custom_minimum_size = Vector2(VisualTheme.MANA_GEM_SIZE + 4, VisualTheme.MANA_GEM_SIZE + 4)
		size = custom_minimum_size

	func set_filled(filled: bool) -> void:
		is_filled = filled
		queue_redraw()

	func _draw() -> void:
		var center := size / 2
		var radius := VisualTheme.MANA_GEM_SIZE / 2.0

		# Border
		draw_circle(center, radius + 1, VisualTheme.MANA_GEM_BORDER if is_filled else VisualTheme.HP_BAR_BORDER)

		# Fill
		var fill_color := VisualTheme.MANA_GEM_FILLED if is_filled else VisualTheme.MANA_GEM_EMPTY
		draw_circle(center, radius - 1, fill_color)

		# Highlight when filled
		if is_filled:
			draw_arc(center + Vector2(-2, -2), radius - 3, deg_to_rad(200), deg_to_rad(320), 6, Color.WHITE.lerp(fill_color, 0.5), 1.5)


class ChampionBox extends Control:
	"""Mini champion display with HP bar."""
	var champion_name: String = ""
	var current_hp: int = 20
	var max_hp: int = 20
	var is_alive: bool = true

	func _init() -> void:
		custom_minimum_size = Vector2(70, 35)
		size = custom_minimum_size

	func setup(champ: ChampionState) -> void:
		champion_name = champ.champion_name
		current_hp = champ.current_hp
		max_hp = champ.max_hp
		is_alive = champ.is_alive()
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y

		# Background
		var bg_color := VisualTheme.UI_PANEL_BG if is_alive else Color(0.15, 0.1, 0.1, 0.9)
		draw_rect(Rect2(0, 0, w, h), bg_color)
		draw_rect(Rect2(0, 0, w, h), VisualTheme.UI_PANEL_BORDER, false, 1.0)

		var font := ThemeDB.fallback_font

		# Champion name (abbreviated)
		var name_text := champion_name.substr(0, 3)
		var name_color := VisualTheme.UI_TEXT if is_alive else Color(0.5, 0.3, 0.3)
		draw_string(font, Vector2(4, 14), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, name_color)

		# HP Bar
		var bar_x := 4.0
		var bar_y := 20.0
		var bar_width := w - 8
		var bar_height := 10.0

		# Bar background
		draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), VisualTheme.HP_BAR_BG)

		# HP fill
		var hp_pct := float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
		var hp_color := VisualTheme.get_hp_color(current_hp, max_hp) if is_alive else Color(0.4, 0.2, 0.2)
		draw_rect(Rect2(bar_x, bar_y, bar_width * hp_pct, bar_height), hp_color)

		# Bar border
		draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), VisualTheme.HP_BAR_BORDER, false, 1.0)

		# HP text
		var hp_text := "%d/%d" % [current_hp, max_hp]
		draw_string(font, Vector2(w / 2 - 12, bar_y + 8), hp_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.WHITE)

		# Death indicator
		if not is_alive:
			draw_line(Vector2(2, 2), Vector2(w - 2, h - 2), Color(0.8, 0.2, 0.2, 0.7), 2.0)
			draw_line(Vector2(w - 2, 2), Vector2(2, h - 2), Color(0.8, 0.2, 0.2, 0.7), 2.0)
