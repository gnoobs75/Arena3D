class_name ChampionState
extends RefCounted
## ChampionState - Runtime state for a champion during gameplay
## Designed to be immutable-friendly for AI simulation

# Identity
var unique_id: String = ""      # Unique instance ID (e.g., "brute_p1_0")
var champion_name: String = ""   # Base champion type
var owner_id: int = 0            # Player 1 or 2

# Position
var position: Vector2i = Vector2i(-1, -1)
var is_on_board: bool = false

# Stats (current values, can be modified by effects)
var current_hp: int = 20
var max_hp: int = 20
var current_power: int = 0
var current_range: int = 0
var current_movement: int = 0

# Base stats (from ChampionData, never change)
var base_power: int = 0
var base_range: int = 0
var base_movement: int = 0

# Action flags (reset each turn)
var has_moved: bool = false
var has_attacked: bool = false
var movement_remaining: int = 0

# Buffs and Debuffs
# Format: {"buff_name": {"duration": int, "stacks": int, "source": String}}
var buffs: Dictionary = {}
var debuffs: Dictionary = {}

# Equipment
# Format: {"card_id": {"charges_remaining": int}}
var equipment: Dictionary = {}


static func create(champion_name: String, owner: int, instance_index: int) -> ChampionState:
	"""Create a new ChampionState from champion data."""
	var state := ChampionState.new()
	state.champion_name = champion_name
	state.owner_id = owner
	state.unique_id = "%s_p%d_%d" % [champion_name.to_lower(), owner, instance_index]

	# Load base stats from database
	var stats := CardDatabase.get_champion_stats(champion_name)
	if not stats.is_empty():
		state.base_power = stats.get("power", 1)
		state.base_range = stats.get("range", 1)
		state.base_movement = stats.get("movement", 3)
		state.max_hp = stats.get("starting_hp", 20)
		state.current_hp = state.max_hp

	# Initialize current stats to base
	state._recalculate_stats()

	return state


func duplicate() -> ChampionState:
	"""Create a deep copy for AI simulation."""
	var copy := ChampionState.new()

	copy.unique_id = unique_id
	copy.champion_name = champion_name
	copy.owner_id = owner_id

	copy.position = position
	copy.is_on_board = is_on_board

	copy.current_hp = current_hp
	copy.max_hp = max_hp
	copy.current_power = current_power
	copy.current_range = current_range
	copy.current_movement = current_movement

	copy.base_power = base_power
	copy.base_range = base_range
	copy.base_movement = base_movement

	copy.has_moved = has_moved
	copy.has_attacked = has_attacked
	copy.movement_remaining = movement_remaining

	# Deep copy dictionaries
	copy.buffs = _deep_copy_dict(buffs)
	copy.debuffs = _deep_copy_dict(debuffs)
	copy.equipment = _deep_copy_dict(equipment)

	return copy


func _deep_copy_dict(source: Dictionary) -> Dictionary:
	var copy := {}
	for key: String in source:
		var value = source[key]
		if value is Dictionary:
			copy[key] = value.duplicate(true)
		else:
			copy[key] = value
	return copy


# --- HP Management ---

func take_damage(amount: int) -> int:
	"""Apply damage and return actual damage taken."""
	# Check for shield
	if has_buff("shield"):
		remove_buff("shield")
		return 0

	# Check for immune
	if has_buff("immune"):
		return 0

	var actual_damage := maxi(0, amount)
	current_hp = maxi(0, current_hp - actual_damage)
	return actual_damage


func heal(amount: int) -> int:
	"""Apply healing and return actual amount healed."""
	var actual_heal := mini(amount, max_hp - current_hp)
	current_hp = mini(max_hp, current_hp + actual_heal)
	return actual_heal


func is_alive() -> bool:
	return current_hp > 0


func is_dead() -> bool:
	return current_hp <= 0


# --- Buff/Debuff Management ---

func add_buff(buff_name: String, duration: int = -1, stacks: int = 1, source: String = "") -> void:
	"""Add or refresh a buff."""
	if buffs.has(buff_name):
		# Refresh duration and add stacks
		buffs[buff_name]["duration"] = maxi(buffs[buff_name]["duration"], duration)
		buffs[buff_name]["stacks"] += stacks
	else:
		buffs[buff_name] = {
			"duration": duration,
			"stacks": stacks,
			"source": source
		}

	# Handle special buff effects on application
	_apply_buff_effect(buff_name)
	_recalculate_stats()


func _apply_buff_effect(buff_name: String) -> void:
	"""Apply immediate effects when a buff is added."""
	match buff_name:
		"extraMove":
			# Grant an extra movement phase - reset movement state
			has_moved = false
			movement_remaining = current_movement
		"extraAttack":
			# The buff itself grants the extra attack through can_attack()
			# No need to reset has_attacked here
			pass


func remove_buff(buff_name: String) -> bool:
	"""Remove a buff. Returns true if it existed."""
	if buffs.erase(buff_name):
		_recalculate_stats()
		return true
	return false


func has_buff(buff_name: String) -> bool:
	return buffs.has(buff_name)


func get_buff_stacks(buff_name: String) -> int:
	if buffs.has(buff_name):
		return buffs[buff_name].get("stacks", 0)
	return 0


func add_debuff(debuff_name: String, duration: int = -1, stacks: int = 1, source: String = "") -> void:
	"""Add or refresh a debuff."""
	if debuffs.has(debuff_name):
		debuffs[debuff_name]["duration"] = maxi(debuffs[debuff_name]["duration"], duration)
		debuffs[debuff_name]["stacks"] += stacks
	else:
		debuffs[debuff_name] = {
			"duration": duration,
			"stacks": stacks,
			"source": source
		}
	_recalculate_stats()


func remove_debuff(debuff_name: String) -> bool:
	"""Remove a debuff. Returns true if it existed."""
	if debuffs.erase(debuff_name):
		_recalculate_stats()
		return true
	return false


func has_debuff(debuff_name: String) -> bool:
	return debuffs.has(debuff_name)


func tick_effects() -> void:
	"""Reduce duration of all timed effects. Called at end of turn."""
	_tick_dict(buffs)
	_tick_dict(debuffs)
	_recalculate_stats()


func _tick_dict(effects: Dictionary) -> void:
	var to_remove: Array[String] = []
	for effect_name: String in effects:
		var duration: int = effects[effect_name].get("duration", -1)
		if duration > 0:
			effects[effect_name]["duration"] = duration - 1
			if duration - 1 <= 0:
				to_remove.append(effect_name)
	for name: String in to_remove:
		effects.erase(name)


func clear_this_turn_effects() -> void:
	"""Remove all effects with 'thisTurn' duration."""
	var buff_names := buffs.keys()
	for buff_name: String in buff_names:
		if buffs[buff_name].get("duration", -1) == 0:  # 0 = this turn
			buffs.erase(buff_name)

	var debuff_names := debuffs.keys()
	for debuff_name: String in debuff_names:
		if debuffs[debuff_name].get("duration", -1) == 0:
			debuffs.erase(debuff_name)

	_recalculate_stats()


# --- Stat Calculation ---

func _recalculate_stats() -> void:
	"""Recalculate current stats from base + modifiers."""
	current_power = base_power
	current_range = base_range
	current_movement = base_movement

	# Apply buff modifiers
	if has_buff("powerBonus"):
		current_power += get_buff_stacks("powerBonus")
	if has_buff("rangeBonus"):
		current_range += get_buff_stacks("rangeBonus")
	if has_buff("movementBonus"):
		current_movement += get_buff_stacks("movementBonus")

	# Apply debuff modifiers
	if has_debuff("powerReduction"):
		current_power = maxi(0, current_power - get_debuff_stacks("powerReduction"))


func get_debuff_stacks(debuff_name: String) -> int:
	if debuffs.has(debuff_name):
		return debuffs[debuff_name].get("stacks", 0)
	return 0


# --- Action Checks ---

func can_move() -> bool:
	if has_debuff("canMove"):
		return false
	if has_debuff("stunned"):
		return false
	return not has_moved and movement_remaining > 0


func can_attack() -> bool:
	if has_debuff("canAttack"):
		return false
	if has_debuff("stunned"):
		return false
	# Can attack if hasn't attacked yet, OR has extraAttack buff
	return not has_attacked or has_buff("extraAttack")


func can_cast() -> bool:
	if has_debuff("canCast"):
		return false
	if has_debuff("silenced"):
		return false
	if has_debuff("stunned"):
		return false
	return true


func reset_turn() -> void:
	"""Reset per-turn state at start of turn."""
	has_moved = false
	has_attacked = false
	movement_remaining = current_movement


# --- Equipment ---

func add_equipment(card_id: String, charges: int) -> void:
	equipment[card_id] = {"charges_remaining": charges}


func use_equipment_charge(card_id: String) -> bool:
	"""Use one charge. Returns false if no charges left."""
	if not equipment.has(card_id):
		return false

	var charges: int = equipment[card_id].get("charges_remaining", 0)
	if charges <= 0:
		return false

	equipment[card_id]["charges_remaining"] = charges - 1
	if charges - 1 <= 0:
		equipment.erase(card_id)
	return true


func has_equipment(card_id: String) -> bool:
	return equipment.has(card_id)


func _to_string() -> String:
	return "ChampionState<%s HP:%d/%d Pos:%s>" % [unique_id, current_hp, max_hp, position]
