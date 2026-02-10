extends CanvasLayer
class_name GameHUD
## GameHUD - Polished game interface with cohesive visual design

signal end_turn_pressed()
signal undo_pressed()
signal menu_pressed()
signal pass_priority_pressed()

const MAX_MANA := 5
const CARD_SCENE := preload("res://scenes/game/cards/card_visual.tscn")

# Layout constants (defaults, overridden by LayoutManager)
const MARGIN := 10
const TOP_BAR_HEIGHT := 0  # No top bar - all info in side panels
const SIDE_PANEL_WIDTH := 220  # Default side panels (overridden by layout)
const PORTRAIT_HEIGHT := 200  # Smaller portraits
const BOTTOM_BAR_HEIGHT := 160  # Hand UI height

# Cached layout
var _layout: LayoutManager = null

# UI Elements
var player1_panel: Control
var player2_panel: Control
var _player1_portrait_widgets: Array[ChampionPortrait] = []
var _player2_portrait_widgets: Array[ChampionPortrait] = []

# AI discard button (in P2 side panel)
var ai_discard_button: Button

# Turn info and action buttons
var turn_info_container: Control
var turn_label: Label
var phase_label: Label
var round_label: Label
var end_turn_button: Button
var undo_button: Button
var scoreboard_label: Label

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

# Card showcase container (for 2-sec center display on cast)
var card_showcase_container: Control

# Combat scoreboard tracking
var _top_hit: int = 0
var _top_hit_attacker: String = ""
var _top_hit_target: String = ""
var _turn_damage: Dictionary = {}  # player_id -> total damage this turn
var _current_turn_player: int = 1

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
	# === LEFT SIDE PANEL (Player 1 + Turn Info + Action Buttons) ===
	player1_panel = _create_side_panel(1)
	add_child(player1_panel)

	# === RIGHT SIDE PANEL (Player 2 / AI) ===
	player2_panel = _create_side_panel(2)
	add_child(player2_panel)

	# Apply layout positioning (will use defaults if no layout set yet)
	_apply_panel_positions()

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

	# === Card showcase container (above combat text) ===
	card_showcase_container = Control.new()
	card_showcase_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_showcase_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card_showcase_container)

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


var _dev_wrappers: Array[DraggableWrapper] = []


func enable_developer_layout() -> void:
	"""Enable draggable/resizable panels for Developer Mode.
	Call after _create_ui() has run (after _ready)."""
	var tb := DraggableWrapper.TITLE_BAR_HEIGHT
	var vp := get_viewport().get_visible_rect().size
	var panel_h := vp.y - BOTTOM_BAR_HEIGHT - MARGIN * 2

	# === Player 1 sidebar (left) ===
	var p1_pos := Vector2(MARGIN, MARGIN)
	var p1_size := Vector2(SIDE_PANEL_WIDTH, panel_h + tb)
	_rewrap_panel(player1_panel, "p1_panel", "Player 1", p1_pos, p1_size)

	# === Player 2 sidebar (right) ===
	var p2_pos := Vector2(vp.x - SIDE_PANEL_WIDTH - MARGIN, MARGIN)
	var p2_size := Vector2(SIDE_PANEL_WIDTH, panel_h + tb)
	_rewrap_panel(player2_panel, "p2_panel", "Player 2", p2_pos, p2_size)

	# === Combat Log ===
	var cl_pos := Vector2(MARGIN, vp.y - CombatLogPanel.PANEL_HEIGHT - MARGIN)
	var cl_size := Vector2(CombatLogPanel.PANEL_WIDTH, CombatLogPanel.PANEL_HEIGHT + tb)
	_rewrap_panel(combat_log_panel, "combat_log", "Combat Log", cl_pos, cl_size)
	combat_log_panel.visible = true

	# === Add Reset Layout button ===
	var reset_btn := Button.new()
	reset_btn.text = "Reset Layout"
	reset_btn.custom_minimum_size = Vector2(100, 28)
	reset_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	reset_btn.offset_left = 10
	reset_btn.offset_top = 4
	reset_btn.offset_right = 110
	reset_btn.offset_bottom = 32
	reset_btn.pressed.connect(_on_reset_layout_pressed)
	reset_btn.z_index = 100
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.35, 0.2, 0.2)
	btn_style.border_color = Color(0.6, 0.3, 0.3)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(3)
	reset_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.45, 0.25, 0.25)
	btn_hover.border_color = Color(0.7, 0.4, 0.4)
	btn_hover.set_border_width_all(1)
	btn_hover.set_corner_radius_all(3)
	reset_btn.add_theme_stylebox_override("hover", btn_hover)
	reset_btn.add_theme_font_size_override("font_size", 12)
	reset_btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.8))
	add_child(reset_btn)

	print("GameHUD: Developer layout enabled — all panels are draggable and resizable")


func _rewrap_panel(panel: Control, id: String, display_name: String, default_pos: Vector2, default_size: Vector2) -> void:
	"""Remove a panel from its current parent and wrap it in a DraggableWrapper."""
	var parent := panel.get_parent()
	if parent:
		parent.remove_child(panel)

	# Clear anchor-based positioning
	panel.anchor_left = 0
	panel.anchor_top = 0
	panel.anchor_right = 0
	panel.anchor_bottom = 0
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0

	var wrapper := DraggableWrapper.wrap(panel, id, display_name, default_pos, default_size)
	add_child(wrapper)
	_dev_wrappers.append(wrapper)


func _on_reset_layout_pressed() -> void:
	"""Reset all panels to default positions."""
	if DevLayout:
		DevLayout.clear_all()
	for wrapper in _dev_wrappers:
		if is_instance_valid(wrapper):
			wrapper.restore_default()
	print("GameHUD: Layout reset to defaults")


func update_layout(new_layout: LayoutManager) -> void:
	"""Update panel positions from LayoutManager. Called on init and viewport resize."""
	_layout = new_layout
	if _is_ready:
		_apply_panel_positions()


func _apply_panel_positions() -> void:
	"""Position panels based on current layout."""
	if _layout == null:
		var vp := get_viewport().get_visible_rect().size
		_layout = LayoutManager.new()
		_layout.calculate(vp)

	var left := _layout.left_panel_rect
	var right := _layout.right_panel_rect
	var panel_w := left.size.x

	# Left panel - full height of board area
	if player1_panel:
		player1_panel.anchor_left = 0
		player1_panel.anchor_top = 0
		player1_panel.anchor_right = 0
		player1_panel.anchor_bottom = 0
		player1_panel.position = left.position
		player1_panel.size = Vector2(panel_w, left.size.y)

	# Right panel - full height of board area
	if player2_panel:
		player2_panel.anchor_left = 0
		player2_panel.anchor_top = 0
		player2_panel.anchor_right = 0
		player2_panel.anchor_bottom = 0
		player2_panel.position = right.position
		player2_panel.size = Vector2(panel_w, right.size.y)


func _create_side_panel(player_id: int) -> Control:
	"""Create a side panel with player info, portraits, and controls.
	Player 1 (left): includes turn info and action buttons.
	Player 2 (right): includes AI hand count and discard button."""
	var panel := PanelContainer.new()
	panel.name = "Player%dPanel" % player_id
	var panel_w: float = SIDE_PANEL_WIDTH
	if _layout:
		panel_w = _layout.left_panel_rect.size.x
	panel.custom_minimum_size = Vector2(panel_w, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var team_color: Color = VisualTheme.get_player_color(player_id)
	var style := StyleBoxFlat.new()
	style.bg_color = VisualTheme.GRADIENT_PANEL_TOP
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

	# Info label (hand/deck count)
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

	# === Player-specific sections ===
	if player_id == 1:
		# --- Turn Info Section (integrated into P1 panel) ---
		var turn_sep := HSeparator.new()
		vbox.add_child(turn_sep)

		# Turn info container for update_layout reference
		turn_info_container = VBoxContainer.new()
		turn_info_container.add_theme_constant_override("separation", VisualTheme.SPACING_MEDIUM)
		vbox.add_child(turn_info_container)

		var info_row := HBoxContainer.new()
		info_row.alignment = BoxContainer.ALIGNMENT_CENTER
		info_row.add_theme_constant_override("separation", 8)
		turn_info_container.add_child(info_row)

		round_label = Label.new()
		round_label.text = "Round 1"
		round_label.add_theme_font_size_override("font_size", 11)
		round_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		info_row.add_child(round_label)

		turn_label = Label.new()
		turn_label.text = "Your Turn"
		turn_label.add_theme_font_size_override("font_size", 13)
		turn_label.add_theme_color_override("font_color", VisualTheme.PLAYER1_COLOR)
		info_row.add_child(turn_label)

		phase_label = Label.new()
		phase_label.text = "ACTION"
		phase_label.add_theme_font_size_override("font_size", 11)
		phase_label.add_theme_color_override("font_color", VisualTheme.UI_ACCENT)
		info_row.add_child(phase_label)

		# Scoreboard row
		scoreboard_label = Label.new()
		scoreboard_label.text = ""
		scoreboard_label.add_theme_font_size_override("font_size", 10)
		scoreboard_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
		scoreboard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		turn_info_container.add_child(scoreboard_label)

		# Action buttons
		var btn_row := HBoxContainer.new()
		btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_row.add_theme_constant_override("separation", 8)
		turn_info_container.add_child(btn_row)

		end_turn_button = Button.new()
		end_turn_button.text = "END TURN"
		end_turn_button.custom_minimum_size = Vector2(100, 32)
		end_turn_button.pressed.connect(_on_end_turn_pressed)
		_style_button(end_turn_button, VisualTheme.PLAYER1_COLOR.lerp(Color.BLACK, 0.3))
		btn_row.add_child(end_turn_button)

		undo_button = Button.new()
		undo_button.text = "UNDO"
		undo_button.custom_minimum_size = Vector2(60, 28)
		undo_button.pressed.connect(_on_undo_pressed)
		_style_button(undo_button, Color(0.4, 0.35, 0.25))
		btn_row.add_child(undo_button)

		# Discard pile viewer button
		var discard_btn := Button.new()
		discard_btn.name = "DiscardButton"
		discard_btn.text = "View Discard"
		discard_btn.custom_minimum_size = Vector2(0, 25)
		discard_btn.pressed.connect(_on_player_discard_clicked)
		_style_button(discard_btn, Color(0.3, 0.3, 0.35))
		vbox.add_child(discard_btn)

	else:
		# --- Player 2 / AI: discard button ---
		var ai_sep := HSeparator.new()
		vbox.add_child(ai_sep)

		ai_discard_button = Button.new()
		ai_discard_button.name = "AIDiscardButton"
		ai_discard_button.text = "View AI Discard"
		ai_discard_button.custom_minimum_size = Vector2(0, 25)
		ai_discard_button.pressed.connect(_on_ai_discard_clicked)
		_style_button(ai_discard_button, VisualTheme.PLAYER2_COLOR.lerp(Color.BLACK, 0.5))
		vbox.add_child(ai_discard_button)

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

	# Update mana gems (dynamically add bonus gems beyond 5)
	var header: HBoxContainer = vbox.get_child(0) as HBoxContainer
	if header:
		var gems: HBoxContainer = header.get_node_or_null("ManaGems")
		if gems:
			var total_gems_needed := maxi(MAX_MANA, mana)
			# Add extra gems if needed
			while gems.get_child_count() < total_gems_needed:
				var gem := ManaGem.new()
				gem.name = "Gem%d" % gems.get_child_count()
				gem.is_bonus = true
				gems.add_child(gem)
			# Remove extra empty gems if mana dropped back
			while gems.get_child_count() > maxi(MAX_MANA, mana):
				var last := gems.get_child(gems.get_child_count() - 1)
				gems.remove_child(last)
				last.queue_free()
			for i in range(gems.get_child_count()):
				var gem: ManaGem = gems.get_child(i) as ManaGem
				if gem:
					gem.set_filled(i < mana)
					gem.is_bonus = i >= MAX_MANA

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

	# Active player gets bright modulate, inactive dims
	var is_active := game_state.active_player == player_id
	if is_active:
		panel.modulate = Color.WHITE
		# Update border to glow with team color
		var active_style := (panel as PanelContainer).get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if active_style:
			active_style.border_color = VisualTheme.get_player_color(player_id)
			active_style.set_border_width_all(3)
			(panel as PanelContainer).add_theme_stylebox_override("panel", active_style)
	else:
		panel.modulate = Color(0.7, 0.7, 0.75)


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


func show_combat_text(text: String, screen_pos: Vector2, color: Color = Color.WHITE, is_damage: bool = true, is_critical: bool = false) -> void:
	if combat_text_container == null:
		return
	var combat_text := FloatingCombatText.new()
	combat_text.setup(text, screen_pos, color, is_damage, is_critical)
	combat_text_container.add_child(combat_text)


func show_damage_number(amount: int, screen_pos: Vector2) -> void:
	var is_critical := amount >= VisualTheme.COMBAT_FLASH_THRESHOLD
	show_combat_text("-%d" % amount, screen_pos, Color(1.0, 0.3, 0.3), true, is_critical)
	# Screen shake for big hits
	if amount >= VisualTheme.COMBAT_SHAKE_THRESHOLD and UIAnimator:
		UIAnimator.screen_shake(3.0 + amount * 0.5, 0.2)
	# Red flash for heavy damage
	if is_critical and UIAnimator:
		UIAnimator.screen_flash(VisualTheme.FLASH_DAMAGE, 0.3)


func show_heal_number(amount: int, screen_pos: Vector2) -> void:
	show_combat_text("+%d" % amount, screen_pos, Color(0.3, 1.0, 0.3), false)
	# Subtle green flash for heals
	if amount >= 3 and UIAnimator:
		UIAnimator.screen_flash(VisualTheme.FLASH_HEAL, 0.25)


## === CHAMPION TAUNTS ===
## Champion-specific trash talk triggered on big hits and kills

# Generic taunts for any champion landing a big hit (4+ damage)
const GENERIC_BIG_HIT_TAUNTS := [
	"Is that all you've got?!",
	"You call that armor?",
	"Didn't even break a sweat!",
	"Stay down!",
	"That's gonna leave a mark!",
	"Feel the pain!",
	"Too slow!",
	"Should've dodged!",
	"Pathetic!",
	"You're done!",
]

# Generic kill taunts
const GENERIC_KILL_TAUNTS := [
	"ELIMINATED!",
	"Another one bites the dust!",
	"That's a wrap!",
	"Sleep tight!",
	"Game over for you!",
]

# Champion-specific taunts: attacker -> { target -> [taunts] }
const CHAMPION_TAUNTS := {
	"Brute": {
		"_default": ["SMASH!", "Brute force!", "Too easy!", "You're just a speed bump!"],
		"Burglar": ["Come out of the shadows, coward!", "Can't hide from THESE fists!", "Sneaky won't save you!"],
		"Ranger": ["Get over here!", "Arrows tickle!", "You can't run forever!"],
		"Illusionist": ["Mirrors can't stop me!", "Which one bleeds? ALL of them!"],
		"DarkWizard": ["Your magic is NOTHING!", "I'll crush your skull AND your spells!"],
	},
	"Ranger": {
		"_default": ["Bullseye!", "Right between the eyes!", "Never saw it coming!", "From downtown!"],
		"Brute": ["Catch this! Oh wait, you can't.", "Big target, easy shot!", "All muscle, no dodge!"],
		"Beast": ["Bad dog! Stay!", "Nice fur... I'll make a rug!", "Heel, boy!"],
		"Berserker": ["Rage all you want from over there!", "Slow and angry, my favorite target!"],
	},
	"Beast": {
		"_default": ["RAWR!", "Nature's fury!", "The wild hungers!", "Tooth and claw!"],
		"Shaman": ["The spirits won't save you!", "Your totems are kindling!"],
		"Redeemer": ["Your light fades!", "Pray harder!"],
		"Alchemist": ["Your potions taste terrible!", "No formula for THIS!"],
	},
	"Redeemer": {
		"_default": ["By the light!", "Justice is served!", "Purified!", "The light condemns you!"],
		"DarkWizard": ["Darkness yields to light!", "Your shadows have no power here!"],
		"Confessor": ["Your faith is misguided!", "Repent!", "False prophet!"],
		"Berserker": ["Calm yourself... permanently!", "Rage is not strength!"],
	},
	"Confessor": {
		"_default": ["Confess your sins!", "Judgment has come!", "The chains tighten!", "Suffer!"],
		"Redeemer": ["Your light blinds only yourself!", "Mercy is weakness!"],
		"Shaman": ["Primitive superstition!", "Your spirits answer to ME now!"],
	},
	"Barbarian": {
		"_default": ["FOR GLORY!", "Blood and thunder!", "WAR!", "The axe speaks!"],
		"Brute": ["I'm the REAL warrior here!", "Amateur!", "You fight like a child!"],
		"Burglar": ["Fight me face to face!", "Coward! Stand and fight!"],
	},
	"Burglar": {
		"_default": ["Didn't see that coming!", "From the shadows!", "Pick pocket, pick LIFE!", "Surprise!"],
		"Shaman": ["Your spirits need glasses!", "Saw that hex coming a mile away!"],
		"Brute": ["Brains over brawn!", "Catch me if you can, big guy!"],
		"Barbarian": ["All that rage and you still missed!", "Too predictable!"],
		"Ranger": ["I can dodge arrows in my sleep!", "Nice aim... NOT!"],
	},
	"Berserker": {
		"_default": ["RAAAAAAGE!", "BLOOD!", "MORE!", "I'LL DESTROY EVERYTHING!", "PAIN IS FUEL!"],
		"Redeemer": ["Your healing won't save you!", "LIGHT BURNS BUT I BURN HOTTER!"],
		"Confessor": ["CHAINS? I'LL BREAK THEM ALL!", "YOUR JUDGMENT MEANS NOTHING!"],
	},
	"Shaman": {
		"_default": ["The spirits strike!", "Elements, hear me!", "Nature's wrath!", "By totem and bone!"],
		"DarkWizard": ["Light magic trumps dark!", "The spirits reject your corruption!"],
		"Illusionist": ["The spirits see through your tricks!", "Illusions don't fool the wind!"],
		"Alchemist": ["Nature needs no laboratory!", "Your science is inferior!"],
	},
	"Illusionist": {
		"_default": ["Now you see me!", "Was that real? Does it matter?", "Confusion is my weapon!", "Mirror match!"],
		"Ranger": ["Can you hit what isn't there?", "Aim at THIS... no, THAT one!"],
		"Barbarian": ["Rage at the mirror, fool!", "Swing away... at nothing!"],
	},
	"DarkWizard": {
		"_default": ["Darkness consumes!", "Your soul is MINE!", "Embrace the void!", "The shadows hunger!"],
		"Redeemer": ["Your light is a candle in a hurricane!", "Faith won't shield you from THIS!"],
		"Shaman": ["Your spirits kneel before me!", "Primitive magic!"],
		"Ranger": ["Arrows? Against MAGIC?", "You can't shoot what you can't see!"],
	},
	"Alchemist": {
		"_default": ["Science prevails!", "Experiment successful!", "Formula complete!", "Boom! Chemistry!"],
		"Shaman": ["Superstition vs science... science wins!", "Your 'spirits' are just gases!"],
		"DarkWizard": ["Magic is just unexplained science!", "I've already analyzed your spells!"],
		"Beast": ["Fascinating specimen!", "Hold still, I need samples!"],
	},
}


func show_taunt(attacker_name: String, target_name: String, damage: int, is_kill: bool) -> void:
	"""Show a champion-specific taunt as floating text near the board center."""
	var taunt: String = ""

	if is_kill:
		# Kill taunts take priority
		var champ_taunts: Dictionary = CHAMPION_TAUNTS.get(attacker_name, {})
		var specific_taunts: Array = champ_taunts.get(target_name, champ_taunts.get("_default", []))
		if not specific_taunts.is_empty():
			taunt = specific_taunts[randi() % specific_taunts.size()]
		else:
			taunt = GENERIC_KILL_TAUNTS[randi() % GENERIC_KILL_TAUNTS.size()]
	elif damage >= 4:
		# Big hit taunts
		var champ_taunts: Dictionary = CHAMPION_TAUNTS.get(attacker_name, {})
		var specific_taunts: Array = champ_taunts.get(target_name, champ_taunts.get("_default", []))
		if not specific_taunts.is_empty():
			taunt = specific_taunts[randi() % specific_taunts.size()]
		else:
			taunt = GENERIC_BIG_HIT_TAUNTS[randi() % GENERIC_BIG_HIT_TAUNTS.size()]

	if taunt.is_empty():
		return

	# Show taunt as floating text in center-ish area, slightly randomized
	var vp_center := get_viewport().get_visible_rect().size / 2.0
	var center := Vector2(vp_center.x, vp_center.y - 140) + Vector2(randf_range(-80, 80), randf_range(-30, 30))
	var taunt_text := FloatingTauntText.new()
	taunt_text.setup(taunt, center, attacker_name)
	if combat_text_container:
		combat_text_container.add_child(taunt_text)


## === CARD SHOWCASE ===
## When a card is cast (especially by AI), show it center screen for 2 seconds

func show_card_showcase(card_name: String, caster_name: String) -> void:
	"""Show a card at center screen for 2 seconds so the player can see what was played."""
	if card_showcase_container == null:
		return
	var showcase := CardShowcase.new()
	showcase.setup(card_name, caster_name)
	card_showcase_container.add_child(showcase)


## === COMBAT SCOREBOARD ===

func track_damage(_attacker_id: String, _target_id: String, amount: int, attacker_name: String, target_name: String) -> void:
	"""Track damage for scoreboard stats."""
	if amount <= 0:
		return
	# Track top hit
	if amount > _top_hit:
		_top_hit = amount
		_top_hit_attacker = attacker_name
		_top_hit_target = target_name
	# Track turn damage
	_turn_damage[_current_turn_player] = _turn_damage.get(_current_turn_player, 0) + amount
	# Update scoreboard display
	if scoreboard_label:
		scoreboard_label.text = get_top_hit_text()


func reset_turn_damage(player_id: int) -> void:
	"""Reset per-turn damage tracking at start of turn."""
	_current_turn_player = player_id
	_turn_damage[player_id] = 0


func get_top_hit_text() -> String:
	if _top_hit <= 0:
		return ""
	return "Top Hit: %d (%s > %s)" % [_top_hit, _top_hit_attacker, _top_hit_target]


func get_turn_damage(player_id: int) -> int:
	return _turn_damage.get(player_id, 0)


func show_turn_banner(player_id: int) -> void:
	"""Dramatic turn start banner with team color and larger text."""
	var team_color := VisualTheme.get_player_color(player_id)
	var banner_height := VisualTheme.TURN_BANNER_HEIGHT

	var banner := ColorRect.new()
	banner.color = team_color.lerp(Color.BLACK, 0.35)
	banner.color.a = 0.92
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -500
	banner.offset_right = 500
	banner.offset_top = -banner_height / 2
	banner.offset_bottom = banner_height / 2
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)

	# Top gold trim line
	var trim_top := ColorRect.new()
	trim_top.color = VisualTheme.FRAME_GOLD_TRIM
	trim_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	trim_top.offset_bottom = 2
	trim_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(trim_top)

	# Bottom gold trim line
	var trim_bottom := ColorRect.new()
	trim_bottom.color = VisualTheme.FRAME_GOLD_TRIM
	trim_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	trim_bottom.offset_top = -2
	trim_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(trim_bottom)

	var label := Label.new()
	var player_name := "YOUR TURN" if player_id == 1 else "AI TURN"
	label.text = player_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", VisualTheme.TURN_BANNER_FONT)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(label)

	# Slide in from right, hold, slide out left
	var vp_width := get_viewport().get_visible_rect().size.x
	banner.position.x = vp_width
	banner.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(banner, "position:x", 0.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(banner, "modulate:a", 1.0, 0.15)
	tween.tween_interval(0.7)
	tween.tween_property(banner, "position:x", -vp_width, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(banner, "modulate:a", 0.0, 0.2)
	tween.tween_callback(banner.queue_free)


func shake_portrait(champion_id: String) -> void:
	"""Shake a champion portrait on damage."""
	for portrait in _player1_portrait_widgets + _player2_portrait_widgets:
		if portrait.champion and portrait.champion.unique_id == champion_id:
			var tween := portrait.create_tween()
			var orig_x := portrait.position.x
			tween.tween_property(portrait, "position:x", orig_x - 4, 0.03)
			tween.tween_property(portrait, "position:x", orig_x + 4, 0.03)
			tween.tween_property(portrait, "position:x", orig_x - 2, 0.03)
			tween.tween_property(portrait, "position:x", orig_x, 0.03)
			break


func pulse_portrait_heal(champion_id: String) -> void:
	"""Green pulse on a champion portrait for healing."""
	for portrait in _player1_portrait_widgets + _player2_portrait_widgets:
		if portrait.champion and portrait.champion.unique_id == champion_id:
			var tween := portrait.create_tween()
			tween.tween_property(portrait, "modulate", Color(0.6, 1.4, 0.6), 0.15)
			tween.tween_property(portrait, "modulate", Color.WHITE, 0.25)
			break


func show_response_window(trigger: String, player_id: int) -> void:
	if response_panel:
		response_panel.visible = true
		# Pop-in animation
		response_panel.pivot_offset = response_panel.size / 2
		response_panel.scale = Vector2(0.5, 0.5)
		response_panel.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(response_panel, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.parallel().tween_property(response_panel, "modulate:a", 1.0, 0.15)
	if response_label:
		var priority_text := "You" if player_id == 1 else "Opponent"
		response_label.text = "Response: %s\n%s has priority" % [trigger, priority_text]


func hide_response_window() -> void:
	if response_panel:
		# Shrink out
		var tween := create_tween()
		tween.tween_property(response_panel, "scale", Vector2(0.5, 0.5), 0.12).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(response_panel, "modulate:a", 0.0, 0.1)
		tween.tween_callback(func(): response_panel.visible = false)


func show_message(text: String, duration: float = 2.0) -> void:
	if message_label:
		message_label.text = text
		message_label.visible = true
		message_label.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(message_label, "modulate:a", 1.0, 0.2)
		tween.tween_interval(duration - 0.5)
		tween.tween_property(message_label, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): message_label.visible = false)


var _end_turn_pulse_tween: Tween

func set_action_buttons_enabled(enabled: bool) -> void:
	if end_turn_button:
		end_turn_button.disabled = not enabled
		# Pulse the end turn button when enabled to draw attention
		if enabled:
			_start_end_turn_pulse()
		else:
			_stop_end_turn_pulse()
	if undo_button:
		undo_button.disabled = not enabled


func _start_end_turn_pulse() -> void:
	if _end_turn_pulse_tween and _end_turn_pulse_tween.is_valid():
		_end_turn_pulse_tween.kill()
	if end_turn_button == null:
		return
	end_turn_button.pivot_offset = end_turn_button.size / 2
	_end_turn_pulse_tween = end_turn_button.create_tween()
	_end_turn_pulse_tween.set_loops()
	_end_turn_pulse_tween.tween_property(end_turn_button, "scale", Vector2(1.04, 1.04), 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_end_turn_pulse_tween.tween_property(end_turn_button, "scale", Vector2(0.98, 0.98), 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _stop_end_turn_pulse() -> void:
	if _end_turn_pulse_tween and _end_turn_pulse_tween.is_valid():
		_end_turn_pulse_tween.kill()
	if end_turn_button:
		end_turn_button.scale = Vector2.ONE


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
	var is_bonus: bool = false
	var _was_filled: bool = true  # Track for fill/drain animation
	var _anim_scale: float = 1.0
	var _sparkle_time: float = 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		pivot_offset = Vector2(11, 11)

	func _process(delta: float) -> void:
		if is_filled:
			_sparkle_time += delta
			# Redraw periodically for sparkle effect
			if fmod(_sparkle_time, 0.1) < delta:
				queue_redraw()

	func set_filled(filled: bool) -> void:
		var changed := is_filled != filled
		_was_filled = is_filled
		is_filled = filled
		if changed:
			_play_change_anim()
		queue_redraw()

	func _play_change_anim() -> void:
		"""Animate mana gem fill or drain."""
		var tween := create_tween()
		if is_filled:
			# Fill: pop bigger with blue flash then settle
			tween.tween_property(self, "modulate", Color(0.6, 0.8, 1.5), 0.06)
			tween.parallel().tween_property(self, "scale", Vector2(1.3, 1.3), 0.08).set_ease(Tween.EASE_OUT)
			tween.tween_property(self, "modulate", Color.WHITE, 0.15)
			tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)
		else:
			# Drain: flash bright then shrink with color drain
			tween.tween_property(self, "modulate", Color(0.4, 0.6, 1.4), 0.05)
			tween.parallel().tween_property(self, "scale", Vector2(1.15, 1.15), 0.05)
			tween.tween_property(self, "scale", Vector2(0.65, 0.65), 0.08)
			tween.parallel().tween_property(self, "modulate", Color(0.6, 0.6, 0.7), 0.08)
			tween.tween_property(self, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tween.parallel().tween_property(self, "modulate", Color.WHITE, 0.12)

	func _draw() -> void:
		var center := size / 2
		var radius := 9.0

		# Shadow
		draw_circle(center + VisualTheme.SHADOW_OFFSET_SMALL, radius, VisualTheme.SHADOW_SOFT)

		# Outer ring (dark border)
		draw_circle(center, radius, Color(0.1, 0.1, 0.15))

		if is_filled:
			if is_bonus:
				# Bonus gem - gold/amber color to distinguish from normal mana
				var outer_color := Color(0.6, 0.45, 0.1)
				var inner_color := Color(1.0, 0.85, 0.3)
				var mid_color := outer_color.lerp(inner_color, 0.5)

				draw_circle(center, radius - 1.5, outer_color)
				draw_circle(center, radius - 3, mid_color)
				draw_circle(center, radius - 5, inner_color)

				# Shine highlights (gold tint)
				draw_circle(center + Vector2(-2.5, -2.5), 2.5, Color(1.0, 0.95, 0.6, 0.5))
				draw_circle(center + Vector2(2, 3), 1.5, Color(0.9, 0.8, 0.3, 0.25))

				# Outer glow (gold)
				for i in range(3, 0, -1):
					var glow_alpha := 0.12 * (1.0 - float(i) / 3.0)
					draw_arc(center, radius + i, 0, TAU, 24, Color(1.0, 0.8, 0.2, glow_alpha), 1.5)
			else:
				# Normal filled gem - gradient effect with concentric circles
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

			# Sparkle point (travels around the gem)
			var sparkle_angle := _sparkle_time * 2.5
			var sparkle_r := radius - 3.0
			var sparkle_pos := center + Vector2(cos(sparkle_angle), sin(sparkle_angle)) * sparkle_r
			var sparkle_alpha := (sin(_sparkle_time * 5.0) + 1.0) * 0.25
			draw_circle(sparkle_pos, 1.5, Color(1, 1, 1, sparkle_alpha))
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
	const HEIGHT := 210  # Base height without equipment
	const EQUIP_ROW_HEIGHT := 18.0
	const MAX_EQUIP_DISPLAY := 3
	const CHARACTER_ART_PATH := "res://assets/art/characters/"

	func _init() -> void:
		custom_minimum_size = Vector2(WIDTH, HEIGHT)

	func _get_equipment_height() -> float:
		if champion == null or champion.equipment.is_empty():
			return 0.0
		var count := mini(champion.equipment.size(), MAX_EQUIP_DISPLAY)
		return 16.0 + count * EQUIP_ROW_HEIGHT  # label + rows

	func _process(delta: float) -> void:
		_glow_timer += delta * 3.0
		if _is_selected or (champion and (not champion.buffs.is_empty() or not champion.debuffs.is_empty() or not champion.equipment.is_empty())):
			queue_redraw()
		# Update tooltip dynamically based on mouse position over status icons
		var tip := _get_tooltip_text()
		if tip != tooltip_text:
			tooltip_text = tip

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
		_update_size()
		queue_redraw()

	func _update_size() -> void:
		var status_height := 0.0
		if champion and (not champion.buffs.is_empty() or not champion.debuffs.is_empty()):
			status_height = 40.0
		custom_minimum_size = Vector2(WIDTH, HEIGHT + status_height + _get_equipment_height())

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

		# Ornamental gold corners
		if is_alive:
			var gold := VisualTheme.FRAME_GOLD_TRIM
			var corner_len := 12.0
			# Top-left
			draw_line(Vector2(2, 2), Vector2(2 + corner_len, 2), gold, 1.5)
			draw_line(Vector2(2, 2), Vector2(2, 2 + corner_len), gold, 1.5)
			# Top-right
			draw_line(Vector2(w - 2, 2), Vector2(w - 2 - corner_len, 2), gold, 1.5)
			draw_line(Vector2(w - 2, 2), Vector2(w - 2, 2 + corner_len), gold, 1.5)
			# Bottom-left
			draw_line(Vector2(2, h - 2), Vector2(2 + corner_len, h - 2), gold, 1.5)
			draw_line(Vector2(2, h - 2), Vector2(2, h - 2 - corner_len), gold, 1.5)
			# Bottom-right
			draw_line(Vector2(w - 2, h - 2), Vector2(w - 2 - corner_len, h - 2), gold, 1.5)
			draw_line(Vector2(w - 2, h - 2), Vector2(w - 2, h - 2 - corner_len), gold, 1.5)

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

		# Enhanced HP bar - taller with tick marks and danger pulse
		var hp_bar_h := float(VisualTheme.HP_BAR_HEIGHT_ENHANCED)
		var hp_rect := Rect2(8, y, w - 16, hp_bar_h)
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

			# Danger pulse when low HP
			if hp_pct <= VisualTheme.HP_DANGER_THRESHOLD and is_alive:
				var danger_pulse := (sin(_glow_timer * 4.0) + 1.0) * 0.5
				draw_rect(hp_fill, Color(1.0, 0.2, 0.1, 0.15 * danger_pulse))

		# Tick marks every N HP
		if champion.max_hp > 0:
			var tick_interval := VisualTheme.HP_TICK_INTERVAL
			var bar_inner_w := hp_rect.size.x - 2
			for tick_hp in range(tick_interval, champion.max_hp, tick_interval):
				var tick_x := hp_rect.position.x + 1 + bar_inner_w * (float(tick_hp) / float(champion.max_hp))
				draw_line(Vector2(tick_x, hp_rect.position.y + 1), Vector2(tick_x, hp_rect.end.y - 1), Color(0, 0, 0, 0.3), 1.0)

		draw_rect(hp_rect, Color(0.35, 0.35, 0.4), false, 1.0)
		VisualTheme.draw_text_shadow(self, font, Vector2(w / 2 - 16, y + hp_bar_h - 4), "%d/%d" % [champion.current_hp, champion.max_hp], 11, Color.WHITE)
		y += int(hp_bar_h) + 4

		# Stats with shadows and spacing
		var stat_w := (w - 24) / 3.0
		var stat_gap := 4.0
		_draw_stat(font, 8, y, stat_w, "PWR", champion.current_power, _base_power, Color(0.85, 0.3, 0.25), is_alive)
		_draw_stat(font, 8 + stat_w + stat_gap, y, stat_w, "RNG", champion.current_range, _base_range, Color(0.3, 0.55, 0.85), is_alive)
		_draw_stat(font, 8 + (stat_w + stat_gap) * 2, y, stat_w, "MOV", champion.current_movement, _base_movement, Color(0.3, 0.75, 0.4), is_alive)

		# Status effects section (buffs/debuffs)
		if is_alive:
			var status_icons := _get_status_icons()
			if not status_icons.is_empty():
				y += 22
				var icon_x := 10.0
				for icon_data: Dictionary in status_icons:
					var icon_col: Color = icon_data["color"]
					var icon_symbol: String = icon_data["symbol"]
					var is_debuff: bool = icon_data.get("is_debuff", false)

					# Icon background circle
					var bg := Color(0.15, 0.12, 0.2, 0.8) if is_debuff else Color(0.12, 0.18, 0.12, 0.8)
					draw_circle(Vector2(icon_x + 8, y + 8), 9.0, bg)
					draw_arc(Vector2(icon_x + 8, y + 8), 9.0, 0, TAU, 12, icon_col.lerp(Color.WHITE, 0.3), 1.0)

					# Icon symbol
					VisualTheme.draw_text_shadow(self, font, Vector2(icon_x + 3, y + 13), icon_symbol, 11, icon_col)

					# Duration text (small, below icon)
					var dur_text: String = icon_data.get("duration_text", "")
					if not dur_text.is_empty():
						VisualTheme.draw_text_shadow(self, font, Vector2(icon_x + 2, y + 22), dur_text, 7, Color(0.7, 0.7, 0.7))

					icon_x += 22.0
					if icon_x > w - 20:
						break
				y += 18

		# Equipment section
		if not champion.equipment.is_empty() and is_alive:
			y += 40  # below stats
			var equip_label_col := Color(0.7, 0.6, 0.3)
			VisualTheme.draw_text_shadow(self, font, Vector2(10, y + 10), "EQUIPPED", 9, equip_label_col)
			y += 14
			var equip_count := 0
			for card_name: String in champion.equipment:
				if equip_count >= MAX_EQUIP_DISPLAY:
					break
				var equip_data: Dictionary = champion.equipment[card_name]
				var charges_rem: int = equip_data.get("charges_remaining", 0)
				var charges_max: int = equip_data.get("charges_max", 0)
				var charge_text: String
				if charges_max < 0 or charges_rem < 0:
					charge_text = "∞"
				else:
					charge_text = "%d/%d" % [charges_rem, charges_max]
				# Equipment icon dot
				draw_circle(Vector2(14, y + 7), 3.0, Color(0.8, 0.7, 0.3))
				# Name (truncated)
				var display_name: String = card_name if card_name.length() <= 16 else card_name.left(14) + ".."
				VisualTheme.draw_text_shadow(self, font, Vector2(20, y + 11), display_name, 9, Color(0.85, 0.85, 0.9))
				# Charges on right
				VisualTheme.draw_text_shadow(self, font, Vector2(w - 36, y + 11), charge_text, 9, Color(0.7, 0.6, 0.3))
				y += EQUIP_ROW_HEIGHT
				equip_count += 1
			_update_size()

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


	func _get_status_icons() -> Array[Dictionary]:
		"""Build list of status effect icons from champion's active buffs/debuffs."""
		var icons: Array[Dictionary] = []
		if champion == null:
			return icons

		# Debuffs (red/purple icons)
		for debuff_name: String in champion.debuffs:
			var debuff_data: Dictionary = champion.debuffs[debuff_name]
			var dur: int = int(debuff_data.get("duration", 0))
			var dur_text := ""
			if dur > 0:
				dur_text = "%dt" % dur
			elif dur == 0:
				dur_text = "turn"

			var icon := {"is_debuff": true, "name": debuff_name, "duration_text": dur_text}
			match debuff_name:
				"blinded":
					icon["symbol"] = "X"
					icon["color"] = Color(0.7, 0.2, 0.8)
					icon["tooltip"] = "Blinded - Cannot attack"
				"hypnotized":
					icon["symbol"] = "S"
					icon["color"] = Color(0.5, 0.5, 0.55)
					icon["tooltip"] = "Petrified - Pay 2 mana to break free"
					icon["duration_text"] = "2g"
				"canMove":
					icon["symbol"] = "M"
					icon["color"] = Color(0.8, 0.4, 0.2)
					icon["tooltip"] = "Immobilized - Cannot move"
				"canAttack":
					icon["symbol"] = "A"
					icon["color"] = Color(0.9, 0.25, 0.25)
					icon["tooltip"] = "Disarmed - Cannot attack"
				"canCast":
					icon["symbol"] = "C"
					icon["color"] = Color(0.6, 0.2, 0.9)
					icon["tooltip"] = "Silenced - Cannot cast spells"
				"powerLocked":
					icon["symbol"] = "P"
					icon["color"] = Color(0.6, 0.15, 0.15)
					icon["tooltip"] = "Power suppressed to 0"
				"noHeal":
					icon["symbol"] = "H"
					icon["color"] = Color(0.5, 0.15, 0.15)
					icon["tooltip"] = "Cannot be healed"
				_:
					icon["symbol"] = "D"
					icon["color"] = Color(0.7, 0.3, 0.3)
					icon["tooltip"] = debuff_name
			icons.append(icon)

		# Buffs (green/gold icons)
		for buff_name: String in champion.buffs:
			var buff_data: Dictionary = champion.buffs[buff_name]
			var dur: int = int(buff_data.get("duration", 0))
			var dur_text := ""
			if dur > 0:
				dur_text = "%dt" % dur
			elif dur == 0:
				dur_text = "turn"

			var icon := {"is_debuff": false, "name": buff_name, "duration_text": dur_text}
			match buff_name:
				"immune":
					icon["symbol"] = "I"
					icon["color"] = Color(1.0, 0.85, 0.3)
					icon["tooltip"] = "Immune - Cannot be targeted or damaged"
				"extraAttack":
					icon["symbol"] = "+"
					icon["color"] = Color(0.9, 0.5, 0.2)
					icon["tooltip"] = "Extra attack available"
				"cheatDeath":
					icon["symbol"] = "U"
					icon["color"] = Color(0.9, 0.8, 0.3)
					icon["tooltip"] = "Cannot go below 1 HP"
				"leech":
					icon["symbol"] = "L"
					icon["color"] = Color(0.3, 0.8, 0.3)
					icon["tooltip"] = "Heals when dealing damage"
				"negateSpell":
					icon["symbol"] = "N"
					icon["color"] = Color(0.4, 0.6, 0.9)
					icon["tooltip"] = "Negate next spell"
				"stealthed":
					icon["symbol"] = "E"
					icon["color"] = Color(0.4, 0.4, 0.5)
					icon["tooltip"] = "Stealthed - Ignores non-AOE damage"
				"vortexShield":
					icon["symbol"] = "V"
					icon["color"] = Color(0.3, 0.7, 0.9)
					icon["tooltip"] = "Vortex Shield - Fully immune"
				_:
					icon["symbol"] = "B"
					icon["color"] = Color(0.3, 0.7, 0.3)
					icon["tooltip"] = buff_name
			icons.append(icon)

		return icons


	func _get_tooltip_text() -> String:
		"""Get tooltip text for status icons under mouse cursor."""
		var icons := _get_status_icons()
		if icons.is_empty():
			return ""

		var mouse_pos := get_local_mouse_position()
		var icon_y := 0.0

		# Calculate y position where status icons are drawn
		# This is approximate - after stats (portrait + name + hp + stats)
		icon_y = 75.0 + 14 + 30 + float(VisualTheme.HP_BAR_HEIGHT_ENHANCED) + 4 + 22

		var icon_x := 10.0
		for icon_data: Dictionary in icons:
			var icon_center := Vector2(icon_x + 8, icon_y + 8)
			if mouse_pos.distance_to(icon_center) < 11.0:
				return icon_data.get("tooltip", "")
			icon_x += 22.0

		return ""


class FloatingCombatText extends Control:
	var _text: String = ""
	var _color: Color = Color.WHITE
	var _lifetime: float = 1.5
	var _elapsed: float = 0.0
	var _font_size: int = 18
	var _is_damage: bool = true
	var _is_critical: bool = false
	var _start_scale: float = 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(120, 60)

	func setup(text: String, screen_pos: Vector2, color: Color = Color.WHITE, is_damage: bool = true, is_critical: bool = false) -> void:
		_text = text
		_color = color
		_is_damage = is_damage
		_is_critical = is_critical
		if is_critical:
			_font_size = VisualTheme.COMBAT_FONT_CRIT
			_start_scale = VisualTheme.COMBAT_IMPACT_SCALE
		elif is_damage:
			_font_size = VisualTheme.COMBAT_FONT_DAMAGE
			_start_scale = 1.5
		else:
			_font_size = VisualTheme.COMBAT_FONT_HEAL
			_start_scale = 1.0
		position = screen_pos - Vector2(60, 30)

		# Impact pop animation for damage
		if is_damage:
			scale = Vector2(_start_scale, _start_scale)
			pivot_offset = Vector2(60, 30)
			var tween := create_tween()
			tween.tween_property(self, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= _lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var progress := _elapsed / _lifetime

		# Different motion curves for damage vs heal
		var y_offset: float
		if _is_damage:
			# Damage: fast up, then slow drift
			y_offset = -50.0 * (1.0 - pow(1.0 - progress, 3.0))
		else:
			# Heal: gentle float up
			y_offset = -35.0 * progress

		# Fade: sharp initial, then gentle
		var alpha: float
		if progress < 0.3:
			alpha = 1.0
		else:
			alpha = 1.0 - ((progress - 0.3) / 0.7) * ((progress - 0.3) / 0.7)

		var draw_color := _color
		draw_color.a = alpha
		var outline := Color.BLACK
		outline.a = alpha * 0.9
		var pos := Vector2(60, 30 + y_offset)

		# Thicker outline for more impact
		for off in [Vector2(-1.5, -1.5), Vector2(1.5, -1.5), Vector2(-1.5, 1.5), Vector2(1.5, 1.5), Vector2(0, -2), Vector2(0, 2), Vector2(-2, 0), Vector2(2, 0)]:
			draw_string(ThemeDB.fallback_font, pos + off, _text, HORIZONTAL_ALIGNMENT_CENTER, 120, _font_size, outline)
		draw_string(ThemeDB.fallback_font, pos, _text, HORIZONTAL_ALIGNMENT_CENTER, 120, _font_size, draw_color)


## === FLOATING TAUNT TEXT ===
## Snarky champion-specific taunts that float up from attacks

class FloatingTauntText extends Control:
	var _text: String = ""
	var _champion_name: String = ""
	var _lifetime: float = 2.5
	var _elapsed: float = 0.0
	var _color: Color = Color(1.0, 0.85, 0.3)  # Golden for taunts

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(400, 60)

	func setup(text: String, screen_pos: Vector2, champion_name: String) -> void:
		_text = text
		_champion_name = champion_name
		# Champion-specific taunt colors
		_color = _get_champion_taunt_color(champion_name)
		position = screen_pos - Vector2(200, 30)
		# Pop-in scale animation
		scale = Vector2(0.3, 0.3)
		pivot_offset = Vector2(200, 30)
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	func _get_champion_taunt_color(champ_name: String) -> Color:
		match champ_name:
			"Brute": return Color(0.9, 0.5, 0.2)       # Orange
			"Ranger": return Color(0.3, 0.8, 0.3)       # Green
			"Beast": return Color(0.7, 0.4, 0.2)        # Brown
			"Redeemer": return Color(1.0, 0.95, 0.5)     # Holy gold
			"Confessor": return Color(0.6, 0.3, 0.6)     # Purple
			"Barbarian": return Color(0.9, 0.3, 0.2)     # Red
			"Burglar": return Color(0.5, 0.5, 0.6)       # Steel gray
			"Berserker": return Color(1.0, 0.2, 0.2)     # Bright red
			"Shaman": return Color(0.3, 0.7, 0.9)        # Spirit blue
			"Illusionist": return Color(0.7, 0.4, 0.9)   # Arcane purple
			"DarkWizard": return Color(0.4, 0.1, 0.5)    # Dark purple
			"Alchemist": return Color(0.2, 0.9, 0.5)     # Chemical green
			_: return Color(1.0, 0.85, 0.3)

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= _lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var progress := _elapsed / _lifetime
		# Gentle float up with slight wave
		var y_offset := -40.0 * progress
		var x_wave := sin(progress * PI * 2.0) * 5.0

		# Fade: hold for 60%, then fade
		var alpha: float
		if progress < 0.6:
			alpha = 1.0
		else:
			alpha = 1.0 - ((progress - 0.6) / 0.4)

		var draw_color := _color
		draw_color.a = alpha
		var outline := Color.BLACK
		outline.a = alpha * 0.95
		var pos := Vector2(200 + x_wave, 30 + y_offset)
		var font_size := 20

		# Draw speech bubble background
		var bubble_rect := Rect2(pos.x - 160, pos.y - 18, 320, 32)
		var bg_color := Color(0, 0, 0, alpha * 0.5)
		draw_rect(bubble_rect, bg_color, true)
		var border_color := _color
		border_color.a = alpha * 0.6
		draw_rect(bubble_rect, border_color, false, 1.5)

		# Draw text with outline
		for off in [Vector2(-1.5, -1.5), Vector2(1.5, -1.5), Vector2(-1.5, 1.5), Vector2(1.5, 1.5)]:
			draw_string(ThemeDB.fallback_font, pos + off, _text, HORIZONTAL_ALIGNMENT_CENTER, 320, font_size, outline)
		draw_string(ThemeDB.fallback_font, pos, _text, HORIZONTAL_ALIGNMENT_CENTER, 320, font_size, draw_color)


## === CARD SHOWCASE ===
## Shows a card at center screen for 2 seconds when cast (especially by AI)

class CardShowcase extends Control:
	var _card_name: String = ""
	var _caster_name: String = ""
	var _card_visual: CardVisual
	var _elapsed: float = 0.0
	var _lifetime: float = 2.0
	var _bg: ColorRect

	const CARD_SCENE_PATH := "res://scenes/game/cards/card_visual.tscn"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(card_name: String, caster_name: String) -> void:
		_card_name = card_name
		_caster_name = caster_name

		# Dark overlay behind the card
		_bg = ColorRect.new()
		_bg.color = Color(0, 0, 0, 0.0)
		_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg)

		# Create card visual
		var scene := load(CARD_SCENE_PATH)
		_card_visual = scene.instantiate()
		_card_visual.setup(card_name, true, false)
		_card_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Recursively set mouse filter on children
		_set_mouse_filter_recursive(_card_visual, Control.MOUSE_FILTER_IGNORE)

		# Position at center, scaled up
		var screen_size := Vector2(1920, 1080)
		if get_viewport():
			screen_size = get_viewport().get_visible_rect().size
		var card_size := Vector2(VisualTheme.CARD_WIDTH, VisualTheme.CARD_HEIGHT)
		_card_visual.position = Vector2(
			(screen_size.x - card_size.x * 1.5) / 2,
			(screen_size.y - card_size.y * 1.5) / 2 - 40
		)
		_card_visual.scale = Vector2(1.5, 1.5)
		_card_visual.pivot_offset = card_size / 2
		add_child(_card_visual)

		# Caster name label below card
		var label := Label.new()
		label.text = "%s casts %s" % [caster_name, card_name]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_CENTER)
		label.offset_left = -200
		label.offset_right = 200
		label.offset_top = card_size.y * 1.5 / 2 + 10
		label.offset_bottom = card_size.y * 1.5 / 2 + 40
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)

		# Animate in: scale pop + background fade
		_card_visual.modulate.a = 0.0
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(_bg, "color:a", 0.35, 0.3)
		tween.tween_property(_card_visual, "modulate:a", 1.0, 0.3)
		tween.tween_property(_card_visual, "scale", Vector2(1.5, 1.5), 0.4).from(Vector2(0.5, 0.5)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	func _set_mouse_filter_recursive(node: Node, filter: Control.MouseFilter) -> void:
		if node is Control:
			(node as Control).mouse_filter = filter
		for child in node.get_children():
			_set_mouse_filter_recursive(child, filter)

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= _lifetime:
			# Fade out and cleanup
			var tween := create_tween()
			tween.set_parallel(true)
			tween.tween_property(_bg, "color:a", 0.0, 0.3)
			if _card_visual:
				tween.tween_property(_card_visual, "modulate:a", 0.0, 0.3)
				tween.tween_property(_card_visual, "scale", Vector2(0.8, 0.8), 0.3)
			tween.chain().tween_callback(queue_free)
			set_process(false)
