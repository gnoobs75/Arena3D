class_name AIvsAIRunner
extends RefCounted
## AIvsAIRunner - Runs automated AI vs AI matches with detailed logging
## Use this to find bugs and edge cases in game logic

signal match_started(match_number: int)
signal match_ended(match_number: int, winner: int, rounds: int, reason: String)
signal all_matches_complete(results: Array)
signal bug_found(bug: Dictionary)

const MAX_ROUNDS := 30  # Safety limit to prevent infinite games
const MAX_ACTIONS_PER_TURN := 20  # Safety limit
const VERBOSE_LOGGING := false  # Set to true for detailed output

var game_controller: GameController
var ai_player1: AIController
var ai_player2: AIController

var match_logs: Array[Dictionary] = []
var current_match_log: Dictionary = {}
var bugs_found: Array[Dictionary] = []

var total_matches: int = 0
var matches_completed: int = 0
var current_match: int = 0

# Statistics
var p1_wins: int = 0
var p2_wins: int = 0
var draws: int = 0
var errors_encountered: int = 0


func run_matches(num_matches: int, p1_champions: Array[String], p2_champions: Array[String],
				 p1_difficulty: AIController.Difficulty = AIController.Difficulty.MEDIUM,
				 p2_difficulty: AIController.Difficulty = AIController.Difficulty.MEDIUM) -> Dictionary:
	"""Run multiple AI vs AI matches and return results."""
	total_matches = num_matches
	matches_completed = 0
	match_logs.clear()
	bugs_found.clear()
	p1_wins = 0
	p2_wins = 0
	draws = 0
	errors_encountered = 0

	_log_system("=== AI vs AI Test Session Started ===")
	_log_system("Matches to run: %d" % num_matches)
	_log_system("P1 Champions: %s (Difficulty: %s)" % [str(p1_champions), AIController.Difficulty.keys()[p1_difficulty]])
	_log_system("P2 Champions: %s (Difficulty: %s)" % [str(p2_champions), AIController.Difficulty.keys()[p2_difficulty]])
	_log_system("")

	for i in range(num_matches):
		current_match = i + 1
		_log_system("--- Starting Match %d/%d ---" % [current_match, num_matches])
		match_started.emit(current_match)

		var result := _run_single_match(p1_champions.duplicate(), p2_champions.duplicate(),
										p1_difficulty, p2_difficulty)

		match_logs.append(result)
		matches_completed += 1

		match result.get("winner", 0):
			0:
				draws += 1
			1:
				p1_wins += 1
			2:
				p2_wins += 1

		match_ended.emit(current_match, result.get("winner", 0), result.get("rounds", 0), result.get("reason", ""))

	var summary := _generate_summary()
	_log_system("")
	_log_system("=== Test Session Complete ===")
	_log_system(summary)

	all_matches_complete.emit(match_logs)

	return {
		"matches": match_logs,
		"bugs": bugs_found,
		"summary": summary,
		"p1_wins": p1_wins,
		"p2_wins": p2_wins,
		"draws": draws,
		"errors": errors_encountered
	}


func _run_single_match(p1_champions: Array[String], p2_champions: Array[String],
					   p1_diff: AIController.Difficulty, p2_diff: AIController.Difficulty) -> Dictionary:
	"""Run a single match and return detailed log."""
	current_match_log = {
		"match_number": current_match,
		"p1_champions": p1_champions,
		"p2_champions": p2_champions,
		"rounds": 0,
		"winner": 0,
		"reason": "",
		"actions": [],
		"errors": [],
		"warnings": [],
		"state_snapshots": []
	}

	# Initialize game
	game_controller = GameController.new()
	var init_success := game_controller.initialize(p1_champions, p2_champions)

	if not init_success:
		_log_error("Failed to initialize game controller")
		current_match_log["reason"] = "initialization_failed"
		return current_match_log

	# Initialize AI controllers
	ai_player1 = AIController.new(game_controller, 1)
	ai_player1.set_difficulty(p1_diff)
	ai_player2 = AIController.new(game_controller, 2)
	ai_player2.set_difficulty(p2_diff)

	# Take initial state snapshot
	_snapshot_state("initial")

	var state := game_controller.get_game_state()
	_log_action("Game initialized - Round 1 begins")

	# Main game loop - simplified direct state manipulation
	while not state.game_over and state.round_number <= MAX_ROUNDS:
		# Execute turn for current player
		var turn_result := _execute_turn_direct(state)

		if turn_result.get("error", false):
			_log_error("Turn execution error: %s" % turn_result.get("message", "unknown"))
			break

		# Check for game over
		state.check_win_condition()

		if state.game_over:
			current_match_log["winner"] = state.winner
			current_match_log["reason"] = "champions_defeated"
			print("[MATCH %d] Game Over! Player %d wins" % [current_match, state.winner])
			break

		# End turn and switch to next player
		_end_turn_direct(state)

	# Check if we hit round limit
	if state.round_number > MAX_ROUNDS:
		current_match_log["reason"] = "round_limit_exceeded"
		# Determine winner by HP
		var p1_hp := _get_total_hp(state, 1)
		var p2_hp := _get_total_hp(state, 2)
		if p1_hp > p2_hp:
			current_match_log["winner"] = 1
		elif p2_hp > p1_hp:
			current_match_log["winner"] = 2
		current_match_log["reason"] = "round_limit_hp_advantage"
		print("[MATCH %d] Round limit - P1 HP: %d, P2 HP: %d, Winner: P%d" % [
			current_match, p1_hp, p2_hp, current_match_log["winner"]])

	current_match_log["rounds"] = state.round_number
	_snapshot_state("final")

	return current_match_log


func _get_total_hp(state: GameState, player_id: int) -> int:
	"""Get total HP for a player's team."""
	var total := 0
	for champ: ChampionState in state.get_champions(player_id):
		total += maxi(0, champ.current_hp)
	return total


func _end_turn_direct(state: GameState) -> void:
	"""End current turn and start next player's turn."""
	var current_player: int = state.active_player

	# Discard down to 7 cards
	var hand: Array = state.get_hand(current_player)
	while hand.size() > 7:
		var discarded: String = hand.pop_back()
		state.get_discard(current_player).append(discarded)

	# Clear this-turn effects
	for champ: ChampionState in state.get_champions(current_player):
		champ.clear_this_turn_effects()

	# Switch to next player
	var next_player: int = 2 if current_player == 1 else 1

	# New round if back to player 1
	if next_player == 1:
		state.round_number += 1

	state.active_player = next_player
	state.current_phase = "ACTION"

	# Start of turn: reset mana, reset flags, draw card
	state.reset_mana(next_player)
	for champ: ChampionState in state.get_champions(next_player):
		champ.reset_turn()

	# Only draw if hand is under 10 cards (safety)
	if state.get_hand(next_player).size() < 10:
		state.draw_card(next_player)


func _execute_turn_direct(state: GameState) -> Dictionary:
	"""Execute a single player's turn using direct state manipulation."""
	var player_id: int = state.active_player

	_log_action("Player %d turn (Mana: %d, Hand: %d cards)" % [
		player_id,
		state.get_mana(player_id),
		state.get_hand(player_id).size()
	])

	var actions_this_turn := 0
	var turn_actions: Array = []

	while actions_this_turn < MAX_ACTIONS_PER_TURN:
		# Get valid actions
		var valid_actions := _get_all_valid_actions_for_player(state, player_id)

		if valid_actions.is_empty():
			break

		# Choose best action (simple scoring)
		var chosen_action := _choose_best_action(valid_actions, state, player_id)

		if chosen_action.is_empty():
			break

		# Execute action directly
		var result := _execute_action_direct(chosen_action, state)

		if result.get("success", false):
			actions_this_turn += 1
			turn_actions.append(chosen_action)
			_log_action("  %s" % _describe_action(chosen_action))

			# Check if any champion died
			state.check_win_condition()
			if state.game_over:
				break
		else:
			# Action failed - skip it and try next
			break

	current_match_log["actions"].append({
		"round": state.round_number,
		"player": player_id,
		"action_count": actions_this_turn
	})

	return {"success": true}


func _choose_best_action(valid_actions: Array, state: GameState, player_id: int) -> Dictionary:
	"""Choose the best action based on simple scoring."""
	if valid_actions.is_empty():
		return {}

	var best_action: Dictionary = {}
	var best_score := -999.0

	for action: Dictionary in valid_actions:
		var score := _simple_score_action(action, state, player_id)
		# Add randomization
		score *= randf_range(0.7, 1.3)

		if score > best_score:
			best_score = score
			best_action = action

	return best_action


func _execute_action_direct(action: Dictionary, state: GameState) -> Dictionary:
	"""Execute action directly on game state."""
	var action_type: String = action.get("type", "")

	match action_type:
		"move":
			return _do_move(action, state)
		"attack":
			return _do_attack(action, state)
		"cast":
			return _do_cast(action, state)

	return {"success": false}


func _do_move(action: Dictionary, state: GameState) -> Dictionary:
	"""Execute a move action."""
	var champ_id: String = action.get("champion", "")
	var target_pos: Vector2i = action.get("target", Vector2i.ZERO)

	var champion := state.get_champion(champ_id)
	if champion == null or not champion.can_move():
		return {"success": false}

	# Calculate path
	var pathfinder := Pathfinder.new(state)
	var path := pathfinder.find_path(champion.position, target_pos, champion)

	if path.is_empty() or path.size() > champion.movement_remaining:
		return {"success": false}

	# Execute move
	champion.position = target_pos
	champion.movement_remaining -= path.size()
	champion.has_moved = true

	return {"success": true}


func _do_attack(action: Dictionary, state: GameState) -> Dictionary:
	"""Execute an attack action."""
	var attacker_id: String = action.get("champion", "")
	var target_id: String = action.get("target", "")

	var attacker := state.get_champion(attacker_id)
	var target := state.get_champion(target_id)

	if attacker == null or target == null:
		return {"success": false}
	if not attacker.can_attack():
		return {"success": false}

	# Check range
	var range_calc := RangeCalculator.new()
	if not range_calc.can_attack(attacker, target, state):
		return {"success": false}

	# Deal damage
	var damage: int = attacker.current_power
	target.take_damage(damage)
	attacker.has_attacked = true

	return {"success": true, "damage": damage}


func _do_cast(action: Dictionary, state: GameState) -> Dictionary:
	"""Execute a cast action (simplified - just spend mana and remove card)."""
	var card_name: String = action.get("card", "")
	var caster_id: String = action.get("champion", "")
	var targets: Array = action.get("targets", [])

	var caster := state.get_champion(caster_id)
	if caster == null:
		return {"success": false}

	var card_data := CardDatabase.get_card(card_name)
	var cost: int = _to_int(card_data.get("cost", 0))
	var player_id: int = caster.owner_id

	# Check mana
	if state.get_mana(player_id) < cost:
		return {"success": false}

	# Check card in hand
	var hand: Array = state.get_hand(player_id)
	if card_name not in hand:
		return {"success": false}

	# Spend mana and remove card
	state.spend_mana(player_id, cost)
	hand.erase(card_name)
	state.get_discard(player_id).append(card_name)

	# Apply simple effects
	var effects: Array = card_data.get("effect", [])
	for effect: Dictionary in effects:
		_apply_simple_effect(effect, caster, targets, state)

	return {"success": true}


func _apply_simple_effect(effect: Dictionary, caster: ChampionState, targets: Array, state: GameState) -> void:
	"""Apply a simplified card effect."""
	var effect_type: String = str(effect.get("type", ""))
	var value: int = _to_int(effect.get("value", 0))

	match effect_type:
		"damage":
			# Deal damage to targets
			for target_id in targets:
				var target := state.get_champion(str(target_id))
				if target:
					target.take_damage(value)
		"heal":
			# Heal caster or targets
			if targets.is_empty():
				caster.heal(value)
			else:
				for target_id in targets:
					var target := state.get_champion(str(target_id))
					if target:
						target.heal(value)
		"buff":
			var buff_name: String = str(effect.get("buff", ""))
			var duration: int = _to_int(effect.get("duration", -1))
			if not buff_name.is_empty():
				caster.add_buff(buff_name, duration)
		"debuff":
			var debuff_name: String = str(effect.get("debuff", ""))
			var duration: int = _to_int(effect.get("duration", -1))
			for target_id in targets:
				var target := state.get_champion(str(target_id))
				if target and not debuff_name.is_empty():
					target.add_debuff(debuff_name, duration)
		"draw":
			var count: int = _to_int(effect.get("value", 1))
			if count < 1:
				count = 1
			for i in range(count):
				state.draw_card(caster.owner_id)


func _to_int(value) -> int:
	"""Safely convert any value to int."""
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String:
		# Handle special duration strings
		match value.to_lower():
			"thisturn":
				return 0  # 0 means this turn only
			"permanent", "forever":
				return -1  # -1 means permanent
			_:
				if value.is_valid_int():
					return value.to_int()
				return -1
	return 0


func _get_all_valid_actions_for_player(state: GameState, player_id: int) -> Array:
	"""Get all valid actions for a player."""
	var actions: Array = []

	for champ: ChampionState in state.get_champions(player_id):
		if not champ.is_alive():
			continue

		# Move actions
		if champ.can_move() and champ.movement_remaining > 0:
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

		# Cast actions (simplified - just check mana)
		if champ.can_cast():
			var hand: Array = state.get_hand(player_id)
			var mana: int = state.get_mana(player_id)

			for card_name: String in hand:
				var card_data := CardDatabase.get_card(card_name)
				var cost: int = _to_int(card_data.get("cost", 0))
				var card_type: String = str(card_data.get("type", ""))

				if card_type == "Response":
					continue

				if cost <= mana:
					var targets: Array = _get_cast_targets(state, champ, card_data)
					for target_set: Array in targets:
						actions.append({
							"type": "cast",
							"champion": champ.unique_id,
							"card": card_name,
							"targets": target_set
						})

	return actions


func _get_cast_targets(state: GameState, caster: ChampionState, card_data: Dictionary) -> Array:
	"""Get valid target combinations for a card."""
	var target_sets: Array = []
	var target_type: String = str(card_data.get("target", "none"))
	var player_id: int = caster.owner_id

	match target_type.to_lower():
		"none", "self":
			target_sets.append([])
		"enemy":
			var opp_id: int = 1 if player_id == 2 else 2
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


func _ai_choose_action(ai: AIController, valid_actions: Array, state: GameState) -> Dictionary:
	"""Have AI choose from valid actions."""
	if valid_actions.is_empty():
		return {"type": "end_turn"}

	# Score and choose (simplified version of AI logic)
	var best_action: Dictionary = {}
	var best_score := -999.0

	for action: Dictionary in valid_actions:
		var score := _simple_score_action(action, state, ai.player_id)
		# Add randomization
		score *= randf_range(0.8, 1.2)

		if score > best_score:
			best_score = score
			best_action = action

	return best_action


func _simple_score_action(action: Dictionary, state: GameState, player_id: int) -> float:
	"""Simple action scoring for testing."""
	var score := 1.0
	var action_type: String = action.get("type", "")

	match action_type:
		"attack":
			score = 10.0
			var target_id: String = action.get("target", "")
			var attacker_id: String = action.get("champion", "")
			var target := state.get_champion(target_id)
			var attacker := state.get_champion(attacker_id)
			if target and attacker:
				# Bonus for kills
				if target.current_hp <= attacker.current_power:
					score += 20.0
				# Prefer low HP targets
				score += (20.0 - target.current_hp) * 0.5

		"move":
			score = 2.0
			var champ_id: String = action.get("champion", "")
			var champion := state.get_champion(champ_id)
			var target_pos: Vector2i = action.get("target", Vector2i.ZERO)
			if champion:
				# Prefer moving toward enemies
				var opp_id: int = 1 if player_id == 2 else 2
				for enemy: ChampionState in state.get_living_champions(opp_id):
					var dist: int = absi(target_pos.x - enemy.position.x) + absi(target_pos.y - enemy.position.y)
					score += (20.0 - dist) * 0.2

		"cast":
			score = 5.0
			var card_name: String = action.get("card", "")
			var card_data := CardDatabase.get_card(card_name)
			var effects: Array = card_data.get("effect", [])
			for effect: Dictionary in effects:
				var effect_type: String = str(effect.get("type", ""))
				match effect_type:
					"damage":
						score += 8.0
					"heal":
						score += 6.0
					"buff":
						score += 4.0

	return score


func _execute_action(action: Dictionary, _player_id: int) -> Dictionary:
	"""Execute an action through the game controller."""
	var action_type: String = action.get("type", "")

	match action_type:
		"move":
			var champ_id: String = action.get("champion", "")
			var target_pos: Vector2i = action.get("target", Vector2i.ZERO)
			return game_controller.move_champion(champ_id, target_pos)
		"attack":
			var attacker_id: String = action.get("champion", "")
			var target_id: String = action.get("target", "")
			return game_controller.attack_champion(attacker_id, target_id)
		"cast":
			var cast_card: String = action.get("card", "")
			var caster_id: String = action.get("champion", "")
			var cast_targets: Array = action.get("targets", [])
			return game_controller.cast_card(cast_card, caster_id, cast_targets)

	return {"success": false, "error": "Unknown action type"}


func _describe_action(action: Dictionary) -> String:
	"""Create human-readable action description."""
	var action_type: String = action.get("type", "")

	match action_type:
		"move":
			var champ: String = action.get("champion", "?")
			var target = action.get("target", "?")
			return "Move %s to %s" % [champ, target]
		"attack":
			var champ: String = action.get("champion", "?")
			var target: String = action.get("target", "?")
			return "Attack %s -> %s" % [champ, target]
		"cast":
			var card: String = action.get("card", "?")
			var champ: String = action.get("champion", "?")
			var targets: Array = action.get("targets", [])
			return "Cast %s by %s on %s" % [card, champ, targets]
		"end_turn":
			return "End turn"

	return "Unknown action"


func _get_team_hp(state: GameState, player_id: int) -> String:
	"""Get HP summary for a team."""
	var parts: Array[String] = []
	for champ: ChampionState in state.get_champions(player_id):
		parts.append("%s:%d/%d" % [champ.champion_name.substr(0, 3), champ.current_hp, champ.max_hp])
	return ", ".join(parts)


func _get_state_summary(state: GameState) -> Dictionary:
	"""Get a summary of current game state."""
	return {
		"round": state.round_number,
		"active_player": state.active_player,
		"p1_mana": state.player1_mana,
		"p2_mana": state.player2_mana,
		"p1_hp": _get_team_hp(state, 1),
		"p2_hp": _get_team_hp(state, 2),
		"p1_hand_size": state.player1_hand.size(),
		"p2_hand_size": state.player2_hand.size()
	}


func _snapshot_state(label: String) -> void:
	"""Take a snapshot of current game state."""
	var state := game_controller.get_game_state()
	current_match_log["state_snapshots"].append({
		"label": label,
		"state": _get_state_summary(state)
	})


# --- Logging ---

func _log_system(message: String) -> void:
	print("[SYSTEM] %s" % message)


func _log_action(message: String) -> void:
	if VERBOSE_LOGGING:
		print("[MATCH %d] %s" % [current_match, message])


func _log_warning(message: String) -> void:
	print("[WARNING] Match %d: %s" % [current_match, message])
	current_match_log["warnings"].append(message)


func _log_error(message: String) -> void:
	print("[ERROR] Match %d: %s" % [current_match, message])
	current_match_log["errors"].append(message)
	errors_encountered += 1


func _report_bug(bug_type: String, description: String, context: Dictionary) -> void:
	"""Report a potential bug."""
	var bug := {
		"type": bug_type,
		"description": description,
		"match": current_match,
		"context": context,
		"timestamp": Time.get_datetime_string_from_system()
	}
	bugs_found.append(bug)
	bug_found.emit(bug)
	print("[BUG FOUND] %s: %s" % [bug_type, description])


func _generate_summary() -> String:
	"""Generate test session summary."""
	var lines: Array[String] = []
	lines.append("=== Test Summary ===")
	lines.append("Matches played: %d" % matches_completed)
	lines.append("Player 1 wins: %d (%.1f%%)" % [p1_wins, 100.0 * p1_wins / maxi(1, matches_completed)])
	lines.append("Player 2 wins: %d (%.1f%%)" % [p2_wins, 100.0 * p2_wins / maxi(1, matches_completed)])
	lines.append("Draws: %d" % draws)
	lines.append("Errors encountered: %d" % errors_encountered)
	lines.append("Bugs found: %d" % bugs_found.size())

	if not bugs_found.is_empty():
		lines.append("")
		lines.append("=== Bugs Found ===")
		for bug: Dictionary in bugs_found:
			lines.append("- [%s] %s (Match %d)" % [bug.get("type", "?"), bug.get("description", "?"), bug.get("match", 0)])

	return "\n".join(lines)


func get_bugs() -> Array[Dictionary]:
	"""Get all bugs found during testing."""
	return bugs_found


func get_full_log() -> String:
	"""Get complete log as string for file output."""
	var lines: Array[String] = []

	for match_log: Dictionary in match_logs:
		lines.append("=== Match %d ===" % match_log.get("match_number", 0))
		lines.append("Winner: Player %d" % match_log.get("winner", 0))
		lines.append("Rounds: %d" % match_log.get("rounds", 0))
		lines.append("Reason: %s" % match_log.get("reason", "unknown"))

		if not match_log.get("errors", []).is_empty():
			lines.append("Errors:")
			for error: String in match_log.get("errors", []):
				lines.append("  - %s" % error)

		if not match_log.get("warnings", []).is_empty():
			lines.append("Warnings:")
			for warning: String in match_log.get("warnings", []):
				lines.append("  - %s" % warning)

		lines.append("")

	lines.append(_generate_summary())

	return "\n".join(lines)
