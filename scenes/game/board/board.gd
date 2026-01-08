extends Node2D
class_name GameBoard
## GameBoard - Enhanced 2D grid board for the Arena game
## Features polished tiles, coordinate labels, and styled champion tokens

signal tile_clicked(position: Vector2i)
signal tile_hovered(position: Vector2i)
signal tile_unhovered(position: Vector2i)
signal champion_clicked(champion_id: String)

const BOARD_SIZE := 10
const TILE_SIZE := 64  # Pixels per tile
const COORD_MARGIN := 24  # Space for coordinate labels

# Node references - fetched in _ready() for safety
var tiles_container: Node2D
var highlights_container: Node2D
var champions_container: Node2D
var coords_container: Node2D
var board_frame: Control
var _is_ready: bool = false

# State
var game_state: GameState
var tile_nodes: Array = []  # 2D array of tile Controls
var highlight_nodes: Array = []  # 2D array of highlight Controls
var champion_nodes: Dictionary = {}  # champion_id -> ChampionToken
var hovered_tile: Vector2i = Vector2i(-1, -1)
var selected_champion: String = ""

# Highlight sets
var move_highlights: Array[Vector2i] = []
var attack_highlights: Array[Vector2i] = []
var cast_highlights: Array[Vector2i] = []


func _ready() -> void:
	# Get node references safely
	tiles_container = get_node_or_null("Tiles")
	highlights_container = get_node_or_null("Highlights")
	champions_container = get_node_or_null("Champions")
	coords_container = get_node_or_null("Coords")
	board_frame = get_node_or_null("BoardFrame")

	if tiles_container == null:
		tiles_container = Node2D.new()
		tiles_container.name = "Tiles"
		add_child(tiles_container)

	if highlights_container == null:
		highlights_container = Node2D.new()
		highlights_container.name = "Highlights"
		add_child(highlights_container)

	if champions_container == null:
		champions_container = Node2D.new()
		champions_container.name = "Champions"
		add_child(champions_container)

	if coords_container == null:
		coords_container = Node2D.new()
		coords_container.name = "Coords"
		add_child(coords_container)

	_is_ready = true
	_create_board()
	_create_coordinate_labels()


func _create_board() -> void:
	"""Create the visual board grid with polished tiles."""
	tile_nodes = []
	highlight_nodes = []

	# Position board with margin for coordinates
	tiles_container.position = Vector2(COORD_MARGIN, COORD_MARGIN)
	highlights_container.position = Vector2(COORD_MARGIN, COORD_MARGIN)
	champions_container.position = Vector2(COORD_MARGIN, COORD_MARGIN)

	for y in range(BOARD_SIZE):
		var tile_row: Array = []
		var highlight_row: Array = []

		for x in range(BOARD_SIZE):
			# Create tile
			var tile := _create_tile(x, y)
			tiles_container.add_child(tile)
			tile_row.append(tile)

			# Create highlight overlay
			var highlight := _create_highlight(x, y)
			highlights_container.add_child(highlight)
			highlight_row.append(highlight)

		tile_nodes.append(tile_row)
		highlight_nodes.append(highlight_row)


func _create_tile(x: int, y: int) -> Control:
	"""Create a single polished tile visual."""
	var tile := Control.new()
	tile.size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.position = Vector2(x * TILE_SIZE, y * TILE_SIZE)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Custom drawing for tile
	var drawer := TileDrawer.new()
	drawer.tile_x = x
	drawer.tile_y = y
	drawer.size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.add_child(drawer)

	return tile


func _create_highlight(x: int, y: int) -> Control:
	"""Create a highlight overlay for a tile."""
	var highlight := Control.new()
	highlight.size = Vector2(TILE_SIZE, TILE_SIZE)
	highlight.position = Vector2(x * TILE_SIZE, y * TILE_SIZE)
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var drawer := HighlightDrawer.new()
	drawer.size = Vector2(TILE_SIZE, TILE_SIZE)
	highlight.add_child(drawer)

	return highlight


func _create_coordinate_labels() -> void:
	"""Create coordinate labels around the board."""
	coords_container.position = Vector2.ZERO

	var font := ThemeDB.fallback_font

	# Column labels (A-J at top)
	for x in range(BOARD_SIZE):
		var label := Label.new()
		label.text = char(65 + x)  # A, B, C...
		label.position = Vector2(COORD_MARGIN + x * TILE_SIZE + TILE_SIZE / 2 - 5, 4)
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", VisualTheme.UI_TEXT_DIM)
		coords_container.add_child(label)

	# Row labels (1-10 on left)
	for y in range(BOARD_SIZE):
		var label := Label.new()
		label.text = str(y + 1)
		label.position = Vector2(4, COORD_MARGIN + y * TILE_SIZE + TILE_SIZE / 2 - 8)
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", VisualTheme.UI_TEXT_DIM)
		coords_container.add_child(label)


func initialize(state: GameState) -> void:
	"""Initialize board with game state."""
	game_state = state
	if not _is_ready:
		push_warning("Board: initialize() called before _ready()")
		return
	update_terrain()
	_create_champions()


func update_terrain() -> void:
	"""Update tile visuals based on terrain."""
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var terrain := game_state.get_terrain(Vector2i(x, y))
			var tile: Control = tile_nodes[y][x]
			var drawer: TileDrawer = tile.get_child(0) as TileDrawer
			if drawer:
				drawer.terrain_type = terrain
				drawer.queue_redraw()


func _create_champions() -> void:
	"""Create champion tokens for all champions."""
	for champ: ChampionState in game_state.get_all_champions():
		var token := _create_champion_token(champ)
		champions_container.add_child(token)
		champion_nodes[champ.unique_id] = token


func _create_champion_token(champ: ChampionState) -> Control:
	"""Create a styled champion token."""
	var token := ChampionToken.new()
	token.setup(champ)
	token.position = _grid_to_world(champ.position) - Vector2(VisualTheme.CHAMPION_TOKEN_SIZE / 2, VisualTheme.CHAMPION_TOKEN_SIZE / 2)
	return token


func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""Convert grid position to world position (center of tile)."""
	return Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE / 2,
		grid_pos.y * TILE_SIZE + TILE_SIZE / 2
	)


func _world_to_grid(world_pos: Vector2) -> Vector2i:
	"""Convert world position to grid position."""
	var adjusted := world_pos - Vector2(COORD_MARGIN, COORD_MARGIN)
	return Vector2i(
		int(adjusted.x / TILE_SIZE),
		int(adjusted.y / TILE_SIZE)
	)


# === Input Handling ===

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_mouse_move(event.position)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)


func _handle_mouse_move(mouse_pos: Vector2) -> void:
	var local_pos := get_local_mouse_position()
	var grid_pos := _world_to_grid(local_pos)

	if _is_valid_position(grid_pos):
		if grid_pos != hovered_tile:
			if hovered_tile != Vector2i(-1, -1):
				tile_unhovered.emit(hovered_tile)
				_set_tile_hover(hovered_tile, false)

			hovered_tile = grid_pos
			_set_tile_hover(grid_pos, true)
			tile_hovered.emit(grid_pos)
	else:
		if hovered_tile != Vector2i(-1, -1):
			tile_unhovered.emit(hovered_tile)
			_set_tile_hover(hovered_tile, false)
			hovered_tile = Vector2i(-1, -1)


func _handle_click(mouse_pos: Vector2) -> void:
	var local_pos := get_local_mouse_position()
	var grid_pos := _world_to_grid(local_pos)

	if not _is_valid_position(grid_pos):
		return

	# Check if clicking on a champion
	var champ := game_state.get_champion_at(grid_pos)
	if champ:
		champion_clicked.emit(champ.unique_id)
	else:
		tile_clicked.emit(grid_pos)


func _is_valid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_SIZE and pos.y >= 0 and pos.y < BOARD_SIZE


func _set_tile_hover(pos: Vector2i, hovered: bool) -> void:
	"""Set hover state on a tile."""
	if not _is_valid_position(pos):
		return
	var highlight: Control = highlight_nodes[pos.y][pos.x]
	var drawer: HighlightDrawer = highlight.get_child(0) as HighlightDrawer
	if drawer:
		drawer.is_hovered = hovered
		drawer.queue_redraw()


# === Highlighting ===

func show_move_highlights(positions: Array[Vector2i]) -> void:
	"""Show valid move destinations."""
	move_highlights = positions
	_apply_highlights()


func show_attack_highlights(positions: Array[Vector2i]) -> void:
	"""Show valid attack targets."""
	attack_highlights = positions
	_apply_highlights()


func show_cast_highlights(positions: Array[Vector2i]) -> void:
	"""Show valid cast targets."""
	cast_highlights = positions
	_apply_highlights()


func select_champion(champion_id: String) -> void:
	"""Highlight selected champion's tile."""
	selected_champion = champion_id
	_apply_highlights()

	# Update champion token selection state
	for id in champion_nodes:
		var token: ChampionToken = champion_nodes[id]
		token.set_selected(id == champion_id)


func clear_highlights() -> void:
	"""Clear all highlights."""
	move_highlights.clear()
	attack_highlights.clear()
	cast_highlights.clear()
	selected_champion = ""
	_apply_highlights()

	# Clear champion selection
	for id in champion_nodes:
		var token: ChampionToken = champion_nodes[id]
		token.set_selected(false)


func _apply_highlights() -> void:
	"""Apply all current highlights."""
	# Clear all
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var highlight: Control = highlight_nodes[y][x]
			var drawer: HighlightDrawer = highlight.get_child(0) as HighlightDrawer
			if drawer:
				drawer.highlight_type = HighlightDrawer.HighlightType.NONE
				drawer.queue_redraw()

	# Selected champion
	if not selected_champion.is_empty():
		var champ := game_state.get_champion(selected_champion)
		if champ:
			var pos: Vector2i = champ.position
			_set_highlight(pos, HighlightDrawer.HighlightType.SELECTED)

	# Move highlights
	for pos: Vector2i in move_highlights:
		_set_highlight(pos, HighlightDrawer.HighlightType.MOVE)

	# Attack highlights
	for pos: Vector2i in attack_highlights:
		_set_highlight(pos, HighlightDrawer.HighlightType.ATTACK)

	# Cast highlights
	for pos: Vector2i in cast_highlights:
		_set_highlight(pos, HighlightDrawer.HighlightType.CAST)


func _set_highlight(pos: Vector2i, type: int) -> void:
	"""Set highlight type on a tile."""
	if not _is_valid_position(pos):
		return
	var highlight: Control = highlight_nodes[pos.y][pos.x]
	var drawer: HighlightDrawer = highlight.get_child(0) as HighlightDrawer
	if drawer:
		drawer.highlight_type = type
		drawer.queue_redraw()


# === Updates ===

func update_champion_positions() -> void:
	"""Update all champion positions on board."""
	for champ: ChampionState in game_state.get_all_champions():
		if champion_nodes.has(champ.unique_id):
			var token: ChampionToken = champion_nodes[champ.unique_id]
			if champ.is_alive() and champ.is_on_board:
				token.visible = true
				token.position = _grid_to_world(champ.position) - Vector2(VisualTheme.CHAMPION_TOKEN_SIZE / 2, VisualTheme.CHAMPION_TOKEN_SIZE / 2)
			else:
				token.visible = false


func update_champion_hp() -> void:
	"""Update HP displays for all champions."""
	for champ: ChampionState in game_state.get_all_champions():
		if champion_nodes.has(champ.unique_id):
			var token: ChampionToken = champion_nodes[champ.unique_id]
			token.update_hp(champ.current_hp, champ.max_hp)


func animate_move(champion_id: String, path: Array[Vector2i], duration: float = 0.3) -> void:
	"""Animate champion movement along path."""
	if not champion_nodes.has(champion_id):
		return

	var token: ChampionToken = champion_nodes[champion_id]
	var tween := create_tween()

	for pos: Vector2i in path:
		var world_pos := _grid_to_world(pos) - Vector2(VisualTheme.CHAMPION_TOKEN_SIZE / 2, VisualTheme.CHAMPION_TOKEN_SIZE / 2)
		tween.tween_property(token, "position", world_pos, duration / path.size())


func animate_attack(attacker_id: String, target_id: String) -> void:
	"""Animate attack between champions."""
	if not champion_nodes.has(attacker_id) or not champion_nodes.has(target_id):
		return

	var attacker: ChampionToken = champion_nodes[attacker_id]
	var target: ChampionToken = champion_nodes[target_id]

	var original_pos: Vector2 = attacker.position
	var target_pos: Vector2 = target.position
	var lunge_pos: Vector2 = original_pos.lerp(target_pos, 0.3)

	var tween := create_tween()
	tween.tween_property(attacker, "position", lunge_pos, 0.1)
	tween.tween_property(attacker, "position", original_pos, 0.1)

	# Flash target
	tween.parallel().tween_property(target, "modulate", Color.RED, 0.1)
	tween.tween_property(target, "modulate", Color.WHITE, 0.1)


func get_board_size_pixels() -> Vector2:
	"""Get total board size in pixels including margins."""
	return Vector2(BOARD_SIZE * TILE_SIZE + COORD_MARGIN * 2, BOARD_SIZE * TILE_SIZE + COORD_MARGIN * 2)


# === Inner Classes ===

class TileDrawer extends Control:
	"""Custom drawing for a single tile."""
	var tile_x: int = 0
	var tile_y: int = 0
	var terrain_type: int = 0  # GameState.Terrain enum value

	func _draw() -> void:
		var w := size.x
		var h := size.y

		# Checkerboard pattern for empty tiles
		var is_alt := (tile_x + tile_y) % 2 == 1

		# Base tile color
		var base_color: Color
		var border_color := VisualTheme.TILE_BORDER

		match terrain_type:
			1:  # WALL
				base_color = VisualTheme.TILE_WALL
				# Draw brick pattern
				draw_rect(Rect2(1, 1, w - 2, h - 2), base_color)
				_draw_brick_pattern()
			2:  # PIT
				base_color = VisualTheme.TILE_PIT
				draw_rect(Rect2(1, 1, w - 2, h - 2), base_color)
				# Draw pit edge glow
				draw_rect(Rect2(4, 4, w - 8, h - 8), VisualTheme.TILE_PIT_EDGE, false, 2.0)
			_:  # EMPTY
				base_color = VisualTheme.TILE_EMPTY_ALT if is_alt else VisualTheme.TILE_EMPTY
				draw_rect(Rect2(1, 1, w - 2, h - 2), base_color)

		# Grid border
		draw_rect(Rect2(0, 0, w, h), border_color, false, 1.0)

	func _draw_brick_pattern() -> void:
		"""Draw a subtle brick pattern on wall tiles."""
		var brick_color := VisualTheme.TILE_WALL_ACCENT
		var w := size.x
		var h := size.y

		# Horizontal lines
		for y_off in [16, 32, 48]:
			draw_line(Vector2(2, y_off), Vector2(w - 2, y_off), brick_color, 1.0)

		# Vertical lines (offset every other row)
		for row in range(4):
			var y_start := row * 16
			var x_offset := 0 if row % 2 == 0 else 16
			for x in range(0, int(w), 32):
				var x_pos := x + x_offset
				if x_pos > 2 and x_pos < w - 2:
					draw_line(Vector2(x_pos, y_start + 1), Vector2(x_pos, y_start + 15), brick_color, 1.0)


class HighlightDrawer extends Control:
	"""Custom drawing for tile highlights."""
	enum HighlightType { NONE, MOVE, ATTACK, CAST, SELECTED }

	var highlight_type: int = HighlightType.NONE
	var is_hovered: bool = false

	func _draw() -> void:
		var w := size.x
		var h := size.y

		# Hover effect (if no other highlight)
		if is_hovered and highlight_type == HighlightType.NONE:
			draw_rect(Rect2(0, 0, w, h), VisualTheme.HIGHLIGHT_HOVER)
			return

		if highlight_type == HighlightType.NONE:
			return

		var fill_color: Color
		var border_color: Color

		match highlight_type:
			HighlightType.MOVE:
				fill_color = VisualTheme.HIGHLIGHT_MOVE
				border_color = VisualTheme.HIGHLIGHT_MOVE_BORDER
			HighlightType.ATTACK:
				fill_color = VisualTheme.HIGHLIGHT_ATTACK
				border_color = VisualTheme.HIGHLIGHT_ATTACK_BORDER
			HighlightType.CAST:
				fill_color = VisualTheme.HIGHLIGHT_CAST
				border_color = VisualTheme.HIGHLIGHT_CAST_BORDER
			HighlightType.SELECTED:
				fill_color = VisualTheme.HIGHLIGHT_SELECTED
				border_color = VisualTheme.HIGHLIGHT_SELECTED_BORDER

		# Fill
		draw_rect(Rect2(2, 2, w - 4, h - 4), fill_color)

		# Border
		draw_rect(Rect2(2, 2, w - 4, h - 4), border_color, false, 2.0)

		# Extra hover brightness
		if is_hovered:
			draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.1))


class ChampionToken extends Control:
	"""Styled champion token with HP bar."""
	var champion_state: ChampionState
	var current_hp: int = 20
	var max_hp: int = 20
	var is_selected: bool = false
	var owner_id: int = 1
	var champion_name: String = ""

	func _init() -> void:
		size = Vector2(VisualTheme.CHAMPION_TOKEN_SIZE, VisualTheme.CHAMPION_TOKEN_SIZE)
		custom_minimum_size = size

	func setup(champ: ChampionState) -> void:
		champion_state = champ
		current_hp = champ.current_hp
		max_hp = champ.max_hp
		owner_id = champ.owner_id
		champion_name = champ.champion_name
		queue_redraw()

	func update_hp(hp: int, max_val: int) -> void:
		current_hp = hp
		max_hp = max_val
		queue_redraw()

	func set_selected(selected: bool) -> void:
		is_selected = selected
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var center := Vector2(w / 2, h / 2 - 4)
		var radius := w / 2 - 4

		# Team color
		var team_color := VisualTheme.get_player_color(owner_id)
		var dark_color := VisualTheme.get_player_dark_color(owner_id)

		# Selection glow
		if is_selected:
			draw_circle(center, radius + 4, VisualTheme.HIGHLIGHT_SELECTED_BORDER)

		# Outer ring (dark)
		draw_circle(center, radius, dark_color)

		# Inner circle (team color)
		draw_circle(center, radius - 3, team_color)

		# Champion initials
		var font := ThemeDB.fallback_font
		var initials := champion_name.substr(0, 2).to_upper()
		var text_size := font.get_string_size(initials, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_string(font, center - Vector2(text_size.x / 2, -5), initials, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)

		# HP Bar
		var bar_y := h - 10
		var bar_height := 6
		var bar_width := w - 8

		# Bar background
		draw_rect(Rect2(4, bar_y, bar_width, bar_height), VisualTheme.HP_BAR_BG)

		# HP fill
		var hp_pct := float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
		var hp_color := VisualTheme.get_hp_color(current_hp, max_hp)
		draw_rect(Rect2(4, bar_y, bar_width * hp_pct, bar_height), hp_color)

		# Bar border
		draw_rect(Rect2(4, bar_y, bar_width, bar_height), VisualTheme.HP_BAR_BORDER, false, 1.0)

		# HP text
		var hp_text := str(current_hp)
		draw_string(font, Vector2(w / 2 - 4, bar_y + 5), hp_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
