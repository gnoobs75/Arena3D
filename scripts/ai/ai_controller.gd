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

	var actions_taken := 0
	var max_actions := 20  # Safety limit

	while actions_taken < max_actions:
		var action := _choose_action()

		if action.is_empty() or action.get("type") == "end_turn":
			break

		var result := _execute_action(action)
		if result.get("success", false):
			actions_taken += 1
			action_chosen.emit(action)

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

	if valid_actions.is_empty():
		return {"type": "end_turn"}

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

	if randf() < optimal_chance:
		# Pick best action
		return scored_actions[0]["action"]
	else:
		# Pick random from top 3
		var top_count := mini(3, scored_actions.size())
		var index := randi() % top_count
		return scored_actions[index]["action"]


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
		"none", "self":
			target_sets.append([])
		"enemy":
			var opp_id := 1 if player_id == 2 else 2
			for enemy: ChampionState in state.get_living_champions(opp_id):
				target_sets.append([enemy.unique_id])
		"ally", "friendly":
			for ally: ChampionState in state.get_living_champions(player_id):
				if ally.unique_id != caster.unique_id:
					target_sets.append([ally.unique_id])
		"champion", "any":
			for champ: ChampionState in state.get_all_champions():
				if champ.is_alive():
					target_sets.append([champ.unique_id])
		"allyorself":
			for ally: ChampionState in state.get_living_champions(player_id):
				target_sets.append([ally.unique_id])
		_:
			target_sets.append([])

	return target_sets


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

	return score


func _score_move(action: Dictionary, state: GameState) -> float:
	"""Score a move action."""
	var score := 1.0
	var champion := state.get_champion(action.get("champion", ""))
	var target_pos: Vector2i = action.get("target", Vector2i.ZERO)

	if champion == null:
		return 0.0

	var opp_id := 1 if player_id == 2 else 2
	var pathfinder := Pathfinder.new(state)
	var range_calc := RangeCalculator.new()

	# Prefer moving toward enemies
	var min_enemy_dist := 999
	for enemy: ChampionState in state.get_living_champions(opp_id):
		var dist := pathfinder.manhattan_distance(target_pos, enemy.position)
		min_enemy_dist = mini(min_enemy_dist, dist)

		# Bonus for getting in attack range
		if dist <= champion.current_range:
			score += 3.0

	# Closer to enemies is better (for melee)
	if champion.current_range <= 1:
		score += (10.0 - min_enemy_dist) * 0.3

	# Avoid moving if we can already attack
	var current_targets := range_calc.get_valid_targets(champion, state)
	if not current_targets.is_empty():
		score *= 0.5

	return score


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
	var score := 2.0  # Base cast value
	var card_name: String = action.get("card", "")
	var card_data := CardDatabase.get_card(card_name)
	var targets: Array = action.get("targets", [])

	if card_data.is_empty():
		return 0.0

	var cost: int = card_data.get("cost", 0)
	var effects: Array = card_data.get("effect", [])

	# Evaluate effects
	for effect: Dictionary in effects:
		var effect_type: String = effect.get("type", "")

		match effect_type:
			"damage":
				var damage = effect.get("value", 0)
				if damage is int:
					score += damage * 1.5

				# Check if this kills a target
				if not targets.is_empty():
					var target := state.get_champion(targets[0])
					if target and target.current_hp <= damage:
						score += 8.0

			"heal":
				var heal = effect.get("value", 0)
				if heal is int:
					# Value healing more when low HP
					var caster := state.get_champion(action.get("champion", ""))
					if caster:
						var hp_missing := caster.max_hp - caster.current_hp
						score += mini(heal, hp_missing) * 1.2

			"buff":
				score += 2.5

			"debuff":
				score += 2.0

			"draw":
				score += 1.5

	# Mana efficiency
	if cost > 0:
		score = score / cost

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
