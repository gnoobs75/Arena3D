extends Node
class_name AnimationControllerClass
## AnimationController - Connects EventBus signals to ChampionVisual animations
## Acts as a bridge between game events and visual feedback

# Reference to the game board (set by game.gd)
var _board: GameBoard = null

# Queue of pending animations to play sequentially
var _animation_queue: Array[Dictionary] = []
var _is_playing: bool = false


func _ready() -> void:
	_connect_event_bus()


func _connect_event_bus() -> void:
	"""Connect to game events for automatic animation triggering."""
	# Champion actions
	EventBus.champion_moved.connect(_on_champion_moved)
	EventBus.champion_attacked.connect(_on_champion_attacked)
	EventBus.champion_damaged.connect(_on_champion_damaged)
	EventBus.champion_healed.connect(_on_champion_healed)
	EventBus.champion_died.connect(_on_champion_died)

	# Buffs/Debuffs
	EventBus.champion_buff_applied.connect(_on_buff_applied)
	EventBus.champion_debuff_applied.connect(_on_debuff_applied)

	# Cards
	EventBus.card_played.connect(_on_card_played)


func set_board(board: GameBoard) -> void:
	"""Set reference to game board for accessing champion visuals."""
	_board = board


func get_champion_visual(champion_id: String) -> ChampionVisual:
	"""Get ChampionVisual for a given champion ID."""
	if _board == null:
		return null

	if not _board.champion_nodes.has(champion_id):
		return null

	var node = _board.champion_nodes[champion_id]
	if node is ChampionVisual:
		return node as ChampionVisual
	return null


# === Event Handlers ===

func _on_champion_moved(champion_id: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	"""Trigger walk animation when champion moves."""
	var visual := get_champion_visual(champion_id)
	if visual:
		var direction := Vector2(to_pos - from_pos)
		visual.play_walk_animation(direction)


func _on_champion_attacked(attacker_id: String, target_id: String, _damage: int) -> void:
	"""Trigger attack animation when champion attacks."""
	var attacker_visual := get_champion_visual(attacker_id)
	var target_visual := get_champion_visual(target_id)

	if attacker_visual and target_visual:
		var direction: Vector2 = target_visual.position - attacker_visual.position
		attacker_visual.play_attack_animation(direction)


func _on_champion_damaged(champion_id: String, amount: int, _source: String) -> void:
	"""Trigger hit animation when champion takes damage."""
	var visual := get_champion_visual(champion_id)
	if visual and amount > 0:
		visual.play_hit_animation()


func _on_champion_healed(champion_id: String, amount: int, _source: String) -> void:
	"""Trigger heal animation when champion is healed."""
	var visual := get_champion_visual(champion_id)
	if visual and amount > 0:
		visual.play_heal_animation()


func _on_champion_died(champion_id: String, _killer_id: String) -> void:
	"""Trigger death animation when champion dies."""
	var visual := get_champion_visual(champion_id)
	if visual:
		visual.play_death_animation()


func _on_buff_applied(champion_id: String, _buff_name: String, _duration: int) -> void:
	"""Trigger buff animation when buff is applied."""
	var visual := get_champion_visual(champion_id)
	if visual:
		visual.play_buff_animation()


func _on_debuff_applied(champion_id: String, _debuff_name: String, _duration: int) -> void:
	"""Trigger debuff animation when debuff is applied."""
	var visual := get_champion_visual(champion_id)
	if visual:
		visual.play_debuff_animation()


func _on_card_played(player_id: int, card_id: String, targets: Array) -> void:
	"""Trigger cast animation when a card is played."""
	# Find the caster - need to determine which champion is casting
	# For now, we'll trigger cast animation on all of that player's champions
	if _board == null or _board.game_state == null:
		return

	for champ in _board.game_state.get_all_champions():
		if champ.owner_id == player_id:
			var visual := get_champion_visual(champ.unique_id)
			if visual:
				visual.play_cast_animation()
				break  # Only animate one champion (first found)
