extends Control
class_name HandUI
## HandUI - Enhanced container for player's hand of cards
## Includes card display, discard pile, and hover preview

signal card_selected(card_name: String)
signal card_deselected()
signal card_toggled(card_name: String, selected: bool)  # For multi-select mode
signal discard_pile_clicked(player_id: int)

const CARD_SPACING := 8  # Spacing between cards
const CARD_SCENE := preload("res://scenes/game/cards/card_visual.tscn")
const DISCARD_SCENE := preload("res://scenes/game/cards/discard_pile.tscn")
const PREVIEW_SCALE := 1.8  # Scale factor for preview card

# Node references - fetched in _ready() for safety
var cards_container: HBoxContainer
var discard_pile: DiscardPile
var background: ColorRect
var _is_ready: bool = false

# Card preview
var card_preview: CardVisual = null
var preview_container: Control = null

var response_slot_node: Control = null  # ResponseSlot, typed as Control to avoid cyclic ref
var player_id: int = 1
var card_visuals: Dictionary = {}  # card_index -> CardVisual
var selected_card: String = ""
var playable_cards: Array[String] = []

# Multi-select mode (for From the Sky, etc.)
var multi_select_mode: bool = false
var multi_selected_cards: Array[String] = []


func _ready() -> void:
	# Set up anchors for bottom positioning
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -LayoutManager.HAND_H
	offset_left = LayoutManager.MARGIN
	offset_right = -LayoutManager.MARGIN
	offset_bottom = 0

	_create_ui()
	_is_ready = true


func update_layout(new_layout: LayoutManager) -> void:
	"""Update positioning from LayoutManager."""
	anchor_left = 0
	anchor_top = 0
	anchor_right = 0
	anchor_bottom = 0
	position = new_layout.hand_rect.position
	size = new_layout.hand_rect.size


func _create_ui() -> void:
	"""Create the hand UI layout with enhanced styling."""
	# Background with gradient effect
	background = ColorRect.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = VisualTheme.GRADIENT_PANEL_TOP  # Will appear as solid, gradient in cards panel
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# Top shadow line for depth
	var top_shadow := ColorRect.new()
	top_shadow.name = "TopShadow"
	top_shadow.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_shadow.offset_bottom = 4
	top_shadow.color = Color(0, 0, 0, 0.4)
	top_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_shadow)

	# Main container
	var main_container := HBoxContainer.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.add_theme_constant_override("separation", VisualTheme.SPACING_LARGE)
	main_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(main_container)

	# === 1. Discard pile (far left) ===
	discard_pile = DISCARD_SCENE.instantiate() as DiscardPile
	discard_pile.setup(player_id)
	discard_pile.pile_clicked.connect(_on_discard_clicked)
	discard_pile.custom_minimum_size = Vector2(110, 0)
	main_container.add_child(discard_pile)

	# Separator
	var sep1 := VSeparator.new()
	sep1.custom_minimum_size = Vector2(2, 0)
	main_container.add_child(sep1)

	# === 2. Response Window (placeholder, replaced via set_response_slot) ===
	var _response_placeholder := Control.new()
	_response_placeholder.name = "ResponsePlaceholder"
	_response_placeholder.custom_minimum_size = Vector2(130, 0)
	_response_placeholder.visible = false
	main_container.add_child(_response_placeholder)

	# Separator
	var sep2 := VSeparator.new()
	sep2.custom_minimum_size = Vector2(2, 0)
	main_container.add_child(sep2)

	# === 3. Cards panel (takes remaining space, cards centered inside) ===
	var cards_panel := PanelContainer.new()
	cards_panel.name = "CardsPanel"
	cards_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	var style := StyleBoxFlat.new()
	style.bg_color = VisualTheme.GRADIENT_PANEL_BOTTOM.lerp(Color.BLACK, 0.1)
	style.set_border_width_all(1)
	style.border_color = VisualTheme.UI_PANEL_BORDER.lerp(VisualTheme.PLAYER1_COLOR, 0.2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	style.shadow_color = VisualTheme.SHADOW_SOFT
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, -2)
	cards_panel.add_theme_stylebox_override("panel", style)
	main_container.add_child(cards_panel)

	cards_container = HBoxContainer.new()
	cards_container.name = "CardsContainer"
	cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_container.add_theme_constant_override("separation", CARD_SPACING)
	cards_container.mouse_filter = Control.MOUSE_FILTER_PASS
	cards_panel.add_child(cards_container)

	# Create preview container (positioned above the hand)
	_create_preview_container()


func _create_preview_container() -> void:
	"""Create the card preview popup that appears on hover."""
	preview_container = Control.new()
	preview_container.name = "PreviewContainer"
	preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_container.visible = false
	preview_container.z_index = 100  # Always on top
	add_child(preview_container)

	# Create the preview card visual
	card_preview = CARD_SCENE.instantiate()
	card_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	preview_container.add_child(card_preview)


func setup(player: int) -> void:
	"""Initialize for a specific player."""
	player_id = player
	if discard_pile:
		discard_pile.setup(player)


func set_response_slot(slot: Control) -> void:
	"""Reparent response slot into the hand bar, replacing the placeholder."""
	response_slot_node = slot
	var main_container := get_node_or_null("MainContainer")
	if main_container == null:
		return
	# Remove placeholder and insert response window at same index
	var placeholder := main_container.get_node_or_null("ResponsePlaceholder")
	if placeholder:
		var idx := placeholder.get_index()
		main_container.remove_child(placeholder)
		placeholder.queue_free()
		if slot.get_parent():
			slot.get_parent().remove_child(slot)
		# Wrap slot in a labeled container
		var wrapper := VBoxContainer.new()
		wrapper.name = "ResponseWindow"
		wrapper.custom_minimum_size = Vector2(130, 0)
		wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
		# Add slot centered in wrapper
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		wrapper.add_child(slot)
		main_container.add_child(wrapper)
		main_container.move_child(wrapper, idx)


var _previous_hand_size: int = 0

var _game_state: GameState = null

func set_game_state(state: GameState) -> void:
	"""Set game state reference for cost reduction checks."""
	_game_state = state


var _cost_locked_cards: Array[String] = []  # Cards blocked by maxCastCost (Guess Again)


func update_hand(hand: Array, mana: int, valid_responses: Array[String] = [], restricted_cards: Array[String] = [], cost_locked_cards: Array[String] = []) -> void:
	"""Update displayed cards from hand array.
	valid_responses: If non-empty, these response cards are playable (response window is open).
	restricted_cards: Cards that cannot be played due to game state (e.g. champion already attacked).
	cost_locked_cards: Cards blocked by maxCastCost debuff (show red X on cost)."""
	_cost_locked_cards = cost_locked_cards
	if not _is_ready or cards_container == null:
		return

	var had_cards := _previous_hand_size
	_clear_cards()
	_previous_hand_size = hand.size()

	# Determine playable cards
	playable_cards.clear()
	for card_name: String in hand:
		# In multi-select mode (discard selection), ALL cards are selectable
		if multi_select_mode:
			playable_cards.append(card_name)
			continue

		# Cards restricted by game state are never playable
		if card_name in restricted_cards:
			continue

		var card_data := CardDatabase.get_card(card_name)
		var cost: int = _game_state.get_effective_cost(card_name) if _game_state else card_data.get("cost", 0)
		var card_type: String = str(card_data.get("type", ""))

		if card_type == "Response":
			# Response cards are always "playable" since they can be placed in the response slot
			# They'll auto-trigger when their condition is met and player has enough mana
			playable_cards.append(card_name)
		elif cost <= mana:
			# Action/Equipment cards playable if we have mana
			playable_cards.append(card_name)

	# Detect if a card was drawn (hand grew by 1)
	var new_card_drawn := hand.size() > had_cards and had_cards > 0

	# Create card visuals with staggered entrance
	for i in range(hand.size()):
		var card_name: String = hand[i]
		var is_playable := card_name in playable_cards
		var card_visual := _create_card_visual(card_name, is_playable, i)
		cards_container.add_child(card_visual)
		card_visuals[i] = card_visual

		var is_new_card := new_card_drawn and i == hand.size() - 1

		# Staggered fan-in animation
		card_visual.modulate.a = 0.0
		card_visual.pivot_offset = card_visual.size / 2
		card_visual.scale = Vector2(0.85, 0.85)
		var tween := card_visual.create_tween()

		if is_new_card:
			# Newly drawn card flies in from top-right of screen
			card_visual.scale = Vector2(0.5, 0.5)
			card_visual.position = Vector2(size.x * 0.7, -VisualTheme.CARD_HEIGHT * 1.5)
			card_visual.modulate.a = 0.6
			tween.set_parallel(true)
			tween.tween_property(card_visual, "position", Vector2.ZERO, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(card_visual, "scale", Vector2(1.08, 1.08), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tween.tween_property(card_visual, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
			# Golden flash on arrival
			tween.chain().tween_property(card_visual, "modulate", Color(1.5, 1.3, 0.7), 0.12)
			tween.tween_property(card_visual, "modulate", Color.WHITE, 0.3)
			tween.parallel().tween_property(card_visual, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_IN_OUT)
		else:
			tween.tween_interval(i * 0.04)
			tween.tween_property(card_visual, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(card_visual, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func update_discard(discard: Array) -> void:
	"""Update the discard pile display."""
	if discard_pile:
		discard_pile.update_pile(discard)


func _clear_cards() -> void:
	"""Remove all card visuals."""
	if cards_container:
		for child in cards_container.get_children():
			child.queue_free()
	card_visuals.clear()
	selected_card = ""


func _create_card_visual(card_name: String, is_playable: bool, index: int) -> CardVisual:
	"""Create a card visual instance."""
	var card: CardVisual = CARD_SCENE.instantiate()
	# Set cost override for cards with conditional cost reduction
	if _game_state:
		var card_data := CardDatabase.get_card(card_name)
		var base_cost: int = card_data.get("cost", 0)
		var effective: int = _game_state.get_effective_cost(card_name)
		if effective != base_cost:
			card.cost_override = effective
	card.setup(card_name, is_playable)
	if card_name in _cost_locked_cards:
		card.is_cost_locked = true
	card.card_clicked.connect(_on_card_clicked)
	card.card_hovered.connect(_on_card_hovered)
	card.card_unhovered.connect(_on_card_unhovered)
	return card


func _on_card_clicked(card_name: String) -> void:
	if multi_select_mode:
		# Toggle selection in multi-select mode
		if card_name in multi_selected_cards:
			multi_selected_cards.erase(card_name)
			card_toggled.emit(card_name, false)
			_update_card_selection_visual(card_name, false)
		else:
			multi_selected_cards.append(card_name)
			card_toggled.emit(card_name, true)
			_update_card_selection_visual(card_name, true)
	else:
		# Normal single-select mode
		if selected_card == card_name:
			# Deselect
			selected_card = ""
			card_deselected.emit()
		else:
			# Select
			selected_card = card_name
			card_selected.emit(card_name)


var _hovered_card_visual: CardVisual = null
const CARD_PEEK_LIFT := 50.0  # How far cards lift on hover


func _on_card_hovered(card_name: String) -> void:
	"""Show large preview and lift card when hovering."""
	# Find the hovered card visual
	var hovered_card: CardVisual = null
	for index: int in card_visuals:
		var card: CardVisual = card_visuals[index]
		if card.card_name == card_name:
			hovered_card = card
			break

	if hovered_card == null:
		return

	# Lift the card up (peek effect)
	if _hovered_card_visual != hovered_card:
		_unhover_current_card()
		_hovered_card_visual = hovered_card
		var tween := hovered_card.create_tween()
		tween.tween_property(hovered_card, "position:y", hovered_card.position.y - CARD_PEEK_LIFT, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		hovered_card.z_index = 10

	# Show large preview
	if preview_container == null or card_preview == null:
		return

	card_preview.setup(card_name, true, false)

	# Position preview above the hovered card, centered horizontally
	var card_global_pos := hovered_card.global_position
	var card_center_x := card_global_pos.x + hovered_card.size.x / 2
	var preview_width := VisualTheme.CARD_WIDTH * PREVIEW_SCALE
	var preview_height := VisualTheme.CARD_HEIGHT * PREVIEW_SCALE

	# Convert to local position relative to this control
	var local_pos := Vector2.ZERO
	local_pos.x = card_center_x - global_position.x - preview_width / 2
	local_pos.y = -preview_height - CARD_PEEK_LIFT - 20  # Above the lifted card

	# Clamp horizontal position to keep preview on screen
	var screen_width := get_viewport_rect().size.x
	var global_preview_x := global_position.x + local_pos.x
	if global_preview_x < 10:
		local_pos.x = 10 - global_position.x
	elif global_preview_x + preview_width > screen_width - 10:
		local_pos.x = screen_width - 10 - preview_width - global_position.x

	preview_container.position = local_pos
	preview_container.visible = true


func _unhover_current_card() -> void:
	"""Lower the previously hovered card back to its original position."""
	if _hovered_card_visual and is_instance_valid(_hovered_card_visual):
		var card := _hovered_card_visual
		card.z_index = 0
		var tween := card.create_tween()
		tween.tween_property(card, "position:y", 0.0, 0.1).set_ease(Tween.EASE_IN)
		_hovered_card_visual = null


func _on_card_unhovered(_card_name: String) -> void:
	"""Hide preview and lower card when not hovering."""
	_unhover_current_card()
	if preview_container:
		preview_container.visible = false


func _on_discard_clicked(pid: int) -> void:
	discard_pile_clicked.emit(pid)


func get_selected_card() -> String:
	return selected_card


func clear_selection() -> void:
	selected_card = ""
	card_deselected.emit()


func highlight_playable_cards() -> void:
	"""Visually highlight all playable cards."""
	for index: int in card_visuals:
		var card: CardVisual = card_visuals[index]
		card.set_playable(card.card_name in playable_cards)


func get_card_count() -> int:
	return card_visuals.size()


func set_multi_select_mode(enabled: bool) -> void:
	"""Enable or disable multi-select mode for card selection."""
	multi_select_mode = enabled
	multi_selected_cards = []

	# Update visual state of all cards
	for index: int in card_visuals:
		var card: CardVisual = card_visuals[index]
		card.set_playable(enabled)  # All cards selectable in multi-select mode
		_update_card_selection_visual(card.card_name, false)


func _update_card_selection_visual(card_name: String, selected: bool) -> void:
	"""Update the visual selection state of a card."""
	for index: int in card_visuals:
		var card: CardVisual = card_visuals[index]
		if card.card_name == card_name:
			card.set_selected(selected)
			break


func get_multi_selected_cards() -> Array[String]:
	"""Get all cards currently selected in multi-select mode."""
	return multi_selected_cards


func play_card_fly_animation(card_name: String) -> void:
	"""Animate a card flying upward from hand when played, with type-specific trail colors."""
	# Find the card visual in the hand
	var source_card: CardVisual = null
	for index: int in card_visuals:
		var card: CardVisual = card_visuals[index]
		if card.card_name == card_name:
			source_card = card
			break

	if source_card == null:
		return

	# Get card type for trail color
	var card_data := CardDatabase.get_card(card_name)
	var card_type: String = str(card_data.get("type", "Action"))
	var trail_color: Color
	match card_type:
		"Response":
			trail_color = VisualTheme.TRAIL_RESPONSE
		"Equipment":
			trail_color = VisualTheme.TRAIL_EQUIPMENT
		_:
			trail_color = VisualTheme.TRAIL_ACTION

	# Create a temporary clone card for the animation
	var fly_card: CardVisual = CARD_SCENE.instantiate()
	fly_card.setup(card_name, true, false)
	fly_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly_card.z_index = 50
	fly_card.pivot_offset = Vector2(VisualTheme.CARD_WIDTH / 2, VisualTheme.CARD_HEIGHT / 2)

	# Get start position before adding to tree
	var start_pos := source_card.global_position

	# Add to the scene tree at a high level so it renders above everything
	var viewport := get_viewport()
	if viewport and viewport.get_child(0):
		viewport.get_child(0).add_child(fly_card)
	else:
		add_child(fly_card)

	# Set position after adding to tree so global_position works
	fly_card.global_position = start_pos

	# Fly upward toward board center, scale up slightly, then fade
	var target_pos := Vector2(
		get_viewport_rect().size.x / 2 - fly_card.size.x / 2,
		get_viewport_rect().size.y / 2 - fly_card.size.y
	)

	# Spawn trail ghosts behind the flying card (type-colored)
	var parent_node := fly_card.get_parent()
	for ghost_i in range(3):
		var ghost := ColorRect.new()
		var ghost_col := trail_color
		ghost_col.a = trail_color.a - float(ghost_i) * 0.04
		ghost.color = ghost_col
		ghost.size = fly_card.size
		ghost.global_position = start_pos
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.z_index = 49 - ghost_i
		ghost.pivot_offset = fly_card.size / 2
		parent_node.add_child(ghost)
		var ghost_delay := 0.04 + float(ghost_i) * 0.04
		var ghost_tween := ghost.create_tween()
		ghost_tween.set_parallel(true)
		ghost_tween.tween_property(ghost, "global_position", target_pos, 0.35 + ghost_delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(ghost_delay)
		ghost_tween.tween_property(ghost, "modulate:a", 0.0, 0.25).set_delay(ghost_delay + 0.05)
		ghost_tween.chain().tween_callback(ghost.queue_free)

	var tween := fly_card.create_tween()
	tween.set_parallel(true)
	tween.tween_property(fly_card, "global_position", target_pos, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(fly_card, "scale", Vector2(1.2, 1.2), 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(fly_card, "modulate:a", 0.0, 0.35).set_ease(Tween.EASE_IN).set_delay(0.1)
	tween.chain().tween_callback(fly_card.queue_free)
