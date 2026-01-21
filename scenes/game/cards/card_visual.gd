extends Control
class_name CardVisual
## CardVisual - Card display using character art as background
## Overlays: Cost (top-right), Name (top-middle), Description (bottom)

signal card_clicked(card_name: String)
signal card_hovered(card_name: String)
signal card_unhovered(card_name: String)

const HOVER_LIFT := 30
const HOVER_SCALE := 1.05
const CHARACTER_ART_PATH := "res://assets/art/characters/"

# UI overlay colors
const OVERLAY_BG := Color(0.1, 0.1, 0.12, 0.85)
const OVERLAY_BORDER := Color(0.4, 0.4, 0.45, 0.9)

var card_name: String = ""
var card_data: Dictionary = {}
var is_playable: bool = true
var is_hovered: bool = false
var is_face_down: bool = false
var original_position: Vector2 = Vector2.ZERO
var character_texture: Texture2D = null

# Deferred setup data
var _pending_setup: bool = false
var _pending_card_name: String = ""
var _pending_playable: bool = true
var _pending_face_down: bool = false


func _ready() -> void:
	# Ensure we receive mouse events
	mouse_filter = Control.MOUSE_FILTER_STOP

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	custom_minimum_size = Vector2(VisualTheme.CARD_WIDTH, VisualTheme.CARD_HEIGHT)
	size = Vector2(VisualTheme.CARD_WIDTH, VisualTheme.CARD_HEIGHT)

	# Process any pending setup
	if _pending_setup:
		_do_setup(_pending_card_name, _pending_playable, _pending_face_down)
		_pending_setup = false


func setup(card_name_: String, playable: bool = true, face_down: bool = false) -> void:
	"""Initialize card with data. Can be called before or after _ready."""
	if not is_inside_tree():
		# _ready hasn't run yet, defer the setup
		_pending_setup = true
		_pending_card_name = card_name_
		_pending_playable = playable
		_pending_face_down = face_down
		return

	_do_setup(card_name_, playable, face_down)


func _do_setup(card_name_: String, playable: bool, face_down: bool) -> void:
	"""Actually perform the setup."""
	card_name = card_name_
	card_data = CardDatabase.get_card(card_name)
	is_playable = playable
	is_face_down = face_down

	# Load character art texture
	character_texture = _load_character_art()

	queue_redraw()


func _load_character_art() -> Texture2D:
	"""Load the character art texture for this card's champion."""
	if card_data.is_empty():
		return null

	var champion: String = card_data.get("character", "")
	if champion.is_empty():
		return null

	var full_path := CHARACTER_ART_PATH + champion + ".png"

	# Try to load the texture
	if ResourceLoader.exists(full_path):
		return load(full_path)
	else:
		print("CardVisual: Missing character art for '%s'" % champion)
		return null


func set_playable(playable: bool) -> void:
	"""Update playable state."""
	is_playable = playable
	queue_redraw()


func set_face_down(face_down: bool) -> void:
	"""Show card back instead of front."""
	is_face_down = face_down
	queue_redraw()


func _draw() -> void:
	if is_face_down:
		_draw_card_back()
	else:
		_draw_card_front()


func _draw_card_back() -> void:
	"""Draw the universal Arena card back design."""
	var w := size.x
	var h := size.y

	# Outer border
	draw_rect(Rect2(0, 0, w, h), VisualTheme.CARD_BACK["border"], false, 3.0)

	# Background gradient
	var bg_rect := Rect2(2, 2, w - 4, h - 4)
	draw_rect(bg_rect, VisualTheme.CARD_BACK["primary"])

	# Inner decorative border
	var inner_rect := Rect2(8, 8, w - 16, h - 16)
	draw_rect(inner_rect, VisualTheme.CARD_BACK["secondary"], false, 2.0)

	# Diamond pattern in center
	var center := Vector2(w / 2, h / 2)
	var diamond_size := 30.0
	var diamond_points := PackedVector2Array([
		center + Vector2(0, -diamond_size),
		center + Vector2(diamond_size, 0),
		center + Vector2(0, diamond_size),
		center + Vector2(-diamond_size, 0)
	])
	draw_colored_polygon(diamond_points, VisualTheme.CARD_BACK["accent"])
	draw_polyline(diamond_points + PackedVector2Array([diamond_points[0]]), VisualTheme.CARD_BACK["border"], 2.0)

	# Inner diamond
	diamond_size = 18.0
	diamond_points = PackedVector2Array([
		center + Vector2(0, -diamond_size),
		center + Vector2(diamond_size, 0),
		center + Vector2(0, diamond_size),
		center + Vector2(-diamond_size, 0)
	])
	draw_colored_polygon(diamond_points, VisualTheme.CARD_BACK["secondary"])

	# "ARENA" text
	var font := ThemeDB.fallback_font
	var text := "ARENA"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
	draw_string(font, Vector2((w - text_size.x) / 2, h - 20), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, VisualTheme.CARD_BACK["accent"])

	# Corner decorations
	_draw_corner_flourish(Vector2(12, 12), 1)
	_draw_corner_flourish(Vector2(w - 12, 12), 2)
	_draw_corner_flourish(Vector2(12, h - 12), 3)
	_draw_corner_flourish(Vector2(w - 12, h - 12), 4)


func _draw_corner_flourish(pos: Vector2, corner: int) -> void:
	"""Draw a small decorative element at a corner."""
	var color := VisualTheme.CARD_BACK["accent"]
	var size_f := 6.0
	match corner:
		1:  # Top-left
			draw_line(pos, pos + Vector2(size_f, 0), color, 1.5)
			draw_line(pos, pos + Vector2(0, size_f), color, 1.5)
		2:  # Top-right
			draw_line(pos, pos + Vector2(-size_f, 0), color, 1.5)
			draw_line(pos, pos + Vector2(0, size_f), color, 1.5)
		3:  # Bottom-left
			draw_line(pos, pos + Vector2(size_f, 0), color, 1.5)
			draw_line(pos, pos + Vector2(0, -size_f), color, 1.5)
		4:  # Bottom-right
			draw_line(pos, pos + Vector2(-size_f, 0), color, 1.5)
			draw_line(pos, pos + Vector2(0, -size_f), color, 1.5)


func _draw_card_front() -> void:
	"""Draw card with character art background and overlaid UI elements."""
	if card_data.is_empty():
		_draw_placeholder()
		return

	var w := size.x
	var h := size.y
	var card_type: String = card_data.get("type", "Action")
	var champion: String = card_data.get("character", "")
	var cost: int = card_data.get("cost", 0)
	var font := ThemeDB.fallback_font

	# Get colors for card type border
	var type_colors := VisualTheme.get_card_type_colors(card_type)
	var border_color: Color = type_colors["border"]
	if not is_playable:
		border_color = border_color.lerp(Color(0.2, 0.2, 0.2), 0.65)

	# === CARD BORDER ===
	draw_rect(Rect2(0, 0, w, h), border_color)

	# === CHARACTER ART BACKGROUND ===
	var art_rect := Rect2(2, 2, w - 4, h - 4)

	if character_texture != null:
		# Draw character art as full card background
		var tex_size := character_texture.get_size()

		# Scale to fill the card (crop if needed)
		var scale_x := art_rect.size.x / tex_size.x
		var scale_y := art_rect.size.y / tex_size.y
		var scale_factor := maxf(scale_x, scale_y)  # Use max to fill

		var scaled_size := tex_size * scale_factor
		var offset := (art_rect.size - scaled_size) / 2.0
		var draw_pos := art_rect.position + offset

		# Apply dim effect if not playable
		var modulate_color := Color.WHITE if is_playable else Color(0.4, 0.4, 0.4)
		draw_texture_rect(character_texture, Rect2(draw_pos, scaled_size), false, modulate_color)
	else:
		# Fallback: solid color background
		var champ_colors := VisualTheme.get_champion_colors(champion)
		var bg_color: Color = champ_colors["primary"].lerp(Color(0.1, 0.1, 0.1), 0.5)
		if not is_playable:
			bg_color = bg_color.lerp(Color(0.2, 0.2, 0.2), 0.6)
		draw_rect(art_rect, bg_color)

	# === COST OVERLAY (Top Right) ===
	var cost_size := 28.0
	var cost_margin := 6.0
	var cost_rect := Rect2(w - cost_size - cost_margin, cost_margin, cost_size, cost_size)

	# Background circle
	var cost_center := cost_rect.position + Vector2(cost_size / 2, cost_size / 2)
	var cost_bg_color := OVERLAY_BG if is_playable else Color(0.15, 0.15, 0.18, 0.9)
	draw_circle(cost_center, cost_size / 2, cost_bg_color)
	draw_arc(cost_center, cost_size / 2, 0, TAU, 32, OVERLAY_BORDER, 2.0)

	# Cost number
	var cost_str := str(cost)
	var cost_text_size := font.get_string_size(cost_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	var cost_text_pos := cost_center + Vector2(-cost_text_size.x / 2, 6)
	var cost_color := Color(1.0, 0.9, 0.5) if is_playable else Color(0.5, 0.5, 0.5)
	draw_string(font, cost_text_pos, cost_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, cost_color)

	# === NAME OVERLAY (Top Middle) ===
	var name_margin := 4.0
	var name_height := 22.0
	var name_width := w - cost_size - cost_margin * 2 - name_margin * 2
	var name_rect := Rect2(name_margin, name_margin, name_width, name_height)

	# Background
	draw_rect(name_rect, OVERLAY_BG)
	draw_rect(name_rect, OVERLAY_BORDER, false, 1.0)

	# Card name text
	var card_name_text: String = card_data.get("name", "Unknown")
	if card_name_text.length() > 16:
		card_name_text = card_name_text.substr(0, 15) + ".."
	var name_color := Color.WHITE if is_playable else Color(0.6, 0.6, 0.6)
	var name_text_pos := Vector2(name_margin + 4, name_margin + 16)
	draw_string(font, name_text_pos, card_name_text, HORIZONTAL_ALIGNMENT_LEFT, int(name_width) - 8, 12, name_color)

	# === TYPE INDICATOR (small badge next to name) ===
	var type_short := card_type.substr(0, 1)  # A, R, or E
	var type_badge_pos := Vector2(name_rect.end.x - 16, name_margin + 15)
	var type_color: Color
	match card_type:
		"Action":
			type_color = Color(0.3, 0.6, 0.9) if is_playable else Color(0.3, 0.3, 0.4)
		"Response":
			type_color = Color(0.9, 0.6, 0.3) if is_playable else Color(0.4, 0.3, 0.3)
		"Equipment":
			type_color = Color(0.6, 0.9, 0.3) if is_playable else Color(0.3, 0.4, 0.3)
		_:
			type_color = Color(0.6, 0.6, 0.6)
	draw_string(font, type_badge_pos, type_short, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, type_color)

	# === DESCRIPTION OVERLAY (Bottom) ===
	var desc_margin := 4.0
	var desc_height := 70.0
	var desc_rect := Rect2(desc_margin, h - desc_height - desc_margin, w - desc_margin * 2, desc_height)

	# Background
	draw_rect(desc_rect, OVERLAY_BG)
	draw_rect(desc_rect, OVERLAY_BORDER, false, 1.0)

	# Description text (wrapped)
	var desc: String = card_data.get("description", "")
	var desc_text_rect := Rect2(desc_rect.position.x + 4, desc_rect.position.y + 2, desc_rect.size.x - 8, desc_rect.size.y - 4)
	_draw_wrapped_text(desc, desc_text_rect, 9)

	# === PLAYABILITY INDICATOR ===
	if is_playable and is_hovered:
		# Glow effect when playable and hovered
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 0.7, 0.2))
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 0.5, 0.8), false, 2.0)


func _draw_wrapped_text(text: String, rect: Rect2, font_size: int) -> void:
	"""Draw text wrapped within a rectangle."""
	var font := ThemeDB.fallback_font
	var line_height := font_size + 2
	var max_width := rect.size.x
	var words := text.split(" ")
	var lines: Array[String] = []
	var current_line := ""

	for word in words:
		var test_line := current_line + " " + word if current_line else word
		var test_width := font.get_string_size(test_line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if test_width <= max_width:
			current_line = test_line
		else:
			if current_line:
				lines.append(current_line)
			current_line = word

	if current_line:
		lines.append(current_line)

	# Draw lines
	var y := rect.position.y + line_height
	var max_lines := int(rect.size.y / line_height)
	var text_color := Color(0.9, 0.9, 0.9) if is_playable else Color(0.5, 0.5, 0.5)

	for i in range(mini(lines.size(), max_lines)):
		var line := lines[i]
		if i == max_lines - 1 and lines.size() > max_lines:
			line = line.substr(0, line.length() - 3) + "..."
		draw_string(font, Vector2(rect.position.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		y += line_height


func _draw_placeholder() -> void:
	"""Draw a placeholder card when no data."""
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.3, 0.3, 0.35))
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.2, 0.2, 0.25), false, 2.0)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(size.x / 2 - 10, size.y / 2), "?", HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color(0.5, 0.5, 0.5))


func _on_mouse_entered() -> void:
	is_hovered = true
	original_position = position
	position.y -= HOVER_LIFT
	z_index = 10
	queue_redraw()
	card_hovered.emit(card_name)


func _on_mouse_exited() -> void:
	is_hovered = false
	position = original_position
	z_index = 0
	queue_redraw()
	card_unhovered.emit(card_name)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if is_playable:
				card_clicked.emit(card_name)
