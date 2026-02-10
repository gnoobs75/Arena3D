extends Node
class_name AnimationControllerClass
## AnimationController - Connects EventBus signals to ChampionVisual animations
## Acts as a bridge between game events and visual/audio feedback

# Reference to the game board (set by game.gd)
var _board: GameBoard = null

# Queue of pending animations to play sequentially
var _animation_queue: Array[Dictionary] = []
var _is_playing: bool = false

# Preloaded sound cache
var _sounds_loaded: bool = false

# Screen shake state
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _shake_original_pos: Vector2 = Vector2.ZERO
var _shake_active: bool = false


func _ready() -> void:
	_connect_event_bus()
	# Preload sounds on next frame to avoid load-order issues
	call_deferred("_preload_sounds")


func _preload_sounds() -> void:
	"""Preload all game sound effects into AudioManager cache."""
	if _sounds_loaded:
		return
	_sounds_loaded = true
	if not AudioManager:
		return
	# Preload hit sounds
	for path: String in VisualTheme.SFX_HIT:
		AudioManager.preload_sound(path)
	# Preload magic sounds
	for path: String in VisualTheme.SFX_MAGIC:
		AudioManager.preload_sound(path)
	# Preload individual sounds
	AudioManager.preload_sound(VisualTheme.SFX_SPELL_CAST)
	AudioManager.preload_sound(VisualTheme.SFX_MAGIC_IMPACT)
	AudioManager.preload_sound(VisualTheme.SFX_DEATH)
	AudioManager.preload_sound(VisualTheme.SFX_PAIN)
	AudioManager.preload_sound(VisualTheme.SFX_HEAL)
	AudioManager.preload_sound(VisualTheme.SFX_VICTORY)
	AudioManager.preload_sound(VisualTheme.MUSIC_BATTLE)
	AudioManager.preload_sound(VisualTheme.MUSIC_AMBIENT)


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

	# Turn lifecycle (for Beast form revert)
	EventBus.turn_ended.connect(_on_turn_ended)

	# Game lifecycle
	EventBus.game_started.connect(_on_game_started)
	EventBus.game_ended.connect(_on_game_ended)


func _process(delta: float) -> void:
	if _shake_active and _board:
		_shake_timer -= delta
		if _shake_timer <= 0:
			_shake_active = false
			_board.position = _shake_original_pos
		else:
			var shake_decay := _shake_timer / 0.3  # Decay over time
			var offset_x := sin(_shake_timer * 45.0) * _shake_intensity * shake_decay
			var offset_y := sin(_shake_timer * 35.0 + 1.0) * _shake_intensity * shake_decay * 0.7
			_board.position = _shake_original_pos + Vector2(offset_x, offset_y)


func trigger_screen_shake(intensity: float, duration: float = 0.3) -> void:
	"""Shake the board for impact feedback."""
	if _board == null:
		return
	if not _shake_active:
		_shake_original_pos = _board.position
	_shake_intensity = intensity
	_shake_timer = duration
	_shake_active = true


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


# === Sound Helpers ===

func _play_random_sfx(paths: Array, volume: float = 1.0, pitch_variance: float = 0.1) -> void:
	"""Play a random sound from an array of paths."""
	if not AudioManager or paths.is_empty():
		return
	# Pick deterministic-ish random index
	var idx := int(Time.get_ticks_msec()) % paths.size()
	var stream := AudioManager.preload_sound(paths[idx])
	if stream:
		var pitch := 1.0 + (sin(float(Time.get_ticks_msec()) * 0.001) * pitch_variance)
		AudioManager.play_sfx(stream, volume, pitch)


func _play_sfx(path: String, volume: float = 1.0, pitch: float = 1.0) -> void:
	"""Play a single sound effect."""
	if not AudioManager:
		return
	var stream := AudioManager.preload_sound(path)
	if stream:
		AudioManager.play_sfx(stream, volume, pitch)


# === Event Handlers ===

func _on_champion_moved(champion_id: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	"""Trigger walk animation when champion moves."""
	var visual := get_champion_visual(champion_id)
	if visual:
		var direction := Vector2(to_pos - from_pos)
		visual.play_walk_animation(direction)
	# Dust trail VFX at destination
	if _board:
		_board.trigger_dust(to_pos)


func _on_champion_attacked(attacker_id: String, target_id: String, _damage: int) -> void:
	"""Trigger attack animation when champion attacks."""
	var attacker_visual := get_champion_visual(attacker_id)
	var target_visual := get_champion_visual(target_id)

	if attacker_visual and target_visual:
		var direction: Vector2 = target_visual.position - attacker_visual.position
		attacker_visual.play_attack_animation(direction)

	# VFX + SFX based on attack range
	if _board and _board.game_state:
		var attacker := _board.game_state.get_champion(attacker_id)
		var target := _board.game_state.get_champion(target_id)
		if attacker and target:
			if attacker.current_range <= 2:
				_board.trigger_melee_impact(target.position)
				_play_random_sfx(VisualTheme.SFX_HIT, 0.8, 0.15)
			else:
				_board.trigger_ranged_trail(attacker.position, target.position)
				_board.trigger_melee_impact(target.position)
				_play_random_sfx(VisualTheme.SFX_HIT, 0.7, 0.1)


func _on_champion_damaged(champion_id: String, amount: int, _source: String) -> void:
	"""Trigger hit animation when champion takes damage."""
	var visual := get_champion_visual(champion_id)
	if visual and amount > 0:
		visual.play_hit_animation()
	# Screen shake on heavy damage
	if amount >= 6:
		trigger_screen_shake(4.0, 0.35)
	elif amount >= 4:
		trigger_screen_shake(2.5, 0.25)
	elif amount >= 3:
		trigger_screen_shake(1.5, 0.15)
	# Pain sound on heavy damage
	if amount >= 4:
		_play_sfx(VisualTheme.SFX_PAIN, 0.6, 1.0 + sin(float(Time.get_ticks_msec()) * 0.001) * 0.15)


func _on_champion_healed(champion_id: String, amount: int, _source: String) -> void:
	"""Trigger heal animation when champion is healed."""
	var visual := get_champion_visual(champion_id)
	if visual and amount > 0:
		visual.play_heal_animation()
	# Heal sparkle VFX + SFX
	if _board and _board.game_state and amount > 0:
		var champ := _board.game_state.get_champion(champion_id)
		if champ:
			_board.trigger_heal_sparkles(champ.position)
		_play_sfx(VisualTheme.SFX_HEAL, 0.5, 1.1)


func _on_champion_died(champion_id: String, _killer_id: String) -> void:
	"""Trigger death animation when champion dies."""
	var visual := get_champion_visual(champion_id)
	if visual:
		visual.play_death_animation()
	# Death VFX + SFX + screen shake
	if _board and _board.game_state:
		var champ := _board.game_state.get_champion(champion_id)
		if champ:
			_board.trigger_death_vfx(champ.position)
	trigger_screen_shake(5.0, 0.4)
	_play_sfx(VisualTheme.SFX_DEATH, 0.7)


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


func _on_card_played(_player_id: int, card_id: String, targets: Array, caster_id: String) -> void:
	"""Trigger cast animation + type-specific VFX when a card is played."""
	if _board == null or _board.game_state == null:
		return

	# Get card data for type-specific effects
	var card_data: Dictionary = {}
	if CardDatabase:
		card_data = CardDatabase.get_card(card_id) if CardDatabase.has_method("get_card") else {}

	var card_type: String = str(card_data.get("type", "Action"))

	# Find the specific caster champion by ID
	var champ := _board.game_state.get_champion(caster_id)
	if champ == null:
		return

	var visual := get_champion_visual(champ.unique_id)
	if visual == null:
		return

	# Beast form detection
	if champ.champion_name == "Beast" and card_data.size() > 0:
		_check_beast_transform(visual, card_data)
	visual.play_cast_animation()

	var champ_colors := VisualTheme.get_champion_colors(champ.champion_name)
	var primary_color: Color = champ_colors["primary"]

	# Type-specific VFX
	match card_type:
		"Action":
			# Bold energy burst from caster
			_board.trigger_cast_shimmer(champ.position)
			_board.trigger_cast_burst(champ.position, primary_color)
			# Energy beam to each target
			if targets.size() > 0:
				for target_id in targets:
					if target_id is String:
						var target_champ := _board.game_state.get_champion(target_id)
						if target_champ:
							_board.trigger_energy_beam(champ.position, target_champ.position, primary_color)
							_board.trigger_magic_swirl(target_champ.position, primary_color)
			# Sound: dramatic spell cast
			_play_sfx(VisualTheme.SFX_SPELL_CAST, 0.7)
			_play_random_sfx(VisualTheme.SFX_MAGIC, 0.5, 0.1)

		"Response":
			# Quick reactive shield flash
			_board.trigger_shield_flash(champ.position)
			_board.trigger_cast_shimmer(champ.position)
			# Magic swirl on targets
			if targets.size() > 0:
				for target_id in targets:
					if target_id is String:
						var target_champ := _board.game_state.get_champion(target_id)
						if target_champ:
							_board.trigger_magic_swirl(target_champ.position, primary_color)
			# Sound: quick reactive magic
			_play_random_sfx(VisualTheme.SFX_MAGIC, 0.5, 0.15)

		"Equipment":
			# Metallic attach glow
			_board.trigger_equip_glow(champ.position)
			_board.trigger_cast_shimmer(champ.position)
			# Sound: metallic equip
			_play_sfx(VisualTheme.SFX_MAGIC_IMPACT, 0.4, 1.3)


func _check_beast_transform(visual: ChampionVisual, card_data: Dictionary) -> void:
	"""Detect Beast cards and trigger appropriate transformation."""
	var card_name: String = card_data.get("name", "").to_lower()
	if "bear" in card_name or "maul" in card_name or "hibernate" in card_name:
		visual.set_beast_form("bear")
	elif "elk" in card_name or "antler" in card_name or "charge" in card_name:
		visual.set_beast_form("elk")
	elif "ape" in card_name or "primal" in card_name or "pound" in card_name:
		visual.set_beast_form("ape")


func _on_turn_ended(_player_id: int) -> void:
	"""Revert Beast forms at turn end."""
	if _board == null or _board.game_state == null:
		return
	for champ in _board.game_state.get_all_champions():
		if champ.champion_name == "Beast":
			var visual := get_champion_visual(champ.unique_id)
			if visual:
				visual.set_beast_form("base")


func _on_game_started(_p1_champs: Array, _p2_champs: Array) -> void:
	"""Start background music when game begins."""
	if not AudioManager:
		return
	var music := AudioManager.preload_sound(VisualTheme.MUSIC_BATTLE)
	if music:
		AudioManager.play_music(music, 2.0)


func _on_game_ended(_winner: int, _reason: String) -> void:
	"""Play victory sound and fade music."""
	if not AudioManager:
		return
	_play_sfx(VisualTheme.SFX_VICTORY, 0.8)
	AudioManager.stop_music(2.0)
