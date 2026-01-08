extends Control
class_name CardVisual
## CardVisual - Beautiful visual representation of a card
## Features styled borders, champion colors, mana gems, and hover effects

signal card_clicked(card_name: String)
signal card_hovered(card_name: String)
signal card_unhovered(card_name: String)

const HOVER_LIFT := 30
const HOVER_SCALE := 1.05

var card_name: String = ""
var card_data: Dictionary = {}
var is_playable: bool = true
var is_hovered: bool = false
var is_face_down: bool = false
var original_position: Vector2 = Vector2.ZERO

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
	queue_redraw()


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
	"""Draw the card front with all details."""
	if card_data.is_empty():
		_draw_placeholder()
		return

	var w := size.x
	var h := size.y
	var card_type: String = card_data.get("type", "Action")
	var champion: String = card_data.get("character", "")
	var cost: int = card_data.get("cost", 0)

	var type_colors := VisualTheme.get_card_type_colors(card_type)
	var champ_colors := VisualTheme.get_champion_colors(champion)

	# Adjust colors if not playable
	var primary_color: Color = type_colors["primary"]
	var secondary_color: Color = type_colors["secondary"]
	var border_color: Color = type_colors["border"]

	if not is_playable:
		primary_color = primary_color.lerp(Color(0.25, 0.25, 0.25), 0.65)
		secondary_color = secondary_color.lerp(Color(0.3, 0.3, 0.3), 0.65)
		border_color = border_color.lerp(Color(0.2, 0.2, 0.2), 0.65)

	# === CARD FRAME ===
	# Outer border
	draw_rect(Rect2(0, 0, w, h), border_color)

	# Main background
	var main_rect := Rect2(2, 2, w - 4, h - 4)
	draw_rect(main_rect, primary_color)

	# === HEADER SECTION (champion color accent) ===
	var header_height := 24.0
	var header_color: Color = champ_colors["primary"] if is_playable else champ_colors["primary"].lerp(Color(0.3, 0.3, 0.3), 0.5)
	draw_rect(Rect2(2, 2, w - 4, header_height), header_color)

	# === MANA COST GEM ===
	_draw_mana_gem(Vector2(16, 14), cost)

	# === TYPE BADGE ===
	var type_badge_x := w - 8.0
	var type_short := card_type.substr(0, 1)  # A, R, or E
	var font := ThemeDB.fallback_font
	var badge_color := secondary_color if is_playable else secondary_color.lerp(Color(0.3, 0.3, 0.3), 0.5)
	draw_circle(Vector2(type_badge_x - 10, 14), 8, badge_color)
	draw_string(font, Vector2(type_badge_x - 14, 18), type_short, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)

	# === ART AREA ===
	var art_top := header_height + 4
	var art_height := 50.0
	var art_rect := Rect2(6, art_top, w - 12, art_height)

	# Gradient background for art area
	var art_color1: Color = champ_colors["primary"].lerp(Color(0.1, 0.1, 0.1), 0.3)
	var art_color2: Color = champ_colors["secondary"].lerp(Color(0.1, 0.1, 0.1), 0.3)
	if not is_playable:
		art_color1 = art_color1.lerp(Color(0.2, 0.2, 0.2), 0.6)
		art_color2 = art_color2.lerp(Color(0.25, 0.25, 0.25), 0.6)

	draw_rect(art_rect, art_color1)

	# Champion symbol in center of art area
	var symbol := VisualTheme.get_champion_symbol(champion)
	var symbol_pos := Vector2(w / 2 - 8, art_top + art_height / 2 + 10)
	var symbol_color: Color = champ_colors["secondary"] if is_playable else Color(0.4, 0.4, 0.4)
	draw_string(font, symbol_pos, symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, 28, symbol_color)

	# Art area border
	draw_rect(art_rect, border_color, false, 1.0)

	# === NAME SECTION ===
	var name_top := art_top + art_height + 2
	var name_height := 20.0
	var name_rect := Rect2(4, name_top, w - 8, name_height)
	draw_rect(name_rect, secondary_color.lerp(Color.BLACK, 0.3))

	var card_name_text: String = card_data.get("name", "Unknown")
	if card_name_text.length() > 14:
		card_name_text = card_name_text.substr(0, 13) + ".."
	var name_text_width := font.get_string_size(card_name_text, HORIZONTAL_ALIGNMENT_CENTER, -1, VisualTheme.FONT_CARD_NAME).x
	draw_string(font, Vector2((w - name_text_width) / 2, name_top + 14), card_name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, VisualTheme.FONT_CARD_NAME, Color.WHITE)

	# === DESCRIPTION SECTION ===
	var desc_top := name_top + name_height + 2
	var desc_rect := Rect2(4, desc_top, w - 8, h - desc_top - 4)
	draw_rect(desc_rect, primary_color.lerp(Color.BLACK, 0.15))
	draw_rect(desc_rect, border_color, false, 1.0)

	# Description text (wrapped)
	var desc: String = card_data.get("description", "")
	_draw_wrapped_text(desc, Rect2(8, desc_top + 4, w - 16, desc_rect.size.y - 8), VisualTheme.FONT_CARD_DESC)

	# === PLAYABILITY INDICATOR ===
	if is_playable and is_hovered:
		# Glow effect when playable and hovered
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 0.7, 0.15))


func _draw_mana_gem(center: Vector2, cost: int) -> void:
	"""Draw a mana cost gem."""
	var gem_color := VisualTheme.get_mana_cost_color(cost)
	var dark_color := gem_color.lerp(Color.BLACK, 0.4)

	# Outer circle (border)
	draw_circle(center, 10, dark_color)
	# Inner circle (gem)
	draw_circle(center, 8, gem_color)
	# Highlight
	draw_arc(center + Vector2(-2, -2), 5, deg_to_rad(200), deg_to_rad(340), 8, gem_color.lerp(Color.WHITE, 0.5), 1.5)

	# Cost number
	var font := ThemeDB.fallback_font
	var cost_str := str(cost)
	draw_string(font, center + Vector2(-4, 5), cost_str, HORIZONTAL_ALIGNMENT_CENTER, -1, VisualTheme.FONT_CARD_COST, Color.WHITE)


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
	var text_color := Color(0.85, 0.85, 0.85) if is_playable else Color(0.5, 0.5, 0.5)

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
