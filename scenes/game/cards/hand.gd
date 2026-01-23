extends Control
class_name HandUI
## HandUI - Enhanced container for player's hand of cards
## Includes card display and discard pile

signal card_selected(card_name: String)
signal card_deselected()
signal card_toggled(card_name: String, selected: bool)  # For multi-select mode
signal discard_pile_clicked(player_id: int)

const CARD_SPACING := 12  # Increased for better spacing
const CARD_SCENE := preload("res://scenes/game/cards/card_visual.tscn")
const DISCARD_SCENE := preload("res://scenes/game/cards/discard_pile.tscn")

# Node references - fetched in _ready() for safety
var cards_container: HBoxContainer
var discard_pile: DiscardPile
var background: ColorRect
var _is_ready: bool = false

var player_id: int = 1
var card_visuals: Dictionary = {}  # card_index -> CardVisual
var selected_card: String = ""
var playable_cards: Array[String] = []

# Multi-select mode (for From the Sky, etc.)
var multi_select_mode: bool = false
var multi_selected_cards: Array[String] = []


func _ready() -> void:
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


func setup(player: int) -> void:
	"""Initialize for a specific player."""
	player_id = player
	if discard_pile:
		discard_pile.setup(player)


func update_hand(hand: Array, mana: int, valid_responses: Array[String] = []) -> void:
	"""Update displayed cards from hand array.
	valid_responses: If non-empty, these response cards are playable (response window is open)."""
	if not _is_ready or cards_container == null:
		return
	_clear_cards()

	# Determine playable cards
	playable_cards.clear()
	for card_name: String in hand:
		# In multi-select mode (discard selection), ALL cards are selectable
		if multi_select_mode:
			playable_cards.append(card_name)
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

	# Create card visuals
	for i in range(hand.size()):
		var card_name: String = hand[i]
		var is_playable := card_name in playable_cards
		var card_visual := _create_card_visual(card_name, is_playable, i)
		cards_container.add_child(card_visual)
		card_visuals[i] = card_visual


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
	# Could show card detail popup
	pass


func _on_card_unhovered(card_name: String) -> void:
	pass


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
