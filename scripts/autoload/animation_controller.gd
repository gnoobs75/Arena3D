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


# Screen flash state
var _flash_node: CanvasLayer = null
var _flash_rect: ColorRect = null

# Hitstop state
var _hitstop_active: bool = false

# Kill tracking for streaks
var _kill_count: int = 0
var _kills_this_turn: int = 0

# Card-specific VFX mapping: card_name -> { "vfx": String, "color": Color (optional), "flash": Color (optional) }
const CARD_VFX := {
	# Shaman - lightning
	"Lightning Strike": { "vfx": "lightning", "flash": Color(1, 1, 1, 0.3) },
	"Elemental Storm": { "vfx": "lightning", "flash": Color(1, 1, 1, 0.25) },
	"Thunderous Wrath": { "vfx": "lightning", "flash": Color(1, 1, 1, 0.3) },
	"Static Shock": { "vfx": "lightning" },
	"Super Charged": { "vfx": "lightning" },
	"Overload": { "vfx": "lightning" },
	# Redeemer - holy
	"Restoration": { "vfx": "holy", "flash": Color(1.0, 0.9, 0.4, 0.2) },
	"Resurrection": { "vfx": "holy", "flash": Color(1.0, 0.9, 0.4, 0.25) },
	"Spirit Strike": { "vfx": "holy" },
	"Inspire": { "vfx": "holy" },
	"Light Bomb": { "vfx": "shockwave_holy", "flash": Color(1.0, 0.95, 0.7, 0.3) },
	"Power Shield": { "vfx": "holy" },
	"Light Speed": { "vfx": "holy" },
	"Smite": { "vfx": "holy" },
	# DarkWizard - shadow
	"Shadow Bolt": { "vfx": "shadow", "flash": Color(0.3, 0.1, 0.4, 0.2) },
	"Black Hole": { "vfx": "shadow", "flash": Color(0.2, 0.05, 0.3, 0.25) },
	"Pit of Despair": { "vfx": "shadow" },
	"Mana Burn": { "vfx": "shadow" },
	"Underworld Terror": { "vfx": "shadow", "flash": Color(0.3, 0.1, 0.4, 0.2) },
	"Shadow Burst": { "vfx": "shadow" },
	"Lifetap": { "vfx": "shadow" },
	"Dark Pact": { "vfx": "shadow" },
	# Beast - nature
	"Natures Wrath": { "vfx": "leaf" },
	"Elk Restoration": { "vfx": "leaf" },
	"Natures Gift": { "vfx": "leaf" },
	"Bear Intimidation": { "vfx": "shockwave_nature" },
	"Elk Infusion": { "vfx": "leaf" },
	"Natures Resilience": { "vfx": "leaf" },
	"Maul": { "vfx": "ground_crack" },
	# Brute - physical
	"Ground Pound": { "vfx": "ground_crack" },
	"Heave": { "vfx": "ground_crack" },
	"Shove Off": { "vfx": "ground_crack" },
	"No Bullying": { "vfx": "ground_crack" },
	"Tantrum": { "vfx": "shockwave_earth" },
	"Friends Forever": { "vfx": "ground_crack" },
	"Thick Skin": { "vfx": "ground_crack" },
	# Barbarian - blood/rage
	"Whirlwind": { "vfx": "blood" },
	"Critical Strike": { "vfx": "blood" },
	"Head Smash": { "vfx": "blood" },
	"Blood Shield": { "vfx": "blood" },
	"Enrage": { "vfx": "blood" },
	"Pursuit": { "vfx": "blood" },
	"Refuel": { "vfx": "blood" },
	"Quick Recovery": { "vfx": "blood" },
	# Berserker - chaos
	"MAD": { "vfx": "blood", "flash": Color(0.6, 0.1, 0.1, 0.2) },
	"Bloodthirsty": { "vfx": "blood" },
	"Commanding Shout": { "vfx": "shockwave_rage" },
	"Dual Wield": { "vfx": "blood" },
	"Frenzy": { "vfx": "blood" },
	# Ranger - arrows
	"Rain of Arrows": { "vfx": "arrows" },
	"Power Shot": { "vfx": "arrows" },
	"Bear Trap": { "vfx": "chain" },
	"Rapid Fire": { "vfx": "arrows" },
	"Leech": { "vfx": "arrows" },
	"Eagle Eye": { "vfx": "arrows" },
	# Alchemist - flasks (each with unique color)
	"Potion Flask": { "vfx": "flask", "color": Color(0.3, 0.9, 0.15) },
	"Fire Flask": { "vfx": "flask", "color": Color(0.95, 0.4, 0.1) },
	"Frost Flask": { "vfx": "flask", "color": Color(0.3, 0.7, 1.0) },
	"Poison Flask": { "vfx": "flask", "color": Color(0.5, 0.9, 0.1) },
	"Smoke Flask": { "vfx": "flask", "color": Color(0.5, 0.5, 0.5) },
	"Acid Bomb": { "vfx": "flask", "color": Color(0.7, 0.9, 0.0) },
	"Smoke Bomb": { "vfx": "smoke" },
	"Spectre's Essence": { "vfx": "flask", "color": Color(0.6, 0.3, 0.8) },
	"Experimental Brew": { "vfx": "flask", "color": Color(0.9, 0.2, 0.5) },
	# Illusionist - mirrors
	"Now You See Me": { "vfx": "mirror" },
	"Confuse": { "vfx": "mirror" },
	"Grand Finale": { "vfx": "mirror", "flash": Color(0.8, 0.5, 0.9, 0.2) },
	"Reshuffle": { "vfx": "mirror" },
	"Teleport": { "vfx": "mirror" },
	"Gamble": { "vfx": "mirror" },
	"House Odds": { "vfx": "mirror" },
	"Guess Again": { "vfx": "mirror" },
	# Burglar - daggers
	"Surprise Attack": { "vfx": "dagger" },
	"Vanish": { "vfx": "smoke" },
	"From the Shadows": { "vfx": "dagger" },
	"Quick Hit": { "vfx": "dagger" },
	"Pick Pocket": { "vfx": "dagger" },
	"Jackpot": { "vfx": "dagger" },
	"Blinded": { "vfx": "dagger" },
	"Low Blow": { "vfx": "dagger" },
	# Confessor - chains/dark
	"Denial": { "vfx": "chain" },
	"Betrayal": { "vfx": "shadow" },
	"Blasphemy": { "vfx": "shadow" },
	"Atone": { "vfx": "chain" },
	"Life Payment": { "vfx": "shadow" },
	"Secret Revealed": { "vfx": "shadow" },
	"Martyr": { "vfx": "holy" },
	"Silence": { "vfx": "chain" },
}


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
	EventBus.game_started.connect(_on_game_started_reset)
	EventBus.game_ended.connect(_on_game_ended)

	# Response window drama
	EventBus.response_window_opened.connect(_on_response_window_opened)

	# AI thinking indicator
	EventBus.ai_thinking_started.connect(_on_ai_thinking_started)
	EventBus.ai_thinking_finished.connect(_on_ai_thinking_finished)


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


func setup_flash_overlay(game_node: Node) -> void:
	"""Create the screen flash overlay. Called by game.gd after scene setup."""
	_flash_node = CanvasLayer.new()
	_flash_node.layer = 10
	game_node.add_child(_flash_node)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_node.add_child(_flash_rect)


func trigger_screen_flash(color: Color, duration: float = 0.15) -> void:
	"""Flash the screen with a color overlay that fades out."""
	if _flash_rect == null:
		return
	_flash_rect.color = color
	var tween := _flash_rect.create_tween()
	tween.tween_property(_flash_rect, "color:a", 0.0, duration).set_ease(Tween.EASE_OUT)


func trigger_hitstop(duration_ms: float = 60.0) -> void:
	"""Brief freeze-frame on heavy impact. Pauses the scene tree momentarily."""
	if _hitstop_active:
		return
	_hitstop_active = true
	get_tree().paused = true
	await get_tree().create_timer(duration_ms / 1000.0, true, false, true).timeout
	get_tree().paused = false
	_hitstop_active = false


func trigger_kill_slowmo(duration: float = 0.5) -> void:
	"""Dramatic slow-motion on champion kill."""
	var original_scale := Engine.time_scale
	Engine.time_scale = 0.25
	# Screen flash for dramatic effect
	trigger_screen_flash(Color(1.0, 0.9, 0.7, 0.15), 0.4)
	await get_tree().create_timer(duration * 0.25, true).timeout  # Actual wait is shorter due to time_scale
	# Ramp back to normal
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_method(func(v: float): Engine.time_scale = v, 0.25, original_scale, 0.15)


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
	# Hitstop on heavy damage - brief freeze frame for impact
	if amount >= 4:
		trigger_hitstop(70.0)
	elif amount >= 3:
		trigger_hitstop(40.0)
	# Screen shake on heavy damage
	if amount >= 6:
		trigger_screen_shake(4.0, 0.35)
	elif amount >= 4:
		trigger_screen_shake(2.5, 0.25)
	elif amount >= 3:
		trigger_screen_shake(1.5, 0.15)
	# Floating damage number
	_spawn_floating_number(champion_id, amount, false)
	# Pain sound on heavy damage
	if amount >= 4:
		_play_sfx(VisualTheme.SFX_PAIN, 0.6, 1.0 + sin(float(Time.get_ticks_msec()) * 0.001) * 0.15)


func _on_champion_healed(champion_id: String, amount: int, _source: String) -> void:
	"""Trigger heal animation when champion is healed."""
	var visual := get_champion_visual(champion_id)
	if visual and amount > 0:
		visual.play_heal_animation()
	# Floating heal number
	if amount > 0:
		_spawn_floating_number(champion_id, amount, true)
	# Heal sparkle VFX + SFX
	if _board and _board.game_state and amount > 0:
		var champ := _board.game_state.get_champion(champion_id)
		if champ:
			_board.trigger_heal_sparkles(champ.position)
		_play_sfx(VisualTheme.SFX_HEAL, 0.5, 1.1)


func _on_champion_died(champion_id: String, _killer_id: String) -> void:
	"""Trigger death animation when champion dies."""
	# Kill slow-mo for dramatic effect
	trigger_kill_slowmo(0.5)
	var visual := get_champion_visual(champion_id)
	if visual:
		visual.play_death_animation()
	# Kill streak tracking
	_kill_count += 1
	_kills_this_turn += 1
	_announce_kill_streak(champion_id, _killer_id)
	# Death VFX + SFX + screen shake
	if _board and _board.game_state:
		var champ := _board.game_state.get_champion(champion_id)
		if champ:
			_board.trigger_death_vfx(champ.position)
	trigger_screen_shake(5.0, 0.4)
	trigger_screen_flash(Color(0.6, 0.05, 0.05, 0.2), 0.1)
	# Add blood scar at death position
	if _board and _board.game_state:
		var dead_champ := _board.game_state.get_champion(champion_id)
		if dead_champ:
			_board.add_battle_scar(dead_champ.position, "blood", Color(0.35, 0.05, 0.02, 0.35))
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
	"""Trigger cast animation + card-specific or type-specific VFX when a card is played."""
	if _board == null or _board.game_state == null:
		return

	# Get card data for type-specific effects
	var card_data: Dictionary = {}
	if CardDatabase:
		card_data = CardDatabase.get_card(card_id) if CardDatabase.has_method("get_card") else {}

	var card_type: String = str(card_data.get("type", "Action"))
	var card_name: String = str(card_data.get("name", card_id))

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

	# Resolve target champions
	var target_champs: Array = []
	for target_id in targets:
		if target_id is String:
			var tc := _board.game_state.get_champion(target_id)
			if tc:
				target_champs.append(tc)

	# Check card-specific VFX first
	if CARD_VFX.has(card_name):
		var vfx_info: Dictionary = CARD_VFX[card_name]
		var vfx_type: String = str(vfx_info.get("vfx", ""))
		var vfx_color: Color = vfx_info.get("color", primary_color) as Color
		var flash_color = vfx_info.get("flash", null)

		# Always do cast shimmer from caster
		_board.trigger_cast_shimmer(champ.position)

		# Dispatch card-specific VFX
		_trigger_card_vfx(vfx_type, champ, target_champs, vfx_color)

		# Screen flash
		if flash_color != null:
			trigger_screen_flash(flash_color as Color, 0.15)

		# Sound based on VFX type
		match vfx_type:
			"lightning":
				_play_sfx(VisualTheme.SFX_SPELL_CAST, 0.7)
				_play_random_sfx(VisualTheme.SFX_MAGIC, 0.6, 0.15)
			"holy":
				_play_sfx(VisualTheme.SFX_SPELL_CAST, 0.6)
				_play_sfx(VisualTheme.SFX_HEAL, 0.4, 1.2)
			"shadow":
				_play_sfx(VisualTheme.SFX_SPELL_CAST, 0.7)
				_play_random_sfx(VisualTheme.SFX_MAGIC, 0.5, 0.1)
			"dagger":
				_play_random_sfx(VisualTheme.SFX_HIT, 0.5, 0.2)
			"blood", "ground_crack":
				_play_random_sfx(VisualTheme.SFX_HIT, 0.6, 0.15)
			_:
				_play_sfx(VisualTheme.SFX_SPELL_CAST, 0.5)
				_play_random_sfx(VisualTheme.SFX_MAGIC, 0.4, 0.1)
		return

	# Fallback to generic type-based VFX
	match card_type:
		"Action":
			_board.trigger_cast_shimmer(champ.position)
			_board.trigger_cast_burst(champ.position, primary_color)
			for tc in target_champs:
				_board.trigger_energy_beam(champ.position, tc.position, primary_color)
				_board.trigger_magic_swirl(tc.position, primary_color)
			_play_sfx(VisualTheme.SFX_SPELL_CAST, 0.7)
			_play_random_sfx(VisualTheme.SFX_MAGIC, 0.5, 0.1)

		"Response":
			_board.trigger_shield_flash(champ.position)
			_board.trigger_cast_shimmer(champ.position)
			for tc in target_champs:
				_board.trigger_magic_swirl(tc.position, primary_color)
			_play_random_sfx(VisualTheme.SFX_MAGIC, 0.5, 0.15)

		"Equipment":
			_board.trigger_equip_glow(champ.position)
			_board.trigger_cast_shimmer(champ.position)
			_play_sfx(VisualTheme.SFX_MAGIC_IMPACT, 0.4, 1.3)


func _trigger_card_vfx(vfx_type: String, caster: ChampionState, target_champs: Array, color: Color) -> void:
	"""Dispatch card-specific VFX to the appropriate board trigger methods."""
	match vfx_type:
		"lightning":
			if target_champs.size() > 0:
				for tc in target_champs:
					_board.trigger_lightning_arc(caster.position, tc.position, color)
					_board.add_battle_scar(tc.position, "scorch", Color(0.15, 0.12, 0.08, 0.25))
			else:
				_board.trigger_lightning_arc(caster.position, caster.position + Vector2i(2, 0), color)
		"holy":
			_board.trigger_holy_pillar(caster.position)
			for tc in target_champs:
				_board.trigger_holy_pillar(tc.position)
		"shadow":
			_board.trigger_shadow_tendrils(caster.position)
			for tc in target_champs:
				_board.trigger_shadow_tendrils(tc.position)
		"leaf":
			_board.trigger_leaf_swirl(caster.position)
			for tc in target_champs:
				_board.trigger_leaf_swirl(tc.position)
		"ground_crack":
			for tc in target_champs:
				_board.trigger_ground_crack(tc.position)
				_board.trigger_shockwave(tc.position, Color(0.5, 0.4, 0.25))
				_board.add_battle_scar(tc.position, "crack", Color(0.2, 0.18, 0.12, 0.3))
			if target_champs.is_empty():
				_board.trigger_ground_crack(caster.position)
				_board.add_battle_scar(caster.position, "crack", Color(0.2, 0.18, 0.12, 0.3))
		"blood":
			_board.trigger_blood_splatter(caster.position)
			for tc in target_champs:
				_board.trigger_blood_splatter(tc.position)
		"arrows":
			for tc in target_champs:
				_board.trigger_arrow_volley(tc.position)
			if target_champs.is_empty():
				_board.trigger_arrow_volley(caster.position)
		"flask":
			for tc in target_champs:
				_board.trigger_flask_splash(tc.position, color)
			if target_champs.is_empty():
				_board.trigger_flask_splash(caster.position, color)
		"mirror":
			_board.trigger_mirror_shards(caster.position)
			for tc in target_champs:
				_board.trigger_mirror_shards(tc.position)
		"dagger":
			if target_champs.size() > 0:
				for tc in target_champs:
					_board.trigger_dagger_glint(caster.position, tc.position)
			else:
				_board.trigger_dagger_glint(caster.position, caster.position + Vector2i(1, 0))
		"chain":
			for tc in target_champs:
				_board.trigger_chain_wrap(tc.position)
			if target_champs.is_empty():
				_board.trigger_chain_wrap(caster.position)
		"smoke":
			_board.trigger_smoke_poof(caster.position)
		"shockwave_holy":
			_board.trigger_shockwave(caster.position, Color(1.0, 0.9, 0.5))
			_board.trigger_holy_pillar(caster.position)
		"shockwave_nature":
			_board.trigger_shockwave(caster.position, Color(0.3, 0.6, 0.2))
			_board.trigger_leaf_swirl(caster.position)
		"shockwave_earth":
			_board.trigger_shockwave(caster.position, Color(0.5, 0.4, 0.25))
			_board.trigger_ground_crack(caster.position)
		"shockwave_rage":
			_board.trigger_shockwave(caster.position, Color(0.8, 0.2, 0.1))
			_board.trigger_blood_splatter(caster.position)


func _check_beast_transform(visual: ChampionVisual, card_data: Dictionary) -> void:
	"""Detect Beast cards and trigger appropriate transformation."""
	var card_name: String = card_data.get("name", "").to_lower()
	if "bear" in card_name or "maul" in card_name or "hibernate" in card_name:
		visual.set_beast_form("bear")
	elif "elk" in card_name or "antler" in card_name or "charge" in card_name:
		visual.set_beast_form("elk")
	elif "ape" in card_name or "primal" in card_name or "pound" in card_name:
		visual.set_beast_form("ape")


var _ai_thinking_bubble: Node2D = null

func _on_ai_thinking_started(player_id: int) -> void:
	"""Show thinking bubble over AI's first alive champion."""
	_remove_ai_thinking_bubble()
	if _board == null or _board.game_state == null:
		return
	var champs := _board.game_state.get_champions(player_id)
	for champ in champs:
		if champ.is_alive():
			var visual := get_champion_visual(champ.unique_id)
			if visual:
				_ai_thinking_bubble = AIThinkingBubble.new()
				visual.add_child(_ai_thinking_bubble)
				_ai_thinking_bubble.position = Vector2(0, -60)
			break


func _on_ai_thinking_finished(_player_id: int) -> void:
	"""Remove thinking bubble."""
	_remove_ai_thinking_bubble()


func _remove_ai_thinking_bubble() -> void:
	if _ai_thinking_bubble and is_instance_valid(_ai_thinking_bubble):
		_ai_thinking_bubble.queue_free()
		_ai_thinking_bubble = null


func _on_response_window_opened(_trigger: String, _context: Dictionary) -> void:
	"""Dramatic edge flash when response window opens."""
	show_response_drama()


func _on_turn_ended(_player_id: int) -> void:
	"""Revert Beast forms at turn end. Fade battle scars. Reset per-turn kills."""
	_kills_this_turn = 0
	if _board == null or _board.game_state == null:
		return
	for champ in _board.game_state.get_all_champions():
		if champ.champion_name == "Beast":
			var visual := get_champion_visual(champ.unique_id)
			if visual:
				visual.set_beast_form("base")
	# Fade battle scars each turn
	_board.fade_battle_scars()


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


func _on_game_started_reset(_p1: Array, _p2: Array) -> void:
	"""Reset kill tracking at game start."""
	_kill_count = 0
	_kills_this_turn = 0


# === Floating Damage/Heal Numbers ===

func _spawn_floating_number(champion_id: String, amount: int, is_heal: bool) -> void:
	"""Spawn a floating number above a champion on the board."""
	if _board == null or _board.game_state == null:
		return
	var champ := _board.game_state.get_champion(champion_id)
	if champ == null:
		return
	# Get screen position from board
	var tile_size := 64.0 * _board.scale.x
	var board_pos := _board.position
	var margin_offset := 24.0 * _board.scale.x  # coord margin
	var screen_pos := board_pos + Vector2(
		float(champ.position.x) * tile_size + margin_offset + tile_size * 0.5,
		float(champ.position.y) * tile_size + margin_offset
	)
	var number_node := FloatingNumber.new()
	number_node.setup(amount, is_heal, screen_pos)
	# Add to scene tree at root level so it's above everything
	var root := get_tree().root
	if root.get_child_count() > 0:
		root.get_child(0).add_child(number_node)


# === Kill Streak Announcements ===

const STREAK_TEXTS := {
	1: "FIRST BLOOD!",
	2: "DOUBLE KILL!",
	3: "TRIPLE KILL!",
	4: "QUADRA KILL!",
}

func _announce_kill_streak(dead_id: String, killer_id: String) -> void:
	"""Show kill streak banner for dramatic moments."""
	var streak_text := ""
	if _kill_count == 1:
		streak_text = "FIRST BLOOD!"
	elif _kills_this_turn >= 2:
		streak_text = STREAK_TEXTS.get(_kills_this_turn, "KILLING SPREE!")

	if streak_text.is_empty():
		return

	# Get killer name for flavor
	var killer_name := ""
	if _board and _board.game_state and not killer_id.is_empty():
		var killer := _board.game_state.get_champion(killer_id)
		if killer:
			killer_name = killer.champion_name

	_spawn_announcement_banner(streak_text, killer_name)

	# Trigger crowd wild cheer
	if _board:
		_board.trigger_crowd_reaction("kill")


func _spawn_announcement_banner(text: String, subtitle: String = "") -> void:
	"""Show a dramatic center-screen announcement that slides in and out."""
	var root := get_tree().root
	if root.get_child_count() == 0:
		return
	var game_node := root.get_child(0)
	var banner := AnnouncementBanner.new()
	banner.setup(text, subtitle)
	game_node.add_child(banner)


# === Response Window Drama ===

func show_response_drama() -> void:
	"""Flash screen edges when response window opens."""
	trigger_screen_flash(Color(0.3, 0.5, 1.0, 0.12), 0.3)


# === Champion Entrance ===

const CHAMPION_TITLES := {
	"Brute": "The Unstoppable Force",
	"Ranger": "The Sharpshooter",
	"Beast": "The Shapeshifter",
	"Redeemer": "The Divine Light",
	"Confessor": "The Dark Shepherd",
	"Barbarian": "The Bloodsworn",
	"Burglar": "The Shadow",
	"Berserker": "The Unhinged",
	"Shaman": "The Stormcaller",
	"Illusionist": "The Grand Deceiver",
	"DarkWizard": "The Void Walker",
	"Alchemist": "The Mad Genius",
}

func show_entrance_nameplate(champion_name: String, player_id: int) -> void:
	"""Show a dramatic WWE-style nameplate for champion entrance."""
	var root := get_tree().root
	if root.get_child_count() == 0:
		return
	var game_node := root.get_child(0)
	var title: String = CHAMPION_TITLES.get(champion_name, "The Challenger")
	var champ_colors := VisualTheme.get_champion_colors(champion_name)
	var nameplate := EntranceNameplate.new()
	nameplate.setup(champion_name, title, player_id, champ_colors["primary"])
	game_node.add_child(nameplate)
	# Dramatic screen flash in champion's color
	var flash_color: Color = champ_colors["primary"]
	flash_color.a = 0.15
	trigger_screen_flash(flash_color, 0.3)


# === Inner Classes ===

class FloatingNumber extends Node2D:
	"""Floating damage/heal number that pops up and fades."""
	var _amount: int = 0
	var _is_heal: bool = false
	var _elapsed: float = 0.0
	var _start_pos: Vector2
	const DURATION := 1.2
	const RISE_SPEED := 80.0

	func setup(amount: int, is_heal: bool, pos: Vector2) -> void:
		_amount = amount
		_is_heal = is_heal
		_start_pos = pos
		position = pos
		z_index = 200

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= DURATION:
			queue_free()
			return
		# Rise up
		position.y = _start_pos.y - _elapsed * RISE_SPEED
		# Slight horizontal drift
		position.x = _start_pos.x + sin(_elapsed * 3.0) * 8.0
		queue_redraw()

	func _draw() -> void:
		var progress := _elapsed / DURATION
		# Scale: pop in big then shrink
		var s := 1.0
		if progress < 0.15:
			s = lerpf(0.3, 1.5, progress / 0.15)
		elif progress < 0.3:
			s = lerpf(1.5, 1.0, (progress - 0.15) / 0.15)
		# Fade out in last 40%
		var alpha := 1.0
		if progress > 0.6:
			alpha = lerpf(1.0, 0.0, (progress - 0.6) / 0.4)

		var text := "+%d" % _amount if _is_heal else "-%d" % _amount
		var color: Color
		if _is_heal:
			color = Color(0.3, 1.0, 0.3, alpha)
		else:
			color = Color(1.0, 0.2, 0.15, alpha)

		var font := ThemeDB.fallback_font
		var font_size := int(22.0 * s)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		# Shadow
		draw_string(font, Vector2(-text_size.x / 2 + 1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0, 0, 0, alpha * 0.6))
		# Main text
		draw_string(font, Vector2(-text_size.x / 2, 0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)


class AnnouncementBanner extends CanvasLayer:
	"""Full-screen announcement banner that slides in dramatically."""
	var _banner: ColorRect
	var _label: Label
	var _subtitle_label: Label

	func _init() -> void:
		layer = 15

	func setup(text: String, subtitle: String = "") -> void:
		# Background banner
		_banner = ColorRect.new()
		_banner.color = Color(0.08, 0.02, 0.02, 0.92)
		_banner.set_anchors_preset(Control.PRESET_CENTER)
		_banner.offset_left = -600
		_banner.offset_right = 600
		_banner.offset_top = -40
		_banner.offset_bottom = 40
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_banner)

		# Gold trim top
		var trim_top := ColorRect.new()
		trim_top.color = Color(0.85, 0.65, 0.15)
		trim_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
		trim_top.offset_bottom = 3
		trim_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.add_child(trim_top)

		# Gold trim bottom
		var trim_bot := ColorRect.new()
		trim_bot.color = Color(0.85, 0.65, 0.15)
		trim_bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		trim_bot.offset_top = -3
		trim_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.add_child(trim_bot)

		# Main text
		_label = Label.new()
		_label.text = text
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.add_theme_font_size_override("font_size", 36)
		_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		_label.add_theme_constant_override("shadow_offset_x", 2)
		_label.add_theme_constant_override("shadow_offset_y", 2)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.add_child(_label)

		# Subtitle (killer name)
		if not subtitle.is_empty():
			_subtitle_label = Label.new()
			_subtitle_label.text = subtitle
			_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_subtitle_label.set_anchors_preset(Control.PRESET_CENTER)
			_subtitle_label.offset_top = 20
			_subtitle_label.offset_bottom = 45
			_subtitle_label.offset_left = -200
			_subtitle_label.offset_right = 200
			_subtitle_label.add_theme_font_size_override("font_size", 16)
			_subtitle_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
			_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_banner.add_child(_subtitle_label)

		# Animate: slide in from right, hold, slide out left
		_banner.position.x = 1920
		_banner.modulate.a = 0.0
		var tween := _banner.create_tween()
		tween.tween_property(_banner, "position:x", 0.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.parallel().tween_property(_banner, "modulate:a", 1.0, 0.1)
		tween.tween_interval(1.2)
		tween.tween_property(_banner, "position:x", -1920.0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tween.parallel().tween_property(_banner, "modulate:a", 0.0, 0.15)
		tween.tween_callback(queue_free)


class AIThinkingBubble extends Node2D:
	"""Pulsing '...' speech bubble above AI champion."""
	var _elapsed: float = 0.0

	func _ready() -> void:
		z_index = 100

	func _process(delta: float) -> void:
		_elapsed += delta
		queue_redraw()

	func _draw() -> void:
		# Bubble background
		var bubble_w := 36.0
		var bubble_h := 20.0
		var bob := sin(_elapsed * 2.5) * 3.0
		var bg_rect := Rect2(-bubble_w / 2, -bubble_h / 2 + bob, bubble_w, bubble_h)
		draw_rect(bg_rect, Color(0.15, 0.15, 0.2, 0.9), true)
		draw_rect(bg_rect, Color(0.6, 0.6, 0.7, 0.8), false, 1.5)
		# Tail triangle pointing down
		var tail := PackedVector2Array([
			Vector2(-4, bubble_h / 2 + bob),
			Vector2(4, bubble_h / 2 + bob),
			Vector2(0, bubble_h / 2 + 8 + bob)
		])
		draw_colored_polygon(tail, Color(0.15, 0.15, 0.2, 0.9))
		# Animated dots
		var font := ThemeDB.fallback_font
		var dots := ""
		var dot_count := int(fmod(_elapsed * 2.0, 4.0))
		for i in range(3):
			if i < dot_count:
				dots += "."
			else:
				dots += " "
		draw_string(font, Vector2(-10, 5 + bob), dots, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.9, 0.9, 1.0))


class EntranceNameplate extends CanvasLayer:
	"""WWE-style entrance nameplate - champion name + title slides in dramatically."""
	var _panel: Control
	var _champion_color: Color

	func _init() -> void:
		layer = 14

	func setup(champ_name: String, title: String, player_id: int, color: Color) -> void:
		_champion_color = color

		# Full-width panel container
		_panel = Control.new()
		_panel.set_anchors_preset(Control.PRESET_CENTER)
		_panel.offset_left = -500
		_panel.offset_right = 500
		_panel.offset_top = -55
		_panel.offset_bottom = 55
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_panel)

		# Background - dark with champion color accent
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.03, 0.08, 0.95)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(bg)

		# Champion color accent bar (left side)
		var accent := ColorRect.new()
		accent.color = color
		accent.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		accent.offset_right = 6
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(accent)

		# Champion color accent bar (right side)
		var accent_r := ColorRect.new()
		accent_r.color = color
		accent_r.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		accent_r.offset_left = -6
		accent_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(accent_r)

		# Gold trim top
		var trim_top := ColorRect.new()
		trim_top.color = Color(0.85, 0.65, 0.15)
		trim_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
		trim_top.offset_bottom = 2
		trim_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(trim_top)

		# Gold trim bottom
		var trim_bot := ColorRect.new()
		trim_bot.color = Color(0.85, 0.65, 0.15)
		trim_bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		trim_bot.offset_top = -2
		trim_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(trim_bot)

		# Player label (small, top)
		var player_label := Label.new()
		player_label.text = "PLAYER %d" % player_id
		player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		player_label.offset_top = 6
		player_label.offset_bottom = 22
		player_label.offset_left = -200
		player_label.offset_right = 200
		player_label.add_theme_font_size_override("font_size", 11)
		player_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(player_label)

		# Champion name (large, center)
		var name_label := Label.new()
		name_label.text = champ_name.to_upper()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.set_anchors_preset(Control.PRESET_CENTER)
		name_label.offset_top = -8
		name_label.offset_bottom = 28
		name_label.offset_left = -300
		name_label.offset_right = 300
		name_label.add_theme_font_size_override("font_size", 38)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.add_theme_color_override("font_shadow_color", color.darkened(0.5))
		name_label.add_theme_constant_override("shadow_offset_x", 2)
		name_label.add_theme_constant_override("shadow_offset_y", 2)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(name_label)

		# Title (small, below name)
		var title_label := Label.new()
		title_label.text = "~ %s ~" % title
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		title_label.offset_top = -24
		title_label.offset_bottom = -6
		title_label.offset_left = -200
		title_label.offset_right = 200
		title_label.add_theme_font_size_override("font_size", 14)
		title_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
		title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(title_label)

		# Animate: slide in from side based on player, hold, slide out
		var slide_from := 1200.0 if player_id == 1 else -1200.0
		var slide_to := -1200.0 if player_id == 1 else 1200.0
		_panel.position.x = slide_from
		_panel.modulate.a = 0.0

		var tween := _panel.create_tween()
		# Slide in
		tween.tween_property(_panel, "position:x", 0.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.parallel().tween_property(_panel, "modulate:a", 1.0, 0.12)
		# Hold
		tween.tween_interval(1.0)
		# Slide out opposite direction
		tween.tween_property(_panel, "position:x", slide_to, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tween.parallel().tween_property(_panel, "modulate:a", 0.0, 0.15)
		tween.tween_callback(queue_free)
