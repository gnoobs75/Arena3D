extends Control
class_name DiscardPile
## DiscardPile - Visual representation of a discard pile
## Shows stacked cards with count badge and top card preview

signal pile_clicked(player_id: int)

const CARD_OFFSET := 2  # Pixels between stacked cards
const MAX_VISIBLE_STACK := 5  # Max cards to show in stack visual
const PILE_WIDTH := 100
const PILE_HEIGHT := 140

var player_id: int = 1
var discard_cards: Array = []  # Array of card names
var _is_hovered: bool = false


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	custom_minimum_size = Vector2(PILE_WIDTH, PILE_HEIGHT)
	size = custom_minimum_size


func setup(player: int) -> void:
	"""Initialize for a specific player."""
	player_id = player
	queue_redraw()


func update_pile(cards: Array) -> void:
	"""Update the discard pile contents."""
	discard_cards = cards.duplicate()
	queue_redraw()


func get_card_count() -> int:
	"""Get number of cards in discard pile."""
	return discard_cards.size()


func _draw() -> void:
	var w := size.x
	var h := size.y

	# Draw pile background/area
	var bg_color := Color(0.1, 0.1, 0.12, 0.8)
	draw_rect(Rect2(0, 0, w, h), bg_color)
	draw_rect(Rect2(0, 0, w, h), VisualTheme.UI_PANEL_BORDER, false, 1.0)

	if discard_cards.is_empty():
		_draw_empty_pile()
	else:
		_draw_card_stack()

	# Label
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(4, h - 6), "Discard", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, VisualTheme.UI_TEXT_DIM)

	# Hover effect
	if _is_hovered:
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.1))


func _draw_empty_pile() -> void:
	"""Draw placeholder for empty pile."""
	var center := size / 2 - Vector2(0, 10)

	# Dashed border to indicate card placement
	var card_w := 60.0
	var card_h := 80.0
	var card_rect := Rect2(center.x - card_w / 2, center.y - card_h / 2, card_w, card_h)

	draw_rect(card_rect, Color(0.2, 0.2, 0.25), false, 1.0)

	# "Empty" text
	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-15, 5), "Empty", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.4, 0.4, 0.45))


func _draw_card_stack() -> void:
	"""Draw stacked cards with top card visible."""
	var stack_count := mini(discard_cards.size(), MAX_VISIBLE_STACK)
	var center_x := size.x / 2
	var base_y := 15.0

	var card_w := 60.0
	var card_h := 80.0

	# Draw stack layers (back cards)
	for i in range(stack_count - 1):
		var offset := i * CARD_OFFSET
		var card_rect := Rect2(center_x - card_w / 2 + offset, base_y + offset, card_w, card_h)
		_draw_mini_card_back(card_rect)

	# Draw top card (face up)
	if discard_cards.size() > 0:
		var top_card_name: String = discard_cards[discard_cards.size() - 1]
		var offset := (stack_count - 1) * CARD_OFFSET
		var card_rect := Rect2(center_x - card_w / 2 + offset, base_y + offset, card_w, card_h)
		_draw_mini_card_front(card_rect, top_card_name)

	# Count badge
	_draw_count_badge()


func _draw_mini_card_back(rect: Rect2) -> void:
	"""Draw a miniature card back."""
	# Border
	draw_rect(rect, VisualTheme.CARD_BACK["border"])
	# Background
	draw_rect(Rect2(rect.position.x + 1, rect.position.y + 1, rect.size.x - 2, rect.size.y - 2), VisualTheme.CARD_BACK["primary"])
	# Inner border
	draw_rect(Rect2(rect.position.x + 3, rect.position.y + 3, rect.size.x - 6, rect.size.y - 6), VisualTheme.CARD_BACK["secondary"], false, 1.0)

	# Small diamond
	var center := rect.position + rect.size / 2
	var diamond_size := 8.0
	var diamond_points := PackedVector2Array([
		center + Vector2(0, -diamond_size),
		center + Vector2(diamond_size, 0),
		center + Vector2(0, diamond_size),
		center + Vector2(-diamond_size, 0)
	])
	draw_colored_polygon(diamond_points, VisualTheme.CARD_BACK["accent"])


func _draw_mini_card_front(rect: Rect2, card_name: String) -> void:
	"""Draw a miniature card front."""
	var card_data := CardDatabase.get_card(card_name)
	if card_data.is_empty():
		_draw_mini_card_back(rect)
		return

	var card_type: String = card_data.get("type", "Action")
	var champion: String = card_data.get("character", "")
	var cost: int = card_data.get("cost", 0)

	var type_colors := VisualTheme.get_card_type_colors(card_type)
	var champ_colors := VisualTheme.get_champion_colors(champion)

	# Border
	draw_rect(rect, type_colors["border"])
	# Background
	draw_rect(Rect2(rect.position.x + 1, rect.position.y + 1, rect.size.x - 2, rect.size.y - 2), type_colors["primary"])

	# Header with champion color
	var header_rect := Rect2(rect.position.x + 1, rect.position.y + 1, rect.size.x - 2, 12)
	draw_rect(header_rect, champ_colors["primary"])

	# Mini cost circle
	var cost_center := rect.position + Vector2(10, 10)
	draw_circle(cost_center, 6, VisualTheme.get_mana_cost_color(cost))
	var font := ThemeDB.fallback_font
	draw_string(font, cost_center + Vector2(-3, 3), str(cost), HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)

	# Card name (abbreviated)
	var name_text: String = card_data.get("name", "?")
	if name_text.length() > 8:
		name_text = name_text.substr(0, 7) + ".."
	draw_string(font, rect.position + Vector2(4, rect.size.y / 2 + 4), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)

	# Champion symbol
	var symbol := VisualTheme.get_champion_symbol(champion)
	var symbol_pos := rect.position + Vector2(rect.size.x / 2 - 6, rect.size.y - 15)
	draw_string(font, symbol_pos, symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, champ_colors["secondary"].lerp(Color.WHITE, 0.3))


func _draw_count_badge() -> void:
	"""Draw the card count badge."""
	var count := discard_cards.size()
	var badge_pos := Vector2(size.x - 20, 8)
	var badge_radius := 12.0

	# Badge background
	draw_circle(badge_pos, badge_radius, VisualTheme.UI_ACCENT)
	draw_circle(badge_pos, badge_radius - 1, VisualTheme.UI_PANEL_BG)

	# Count text
	var font := ThemeDB.fallback_font
	var count_str := str(count)
	var text_offset := Vector2(-4, 4) if count < 10 else Vector2(-6, 4)
	draw_string(font, badge_pos + text_offset, count_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, VisualTheme.UI_ACCENT)


func _on_mouse_entered() -> void:
	_is_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_is_hovered = false
	queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pile_clicked.emit(player_id)
