extends Control
class_name ResponseSlot
## ResponseSlot - UI for the response card slot
## Players can place one response card here to auto-trigger when conditions are met

signal card_placed(card_name: String)
signal card_removed(card_name: String)
signal slot_clicked()

const CARD_SCENE := preload("res://scenes/game/cards/card_visual.tscn")

var player_id: int = 1
var slotted_card: String = ""
var card_visual: CardVisual = null
var game_state: GameState = null

# Visual settings
const SLOT_WIDTH := 120
const SLOT_HEIGHT := 170
const BORDER_WIDTH := 3


func _ready() -> void:
	custom_minimum_size = Vector2(SLOT_WIDTH, SLOT_HEIGHT)
	size = Vector2(SLOT_WIDTH, SLOT_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	gui_input.connect(_on_gui_input)


func setup(pid: int, state: GameState) -> void:
	"""Initialize the response slot for a player."""
	player_id = pid
	game_state = state
	queue_redraw()


func update_slot() -> void:
	"""Update the slot display based on game state."""
	if game_state == null:
		return

	var current_card := game_state.get_response_slot(player_id)

	if current_card != slotted_card:
		slotted_card = current_card
		_update_card_visual()


func _update_card_visual() -> void:
	"""Update or create the card visual in the slot."""
	# Remove existing card visual
	if card_visual != null:
		card_visual.queue_free()
		card_visual = null

	if slotted_card.is_empty():
		queue_redraw()
		return

	# Create new card visual
	card_visual = CARD_SCENE.instantiate()
	add_child(card_visual)

	# Scale card to fit slot
	var scale_factor := 0.85
	card_visual.scale = Vector2(scale_factor, scale_factor)
	card_visual.position = Vector2(
		(SLOT_WIDTH - VisualTheme.CARD_WIDTH * scale_factor) / 2,
		(SLOT_HEIGHT - VisualTheme.CARD_HEIGHT * scale_factor) / 2
	)

	card_visual.setup(slotted_card, true)
	card_visual.card_clicked.connect(_on_card_clicked)

	queue_redraw()


func _on_card_clicked(_card_name: String) -> void:
	"""Handle clicking the slotted card - remove it."""
	if not slotted_card.is_empty():
		var removed := slotted_card
		card_removed.emit(removed)


func _on_gui_input(event: InputEvent) -> void:
	"""Handle clicking the empty slot."""
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit()


func _draw() -> void:
	var w := size.x
	var h := size.y

	# Background
	var bg_color := Color(0.12, 0.12, 0.15, 0.9)
	draw_rect(Rect2(0, 0, w, h), bg_color)

	# Border color based on state
	var border_color: Color
	if slotted_card.is_empty():
		border_color = Color(0.4, 0.4, 0.5, 0.7)  # Dim when empty
	else:
		border_color = Color(0.9, 0.6, 0.2, 1.0)  # Orange when card slotted

	# Border
	draw_rect(Rect2(0, 0, w, h), border_color, false, BORDER_WIDTH)

	# Label
	var font := ThemeDB.fallback_font
	var label_text := "RESPONSE"
	var label_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
	var label_pos := Vector2((w - label_size.x) / 2, h - 8)
	draw_string(font, label_pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.6, 0.6, 0.7))

	# If empty, show hint
	if slotted_card.is_empty():
		var hint_text := "Drop"
		var hint_size := font.get_string_size(hint_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		var hint_pos := Vector2((w - hint_size.x) / 2, h / 2 - 10)
		draw_string(font, hint_pos, hint_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.5, 0.5, 0.6))

		var hint_text2 := "Response"
		var hint_size2 := font.get_string_size(hint_text2, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		var hint_pos2 := Vector2((w - hint_size2.x) / 2, h / 2 + 5)
		draw_string(font, hint_pos2, hint_text2, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.5, 0.5, 0.6))

		var hint_text3 := "Card"
		var hint_size3 := font.get_string_size(hint_text3, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		var hint_pos3 := Vector2((w - hint_size3.x) / 2, h / 2 + 20)
		draw_string(font, hint_pos3, hint_text3, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.5, 0.5, 0.6))


func get_trigger() -> String:
	"""Get the trigger type for the slotted card."""
	if slotted_card.is_empty():
		return ""

	var card_data := CardDatabase.get_card(slotted_card)
	return card_data.get("trigger", "")


func get_cost() -> int:
	"""Get the mana cost of the slotted card."""
	if slotted_card.is_empty():
		return 0

	var card_data := CardDatabase.get_card(slotted_card)
	return card_data.get("cost", 0)


func can_afford() -> bool:
	"""Check if player can afford to cast the slotted card."""
	if slotted_card.is_empty() or game_state == null:
		return false

	var cost := get_cost()
	var mana := game_state.get_mana(player_id)
	return mana >= cost
