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
	offset_top = -200  # Height of the hand area
	offset_left = 240   # After left side panel (220 + margin)
	offset_right = -240  # Before right side panel
	offset_bottom = 0

	_create_ui()
	_is_ready = true


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

	# Discard pile on left
	discard_pile = DISCARD_SCENE.instantiate() as DiscardPile
	discard_pile.setup(player_id)
	discard_pile.pile_clicked.connect(_on_discard_clicked)
	discard_pile.custom_minimum_size = Vector2(110, 0)  # Slightly wider
	main_container.add_child(discard_pile)

	# Separator with styling
	var separator := VSeparator.new()
	separator.custom_minimum_size = Vector2(2, 0)
	main_container.add_child(separator)

	# Cards container (takes remaining space)
	var cards_panel := PanelContainer.new()
	cards_panel.name = "CardsPanel"
	cards_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	var style := StyleBoxFlat.new()
	style.bg_color = VisualTheme.GRADIENT_PANEL_BOTTOM.lerp(Color.BLACK, 0.1)
	style.set_border_width_all(1)
	style.border_color = VisualTheme.UI_PANEL_BORDER.lerp(VisualTheme.PLAYER1_COLOR, 0.2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(VisualTheme.PADDING_PANEL)
	style.shadow_color = VisualTheme.SHADOW_SOFT
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, -2)  # Shadow on top for inset effect
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


var _previous_hand_size: int = 0

func update_hand(hand: Array, mana: int, valid_responses: Array[String] = [], restricted_cards: Array[String] = []) -> void:
	"""Update displayed cards from hand array.
	valid_responses: If non-empty, these response cards are playable (response window is open).
	restricted_cards: Cards that cannot be played due to game state (e.g. champion already attacked)."""
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
		var cost: int = card_data.get("cost", 0)
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
		tween.tween_interval(i * 0.04)
		tween.tween_property(card_visual, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(card_visual, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

		# Newly drawn card gets a golden flash highlight
		if is_new_card:
			tween.tween_property(card_visual, "modulate", Color(1.3, 1.2, 0.8), 0.15)
			tween.tween_property(card_visual, "modulate", Color.WHITE, 0.3)


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
	card.setup(card_name, is_playable)
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


func _on_card_hovered(card_name: String) -> void:
	"""Show large preview when hovering over a card."""
	if preview_container == null or card_preview == null:
		return

	# Find the hovered card visual to position the preview
	var hovered_card: CardVisual = null
	for index: int in card_visuals:
		var card: CardVisual = card_visuals[index]
		if card.card_name == card_name:
			hovered_card = card
			break

	if hovered_card == null:
		return

	# Setup the preview card
	card_preview.setup(card_name, true, false)

	# Position preview above the hovered card, centered horizontally
	var card_global_pos := hovered_card.global_position
	var card_center_x := card_global_pos.x + hovered_card.size.x / 2
	var preview_width := VisualTheme.CARD_WIDTH * PREVIEW_SCALE
	var preview_height := VisualTheme.CARD_HEIGHT * PREVIEW_SCALE

	# Convert to local position relative to this control
	var local_pos := Vector2.ZERO
	local_pos.x = card_center_x - global_position.x - preview_width / 2
	local_pos.y = -preview_height - 20  # Above the hand with some padding

	# Clamp horizontal position to keep preview on screen
	var screen_width := get_viewport_rect().size.x
	var global_preview_x := global_position.x + local_pos.x
	if global_preview_x < 10:
		local_pos.x = 10 - global_position.x
	elif global_preview_x + preview_width > screen_width - 10:
		local_pos.x = screen_width - 10 - preview_width - global_position.x

	preview_container.position = local_pos
	preview_container.visible = true


func _on_card_unhovered(_card_name: String) -> void:
	"""Hide preview when not hovering."""
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
	"""Animate a card flying upward from hand when played."""
	# Find the card visual in the hand
	var source_card: CardVisual = null
	for index: int in card_visuals:
		var card: CardVisual = card_visuals[index]
		if card.card_name == card_name:
			source_card = card
			break

	if source_card == null:
		return

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

	var tween := fly_card.create_tween()
	tween.set_parallel(true)
	tween.tween_property(fly_card, "global_position", target_pos, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(fly_card, "scale", Vector2(1.2, 1.2), 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(fly_card, "modulate:a", 0.0, 0.35).set_ease(Tween.EASE_IN).set_delay(0.1)
	tween.chain().tween_callback(fly_card.queue_free)
