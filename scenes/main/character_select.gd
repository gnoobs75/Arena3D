extends Control
class_name CharacterSelect
## CharacterSelect - Fighting game style character selection with snake draft
## Flow: P1 picks -> AI picks -> P1 picks -> AI picks -> FIGHT!

signal selection_complete(p1_champions: Array, p2_champions: Array, use_3d: bool)

# === CONSTANTS ===
const CHAMPIONS := [
	"Brute", "Ranger", "Beast", "Redeemer",
	"Confessor", "Barbarian", "Burglar", "Berserker",
	"Shaman", "Illusionist", "DarkWizard", "Alchemist"
]

const CARD_SIZE := Vector2(140, 180)
const CARD_SPACING := 15
const GRID_COLUMNS := 4
const HOVER_SCALE := 1.08
const HOVER_DURATION := 0.15

# === DRAFT STATE ===
enum DraftPhase { P1_PICK1, AI_PICK1, P1_PICK2, AI_PICK2, COMPLETE }
var draft_phase: DraftPhase = DraftPhase.P1_PICK1
var p1_selections: Array[String] = []
var p2_selections: Array[String] = []
var use_3d_mode: bool = false
var _taken_champions: Dictionary = {}  # champion_name -> player_id

# === NODE REFERENCES ===
var champion_cards: Dictionary = {}  # champion_name -> Control node
var p1_pick_slots: Array[Control] = []
var p2_pick_slots: Array[Control] = []
var phase_label: Label
var fight_button: Button
var vs_label: Label
var hovered_champion: String = ""


func _ready() -> void:
	_build_ui()
	_update_phase_display()


func _build_ui() -> void:
	"""Build the entire character select UI programmatically."""
	# Full screen dark background
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 20)
	add_child(main_vbox)

	# Add margins
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 25)
	margin.add_child(content)

	# Title
	var title := Label.new()
	title.text = "SELECT YOUR CHAMPIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", VisualTheme.UI_ACCENT)
	content.add_child(title)

	# Champion grid
	var grid_container := _build_champion_grid()
	grid_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(grid_container)

	# Selection panel (Player picks - VS - CPU picks)
	var selection_panel := _build_selection_panel()
	content.add_child(selection_panel)

	# Phase label
	phase_label = Label.new()
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 22)
	phase_label.add_theme_color_override("font_color", VisualTheme.UI_TEXT)
	content.add_child(phase_label)

	# Fight button (hidden until complete)
	var button_container := CenterContainer.new()
	fight_button = Button.new()
	fight_button.text = "FIGHT!"
	fight_button.custom_minimum_size = Vector2(200, 60)
	fight_button.visible = false
	fight_button.pressed.connect(_on_fight_pressed)
	_style_fight_button(fight_button)
	button_container.add_child(fight_button)
	content.add_child(button_container)


func _build_champion_grid() -> Control:
	"""Build the 4x3 grid of champion cards."""
	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", CARD_SPACING)
	grid.add_theme_constant_override("v_separation", CARD_SPACING)

	for champion_name in CHAMPIONS:
		var card := _create_champion_card(champion_name)
		grid.add_child(card)
		champion_cards[champion_name] = card

	return grid


func _create_champion_card(champion_name: String) -> Control:
	"""Create a single champion card with portrait, name, and stats."""
	var card := Control.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	# Card background panel
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := _create_card_style(champion_name)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(panel)

	# Portrait image
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex_path := "res://assets/art/characters/%s.png" % champion_name
	var texture: Texture2D = load(tex_path)
	if texture:
		portrait.texture = texture
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(portrait)

	# Gradient overlay for readability
	var gradient_overlay := ColorRect.new()
	gradient_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	gradient_overlay.color = Color(0, 0, 0, 0.3)
	gradient_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(gradient_overlay)

	# Name label at bottom
	var name_bg := ColorRect.new()
	name_bg.anchor_left = 0
	name_bg.anchor_right = 1
	name_bg.anchor_top = 1
	name_bg.anchor_bottom = 1
	name_bg.offset_top = -40
	name_bg.color = Color(0, 0, 0, 0.7)
	name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_bg)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = champion_name.to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.anchor_top = 1
	name_label.offset_top = -40
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_label)

	# Stats overlay (shown on hover)
	var stats_panel := _create_stats_overlay(champion_name)
	stats_panel.name = "StatsPanel"
	stats_panel.visible = false
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stats_panel)

	# Selection indicator (checkmark)
	var selected_indicator := _create_selected_indicator()
	selected_indicator.name = "SelectedIndicator"
	selected_indicator.visible = false
	selected_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(selected_indicator)

	# Glow border (shown on hover)
	var glow := Panel.new()
	glow.name = "GlowBorder"
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -4
	glow.offset_right = 4
	glow.offset_top = -4
	glow.offset_bottom = 4
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(0, 0, 0, 0)
	glow_style.border_color = VisualTheme.UI_ACCENT
	glow_style.set_border_width_all(3)
	glow_style.set_corner_radius_all(8)
	glow.add_theme_stylebox_override("panel", glow_style)
	glow.visible = false
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(glow)

	# Store champion name in metadata
	card.set_meta("champion_name", champion_name)

	# Connect mouse events
	card.mouse_entered.connect(_on_card_mouse_entered.bind(champion_name))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(champion_name))
	card.gui_input.connect(_on_card_gui_input.bind(champion_name))

	return card


func _create_card_style(champion_name: String) -> StyleBoxFlat:
	"""Create styled panel for champion card."""
	var colors := VisualTheme.get_champion_colors(champion_name)
	var style := StyleBoxFlat.new()
	style.bg_color = colors["primary"].darkened(0.3)
	style.border_color = colors["secondary"]
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


func _create_stats_overlay(champion_name: String) -> Control:
	"""Create stats overlay panel for a champion."""
	var stats := CardDatabase.get_champion_stats(champion_name)

	var panel := Panel.new()
	panel.anchor_left = 0
	panel.anchor_right = 1
	panel.anchor_top = 0
	panel.offset_bottom = 70

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Add margin
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	margin.add_child(vbox)

	# Power
	var power_label := Label.new()
	power_label.text = "PWR: %d" % stats.get("power", 0)
	power_label.add_theme_font_size_override("font_size", 12)
	power_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	power_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(power_label)

	# Range
	var range_label := Label.new()
	range_label.text = "RNG: %d" % stats.get("range", 1)
	range_label.add_theme_font_size_override("font_size", 12)
	range_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1))
	range_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(range_label)

	# Movement
	var move_label := Label.new()
	move_label.text = "MOV: %d" % stats.get("movement", 3)
	move_label.add_theme_font_size_override("font_size", 12)
	move_label.add_theme_color_override("font_color", Color(0.4, 1, 0.5))
	move_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(move_label)

	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return panel


func _create_selected_indicator() -> Control:
	"""Create the selection indicator (team colored border + icon)."""
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Colored overlay
	var overlay := ColorRect.new()
	overlay.name = "TeamOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.2, 0.5, 0.85, 0.3)  # Default to P1 color
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(overlay)

	# Checkmark or "PICKED" label
	var picked_label := Label.new()
	picked_label.name = "PickedLabel"
	picked_label.text = "PICKED"
	picked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	picked_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	picked_label.set_anchors_preset(Control.PRESET_CENTER)
	picked_label.add_theme_font_size_override("font_size", 18)
	picked_label.add_theme_color_override("font_color", Color.WHITE)
	picked_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(picked_label)

	return container


func _build_selection_panel() -> Control:
	"""Build the Player 1 - VS - CPU selection panel."""
	var panel := HBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 50)

	# Player 1 side
	var p1_panel := _build_player_panel(1, "PLAYER")
	panel.add_child(p1_panel)

	# VS label
	vs_label = Label.new()
	vs_label.text = "VS"
	vs_label.add_theme_font_size_override("font_size", 48)
	vs_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	vs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Add some flair
	var vs_container := Control.new()
	vs_container.custom_minimum_size = Vector2(120, 150)
	vs_label.set_anchors_preset(Control.PRESET_CENTER)
	vs_label.position = Vector2(-25, -30)
	vs_container.add_child(vs_label)
	panel.add_child(vs_container)

	# Player 2 / CPU side
	var p2_panel := _build_player_panel(2, "CPU")
	panel.add_child(p2_panel)

	return panel


func _build_player_panel(player_id: int, label_text: String) -> Control:
	"""Build a player's selection panel with pick slots."""
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# Player label
	var player_label := Label.new()
	player_label.text = label_text
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_label.add_theme_font_size_override("font_size", 24)
	var team_color := VisualTheme.get_player_color(player_id)
	player_label.add_theme_color_override("font_color", team_color)
	vbox.add_child(player_label)

	# Pick slots container
	var picks_hbox := HBoxContainer.new()
	picks_hbox.add_theme_constant_override("separation", 15)
	picks_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(picks_hbox)

	# Two pick slots
	for i in range(2):
		var slot := _create_pick_slot(player_id)
		picks_hbox.add_child(slot)
		if player_id == 1:
			p1_pick_slots.append(slot)
		else:
			p2_pick_slots.append(slot)

	return vbox


func _create_pick_slot(player_id: int) -> Control:
	"""Create a single pick slot (empty or filled with portrait)."""
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(100, 130)

	var team_color := VisualTheme.get_player_color(player_id)

	# Background panel
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18)
	style.border_color = team_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	slot.add_child(panel)

	# Portrait (initially empty)
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.visible = false
	slot.add_child(portrait)

	# Question mark for empty slot
	var question := Label.new()
	question.name = "QuestionMark"
	question.text = "?"
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question.set_anchors_preset(Control.PRESET_FULL_RECT)
	question.add_theme_font_size_override("font_size", 40)
	question.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	slot.add_child(question)

	return slot


func _style_fight_button(button: Button) -> void:
	"""Style the FIGHT button with aggressive look."""
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.7, 0.15, 0.1, 0.95)
	style_normal.border_color = Color(1.0, 0.3, 0.2)
	style_normal.set_border_width_all(3)
	style_normal.set_corner_radius_all(8)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.85, 0.2, 0.15, 0.98)
	style_hover.border_color = Color(1.0, 0.5, 0.3)
	style_hover.set_border_width_all(3)
	style_hover.set_corner_radius_all(8)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.5, 0.1, 0.08, 0.95)
	style_pressed.border_color = Color(0.8, 0.2, 0.15)
	style_pressed.set_border_width_all(3)
	style_pressed.set_corner_radius_all(8)

	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color(1, 1, 0.8))


# === INPUT HANDLERS ===

func _on_card_mouse_entered(champion_name: String) -> void:
	"""Handle mouse entering a champion card."""
	if _is_champion_taken(champion_name):
		return

	hovered_champion = champion_name
	var card: Control = champion_cards[champion_name]

	# Show glow border
	var glow: Panel = card.get_node_or_null("GlowBorder")
	if glow:
		glow.visible = true

	# Show stats
	var stats: Control = card.get_node_or_null("StatsPanel")
	if stats:
		stats.visible = true

	# Scale up with tween
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_DURATION)
	card.pivot_offset = card.size / 2


func _on_card_mouse_exited(champion_name: String) -> void:
	"""Handle mouse exiting a champion card."""
	if hovered_champion == champion_name:
		hovered_champion = ""

	var card: Control = champion_cards[champion_name]

	# Hide glow border
	var glow: Panel = card.get_node_or_null("GlowBorder")
	if glow:
		glow.visible = false

	# Hide stats
	var stats: Control = card.get_node_or_null("StatsPanel")
	if stats:
		stats.visible = false

	# Scale back down
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(card, "scale", Vector2.ONE, HOVER_DURATION)


func _on_card_gui_input(event: InputEvent, champion_name: String) -> void:
	"""Handle click on a champion card."""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_champion(champion_name)


func _select_champion(champion_name: String) -> void:
	"""Handle champion selection during draft."""
	if _is_champion_taken(champion_name):
		return

	if draft_phase == DraftPhase.COMPLETE:
		return

	# Only allow selection during player phases
	if draft_phase == DraftPhase.P1_PICK1 or draft_phase == DraftPhase.P1_PICK2:
		p1_selections.append(champion_name)
		_mark_champion_taken(champion_name, 1)
		_update_pick_slot(1, p1_selections.size() - 1, champion_name)

		# Advance to AI pick
		if draft_phase == DraftPhase.P1_PICK1:
			draft_phase = DraftPhase.AI_PICK1
		else:
			draft_phase = DraftPhase.AI_PICK2

		_update_phase_display()
		_do_ai_pick()


func _do_ai_pick() -> void:
	"""AI makes a pick after a delay."""
	if draft_phase != DraftPhase.AI_PICK1 and draft_phase != DraftPhase.AI_PICK2:
		return

	# Disable input during AI pick
	set_process_input(false)

	# Dramatic pause
	await get_tree().create_timer(0.8).timeout

	# Get available champions
	var available := _get_available_champions()
	if available.is_empty():
		push_error("CharacterSelect: No champions available for AI pick!")
		return

	# Simple AI: pick randomly (could be smarter later)
	var pick: String = available[randi() % available.size()]

	p2_selections.append(pick)
	_mark_champion_taken(pick, 2)
	_update_pick_slot(2, p2_selections.size() - 1, pick)

	# Advance phase
	if draft_phase == DraftPhase.AI_PICK1:
		draft_phase = DraftPhase.P1_PICK2
	else:
		draft_phase = DraftPhase.COMPLETE
		_show_fight_button()

	_update_phase_display()

	# Re-enable input
	set_process_input(true)


func _show_fight_button() -> void:
	"""Show the FIGHT button with animation."""
	fight_button.visible = true
	fight_button.modulate.a = 0
	var tween := create_tween()
	tween.tween_property(fight_button, "modulate:a", 1.0, 0.3)


func _on_fight_pressed() -> void:
	"""Handle FIGHT button press."""
	selection_complete.emit(p1_selections, p2_selections, use_3d_mode)


# === HELPER FUNCTIONS ===

func _is_champion_taken(champion_name: String) -> bool:
	"""Check if a champion has been picked."""
	return _taken_champions.has(champion_name)


func _mark_champion_taken(champion_name: String, player_id: int) -> void:
	"""Mark a champion as picked and update visuals."""
	_taken_champions[champion_name] = player_id

	var card: Control = champion_cards[champion_name]

	# Show selected indicator
	var indicator: Control = card.get_node_or_null("SelectedIndicator")
	if indicator:
		indicator.visible = true
		var overlay: ColorRect = indicator.get_node_or_null("TeamOverlay")
		if overlay:
			var team_color := VisualTheme.get_player_color(player_id)
			overlay.color = Color(team_color.r, team_color.g, team_color.b, 0.4)

	# Dim the card
	card.modulate = Color(0.6, 0.6, 0.6)

	# Hide glow if showing
	var glow: Panel = card.get_node_or_null("GlowBorder")
	if glow:
		glow.visible = false


func _get_available_champions() -> Array[String]:
	"""Get list of champions not yet picked."""
	var available: Array[String] = []
	for champion in CHAMPIONS:
		if not _is_champion_taken(champion):
			available.append(champion)
	return available


func _update_pick_slot(player_id: int, slot_index: int, champion_name: String) -> void:
	"""Update a pick slot with the selected champion portrait."""
	var slots := p1_pick_slots if player_id == 1 else p2_pick_slots
	if slot_index >= slots.size():
		return

	var slot: Control = slots[slot_index]

	# Hide question mark
	var question: Label = slot.get_node_or_null("QuestionMark")
	if question:
		question.visible = false

	# Show portrait
	var portrait: TextureRect = slot.get_node_or_null("Portrait")
	if portrait:
		var tex_path := "res://assets/art/characters/%s.png" % champion_name
		var texture: Texture2D = load(tex_path)
		if texture:
			portrait.texture = texture
			portrait.visible = true


func _update_phase_display() -> void:
	"""Update the phase instruction label."""
	match draft_phase:
		DraftPhase.P1_PICK1:
			phase_label.text = "Player 1: Choose your FIRST champion!"
			phase_label.add_theme_color_override("font_color", VisualTheme.PLAYER1_COLOR)
		DraftPhase.AI_PICK1:
			phase_label.text = "CPU is choosing..."
			phase_label.add_theme_color_override("font_color", VisualTheme.PLAYER2_COLOR)
		DraftPhase.P1_PICK2:
			phase_label.text = "Player 1: Choose your SECOND champion!"
			phase_label.add_theme_color_override("font_color", VisualTheme.PLAYER1_COLOR)
		DraftPhase.AI_PICK2:
			phase_label.text = "CPU is choosing..."
			phase_label.add_theme_color_override("font_color", VisualTheme.PLAYER2_COLOR)
		DraftPhase.COMPLETE:
			phase_label.text = "All champions selected! Ready to battle!"
			phase_label.add_theme_color_override("font_color", VisualTheme.UI_ACCENT)
