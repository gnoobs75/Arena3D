extends Node3D
class_name Board3D
## Board3D - 3D isometric game board for Arena
## Renders the 10x10 tactical grid with tiles, highlights, and champions

# === SIGNALS ===
signal tile_clicked(grid_pos: Vector2i)
signal tile_hovered(grid_pos: Vector2i)
signal tile_unhovered(grid_pos: Vector2i)
signal champion_clicked(champion_id: String)

# === CONSTANTS ===
const GRID_SIZE: int = 10
const TILE_SIZE: float = 1.0  # 1 unit per tile in 3D space
const TILE_HEIGHT: float = 0.1  # Tile thickness
const WALL_HEIGHT: float = 0.5  # Raised wall tiles
const CHAMPION_Y_OFFSET: float = 0.05  # Champions sit slightly above tiles

# Highlight types matching 2D board
enum HighlightType { NONE, MOVE, ATTACK, CAST, SELECTED, RANGE, HOVER }

# === NODE REFERENCES ===
var camera: Camera3D
var tiles_container: Node3D
var highlights_container: Node3D
var champions_container: Node3D
var vfx_container: Node3D

# === STATE ===
var _tiles: Dictionary = {}  # Vector2i -> MeshInstance3D
var _highlights: Dictionary = {}  # Vector2i -> MeshInstance3D
var _champion_nodes: Dictionary = {}  # champion_id -> Node3D
var _hovered_tile: Vector2i = Vector2i(-1, -1)
var _board_data: Array = []  # Terrain data from GameState
var _initialized: bool = false

# Materials (created once, reused)
var _tile_materials: Dictionary = {}
var _highlight_materials: Dictionary = {}

func _ready() -> void:
	_create_containers()
	_create_materials()
	_setup_camera()
	_setup_lighting()
	_create_board_tiles()
	_create_highlight_meshes()
	_initialized = true
	print("Board3D: Initialized successfully")


func _create_containers() -> void:
	"""Create container nodes for organization."""
	# Camera
	camera = Camera3D.new()
	camera.name = "Camera3D"
	add_child(camera)

	# Tiles container
	tiles_container = Node3D.new()
	tiles_container.name = "Tiles"
	add_child(tiles_container)

	# Highlights container
	highlights_container = Node3D.new()
	highlights_container.name = "Highlights"
	add_child(highlights_container)

	# Champions container
	champions_container = Node3D.new()
	champions_container.name = "Champions"
	add_child(champions_container)

	# VFX container
	vfx_container = Node3D.new()
	vfx_container.name = "VFX"
	add_child(vfx_container)

# === INITIALIZATION ===

func _create_materials() -> void:
	"""Create reusable materials for tiles and highlights."""
	# Tile materials
	_tile_materials["empty"] = _create_tile_material(VisualTheme.TILE_EMPTY)
	_tile_materials["empty_alt"] = _create_tile_material(VisualTheme.TILE_EMPTY_ALT)
	_tile_materials["wall"] = _create_tile_material(VisualTheme.TILE_WALL)
	_tile_materials["pit"] = _create_pit_material()

	# Highlight materials (semi-transparent)
	_highlight_materials[HighlightType.MOVE] = _create_highlight_material(VisualTheme.HIGHLIGHT_MOVE)
	_highlight_materials[HighlightType.ATTACK] = _create_highlight_material(VisualTheme.HIGHLIGHT_ATTACK)
	_highlight_materials[HighlightType.CAST] = _create_highlight_material(VisualTheme.HIGHLIGHT_CAST)
	_highlight_materials[HighlightType.SELECTED] = _create_highlight_material(VisualTheme.HIGHLIGHT_SELECTED)
	_highlight_materials[HighlightType.RANGE] = _create_highlight_material(Color(0.9, 0.8, 0.2, 0.15))
	_highlight_materials[HighlightType.HOVER] = _create_highlight_material(VisualTheme.HIGHLIGHT_HOVER)


func _create_tile_material(color: Color) -> StandardMaterial3D:
	"""Create a standard material for tiles."""
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mat.metallic = 0.1
	return mat


func _create_pit_material() -> StandardMaterial3D:
	"""Create a dark, glowing material for pit tiles."""
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = VisualTheme.TILE_PIT
	mat.emission_enabled = true
	mat.emission = VisualTheme.TILE_PIT_EDGE
	mat.emission_energy_multiplier = 0.5
	mat.roughness = 1.0
	return mat


func _create_highlight_material(color: Color) -> StandardMaterial3D:
	"""Create a transparent material for highlights."""
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _setup_camera() -> void:
	"""Configure orthographic isometric camera."""
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0  # Adjust to fit 10x10 board with margin

	# Classic isometric angle: 30° pitch, 45° yaw
	# Position camera to look at board center
	var board_center: Vector3 = Vector3(0, 0, 0)
	var camera_distance: float = 15.0

	# Calculate camera position for isometric view
	camera.rotation_degrees = Vector3(-35, 45, 0)
	camera.position = board_center + Vector3(camera_distance, camera_distance * 0.7, camera_distance)
	camera.look_at(board_center)


func _setup_lighting() -> void:
	"""Set up directional light for the board."""
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45, 45, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

	# Ambient light via environment
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.35, 0.4)
	env.ambient_light_energy = 0.4

	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _create_board_tiles() -> void:
	"""Generate 3D tiles for the 10x10 board."""
	var tile_mesh: BoxMesh = BoxMesh.new()
	tile_mesh.size = Vector3(TILE_SIZE * 0.95, TILE_HEIGHT, TILE_SIZE * 0.95)  # Small gap between tiles

	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var grid_pos: Vector2i = Vector2i(x, y)
			var tile: MeshInstance3D = MeshInstance3D.new()
			tile.mesh = tile_mesh
			tile.name = "Tile_%d_%d" % [x, y]

			# Checkerboard pattern for empty tiles
			var is_alt: bool = (x + y) % 2 == 1
			tile.material_override = _tile_materials["empty_alt"] if is_alt else _tile_materials["empty"]

			# Position tile
			tile.position = grid_to_world(grid_pos)
			tile.position.y = -TILE_HEIGHT / 2  # Sink into ground plane

			# Add collision for raycasting
			var collision: StaticBody3D = StaticBody3D.new()
			var collision_shape: CollisionShape3D = CollisionShape3D.new()
			var box_shape: BoxShape3D = BoxShape3D.new()
			box_shape.size = Vector3(TILE_SIZE, TILE_HEIGHT, TILE_SIZE)
			collision_shape.shape = box_shape
			collision.add_child(collision_shape)
			tile.add_child(collision)

			# Store metadata for raycast hits
			collision.set_meta("grid_pos", grid_pos)

			tiles_container.add_child(tile)
			_tiles[grid_pos] = tile


func _create_highlight_meshes() -> void:
	"""Create highlight plane meshes for each tile (initially invisible)."""
	var highlight_mesh: PlaneMesh = PlaneMesh.new()
	highlight_mesh.size = Vector2(TILE_SIZE * 0.9, TILE_SIZE * 0.9)

	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var grid_pos: Vector2i = Vector2i(x, y)
			var highlight: MeshInstance3D = MeshInstance3D.new()
			highlight.mesh = highlight_mesh
			highlight.name = "Highlight_%d_%d" % [x, y]
			highlight.visible = false

			# Position slightly above tile
			highlight.position = grid_to_world(grid_pos)
			highlight.position.y = 0.02

			# Rotate to face up
			highlight.rotation_degrees.x = -90

			highlights_container.add_child(highlight)
			_highlights[grid_pos] = highlight


# === COORDINATE CONVERSION ===

func grid_to_world(grid_pos: Vector2i) -> Vector3:
	"""Convert grid position (0-9, 0-9) to 3D world position."""
	# Center the board: grid center (4.5, 4.5) maps to world (0, 0, 0)
	return Vector3(
		(grid_pos.x - 4.5) * TILE_SIZE,
		0.0,
		(grid_pos.y - 4.5) * TILE_SIZE
	)


func world_to_grid(world_pos: Vector3) -> Vector2i:
	"""Convert 3D world position to grid position."""
	var gx: int = int(round(world_pos.x / TILE_SIZE + 4.5))
	var gy: int = int(round(world_pos.z / TILE_SIZE + 4.5))
	return Vector2i(clampi(gx, 0, GRID_SIZE - 1), clampi(gy, 0, GRID_SIZE - 1))


func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	"""Convert screen position to grid position via raycast."""
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	# Intersect with Y=0 plane
	if abs(ray_dir.y) < 0.001:
		return Vector2i(-1, -1)  # Ray parallel to ground

	var t: float = -ray_origin.y / ray_dir.y
	if t < 0:
		return Vector2i(-1, -1)  # Behind camera

	var world_pos: Vector3 = ray_origin + ray_dir * t
	var grid_pos: Vector2i = world_to_grid(world_pos)

	# Validate grid bounds
	if grid_pos.x < 0 or grid_pos.x >= GRID_SIZE or grid_pos.y < 0 or grid_pos.y >= GRID_SIZE:
		return Vector2i(-1, -1)

	return grid_pos


# === TERRAIN ===

func set_terrain(board_data: Array) -> void:
	"""Update tile materials and geometry based on terrain data from GameState."""
	_board_data = board_data

	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if x >= board_data.size() or y >= board_data[x].size():
				continue

			var grid_pos: Vector2i = Vector2i(x, y)
			var terrain: int = board_data[x][y]
			var tile: MeshInstance3D = _tiles.get(grid_pos)
			if not tile:
				continue

			# Terrain types: 0 = empty, 1 = wall, 2 = pit
			match terrain:
				0:  # Empty
					var is_alt: bool = (x + y) % 2 == 1
					tile.material_override = _tile_materials["empty_alt"] if is_alt else _tile_materials["empty"]
					tile.position.y = -TILE_HEIGHT / 2
					tile.scale = Vector3.ONE

				1:  # Wall - create raised 3D block
					tile.material_override = _tile_materials["wall"]
					tile.position.y = WALL_HEIGHT / 2
					# Create taller mesh for wall
					var wall_mesh: BoxMesh = BoxMesh.new()
					wall_mesh.size = Vector3(TILE_SIZE * 0.95, WALL_HEIGHT, TILE_SIZE * 0.95)
					tile.mesh = wall_mesh
					# Add stone-like detail
					_add_wall_details(tile, grid_pos)

				2:  # Pit - lower with glow effect
					tile.material_override = _tile_materials["pit"]
					tile.position.y = -TILE_HEIGHT * 2
					# Add edge glow
					_add_pit_glow(grid_pos)


func _add_wall_details(tile: MeshInstance3D, grid_pos: Vector2i) -> void:
	"""Add visual details to wall tiles."""
	# Add a slight bevel/top cap with different color
	var cap: MeshInstance3D = MeshInstance3D.new()
	cap.name = "WallCap"
	var cap_mesh: BoxMesh = BoxMesh.new()
	cap_mesh.size = Vector3(TILE_SIZE * 0.98, 0.05, TILE_SIZE * 0.98)
	cap.mesh = cap_mesh
	cap.position.y = WALL_HEIGHT / 2 - 0.025

	var cap_mat: StandardMaterial3D = StandardMaterial3D.new()
	cap_mat.albedo_color = VisualTheme.TILE_WALL_ACCENT
	cap.material_override = cap_mat

	tile.add_child(cap)


func _add_pit_glow(grid_pos: Vector2i) -> void:
	"""Add glowing edge effect to pit tiles."""
	var world_pos: Vector3 = grid_to_world(grid_pos)

	# Create glowing edge ring
	var glow: MeshInstance3D = MeshInstance3D.new()
	glow.name = "PitGlow_%d_%d" % [grid_pos.x, grid_pos.y]

	var glow_mesh: TorusMesh = TorusMesh.new()
	glow_mesh.inner_radius = TILE_SIZE * 0.35
	glow_mesh.outer_radius = TILE_SIZE * 0.45

	glow.mesh = glow_mesh
	glow.position = Vector3(world_pos.x, -0.1, world_pos.z)
	glow.rotation_degrees.x = 90

	var glow_mat: StandardMaterial3D = StandardMaterial3D.new()
	glow_mat.albedo_color = VisualTheme.TILE_PIT_EDGE
	glow_mat.emission_enabled = true
	glow_mat.emission = VisualTheme.TILE_PIT_EDGE
	glow_mat.emission_energy_multiplier = 0.8
	glow.material_override = glow_mat

	tiles_container.add_child(glow)


# === HIGHLIGHTS ===

func set_highlight(grid_pos: Vector2i, highlight_type: HighlightType) -> void:
	"""Set highlight for a single tile."""
	var highlight: MeshInstance3D = _highlights.get(grid_pos)
	if not highlight:
		return

	if highlight_type == HighlightType.NONE:
		highlight.visible = false
	else:
		highlight.visible = true
		highlight.material_override = _highlight_materials.get(highlight_type)


func set_highlights(positions: Array, highlight_type: HighlightType) -> void:
	"""Set highlights for multiple tiles."""
	for pos in positions:
		if pos is Vector2i:
			set_highlight(pos, highlight_type)


func clear_highlights() -> void:
	"""Clear all tile highlights."""
	for highlight in _highlights.values():
		highlight.visible = false


func clear_highlight_type(highlight_type: HighlightType) -> void:
	"""Clear highlights of a specific type."""
	for grid_pos in _highlights:
		var highlight: MeshInstance3D = _highlights[grid_pos]
		if highlight.visible and highlight.material_override == _highlight_materials.get(highlight_type):
			highlight.visible = false


# === CHAMPIONS ===

func add_champion(champion_id: String, grid_pos: Vector2i, champion_name: String, owner_id: int) -> void:
	"""Add a 3D champion to the board."""
	# Use ChampionFactory to create procedural champion
	var champion: Node3D = ChampionFactory.create_champion(champion_name, owner_id)
	champion.name = "Champion_" + champion_id
	champion.set_meta("champion_id", champion_id)
	champion.set_meta("champion_name", champion_name)
	champion.set_meta("owner_id", owner_id)

	# Position on grid
	var world_pos: Vector3 = grid_to_world(grid_pos)
	champion.position = Vector3(world_pos.x, CHAMPION_Y_OFFSET, world_pos.z)

	champions_container.add_child(champion)
	_champion_nodes[champion_id] = champion


# Placeholder champion creation removed - using ChampionFactory.create_champion() instead


func remove_champion(champion_id: String) -> void:
	"""Remove a champion from the board."""
	var champion: Node3D = _champion_nodes.get(champion_id)
	if champion:
		champion.queue_free()
		_champion_nodes.erase(champion_id)


func move_champion(champion_id: String, grid_pos: Vector2i) -> void:
	"""Instantly move champion to new position (no animation)."""
	var champion: Node3D = _champion_nodes.get(champion_id)
	if champion:
		var world_pos: Vector3 = grid_to_world(grid_pos)
		champion.position = Vector3(world_pos.x, CHAMPION_Y_OFFSET, world_pos.z)


func get_champion_node(champion_id: String) -> Node3D:
	"""Get champion node by ID."""
	return _champion_nodes.get(champion_id)


# === ANIMATION STUBS (to be implemented) ===

func animate_move(champion_id: String, path: Array[Vector2i], duration: float = 0.4) -> void:
	"""Animate champion walking along path with walk animation."""
	var champion: Node3D = _champion_nodes.get(champion_id)
	if not champion or path.is_empty():
		return

	var time_per_tile: float = duration / path.size()

	for i in range(path.size()):
		var grid_pos: Vector2i = path[i]
		var world_pos: Vector3 = grid_to_world(grid_pos)
		var target: Vector3 = Vector3(world_pos.x, CHAMPION_Y_OFFSET, world_pos.z)

		# Calculate direction for facing
		var direction: Vector3 = target - champion.position
		direction.y = 0

		# Play walk animation if champion supports it
		if champion is Champion3D:
			# Start walk animation (will loop during movement)
			champion.play_walk_animation(direction, time_per_tile)

		# Tween position
		var tween: Tween = create_tween()
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_SINE)
		tween.tween_property(champion, "position", target, time_per_tile)

		await tween.finished


func animate_attack(attacker_id: String, target_id: String) -> void:
	"""Animate attack sequence with Battle Chess choreography."""
	var attacker: Node3D = _champion_nodes.get(attacker_id)
	var target: Node3D = _champion_nodes.get(target_id)
	if not attacker or not target:
		return

	var original_pos: Vector3 = attacker.position
	var target_pos: Vector3 = target.position
	var direction: Vector3 = (target_pos - original_pos).normalized()

	# Calculate attack position (adjacent to target)
	var attack_distance: float = 0.8  # Stay this far from target
	var attack_pos: Vector3 = target_pos - direction * attack_distance

	# Phase 1: Walk to attack position
	if attacker.position.distance_to(attack_pos) > 0.1:
		var walk_path: Array[Vector2i] = [world_to_grid(attack_pos)]
		await animate_move(attacker_id, walk_path, 0.3)

	# Phase 2: Face target and attack
	if attacker is Champion3D:
		attacker.play_attack_animation(direction)
		await attacker.animation_finished

	# Phase 3: Target hit reaction
	if target is Champion3D:
		target.play_hit_animation(1)
		# Don't wait for hit animation - let it play while attacker returns

	# Phase 4: Return to original position
	if attacker.position.distance_to(original_pos) > 0.1:
		var return_path: Array[Vector2i] = [world_to_grid(original_pos)]
		await animate_move(attacker_id, return_path, 0.3)
	else:
		# Just move back directly
		var return_tween: Tween = create_tween()
		return_tween.tween_property(attacker, "position", original_pos, 0.2)
		await return_tween.finished


func animate_cast(champion_id: String, target_positions: Array = []) -> void:
	"""Animate spell casting."""
	var champion: Node3D = _champion_nodes.get(champion_id)
	if not champion:
		return

	# Face toward center of targets if any
	if target_positions.size() > 0:
		var center: Vector3 = Vector3.ZERO
		for pos in target_positions:
			if pos is Vector2i:
				center += grid_to_world(pos)
		center /= target_positions.size()

		var direction: Vector3 = (center - champion.position).normalized()
		if direction.length_squared() > 0.01:
			var target_angle: float = atan2(direction.x, direction.z)
			champion.rotation.y = target_angle

	if champion is Champion3D:
		champion.play_cast_animation(false)
		await champion.animation_finished


func animate_death(champion_id: String) -> void:
	"""Animate champion death."""
	var champion: Node3D = _champion_nodes.get(champion_id)
	if not champion:
		return

	if champion is Champion3D:
		champion.play_death_animation()
		await champion.animation_finished


func animate_buff(champion_id: String) -> void:
	"""Animate buff received."""
	var champion: Node3D = _champion_nodes.get(champion_id)
	if not champion:
		return

	if champion is Champion3D:
		champion.play_buff_animation()
		await champion.animation_finished


func animate_debuff(champion_id: String) -> void:
	"""Animate debuff received."""
	var champion: Node3D = _champion_nodes.get(champion_id)
	if not champion:
		return

	if champion is Champion3D:
		champion.play_debuff_animation()
		await champion.animation_finished


func set_champion_selected(champion_id: String, is_selected: bool) -> void:
	"""Show/hide selection highlight on champion."""
	var champion: Node3D = _champion_nodes.get(champion_id)
	if not champion:
		return

	if champion is Champion3D:
		champion.set_selected(is_selected)


# === 2D BOARD COMPATIBILITY METHODS ===
# These methods match the 2D GameBoard interface for easy swapping

var _game_state: GameState  # Reference to game state for updates
var _selected_champion_id: String = ""

func initialize(game_state: GameState) -> void:
	"""Initialize board with game state (compatibility with 2D board)."""
	_game_state = game_state
	set_terrain(game_state.board_terrain)

	# Add all champions (skip if already added)
	for player_id in [1, 2]:
		for champion in game_state.get_champions(player_id):
			if not _champion_nodes.has(champion.unique_id):
				add_champion(
					champion.unique_id,
					champion.position,
					champion.champion_name,
					champion.owner_id
				)


func select_champion(champion_id: String) -> void:
	"""Select a champion (2D board compatibility)."""
	# Deselect previous
	if not _selected_champion_id.is_empty():
		set_champion_selected(_selected_champion_id, false)

	_selected_champion_id = champion_id
	set_champion_selected(champion_id, true)

	# Also highlight the tile
	var champion: Node3D = _champion_nodes.get(champion_id)
	if champion:
		var grid_pos: Vector2i = world_to_grid(champion.position)
		set_highlight(grid_pos, HighlightType.SELECTED)


func show_move_highlights(positions: Array) -> void:
	"""Show movement highlight on positions (2D board compatibility)."""
	var typed_positions: Array = []
	for pos in positions:
		if pos is Vector2i:
			typed_positions.append(pos)
	set_highlights(typed_positions, HighlightType.MOVE)


func show_attack_highlights(positions: Array) -> void:
	"""Show attack highlight on positions (2D board compatibility)."""
	var typed_positions: Array = []
	for pos in positions:
		if pos is Vector2i:
			typed_positions.append(pos)
	set_highlights(typed_positions, HighlightType.ATTACK)


func show_cast_highlights(positions: Array) -> void:
	"""Show cast highlight on positions (2D board compatibility)."""
	var typed_positions: Array = []
	for pos in positions:
		if pos is Vector2i:
			typed_positions.append(pos)
	set_highlights(typed_positions, HighlightType.CAST)


func show_range_highlights(positions: Array) -> void:
	"""Show range highlight on positions (2D board compatibility)."""
	var typed_positions: Array = []
	for pos in positions:
		if pos is Vector2i:
			typed_positions.append(pos)
	set_highlights(typed_positions, HighlightType.RANGE)


func update_champion_positions() -> void:
	"""Sync champion positions from game state (2D board compatibility)."""
	if not _game_state:
		return

	for player_id in [1, 2]:
		for champion in _game_state.get_champions(player_id):
			var node: Node3D = _champion_nodes.get(champion.unique_id)
			if node:
				var world_pos: Vector3 = grid_to_world(champion.position)
				node.position = Vector3(world_pos.x, CHAMPION_Y_OFFSET, world_pos.z)

				# Update visibility based on alive status
				node.visible = champion.is_alive()


func update_champion_hp() -> void:
	"""Update champion HP displays (2D board compatibility)."""
	if not _game_state:
		return

	for player_id in [1, 2]:
		for champion in _game_state.get_champions(player_id):
			var node: Node3D = _champion_nodes.get(champion.unique_id)
			if node and node is Champion3D:
				node.update_hp(champion.current_hp, champion.max_hp)


func update_terrain() -> void:
	"""Refresh terrain display (2D board compatibility)."""
	if _game_state:
		set_terrain(_game_state.board_terrain)


func get_champion_screen_position(champion_id: String) -> Vector2:
	"""Get screen position of a champion for floating text (2D board compatibility)."""
	var champion: Node3D = _champion_nodes.get(champion_id)
	if not champion or not camera:
		return Vector2.ZERO

	# Project 3D position to screen space
	var world_pos: Vector3 = champion.global_position + Vector3(0, 1.0, 0)  # Offset up for head

	if not camera.is_position_behind(world_pos):
		return camera.unproject_position(world_pos)

	return Vector2.ZERO


# === INPUT HANDLING ===

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)


func _handle_mouse_motion(screen_pos: Vector2) -> void:
	"""Handle mouse hover over tiles."""
	var grid_pos: Vector2i = screen_to_grid(screen_pos)

	if grid_pos != _hovered_tile:
		if _hovered_tile != Vector2i(-1, -1):
			tile_unhovered.emit(_hovered_tile)

		_hovered_tile = grid_pos

		if grid_pos != Vector2i(-1, -1):
			tile_hovered.emit(grid_pos)


func _handle_click(screen_pos: Vector2) -> void:
	"""Handle click on tile or champion."""
	var grid_pos: Vector2i = screen_to_grid(screen_pos)
	if grid_pos == Vector2i(-1, -1):
		return

	# Check if clicking a champion
	for champion_id in _champion_nodes:
		var champion: Node3D = _champion_nodes[champion_id]
		var champion_grid: Vector2i = world_to_grid(champion.position)
		if champion_grid == grid_pos:
			champion_clicked.emit(champion_id)
			return

	tile_clicked.emit(grid_pos)
