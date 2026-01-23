class_name AIController
extends RefCounted
## AIController - Main AI decision-making system
## Supports multiple difficulty levels

signal thinking_started()
signal thinking_finished()
signal action_chosen(action: Dictionary)

enum Difficulty {
	EASY,
	MEDIUM,
	HARD
}

const DIFFICULTY_PROFILES := {
	Difficulty.EASY: {
		"name": "Easy",
		"optimal_chance": 0.4,
		"score_randomization": 0.35,
		"lookahead": 0,
		"thinking_delay": 0.5
	},
	Difficulty.MEDIUM: {
		"name": "Medium",
		"optimal_chance": 0.7,
		"score_randomization": 0.15,
		"lookahead": 1,
		"thinking_delay": 0.8
	},
	Difficulty.HARD: {
		"name": "Hard",
		"optimal_chance": 0.95,
		"score_randomization": 0.05,
		"lookahead": 2,
		"thinking_delay": 1.0
	}
}

var difficulty: Difficulty = Difficulty.EASY
var profile: Dictionary
var player_id: int = 2
var game_controller: GameController

# Track actions per champion to balance between them
var _champion_action_count: Dictionary = {}  # champion_id -> action count this turn


func _init(controller: GameController, player: int = 2) -> void:
	game_controller = controller
	player_id = player
	set_difficulty(Difficulty.EASY)


func set_difficulty(diff: Difficulty) -> void:
	"""Set AI difficulty level."""
	difficulty = diff
	profile = DIFFICULTY_PROFILES[diff]


func take_turn() -> void:
	"""Execute AI turn - make decisions and perform actions."""
	thinking_started.emit()

	# Reset action tracking for new turn
	_champion_action_count.clear()

	# Manage response slot at start of turn
	_manage_response_slot()

	var actions_taken := 0
	var max_actions := 20  # Safety limit
	var consecutive_failures := 0
	var max_failures := 5  # Break if too many consecutive failures

	while actions_taken < max_actions:
		# Wait for any response windows to close before continuing
		while game_controller.response_stack.is_open():
			print("AI: Waiting for response window to close...")
			await _delay(0.5)
			# Safety check - if we've been waiting too long, something is wrong
			consecutive_failures += 1
			if consecutive_failures > 10:
				print("AI: Response window stuck, forcing end turn")
				break

		if consecutive_failures > 10:
			break

		var action := _choose_action()

		if action.is_empty() or action.get("type") == "end_turn":
			break

		var result := _execute_action(action)
		if result.get("success", false):
			actions_taken += 1
			consecutive_failures = 0  # Reset on success
			action_chosen.emit(action)

			# Track action for this champion
			var champ_id: String = action.get("champion", "")
			if not champ_id.is_empty():
				_champion_action_count[champ_id] = _champion_action_count.get(champ_id, 0) + 1
		else:
			consecutive_failures += 1
			print("AI: Action failed (%d consecutive failures)" % consecutive_failures)
			if consecutive_failures >= max_failures:
				print("AI: Too many failures, ending turn")
				break

		# Small delay between actions for visual feedback
		await _delay(0.3)

	# End turn
	game_controller.end_turn()
	thinking_finished.emit()


func _choose_action() -> Dictionary:
	"""Choose the next action to take."""
	var state := game_controller.get_game_state()

	# Get all valid actions
	var valid_actions := _get_all_valid_actions(state)

	# Debug: count action types per champion
	var champ_actions: Dictionary = {}  # champ_id -> {move: int, attack: int, cast: int}
	for action: Dictionary in valid_actions:
		var champ_id: String = action.get("champion", "unknown")
		if not champ_actions.has(champ_id):
			champ_actions[champ_id] = {"move": 0, "attack": 0, "cast": 0}
		var action_type: String = action.get("type", "")
		if champ_actions[champ_id].has(action_type):
			champ_actions[champ_id][action_type] += 1

	print("AI: Found %d valid actions:" % valid_actions.size())
	for champ_id: String in champ_actions:
		var counts: Dictionary = champ_actions[champ_id]
		var champ := state.get_champion(champ_id)
		var name: String = champ.champion_name if champ else champ_id
		print("  %s: moves=%d, attacks=%d, casts=%d (actions taken: %d)" % [
			name, counts["move"], counts["attack"], counts["cast"],
			_champion_action_count.get(champ_id, 0)
		])

	if valid_actions.is_empty():
		print("AI: No valid actions, ending turn")
		return {"type": "end_turn"}

	# Strategic check: don't end turn if one champion hasn't done anything useful
	# Filter actions to prioritize inactive champions
	var dominated_by_one_champ := _check_champion_imbalance(state)
	if dominated_by_one_champ:
		var inactive_champ_actions := valid_actions.filter(func(a: Dictionary) -> bool:
			var champ_id: String = a.get("champion", "")
			return _champion_action_count.get(champ_id, 0) == 0
		)
		if not inactive_champ_actions.is_empty():
			print("AI: Prioritizing inactive champion actions (%d available)" % inactive_champ_actions.size())
			valid_actions = inactive_champ_actions

	# Score actions
	var scored_actions: Array = []
	for action: Dictionary in valid_actions:
		var score := _score_action(action, state)

		# Apply randomization based on difficulty
		var randomization: float = profile.get("score_randomization", 0.0)
		score *= randf_range(1.0 - randomization, 1.0 + randomization)

		scored_actions.append({"action": action, "score": score})

	# Sort by score
	scored_actions.sort_custom(func(a, b): return a["score"] > b["score"])

	# Choose action based on difficulty
	var optimal_chance: float = profile.get("optimal_chance", 0.5)
	var chosen_action: Dictionary

	if randf() < optimal_chance:
		# Pick best action
		chosen_action = scored_actions[0]["action"]
	else:
		# Pick random from top 3
		var top_count := mini(3, scored_actions.size())
		var index := randi() % top_count
		chosen_action = scored_actions[index]["action"]

	# Debug output
	var action_type: String = chosen_action.get("type", "unknown")
	var score: float = scored_actions[0]["score"] if not scored_actions.is_empty() else 0.0
	print("AI: Chose %s action (best score: %.1f)" % [action_type, score])
	if action_type == "cast":
		print("AI: Casting card '%s'" % chosen_action.get("card", ""))

	return chosen_action


func _get_all_valid_actions(state: GameState) -> Array:
	"""Get all valid actions for AI player."""
	var actions: Array = []

	for champ: ChampionState in state.get_champions(player_id):
		if not champ.is_alive():
			continue

		# Move actions
		if champ.can_move():
			var pathfinder := Pathfinder.new(state)
			var reachable := pathfinder.get_reachable_tiles(champ)
			for pos: Vector2i in reachable:
				actions.append({
					"type": "move",
					"champion": champ.unique_id,
					"target": pos
				})

		# Attack actions
		if champ.can_attack():
			var range_calc := RangeCalculator.new()
			var targets := range_calc.get_valid_targets(champ, state)
			for target: ChampionState in targets:
				actions.append({
					"type": "attack",
					"champion": champ.unique_id,
					"target": target.unique_id
				})

		# Cast actions
		if champ.can_cast():
			var hand := state.get_hand(player_id)
			var mana := state.get_mana(player_id)

			for card_name: String in hand:
				var card_data := CardDatabase.get_card(card_name)
				var cost: int = card_data.get("cost", 0)
				var card_type: String = card_data.get("type", "")

				if card_type == "Response":
					continue  # Response cards played reactively

				if cost <= mana:
					var cast_targets := _get_valid_cast_targets(state, champ, card_data)
					for targets: Array in cast_targets:
						actions.append({
							"type": "cast",
							"champion": champ.unique_id,
							"card": card_name,
							"targets": targets
						})

	return actions


func _get_valid_cast_targets(state: GameState, caster: ChampionState, card_data: Dictionary) -> Array:
	"""Get valid target combinations for a card."""
	var target_sets: Array = []
	var target_type: String = card_data.get("target", "none")

	match target_type.to_lower():
		"none":
			target_sets.append([])
		"self":
			# Self-targeting cards should pass the caster's ID
			target_sets.append([caster.unique_id])
		"enemy":
			var opp_id := 1 if player_id == 2 else 2
			for enemy: ChampionState in state.get_living_champions(opp_id):
				# Check if enemy is in range for targeted cards
				if _is_valid_target_for_card(caster, enemy, card_data, state):
					target_sets.append([enemy.unique_id])
		"ally", "friendly":
			for ally: ChampionState in state.get_living_champions(player_id):
				if ally.unique_id != caster.unique_id:
					if _is_valid_target_for_card(caster, ally, card_data, state):
						target_sets.append([ally.unique_id])
		"champion", "any":
			for champ: ChampionState in state.get_all_champions():
				if champ.is_alive():
					if _is_valid_target_for_card(caster, champ, card_data, state):
						target_sets.append([champ.unique_id])
		"allyorself":
			for ally: ChampionState in state.get_living_champions(player_id):
				if _is_valid_target_for_card(caster, ally, card_data, state):
					target_sets.append([ally.unique_id])
		_:
			target_sets.append([])

	return target_sets


func _is_valid_target_for_card(caster: ChampionState, target: ChampionState, card_data: Dictionary, state: GameState) -> bool:
	"""Check if a target is valid for a card (including range check)."""
	# Self is always valid
	if caster.unique_id == target.unique_id:
		return true

	# Check range based on caster's attack range
	var caster_pos: Vector2i = caster.position
	var target_pos: Vector2i = target.position
	var is_melee: bool = caster.current_range <= 1

	if is_melee:
		var dist: int = maxi(absi(target_pos.x - caster_pos.x), absi(target_pos.y - caster_pos.y))
		return dist <= caster.current_range
	else:
		var dx: int = target_pos.x - caster_pos.x
		var dy: int = target_pos.y - caster_pos.y
		if dx != 0 and dy != 0:
			return false
		var dist: int = absi(dx) + absi(dy)
		return dist <= caster.current_range


func _score_action(action: Dictionary, state: GameState) -> float:
	"""Score an action based on utility."""
	var score := 0.0
	var action_type: String = action.get("type", "")

	match action_type:
		"move":
			score = _score_move(action, state)
		"attack":
			score = _score_attack(action, state)
		"cast":
			score = _score_cast(action, state)

	# Strong fairness bonus for champions that haven't acted
	# This ensures both champions participate in each turn
	var champ_id: String = action.get("champion", "")
	var action_count: int = _champion_action_count.get(champ_id, 0)

	# Check if the OTHER champion has already acted
	var other_champ_acted := false
	var other_champ_action_count := 0
	for other_id: String in _champion_action_count:
		if other_id != champ_id:
			other_champ_action_count = _champion_action_count[other_id]
			if other_champ_action_count > 0:
				other_champ_acted = true
				break

	if action_count == 0:
		# Strong bonus for champions that haven't acted at all
		score += 8.0
		# Extra bonus if the other champion already acted - balance the turn
		if other_champ_acted:
			score += 5.0
	elif action_count == 1:
		score += 3.0  # Smaller bonus for only one action
	elif action_count >= 3:
		# Penalty for using same champion too much
		score -= 2.0

	return score


func _score_move(action: Dictionary, state: GameState) -> float:
	"""Score a move action."""
	var score := 2.0  # Base move value
	var champion := state.get_champion(action.get("champion", ""))
	var target_pos: Vector2i = action.get("target", Vector2i.ZERO)

	if champion == null:
		return 0.0

	var opp_id := 1 if player_id == 2 else 2
	var pathfinder := Pathfinder.new(state)
	var range_calc := RangeCalculator.new()

	# Check current attack capability
	var current_targets := range_calc.get_valid_targets(champion, state)
	var can_currently_attack := not current_targets.is_empty()

	# Calculate distances to enemies from current and target positions
	var current_min_dist := 999
	var target_min_dist := 999
	var will_be_in_range := false

	for enemy: ChampionState in state.get_living_champions(opp_id):
		var current_dist := _chebyshev_distance(champion.position, enemy.position)
		var target_dist := _chebyshev_distance(target_pos, enemy.position)
		current_min_dist = mini(current_min_dist, current_dist)
		target_min_dist = mini(target_min_dist, target_dist)

		# Check if we'll be in attack range after moving
		if target_dist <= champion.current_range:
			will_be_in_range = true

	# Big bonus for moving into attack range when we can't currently attack
	if not can_currently_attack and will_be_in_range:
		score += 8.0  # High priority to get into the fight!

	# Bonus for getting closer to enemies
	if target_min_dist < current_min_dist:
		score += (current_min_dist - target_min_dist) * 1.5

	# Bonus for melee champions getting adjacent
	if champion.current_range <= 1 and target_min_dist <= 1:
		score += 4.0

	# Small penalty for moving when already in attack range (but don't completely discourage it)
	if can_currently_attack:
		score -= 2.0

	# Bonus for moving if we've already attacked (repositioning)
	if champion.has_attacked:
		score += 1.0

	return maxf(score, 0.5)  # Minimum score to keep moves as options


func _chebyshev_distance(from: Vector2i, to: Vector2i) -> int:
	"""Calculate Chebyshev distance (8-directional king moves)."""
	return maxi(absi(to.x - from.x), absi(to.y - from.y))


func _check_champion_imbalance(state: GameState) -> bool:
	"""Check if one champion has been doing all the work while the other is idle."""
	var living_champs := state.get_living_champions(player_id)
	if living_champs.size() < 2:
		return false  # Only one champion, no imbalance possible

	# Check action counts
	var max_actions := 0
	var min_actions := 999
	var idle_count := 0

	for champ: ChampionState in living_champs:
		var count: int = _champion_action_count.get(champ.unique_id, 0)
		max_actions = maxi(max_actions, count)
		min_actions = mini(min_actions, count)
		if count == 0:
			idle_count += 1

	# Imbalance if one champion has done 2+ actions and another has done none
	if max_actions >= 2 and idle_count > 0:
		return true

	return false


func _score_attack(action: Dictionary, state: GameState) -> float:
	"""Score an attack action."""
	var score := 5.0  # Base attack value
	var attacker := state.get_champion(action.get("champion", ""))
	var target := state.get_champion(action.get("target", ""))

	if attacker == null or target == null:
		return 0.0

	# Prefer attacking low HP targets (potential kill)
	if target.current_hp <= attacker.current_power:
		score += 10.0  # Kill bonus

	# Prefer attacking lower HP enemies
	var hp_ratio := float(target.current_hp) / float(target.max_hp)
	score += (1.0 - hp_ratio) * 3.0

	# Prefer attacking high-threat enemies
	if target.current_power >= 2:
		score += 2.0

	return score


func _score_cast(action: Dictionary, state: GameState) -> float:
	"""Score a card cast action."""
	var score := 3.0  # Base cast value (increased)
	var card_name: String = action.get("card", "")
	var card_data := CardDatabase.get_card(card_name)
	var targets: Array = action.get("targets", [])
	var caster := state.get_champion(action.get("champion", ""))

	if card_data.is_empty() or caster == null:
		return 0.0

	var cost: int = card_data.get("cost", 0)
	var effects: Array = card_data.get("effect", [])
	var mana := state.get_mana(player_id)

	# Evaluate effects
	for effect: Dictionary in effects:
		var effect_type: String = effect.get("type", "")

		match effect_type:
			"damage":
				var damage = effect.get("value", 0)
				var scope: String = effect.get("scope", "target")

				if damage is int:
					score += damage * 2.0

					# Multi-target damage is very valuable
					if scope == "enemies" or scope == "allenemies":
						score += damage * 3.0

				# Check if this kills a target
				if not targets.is_empty():
					var target := state.get_champion(str(targets[0]))
					if target and damage is int and target.current_hp <= damage:
						score += 10.0  # Kill bonus

			"heal":
				var heal = effect.get("value", 0)
				if heal is int:
					# Value healing more when low HP
					var hp_missing := caster.max_hp - caster.current_hp
					var effective_heal := mini(heal, hp_missing)
					score += effective_heal * 1.5

					# Urgent healing when very low
					if caster.current_hp <= 5:
						score += effective_heal * 2.0

			"statMod":
				var stat: String = effect.get("stat", "")
				var value = effect.get("value", 0)
				if value is int and value > 0:
					match stat:
						"power":
							score += value * 3.0  # Power buffs are very valuable
						"range":
							score += value * 2.0
						"movement":
							score += value * 1.5

			"buff":
				var buff_name: String = effect.get("name", "")
				match buff_name:
					"extraAttack":
						# Very valuable if we have a target to attack
						var range_calc := RangeCalculator.new()
						var attack_targets := range_calc.get_valid_targets(caster, state)
						if not attack_targets.is_empty():
							score += 8.0
						else:
							score += 3.0
					"extraMove":
						score += 4.0
					"leech":
						score += 5.0
					_:
						score += 3.0

			"debuff":
				score += 3.0

			"draw":
				var draw_count = effect.get("value", 1)
				if draw_count is int:
					score += draw_count * 2.0

			"move":
				# Movement effects (push, pull, etc.)
				score += 3.0

	# Prefer using mana efficiently - don't waste mana at end of turn
	if mana >= cost:
		# Bonus for using mana that would otherwise be wasted
		var leftover_mana := mana - cost
		if leftover_mana < 2:
			score += 2.0

	# Scale by cost for efficiency, but don't penalize too much
	if cost > 0:
		score = score * (1.0 + 1.0 / cost)

	print("AI: Scoring card '%s' = %.1f (cost %d, mana %d)" % [card_name, score, cost, mana])
	return score


func _execute_action(action: Dictionary) -> Dictionary:
	"""Execute the chosen action through game controller."""
	var action_type: String = action.get("type", "")

	match action_type:
		"move":
			return game_controller.move_champion(
				action.get("champion", ""),
				action.get("target", Vector2i.ZERO)
			)
		"attack":
			return game_controller.attack_champion(
				action.get("champion", ""),
				action.get("target", "")
			)
		"cast":
			return game_controller.cast_card(
				action.get("card", ""),
				action.get("champion", ""),
				action.get("targets", [])
			)

	return {"success": false}


func handle_response_window(trigger: String, context: Dictionary) -> Dictionary:
	"""Decide whether to play a response card."""
	var state := game_controller.get_game_state()
	var valid_responses := game_controller.get_valid_responses(player_id)

	if valid_responses.is_empty():
		return {"action": "pass"}

	# Easy AI: Low chance to use responses
	if difficulty == Difficulty.EASY:
		if randf() < 0.3:  # 30% chance to respond
			var chosen: String = valid_responses[randi() % valid_responses.size()]
			return {"action": "respond", "card": chosen}
		return {"action": "pass"}

	# Medium/Hard: Evaluate response value
	var best_response := ""
	var best_score := 0.0

	for card_name: String in valid_responses:
		var score := _score_response(card_name, trigger, context, state)
		if score > best_score:
			best_score = score
			best_response = card_name

	# Threshold for playing response
	var threshold := 3.0 if difficulty == Difficulty.HARD else 5.0
	if best_score >= threshold:
		return {"action": "respond", "card": best_response}

	return {"action": "pass"}


func _score_response(card_name: String, trigger: String, context: Dictionary, state: GameState) -> float:
	"""Score a response card for the current trigger."""
	var score := 0.0
	var card_data := CardDatabase.get_card(card_name)

	match trigger:
		"beforeDamage":
			# Value damage prevention highly
			var incoming_damage: int = context.get("damage", 0)
			score += incoming_damage * 2.0

		"afterDamage":
			# Counter-attack responses
			score += 3.0

	return score


func _delay(seconds: float) -> void:
	"""Helper for async delay."""
	# AIController is a RefCounted, so we need to get tree from Engine singleton
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(seconds).timeout


func _manage_response_slot() -> void:
	"""Evaluate and place the best response card in the response slot."""
	var state := game_controller.get_game_state()
	var hand := state.get_hand(player_id)
	var current_slot := state.get_response_slot(player_id)

	# Find all response cards in hand
	var response_cards: Array[Dictionary] = []
	for card_name: String in hand:
		var card_data := CardDatabase.get_card(card_name)
		if card_data.get("type", "") == "Response":
			response_cards.append({
				"name": card_name,
				"data": card_data,
				"score": _score_response_card_for_slot(card_name, card_data, state)
			})

	if response_cards.is_empty():
		# No response cards available - clear slot if we have one
		# (Keep existing card in slot since it's better than nothing)
		return

	# Sort by score
	response_cards.sort_custom(func(a, b): return a["score"] > b["score"])

	var best_card: Dictionary = response_cards[0]

	# If we already have a card in slot, only replace if new one is better
	if not current_slot.is_empty():
		var current_score := _score_response_card_for_slot(current_slot, CardDatabase.get_card(current_slot), state)
		if best_card["score"] <= current_score:
			# Keep current card
			return

	# Place the best response card in the slot
	var card_to_place: String = best_card["name"]
	if state.set_response_slot(player_id, card_to_place):
		print("AI: Placed '%s' in response slot (score: %.1f)" % [card_to_place, best_card["score"]])


func _score_response_card_for_slot(card_name: String, card_data: Dictionary, state: GameState) -> float:
	"""Score a response card for slot placement."""
	var score := 0.0
	var trigger: String = card_data.get("trigger", "")
	var cost: int = card_data.get("cost", 0)
	var effects: Array = card_data.get("effect", [])

	# Base score by trigger type
	match trigger:
		"beforeDamage":
			# Defensive cards are valuable
			score += 5.0
		"afterDamage":
			# Reactive damage/effects
			score += 4.0
		"onMove":
			# Traps and movement reactions
			score += 3.0
		"onHeal":
			# Usually disruption
			score += 3.0
		"onCast":
			# Spell reactions
			score += 3.0
		_:
			score += 2.0

	# Evaluate effects
	for effect: Dictionary in effects:
		var effect_type: String = effect.get("type", "")
		match effect_type:
			"damage":
				var value = effect.get("value", 0)
				if value is int:
					score += value * 1.5
			"heal":
				var value = effect.get("value", 0)
				if value is int:
					score += value * 1.0
			"move":
				# Movement effects (dodge, etc.) are valuable
				score += 3.0
			"buff":
				var buff_name: String = effect.get("name", "")
				if buff_name == "negateDamage":
					score += 8.0  # Damage negation is very valuable
				elif buff_name == "shield":
					score += 6.0
				else:
					score += 2.0
			"statMod":
				score += 2.0

	# Penalize high-cost cards (harder to trigger)
	if cost > 3:
		score -= (cost - 3) * 1.0

	# Bonus for character-specific cards if that character is alive and healthy
	var card_character: String = card_data.get("character", "")
	if not card_character.is_empty():
		for champ: ChampionState in state.get_champions(player_id):
			if champ.champion_name == card_character:
				if champ.is_alive():
					# Bonus if the character is low health (needs protection)
					var hp_ratio := float(champ.current_hp) / float(champ.max_hp)
					if hp_ratio < 0.5:
						score += 3.0
				else:
					# Character is dead - card is useless
					score = -10.0
				break

	return score
