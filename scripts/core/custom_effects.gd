class_name CustomEffects
extends RefCounted
## CustomEffects - Handles all custom/special card effects
## Complex mechanics that don't fit standard effect types

signal dice_rolled(player_id: int, dice_values: Array, total: int)
signal choice_required(player_id: int, card_name: String, options: Array)
signal choice_made(player_id: int, card_name: String, chosen: Array)

var game_state: GameState
var effect_processor: EffectProcessor

# Pending choices waiting for player input
var pending_choices: Dictionary = {}


func _init(state: GameState) -> void:
	game_state = state
	effect_processor = EffectProcessor.new(state)


func process_custom_effect(effect: Dictionary, caster: ChampionState, targets: Array, card_data: Dictionary) -> Dictionary:
	"""Process a custom effect based on its name/handler."""
	var custom_name: String = effect.get("name", "")
	var custom_handler: String = card_data.get("customHandler", "")

	# Try name-based handler first
	match custom_name:
		"houseOdds":
			return _handle_house_odds(caster)
		"misdirection":
			return _handle_misdirection(caster, targets, effect)
		"evilTricks":
			return _handle_choose_effects(caster, effect, card_data)
		"spiritLink":
			return _handle_spirit_link(caster, targets)
		"resurrection":
			return _handle_resurrection(caster, targets)
		"copyStats":
			return _handle_copy_stats(caster, targets)
		"swapPositions":
			return _handle_swap_positions(caster, targets)
		"stealBuff":
			return _handle_steal_buff(caster, targets)
		"transferDebuff":
			return _handle_transfer_debuff(caster, targets)
		"coinFlip":
			return _handle_coin_flip(caster, effect)
		"transform":
			return _handle_transform(caster, targets, effect)
		"cloneChampion":
			return _handle_clone(caster, targets)
		"absorbPower":
			return _handle_absorb_power(caster, targets)

	# Try handler-based dispatch
	match custom_handler:
		"rollDice":
			return _handle_dice_roll(caster, effect, card_data)
		"chooseEffects":
			return _handle_choose_effects(caster, effect, card_data)
		"controlEnemy":
			return _handle_control_enemy(caster, targets, effect)

	push_warning("CustomEffects: Unknown custom effect '%s' / handler '%s'" % [custom_name, custom_handler])
	return {"success": false, "error": "Unknown custom effect"}


# === Dice Rolling Effects ===

func _handle_house_odds(caster: ChampionState) -> Dictionary:
	"""
	Illusionist's House Odds:
	Roll 2d6. 2-4: Self damage, 5-10: Enemy damage, 11-12: All enemy damage
	"""
	var dice := _roll_dice(2, 6)
	var total: int = dice[0] + dice[1]

	dice_rolled.emit(caster.owner_id, dice, total)

	var result := {"type": "custom", "custom": "houseOdds", "dice": dice, "total": total, "success": true}
	var opp_id := 2 if caster.owner_id == 1 else 1

	if total <= 4:
		# Bad outcome - damage self
		var damage := caster.take_damage(4)
		result["outcome"] = "self_damage"
		result["damage_dealt"] = damage
	elif total <= 10:
		# Medium outcome - damage one enemy
		var enemies := game_state.get_living_champions(opp_id)
		if not enemies.is_empty():
			# Would need player choice in full implementation
			var target: ChampionState = enemies[0]
			var damage := target.take_damage(4)
			result["outcome"] = "single_enemy"
			result["target"] = target.unique_id
			result["damage_dealt"] = damage
	else:
		# Great outcome - damage all enemies
		var total_damage := 0
		for enemy: ChampionState in game_state.get_living_champions(opp_id):
			total_damage += enemy.take_damage(4)
		result["outcome"] = "all_enemies"
		result["damage_dealt"] = total_damage

	return result


func _handle_dice_roll(caster: ChampionState, effect: Dictionary, card_data: Dictionary) -> Dictionary:
	"""Generic dice roll handler."""
	var num_dice: int = effect.get("numDice", 2)
	var die_sides: int = effect.get("dieSides", 6)
	var dice := _roll_dice(num_dice, die_sides)
	var total := 0
	for d: int in dice:
		total += d

	dice_rolled.emit(caster.owner_id, dice, total)

	return {
		"type": "custom",
		"custom": "diceRoll",
		"success": true,
		"dice": dice,
		"total": total
	}


func _roll_dice(num: int, sides: int) -> Array[int]:
	"""Roll multiple dice."""
	var results: Array[int] = []
	for i in range(num):
		results.append(randi() % sides + 1)
	return results


# === Coin Flip Effects ===

func _handle_coin_flip(caster: ChampionState, effect: Dictionary) -> Dictionary:
	"""50/50 chance effect."""
	var success := randi() % 2 == 0

	var result := {
		"type": "custom",
		"custom": "coinFlip",
		"success": true,
		"won": success
	}

	if success:
		# Apply success effects
		var success_effects: Array = effect.get("onSuccess", [])
		for eff: Dictionary in success_effects:
			effect_processor._process_single_effect(eff, caster, [], {})
	else:
		# Apply failure effects
		var fail_effects: Array = effect.get("onFail", [])
		for eff: Dictionary in fail_effects:
			effect_processor._process_single_effect(eff, caster, [], {})

	return result


# === Choice Effects ===

func _handle_choose_effects(caster: ChampionState, effect: Dictionary, card_data: Dictionary) -> Dictionary:
	"""
	Effects where player chooses from options (e.g., Evil Tricks).
	Returns pending state - needs UI callback.
	"""
	var options: Array = effect.get("options", [])
	var choose_count: int = effect.get("choose", 1)

	# For AI or auto-resolve, pick first N options
	# In full implementation, this would pause for player input
	var chosen: Array = []
	for i in range(mini(choose_count, options.size())):
		chosen.append(options[i])

	# Process chosen effects
	var results: Array = []
	for opt: Dictionary in chosen:
		for key: String in opt:
			var eff := {key: opt[key]}
			var res := effect_processor._process_single_effect(eff, caster, [], card_data)
			results.append(res)

	return {
		"type": "custom",
		"custom": "chooseEffects",
		"success": true,
		"chosen_count": chosen.size(),
		"results": results
	}


# === Control Effects ===

func _handle_misdirection(caster: ChampionState, targets: Array, effect: Dictionary) -> Dictionary:
	"""Illusionist's misdirection - redirect enemy attack."""
	# This would need to integrate with the attack resolution system
	# For now, apply a buff that triggers on attack
	caster.add_buff("misdirection", 1, 1, "misdirection")

	return {
		"type": "custom",
		"custom": "misdirection",
		"success": true
	}


func _handle_control_enemy(caster: ChampionState, targets: Array, effect: Dictionary) -> Dictionary:
	"""Take control of enemy action."""
	# Complex - would need UI/AI integration
	return {
		"type": "custom",
		"custom": "controlEnemy",
		"success": true,
		"note": "Control effect applied"
	}


# === Champion Manipulation ===

func _handle_spirit_link(caster: ChampionState, targets: Array) -> Dictionary:
	"""Link two champions - share damage."""
	if targets.is_empty():
		return {"success": false, "error": "No target"}

	var target := game_state.get_champion(targets[0])
	if target == null:
		return {"success": false, "error": "Invalid target"}

	# Link both champions to each other
	caster.add_buff("spiritLink", 2, 1, target.unique_id)
	target.add_buff("spiritLink", 2, 1, caster.unique_id)

	return {
		"type": "custom",
		"custom": "spiritLink",
		"success": true,
		"linked": [caster.unique_id, target.unique_id]
	}


func _handle_resurrection(caster: ChampionState, targets: Array) -> Dictionary:
	"""Redeemer's resurrection - swap position AND HP with dead ally."""
	if targets.is_empty():
		return {"success": false, "error": "No target"}

	var target := game_state.get_champion(targets[0])
	if target == null:
		return {"success": false, "error": "Invalid target"}

	if target.is_alive():
		return {"success": false, "error": "Target is not dead"}

	if target.owner_id != caster.owner_id:
		return {"success": false, "error": "Can only resurrect allies"}

	# Swap positions
	var caster_pos: Vector2i = caster.position
	var target_pos: Vector2i = target.position
	caster.position = target_pos
	target.position = caster_pos

	# Swap HP (caster's current HP goes to target, caster goes to 1)
	var caster_hp: int = caster.current_hp
	target.current_hp = caster_hp
	target.is_on_board = true
	caster.current_hp = 1

	return {
		"type": "custom",
		"custom": "resurrection",
		"success": true,
		"revived": target.unique_id,
		"revived_hp": caster_hp
	}


func _handle_copy_stats(caster: ChampionState, targets: Array) -> Dictionary:
	"""Copy target's current stats."""
	if targets.is_empty():
		return {"success": false, "error": "No target"}

	var target := game_state.get_champion(targets[0])
	if target == null:
		return {"success": false, "error": "Invalid target"}

	var old_stats := {
		"power": caster.current_power,
		"range": caster.current_range,
		"movement": caster.current_movement
	}

	caster.current_power = target.current_power
	caster.current_range = target.current_range
	caster.current_movement = target.current_movement

	return {
		"type": "custom",
		"custom": "copyStats",
		"success": true,
		"from": target.unique_id,
		"old_stats": old_stats,
		"new_stats": {
			"power": caster.current_power,
			"range": caster.current_range,
			"movement": caster.current_movement
		}
	}


func _handle_swap_positions(caster: ChampionState, targets: Array) -> Dictionary:
	"""Swap positions with target."""
	if targets.is_empty():
		return {"success": false, "error": "No target"}

	var target := game_state.get_champion(targets[0])
	if target == null:
		return {"success": false, "error": "Invalid target"}

	var caster_pos: Vector2i = caster.position
	var target_pos: Vector2i = target.position

	caster.position = target_pos
	target.position = caster_pos

	return {
		"type": "custom",
		"custom": "swapPositions",
		"success": true,
		"positions": {
			caster.unique_id: target_pos,
			target.unique_id: caster_pos
		}
	}


func _handle_steal_buff(caster: ChampionState, targets: Array) -> Dictionary:
	"""Steal a buff from target."""
	if targets.is_empty():
		return {"success": false, "error": "No target"}

	var target := game_state.get_champion(targets[0])
	if target == null or target.buffs.is_empty():
		return {"success": false, "error": "No buffs to steal"}

	# Pick random buff
	var buff_names := target.buffs.keys()
	var stolen_name: String = buff_names[randi() % buff_names.size()]
	var buff_data: Dictionary = target.buffs[stolen_name]

	# Transfer buff
	target.remove_buff(stolen_name)
	caster.add_buff(
		stolen_name,
		buff_data.get("duration", -1),
		buff_data.get("stacks", 1),
		"stolen"
	)

	return {
		"type": "custom",
		"custom": "stealBuff",
		"success": true,
		"stolen": stolen_name,
		"from": target.unique_id
	}


func _handle_transfer_debuff(caster: ChampionState, targets: Array) -> Dictionary:
	"""Transfer a debuff from self to target."""
	if targets.is_empty() or caster.debuffs.is_empty():
		return {"success": false, "error": "No debuff to transfer or no target"}

	var target := game_state.get_champion(targets[0])
	if target == null:
		return {"success": false, "error": "Invalid target"}

	# Transfer first debuff
	var debuff_names := caster.debuffs.keys()
	var transferred_name: String = debuff_names[0]
	var debuff_data: Dictionary = caster.debuffs[transferred_name]

	caster.remove_debuff(transferred_name)
	target.add_debuff(
		transferred_name,
		debuff_data.get("duration", -1),
		debuff_data.get("stacks", 1),
		caster.unique_id
	)

	return {
		"type": "custom",
		"custom": "transferDebuff",
		"success": true,
		"transferred": transferred_name,
		"to": target.unique_id
	}


func _handle_transform(caster: ChampionState, targets: Array, effect: Dictionary) -> Dictionary:
	"""Beast's transformation effects."""
	var transform_to: String = effect.get("transformTo", "")

	# Apply stat changes based on form
	match transform_to:
		"wolf":
			caster.add_buff("movementBonus", -1, 2, "transform")
			caster.add_buff("powerBonus", -1, 1, "transform")
		"bear":
			caster.add_buff("powerBonus", -1, 2, "transform")
			caster.add_buff("damageReduction", -1, 1, "transform")
		"hawk":
			caster.add_buff("rangeBonus", -1, 3, "transform")
			caster.add_buff("agility", -1, 1, "transform")

	return {
		"type": "custom",
		"custom": "transform",
		"success": true,
		"form": transform_to
	}


func _handle_clone(caster: ChampionState, _targets: Array) -> Dictionary:
	"""Create illusion/clone."""
	# Would need to create a temporary champion
	return {
		"type": "custom",
		"custom": "clone",
		"success": true,
		"note": "Clone created (not fully implemented)"
	}


func _handle_absorb_power(caster: ChampionState, targets: Array) -> Dictionary:
	"""Steal power from target."""
	if targets.is_empty():
		return {"success": false, "error": "No target"}

	var target := game_state.get_champion(targets[0])
	if target == null:
		return {"success": false, "error": "Invalid target"}

	var stolen_power := mini(target.current_power, 2)
	target.add_debuff("powerReduction", 1, stolen_power, caster.unique_id)
	caster.add_buff("powerBonus", 1, stolen_power, "absorbed")

	return {
		"type": "custom",
		"custom": "absorbPower",
		"success": true,
		"power_stolen": stolen_power
	}
