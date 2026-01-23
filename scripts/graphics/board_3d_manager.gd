extends Node
class_name Board3DManager
## Board3DManager - Bridges EventBus signals to Board3D
## Handles all champion updates, highlights, animations, and VFX

# === CONSTANTS ===
const BOARD_3D_SCENE: PackedScene = preload("res://scenes/game/board_3d/board_3d.tscn")

# === REFERENCES ===
var board_3d: Board3D
var game_state: GameState
var vfx_library: VFXLibrary
var choreographer: CombatChoreographer

# === STATE ===
var _champion_positions: Dictionary = {}  # champion_id -> Vector2i

func _ready() -> void:
	_connect_eventbus_signals()


func initialize(gs: GameState) -> void:
	"""Initialize with game state reference."""
	game_state = gs

	# Initialize VFX library
	if board_3d:
		var vfx_container: Node = board_3d.get_node_or_null("VFX")
		if vfx_container:
			vfx_library = VFXLibrary.new(vfx_container)

		# Initialize choreographer
		choreographer = CombatChoreographer.new(board_3d)

	_sync_board_state()


func create_board() -> Board3D:
	"""Create and return a new Board3D instance."""
	board_3d = BOARD_3D_SCENE.instantiate()
	return board_3d


func set_board(board: Board3D) -> void:
	"""Set existing Board3D reference."""
	board_3d = board


# === EVENTBUS CONNECTIONS ===

func _connect_eventbus_signals() -> void:
	"""Connect to all relevant EventBus signals."""
	# Champion signals
	EventBus.champion_moved.connect(_on_champion_moved)
	EventBus.champion_attacked.connect(_on_champion_attacked)
	EventBus.champion_damaged.connect(_on_champion_damaged)
	EventBus.champion_healed.connect(_on_champion_healed)
	EventBus.champion_died.connect(_on_champion_died)
	EventBus.champion_buff_applied.connect(_on_champion_buff_applied)
	EventBus.champion_debuff_applied.connect(_on_champion_debuff_applied)

	# Card signals
	EventBus.card_played.connect(_on_card_played)

	# Game flow
	EventBus.game_started.connect(_on_game_started)
	EventBus.turn_started.connect(_on_turn_started)


# === SYNC ===

func _sync_board_state() -> void:
	"""Sync 3D board with current game state."""
	if not board_3d or not game_state:
		return

	# Set terrain
	board_3d.set_terrain(game_state.board_terrain)

	# Add all champions
	for player_id in [1, 2]:
		for champion in game_state.get_champions(player_id):
			_add_champion_3d(champion)


func _add_champion_3d(champion: ChampionState) -> void:
	"""Add a champion to the 3D board."""
	if not board_3d:
		return

	board_3d.add_champion(
		champion.unique_id,
		champion.position,
		champion.champion_name,
		champion.owner_id
	)
	_champion_positions[champion.unique_id] = champion.position


# === EVENT HANDLERS ===

func _on_game_started(p1_champions: Array, p2_champions: Array) -> void:
	"""Handle game start - add all champions."""
	if not board_3d or not game_state:
		return

	_sync_board_state()


func _on_turn_started(player_id: int, round_number: int) -> void:
	"""Handle turn start - update any visuals."""
	pass  # Could highlight active player's champions


func _on_champion_moved(champion_id: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	"""Handle champion movement - animate walk."""
	if not board_3d:
		return

	# Build path (for now just direct, later use pathfinding)
	var path: Array[Vector2i] = [to_pos]

	# Animate movement
	await board_3d.animate_move(champion_id, path, 0.4)

	# Update stored position
	_champion_positions[champion_id] = to_pos


func _on_champion_attacked(attacker_id: String, target_id: String, damage: int) -> void:
	"""Handle attack - play attack choreography."""
	if not board_3d:
		return

	await board_3d.animate_attack(attacker_id, target_id)


func _on_champion_damaged(champion_id: String, amount: int, source: String) -> void:
	"""Handle damage - play hit reaction."""
	if not board_3d:
		return

	# TODO: Play hit animation on champion
	var champion: Node3D = board_3d.get_champion_node(champion_id)
	if champion:
		# Flash red or shake
		_play_damage_effect(champion, amount)


func _on_champion_healed(champion_id: String, amount: int, source: String) -> void:
	"""Handle healing - play heal effect."""
	if not board_3d:
		return

	var champion: Node3D = board_3d.get_champion_node(champion_id)
	if champion:
		_play_heal_effect(champion, amount)


func _on_champion_died(champion_id: String, killer_id: String) -> void:
	"""Handle death - play death animation and remove."""
	if not board_3d:
		return

	var champion: Node3D = board_3d.get_champion_node(champion_id)
	if champion:
		await _play_death_animation(champion)

	board_3d.remove_champion(champion_id)
	_champion_positions.erase(champion_id)


func _on_champion_buff_applied(champion_id: String, buff_name: String, duration: int) -> void:
	"""Handle buff - show buff visual."""
	if not board_3d:
		return

	var champion: Node3D = board_3d.get_champion_node(champion_id)
	if champion:
		_play_buff_effect(champion)


func _on_champion_debuff_applied(champion_id: String, debuff_name: String, duration: int) -> void:
	"""Handle debuff - show debuff visual."""
	if not board_3d:
		return

	var champion: Node3D = board_3d.get_champion_node(champion_id)
	if champion:
		_play_debuff_effect(champion)


func _on_card_played(player_id: int, card_id: String, targets: Array) -> void:
	"""Handle card cast - play cast animation."""
	if not board_3d or not game_state:
		return

	# TODO: Determine caster and play cast animation


# === EFFECT HELPERS ===

func _play_damage_effect(champion: Node3D, amount: int) -> void:
	"""Play damage visual effect with VFX."""
	# Spawn impact VFX
	if vfx_library:
		var champion_name: String = champion.get_meta("champion_name", "")
		if champion_name:
			vfx_library.spawn_impact(champion.position + Vector3(0, 0.5, 0), Color.RED)
		else:
			vfx_library.spawn_impact(champion.position + Vector3(0, 0.5, 0))

	# Flash red using materials
	var body: Node = champion.get_node_or_null("Body")
	if body and body is MeshInstance3D:
		var mat: StandardMaterial3D = body.material_override
		if mat:
			var original_color: Color = mat.albedo_color
			var flash_color: Color = Color(1.0, 0.2, 0.2)

			var tween: Tween = champion.create_tween()
			tween.tween_property(mat, "albedo_color", flash_color, 0.1)
			tween.tween_property(mat, "albedo_color", original_color, 0.15)


func _play_heal_effect(champion: Node3D, amount: int) -> void:
	"""Play healing visual effect with VFX."""
	# Spawn heal VFX
	if vfx_library:
		vfx_library.spawn_heal(champion.position, Color.GREEN)

	var body: Node = champion.get_node_or_null("Body")
	if body and body is MeshInstance3D:
		var mat: StandardMaterial3D = body.material_override
		if mat:
			var original_color: Color = mat.albedo_color
			var heal_color: Color = Color(0.2, 1.0, 0.3)

			var tween: Tween = champion.create_tween()
			tween.tween_property(mat, "albedo_color", heal_color, 0.1)
			tween.tween_property(mat, "albedo_color", original_color, 0.2)


func _play_buff_effect(champion: Node3D) -> void:
	"""Play buff visual effect with VFX."""
	# Spawn buff VFX
	if vfx_library:
		vfx_library.spawn_buff(champion.position, Color.CYAN)

	# Scale up briefly
	var original_scale: Vector3 = champion.scale
	var buff_scale: Vector3 = original_scale * 1.1

	var tween: Tween = champion.create_tween()
	tween.tween_property(champion, "scale", buff_scale, 0.15)
	tween.tween_property(champion, "scale", original_scale, 0.15)


func _play_debuff_effect(champion: Node3D) -> void:
	"""Play debuff visual effect with VFX."""
	# Spawn debuff VFX
	if vfx_library:
		vfx_library.spawn_debuff(champion.position, Color.PURPLE)

	# Scale down briefly
	var original_scale: Vector3 = champion.scale
	var debuff_scale: Vector3 = original_scale * 0.9

	var tween: Tween = champion.create_tween()
	tween.tween_property(champion, "scale", debuff_scale, 0.15)
	tween.tween_property(champion, "scale", original_scale, 0.15)


func _play_death_animation(champion: Node3D) -> void:
	"""Play death animation with VFX."""
	# Spawn death VFX (soul rising)
	if vfx_library:
		var colors: Dictionary = VisualTheme.get_champion_colors(champion.get_meta("champion_name", ""))
		vfx_library.spawn_death(champion.position, colors.get("primary", Color.WHITE))

	var tween: Tween = champion.create_tween()

	# Fall over and fade out
	tween.parallel().tween_property(champion, "rotation_degrees:x", 90, 0.4)
	tween.parallel().tween_property(champion, "position:y", -0.3, 0.4)

	# Fade out (if materials support it)
	var body: Node = champion.get_node_or_null("Body")
	if body and body is MeshInstance3D:
		var mat: StandardMaterial3D = body.material_override
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.5)

	await tween.finished


# === HIGHLIGHT PASSTHROUGH ===

func set_highlights(positions: Array, highlight_type: int) -> void:
	"""Set highlights on tiles."""
	if board_3d:
		board_3d.set_highlights(positions, highlight_type as Board3D.HighlightType)


func clear_highlights() -> void:
	"""Clear all highlights."""
	if board_3d:
		board_3d.clear_highlights()


func set_highlight(pos: Vector2i, highlight_type: int) -> void:
	"""Set single tile highlight."""
	if board_3d:
		board_3d.set_highlight(pos, highlight_type as Board3D.HighlightType)
