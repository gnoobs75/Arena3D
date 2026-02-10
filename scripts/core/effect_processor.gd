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
signal cards_drawn(player_id: int, count: int, is_extra: bool)  # For Hypocrite onDraw trigger
signal immediate_movement_required(champion_ids: Array, movement_bonus: int)
signal discard_selection_required(player_id: int, caster_id: String, damage_per_card: int)
signal x_value_required(player_id: int, card_name: String, min_val: int, max_val: int)
signal choice_required(player_id: int, options: Array, choose_count: int, context: Dictionary)
signal position_selection_required(player_id: int, valid_positions: Array, context: Dictionary)
signal immediate_control_required(champion_id: String, controller_player_id: int)
signal intel_choice_required(caster_owner_id: int, own_top_card: String, opp_top_card: String)
signal discard_choice_required(player_id: int, count: int)
signal placement_selection_required(player_id: int, champion_id: String, valid_positions: Array)

var game_state: GameState

# Pending discard selection context
var _pending_discard_caster: String = ""
var _pending_discard_damage: int = 0

# Pending placement selection context (Heave "anyEmpty")
var _pending_placement_champion_id: String = ""

# Pending discard choice context (Introspection-style: player chooses which cards to discard)
var _pending_discard_choice_player: int = -1
var _pending_discard_choice_count: int = 0

# Pending Intel choice context
var _pending_intel_caster_owner: int = -1

# Damage source tracking for effects like adjacentToSource (Spell Punish)
var _damage_source_id: String = ""

# X variable system - pending input tracking
var _pending_x_context: Dictionary = {}  # Stores context when waiting for X value
var _pending_choice_context: Dictionary = {}  # Stores context when waiting for choice
var _pending_position_context: Dictionary = {}  # Stores context when waiting for position
var _current_x_value: int = 0  # Currently resolved X value for card processing

# Damage tracking for cards like Black Hole that heal based on damage dealt
var _card_damage_dealt: int = 0  # Total damage dealt during current card processing

# Draw tracking for Hypocrite's "match" draw value
var _last_player_draw_count: Dictionary = {1: 0, 2: 0}  # Track extra cards drawn per player


func set_damage_source(source_id: String) -> void:
	"""Set the damage source for effects that need it."""
	_damage_source_id = source_id


func clear_damage_source() -> void:
	"""Clear the damage source after effect resolution."""
	_damage_source_id = ""


func get_card_damage_dealt() -> int:
	"""Get total damage dealt during current card processing (for damageDealt heal value)."""
	return _card_damage_dealt


func _reset_card_damage_tracking() -> void:
	"""Reset damage tracking at start of card processing."""
	_card_damage_dealt = 0


func _add_card_damage_dealt(amount: int) -> void:
	"""Add to damage dealt tracking during card processing."""
	_card_damage_dealt += amount


# --- X Variable System ---

func request_x_value(player_id: int, card_name: String, caster: ChampionState, targets: Array, card_data: Dictionary) -> void:
	"""Request player input for X value. Max X depends on xSource (mana or hp)."""
	var x_source: String = card_data.get("xSource", "mana")
	var max_x: int = 0

	if x_source == "hp":
		# HP-based X: max is caster's current HP
		max_x = caster.current_hp
	else:
		# Mana-based X: max is remaining mana minus base cost
		var max_mana := game_state.get_mana(player_id)
		var base_cost: int = card_data.get("baseCost", 0)
		max_x = max_mana - base_cost

	if max_x <= 0:
		# Can't afford any X, use 0
		_current_x_value = 0
		return

	# Store context for when player responds
	_pending_x_context = {
		"player_id": player_id,
		"card_name": card_name,
		"caster_id": caster.unique_id,
		"targets": targets,
		"card_data": card_data,
		"max_x": max_x,
		"x_source": x_source
	}

	# Emit signal for UI to show X selector
	x_value_required.emit(player_id, card_name, 0, max_x)


func complete_x_selection(value: int) -> Dictionary:
	"""Complete X value selection and continue card processing."""
	if _pending_x_context.is_empty():
		return {"success": false, "error": "No pending X selection"}

	var ctx := _pending_x_context
	_pending_x_context = {}

	# Clamp value to valid range
	var max_x: int = ctx.get("max_x", 0)
	_current_x_value = clampi(value, 0, max_x)

	# Get caster and continue processing
	var caster := game_state.get_champion(ctx.get("caster_id", ""))
	if caster == null:
		return {"success": false, "error": "Caster not found"}

	# Spend the additional mana for X (skip for HP-based X cards like Pursuit)
	var player_id: int = ctx.get("player_id", 1)
	var x_source: String = ctx.get("x_source", "mana")
	if _current_x_value > 0 and x_source == "mana":
		game_state.spend_mana(player_id, _current_x_value)
		print("X value set to %d, spent %d additional mana" % [_current_x_value, _current_x_value])
	elif _current_x_value > 0:
		print("X value set to %d (HP-based, no mana spent)" % _current_x_value)

	# Continue processing the card
	var card_name: String = ctx.get("card_name", "")
	var targets: Array = ctx.get("targets", [])

	return process_card(card_name, caster, targets)


func get_current_x_value() -> int:
	"""Get the current X value for effect calculations."""
	return _current_x_value


func has_pending_x_selection() -> bool:
	"""Check if waiting for X value input."""
	return not _pending_x_context.is_empty()


# --- Choice System ---

func request_choice(player_id: int, options: Array, choose_count: int, context: Dictionary) -> void:
	"""Request player to choose from options (Evil Tricks style)."""
	_pending_choice_context = {
		"player_id": player_id,
		"options": options,
		"choose_count": choose_count,
		"context": context
	}

	choice_required.emit(player_id, options, choose_count, context)


func complete_choice_selection(choices: Array) -> Dictionary:
	"""Complete choice selection and apply chosen effects."""
	if _pending_choice_context.is_empty():
		return {"success": false, "error": "No pending choice"}

	var ctx := _pending_choice_context
	_pending_choice_context = {}

	var results: Array = []
	var caster_id: String = ctx.get("context", {}).get("caster_id", "")
	var caster := game_state.get_champion(caster_id)

	if caster == null:
		return {"success": false, "error": "Caster not found"}

	# Process each chosen effect
	for choice_idx in choices:
		if choice_idx >= 0 and choice_idx < ctx.get("options", []).size():
			var effect: Dictionary = ctx["options"][choice_idx]
			var result := _process_single_effect(effect, caster, [], {})
			results.append(result)

	return {
		"success": true,
		"choices": choices,
		"results": results
	}


func has_pending_choice() -> bool:
	"""Check if waiting for choice input."""
	return not _pending_choice_context.is_empty()


# --- Position Selection System ---

func request_position_selection(player_id: int, valid_positions: Array, context: Dictionary) -> void:
	"""Request player to select a board position."""
	_pending_position_context = {
		"player_id": player_id,
		"valid_positions": valid_positions,
		"context": context
	}

	position_selection_required.emit(player_id, valid_positions, context)


func complete_position_selection(position: Vector2i) -> Dictionary:
	"""Complete position selection."""
	if _pending_position_context.is_empty():
		return {"success": false, "error": "No pending position selection"}

	var ctx := _pending_position_context
	_pending_position_context = {}

	var valid_positions: Array = ctx.get("valid_positions", [])
	if position not in valid_positions:
		return {"success": false, "error": "Invalid position"}

	# Return the selected position for the caller to use
	return {
		"success": true,
		"position": position,
		"context": ctx.get("context", {})
	}


func has_pending_position_selection() -> bool:
	"""Check if waiting for position input."""
	return not _pending_position_context.is_empty()


# --- Placement Selection System (Heave "anyEmpty") ---

func resolve_placement(destination: Vector2i) -> Dictionary:
	"""Resolve pending placement by moving the champion to the destination."""
	if _pending_placement_champion_id.is_empty():
		return {"success": false, "error": "No pending placement"}

	var champion := game_state.get_champion(_pending_placement_champion_id)
	if champion == null or not champion.is_alive():
		_pending_placement_champion_id = ""
		return {"success": false, "error": "Champion not found or dead"}

	if not game_state.is_walkable(destination):
		return {"success": false, "error": "Destination not walkable"}

	var old_pos: Vector2i = champion.position
	champion.position = destination
	champion_moved.emit(champion.unique_id, old_pos, destination)
	_pending_placement_champion_id = ""

	return {"success": true, "champion_id": champion.unique_id, "from": old_pos, "to": destination}


func has_pending_placement() -> bool:
	"""Check if waiting for placement input."""
	return not _pending_placement_champion_id.is_empty()


func _get_all_empty_positions() -> Array[Vector2i]:
	"""Get all walkable, unoccupied positions on the board."""
	var positions: Array[Vector2i] = []
	for y in range(GameState.BOARD_SIZE):
		for x in range(GameState.BOARD_SIZE):
			var pos := Vector2i(x, y)
			if game_state.is_walkable(pos):
				positions.append(pos)
	return positions


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

	# Reset damage tracking for this card (used by damageDealt heal value)
	_reset_card_damage_tracking()

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
		"effects": results,
		"total_damage_dealt": _card_damage_dealt
	}


func _handle_special_card(card_name: String, caster: ChampionState, targets: Array, card_data: Dictionary) -> Dictionary:
	"""Handle cards that need special processing beyond standard effects."""
	# First check for card-level customHandler
	var custom_handler: String = card_data.get("customHandler", "")
	if not custom_handler.is_empty():
		return _process_custom({"type": "custom", "name": custom_handler}, caster, targets, card_data)

	# Then check for specific cards by name
	match card_name:
		"Bear Tank":
			return _handle_bear_tank(caster, targets)
		"From the Sky":
			return _handle_from_the_sky(caster)
	return {}


func _handle_from_the_sky(caster: ChampionState) -> Dictionary:
	"""Handle From the Sky - player selects cards to discard, each deals 2 damage to random enemy."""
	# Store context for when player confirms selection
	_pending_discard_caster = caster.unique_id
	_pending_discard_damage = 2  # 2 damage per card discarded

	# Signal that we need the player to select cards to discard
	discard_selection_required.emit(caster.owner_id, caster.unique_id, 2)

	return {
		"success": true,
		"card": "From the Sky",
		"caster": caster.unique_id,
		"pending_discard_selection": true,
		"effects": []
	}


func complete_discard_selection(discarded_cards: Array[String]) -> Dictionary:
	"""Complete the From the Sky effect after player selects cards to discard."""
	var caster := game_state.get_champion(_pending_discard_caster)
	if caster == null:
		return {"success": false, "error": "Caster not found"}

	var total_damage := discarded_cards.size() * _pending_discard_damage
	var opp_id := 2 if caster.owner_id == 1 else 1

	# Get living enemy champions
	var enemies: Array[ChampionState] = []
	for enemy: ChampionState in game_state.get_champions(opp_id):
		if enemy.is_alive():
			enemies.append(enemy)

	if enemies.is_empty():
		return {
			"success": true,
			"discarded": discarded_cards.size(),
			"damage_dealt": 0,
			"message": "No enemies to damage"
		}

	# Discard the selected cards
	var hand := game_state.get_hand(caster.owner_id)
	var discard := game_state.get_discard(caster.owner_id)
	for card_name: String in discarded_cards:
		var idx := hand.find(card_name)
		if idx != -1:
			hand.remove_at(idx)
			discard.append(card_name)

	# Distribute damage randomly among enemies
	var damage_distribution: Dictionary = {}  # enemy_id -> damage taken
	for i in range(total_damage):
		var random_enemy: ChampionState = enemies[randi() % enemies.size()]
		var dealt := random_enemy.take_damage(1)
		if dealt > 0:
			damage_dealt.emit(caster.unique_id, random_enemy.unique_id, dealt)
			EventBus.champion_damaged.emit(random_enemy.unique_id, dealt, caster.champion_name)

			if not damage_distribution.has(random_enemy.unique_id):
				damage_distribution[random_enemy.unique_id] = 0
			damage_distribution[random_enemy.unique_id] += dealt

		# Remove dead enemies from the pool
		if random_enemy.is_dead():
			enemies.erase(random_enemy)
			if enemies.is_empty():
				break

	# Clear pending context
	_pending_discard_caster = ""
	_pending_discard_damage = 0

	return {
		"success": true,
		"discarded": discarded_cards.size(),
		"total_damage": total_damage,
		"distribution": damage_distribution
	}


func complete_intel_choice(own_to_bottom: bool, opp_to_bottom: bool) -> void:
	"""Complete the Intel card choice — move cards to bottom as chosen."""
	if _pending_intel_caster_owner < 0:
		return
	var owner_id := _pending_intel_caster_owner
	var opp_id := 2 if owner_id == 1 else 1
	var own_deck := game_state.get_deck(owner_id)
	var opp_deck := game_state.get_deck(opp_id)

	if own_to_bottom and not own_deck.is_empty():
		var card: String = own_deck.pop_front()
		own_deck.push_back(card)
		print("Intel: Put own deck's %s on bottom" % card)

	if opp_to_bottom and not opp_deck.is_empty():
		var card: String = opp_deck.pop_front()
		opp_deck.push_back(card)
		print("Intel: Put opponent's %s on bottom" % card)

	_pending_intel_caster_owner = -1


func _process_single_effect(effect: Dictionary, caster: ChampionState, targets: Array, card_data: Dictionary) -> Dictionary:
	"""Process a single effect from the card's effect array."""
	var result := {"type": "unknown", "success": false}

	# Get effect type - cards.json uses "type" field
	var effect_type: String = str(effect.get("type", ""))

	# For self-targeting cards or cards with no target, ensure caster is included in targets
	var effective_targets := targets
	var card_target_type: String = str(card_data.get("target", "")).to_lower()
	if (card_target_type == "self" or card_target_type == "none" or card_target_type == "") and effective_targets.is_empty():
		effective_targets = [caster.unique_id]

	# Check conditions before processing effect
	var condition: Dictionary = effect.get("condition", {})
	if not condition.is_empty():
		var condition_result := _check_effect_condition(condition, caster, effective_targets, card_data)
		if not condition_result.get("passed", true):
			return {
				"type": effect_type,
				"success": false,
				"reason": condition_result.get("reason", "condition_failed")
			}
		# Some conditions modify the effect value
		if condition_result.has("modified_value"):
			effect = effect.duplicate()
			effect["value"] = condition_result["modified_value"]

	# Determine effect type and process
	match effect_type.to_lower():
		"damage":
			result = _process_damage(effect, caster, effective_targets, card_data)
		"heal":
			result = _process_heal(effect, caster, effective_targets, card_data)
		"statmod":
			result = _process_stat_mod(effect, caster, effective_targets)
		"buff":
			result = _process_buff(effect, caster, effective_targets)
		"debuff":
			result = _process_debuff(effect, caster, effective_targets)
		"move":
			result = _process_move(effect, caster, effective_targets, card_data)
		"draw":
			result = _process_draw(effect, caster, effective_targets, str(card_data.get("name", "")))
		"discard":
			result = _process_discard(effect, caster, effective_targets)
		"custom":
			result = _process_custom(effect, caster, targets, card_data)
		"gainmana":
			result = _process_gain_mana(effect, caster)
		"lockmana":
			result = _process_lock_mana(effect, caster)
		"stealmana":
			result = _process_steal_mana(effect, caster)
		"control":
			result = _process_control(effect, caster, effective_targets)
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
	var target_type: String = str(card_data.get("target", ""))
	var scope_lower := scope.to_lower()

	# Handle AOE random damage (e.g., Rain of Arrows)
	if scope == "random" and (card_range == "AOE" or effect_range == "AOE"):
		return _process_aoe_random_damage(damage_value, caster, targets, card_data)

	# Handle position-targeted AOE damage (e.g., Acid Bomb, Black Hole)
	# This is when scope is "all" and target is "position" with AOE range
	if (scope_lower == "all" or scope_lower == "allchamps") and target_type == "position" and card_range == "AOE":
		return _process_position_aoe_damage(damage_value, caster, targets, card_data)

	# Handle direction-targeted damage (e.g., Ground Pound - damage all in a direction)
	if target_type == "direction" and (scope_lower == "all" or card_range == "LOS"):
		return _process_direction_damage(damage_value, caster, targets, card_data)

	var actual_targets := _resolve_targets(scope, caster, targets, card_range)
	var total_damage := 0

	for target: ChampionState in actual_targets:
		var amount := _calculate_damage(damage_value, caster, target)
		var dealt := target.take_damage(amount)
		total_damage += dealt
		_add_card_damage_dealt(dealt)  # Track for damageDealt heal value
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
		_add_card_damage_dealt(dealt)  # Track for damageDealt heal value
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


func _process_position_aoe_damage(damage_value, caster: ChampionState, targets: Array, card_data: Dictionary) -> Dictionary:
	"""Handle AOE damage centered on a target position (e.g., Acid Bomb).
	Deals damage to ALL champions (friendly and enemy) within AOE radius of the position."""
	var aoe_radius: int = card_data.get("aoeRadius", 1)  # Default AOE radius

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
		print("EffectProcessor: Position AOE damage - no valid target position in targets: %s" % [targets])
		return {"type": "damage", "success": false, "error": "No target position"}

	print("EffectProcessor: Position AOE target: %s, radius: %d" % [target_pos, aoe_radius])

	# Find ALL champions within AOE range of target position (both friendly and enemy)
	var champions_in_aoe: Array[ChampionState] = []
	for champ: ChampionState in game_state.get_all_champions():
		if champ.is_alive():
			var dist: int = maxi(absi(champ.position.x - target_pos.x), absi(champ.position.y - target_pos.y))
			if dist <= aoe_radius:
				champions_in_aoe.append(champ)
				print("EffectProcessor: %s at %s is in AOE (dist=%d)" % [champ.champion_name, champ.position, dist])

	if champions_in_aoe.is_empty():
		print("EffectProcessor: Position AOE damage - no champions in range of position %s" % target_pos)
		return {"type": "damage", "success": true, "total_damage": 0, "target_count": 0}

	# Deal damage to each target
	var total_damage := 0
	var damage_amount := _calculate_damage(damage_value, caster, caster)

	for target: ChampionState in champions_in_aoe:
		var dealt := target.take_damage(damage_amount)
		total_damage += dealt
		_add_card_damage_dealt(dealt)  # Track for damageDealt heal value
		damage_dealt.emit(caster.unique_id, target.unique_id, dealt)
		if dealt > 0:
			EventBus.champion_damaged.emit(target.unique_id, dealt, caster.champion_name)

	print("EffectProcessor: Position AOE damage - dealt %d total to %d champions" % [total_damage, champions_in_aoe.size()])

	return {
		"type": "damage",
		"success": true,
		"total_damage": total_damage,
		"target_count": champions_in_aoe.size()
	}


func _process_direction_damage(damage_value, caster: ChampionState, targets: Array, _card_data: Dictionary) -> Dictionary:
	"""Handle direction-targeted damage (e.g., Ground Pound - damage all in a line)."""
	# Get direction from targets
	var direction: String = ""
	if targets.size() > 0:
		direction = str(targets[0]).to_lower()

	if direction.is_empty() or direction not in ["up", "down", "left", "right"]:
		print("EffectProcessor: Direction damage - invalid direction: %s" % direction)
		return {"type": "damage", "success": false, "error": "Invalid direction"}

	print("EffectProcessor: Direction damage - direction=%s from %s" % [direction, caster.position])

	# Get all champions in that direction
	var champions_in_line := _get_champions_in_direction(caster, direction)

	if champions_in_line.is_empty():
		print("EffectProcessor: Direction damage - no champions in direction %s" % direction)
		return {"type": "damage", "success": true, "total_damage": 0, "target_count": 0}

	# Deal damage to each champion in the line
	var total_damage := 0
	var damage_amount := _calculate_damage(damage_value, caster, caster)

	for target: ChampionState in champions_in_line:
		var dealt := target.take_damage(damage_amount)
		total_damage += dealt
		_add_card_damage_dealt(dealt)  # Track for damageDealt heal value
		damage_dealt.emit(caster.unique_id, target.unique_id, dealt)
		if dealt > 0:
			EventBus.champion_damaged.emit(target.unique_id, dealt, caster.champion_name)
		print("EffectProcessor: Direction damage - %s took %d damage" % [target.champion_name, dealt])

	return {
		"type": "damage",
		"success": true,
		"total_damage": total_damage,
		"target_count": champions_in_line.size()
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
			"random1or2":
				# Randomly deal 1 or 2 damage (Dark Offering, etc.)
				return randi() % 2 + 1
			"discardCount":
				# Damage equals number of cards discarded this effect (placeholder - needs context)
				return 1
			"handSize":
				# Damage based on hand size
				return game_state.get_hand(caster.owner_id).size()
			"oppHandSize":
				# Damage based on opponent's hand size
				var opp_id := 2 if caster.owner_id == 1 else 1
				return game_state.get_hand(opp_id).size()
			"cost":
				# Damage equals card's mana cost (dealCostDamage)
				# This should be passed in from the card data
				return 0
			"X":
				# X variable - use current X value
				return _current_x_value
			"X+1":
				return _current_x_value + 1
			"2X":
				return _current_x_value * 2
			_:
				# Try to parse as integer string
				if damage_value.is_valid_int():
					return damage_value.to_int()
				# Check for X expressions like "X+2"
				if damage_value.begins_with("X"):
					var modifier: String = damage_value.substr(1)
					if modifier.begins_with("+") and modifier.substr(1).is_valid_int():
						return _current_x_value + modifier.substr(1).to_int()
					elif modifier.begins_with("-") and modifier.substr(1).is_valid_int():
						return _current_x_value - modifier.substr(1).to_int()
				return 0
	elif damage_value is Dictionary:
		var base: int = damage_value.get("base", 0)
		var per_power: int = damage_value.get("perPower", 0)
		var per_discard: int = damage_value.get("perDiscard", 0)
		var per_x: int = damage_value.get("perX", 0)

		var total := base + (per_power * caster.current_power)

		# perDiscard multiplier (damage per card discarded)
		if per_discard > 0:
			# This needs context from a previous discard effect
			# For now, check a pending context
			var discarded: int = damage_value.get("_discarded_count", 0)
			total += per_discard * discarded

		# perX multiplier (damage per X value)
		if per_x > 0:
			total += per_x * _current_x_value

		return total

	return 0


# --- Heal Processing ---

func _process_heal(effect: Dictionary, caster: ChampionState, targets: Array, card_data: Dictionary = {}) -> Dictionary:
	# Support both new format (value) and old format (heal)
	var heal_value = effect.get("value", effect.get("heal", 0))
	var scope: String = str(effect.get("scope", "target"))
	var condition: Dictionary = effect.get("condition", {})
	var card_range: String = str(card_data.get("range", ""))
	var target_type: String = str(card_data.get("target", ""))

	# Handle position-targeted AOE healing (e.g., Healing Rain)
	var scope_lower := scope.to_lower()
	if (scope_lower == "all" or scope_lower == "allchamps") and target_type == "position" and card_range == "AOE":
		print("EffectProcessor: Position AOE heal detected - heal_value=%s (type=%s), scope=%s" % [heal_value, typeof(heal_value), scope])
		return _process_position_aoe_heal(heal_value, caster, targets, card_data)

	var actual_targets := _resolve_targets(scope, caster, targets)
	var total_healed := 0

	for target: ChampionState in actual_targets:
		# Check condition (e.g., ifDamageAbove for Second Wind)
		if not condition.is_empty():
			if not _check_heal_condition(condition, target):
				continue

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


func _process_position_aoe_heal(heal_value, caster: ChampionState, targets: Array, card_data: Dictionary) -> Dictionary:
	"""Handle AOE healing centered on a target position (e.g., Healing Rain).
	Heals ALL champions within AOE radius of the position."""
	var aoe_radius: int = card_data.get("aoeRadius", 1)

	# Find the target position from targets array
	var target_pos: Vector2i = Vector2i(-999, -999)
	var found_position := false
	if targets.size() > 0:
		var first_target = targets[0]
		if first_target is Vector2i:
			target_pos = first_target
			found_position = true
		elif first_target is String:
			var parts: PackedStringArray = first_target.split(",")
			if parts.size() == 2:
				target_pos = Vector2i(int(parts[0]), int(parts[1]))
				found_position = true

	if not found_position:
		print("EffectProcessor: Position AOE heal - no valid target position in targets: %s" % [targets])
		return {"type": "heal", "success": false, "error": "No target position"}

	print("EffectProcessor: Position AOE heal at %s, radius: %d" % [target_pos, aoe_radius])

	# Find ALL champions within AOE range of target position
	var champions_in_aoe: Array[ChampionState] = []
	for champ: ChampionState in game_state.get_all_champions():
		if champ.is_alive():
			var dist: int = maxi(absi(champ.position.x - target_pos.x), absi(champ.position.y - target_pos.y))
			if dist <= aoe_radius:
				champions_in_aoe.append(champ)
				print("EffectProcessor: %s at %s is in heal AOE (dist=%d)" % [champ.champion_name, champ.position, dist])

	if champions_in_aoe.is_empty():
		print("EffectProcessor: Position AOE heal - no champions in range of position %s" % target_pos)
		return {"type": "heal", "success": true, "total_healed": 0}

	# Heal each target
	var total_healed := 0
	print("EffectProcessor: About to calculate heal - heal_value=%s (type=%s)" % [heal_value, typeof(heal_value)])
	var heal_amount := _calculate_heal(heal_value, caster, caster)
	print("EffectProcessor: Position AOE heal amount calculated: %d" % heal_amount)

	for target: ChampionState in champions_in_aoe:
		print("EffectProcessor: Healing %s (HP: %d/%d, noHeal: %s)" % [target.champion_name, target.current_hp, target.max_hp, target.has_debuff("noHeal")])
		var healed := target.heal(heal_amount)
		total_healed += healed
		healing_done.emit(caster.unique_id, target.unique_id, healed)
		if healed > 0:
			EventBus.champion_healed.emit(target.unique_id, healed, caster.champion_name)

	print("EffectProcessor: Position AOE heal - healed %d total to %d champions" % [total_healed, champions_in_aoe.size()])

	return {
		"type": "heal",
		"success": true,
		"total_healed": total_healed,
		"target_count": champions_in_aoe.size()
	}


func _check_heal_condition(condition: Dictionary, target: ChampionState) -> bool:
	"""Check if a heal condition is met."""
	if condition.has("ifDamageAbove"):
		var threshold: int = condition["ifDamageAbove"]
		return target.damage_taken_last_turn > threshold

	if condition.has("ifDamageAtLeast"):
		var threshold: int = condition["ifDamageAtLeast"]
		return target.damage_taken_last_turn >= threshold

	return true


func _check_effect_condition(condition: Dictionary, caster: ChampionState, targets: Array, _card_data: Dictionary) -> Dictionary:
	"""Check if an effect's condition is met. Returns {passed: bool, reason: String, modified_value: Variant}"""
	var result := {"passed": true}

	# ifNotInRange - effect only triggers if caster is NOT in enemy attack range
	if condition.has("ifNotInRange"):
		var opp_id := 2 if caster.owner_id == 1 else 1
		for enemy: ChampionState in game_state.get_champions(opp_id):
			if enemy.is_alive() and _is_in_attack_range(enemy, caster):
				return {"passed": false, "reason": "in_enemy_range"}

	# ifOnlyCard - effect uses different value if this was the only card in hand
	if condition.has("ifOnlyCard"):
		var hand := game_state.get_hand(caster.owner_id)
		# Hand was already reduced by 1 when card was played, so check if now empty
		if hand.is_empty():
			result["modified_value"] = condition["ifOnlyCard"]

	# ifSpell - effect only triggers if damage came from a spell (not combat)
	if condition.has("ifSpell"):
		# This requires damage context from game_controller
		# For now, assume spell context is set externally
		pass

	# chance - effect has a random chance to trigger
	if condition.has("chance"):
		var chance_value: float = condition["chance"]
		if randf() > chance_value:
			return {"passed": false, "reason": "chance_failed"}

	# ifLifeBelow - effect triggers if target's life is below threshold
	if condition.has("ifLifeBelow"):
		var threshold: int = condition["ifLifeBelow"]
		if not targets.is_empty():
			var target := game_state.get_champion(str(targets[0]))
			if target and target.current_hp > threshold:
				return {"passed": false, "reason": "life_not_below_threshold"}

	# ifLifeAbove - effect triggers if target's life is above threshold
	if condition.has("ifLifeAbove"):
		var threshold: int = condition["ifLifeAbove"]
		if not targets.is_empty():
			var target := game_state.get_champion(str(targets[0]))
			if target and target.current_hp < threshold:
				return {"passed": false, "reason": "life_not_above_threshold"}

	# ifHasDebuff - effect triggers if target has a specific debuff
	if condition.has("ifHasDebuff"):
		var debuff_name: String = condition["ifHasDebuff"]
		if not targets.is_empty():
			var target := game_state.get_champion(str(targets[0]))
			if target and not target.has_debuff(debuff_name):
				return {"passed": false, "reason": "missing_debuff"}

	# ifHasBuff - effect triggers if target has a specific buff
	if condition.has("ifHasBuff"):
		var buff_name: String = condition["ifHasBuff"]
		if not targets.is_empty():
			var target := game_state.get_champion(str(targets[0]))
			if target and not target.has_buff(buff_name):
				return {"passed": false, "reason": "missing_buff"}

	# ifInDiscard - effect triggers if specific card type is in discard
	if condition.has("ifInDiscard"):
		var filter: String = condition["ifInDiscard"]
		var discard := game_state.get_discard(caster.owner_id)
		var found := false
		for card_name: String in discard:
			if _card_matches_filter(card_name, filter):
				found = true
				break
		if not found:
			return {"passed": false, "reason": "card_not_in_discard"}

	# ifDrawnStart - effect triggers if card was drawn at start of turn
	# This needs to be tracked by game_state
	if condition.has("ifDrawnStart"):
		# For now, assume false - needs proper implementation
		pass

	return result


func _calculate_heal(heal_value, caster: ChampionState, target: ChampionState) -> int:
	"""Calculate heal amount from various formats."""
	# Handle numeric types (JSON may parse numbers as float)
	if heal_value is int or heal_value is float:
		return int(heal_value)
	elif heal_value is String:
		match heal_value:
			"damageDealt":
				# Heal for damage dealt by this card (for Black Hole, etc.)
				return _card_damage_dealt
			"damageTaken":
				# Heal for damage taken LAST turn (for Second Wind, etc.)
				return target.damage_taken_last_turn
			"damageTakenThisTurn":
				return target.damage_taken_this_turn
			"missingHP":
				# Total HP missing (old behavior if needed)
				return target.max_hp - target.current_hp
			"halfDamageTaken":
				return target.damage_taken_last_turn / 2
			"halfMissingHP":
				return (target.max_hp - target.current_hp) / 2
			"oppHandSize":
				var opp_id := 2 if caster.owner_id == 1 else 1
				return game_state.get_hand(opp_id).size()
			"X":
				return _current_x_value
			"X+1":
				return _current_x_value + 1
			"2X":
				return _current_x_value * 2
			_:
				# Check for X expressions
				if heal_value.begins_with("X"):
					var modifier: String = heal_value.substr(1)
					if modifier.begins_with("+") and modifier.substr(1).is_valid_int():
						return _current_x_value + modifier.substr(1).to_int()
					elif modifier.begins_with("-") and modifier.substr(1).is_valid_int():
						return _current_x_value - modifier.substr(1).to_int()
				return 0

	return 0


# --- Stat Mod Processing ---

func _process_stat_mod(effect: Dictionary, caster: ChampionState, targets: Array) -> Dictionary:
	# cards.json has flat structure: {"type": "statMod", "stat": "power", "value": 2, "duration": "thisTurn"}
	var stat: String = str(effect.get("stat", ""))
	var duration: String = str(effect.get("duration", "permanent"))
	var scope: String = str(effect.get("scope", "target"))
	var condition: Dictionary = effect.get("condition", {})

	var actual_targets := _resolve_targets(scope, caster, targets)
	var duration_value := _parse_duration(duration)

	# Handle "random" stat - pick a random stat for now (could be player choice)
	if stat == "random":
		var stats := ["power", "range", "movementSpeed"]
		stat = stats[randi() % stats.size()]

	for target: ChampionState in actual_targets:
		# Calculate amount - may depend on conditions or dynamic values
		var amount: int = _calculate_stat_mod_amount(effect, caster, target)

		# Check conditions
		if not condition.is_empty():
			if not _check_stat_mod_condition(condition, caster, target):
				continue

		if amount == 0:
			continue

		var buff_name := stat + "Bonus" if amount > 0 else stat + "Reduction"
		if amount > 0:
			target.add_buff(buff_name, duration_value, absi(amount), caster.unique_id)
		else:
			target.add_debuff(buff_name, duration_value, absi(amount), caster.unique_id)

	return {
		"type": "statMod",
		"success": true,
		"stat": stat,
		"duration": duration
	}


func _calculate_stat_mod_amount(effect: Dictionary, caster: ChampionState, _target: ChampionState) -> int:
	"""Calculate the stat mod amount, handling dynamic values."""
	var value = effect.get("value", effect.get("amount", 0))
	var condition: Dictionary = effect.get("condition", {})

	# Handle integer values directly
	if value is int:
		var base_amount: int = value
		# Apply scaling from condition
		if condition.has("scale"):
			base_amount *= _get_scale_multiplier(condition["scale"], caster)
		return base_amount

	if value is float:
		return int(value)

	# Handle string values
	if value is String:
		match value:
			"handSize":
				return game_state.get_hand(caster.owner_id).size()
			"power":
				return caster.current_power
			"X":
				# X variable - use current X value
				return _current_x_value
			"X+1":
				return _current_x_value + 1
			"2X":
				return _current_x_value * 2
			_:
				if value.is_valid_int():
					return value.to_int()
				# Check for X expressions
				if value.begins_with("X"):
					var modifier: String = value.substr(1)
					if modifier.begins_with("+") and modifier.substr(1).is_valid_int():
						return _current_x_value + modifier.substr(1).to_int()
					elif modifier.begins_with("-") and modifier.substr(1).is_valid_int():
						return _current_x_value - modifier.substr(1).to_int()
				return 0

	return 0


func _get_scale_multiplier(scale_type: String, caster: ChampionState) -> int:
	"""Get the multiplier for scaling effects."""
	match scale_type:
		"enemiesInRange":
			var count := 0
			var opp_id := 2 if caster.owner_id == 1 else 1
			var range_calc := RangeCalculator.new()
			for enemy: ChampionState in game_state.get_champions(opp_id):
				if enemy.is_alive() and range_calc.can_attack(caster, enemy, game_state):
					count += 1
			return count
		"discarded":
			# This should be set by a previous discard effect
			# For now return 1 as a placeholder
			return 1
		_:
			return 1


func _check_stat_mod_condition(condition: Dictionary, _caster: ChampionState, target: ChampionState) -> bool:
	"""Check if a stat mod condition is met."""
	if condition.has("ifLifeBelow"):
		var threshold: int = condition["ifLifeBelow"]
		return target.current_hp <= threshold

	if condition.has("ifLifeAbove"):
		var threshold: int = condition["ifLifeAbove"]
		return target.current_hp >= threshold

	# scale conditions are handled in _calculate_stat_mod_amount
	if condition.has("scale"):
		return true

	return true


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

	# Handle terrain-creating buffs (target is a position, not a champion)
	if buff_name == "createWall":
		return _process_create_wall(targets, scope)

	var actual_targets := _resolve_targets(scope, caster, targets)
	var duration_value := _parse_duration(duration)

	var extra_data: Dictionary = {}

	for target: ChampionState in actual_targets:
		target.add_buff(buff_name, duration_value, stacks, caster.unique_id)
		buff_applied.emit(target.unique_id, buff_name, duration_value)
		EventBus.champion_buff_applied.emit(target.unique_id, buff_name, duration_value)

		# Special handling for buffs that need game_state access
		match buff_name:
			"gainMana":
				# Jackpot - immediately grant mana to the buff target's owner
				game_state.add_mana(target.owner_id, stacks)
				extra_data["mana_granted"] = stacks
				print("%s gained %d mana (Jackpot/gainMana buff)" % [target.champion_name, stacks])
			"createPits":
				# Pit of Despair - create temporary pits around the Dark Wizard
				var pit_positions := game_state.create_pits_around(target.position)
				extra_data["pit_positions"] = pit_positions
				print("Created pits around %s at positions: %s" % [target.champion_name, pit_positions])
			"shuffleDiscard":
				# Immediately shuffle discard into deck
				var count := game_state.shuffle_discard_into_deck(target.owner_id)
				extra_data["cards_shuffled"] = count
				print("Shuffled %d cards from discard into deck" % count)
			"boostFlasks":
				# Alchemist's boost - next flask has double effect
				# This is tracked as a buff and consumed when flask is used
				print("%s: Next flask will have boosted effect" % target.champion_name)
			"spectreEssence":
				# Dark Wizard gains power from kills
				print("%s: Will gain power from kills (Spectre Essence)" % target.champion_name)

	return {
		"type": "buff",
		"success": true,
		"buff": buff_name,
		"targets": actual_targets.size(),
		"extra": extra_data
	}


func _process_create_wall(targets: Array, scope: String) -> Dictionary:
	"""Handle Spirit Wall - create temporary walls at target position and optionally adjacent tiles."""
	# Extract target position from targets array
	var target_pos: Vector2i = Vector2i(-999, -999)
	var found_position := false

	if targets.size() > 0:
		var first_target = targets[0]
		if first_target is Vector2i:
			target_pos = first_target
			found_position = true
		elif first_target is String:
			var parts: PackedStringArray = first_target.split(",")
			if parts.size() == 2:
				target_pos = Vector2i(int(parts[0]), int(parts[1]))
				found_position = true

	if not found_position:
		print("EffectProcessor: createWall - no valid target position")
		return {"type": "buff", "success": false, "error": "No target position"}

	var wall_positions: Array[Vector2i] = []

	# scope "adjacent" means target + all adjacent tiles
	if scope.to_lower() == "adjacent":
		wall_positions = game_state.create_walls_at_and_around(target_pos)
	else:
		# Just the target position
		if game_state.is_valid_position(target_pos):
			var terrain := game_state.get_terrain(target_pos)
			if terrain == GameState.Terrain.EMPTY:
				var occupant := game_state.get_champion_at(target_pos)
				if occupant == null:
					game_state.set_temporary_terrain(target_pos, GameState.Terrain.WALL)
					wall_positions.append(target_pos)

	print("EffectProcessor: Spirit Wall created %d walls at/around %s" % [wall_positions.size(), target_pos])

	return {
		"type": "buff",
		"success": true,
		"buff": "createWall",
		"wall_positions": wall_positions,
		"walls_created": wall_positions.size()
	}


# --- Debuff Processing ---

func _process_debuff(effect: Dictionary, caster: ChampionState, targets: Array) -> Dictionary:
	# cards.json uses "name" for debuff name: {"type": "debuff", "name": "canAttack", "value": false, "duration": "thisTurn"}
	var debuff_name: String = str(effect.get("name", effect.get("debuff", "")))
	var duration: String = str(effect.get("duration", "permanent"))
	var raw_value = effect.get("stacks", effect.get("value", 1))
	var stacks: int
	if raw_value is String and str(raw_value).to_upper() == "X":
		stacks = _current_x_value
	else:
		stacks = _to_int(raw_value)
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

func _process_move(effect: Dictionary, caster: ChampionState, targets: Array, card_data: Dictionary = {}) -> Dictionary:
	# cards.json uses "value" for move type: {"type": "move", "value": "overWall"}
	var move_type: String = str(effect.get("value", effect.get("move", "")))
	var scope: String = str(effect.get("scope", "target"))
	var scope_lower := scope.to_lower()
	var movement_bonus: int = _to_int(effect.get("bonus", 0))
	var card_range: String = str(card_data.get("range", ""))
	var target_type: String = str(card_data.get("target", ""))

	# Handle position-targeted AOE movement (e.g., Light Bomb - push all away from target position)
	if (scope_lower == "all" or scope_lower == "allchamps") and target_type == "position" and card_range == "AOE":
		return _process_position_aoe_move(move_type, caster, targets, card_data)

	var actual_targets := _resolve_targets(scope, caster, targets, card_range)
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

	# "anyEmpty" - requires player/AI to pick destination tile (Heave)
	if move_type == "anyEmpty":
		if actual_targets.is_empty():
			return {"type": "move", "success": false, "reason": "no_targets"}
		var target: ChampionState = actual_targets[0]
		var valid_positions: Array[Vector2i] = _get_all_empty_positions()
		if valid_positions.is_empty():
			return {"type": "move", "success": false, "reason": "no_empty_positions"}
		_pending_placement_champion_id = target.unique_id
		placement_selection_required.emit(caster.owner_id, target.unique_id, valid_positions)
		return {
			"type": "move",
			"success": true,
			"move_type": move_type,
			"pending_placement": true,
			"champion_id": target.unique_id,
			"valid_positions": valid_positions
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


func _process_control(effect: Dictionary, caster: ChampionState, targets: Array) -> Dictionary:
	"""Process mind control effect - allows caster's player to move and attack with target enemy."""
	var control_type: String = str(effect.get("value", "moveAndAttack"))
	var target_ids: Array = []

	for target_id in targets:
		var target: ChampionState = null
		if target_id is ChampionState:
			target = target_id
		else:
			target = game_state.get_champion(str(target_id))

		if target == null or not target.is_alive():
			continue

		# Reset target's action flags so they can move and attack
		target.has_moved = false
		target.has_attacked = false
		target.movement_remaining = target.current_movement
		target_ids.append(target.unique_id)

	if target_ids.is_empty():
		return {"type": "control", "success": false, "reason": "no_valid_targets"}

	# Signal that mind control is required - the controller is the caster's owner
	var controller_player_id: int = caster.owner_id
	for tid: String in target_ids:
		immediate_control_required.emit(tid, controller_player_id)

	return {
		"type": "control",
		"success": true,
		"control_type": control_type,
		"pending_control": true,
		"champion_ids": target_ids,
		"controller_player_id": controller_player_id
	}


func _process_position_aoe_move(move_type: String, caster: ChampionState, targets: Array, card_data: Dictionary) -> Dictionary:
	"""Handle position-targeted AOE movement (e.g., Light Bomb - push all away from target position)."""
	var aoe_radius: int = card_data.get("aoeRadius", 1)

	# Find the target position from targets array
	var target_pos: Vector2i = Vector2i(-999, -999)
	var found_position := false
	if targets.size() > 0:
		var first_target = targets[0]
		if first_target is Vector2i:
			target_pos = first_target
			found_position = true
		elif first_target is String:
			var parts: PackedStringArray = first_target.split(",")
			if parts.size() == 2:
				target_pos = Vector2i(int(parts[0]), int(parts[1]))
				found_position = true

	if not found_position:
		print("EffectProcessor: Position AOE move - no valid target position")
		return {"type": "move", "success": false, "error": "No target position"}

	print("EffectProcessor: Position AOE move at %s, type=%s, radius=%d" % [target_pos, move_type, aoe_radius])

	# Find ALL champions within AOE range (excluding the caster for "all other champions")
	var champions_in_aoe: Array[ChampionState] = []
	for champ: ChampionState in game_state.get_all_champions():
		if champ.is_alive() and champ.unique_id != caster.unique_id:
			var dist: int = maxi(absi(champ.position.x - target_pos.x), absi(champ.position.y - target_pos.y))
			# Include all champions within AOE radius (excluding caster)
			if dist <= aoe_radius:
				champions_in_aoe.append(champ)

	if champions_in_aoe.is_empty():
		print("EffectProcessor: Position AOE move - no champions in range")
		return {"type": "move", "success": true, "moves_done": 0}

	var moves_done := 0

	for champ: ChampionState in champions_in_aoe:
		var new_pos: Vector2i = _calculate_push_from_position(target_pos, champ, move_type)
		if new_pos != champ.position:
			var old_pos: Vector2i = champ.position
			champ.position = new_pos
			champion_moved.emit(champ.unique_id, old_pos, new_pos)
			moves_done += 1
			print("EffectProcessor: Pushed %s from %s to %s" % [champ.champion_name, old_pos, new_pos])

	return {
		"type": "move",
		"success": true,
		"move_type": move_type,
		"moves_done": moves_done
	}


func _calculate_push_from_position(source_pos: Vector2i, target: ChampionState, move_type: String) -> Vector2i:
	"""Calculate where to push a champion from a source position."""
	var dir := Vector2i(
		signi(target.position.x - source_pos.x),
		signi(target.position.y - source_pos.y)
	)

	# If champion is at same position (shouldn't happen for AOE), don't move
	if dir == Vector2i.ZERO:
		return target.position

	match move_type:
		"toWall":
			# Push until hitting a wall or board edge
			var current := target.position
			var max_push := 10  # Safety limit
			for _i in range(max_push):
				var next := current + dir
				if not game_state.is_walkable(next):
					break
				current = next
			return current
		"away":
			# Push one tile
			var next := target.position + dir
			if game_state.is_walkable(next):
				return next
		"awayTwo":
			# Push two tiles
			var current := target.position
			for _j in range(2):
				var next := current + dir
				if not game_state.is_walkable(next):
					break
				current = next
			return current

	return target.position


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
		"overWall":
			# Push target through walls until reaching empty tile beyond
			return _find_over_wall_destination(target, caster)
		"adjacentToSource":
			# Move target adjacent to the damage source (from damage context)
			return _find_adjacent_to_source(target)
		"toTarget":
			# Move caster to target's position (swap or teleport)
			if game_state.is_walkable(target.position):
				return target.position
		"randomAdjacent":
			# Move to random adjacent empty tile
			var adjacent := pathfinder.get_empty_adjacent_tiles(target.position, true)
			if not adjacent.is_empty():
				return adjacent[randi() % adjacent.size()]
		"LOS":
			# Move to a random empty position in line of sight from caster (Distract)
			return _find_los_destination(caster, target)

	return target.position


func _find_los_destination(caster: ChampionState, target: ChampionState) -> Vector2i:
	"""Find an empty position in line of sight from caster to move target to."""
	var valid_positions: Array[Vector2i] = []
	var directions := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

	# Check each cardinal direction from caster
	for dir: Vector2i in directions:
		var pos := caster.position + dir
		while game_state.is_valid_position(pos):
			var terrain := game_state.get_terrain(pos)
			if terrain == GameState.Terrain.WALL:
				break  # Stop at walls

			# Check if position is walkable and empty
			if game_state.is_walkable(pos):
				var occupant := game_state.get_champion_at(pos)
				if occupant == null or occupant.unique_id == target.unique_id:
					valid_positions.append(pos)

			pos += dir

	if valid_positions.is_empty():
		return target.position  # No valid LOS positions

	# Pick a random valid position (AI could be smarter about this)
	return valid_positions[randi() % valid_positions.size()]


func _find_over_wall_destination(target: ChampionState, caster: ChampionState) -> Vector2i:
	"""Find destination when pushing target over/through walls."""
	var target_pos: Vector2i = target.position
	var caster_pos: Vector2i = caster.position

	# Calculate push direction (away from caster)
	var dx: int = target_pos.x - caster_pos.x
	var dy: int = target_pos.y - caster_pos.y

	# Determine primary push direction (cardinal only)
	var push_dir: Vector2i = Vector2i.ZERO
	if absi(dx) >= absi(dy):
		push_dir = Vector2i(1, 0) if dx >= 0 else Vector2i(-1, 0)
	else:
		push_dir = Vector2i(0, 1) if dy >= 0 else Vector2i(0, -1)

	if push_dir == Vector2i.ZERO:
		push_dir = Vector2i(1, 0)

	# Push until we find an empty tile AFTER passing through at least one wall
	var current: Vector2i = target_pos
	var found_wall := false
	var last_valid: Vector2i = target_pos

	while true:
		current += push_dir

		if not game_state.is_valid_position(current):
			break  # Hit edge of map

		var terrain := game_state.get_terrain(current)

		if terrain == GameState.Terrain.WALL:
			found_wall = true
			continue  # Pass through wall

		if terrain == GameState.Terrain.PIT:
			continue  # Pass over pit

		# Check for another champion blocking
		var occupant := game_state.get_champion_at(current)
		if occupant != null and occupant.unique_id != target.unique_id:
			if found_wall:
				break  # Can't land on champion after passing wall
			continue  # Pass through before finding wall

		# Found an empty tile
		if found_wall:
			return current  # Land here after passing through wall

		last_valid = current

	# If we found a wall but couldn't find landing spot, return last valid
	return last_valid


func _find_adjacent_to_source(target: ChampionState) -> Vector2i:
	"""Move target adjacent to the damage source champion."""
	# Get damage context from game_controller (needs to be passed or stored globally)
	# For now, we'll use a class variable that can be set before processing
	if _damage_source_id.is_empty():
		return target.position

	var source := game_state.get_champion(_damage_source_id)
	if source == null:
		return target.position

	var pathfinder := Pathfinder.new(game_state)
	var adjacent := pathfinder.get_empty_adjacent_tiles(source.position, true)

	if adjacent.is_empty():
		return target.position

	# Pick the closest adjacent tile to the target
	var best_pos: Vector2i = adjacent[0]
	var best_dist: int = 999
	for pos: Vector2i in adjacent:
		var dist: int = absi(pos.x - target.position.x) + absi(pos.y - target.position.y)
		if dist < best_dist:
			best_dist = dist
			best_pos = pos

	return best_pos


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

func _process_draw(effect: Dictionary, caster: ChampionState, _targets: Array, source_card_name: String = "") -> Dictionary:
	# cards.json uses "value" for draw count
	var draw_value = effect.get("value", effect.get("draw", 1))
	var draw_count: int = 0

	# Check for condition object which may contain from/filter/maxCost/scale
	var condition: Dictionary = effect.get("condition", {})

	# Handle special "match" value for Hypocrite (draw same as opponent)
	if draw_value is String and draw_value == "match":
		var scale: String = condition.get("scale", "")
		if scale == "oppDraw":
			# Draw the same number as opponent drew last
			var opp_id := 2 if caster.owner_id == 1 else 1
			draw_count = _last_player_draw_count.get(opp_id, 0)
			if draw_count <= 0:
				return {"type": "draw", "success": true, "cards_drawn": 0}
	else:
		draw_count = _to_int(draw_value)
		if draw_count == 0:
			draw_count = 1  # Default to drawing 1 card

	var from: String = str(effect.get("from", condition.get("from", "deck")))
	var filter: String = str(effect.get("filter", condition.get("filter", "")))
	var max_cost: int = condition.get("maxCost", -1)  # -1 means no limit

	var drawn_cards: Array[String] = []

	for i in range(draw_count):
		var drawn := ""
		match from:
			"deck":
				drawn = game_state.draw_card(caster.owner_id)
			"discard":
				drawn = _draw_from_discard(caster.owner_id, filter, max_cost, source_card_name)
			"oppDiscard":
				var opp_id := 2 if caster.owner_id == 1 else 1
				drawn = _draw_from_discard(opp_id, filter, max_cost)

		if not drawn.is_empty():
			drawn_cards.append(drawn)

	# Track this player's draw count for Hypocrite's "match" effect
	if drawn_cards.size() > 0:
		_last_player_draw_count[caster.owner_id] = drawn_cards.size()

	# Emit signal for effect tracking
	if drawn_cards.size() > 0:
		effect_applied.emit("draw", caster.unique_id, "", drawn_cards.size())
		# Emit cards_drawn signal for onDraw triggers (Hypocrite, etc.)
		# This is "extra" drawing (from card effects, not start of turn)
		cards_drawn.emit(caster.owner_id, drawn_cards.size(), true)

	return {
		"type": "draw",
		"success": true,
		"cards_drawn": drawn_cards.size()
	}


func _draw_from_discard(player_id: int, filter: String, max_cost: int = -1, exclude_card: String = "") -> String:
	"""Draw a card from discard pile, optionally filtered by champion and cost."""
	var discard := game_state.get_discard(player_id)
	var hand := game_state.get_hand(player_id)

	if discard.is_empty():
		return ""

	var excluded_one := false  # Track if we already excluded one copy
	var valid_cards: Array[String] = []
	for card_name: String in discard:
		var card_data := CardDatabase.get_card(card_name)
		if card_data.is_empty():
			continue

		# A card cannot retrieve itself from discard (e.g. Refocus)
		if not exclude_card.is_empty() and card_name == exclude_card and not excluded_one:
			excluded_one = true
			continue

		# Check filter (champion name)
		if not filter.is_empty() and not _card_matches_filter(card_name, filter):
			continue

		# Check max cost
		if max_cost >= 0:
			var cost: int = card_data.get("cost", 0)
			if cost > max_cost:
				continue

		valid_cards.append(card_name)

	if valid_cards.is_empty():
		return ""

	# For now, take first valid (AI would choose best, player should get selection)
	var chosen: String = valid_cards[0]
	discard.erase(chosen)
	hand.append(chosen)
	return chosen


func _card_matches_filter(card_name: String, filter: String) -> bool:
	"""Check if card matches filter criteria."""
	var card_data := CardDatabase.get_card(card_name)
	if card_data.is_empty():
		return false

	var filter_lower := filter.to_lower()

	match filter_lower:
		"action":
			return card_data.get("type") == "Action"
		"response":
			return card_data.get("type") == "Response"
		"equipment":
			return card_data.get("type") == "Equipment"
		_:
			# Check if filter is a champion name
			var card_champion: String = card_data.get("character", "")
			if card_champion.to_lower() == filter_lower:
				return true

			# Check if filter is a substring of card name (e.g., "Flask" matches "Stealth Flask")
			if card_name.to_lower().contains(filter_lower):
				return true

			# Unknown filter - match none if filter is specified
			return filter.is_empty()


# --- Discard Processing ---

func _process_discard(effect: Dictionary, caster: ChampionState, _targets: Array) -> Dictionary:
	# cards.json uses "value" for discard count
	var discard_count: int = _to_int(effect.get("value", effect.get("discard", 1)))
	if discard_count == 0:
		discard_count = 1  # Default to discarding 1 card
	var target_player: String = str(effect.get("targetPlayer", "self"))
	var random: bool = effect.get("random", false)

	var pid := caster.owner_id
	if target_player == "opponent":
		pid = 2 if caster.owner_id == 1 else 1

	var hand := game_state.get_hand(pid)

	# Player-choice discard: if discarding from own hand and not random, let player choose
	if not random and target_player != "opponent" and hand.size() > discard_count:
		_pending_discard_choice_player = pid
		_pending_discard_choice_count = mini(discard_count, hand.size())
		discard_choice_required.emit(pid, _pending_discard_choice_count)
		return {
			"type": "discard",
			"success": true,
			"pending_discard_choice": true,
			"count": _pending_discard_choice_count
		}

	# Auto-discard (random, opponent, or hand too small to choose)
	var discard := game_state.get_discard(pid)
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


func complete_discard_choice(chosen_cards: Array[String]) -> void:
	"""Complete player-chosen discard (Introspection, etc.)."""
	if _pending_discard_choice_player < 0:
		return
	var pid := _pending_discard_choice_player
	var hand := game_state.get_hand(pid)
	var discard := game_state.get_discard(pid)

	for card_name: String in chosen_cards:
		var idx := hand.find(card_name)
		if idx >= 0:
			hand.remove_at(idx)
			discard.append(card_name)
			print("Discard choice: %s discarded" % card_name)

	_pending_discard_choice_player = -1
	_pending_discard_choice_count = 0


# --- Mana Effects ---

func _process_gain_mana(effect: Dictionary, caster: ChampionState) -> Dictionary:
	"""Grant mana to caster's player."""
	var amount: int = _to_int(effect.get("value", 1))
	game_state.add_mana(caster.owner_id, amount)

	return {
		"type": "gainMana",
		"success": true,
		"amount": amount
	}


func _process_lock_mana(effect: Dictionary, caster: ChampionState) -> Dictionary:
	"""Lock opponent's mana for next turn."""
	var amount: int = _to_int(effect.get("value", 1))
	var opp_id := 2 if caster.owner_id == 1 else 1
	game_state.lock_mana(opp_id, amount)

	return {
		"type": "lockMana",
		"success": true,
		"amount": amount,
		"target_player": opp_id
	}


func _process_steal_mana(effect: Dictionary, caster: ChampionState) -> Dictionary:
	"""Steal mana from opponent."""
	var amount: int = _to_int(effect.get("value", 1))
	var opp_id := 2 if caster.owner_id == 1 else 1
	var stolen := game_state.steal_mana(opp_id, caster.owner_id, amount)

	return {
		"type": "stealMana",
		"success": true,
		"attempted": amount,
		"stolen": stolen
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
		"revealCard":
			return _handle_reveal_card(caster, targets)
		"repeatRoll":
			return _handle_repeat_roll(caster)
		"randomStat":
			return _handle_random_stat(caster, effect)
		"redirectSpell":
			return _handle_redirect_spell(caster, targets, card_data)
		"controlEnemy":
			return _handle_control_enemy(caster, targets)
		"manipulateDeck":
			return _handle_manipulate_deck(caster, effect)
		"chooseEffects":
			return _handle_choose_effects(caster, effect, card_data)
		"spectreEssence":
			return _handle_spectre_essence(caster)
		"gainManaOnKill":
			return _handle_gain_mana_on_kill(caster, effect)
		"damageAllInLine":
			return _handle_damage_all_in_line(caster, targets, effect)
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


func _handle_reveal_card(caster: ChampionState, _targets: Array) -> Dictionary:
	"""Secret Revealed - Reveal random card from opponent's hand, damage that champion."""
	var opp_id := 2 if caster.owner_id == 1 else 1
	var opp_hand := game_state.get_hand(opp_id)

	if opp_hand.is_empty():
		return {"type": "custom", "success": false, "reason": "empty_hand"}

	# Reveal a random card
	var revealed: String = opp_hand[randi() % opp_hand.size()]
	var card_data := CardDatabase.get_card(revealed)
	var champ_name: String = card_data.get("character", "")

	print("Secret Revealed: Revealed %s (character: %s)" % [revealed, champ_name])

	# Find and damage that champion
	var damaged_id: String = ""
	if not champ_name.is_empty():
		for enemy: ChampionState in game_state.get_champions(opp_id):
			if enemy.champion_name == champ_name and enemy.is_alive():
				var dealt := enemy.take_damage(2)
				damage_dealt.emit(caster.unique_id, enemy.unique_id, dealt)
				damaged_id = enemy.unique_id
				print("Secret Revealed: %s takes 2 damage" % enemy.champion_name)
				break

	return {
		"type": "custom",
		"custom": "revealCard",
		"success": true,
		"revealed": revealed,
		"damaged": damaged_id
	}


func _handle_repeat_roll(caster: ChampionState) -> Dictionary:
	"""Gamble - Keep rolling for mana, 50% chance to continue each time."""
	var mana_gained := 0
	var max_rolls := 10  # Safety cap

	while randi() % 2 == 0 and mana_gained < max_rolls:
		if caster.owner_id == 1:
			game_state.player1_mana += 1
		else:
			game_state.player2_mana += 1
		mana_gained += 1
		print("Gamble: Won roll! Gained 1 mana (total: %d)" % mana_gained)

	print("Gamble: Lost roll after gaining %d mana" % mana_gained)

	return {
		"type": "custom",
		"custom": "repeatRoll",
		"success": true,
		"mana_gained": mana_gained
	}


func _handle_random_stat(caster: ChampionState, effect: Dictionary) -> Dictionary:
	"""Battlecry - Gain random stat bonuses based on discarded cards."""
	var discard_count: int = effect.get("discarded", 1)
	var bonuses_gained: Array = []

	for i in range(discard_count):
		var roll := randi() % 6
		var stat: String
		match roll:
			0, 1:
				stat = "range"
			2, 3:
				stat = "power"
			4, 5:
				stat = "movementSpeed"

		caster.add_buff(stat + "Bonus", 0, 1, "Battlecry")  # This turn only
		bonuses_gained.append(stat)
		print("Battlecry: Gained +1 %s" % stat)

	return {
		"type": "custom",
		"custom": "randomStat",
		"success": true,
		"bonuses": bonuses_gained
	}


func _handle_redirect_spell(caster: ChampionState, targets: Array, _card_data: Dictionary) -> Dictionary:
	"""Confuse - Redirect a spell to a different target."""
	# This would need integration with the spell casting system
	# For now, just mark that redirect is pending
	if targets.is_empty():
		return {"type": "custom", "success": false}

	var target := game_state.get_champion(str(targets[0]))
	if target == null:
		return {"type": "custom", "success": false}

	# Add a redirect buff that the spell system will check
	target.add_buff("redirectSpell", 0, 1, caster.unique_id)

	return {
		"type": "custom",
		"custom": "redirectSpell",
		"success": true,
		"redirect_to": target.unique_id
	}


func _handle_control_enemy(caster: ChampionState, targets: Array) -> Dictionary:
	"""Hypnotize - Take control of enemy champion until they pay mana."""
	if targets.is_empty():
		return {"type": "custom", "success": false}

	var target := game_state.get_champion(str(targets[0]))
	if target == null or target.owner_id == caster.owner_id:
		return {"type": "custom", "success": false}

	# Apply hypnotized debuff - prevents actions until 2 mana paid
	target.add_debuff("hypnotized", -1, 1, caster.unique_id)  # Permanent until removed
	print("Hypnotize: %s is now hypnotized" % target.champion_name)

	return {
		"type": "custom",
		"custom": "controlEnemy",
		"success": true,
		"hypnotized": target.unique_id
	}


func _handle_manipulate_deck(caster: ChampionState, effect: Dictionary) -> Dictionary:
	"""Deck manipulation effects (look at top cards, reorder, etc.).
	For Intel: look at both decks, optionally put top card on bottom."""
	var action: String = effect.get("action", "intel")  # Default to intel behavior
	var count: int = effect.get("count", 1)
	var own_deck := game_state.get_deck(caster.owner_id)
	var opp_id := 2 if caster.owner_id == 1 else 1
	var opp_deck := game_state.get_deck(opp_id)

	match action:
		"intel":
			# Intel: Look at top of both decks, let player/AI choose top or bottom
			var own_top: String = own_deck[0] if not own_deck.is_empty() else ""
			var opp_top: String = opp_deck[0] if not opp_deck.is_empty() else ""

			if own_top.is_empty() and opp_top.is_empty():
				# Both decks empty, nothing to do
				return {
					"type": "custom",
					"custom": "manipulateDeck",
					"success": true,
					"action": "intel",
					"own_top": "",
					"opp_top": ""
				}

			# Store context and emit signal for player/AI choice
			_pending_intel_caster_owner = caster.owner_id
			intel_choice_required.emit(caster.owner_id, own_top, opp_top)

			return {
				"type": "custom",
				"custom": "manipulateDeck",
				"success": true,
				"action": "intel",
				"pending_intel": true,
				"own_top": own_top,
				"opp_top": opp_top
			}
		"look":
			# Look at top N cards of own deck
			var top_cards: Array = []
			for i in range(mini(count, own_deck.size())):
				top_cards.append(own_deck[i])
			return {
				"type": "custom",
				"custom": "manipulateDeck",
				"success": true,
				"action": "look",
				"cards": top_cards
			}
		"shuffle":
			own_deck.shuffle()
			return {
				"type": "custom",
				"custom": "manipulateDeck",
				"success": true,
				"action": "shuffle"
			}
		"putBottom":
			# Put top card on bottom
			if not own_deck.is_empty():
				var card: String = own_deck.pop_front()
				own_deck.push_back(card)
			return {
				"type": "custom",
				"custom": "manipulateDeck",
				"success": true,
				"action": "putBottom"
			}

	return {"type": "custom", "success": false}


func _handle_choose_effects(caster: ChampionState, effect: Dictionary, _card_data: Dictionary) -> Dictionary:
	"""Evil Tricks style - Choose between multiple effects."""
	var choices: Array = effect.get("choices", [])
	if choices.is_empty():
		return {"type": "custom", "success": false}

	# For now, randomly pick one (AI would evaluate, player would choose via UI)
	var chosen: Dictionary = choices[randi() % choices.size()]

	# Process the chosen effect
	var result := _process_single_effect(chosen, caster, [], {})

	return {
		"type": "custom",
		"custom": "chooseEffects",
		"success": true,
		"chosen": chosen,
		"result": result
	}


func _handle_spectre_essence(caster: ChampionState) -> Dictionary:
	"""Dark Wizard's Spectre Essence - Gain power from kills."""
	# This is typically applied as a passive buff
	caster.add_buff("spectreEssence", -1, 1, "SpectreEssence")

	return {
		"type": "custom",
		"custom": "spectreEssence",
		"success": true
	}


func _handle_gain_mana_on_kill(caster: ChampionState, effect: Dictionary) -> Dictionary:
	"""Gain mana when killing an enemy."""
	var mana_amount: int = effect.get("value", 1)

	# This is typically triggered by death events
	if caster.owner_id == 1:
		game_state.player1_mana += mana_amount
	else:
		game_state.player2_mana += mana_amount

	return {
		"type": "custom",
		"custom": "gainManaOnKill",
		"success": true,
		"mana_gained": mana_amount
	}


func _handle_damage_all_in_line(caster: ChampionState, targets: Array, effect: Dictionary) -> Dictionary:
	"""Deal damage to all champions in a line from caster."""
	var damage: int = effect.get("value", 1)
	var direction: String = ""

	if targets.size() > 0:
		direction = str(targets[0]).to_lower()

	var line_targets := _get_champions_in_direction(caster, direction)
	var total_damage := 0

	for target: ChampionState in line_targets:
		var dealt := target.take_damage(damage)
		total_damage += dealt
		damage_dealt.emit(caster.unique_id, target.unique_id, dealt)
		print("Line damage: %s takes %d damage" % [target.champion_name, dealt])

	return {
		"type": "custom",
		"custom": "damageAllInLine",
		"success": true,
		"total_damage": total_damage,
		"hit_count": line_targets.size()
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
					# If card has "range": "self" or "AOE", filter by caster's attack range
					# AOE melee attacks only hit enemies within the caster's range
					if card_range == "self" or card_range == "AOE":
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
