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
var vfx_below: BoardVFXLayer  # Particles rendered below champions
var vfx_above: BoardVFXLayer  # Particles rendered above champions
var crowd_layer: Node2D = null  # Arena crowd around the board
var _is_ready: bool = false

# State
var game_state: GameState
var tile_nodes: Array = []  # 2D array of tile Controls
var highlight_nodes: Array = []  # 2D array of highlight Controls
var champion_nodes: Dictionary = {}  # champion_id -> ChampionVisual
var hovered_tile: Vector2i = Vector2i(-1, -1)
var selected_champion: String = ""

# Highlight sets
var move_highlights: Array[Vector2i] = []
var attack_highlights: Array[Vector2i] = []
var cast_highlights: Array[Vector2i] = []
var range_highlights: Array[Vector2i] = []  # Yellow range indicator


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

	# VFX below champions
	vfx_below = BoardVFXLayer.new()
	vfx_below.name = "VFXBelow"
	add_child(vfx_below)

	if champions_container == null:
		champions_container = Node2D.new()
		champions_container.name = "Champions"
		add_child(champions_container)

	# VFX above champions
	vfx_above = BoardVFXLayer.new()
	vfx_above.name = "VFXAbove"
	add_child(vfx_above)

	if coords_container == null:
		coords_container = Node2D.new()
		coords_container.name = "Coords"
		add_child(coords_container)

	_is_ready = true
	_create_board()
	_create_coordinate_labels()
	_create_board_frame()
	_create_crowd_layer()


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


func _create_board_frame() -> void:
	"""Create ornamental board frame using the COORD_MARGIN area."""
	var frame := BoardFrameDrawer.new()
	frame.board_size_px = BOARD_SIZE * TILE_SIZE
	frame.margin = COORD_MARGIN
	frame.size = Vector2(BOARD_SIZE * TILE_SIZE + COORD_MARGIN * 2, BOARD_SIZE * TILE_SIZE + COORD_MARGIN * 2)
	# Insert behind tiles but ensure it renders
	add_child(frame)
	move_child(frame, 0)


func _create_crowd_layer() -> void:
	"""Create spectator crowd around the arena board."""
	var crowd_script := load("res://scenes/game/board/arena_crowd_layer.gd")
	if crowd_script:
		crowd_layer = crowd_script.new()
		crowd_layer.name = "ArenaCrowd"
		crowd_layer.z_index = -1  # Behind everything
		add_child(crowd_layer)
		move_child(crowd_layer, 0)  # First child = drawn first
		crowd_layer.setup(BOARD_SIZE * TILE_SIZE, COORD_MARGIN)


func initialize(state: GameState) -> void:
	"""Initialize board with game state."""
	game_state = state
	if not _is_ready:
		push_warning("Board: initialize() called before _ready()")
		return
	update_terrain()
	_create_champions()
	_setup_vfx_layers()


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


func _setup_vfx_layers() -> void:
	"""Initialize VFX layers with pit tile positions."""
	var pits: Array[Vector2i] = []
	if game_state:
		for y in range(BOARD_SIZE):
			for x in range(BOARD_SIZE):
				if game_state.get_terrain(Vector2i(x, y)) == 2:  # PIT
					pits.append(Vector2i(x, y))
	# Position VFX at same offset as tiles
	vfx_below.position = Vector2(COORD_MARGIN, COORD_MARGIN)
	vfx_above.position = Vector2(COORD_MARGIN, COORD_MARGIN)
	vfx_below.setup(TILE_SIZE, pits)
	vfx_above.setup(TILE_SIZE, pits)


func trigger_dust(grid_pos: Vector2i) -> void:
	"""Trigger dust VFX at a grid position (below champions)."""
	vfx_below.spawn_dust_trail(_grid_to_world(grid_pos))


func trigger_melee_impact(grid_pos: Vector2i) -> void:
	"""Trigger melee impact sparks (above champions)."""
	vfx_above.spawn_melee_impact(_grid_to_world(grid_pos))


func trigger_ranged_trail(from_grid: Vector2i, to_grid: Vector2i) -> void:
	"""Trigger ranged projectile trail (above champions)."""
	vfx_above.spawn_ranged_trail(_grid_to_world(from_grid), _grid_to_world(to_grid))


func trigger_magic_swirl(grid_pos: Vector2i, color: Color = VisualTheme.VFX_MAGIC) -> void:
	"""Trigger magic swirl at target (above champions)."""
	vfx_above.spawn_magic_swirl(_grid_to_world(grid_pos), color)


func trigger_cast_shimmer(grid_pos: Vector2i) -> void:
	"""Trigger cast sparkles rising from caster (above champions)."""
	vfx_above.spawn_cast_shimmer(_grid_to_world(grid_pos))


func trigger_death_vfx(grid_pos: Vector2i) -> void:
	"""Trigger death effects (above champions)."""
	vfx_above.spawn_death_vfx(_grid_to_world(grid_pos))


func trigger_heal_sparkles(grid_pos: Vector2i) -> void:
	"""Trigger heal sparkles (above champions)."""
	vfx_above.spawn_heal_sparkles(_grid_to_world(grid_pos))


func trigger_energy_beam(from_grid: Vector2i, to_grid: Vector2i, color: Color) -> void:
	"""Trigger energy beam arc from caster to target (Action cards)."""
	vfx_above.spawn_energy_beam(_grid_to_world(from_grid), _grid_to_world(to_grid), color)


func trigger_cast_burst(grid_pos: Vector2i, color: Color) -> void:
	"""Trigger radial particle burst (Action cards)."""
	vfx_above.spawn_cast_burst(_grid_to_world(grid_pos), color)


func trigger_shield_flash(grid_pos: Vector2i) -> void:
	"""Trigger expanding shield ring (Response cards)."""
	vfx_above.spawn_shield_flash(_grid_to_world(grid_pos))


func trigger_equip_glow(grid_pos: Vector2i) -> void:
	"""Trigger metallic sparkle attach (Equipment cards)."""
	vfx_above.spawn_equip_glow(_grid_to_world(grid_pos))


func trigger_smoke_poof(grid_pos: Vector2i) -> void:
	"""Trigger smoke bomb cloud effect at champion position."""
	vfx_above.spawn_smoke_poof(_grid_to_world(grid_pos))


func _create_champions() -> void:
	"""Create champion tokens for all champions."""
	for champ: ChampionState in game_state.get_all_champions():
		var token := _create_champion_token(champ)
		champions_container.add_child(token)
		champion_nodes[champ.unique_id] = token


func _create_champion_token(champ: ChampionState) -> Node2D:
	"""Create a Battle Chess-style champion visual."""
	var visual := ChampionVisual.new()
	visual.setup(champ)
	# ChampionVisual is centered, so position at tile center
	visual.position = _grid_to_world(champ.position)
	return visual


func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""Convert grid position to world position (center of tile)."""
	return Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE / 2,
		grid_pos.y * TILE_SIZE + TILE_SIZE / 2
	)


func get_champion_screen_position(champion_id: String) -> Vector2:
	"""Get the global screen position of a champion for UI overlays."""
	if not champion_nodes.has(champion_id):
		return Vector2.ZERO

	var visual: ChampionVisual = champion_nodes[champion_id]
	# ChampionVisual is already centered at its position
	return visual.global_position


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


func show_range_highlights(positions: Array[Vector2i]) -> void:
	"""Show attack range area (yellow)."""
	range_highlights = positions
	_apply_highlights()


func select_champion(champion_id: String) -> void:
	"""Highlight selected champion's tile."""
	selected_champion = champion_id
	_apply_highlights()

	# Update champion visual selection state
	for id in champion_nodes:
		var visual: ChampionVisual = champion_nodes[id]
		visual.set_selected(id == champion_id)


func clear_highlights() -> void:
	"""Clear all highlights."""
	move_highlights.clear()
	attack_highlights.clear()
	cast_highlights.clear()
	range_highlights.clear()
	selected_champion = ""
	_apply_highlights()

	# Clear champion selection
	for id in champion_nodes:
		var visual: ChampionVisual = champion_nodes[id]
		visual.set_selected(false)


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

	# Range highlights first (lowest priority - underneath others)
	for pos: Vector2i in range_highlights:
		_set_highlight(pos, HighlightDrawer.HighlightType.RANGE)

	# Move highlights (override range)
	for pos: Vector2i in move_highlights:
		_set_highlight(pos, HighlightDrawer.HighlightType.MOVE)

	# Selected champion
	if not selected_champion.is_empty():
		var champ := game_state.get_champion(selected_champion)
		if champ:
			var pos: Vector2i = champ.position
			_set_highlight(pos, HighlightDrawer.HighlightType.SELECTED)

	# Attack highlights (override move)
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
			var visual: ChampionVisual = champion_nodes[champ.unique_id]
			if champ.is_alive() and champ.is_on_board:
				visual.visible = true
				# ChampionVisual is centered, so position at tile center
				visual.position = _grid_to_world(champ.position)
			else:
				visual.visible = false


func update_champion_hp() -> void:
	"""Update HP displays and status effects for all champions."""
	for champ: ChampionState in game_state.get_all_champions():
		if champion_nodes.has(champ.unique_id):
			var visual: ChampionVisual = champion_nodes[champ.unique_id]
			visual.update_hp(champ.current_hp, champ.max_hp)
			visual.update_status_effects(champ)


func animate_move(champion_id: String, path: Array[Vector2i], duration: float = 0.3) -> void:
	"""Animate champion movement along path."""
	if not champion_nodes.has(champion_id):
		return

	var visual: ChampionVisual = champion_nodes[champion_id]
	var tween := create_tween()

	# Trigger walk animation on the visual
	if path.size() > 0:
		var direction := Vector2(path[-1] - path[0])
		visual.play_walk_animation(direction)

	for pos: Vector2i in path:
		# ChampionVisual is centered, so position at tile center
		var world_pos := _grid_to_world(pos)
		tween.tween_property(visual, "position", world_pos, duration / path.size())


func animate_attack(attacker_id: String, target_id: String) -> void:
	"""Animate attack between champions."""
	if not champion_nodes.has(attacker_id) or not champion_nodes.has(target_id):
		return

	var attacker: ChampionVisual = champion_nodes[attacker_id]
	var target: ChampionVisual = champion_nodes[target_id]

	# Get direction from attacker to target
	var direction: Vector2 = target.position - attacker.position

	# Trigger attack animation on the attacker visual
	attacker.play_attack_animation(direction)

	# Trigger hit animation on the target visual
	target.play_hit_animation()


func play_board_reveal() -> void:
	"""Animate tiles appearing from center outward in a ripple."""
	var center := Vector2(BOARD_SIZE / 2.0, BOARD_SIZE / 2.0)
	var max_dist := center.length()

	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var tile: Control = tile_nodes[y][x]
			var dist := Vector2(x, y).distance_to(center)
			var delay := (dist / max_dist) * 0.4  # 0 to 0.4s based on distance from center

			tile.modulate.a = 0.0
			tile.pivot_offset = Vector2(TILE_SIZE / 2, TILE_SIZE / 2)
			tile.scale = Vector2(0.6, 0.6)
			var tween := tile.create_tween()
			tween.tween_interval(delay)
			tween.tween_property(tile, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(tile, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Champions fade in after board
	for id in champion_nodes:
		var visual: ChampionVisual = champion_nodes[id]
		visual.modulate.a = 0.0
		var tween := visual.create_tween()
		tween.tween_interval(0.5)
		tween.tween_property(visual, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)


func get_board_size_pixels() -> Vector2:
	"""Get total board size in pixels including margins."""
	return Vector2(BOARD_SIZE * TILE_SIZE + COORD_MARGIN * 2, BOARD_SIZE * TILE_SIZE + COORD_MARGIN * 2)


# === Inner Classes ===

class TileDrawer extends Control:
	"""Custom drawing for a single tile - raised stone slabs, wall blocks, pit voids."""
	var tile_x: int = 0
	var tile_y: int = 0
	var terrain_type: int = 0  # GameState.Terrain enum value

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var is_alt := (tile_x + tile_y) % 2 == 1
		var lighting := VisualTheme.get_tile_lighting(tile_x, tile_y)

		match terrain_type:
			1:  # WALL - tall stone blocks with mortar
				_draw_wall_tile(w, h, lighting)
			2:  # PIT - gaping void with crumbling rim and purple glow
				_draw_pit_tile(w, h, lighting)
			_:  # EMPTY - raised stone slab with depth
				_draw_empty_tile(w, h, is_alt, lighting)

	func _draw_empty_tile(w: float, h: float, is_alt: bool, lighting: float) -> void:
		var depth := float(VisualTheme.TILE_DEPTH_EMPTY)
		var base := VisualTheme.TILE_STONE_DARK if is_alt else VisualTheme.TILE_STONE_LIGHT
		base = VisualTheme.apply_lighting(base, lighting)

		# Ambient occlusion gap (dark border around slab)
		draw_rect(Rect2(0, 0, w, h), VisualTheme.TILE_AO_GAP)

		# Side faces (depth) - right side and bottom side
		var side_color := base.lerp(Color.BLACK, 0.35)
		# Bottom depth face
		var bottom_pts := PackedVector2Array([
			Vector2(2, h - depth), Vector2(w - 2, h - depth),
			Vector2(w - 2, h - 2), Vector2(2, h - 2)
		])
		draw_colored_polygon(bottom_pts, side_color)
		# Right depth face
		var right_pts := PackedVector2Array([
			Vector2(w - depth, 2), Vector2(w - 2, 2),
			Vector2(w - 2, h - 2), Vector2(w - depth, h - depth)
		])
		draw_colored_polygon(right_pts, side_color.lerp(Color.BLACK, 0.1))

		# Top face (main slab surface)
		var top_rect := Rect2(2, 2, w - depth - 2, h - depth - 2)
		var top_top := base.lerp(Color.WHITE, 0.06)
		var top_bottom := base.lerp(Color.BLACK, 0.04)
		VisualTheme.draw_vertical_gradient(self, top_rect, top_top, top_bottom)

		# Stone grain texture (deterministic sin-based pattern)
		for i in range(5):
			var gx := sin(float(tile_x * 7 + i * 13)) * 0.5 + 0.5
			var gy := sin(float(tile_y * 11 + i * 17)) * 0.5 + 0.5
			var px := top_rect.position.x + gx * top_rect.size.x
			var py := top_rect.position.y + gy * top_rect.size.y
			var grain_len := 6.0 + sin(float(i * 23)) * 4.0
			draw_line(Vector2(px, py), Vector2(px + grain_len, py + 1), VisualTheme.TILE_STONE_GRAIN, 1.0)

		# Specular highlight (top-left corner)
		var spec := VisualTheme.TILE_SPECULAR
		spec.a *= (1.0 + lighting * 2.0)
		draw_line(Vector2(top_rect.position.x + 3, top_rect.position.y + 3),
			Vector2(top_rect.position.x + 18, top_rect.position.y + 3), spec, 2.0)
		draw_line(Vector2(top_rect.position.x + 3, top_rect.position.y + 3),
			Vector2(top_rect.position.x + 3, top_rect.position.y + 14), spec, 1.5)

		# Bevel edges on top face
		VisualTheme.draw_bevel(self, top_rect, 1.0,
			Color(1, 1, 1, 0.1 + maxf(lighting, 0.0)),
			Color(0, 0, 0, 0.15))

	func _draw_wall_tile(w: float, h: float, lighting: float) -> void:
		var depth := float(VisualTheme.TILE_DEPTH_WALL)
		var wall_top := VisualTheme.apply_lighting(VisualTheme.TILE_WALL_TOP, lighting)

		# Dark base (visible as depth)
		draw_rect(Rect2(0, 0, w, h), VisualTheme.TILE_WALL_SIDE)

		# Side faces
		var side_color := wall_top.lerp(Color.BLACK, 0.5)
		# Bottom face
		draw_rect(Rect2(1, h - depth, w - 2, depth - 1), side_color)
		# Right face
		draw_rect(Rect2(w - depth, 1, depth - 1, h - 2), side_color.lerp(Color.BLACK, 0.15))

		# Top face
		var top_rect := Rect2(1, 1, w - depth - 1, h - depth - 1)
		VisualTheme.draw_vertical_gradient(self, top_rect,
			wall_top.lerp(Color.WHITE, 0.05), wall_top.lerp(Color.BLACK, 0.1))

		# Mortar pattern on top face
		var mortar := VisualTheme.TILE_WALL_MORTAR
		for y_off in [14, 28, 42]:
			if y_off < top_rect.size.y:
				draw_line(Vector2(top_rect.position.x + 2, top_rect.position.y + y_off),
					Vector2(top_rect.end.x - 2, top_rect.position.y + y_off), mortar, 1.5)
		for row in range(4):
			var y_start := top_rect.position.y + row * 14
			var x_offset := 0 if row % 2 == 0 else 14
			var x := x_offset
			while x < int(top_rect.size.x):
				var x_pos := top_rect.position.x + x
				if x_pos > top_rect.position.x + 2 and x_pos < top_rect.end.x - 2:
					draw_line(Vector2(x_pos, y_start + 1), Vector2(x_pos, y_start + 13), mortar, 1.0)
				x += 28

		# Strong bevel
		VisualTheme.draw_bevel(self, top_rect, 1.5,
			Color(1, 1, 1, 0.15), Color(0, 0, 0, 0.25))

	func _draw_pit_tile(w: float, h: float, lighting: float) -> void:
		# Outer crumbling stone rim
		draw_rect(Rect2(0, 0, w, h), VisualTheme.TILE_PIT_RIM)

		# Crumbling rim texture (jagged inner edge)
		var rim_width := 8.0
		for i in range(12):
			var angle := float(i) / 12.0 * TAU
			var jag := 2.0 + sin(float(tile_x * 5 + tile_y * 7 + i * 11)) * 3.0
			var cx := w / 2 + cos(angle) * (w / 2 - rim_width + jag)
			var cy := h / 2 + sin(angle) * (h / 2 - rim_width + jag)
			draw_circle(Vector2(cx, cy), 3.0, VisualTheme.TILE_PIT_RIM.lerp(Color.BLACK, 0.3))

		# Void center (black hole)
		var void_rect := Rect2(rim_width, rim_width, w - rim_width * 2, h - rim_width * 2)
		draw_rect(void_rect, VisualTheme.TILE_PIT_VOID)

		# Inner void gradient (even darker center)
		var inner := Rect2(rim_width + 6, rim_width + 6, w - rim_width * 2 - 12, h - rim_width * 2 - 12)
		draw_rect(inner, VisualTheme.TILE_PIT_VOID.lerp(Color.BLACK, 0.5))

		# Purple glow from below (rings)
		var center := Vector2(w / 2, h / 2)
		for i in range(4, 0, -1):
			var glow := VisualTheme.TILE_PIT_GLOW
			glow.a = VisualTheme.TILE_PIT_GLOW.a * (1.0 - float(i) / 4.0) * 0.7
			var r := (w / 2 - rim_width) * (float(i) / 4.0)
			draw_arc(center, r, 0, TAU, 24, glow, 2.0)

		# Animated-looking glow pulses (deterministic, based on tile coords)
		var glow_offset := sin(float(tile_x * 3 + tile_y * 5) * 0.7) * 2.0
		draw_circle(center + Vector2(glow_offset, -glow_offset), 6.0,
			Color(0.5, 0.2, 0.7, 0.12))

		# Inset shadow around rim
		VisualTheme.draw_inset(self, Rect2(1, 1, w - 2, h - 2), 2.0)


class HighlightDrawer extends Control:
	"""Custom drawing for tile highlights with gradients, glow, and breathing pulse."""
	enum HighlightType { NONE, MOVE, ATTACK, CAST, SELECTED, RANGE }

	var highlight_type: int = HighlightType.NONE
	var is_hovered: bool = false
	var _pulse_time: float = 0.0

	func _process(delta: float) -> void:
		if highlight_type != HighlightType.NONE:
			_pulse_time += delta * 3.0
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y

		# Hover effect (if no other highlight)
		if is_hovered and highlight_type == HighlightType.NONE:
			# Subtle gradient hover
			var hover_top := Color(1, 1, 1, 0.12)
			var hover_bottom := Color(1, 1, 1, 0.06)
			VisualTheme.draw_vertical_gradient(self, Rect2(2, 2, w - 4, h - 4), hover_top, hover_bottom)
			draw_rect(Rect2(2, 2, w - 4, h - 4), Color(1, 1, 1, 0.25), false, 1.5)
			return

		if highlight_type == HighlightType.NONE:
			return

		var fill_color: Color
		var border_color: Color
		var glow_color: Color

		match highlight_type:
			HighlightType.MOVE:
				fill_color = VisualTheme.HIGHLIGHT_MOVE
				border_color = VisualTheme.HIGHLIGHT_MOVE_BORDER
				glow_color = Color(0.3, 0.9, 0.4, 0.3)
			HighlightType.ATTACK:
				fill_color = VisualTheme.HIGHLIGHT_ATTACK
				border_color = VisualTheme.HIGHLIGHT_ATTACK_BORDER
				glow_color = Color(1.0, 0.3, 0.3, 0.3)
			HighlightType.CAST:
				fill_color = VisualTheme.HIGHLIGHT_CAST
				border_color = VisualTheme.HIGHLIGHT_CAST_BORDER
				glow_color = Color(0.4, 0.4, 1.0, 0.3)
			HighlightType.SELECTED:
				fill_color = VisualTheme.HIGHLIGHT_SELECTED
				border_color = VisualTheme.HIGHLIGHT_SELECTED_BORDER
				glow_color = Color(1.0, 0.9, 0.3, 0.35)
			HighlightType.RANGE:
				fill_color = Color(0.9, 0.8, 0.2, 0.12)
				border_color = Color(0.9, 0.8, 0.2, 0.35)
				glow_color = Color(0.9, 0.8, 0.2, 0.15)

		# Outer glow
		for i in range(2, 0, -1):
			var g := glow_color
			g.a = glow_color.a * (1.0 - float(i) / 2.0) * 0.5
			draw_rect(Rect2(2 - i, 2 - i, w - 4 + i * 2, h - 4 + i * 2), g, false, 1.5)

		# Breathing pulse intensity
		var pulse := 0.75 + sin(_pulse_time) * 0.25

		# Fill with gradient + pulse
		var fill_top := fill_color.lerp(Color.WHITE, 0.1)
		var fill_bottom := fill_color
		fill_top.a *= pulse
		fill_bottom.a *= pulse
		VisualTheme.draw_vertical_gradient(self, Rect2(3, 3, w - 6, h - 6), fill_top, fill_bottom)

		# Border with pulse
		var pulse_border := border_color
		pulse_border.a *= (0.6 + pulse * 0.4)
		draw_rect(Rect2(2, 2, w - 4, h - 4), pulse_border, false, 2.0)

		# Extra hover brightness
		if is_hovered:
			draw_rect(Rect2(3, 3, w - 6, h - 6), Color(1, 1, 1, 0.15))


class BoardFrameDrawer extends Control:
	"""Ornamental board frame drawn in the COORD_MARGIN area."""
	var board_size_px: int = 640
	var margin: int = 24

	func _draw() -> void:
		var total := board_size_px + margin * 2
		var w := float(total)
		var h := float(total)
		var m := float(margin)

		# === Outer dark wood/stone bars ===
		# Top bar
		VisualTheme.draw_vertical_gradient(self, Rect2(0, 0, w, m),
			VisualTheme.FRAME_WOOD_LIGHT, VisualTheme.FRAME_WOOD)
		# Bottom bar
		VisualTheme.draw_vertical_gradient(self, Rect2(0, h - m, w, m),
			VisualTheme.FRAME_WOOD, VisualTheme.FRAME_WOOD_LIGHT)
		# Left bar
		draw_rect(Rect2(0, m, m, h - m * 2), VisualTheme.FRAME_WOOD)
		# Right bar
		draw_rect(Rect2(w - m, m, m, h - m * 2), VisualTheme.FRAME_WOOD)

		# === Gold trim lines ===
		var gold := VisualTheme.FRAME_GOLD_TRIM
		var gold_dim := VisualTheme.FRAME_GOLD_DIM

		# Outer gold border
		draw_rect(Rect2(1, 1, w - 2, h - 2), gold, false, 1.5)
		# Inner gold border (around board area)
		draw_rect(Rect2(m - 1, m - 1, float(board_size_px) + 2, float(board_size_px) + 2), gold, false, 1.5)
		# Mid gold accent line
		draw_rect(Rect2(m / 2, m / 2, w - m, h - m), gold_dim, false, 1.0)

		# === Corner diamond ornaments ===
		var diamond_size := 5.0
		var corners := [
			Vector2(m / 2, m / 2),           # Top-left
			Vector2(w - m / 2, m / 2),       # Top-right
			Vector2(m / 2, h - m / 2),       # Bottom-left
			Vector2(w - m / 2, h - m / 2)    # Bottom-right
		]
		for corner: Vector2 in corners:
			var pts := PackedVector2Array([
				corner + Vector2(0, -diamond_size),
				corner + Vector2(diamond_size, 0),
				corner + Vector2(0, diamond_size),
				corner + Vector2(-diamond_size, 0)
			])
			draw_colored_polygon(pts, VisualTheme.FRAME_DIAMOND)
			draw_polyline(pts + PackedVector2Array([pts[0]]), gold, 1.0)

		# === Bevel on frame edges ===
		VisualTheme.draw_bevel(self, Rect2(0, 0, w, h), 1.0,
			Color(1, 1, 1, 0.08), Color(0, 0, 0, 0.15))


