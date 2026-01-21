class_name EffectProcessor
extends RefCounted
## EffectProcessor - Handles all card effect logic
## Processes damage, heal, buffs, debuffs, stat mods, movement, draw, custom effects

signal effect_applied(effect_type: String, source: String, target: String, value: int)
signal damage_dealt(attacker: String, target: String, amount: int)
signal healing_done(source: String, target: String, amount: int)
signal buff_applied(target: String, buff_name: String, duration: int)
signal debuff_applied(target: String, debuff_name: String, duration: int)
signal champion_moved(champion: String, from: Vector2i, to: Vector2i)
signal immediate_movement_required(champion_ids: Array, movement_bonus: int)

var game_state: GameState


func _init(state: GameState) -> void:
	game_state = state


func process_card(card_name: String, caster: ChampionState, targets: Array) -> Dictionary:
	"""
	Process all effects of a card.
	Returns result dictionary with outcomes.
	"""
	var card_data := CardDatabase.get_card(card_name)
	if card_data.is_empty():
		return {"success": false, "error": "Card not found"}

	# Check for cards that need special handling
	var special_result := _handle_special_card(card_name, caster, targets, card_data)
	if not special_result.is_empty():
		return special_result

	var effects: Array = card_data.get("effect", [])
	var results: Array = []

	for effect: Dictionary in effects:
		var result := _process_single_effect(effect, caster, targets, card_data)
		results.append(result)

	return {
		"success": true,
		"card": card_name,
		"caster": caster.unique_id,
		"effects": results
	}


func _handle_special_card(card_name: String, caster: ChampionState, targets: Array, _card_data: Dictionary) -> Dictionary:
	"""Handle cards that need special processing beyond standard effects."""
	match card_name:
		"Bear Tank":
			return _handle_bear_tank(caster, targets)
	return {}


func _process_single_effect(effect: Dictionary, caster: ChampionState, targets: Array, card_data: Dictionary) -> Dictionary:
	"""Process a single effect from the card's effect array."""
	var result := {"type": "unknown", "success": false}

	# Get effect type - cards.json uses "type" field
	var effect_type: String = str(effect.get("type", ""))

	# For self-targeting cards, ensure caster is included in targets
	var effective_targets := targets
	var card_target_type: String = str(card_data.get("target", "")).to_lower()
	if card_target_type == "self" and effective_targets.is_empty():
		effective_targets = [caster.unique_id]

	# Determine effect type and process
	match effect_type.to_lower():
		"damage":
			result = _process_damage(effect, caster, effective_targets, card_data)
		"heal":
			result = _process_heal(effect, caster, effective_targets)
		"statmod":
			result = _process_stat_mod(effect, caster, effective_targets)
		"buff":
			result = _process_buff(effect, caster, effective_targets)
		"debuff":
			result = _process_debuff(effect, caster, effective_targets)
		"move":
			result = _process_move(effect, caster, effective_targets)
		"draw":
			result = _process_draw(effect, caster, effective_targets)
		"discard":
			result = _process_discard(effect, caster, effective_targets)
		"custom":
			result = _process_custom(effect, caster, targets, card_data)
		_:
			# Fallback: check for old-style keys for backwards compatibility
			if effect.has("damage"):
				result = _process_damage(effect, caster, targets)
			elif effect.has("heal"):
				result = _process_heal(effect, caster, targets)
			elif effect.has("custom"):
				result = _process_custom(effect, caster, targets, card_data)
			else:
				push_warning("EffectProcessor: Unknown effect type '%s'" % effect_type)

	return result


# --- Damage Processing ---

func _process_damage(effect: Dictionary, caster: ChampionState, targets: Array, card_data: Dictionary = {}) -> Dictionary:
	# Support both new format (value) and old format (damage)
	var damage_value = effect.get("value", effect.get("damage", 0))
	var scope: String = str(effect.get("scope", "target"))
	var card_range: String = str(card_data.get("range", ""))
	var effect_range: String = str(effect.get("range", ""))

	# Handle AOE random damage (e.g., Rain of Arrows)
	if scope == "random" and (card_range == "AOE" or effect_range == "AOE"):
		return _process_aoe_random_damage(damage_value, caster, targets, card_data)

	var actual_targets := _resolve_targets(scope, caster, targets, card_range)
	var total_damage := 0

	for target: ChampionState in actual_targets:
		var amount := _calculate_damage(damage_value, caster, target)
		var dealt := target.take_damage(amount)
		total_damage += dealt
		damage_dealt.emit(caster.unique_id, target.unique_id, dealt)
		if dealt > 0:
			EventBus.champion_damaged.emit(target.unique_id, dealt, caster.champion_name)

	return {
		"type": "damage",
		"success": true,
		"total_damage": total_damage,
		"target_count": actual_targets.size()
	}


func _process_aoe_random_damage(damage_value, caster: ChampionState, targets: Array, card_data: Dictionary) -> Dictionary:
	"""Handle AOE damage distributed randomly among targets in range of a position.
	Used for cards like Rain of Arrows."""
	var total_damage := _calculate_damage(damage_value, caster, caster)  # Calculate total damage pool
	var aoe_radius: int = card_data.get("aoeRadius", 1)  # Default AOE radius

	print("EffectProcessor: AOE random damage - total=%d, radius=%d, targets=%s" % [total_damage, aoe_radius, targets])

	# Find the target position from targets array
	var target_pos: Vector2i = Vector2i(-999, -999)  # Invalid sentinel
	var found_position := false
	if targets.size() > 0:
		var first_target = targets[0]
		if first_target is Vector2i:
			target_pos = first_target
			found_position = true
		elif first_target is String:
			# Try to parse as "x,y" format
			var parts: PackedStringArray = first_target.split(",")
			if parts.size() == 2:
				target_pos = Vector2i(int(parts[0]), int(parts[1]))
				found_position = true

	if not found_position:
		print("EffectProcessor: AOE damage - no valid target position in targets: %s" % [targets])
		return {"type": "damage", "success": false, "error": "No target position"}

	print("EffectProcessor: AOE target position: %s" % target_pos)

	# Find all ENEMY champions within AOE range of target position
	var opp_id := 2 if caster.owner_id == 1 else 1
	var champions_in_aoe: Array[ChampionState] = []
	for champ: ChampionState in game_state.get_champions(opp_id):
		if champ.is_alive():
			var dist: int = maxi(absi(champ.position.x - target_pos.x), absi(champ.position.y - target_pos.y))
			print("EffectProcessor: Checking %s at %s, dist=%d from target" % [champ.champion_name, champ.position, dist])
			if dist <= aoe_radius:
				champions_in_aoe.append(champ)

	if champions_in_aoe.is_empty():
		print("EffectProcessor: AOE damage - no enemy champions in range")
		return {"type": "damage", "success": true, "total_damage": 0, "target_count": 0}

	# Distribute damage randomly among targets
	var dealt_damage := 0
	var damage_distribution: Dictionary = {}  # champion_id -> damage taken

	for i in range(total_damage):
		var random_target: ChampionState = champions_in_aoe[randi() % champions_in_aoe.size()]
		var dealt := random_target.take_damage(1)
		dealt_damage += dealt
		damage_dealt.emit(caster.unique_id, random_target.unique_id, dealt)
		if dealt > 0:
			EventBus.champion_damaged.emit(random_target.unique_id, dealt, caster.champion_name)

		# Track for summary
		if not damage_distribution.has(random_target.unique_id):
			damage_distribution[random_target.unique_id] = 0
		damage_distribution[random_target.unique_id] += dealt

	print("EffectProcessor: AOE random damage - distributed %d damage to %d targets: %s" % [dealt_damage, champions_in_aoe.size(), damage_distribution])

	return {
		"type": "damage",
		"success": true,
		"total_damage": dealt_damage,
		"target_count": champions_in_aoe.size(),
		"distribution": damage_distribution
	}


func _calculate_damage(damage_value, caster: ChampionState, _target: ChampionState) -> int:
	"""Calculate damage amount from various formats."""
	if damage_value is int:
		return damage_value
	elif damage_value is float:
		return int(damage_value)
	elif damage_value is String:
		match damage_value:
			"power":
				return caster.current_power
			"doublePower":
				return caster.current_power * 2
			_:
				return 0
	elif damage_value is Dictionary:
		var base: int = damage_value.get("base", 0)
		var per_power: int = damage_value.get("perPower", 0)
		return base + (per_power * caster.current_power)

	return 0


# --- Heal Processing ---

func _process_heal(effect: Dictionary, caster: ChampionState, targets: Array) -> Dictionary:
	# Support both new format (value) and old format (heal)
	var heal_value = effect.get("value", effect.get("heal", 0))
	var scope: String = str(effect.get("scope", "target"))
	var actual_targets := _resolve_targets(scope, caster, targets)
	var total_healed := 0

	for target: ChampionState in actual_targets:
		var amount := _calculate_heal(heal_value, caster, target)
		var healed := target.heal(amount)
		total_healed += healed
		healing_done.emit(caster.unique_id, target.unique_id, healed)
		if healed > 0:
			EventBus.champion_healed.emit(target.unique_id, healed, caster.champion_name)

	return {
		"type": "heal",
		"success": true,
		"total_healed": total_healed
	}


func _calculate_heal(heal_value, caster: ChampionState, target: ChampionState) -> int:
	"""Calculate heal amount from various formats."""
	if heal_value is int:
		return heal_value
	elif heal_value is String:
		match heal_value:
			"damageTaken":
				return target.max_hp - target.current_hp
			"halfDamageTaken":
				return (target.max_hp - target.current_hp) / 2
			"oppHandSize":
				var opp_id := 2 if caster.owner_id == 1 else 1
				return game_state.get_hand(opp_id).size()
			_:
				return 0

	return 0


# --- Stat Mod Processing ---

func _process_stat_mod(effect: Dictionary, caster: ChampionState, targets: Array) -> Dictionary:
	# cards.json has flat structure: {"type": "statMod", "stat": "power", "value": 2, "duration": "thisTurn"}
	var stat: String = str(effect.get("stat", ""))
	var amount: int = _to_int(effect.get("value", effect.get("amount", 0)))
	var duration: String = str(effect.get("duration", "permanent"))
	var scope: String = str(effect.get("scope", "target"))

	var actual_targets := _resolve_targets(scope, caster, targets)
	var duration_value := _parse_duration(duration)

	for target: ChampionState in actual_targets:
		var buff_name := stat + "Bonus" if amount > 0 else stat + "Reduction"
		if amount > 0:
			target.add_buff(buff_name, duration_value, absi(amount), caster.unique_id)
		else:
			target.add_debuff(buff_name, duration_value, absi(amount), caster.unique_id)

	return {
		"type": "statMod",
		"success": true,
		"stat": stat,
		"amount": amount,
		"duration": duration
	}


func _to_int(value) -> int:
	"""Safely convert any value to int."""
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String:
		if value.is_valid_int():
			return value.to_int()
	return 0


# --- Buff Processing ---

func _process_buff(effect: Dictionary, caster: ChampionState, targets: Array) -> Dictionary:
	# cards.json uses "name" for buff name: {"type": "buff", "name": "extraMove", "value": true, "duration": "thisTurn"}
	var buff_name: String = str(effect.get("name", effect.get("buff", "")))
	var duration: String = str(effect.get("duration", "permanent"))
	var stacks: int = _to_int(effect.get("stacks", effect.get("value", 1)))
	if stacks == 0:
		stacks = 1  # Default to 1 stack if value is boolean true
	var scope: String = str(effect.get("scope", "target"))

	var actual_targets := _resolve_targets(scope, caster, targets)
	var duration_value := _parse_duration(duration)

	var extra_data: Dictionary = {}

	for target: ChampionState in actual_targets:
		target.add_buff(buff_name, duration_value, stacks, caster.unique_id)
		buff_applied.emit(target.unique_id, buff_name, duration_value)
		EventBus.champion_buff_applied.emit(target.unique_id, buff_name, duration_value)

		# Special handling for buffs that need game_state access
		match buff_name:
			"createPits":
				# Pit of Despair - create temporary pits around the Dark Wizard
				var pit_positions := game_state.create_pits_around(target.position)
				extra_data["pit_positions"] = pit_positions
				print("Created pits around %s at positions: %s" % [target.champion_name, pit_positions])

	return {
		"type": "buff",
		"success": true,
		"buff": buff_name,
		"targets": actual_targets.size(),
		"extra": extra_data
	}


# --- Debuff Processing ---

func _process_debuff(effect: Dictionary, caster: ChampionState, targets: Array) -> Dictionary:
	# cards.json uses "name" for debuff name: {"type": "debuff", "name": "canAttack", "value": false, "duration": "thisTurn"}
	var debuff_name: String = str(effect.get("name", effect.get("debuff", "")))
	var duration: String = str(effect.get("duration", "permanent"))
	var stacks: int = _to_int(effect.get("stacks", effect.get("value", 1)))
	if stacks == 0:
		stacks = 1  # Default to 1 stack if value is boolean false
	var scope: String = str(effect.get("scope", "target"))

	var actual_targets := _resolve_targets(scope, caster, targets)
	var duration_value := _parse_duration(duration)

	for target: ChampionState in actual_targets:
		target.add_debuff(debuff_name, duration_value, stacks, caster.unique_id)
		debuff_applied.emit(target.unique_id, debuff_name, duration_value)
		EventBus.champion_debuff_applied.emit(target.unique_id, debuff_name, duration_value)

	return {
		"type": "debuff",
		"success": true,
		"debuff": debuff_name,
		"targets": actual_targets.size()
	}


# --- Move Processing ---

func _process_move(effect: Dictionary, caster: ChampionState, targets: Array) -> Dictionary:
	# cards.json uses "value" for move type: {"type": "move", "value": "overWall"}
	var move_type: String = str(effect.get("value", effect.get("move", "")))
	var scope: String = str(effect.get("scope", "target"))
	var movement_bonus: int = _to_int(effect.get("bonus", 0))
	var actual_targets := _resolve_targets(scope, caster, targets)
	var moves_done := 0

	# Handle "immediate" move type - requires player input
	if move_type == "immediate":
		var champion_ids: Array = []
		for target: ChampionState in actual_targets:
			champion_ids.append(target.unique_id)
			# Apply movement bonus if specified
			if movement_bonus > 0:
				target.movement_remaining += movement_bonus
			else:
				# Reset movement to allow full movement
				target.movement_remaining = target.current_movement
			target.has_moved = false  # Allow movement

		# Signal that immediate movement is required
		immediate_movement_required.emit(champion_ids, movement_bonus)

		return {
			"type": "move",
			"success": true,
			"move_type": move_type,
			"pending_immediate_movement": true,
			"champion_ids": champion_ids,
			"movement_bonus": movement_bonus
		}

	# Auto-calculated move types
	for target: ChampionState in actual_targets:
		var new_pos: Vector2i = _calculate_move_destination(move_type, caster, target)
		if new_pos != target.position and game_state.is_walkable(new_pos):
			var old_pos: Vector2i = target.position
			target.position = new_pos
			champion_moved.emit(target.unique_id, old_pos, new_pos)
			moves_done += 1

	return {
		"type": "move",
		"success": true,
		"move_type": move_type,
		"moves_done": moves_done
	}


func _calculate_move_destination(move_type: String, caster: ChampionState, target: ChampionState) -> Vector2i:
	"""Calculate destination based on move type."""
	var pathfinder := Pathfinder.new(game_state)

	match move_type:
		"adjacent":
			# Move to tile adjacent to caster
			var adjacent := pathfinder.get_empty_adjacent_tiles(caster.position, true)
			if not adjacent.is_empty():
				return adjacent[0]
		"toWall":
			# Push away from caster until hitting a wall
			return _find_wall_push_destination(target, caster)
		"corner":
			# Move to nearest corner
			return _find_nearest_corner(target)
		"safe":
			# Move to safest tile (furthest from enemies)
			return _find_safest_tile(target)
		"away":
			# Move away from caster
			return _calculate_push_away(caster.position, target.position, 1)
		"awayTwo":
			return _calculate_push_away(caster.position, target.position, 2)

	return target.position


func _calculate_push_away(from: Vector2i, current: Vector2i, distance: int) -> Vector2i:
	"""Push target away from a position."""
	var dx := current.x - from.x
	var dy := current.y - from.y

	# Normalize direction
	var dir_x := 0 if dx == 0 else (1 if dx > 0 else -1)
	var dir_y := 0 if dy == 0 else (1 if dy > 0 else -1)

	var new_pos := current + Vector2i(dir_x * distance, dir_y * distance)

	# Check if valid
	if game_state.is_walkable(new_pos):
		return new_pos

	# Try each direction separately
	if dir_x != 0 and game_state.is_walkable(current + Vector2i(dir_x * distance, 0)):
		return current + Vector2i(dir_x * distance, 0)
	if dir_y != 0 and game_state.is_walkable(current + Vector2i(0, dir_y * distance)):
		return current + Vector2i(0, dir_y * distance)

	return current


func _find_wall_push_destination(target: ChampionState, caster: ChampionState) -> Vector2i:
	"""Find destination when pushing away from caster until hitting a wall or edge."""
	var target_pos: Vector2i = target.position
	var caster_pos: Vector2i = caster.position

	# Calculate push direction (away from caster)
	var dx: int = target_pos.x - caster_pos.x
	var dy: int = target_pos.y - caster_pos.y

	# Determine primary push direction (cardinal only)
	var push_dir: Vector2i = Vector2i.ZERO
	if absi(dx) >= absi(dy):
		# Push horizontally (or if equal, prefer horizontal)
		push_dir = Vector2i(1, 0) if dx >= 0 else Vector2i(-1, 0)
	else:
		# Push vertically
		push_dir = Vector2i(0, 1) if dy >= 0 else Vector2i(0, -1)

	# If caster and target are at same position (shouldn't happen), default to right
	if push_dir == Vector2i.ZERO:
		push_dir = Vector2i(1, 0)

	# Push target in direction until hitting wall, edge, or another champion
	var current: Vector2i = target_pos
	var last_valid: Vector2i = target_pos

	while true:
		var next: Vector2i = current + push_dir

		# Check if next position is valid and walkable (can pass over pits)
		if not game_state.is_valid_position(next):
			break  # Hit edge of map

		var terrain := game_state.get_terrain(next)
		if terrain == GameState.Terrain.WALL:
			break  # Hit a wall

		# Check for another champion blocking
		var occupant := game_state.get_champion_at(next)
		if occupant != null and occupant.unique_id != target.unique_id:
			break  # Hit another champion

		# Can move to this position (even if it's a pit - they pass over)
		if terrain != GameState.Terrain.PIT:
			last_valid = next

		current = next

	return last_valid


func _find_nearest_corner(target: ChampionState) -> Vector2i:
	"""Find nearest walkable corner position."""
	var corners: Array[Vector2i] = [
		Vector2i(1, 1),
		Vector2i(1, 8),
		Vector2i(8, 1),
		Vector2i(8, 8)
	]

	var best_dist: float = 999.0
	var best_corner: Vector2i = target.position

	for corner: Vector2i in corners:
		if game_state.is_walkable(corner):
			var dist: float = target.position.distance_squared_to(corner)
			if dist < best_dist:
				best_dist = dist
				best_corner = corner

	return best_corner


func _find_safest_tile(target: ChampionState) -> Vector2i:
	"""Find tile furthest from all enemies."""
	var pathfinder := Pathfinder.new(game_state)
	var reachable := pathfinder.get_reachable_tiles(target)
	var opp_id: int = 2 if target.owner_id == 1 else 1

	var best_score: int = -1
	var best_pos: Vector2i = target.position

	for tile: Vector2i in reachable:
		var min_enemy_dist: int = 999
		for enemy: ChampionState in game_state.get_champions(opp_id):
			if enemy.is_alive():
				var dist: int = pathfinder.manhattan_distance(tile, enemy.position)
				min_enemy_dist = mini(min_enemy_dist, dist)

		if min_enemy_dist > best_score:
			best_score = min_enemy_dist
			best_pos = tile

	return best_pos


# --- Draw Processing ---

func _process_draw(effect: Dictionary, caster: ChampionState, _targets: Array) -> Dictionary:
	# cards.json uses "value" for draw count
	var draw_count: int = _to_int(effect.get("value", effect.get("draw", 1)))
	if draw_count == 0:
		draw_count = 1  # Default to drawing 1 card
	var from: String = str(effect.get("from", "deck"))
	var filter: String = str(effect.get("filter", ""))
	var cards_drawn: Array[String] = []

	for i in range(draw_count):
		var drawn := ""
		match from:
			"deck":
				drawn = game_state.draw_card(caster.owner_id)
			"discard":
				drawn = _draw_from_discard(caster.owner_id, filter)
			"oppDiscard":
				var opp_id := 2 if caster.owner_id == 1 else 1
				drawn = _draw_from_discard(opp_id, filter)

		if not drawn.is_empty():
			cards_drawn.append(drawn)

	return {
		"type": "draw",
		"success": true,
		"cards_drawn": cards_drawn.size()
	}


func _draw_from_discard(player_id: int, filter: String) -> String:
	"""Draw a card from discard pile, optionally filtered."""
	var discard := game_state.get_discard(player_id)
	var hand := game_state.get_hand(player_id)

	if discard.is_empty():
		return ""

	var valid_cards: Array[String] = []
	for card_name: String in discard:
		if filter.is_empty() or _card_matches_filter(card_name, filter):
			valid_cards.append(card_name)

	if valid_cards.is_empty():
		return ""

	# For now, take first valid (AI would choose best)
	var chosen: String = valid_cards[0]
	discard.erase(chosen)
	hand.append(chosen)
	return chosen


func _card_matches_filter(card_name: String, filter: String) -> bool:
	"""Check if card matches filter criteria."""
	var card_data := CardDatabase.get_card(card_name)
	if card_data.is_empty():
		return false

	match filter:
		"action":
			return card_data.get("type") == "Action"
		"response":
			return card_data.get("type") == "Response"
		"equipment":
			return card_data.get("type") == "Equipment"
		_:
			return true


# --- Discard Processing ---

func _process_discard(effect: Dictionary, caster: ChampionState, _targets: Array) -> Dictionary:
	# cards.json uses "value" for discard count
	var discard_count: int = _to_int(effect.get("value", effect.get("discard", 1)))
	if discard_count == 0:
		discard_count = 1  # Default to discarding 1 card
	var target_player: String = str(effect.get("targetPlayer", "self"))
	var random: bool = effect.get("random", false)

	var player_id := caster.owner_id
	if target_player == "opponent":
		player_id = 2 if caster.owner_id == 1 else 1

	var hand := game_state.get_hand(player_id)
	var discard := game_state.get_discard(player_id)
	var discarded := 0

	for i in range(mini(discard_count, hand.size())):
		var idx := 0
		if random:
			idx = randi() % hand.size()

		var card_name: String = hand[idx]
		hand.remove_at(idx)
		discard.append(card_name)
		discarded += 1

	return {
		"type": "discard",
		"success": true,
		"discarded": discarded
	}


# --- Custom Effects ---

func _process_custom(effect: Dictionary, caster: ChampionState, targets: Array, card_data: Dictionary) -> Dictionary:
	var custom_type: String = effect.get("custom", "")

	match custom_type:
		"resurrection":
			return _handle_resurrection(caster, targets)
		"spiritLink":
			return _handle_spirit_link(caster, targets)
		"copyStats":
			return _handle_copy_stats(caster, targets)
		"houseOdds":
			return _handle_house_odds(caster)
		"swapPositions":
			return _handle_swap_positions(caster, targets)
		"stealBuff":
			return _handle_steal_buff(caster, targets)
		"transferDebuff":
			return _handle_transfer_debuff(caster, targets)
		"bearTank":
			return _handle_bear_tank(caster, targets)
		_:
			push_warning("EffectProcessor: Unknown custom effect '%s'" % custom_type)
			return {"type": "custom", "success": false, "error": "Unknown custom: " + custom_type}


func _handle_resurrection(caster: ChampionState, targets: Array) -> Dictionary:
	"""Redeemer's resurrection - swap position AND life with dead ally."""
	if targets.is_empty():
		return {"type": "custom", "success": false}

	var target := game_state.get_champion(targets[0])
	if target == null or target.is_alive():
		return {"type": "custom", "success": false}

	# Swap positions
	var caster_pos: Vector2i = caster.position
	var target_pos: Vector2i = target.position
	caster.position = target_pos
	target.position = caster_pos

	# Swap HP
	var caster_hp: int = caster.current_hp
	target.current_hp = caster_hp
	caster.current_hp = 1  # Caster goes to 1 HP

	target.is_on_board = true

	return {
		"type": "custom",
		"custom": "resurrection",
		"success": true
	}


func _handle_spirit_link(caster: ChampionState, targets: Array) -> Dictionary:
	"""Shaman's spirit link - share damage between linked champions."""
	if targets.is_empty():
		return {"type": "custom", "success": false}

	var target := game_state.get_champion(targets[0])
	if target == null:
		return {"type": "custom", "success": false}

	# Apply spiritLink buff to both
	caster.add_buff("spiritLink", 2, 1, target.unique_id)
	target.add_buff("spiritLink", 2, 1, caster.unique_id)

	return {
		"type": "custom",
		"custom": "spiritLink",
		"success": true
	}


func _handle_copy_stats(caster: ChampionState, targets: Array) -> Dictionary:
	"""Copy target's stats."""
	if targets.is_empty():
		return {"type": "custom", "success": false}

	var target := game_state.get_champion(targets[0])
	if target == null:
		return {"type": "custom", "success": false}

	caster.current_power = target.current_power
	caster.current_range = target.current_range
	caster.current_movement = target.current_movement

	return {
		"type": "custom",
		"custom": "copyStats",
		"success": true
	}


func _handle_house_odds(caster: ChampionState) -> Dictionary:
	"""Illusionist's gamble - 50/50 chance of good or bad outcome."""
	var win := randi() % 2 == 0

	if win:
		caster.add_buff("powerBonus", 1, 2, "houseOdds")
		game_state.draw_card(caster.owner_id)
	else:
		caster.take_damage(2)

	return {
		"type": "custom",
		"custom": "houseOdds",
		"success": true,
		"won": win
	}


func _handle_swap_positions(caster: ChampionState, targets: Array) -> Dictionary:
	"""Swap positions with target."""
	if targets.is_empty():
		return {"type": "custom", "success": false}

	var target := game_state.get_champion(targets[0])
	if target == null:
		return {"type": "custom", "success": false}

	var temp: Vector2i = caster.position
	caster.position = target.position
	target.position = temp

	return {
		"type": "custom",
		"custom": "swapPositions",
		"success": true
	}


func _handle_steal_buff(caster: ChampionState, targets: Array) -> Dictionary:
	"""Steal a random buff from target."""
	if targets.is_empty():
		return {"type": "custom", "success": false}

	var target := game_state.get_champion(targets[0])
	if target == null or target.buffs.is_empty():
		return {"type": "custom", "success": false}

	var buff_names := target.buffs.keys()
	var stolen_buff: String = buff_names[randi() % buff_names.size()]
	var buff_data: Dictionary = target.buffs[stolen_buff]

	target.remove_buff(stolen_buff)
	caster.add_buff(stolen_buff, buff_data.get("duration", -1), buff_data.get("stacks", 1), "stolen")

	return {
		"type": "custom",
		"custom": "stealBuff",
		"success": true,
		"buff": stolen_buff
	}


func _handle_transfer_debuff(caster: ChampionState, targets: Array) -> Dictionary:
	"""Transfer a debuff from self to target."""
	if targets.is_empty() or caster.debuffs.is_empty():
		return {"type": "custom", "success": false}

	var target := game_state.get_champion(targets[0])
	if target == null:
		return {"type": "custom", "success": false}

	var debuff_names := caster.debuffs.keys()
	var transferred: String = debuff_names[0]  # First debuff
	var debuff_data: Dictionary = caster.debuffs[transferred]

	caster.remove_debuff(transferred)
	target.add_debuff(transferred, debuff_data.get("duration", -1), debuff_data.get("stacks", 1), caster.unique_id)

	return {
		"type": "custom",
		"custom": "transferDebuff",
		"success": true,
		"debuff": transferred
	}


func _handle_bear_tank(caster: ChampionState, targets: Array) -> Dictionary:
	"""Beast's Bear Tank - move adjacent to ally, take 1 damage, redirect attack to self."""
	if targets.is_empty():
		return {}  # Return empty to fall through to normal processing

	var ally := game_state.get_champion(str(targets[0]))
	if ally == null or not ally.is_alive():
		return {}  # Return empty to fall through to normal processing

	# Move Beast adjacent to ally
	var pathfinder := Pathfinder.new(game_state)
	var adjacent := pathfinder.get_empty_adjacent_tiles(ally.position, true)

	var moved := false
	if not adjacent.is_empty():
		var old_pos: Vector2i = caster.position
		caster.position = adjacent[0]
		champion_moved.emit(caster.unique_id, old_pos, adjacent[0])
		moved = true
		print("Bear Tank: %s moved to %s (adjacent to %s)" % [caster.champion_name, adjacent[0], ally.champion_name])

	# Beast takes 1 damage
	var damage_taken := caster.take_damage(1)
	damage_dealt.emit("bearTank", caster.unique_id, damage_taken)
	print("Bear Tank: %s took 1 damage" % caster.champion_name)

	# Mark ally to redirect incoming attack to Beast
	# Store Beast's ID in the buff source so we know who to redirect to
	ally.add_buff("redirectAttack", 0, 1, caster.unique_id)  # Duration 0 = this turn only
	print("Bear Tank: %s will redirect attack to %s" % [ally.champion_name, caster.champion_name])

	return {
		"success": true,
		"card": "Bear Tank",
		"caster": caster.unique_id,
		"effects": [{
			"type": "custom",
			"custom": "bearTank",
			"moved": moved,
			"redirect_to": caster.unique_id,
			"protected": ally.unique_id
		}]
	}


# --- Helper Functions ---

func _resolve_targets(scope: String, caster: ChampionState, explicit_targets: Array, card_range: String = "") -> Array[ChampionState]:
	"""Resolve target list based on scope."""
	var targets: Array[ChampionState] = []

	match scope.to_lower():
		"self":
			targets.append(caster)
		"target":
			for target_id in explicit_targets:
				var champ := game_state.get_champion(str(target_id))
				if champ:
					targets.append(champ)
		"allallies", "friendlies":
			for champ: ChampionState in game_state.get_champions(caster.owner_id):
				if champ.is_alive():
					targets.append(champ)
		"allenemies", "enemies":
			var opp_id := 2 if caster.owner_id == 1 else 1
			for champ: ChampionState in game_state.get_champions(opp_id):
				if champ.is_alive():
					# If card has "range": "self", filter by caster's attack range
					if card_range == "self":
						if _is_in_attack_range(caster, champ):
							targets.append(champ)
					else:
						targets.append(champ)
		"all":
			# Check if we have a direction in explicit_targets
			if explicit_targets.size() > 0:
				var first_target: String = str(explicit_targets[0]).to_lower()
				if first_target in ["up", "down", "left", "right"]:
					# Direction-based "all" - get champions in that direction
					targets = _get_champions_in_direction(caster, first_target)
				else:
					# Regular "all" - all living champions
					for champ: ChampionState in game_state.get_all_champions():
						if champ.is_alive():
							targets.append(champ)
			else:
				for champ: ChampionState in game_state.get_all_champions():
					if champ.is_alive():
						targets.append(champ)
		_:
			# Default to explicit targets
			for target_id in explicit_targets:
				var champ := game_state.get_champion(str(target_id))
				if champ:
					targets.append(champ)

	return targets


func _get_champions_in_direction(caster: ChampionState, direction: String) -> Array[ChampionState]:
	"""Get all champions in a line from caster in the specified direction."""
	var targets: Array[ChampionState] = []
	var dir_vec: Vector2i

	match direction:
		"up":
			dir_vec = Vector2i(0, -1)
		"down":
			dir_vec = Vector2i(0, 1)
		"left":
			dir_vec = Vector2i(-1, 0)
		"right":
			dir_vec = Vector2i(1, 0)
		_:
			return targets

	# Walk in direction until hitting a wall
	var pos: Vector2i = caster.position + dir_vec
	while game_state.is_valid_position(pos):
		var terrain := game_state.get_terrain(pos)
		if terrain == GameState.Terrain.WALL:
			break

		# Check for champion at this position
		var champ := game_state.get_champion_at(pos)
		if champ and champ.is_alive():
			targets.append(champ)

		pos += dir_vec

	return targets


func _parse_duration(duration_str: String) -> int:
	"""
	Convert duration string to numeric value.
	-1 = permanent, 0 = this turn, 1+ = number of rounds
	"""
	match duration_str.to_lower():
		"permanent":
			return -1
		"thisturn":
			return 0
		"nextturn":
			return 1
		_:
			if duration_str.is_valid_int():
				return duration_str.to_int()
			return -1


func _is_in_attack_range(caster: ChampionState, target: ChampionState) -> bool:
	"""Check if target is within caster's attack range using range rules."""
	if caster.unique_id == target.unique_id:
		return true  # Self is always in range

	var from: Vector2i = caster.position
	var to: Vector2i = target.position
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	var chebyshev_dist: int = maxi(absi(dx), absi(dy))
	var is_melee: bool = caster.current_range <= 1

	if is_melee:
		# Melee: Chebyshev distance (8 directions)
		return chebyshev_dist <= caster.current_range
	else:
		# Ranged: Adjacent squares (all 8 directions) PLUS cardinal directions at range
		# Distance 1 is always valid (melee range for ranged units)
		if chebyshev_dist == 1:
			return true

		# Beyond distance 1: must be in cardinal direction and within range
		if dx != 0 and dy != 0:
			return false

		var cardinal_dist: int = absi(dx) + absi(dy)
		return cardinal_dist <= caster.current_range
