extends Control
class_name HandUI
## HandUI - Enhanced container for player's hand of cards
## Includes card display and discard pile

signal card_selected(card_name: String)
signal card_deselected()
signal discard_pile_clicked(player_id: int)

const CARD_SPACING := 10
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


func _ready() -> void:
	_create_ui()
	_is_ready = true


func _create_ui() -> void:
	"""Create the hand UI layout."""
	# Background (styled) - add first so it's behind everything
	background = ColorRect.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.08, 0.08, 0.12, 0.9)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block mouse input
	add_child(background)

	# Main container
	var main_container := HBoxContainer.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.add_theme_constant_override("separation", 10)
	main_container.mouse_filter = Control.MOUSE_FILTER_PASS  # Pass mouse to children
	add_child(main_container)

	# Discard pile on left
	discard_pile = DISCARD_SCENE.instantiate() as DiscardPile
	discard_pile.setup(player_id)
	discard_pile.pile_clicked.connect(_on_discard_clicked)
	discard_pile.custom_minimum_size = Vector2(100, 0)
	main_container.add_child(discard_pile)

	# Separator
	var separator := VSeparator.new()
	separator.custom_minimum_size = Vector2(2, 0)
	main_container.add_child(separator)

	# Cards container (takes remaining space)
	var cards_panel := PanelContainer.new()
	cards_panel.name = "CardsPanel"
	cards_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_panel.mouse_filter = Control.MOUSE_FILTER_PASS  # Pass mouse to children

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.5)
	style.set_border_width_all(1)
	style.border_color = VisualTheme.UI_PANEL_BORDER
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	cards_panel.add_theme_stylebox_override("panel", style)
	main_container.add_child(cards_panel)

	cards_container = HBoxContainer.new()
	cards_container.name = "CardsContainer"
	cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_container.add_theme_constant_override("separation", CARD_SPACING)
	cards_container.mouse_filter = Control.MOUSE_FILTER_PASS  # Pass mouse to children
	cards_panel.add_child(cards_container)


func setup(player: int) -> void:
	"""Initialize for a specific player."""
	player_id = player
	if discard_pile:
		discard_pile.setup(player)


func update_hand(hand: Array, mana: int) -> void:
	"""Update displayed cards from hand array."""
	if not _is_ready or cards_container == null:
		return
	_clear_cards()

	# Determine playable cards
	playable_cards.clear()
	for card_name: String in hand:
		var card_data := CardDatabase.get_card(card_name)
		var cost: int = card_data.get("cost", 0)
		var card_type: String = str(card_data.get("type", ""))

		# Response cards aren't playable from hand normally
		if card_type != "Response" and cost <= mana:
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
