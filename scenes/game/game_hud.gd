extends CanvasLayer
class_name GameHUD
## GameHUD - Polished game interface with cohesive visual design

signal end_turn_pressed()
signal undo_pressed()
signal menu_pressed()
signal pass_priority_pressed()

const MAX_MANA := 5
const CARD_SCENE := preload("res://scenes/game/cards/card_visual.tscn")

# Layout constants
const MARGIN := 10
const TOP_BAR_HEIGHT := 160  # Height for AI hand area
const SIDE_PANEL_WIDTH := 220  # Narrower side panels
const PORTRAIT_HEIGHT := 200  # Smaller portraits

# UI Elements
var player1_panel: Control
var player2_panel: Control
var _player1_portrait_widgets: Array[ChampionPortrait] = []
var _player2_portrait_widgets: Array[ChampionPortrait] = []

# Top bar (AI hand)
var ai_hand_panel: Control
var ai_hand_container: HBoxContainer
var ai_discard_button: Button

# Turn info and action buttons
var turn_info_container: Control
var turn_label: Label
var phase_label: Label
var round_label: Label
var end_turn_button: Button
var undo_button: Button

# Card preview popup
var card_preview: Control
var card_preview_visual: CardVisual

# Discard pile viewer
var discard_viewer: Control
var discard_cards_container: HBoxContainer
var discard_viewer_label: Label

# Response window
var response_panel: Control
var response_label: Label
var pass_button: Button

# Message display
var message_label: Label

# Floating combat text container
var combat_text_container: Control

# Combat log
var combat_log_panel: CombatLogPanel
var combat_log_button: Button

var game_state: GameState
var _is_ready: bool = false
var _selected_champion_id: String = ""


func _ready() -> void:
	_create_ui()
	_is_ready = true


func _create_ui() -> void:
	"""Create all UI elements."""
	# === TOP BAR: AI Hand ===
	ai_hand_panel = _create_ai_hand_bar()
	ai_hand_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ai_hand_panel.offset_top = 0
	ai_hand_panel.offset_bottom = TOP_BAR_HEIGHT
	add_child(ai_hand_panel)

	# === LEFT SIDE PANEL (Player 1) ===
	player1_panel = _create_side_panel(1)
	player1_panel.position = Vector2(MARGIN, TOP_BAR_HEIGHT + MARGIN)
	add_child(player1_panel)

	# === RIGHT SIDE PANEL (Player 2) ===
	player2_panel = _create_side_panel(2)
	player2_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	player2_panel.offset_left = -SIDE_PANEL_WIDTH - MARGIN
	player2_panel.offset_right = -MARGIN
	player2_panel.offset_top = TOP_BAR_HEIGHT + MARGIN
	player2_panel.offset_bottom = TOP_BAR_HEIGHT + MARGIN + _get_side_panel_height()
	add_child(player2_panel)

	# === TURN INFO BAR (floating, center-right) ===
	turn_info_container = _create_turn_info_bar()
	turn_info_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	turn_info_container.offset_left = -400
	turn_info_container.offset_right = -SIDE_PANEL_WIDTH - MARGIN - 10
	turn_info_container.offset_top = TOP_BAR_HEIGHT + MARGIN
	turn_info_container.offset_bottom = TOP_BAR_HEIGHT + MARGIN + 90
	add_child(turn_info_container)

	# === CARD PREVIEW POPUP (hidden by default) ===
	card_preview = _create_card_preview()
	card_preview.visible = false
	add_child(card_preview)

	# === DISCARD VIEWER (hidden by default) ===
	discard_viewer = _create_discard_viewer()
	discard_viewer.visible = false
	add_child(discard_viewer)

	# === Response Panel ===
	response_panel = _create_response_panel()
	add_child(response_panel)

	# === Message Label ===
	message_label = Label.new()
	message_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	message_label.offset_left = -200
	message_label.offset_right = 200
	message_label.offset_top = -200
	message_label.offset_bottom = -170
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	message_label.add_theme_font_size_override("font_size", 16)
	message_label.visible = false
	add_child(message_label)

	# === Floating combat text container ===
	combat_text_container = Control.new()
	combat_text_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	combat_text_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(combat_text_container)

	# === Combat Log Panel (hidden by default) ===
	combat_log_panel = CombatLogPanel.new()
	add_child(combat_log_panel)

	# === Combat Log Toggle Button ===
	combat_log_button = Button.new()
	combat_log_button.text = "Log"
	combat_log_button.custom_minimum_size = Vector2(60, 30)
	combat_log_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	combat_log_button.offset_left = MARGIN
	combat_log_button.offset_bottom = -MARGIN
	combat_log_button.offset_right = MARGIN + 60
	combat_log_button.offset_top = -MARGIN - 30
	combat_log_button.pressed.connect(_on_combat_log_button_pressed)
	_style_button(combat_log_button, Color(0.3, 0.35, 0.4))
	add_child(combat_log_button)


func _get_side_panel_height() -> float:
	return PORTRAIT_HEIGHT * 2 + MARGIN * 3 + 80  # 2 portraits + mana + header


func _create_ai_hand_bar() -> Control:
	"""Create the AI hand bar at the top (mirrors player hand style)."""
	var panel := PanelContainer.new()
	panel.name = "AIHandBar"

	var style := StyleBoxFlat.new()
	style.bg_color = VisualTheme.GRADIENT_PANEL_TOP
	style.border_color = VisualTheme.PLAYER2_COLOR.lerp(Color.BLACK, 0.4)
	style.border_width_bottom = 3
	style.set_content_margin_all(VisualTheme.PADDING_PANEL)
	style.shadow_color = VisualTheme.SHADOW_COLOR
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", VisualTheme.SPACING_LARGE)
	panel.add_child(hbox)

	# AI Discard pile button
	ai_discard_button = Button.new()
	ai_discard_button.text = "AI\nDiscard"
	ai_discard_button.custom_minimum_size = Vector2(70, 0)
	ai_discard_button.pressed.connect(_on_ai_discard_clicked)
	_style_button(ai_discard_button, VisualTheme.PLAYER2_COLOR.lerp(Color.BLACK, 0.5))
	hbox.add_child(ai_discard_button)

	# Separator
	var sep := VSeparator.new()
	hbox.add_child(sep)

	# Cards container
	var cards_scroll := ScrollContainer.new()
	cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hbox.add_child(cards_scroll)

	ai_hand_container = HBoxContainer.new()
	ai_hand_container.add_theme_constant_override("separation", 8)
	cards_scroll.add_child(ai_hand_container)

	# AI info label
	var info_label := Label.new()
	info_label.name = "AIInfoLabel"
	info_label.text = "AI Hand"
	info_label.add_theme_color_override("font_color", VisualTheme.PLAYER2_COLOR)
	info_label.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(info_label)

	return panel


func _create_side_panel(player_id: int) -> Control:
	"""Create a compact side panel with player info and portraits."""
	var panel := PanelContainer.new()
	panel.name = "Player%dPanel" % player_id
	panel.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH, _get_side_panel_height())

	var team_color: Color = VisualTheme.get_player_color(player_id)
	var style := StyleBoxFlat.new()
	style.bg_color = VisualTheme.GRADIENT_PANEL_TOP  # Will simulate gradient visually
	style.border_color = team_color.lerp(Color.BLACK, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(VisualTheme.PADDING_PANEL)
	style.shadow_color = VisualTheme.SHADOW_HARD
	style.shadow_size = 8
	style.shadow_offset = Vector2(3, 3)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", VisualTheme.SPACING_LARGE)
	panel.add_child(vbox)

	# Player header with mana
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var color_bar := ColorRect.new()
	color_bar.custom_minimum_size = Vector2(3, 20)
	color_bar.color = team_color
	header.add_child(color_bar)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = " P%d" % player_id if player_id == 1 else " AI"
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", team_color)
	header.add_child(name_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# Mana gems
	var gems := HBoxContainer.new()
	gems.name = "ManaGems"
	gems.add_theme_constant_override("separation", 2)
	for i in range(MAX_MANA):
		var gem := ManaGem.new()
		gem.name = "Gem%d" % i
		gems.add_child(gem)
	header.add_child(gems)

	# Info label
	var info := Label.new()
	info.name = "InfoLabel"
	info.text = "Hand: 5 | Deck: 35"
	info.add_theme_font_size_override("font_size", 10)
	info.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	vbox.add_child(info)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Champion portraits container
	var portraits := VBoxContainer.new()
	portraits.name = "PortraitsContainer"
	portraits.add_theme_constant_override("separation", 8)
	vbox.add_child(portraits)

	# Discard button (for player 1 only, AI discard is in top bar)
	if player_id == 1:
		var discard_btn := Button.new()
		discard_btn.name = "DiscardButton"
		discard_btn.text = "View Discard"
		discard_btn.custom_minimum_size = Vector2(0, 25)
		discard_btn.pressed.connect(_on_player_discard_clicked)
		_style_button(discard_btn, Color(0.3, 0.3, 0.35))
		vbox.add_child(discard_btn)

	return panel


func _create_turn_info_bar() -> Control:
	"""Create turn info bar with action buttons."""
	var panel := PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.bg_color = VisualTheme.GRADIENT_PANEL_TOP
	style.border_color = VisualTheme.UI_ACCENT.lerp(Color.BLACK, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(VisualTheme.PADDING_PANEL)
	style.shadow_color = VisualTheme.SHADOW_HARD
	style.shadow_size = 8
	style.shadow_offset = Vector2(3, 3)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", VisualTheme.SPACING_MEDIUM)
	panel.add_child(vbox)

	# Turn info row
	var info_row := HBoxContainer.new()
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_row.add_theme_constant_override("separation", 15)
	vbox.add_child(info_row)

	round_label = Label.new()
	round_label.text = "Round 1"
	round_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	info_row.add_child(round_label)

	turn_label = Label.new()
	turn_label.text = "Player 1's Turn"
	turn_label.add_theme_font_size_override("font_size", 14)
	turn_label.add_theme_color_override("font_color", VisualTheme.PLAYER1_COLOR)
	info_row.add_child(turn_label)

	phase_label = Label.new()
	phase_label.text = "ACTION"
	phase_label.add_theme_color_override("font_color", VisualTheme.UI_ACCENT)
	info_row.add_child(phase_label)

	# Buttons row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	end_turn_button = Button.new()
	end_turn_button.text = "END TURN"
	end_turn_button.custom_minimum_size = Vector2(100, 30)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	_style_button(end_turn_button, Color(0.2, 0.5, 0.3))
	btn_row.add_child(end_turn_button)

	undo_button = Button.new()
	undo_button.text = "UNDO"
	undo_button.custom_minimum_size = Vector2(70, 30)
	undo_button.pressed.connect(_on_undo_pressed)
	_style_button(undo_button, Color(0.4, 0.35, 0.25))
	btn_row.add_child(undo_button)

	return panel


func _create_card_preview() -> Control:
	"""Create a large card preview popup."""
	var container := Control.new()
	container.name = "CardPreview"
	container.set_anchors_preset(Control.PRESET_CENTER)
	container.offset_left = -100
	container.offset_right = 100
	container.offset_top = -150
	container.offset_bottom = 150
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	card_preview_visual = CARD_SCENE.instantiate()
	card_preview_visual.scale = Vector2(1.5, 1.5)
	card_preview_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(card_preview_visual)

	return container


func _create_discard_viewer() -> Control:
	"""Create a popup to view discard pile contents."""
	var panel := PanelContainer.new()
	panel.name = "DiscardViewer"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = -200
	panel.offset_bottom = 200

	var style := StyleBoxFlat.new()
	style.bg_color = VisualTheme.GRADIENT_PANEL_TOP
	style.border_color = VisualTheme.UI_ACCENT.lerp(Color.WHITE, 0.2)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(VisualTheme.PADDING_PANEL + 4)
	style.shadow_color = VisualTheme.SHADOW_HARD
	style.shadow_size = 12
	style.shadow_offset = Vector2(4, 4)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	discard_viewer_label = Label.new()
	discard_viewer_label.text = "Discard Pile"
	discard_viewer_label.add_theme_font_size_override("font_size", 16)
	discard_viewer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(discard_viewer_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(_close_discard_viewer)
	header.add_child(close_btn)

	# Scroll container for cards
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	discard_cards_container = HBoxContainer.new()
	discard_cards_container.add_theme_constant_override("separation", 10)
	scroll.add_child(discard_cards_container)

	return panel


func _create_response_panel() -> Control:
	"""Create the response priority panel."""
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -160
	panel.offset_right = 160
	panel.offset_top = -80
	panel.offset_bottom = 80
	panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = VisualTheme.GRADIENT_PANEL_TOP
	style.border_color = VisualTheme.UI_ACCENT
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(VisualTheme.PADDING_PANEL + 4)
	style.shadow_color = VisualTheme.SHADOW_HARD
	style.shadow_size = 12
	style.shadow_offset = Vector2(4, 4)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	response_label = Label.new()
	response_label.text = "Response Window"
	response_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(response_label)

	pass_button = Button.new()
	pass_button.text = "Pass"
	pass_button.custom_minimum_size = Vector2(100, 30)
	pass_button.pressed.connect(_on_pass_pressed)
	_style_button(pass_button, Color(0.4, 0.35, 0.25))
	vbox.add_child(pass_button)

	return panel


func _style_button(button: Button, base_color: Color) -> void:
	"""Apply styling to a button with shadows and gradients."""
	# Normal state - gradient with shadow
	var normal := StyleBoxFlat.new()
	normal.bg_color = base_color.lerp(Color.WHITE, 0.08)  # Slightly lighter (top of gradient)
	normal.set_border_width_all(1)
	normal.border_color = base_color.lerp(Color.WHITE, 0.25)
	normal.set_corner_radius_all(6)
	normal.shadow_color = VisualTheme.SHADOW_COLOR
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(2, 2)
	normal.set_content_margin_all(VisualTheme.PADDING_BUTTON)

	# Hover state - brighter with larger shadow
	var hover := StyleBoxFlat.new()
	hover.bg_color = base_color.lerp(Color.WHITE, 0.2)
	hover.set_border_width_all(1)
	hover.border_color = base_color.lerp(Color.WHITE, 0.45)
	hover.set_corner_radius_all(6)
	hover.shadow_color = VisualTheme.SHADOW_COLOR
	hover.shadow_size = 6
	hover.shadow_offset = Vector2(3, 3)
	hover.set_content_margin_all(VisualTheme.PADDING_BUTTON)

	# Pressed state - darker, minimal shadow (pressed in)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = base_color.lerp(Color.BLACK, 0.15)
	pressed.set_border_width_all(1)
	pressed.border_color = base_color.lerp(Color.BLACK, 0.1)
	pressed.set_corner_radius_all(5)
	pressed.shadow_color = VisualTheme.SHADOW_SOFT
	pressed.shadow_size = 1
	pressed.shadow_offset = Vector2(1, 1)
	pressed.set_content_margin_all(VisualTheme.PADDING_BUTTON)

	# Disabled state
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = base_color.lerp(Color(0.3, 0.3, 0.3), 0.6)
	disabled.set_border_width_all(1)
	disabled.border_color = Color(0.3, 0.3, 0.35)
	disabled.set_corner_radius_all(6)
	disabled.set_content_margin_all(VisualTheme.PADDING_BUTTON)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.9))
	button.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.85))
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55))


func initialize(state: GameState) -> void:
	game_state = state
	if _is_ready:
		update_display()


func update_display() -> void:
	if game_state == null or not _is_ready:
		return

	_update_side_panel(player1_panel, 1)
	_update_side_panel(player2_panel, 2)
	_update_turn_info()
	_update_ai_hand()


func _update_side_panel(panel: Control, player_id: int) -> void:
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

	var panel_container: PanelContainer = panel as PanelContainer
	if panel_container == null:
		return

	var vbox: VBoxContainer = panel_container.get_child(0) as VBoxContainer
	if vbox == null:
		return

	# Update mana gems
	var header: HBoxContainer = vbox.get_child(0) as HBoxContainer
	if header:
		var gems: HBoxContainer = header.get_node_or_null("ManaGems")
		if gems:
			for i in range(MAX_MANA):
				var gem: ManaGem = gems.get_node_or_null("Gem%d" % i)
				if gem:
					gem.set_filled(i < mana)

	# Update info label
	var info_label: Label = vbox.get_node_or_null("InfoLabel")
	if info_label:
		info_label.text = "Hand: %d | Deck: %d" % [hand_size, deck_size]

	# Update portraits
	var portraits_container: VBoxContainer = vbox.get_node_or_null("PortraitsContainer")
	if portraits_container:
		var widgets: Array[ChampionPortrait] = _player1_portrait_widgets if player_id == 1 else _player2_portrait_widgets

		while widgets.size() < champions.size():
			var portrait := ChampionPortrait.new()
			portraits_container.add_child(portrait)
			widgets.append(portrait)
			if player_id == 1:
				_player1_portrait_widgets = widgets
			else:
				_player2_portrait_widgets = widgets

		for i in range(champions.size()):
			if i < widgets.size():
				widgets[i].setup(champions[i], player_id)
				widgets[i].visible = true

		for i in range(champions.size(), widgets.size()):
			widgets[i].visible = false

	# Dim inactive player's panel
	var is_active := game_state.active_player == player_id
	panel.modulate = Color.WHITE if is_active else Color(0.7, 0.7, 0.75)


func _update_turn_info() -> void:
	var player_name := "Player 1" if game_state.active_player == 1 else "AI"
	var team_color := VisualTheme.get_player_color(game_state.active_player)

	if turn_label:
		turn_label.text = "%s's Turn" % player_name
		turn_label.add_theme_color_override("font_color", team_color)
	if phase_label:
		phase_label.text = game_state.current_phase
	if round_label:
		round_label.text = "Round %d" % game_state.round_number


func _update_ai_hand() -> void:
	if ai_hand_container == null or game_state == null:
		return

	# Clear existing
	for child in ai_hand_container.get_children():
		child.queue_free()

	var ai_hand := game_state.get_hand(2)
	var ai_mana := game_state.get_mana(2)

	# Update info label in top bar
	var info_label: Label = ai_hand_panel.get_node_or_null("*/AIInfoLabel")
	if info_label == null:
		# Try to find it differently
		for child in ai_hand_panel.get_children():
			if child is HBoxContainer:
				info_label = child.get_node_or_null("AIInfoLabel")
				break
	if info_label:
		info_label.text = "AI: %d cards\n%d mana" % [ai_hand.size(), ai_mana]

	# Add full-sized cards
	for card_name: String in ai_hand:
		var card_visual: CardVisual = CARD_SCENE.instantiate()
		var cost: int = CardDatabase.get_card(card_name).get("cost", 0)
		var is_playable: bool = cost <= ai_mana
		card_visual.setup(card_name, is_playable, false)  # Face up for debugging
		card_visual.card_hovered.connect(_on_ai_card_hovered)
		card_visual.card_unhovered.connect(_on_ai_card_unhovered)
		ai_hand_container.add_child(card_visual)


func _on_ai_card_hovered(card_name: String) -> void:
	"""Show large preview when hovering AI card."""
	if card_preview and card_preview_visual:
		card_preview_visual.setup(card_name, true, false)
		card_preview.visible = true


func _on_ai_card_unhovered(_card_name: String) -> void:
	"""Hide preview when not hovering."""
	if card_preview:
		card_preview.visible = false


func _on_player_discard_clicked() -> void:
	"""Show player 1's discard pile."""
	_show_discard_pile(1)


func _on_ai_discard_clicked() -> void:
	"""Show AI's discard pile."""
	_show_discard_pile(2)


func _show_discard_pile(player_id: int) -> void:
	"""Display the discard pile for a player."""
	if game_state == null or discard_viewer == null:
		return

	var discard := game_state.get_discard(player_id)
	var player_name := "Player 1" if player_id == 1 else "AI"

	discard_viewer_label.text = "%s's Discard Pile (%d cards)" % [player_name, discard.size()]

	# Clear existing cards
	for child in discard_cards_container.get_children():
		child.queue_free()

	# Add cards
	if discard.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Empty"
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		discard_cards_container.add_child(empty_label)
	else:
		for card_name: String in discard:
			var card_visual: CardVisual = CARD_SCENE.instantiate()
			card_visual.setup(card_name, false, false)
			discard_cards_container.add_child(card_visual)

	discard_viewer.visible = true


func _close_discard_viewer() -> void:
	if discard_viewer:
		discard_viewer.visible = false


func set_selected_champion(champion_id: String) -> void:
	_selected_champion_id = champion_id
	for portrait in _player1_portrait_widgets:
		if portrait.champion:
			portrait.set_selected(portrait.champion.unique_id == champion_id)
	for portrait in _player2_portrait_widgets:
		if portrait.champion:
			portrait.set_selected(portrait.champion.unique_id == champion_id)


func clear_selection() -> void:
	_selected_champion_id = ""
	for portrait in _player1_portrait_widgets:
		portrait.set_selected(false)
	for portrait in _player2_portrait_widgets:
		portrait.set_selected(false)


func show_combat_text(text: String, screen_pos: Vector2, color: Color = Color.WHITE, is_damage: bool = true) -> void:
	if combat_text_container == null:
		return
	var combat_text := FloatingCombatText.new()
	combat_text.setup(text, screen_pos, color, is_damage)
	combat_text_container.add_child(combat_text)


func show_damage_number(amount: int, screen_pos: Vector2) -> void:
	show_combat_text("-%d" % amount, screen_pos, Color(1.0, 0.3, 0.3), true)


func show_heal_number(amount: int, screen_pos: Vector2) -> void:
	show_combat_text("+%d" % amount, screen_pos, Color(0.3, 1.0, 0.3), false)


func show_response_window(trigger: String, player_id: int) -> void:
	if response_panel:
		response_panel.visible = true
	if response_label:
		var priority_text := "You" if player_id == 1 else "Opponent"
		response_label.text = "Response: %s\n%s has priority" % [trigger, priority_text]


func hide_response_window() -> void:
	if response_panel:
		response_panel.visible = false


func show_message(text: String, duration: float = 2.0) -> void:
	if message_label:
		message_label.text = text
		message_label.visible = true
		await get_tree().create_timer(duration).timeout
		message_label.visible = false


func set_action_buttons_enabled(enabled: bool) -> void:
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


func _on_combat_log_button_pressed() -> void:
	if combat_log_panel:
		combat_log_panel.toggle()
		# Update button text to show state
		combat_log_button.text = "Log [X]" if combat_log_panel.visible else "Log"


# === Inner Classes ===

class ManaGem extends Control:
	var is_filled: bool = true

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)

	func set_filled(filled: bool) -> void:
		is_filled = filled
		queue_redraw()

	func _draw() -> void:
		var center := size / 2
		var radius := 9.0

		# Shadow
		draw_circle(center + VisualTheme.SHADOW_OFFSET_SMALL, radius, VisualTheme.SHADOW_SOFT)

		# Outer ring (dark border)
		draw_circle(center, radius, Color(0.1, 0.1, 0.15))

		if is_filled:
			# Filled gem - gradient effect with concentric circles
			var outer_color := VisualTheme.GRADIENT_MANA_FILLED_BOTTOM
			var inner_color := VisualTheme.GRADIENT_MANA_FILLED_TOP
			var mid_color := outer_color.lerp(inner_color, 0.5)

			draw_circle(center, radius - 1.5, outer_color)
			draw_circle(center, radius - 3, mid_color)
			draw_circle(center, radius - 5, inner_color)

			# Shine highlights
			draw_circle(center + Vector2(-2.5, -2.5), 2.5, Color(0.7, 0.9, 1.0, 0.5))
			draw_circle(center + Vector2(2, 3), 1.5, Color(0.5, 0.7, 1.0, 0.25))

			# Outer glow
			for i in range(3, 0, -1):
				var glow_alpha := 0.1 * (1.0 - float(i) / 3.0)
				draw_arc(center, radius + i, 0, TAU, 24, Color(0.4, 0.6, 1.0, glow_alpha), 1.5)
		else:
			# Empty gem - recessed/inset look
			var outer_color := VisualTheme.GRADIENT_MANA_EMPTY_BOTTOM
			var inner_color := VisualTheme.GRADIENT_MANA_EMPTY_TOP

			draw_circle(center, radius - 1.5, outer_color)
			draw_circle(center, radius - 4, inner_color)

			# Inset shadow (top-left darker)
			draw_arc(center, radius - 2, PI * 0.75, PI * 1.75, 16, Color(0, 0, 0, 0.3), 2.0)
			# Inset highlight (bottom-right lighter)
			draw_arc(center, radius - 2, PI * 1.75, PI * 2.75, 16, Color(1, 1, 1, 0.1), 1.5)


class ChampionPortrait extends Control:
	var champion: ChampionState = null
	var player_id: int = 1
	var _glow_timer: float = 0.0
	var _is_selected: bool = false
	var _base_power: int = 0
	var _base_range: int = 0
	var _base_movement: int = 0
	var _portrait_texture: Texture2D = null

	const WIDTH := 200
	const HEIGHT := 210  # Slightly taller for better spacing
	const CHARACTER_ART_PATH := "res://assets/art/characters/"

	func _init() -> void:
		custom_minimum_size = Vector2(WIDTH, HEIGHT)

	func _process(delta: float) -> void:
		_glow_timer += delta * 3.0
		if _is_selected or (champion and not champion.buffs.is_empty()):
			queue_redraw()

	func set_selected(selected: bool) -> void:
		_is_selected = selected
		queue_redraw()

	func setup(champ: ChampionState, p_id: int = 1) -> void:
		champion = champ
		player_id = p_id
		if champ:
			_base_power = champ.base_power
			_base_range = champ.base_range
			_base_movement = champ.base_movement
			_load_portrait_texture()
		queue_redraw()

	func _load_portrait_texture() -> void:
		"""Load the portrait texture for this champion."""
		if champion == null:
			_portrait_texture = null
			return

		var full_path := CHARACTER_ART_PATH + champion.champion_name + ".png"

		if ResourceLoader.exists(full_path):
			_portrait_texture = load(full_path)
		else:
			_portrait_texture = null

	func _draw() -> void:
		if champion == null:
			return

		var w := size.x
		var h := size.y
		var champ_colors := VisualTheme.get_champion_colors(champion.champion_name)
		var team_color := VisualTheme.get_player_color(player_id)
		var is_alive := champion.is_alive()
		var font := ThemeDB.fallback_font

		# === DROP SHADOW ===
		draw_rect(Rect2(VisualTheme.SHADOW_OFFSET_LARGE.x, VisualTheme.SHADOW_OFFSET_LARGE.y, w, h), VisualTheme.SHADOW_HARD)

		# Selection glow
		if _is_selected and is_alive:
			var pulse := (sin(_glow_timer) + 1.0) * 0.5
			for i in range(4, 0, -1):
				var glow := Color(1.0, 0.95, 0.4, 0.35 * pulse * (1.0 - float(i) / 4.0))
				draw_rect(Rect2(-i * 2, -i * 2, w + i * 4, h + i * 4), glow, false, 2.5)

		# Frame with gradient
		var frame_top: Color = team_color.lerp(Color.WHITE, 0.15) if is_alive else Color(0.3, 0.3, 0.33)
		var frame_bottom: Color = team_color.lerp(Color.BLACK, 0.15) if is_alive else Color(0.2, 0.2, 0.23)
		VisualTheme.draw_vertical_gradient(self, Rect2(0, 0, w, h), frame_top, frame_bottom)

		# Bevel on frame
		VisualTheme.draw_bevel(self, Rect2(0, 0, w, h), 1.5)

		# Inner background with gradient
		var inner := Rect2(3, 3, w - 6, h - 6)
		var bg_top: Color = champ_colors["secondary"].lerp(Color(0.12, 0.13, 0.16), 0.7) if is_alive else Color(0.12, 0.12, 0.14)
		var bg_bottom: Color = champ_colors["primary"].lerp(Color(0.08, 0.09, 0.12), 0.8) if is_alive else Color(0.1, 0.1, 0.12)
		VisualTheme.draw_vertical_gradient(self, inner, bg_top, bg_bottom)

		# Portrait area with inset
		var portrait_h := 75.0
		var portrait_rect := Rect2(8, 8, w - 16, portrait_h)

		# Portrait shadow (inset)
		draw_rect(portrait_rect, champ_colors["primary"].lerp(Color.BLACK, 0.6))
		VisualTheme.draw_inset(self, portrait_rect)

		# Portrait image or fallback symbol
		if _portrait_texture != null:
			var tex_size := _portrait_texture.get_size()
			var scale_x := portrait_rect.size.x / tex_size.x
			var scale_y := portrait_rect.size.y / tex_size.y
			var scale_factor := minf(scale_x, scale_y)

			var scaled_size := tex_size * scale_factor
			var offset := (portrait_rect.size - scaled_size) / 2.0
			var draw_pos := portrait_rect.position + offset

			var modulate: Color = Color.WHITE if is_alive else Color(0.5, 0.5, 0.5)
			draw_texture_rect(_portrait_texture, Rect2(draw_pos, scaled_size), false, modulate)

			# Vignette overlay
			var vig_rect := Rect2(portrait_rect.position.x, portrait_rect.position.y + portrait_rect.size.y * 0.6, portrait_rect.size.x, portrait_rect.size.y * 0.4)
			VisualTheme.draw_vertical_gradient(self, vig_rect, Color(0, 0, 0, 0), Color(0, 0, 0, 0.4))
		else:
			# Fallback to symbol
			var symbol := VisualTheme.get_champion_symbol(champion.champion_name)
			var sym_color: Color = champ_colors["secondary"] if is_alive else Color(0.35, 0.35, 0.38)
			VisualTheme.draw_text_shadow(self, font, Vector2(w / 2 - 12, portrait_h / 2 + 18), symbol, 32, sym_color)

		var y := portrait_h + 14

		# Name bar with gradient
		var name_rect := Rect2(8, y, w - 16, 24)
		var name_top: Color = champ_colors["primary"].lerp(Color.WHITE, 0.1)
		var name_bottom: Color = champ_colors["primary"].lerp(Color.BLACK, 0.3)
		VisualTheme.draw_vertical_gradient(self, name_rect, name_top, name_bottom)
		draw_rect(name_rect, champ_colors["secondary"].lerp(Color.WHITE, 0.15), false, 1.0)

		# Name text with shadow
		var name_col: Color = Color.WHITE if is_alive else Color(0.5, 0.5, 0.52)
		VisualTheme.draw_text_shadow(self, font, Vector2(12, y + 17), champion.champion_name.to_upper(), 12, name_col)
		y += 30

		# HP bar with shadow and gradient
		var hp_rect := Rect2(8, y, w - 16, 18)
		# HP bar shadow
		draw_rect(Rect2(hp_rect.position + Vector2(1, 1), hp_rect.size), VisualTheme.SHADOW_SOFT)
		# HP bar background
		draw_rect(hp_rect, Color(0.06, 0.06, 0.08))
		VisualTheme.draw_inset(self, hp_rect)

		var hp_pct := float(champion.current_hp) / float(champion.max_hp) if champion.max_hp > 0 else 0.0
		var hp_fill := Rect2(hp_rect.position.x + 1, hp_rect.position.y + 1, (hp_rect.size.x - 2) * hp_pct, hp_rect.size.y - 2)

		if hp_pct > 0:
			var hp_colors := VisualTheme.get_hp_gradient_colors(hp_pct) if is_alive else [Color(0.3, 0.15, 0.15), Color(0.2, 0.1, 0.1)]
			VisualTheme.draw_vertical_gradient(self, hp_fill, hp_colors[0], hp_colors[1])
			# Shine on HP bar
			draw_line(Vector2(hp_fill.position.x, hp_fill.position.y + 2), Vector2(hp_fill.end.x, hp_fill.position.y + 2), Color(1, 1, 1, 0.25), 1.0)

		draw_rect(hp_rect, Color(0.35, 0.35, 0.4), false, 1.0)
		VisualTheme.draw_text_shadow(self, font, Vector2(w / 2 - 16, y + 14), "%d/%d" % [champion.current_hp, champion.max_hp], 11, Color.WHITE)
		y += 24

		# Stats with shadows and spacing
		var stat_w := (w - 24) / 3.0
		var stat_gap := 4.0
		_draw_stat(font, 8, y, stat_w, "PWR", champion.current_power, _base_power, Color(0.85, 0.3, 0.25), is_alive)
		_draw_stat(font, 8 + stat_w + stat_gap, y, stat_w, "RNG", champion.current_range, _base_range, Color(0.3, 0.55, 0.85), is_alive)
		_draw_stat(font, 8 + (stat_w + stat_gap) * 2, y, stat_w, "MOV", champion.current_movement, _base_movement, Color(0.3, 0.75, 0.4), is_alive)

		# Death overlay
		if not is_alive:
			draw_rect(inner, Color(0, 0, 0, 0.55))
			VisualTheme.draw_text_shadow(self, font, Vector2(w / 2 - 32, h / 2), "DEFEATED", 14, Color(1, 0.8, 0.8), Vector2(2, 2), Color(0, 0, 0, 0.8))

	func _draw_stat(font: Font, x: float, y: float, w: float, label: String, current: int, base: int, color: Color, alive: bool) -> void:
		var stat_rect := Rect2(x, y, w, 36)

		# Stat box shadow
		draw_rect(Rect2(stat_rect.position + Vector2(1, 1), stat_rect.size), VisualTheme.SHADOW_SOFT)

		# Stat box background gradient
		var bg_top: Color = color.lerp(Color.BLACK, 0.65) if alive else Color(0.14, 0.14, 0.16)
		var bg_bottom: Color = color.lerp(Color.BLACK, 0.8) if alive else Color(0.1, 0.1, 0.12)
		VisualTheme.draw_vertical_gradient(self, stat_rect, bg_top, bg_bottom)

		# Stat box border with bevel
		var border_color := color.lerp(Color.BLACK, 0.3) if alive else Color(0.22, 0.22, 0.25)
		draw_rect(stat_rect, border_color, false, 1.0)
		VisualTheme.draw_bevel(self, stat_rect, 1.0, Color(1, 1, 1, 0.1), Color(0, 0, 0, 0.15))

		# Label with shadow
		var label_col := Color(0.65, 0.65, 0.7) if alive else Color(0.4, 0.4, 0.43)
		VisualTheme.draw_text_shadow(self, font, Vector2(x + w / 2 - 10, y + 12), label, VisualTheme.FONT_STAT_LABEL, label_col)

		# Value with shadow and buff/debuff coloring
		var val_col: Color = color.lerp(Color.WHITE, 0.5) if alive else Color(0.45, 0.45, 0.48)
		if current > base and alive:
			val_col = Color(0.3, 1.0, 0.4)
		elif current < base and alive:
			val_col = Color(1.0, 0.4, 0.3)
		VisualTheme.draw_text_shadow(self, font, Vector2(x + w / 2 - 6, y + 29), str(current), VisualTheme.FONT_STAT_VALUE, val_col)


class FloatingCombatText extends Control:
	var _text: String = ""
	var _color: Color = Color.WHITE
	var _lifetime: float = 1.5
	var _elapsed: float = 0.0
	var _font_size: int = 18

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(100, 50)

	func setup(text: String, screen_pos: Vector2, color: Color = Color.WHITE, is_damage: bool = true) -> void:
		_text = text
		_color = color
		_font_size = 20 if is_damage else 16
		position = screen_pos - Vector2(50, 25)

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= _lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var progress := _elapsed / _lifetime
		var y_offset := -40.0 * progress
		var alpha := 1.0 - progress * progress
		var draw_color := _color
		draw_color.a = alpha
		var outline := Color.BLACK
		outline.a = alpha * 0.8
		var pos := Vector2(50, 25 + y_offset)
		for off in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_string(ThemeDB.fallback_font, pos + off, _text, HORIZONTAL_ALIGNMENT_CENTER, 100, _font_size, outline)
		draw_string(ThemeDB.fallback_font, pos, _text, HORIZONTAL_ALIGNMENT_CENTER, 100, _font_size, draw_color)
