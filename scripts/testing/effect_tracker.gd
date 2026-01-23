class_name EffectTracker
extends RefCounted
## Tracks card effects and detects no-op plays
## Hooks into EffectProcessor signals to monitor actual effect outcomes


signal card_play_tracked(card_name: String, result: EffectResult)
signal noop_detected(card_name: String, reason: String)


## Connected effect processor
var effect_processor: EffectProcessor

## Connected game state
var game_state: GameState

## Current card being tracked
var _current_card: String = ""
var _current_caster_id: String = ""
var _current_player_id: int = 0
var _tracking_active: bool = false

## Effect counters for current card
var _damage_dealt: int = 0
var _healing_done: int = 0
var _buffs_applied: int = 0
var _debuffs_applied: int = 0
var _movements_caused: int = 0
var _cards_drawn: int = 0
var _mana_changed: int = 0
var _stat_mods_applied: int = 0

## Detailed tracking
var _damage_targets: Array[String] = []
var _heal_targets: Array[String] = []
var _buff_details: Array[Dictionary] = []
var _debuff_details: Array[Dictionary] = []
var _movement_details: Array[Dictionary] = []

## State tracking for additional detection
var _hp_before: Dictionary = {}  # champion_id -> hp
var _hand_size_before: int = 0


func _init() -> void:
	_damage_targets = []
	_heal_targets = []
	_buff_details = []
	_debuff_details = []
	_movement_details = []
	_hp_before = {}


func connect_to_processor(processor: EffectProcessor, state: GameState) -> void:
	"""Connect to an EffectProcessor to track effects."""
	effect_processor = processor
	game_state = state

	# Connect to effect signals
	if not processor.damage_dealt.is_connected(_on_damage_dealt):
		processor.damage_dealt.connect(_on_damage_dealt)
	if not processor.healing_done.is_connected(_on_healing_done):
		processor.healing_done.connect(_on_healing_done)
	if not processor.buff_applied.is_connected(_on_buff_applied):
		processor.buff_applied.connect(_on_buff_applied)
	if not processor.debuff_applied.is_connected(_on_debuff_applied):
		processor.debuff_applied.connect(_on_debuff_applied)
	if not processor.champion_moved.is_connected(_on_champion_moved):
		processor.champion_moved.connect(_on_champion_moved)
	if not processor.effect_applied.is_connected(_on_effect_applied):
		processor.effect_applied.connect(_on_effect_applied)


func disconnect_from_processor() -> void:
	"""Disconnect from the effect processor."""
	if effect_processor != null:
		if effect_processor.damage_dealt.is_connected(_on_damage_dealt):
			effect_processor.damage_dealt.disconnect(_on_damage_dealt)
		if effect_processor.healing_done.is_connected(_on_healing_done):
			effect_processor.healing_done.disconnect(_on_healing_done)
		if effect_processor.buff_applied.is_connected(_on_buff_applied):
			effect_processor.buff_applied.disconnect(_on_buff_applied)
		if effect_processor.debuff_applied.is_connected(_on_debuff_applied):
			effect_processor.debuff_applied.disconnect(_on_debuff_applied)
		if effect_processor.champion_moved.is_connected(_on_champion_moved):
			effect_processor.champion_moved.disconnect(_on_champion_moved)
		if effect_processor.effect_applied.is_connected(_on_effect_applied):
			effect_processor.effect_applied.disconnect(_on_effect_applied)
	effect_processor = null
	game_state = null


func begin_card_tracking(card_name: String, caster_id: String, player_id: int) -> void:
	"""Start tracking effects for a card play."""
	_current_card = card_name
	_current_caster_id = caster_id
	_current_player_id = player_id
	_tracking_active = true

	# Reset counters
	_damage_dealt = 0
	_healing_done = 0
	_buffs_applied = 0
	_debuffs_applied = 0
	_movements_caused = 0
	_cards_drawn = 0
	_mana_changed = 0
	_stat_mods_applied = 0

	# Reset details
	_damage_targets = []
	_heal_targets = []
	_buff_details = []
	_debuff_details = []
	_movement_details = []

	# Capture HP before for additional validation
	_hp_before = {}
	if game_state != null:
		for champion: ChampionState in game_state.get_all_champions():
			_hp_before[champion.unique_id] = champion.current_hp
		_hand_size_before = game_state.get_hand(player_id).size()


func end_card_tracking() -> EffectResult:
	"""End tracking and return the result with no-op detection."""
	_tracking_active = false

	var result := EffectResult.new()
	result.card_name = _current_card
	result.caster_id = _current_caster_id
	result.player_id = _current_player_id

	# Copy tracked values
	result.damage_dealt = _damage_dealt
	result.healing_done = _healing_done
	result.buffs_applied = _buffs_applied
	result.debuffs_applied = _debuffs_applied
	result.movements_caused = _movements_caused
	result.cards_drawn = _cards_drawn
	result.mana_changed = _mana_changed

	# Copy details
	result.damage_targets = _damage_targets.duplicate()
	result.heal_targets = _heal_targets.duplicate()
	result.buff_details = _buff_details.duplicate()
	result.debuff_details = _debuff_details.duplicate()
	result.movement_details = _movement_details.duplicate()

	# Determine if no-op and why
	result.is_noop = _determine_if_noop()
	result.noop_reason = _determine_noop_reason()

	# Emit signal
	card_play_tracked.emit(_current_card, result)
	if result.is_noop:
		noop_detected.emit(_current_card, result.noop_reason)

	return result


func _determine_if_noop() -> bool:
	"""Determine if the card play was a no-op."""
	# Check if card has statMod effects - these don't emit signals but still work
	var card_data := CardDatabase.get_card(_current_card)
	var effects: Array = card_data.get("effect", [])
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		# statMod, gainmana, lockmana, stealmana all work without signals
		if etype in ["statmod", "gainmana", "lockmana", "stealmana"]:
			return false

	# A card is a no-op if ALL effects had no impact
	return (
		_damage_dealt == 0 and
		_healing_done == 0 and
		_buffs_applied == 0 and
		_debuffs_applied == 0 and
		_movements_caused == 0 and
		_cards_drawn == 0 and
		_mana_changed == 0
	)


func _determine_noop_reason() -> String:
	"""Determine the reason for a no-op, if applicable."""
	if not _determine_if_noop():
		return ""

	# Get card data to understand expected effects
	var card_data := CardDatabase.get_card(_current_card)
	if card_data.is_empty():
		return "unknown_card"

	var effects: Array = card_data.get("effect", [])
	if effects.is_empty():
		return "no_effects_defined"

	# Analyze expected vs actual for each effect type
	var reasons: Array[String] = []

	for effect: Dictionary in effects:
		var effect_type: String = str(effect.get("type", ""))
		match effect_type:
			"damage":
				if _damage_dealt == 0:
					reasons.append(_analyze_damage_noop(effect))
			"heal":
				if _healing_done == 0:
					reasons.append(_analyze_heal_noop(effect))
			"buff":
				if _buffs_applied == 0:
					reasons.append("buff_not_applied")
			"debuff":
				if _debuffs_applied == 0:
					reasons.append("debuff_not_applied")
			"move":
				if _movements_caused == 0:
					reasons.append(_analyze_move_noop(effect))
			"draw":
				if _cards_drawn == 0:
					reasons.append("deck_empty")
			"statMod":
				# statMods don't always show in our tracking
				pass

	# Return most relevant reason
	if reasons.is_empty():
		return "unknown_reason"

	# Filter out empty reasons
	var filtered: Array[String] = []
	for reason: String in reasons:
		if not reason.is_empty():
			filtered.append(reason)

	if filtered.is_empty():
		return "unknown_reason"

	return filtered[0]


func _analyze_damage_noop(effect: Dictionary) -> String:
	"""Analyze why damage effect did nothing."""
	if game_state == null:
		return "no_game_state"

	var target_type: String = str(effect.get("target", ""))

	# Check if there were valid targets
	var caster := game_state.get_champion(_current_caster_id)
	if caster == null:
		return "caster_not_found"

	var opponent_id: int = 2 if caster.owner_id == 1 else 1
	var enemies := game_state.get_living_champions(opponent_id)

	if enemies.is_empty():
		return "no_valid_targets"

	# Check if enemies were in range (if applicable)
	# This is a simplified check
	return "damage_reduced_to_zero"


func _analyze_heal_noop(effect: Dictionary) -> String:
	"""Analyze why heal effect did nothing."""
	if game_state == null:
		return "no_game_state"

	var target_type: String = str(effect.get("target", ""))

	# Check if target was at full HP
	if target_type == "self" or target_type == "" or target_type == "none":
		var caster := game_state.get_champion(_current_caster_id)
		if caster and caster.current_hp >= caster.max_hp:
			return "target_full_hp"

	return "heal_had_no_effect"


func _analyze_move_noop(effect: Dictionary) -> String:
	"""Analyze why move effect did nothing."""
	var move_type: String = str(effect.get("value", ""))

	match move_type:
		"adjacent":
			return "already_adjacent_or_blocked"
		"away":
			return "no_valid_destination"
		"toward":
			return "already_adjacent_or_blocked"
		_:
			return "movement_blocked"


# --- Signal Handlers ---

func _on_damage_dealt(attacker: String, target: String, amount: int) -> void:
	"""Handle damage dealt signal."""
	if not _tracking_active:
		return
	if amount > 0:
		_damage_dealt += amount
		_damage_targets.append(target)


func _on_healing_done(source: String, target: String, amount: int) -> void:
	"""Handle healing done signal."""
	if not _tracking_active:
		return
	if amount > 0:
		_healing_done += amount
		_heal_targets.append(target)


func _on_buff_applied(target: String, buff_name: String, duration: int) -> void:
	"""Handle buff applied signal."""
	if not _tracking_active:
		return
	_buffs_applied += 1
	_buff_details.append({
		"target": target,
		"buff": buff_name,
		"duration": duration
	})


func _on_debuff_applied(target: String, debuff_name: String, duration: int) -> void:
	"""Handle debuff applied signal."""
	if not _tracking_active:
		return
	_debuffs_applied += 1
	_debuff_details.append({
		"target": target,
		"debuff": debuff_name,
		"duration": duration
	})


func _on_champion_moved(champion: String, from: Vector2i, to: Vector2i) -> void:
	"""Handle champion moved signal."""
	if not _tracking_active:
		return
	if from != to:
		_movements_caused += 1
		_movement_details.append({
			"champion": champion,
			"from": from,
			"to": to
		})


func _on_effect_applied(effect_type: String, source: String, target: String, value: int) -> void:
	"""Handle generic effect applied signal."""
	if not _tracking_active:
		return
	# Track specific effect types not covered by other signals
	match effect_type:
		"draw":
			if value > 0:
				_cards_drawn += value
		"mana", "gainMana":
			if value > 0:
				_mana_changed += value


## Result of tracking a card play
class EffectResult extends RefCounted:
	var card_name: String = ""
	var caster_id: String = ""
	var player_id: int = 0

	var damage_dealt: int = 0
	var healing_done: int = 0
	var buffs_applied: int = 0
	var debuffs_applied: int = 0
	var movements_caused: int = 0
	var cards_drawn: int = 0
	var mana_changed: int = 0

	var damage_targets: Array[String] = []
	var heal_targets: Array[String] = []
	var buff_details: Array[Dictionary] = []
	var debuff_details: Array[Dictionary] = []
	var movement_details: Array[Dictionary] = []

	var is_noop: bool = false
	var noop_reason: String = ""

	func _init() -> void:
		damage_targets = []
		heal_targets = []
		buff_details = []
		debuff_details = []
		movement_details = []

	func had_effect() -> bool:
		return not is_noop

	func to_dict() -> Dictionary:
		return {
			"card_name": card_name,
			"caster_id": caster_id,
			"player_id": player_id,
			"damage_dealt": damage_dealt,
			"healing_done": healing_done,
			"buffs_applied": buffs_applied,
			"debuffs_applied": debuffs_applied,
			"movements_caused": movements_caused,
			"cards_drawn": cards_drawn,
			"mana_changed": mana_changed,
			"is_noop": is_noop,
			"noop_reason": noop_reason,
			"damage_targets": damage_targets,
			"heal_targets": heal_targets
		}
