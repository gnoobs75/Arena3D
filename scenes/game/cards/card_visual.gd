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
var is_selected: bool = false  # For multi-select mode
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


func set_selected(selected: bool) -> void:
	"""Set selection state for multi-select mode."""
	is_selected = selected
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
	var font := ThemeDB.fallback_font

	# === DROP SHADOW ===
	var shadow_offset := VisualTheme.SHADOW_OFFSET_MEDIUM
	draw_rect(Rect2(shadow_offset.x, shadow_offset.y, w, h), VisualTheme.SHADOW_COLOR)

	# Outer border
	draw_rect(Rect2(0, 0, w, h), VisualTheme.CARD_BACK["border"])

	# Background gradient
	var bg_rect := Rect2(2, 2, w - 4, h - 4)
	var bg_top := VisualTheme.CARD_BACK["secondary"]
	var bg_bottom := VisualTheme.CARD_BACK["primary"]
	VisualTheme.draw_vertical_gradient(self, bg_rect, bg_top, bg_bottom)

	# Inner decorative border with bevel
	var inner_rect := Rect2(8, 8, w - 16, h - 16)
	draw_rect(inner_rect, VisualTheme.CARD_BACK["secondary"].lerp(Color.BLACK, 0.3), false, 2.0)
	VisualTheme.draw_bevel(self, inner_rect, 1.0, Color(1, 1, 1, 0.15), Color(0, 0, 0, 0.2))

	# Diamond pattern in center
	var center := Vector2(w / 2, h / 2)
	var diamond_size := 30.0
	var diamond_points := PackedVector2Array([
		center + Vector2(0, -diamond_size),
		center + Vector2(diamond_size, 0),
		center + Vector2(0, diamond_size),
		center + Vector2(-diamond_size, 0)
	])

	# Diamond shadow
	var shadow_diamond := PackedVector2Array()
	for p in diamond_points:
		shadow_diamond.append(p + Vector2(2, 2))
	draw_colored_polygon(shadow_diamond, Color(0, 0, 0, 0.3))

	# Main diamond with gradient effect
	draw_colored_polygon(diamond_points, VisualTheme.CARD_BACK["accent"])
	draw_polyline(diamond_points + PackedVector2Array([diamond_points[0]]), VisualTheme.CARD_BACK["border"], 2.0)

	# Diamond highlight (top edge)
	draw_line(diamond_points[3], diamond_points[0], Color(1, 1, 1, 0.3), 1.5)
	draw_line(diamond_points[0], diamond_points[1], Color(1, 1, 1, 0.2), 1.5)

	# Inner diamond
	diamond_size = 18.0
	diamond_points = PackedVector2Array([
		center + Vector2(0, -diamond_size),
		center + Vector2(diamond_size, 0),
		center + Vector2(0, diamond_size),
		center + Vector2(-diamond_size, 0)
	])
	draw_colored_polygon(diamond_points, VisualTheme.CARD_BACK["secondary"])
	# Inner diamond highlight
	draw_line(diamond_points[3], diamond_points[0], Color(1, 1, 1, 0.2), 1.0)

	# "ARENA" text with shadow
	var text := "ARENA"
	var text_pos := Vector2(w / 2 - 18, h - 18)
	VisualTheme.draw_text_shadow(self, font, text_pos, text, 11, VisualTheme.CARD_BACK["accent"])

	# Corner decorations
	_draw_corner_flourish(Vector2(14, 14), 1)
	_draw_corner_flourish(Vector2(w - 14, 14), 2)
	_draw_corner_flourish(Vector2(14, h - 14), 3)
	_draw_corner_flourish(Vector2(w - 14, h - 14), 4)


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

	# === LAYER 1: DROP SHADOW ===
	var shadow_offset := VisualTheme.SHADOW_OFFSET_MEDIUM
	var shadow_color := VisualTheme.SHADOW_HARD if is_playable else VisualTheme.SHADOW_SOFT
	draw_rect(Rect2(shadow_offset.x, shadow_offset.y, w, h), shadow_color)

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

		# === VIGNETTE GRADIENT (darken bottom for text readability) ===
		var vignette_rect := Rect2(art_rect.position.x, art_rect.position.y + art_rect.size.y * 0.5, art_rect.size.x, art_rect.size.y * 0.5)
		VisualTheme.draw_vertical_gradient(self, vignette_rect, Color(0, 0, 0, 0), Color(0, 0, 0, 0.5))
	else:
		# Fallback: gradient color background
		var champ_colors := VisualTheme.get_champion_colors(champion)
		var bg_top: Color = champ_colors["secondary"].lerp(Color(0.1, 0.1, 0.1), 0.4)
		var bg_bottom: Color = champ_colors["primary"].lerp(Color(0.1, 0.1, 0.1), 0.6)
		if not is_playable:
			bg_top = bg_top.lerp(Color(0.2, 0.2, 0.2), 0.6)
			bg_bottom = bg_bottom.lerp(Color(0.2, 0.2, 0.2), 0.6)
		VisualTheme.draw_vertical_gradient(self, art_rect, bg_top, bg_bottom)

	# === COST OVERLAY (Top Right) ===
	var cost_size := 30.0  # Slightly larger
	var cost_margin := 6.0
	var cost_center := Vector2(w - cost_size / 2 - cost_margin, cost_margin + cost_size / 2)

	# Cost shadow
	draw_circle(cost_center + VisualTheme.SHADOW_OFFSET_SMALL, cost_size / 2, VisualTheme.SHADOW_COLOR)

	# Cost circle with gradient effect (draw concentric circles)
	var cost_bg_outer := OVERLAY_BG.lerp(Color.BLACK, 0.1) if is_playable else Color(0.12, 0.12, 0.15, 0.9)
	var cost_bg_inner := OVERLAY_BG.lerp(Color.WHITE, 0.05) if is_playable else Color(0.18, 0.18, 0.2, 0.9)
	draw_circle(cost_center, cost_size / 2, cost_bg_outer)
	draw_circle(cost_center, cost_size / 2 - 3, cost_bg_inner)

	# Cost border with highlight
	draw_arc(cost_center, cost_size / 2, 0, TAU, 32, OVERLAY_BORDER, 2.0)
	draw_arc(cost_center, cost_size / 2 - 1, PI * 1.25, PI * 1.75, 16, VisualTheme.BEVEL_HIGHLIGHT, 1.0)  # Top highlight

	# Cost number with shadow
	var cost_str := str(cost)
	var cost_text_pos := cost_center + Vector2(-4, 6)
	var cost_color := Color(1.0, 0.9, 0.5) if is_playable else Color(0.5, 0.5, 0.5)
	VisualTheme.draw_text_shadow(self, font, cost_text_pos, cost_str, VisualTheme.FONT_CARD_COST, cost_color)

	# === NAME OVERLAY (Top Middle) ===
	var name_margin := VisualTheme.PADDING_CARD
	var name_height := 24.0
	var name_width := w - cost_size - cost_margin * 2 - name_margin * 2
	var name_rect := Rect2(name_margin, name_margin, name_width, name_height)

	# Name shadow
	draw_rect(Rect2(name_rect.position + VisualTheme.SHADOW_OFFSET_SMALL, name_rect.size), VisualTheme.SHADOW_SOFT)

	# Name background gradient
	var name_bg_top := OVERLAY_BG.lerp(Color.WHITE, 0.08)
	var name_bg_bottom := OVERLAY_BG
	VisualTheme.draw_vertical_gradient(self, name_rect, name_bg_top, name_bg_bottom)

	# Name border with bevel
	draw_rect(name_rect, OVERLAY_BORDER, false, 1.0)
	VisualTheme.draw_bevel(self, name_rect)

	# Card name text with shadow
	var card_name_text: String = card_data.get("name", "Unknown")
	if card_name_text.length() > 14:
		card_name_text = card_name_text.substr(0, 13) + ".."
	var name_color := Color.WHITE if is_playable else Color(0.6, 0.6, 0.6)
	var name_text_pos := Vector2(name_margin + 5, name_margin + 17)
	VisualTheme.draw_text_shadow(self, font, name_text_pos, card_name_text, VisualTheme.FONT_CARD_NAME, name_color)

	# === TYPE INDICATOR (small badge next to name) ===
	var type_short := card_type.substr(0, 1)  # A, R, or E
	var type_badge_pos := Vector2(name_rect.end.x - 14, name_margin + 17)
	var type_color: Color
	match card_type:
		"Action":
			type_color = Color(0.4, 0.7, 1.0) if is_playable else Color(0.3, 0.3, 0.4)
		"Response":
			type_color = Color(1.0, 0.7, 0.3) if is_playable else Color(0.4, 0.3, 0.3)
		"Equipment":
			type_color = Color(0.5, 1.0, 0.4) if is_playable else Color(0.3, 0.4, 0.3)
		_:
			type_color = Color(0.6, 0.6, 0.6)
	VisualTheme.draw_text_shadow(self, font, type_badge_pos, type_short, VisualTheme.FONT_CARD_TYPE, type_color)

	# === DESCRIPTION OVERLAY (Bottom) ===
	var desc_margin := VisualTheme.PADDING_CARD
	var desc_height := 72.0
	var desc_rect := Rect2(desc_margin, h - desc_height - desc_margin, w - desc_margin * 2, desc_height)

	# Description shadow
	draw_rect(Rect2(desc_rect.position + VisualTheme.SHADOW_OFFSET_SMALL, desc_rect.size), VisualTheme.SHADOW_SOFT)

	# Description background gradient (inverted - darker at bottom)
	var desc_bg_top := OVERLAY_BG
	var desc_bg_bottom := OVERLAY_BG.lerp(Color.BLACK, 0.15)
	VisualTheme.draw_vertical_gradient(self, desc_rect, desc_bg_top, desc_bg_bottom)

	# Description border with inset effect
	draw_rect(desc_rect, OVERLAY_BORDER, false, 1.0)
	VisualTheme.draw_inset(self, desc_rect)

	# Description text (wrapped)
	var desc: String = card_data.get("description", "")
	var desc_text_rect := Rect2(desc_rect.position.x + 5, desc_rect.position.y + 3, desc_rect.size.x - 10, desc_rect.size.y - 6)
	_draw_wrapped_text(desc, desc_text_rect, VisualTheme.FONT_CARD_DESC)

	# === SELECTION INDICATOR (for multi-select mode) ===
	if is_selected:
		# Strong green glow for selected cards
		draw_rect(Rect2(0, 0, w, h), Color(0.2, 0.8, 0.3, 0.3))
		draw_rect(Rect2(0, 0, w, h), Color(0.3, 1.0, 0.4, 1.0), false, 3.0)
		# Checkmark indicator with shadow
		var check_pos := Vector2(w - 20, h - 25)
		VisualTheme.draw_text_shadow(self, font, check_pos, "✓", 18, Color(0.3, 1.0, 0.4))

	# === PLAYABILITY / HOVER INDICATOR ===
	if is_playable and is_hovered and not is_selected:
		# Outer glow effect when playable and hovered
		for i in range(3, 0, -1):
			var glow_alpha := 0.15 * (1.0 - float(i) / 3.0)
			draw_rect(Rect2(-i, -i, w + i * 2, h + i * 2), Color(1.0, 0.95, 0.6, glow_alpha), false, 2.0)
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 0.7, 0.15))
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 0.5, 0.9), false, 2.0)


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
			# Allow clicks when playable OR when selected (for deselecting)
			if is_playable or is_selected:
				card_clicked.emit(card_name)
