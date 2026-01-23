class_name MatchRunner
extends RefCounted
## Executes AI vs AI matches using GameController properly
## Unlike AIvsAIRunner, this uses the full game systems for accurate effect tracking


signal match_started(config: TestSessionConfig.MatchConfig)
signal match_ended(result: MatchResult)
signal turn_completed(player_id: int, turn_number: int)
signal card_played(card_name: String, effect_result: EffectTracker.EffectResult)
signal action_executed(action_type: String, details: Dictionary)
signal debug_message(message: String)

## Verbose logging mode
var verbose: bool = true

## Debug log file
var _log_file: FileAccess = null

func _debug(msg: String) -> void:
	# Always print to console for debugging
	print(msg)
	# Also write to log file
	_write_log(msg)
	if verbose:
		debug_message.emit(msg)

func _write_log(msg: String) -> void:
	if _log_file == null:
		DirAccess.make_dir_recursive_absolute("user://test_reports/")
		_log_file = FileAccess.open("user://test_reports/debug_log.txt", FileAccess.WRITE)
	if _log_file:
		_log_file.store_line(msg)
		_log_file.flush()


const MAX_ROUNDS := 50
const MAX_ACTIONS_PER_TURN := 30
const MAX_CONSECUTIVE_PASSES := 10  # Allow more passes before stalemate - 5 rounds of both passing


## Game controller for this match
var game_controller: GameController

## AI controllers
var ai_player1: AIController
var ai_player2: AIController

## Effect tracker for no-op detection
var effect_tracker: EffectTracker

## RNG manager reference
var rng_manager: RNGManager

## Current match being run
var current_config: TestSessionConfig.MatchConfig
var current_result: MatchResult

## Turn tracking
var current_turn: int = 0
var turn_log: MatchResult.TurnLog

## Round tracking
var current_round_summary: MatchResult.RoundSummary
var last_round_number: int = 0

## Match state
var match_active: bool = false
var match_start_time: int = 0
var consecutive_passes: int = 0


func run_match(config: TestSessionConfig.MatchConfig, rng: RNGManager = null) -> MatchResult:
	"""Run a single match and return the result."""
	print(">>> MatchRunner.run_match() called")
	print(">>> P1 champions: %s" % str(config.p1_champions))
	print(">>> P2 champions: %s" % str(config.p2_champions))

	current_config = config
	rng_manager = rng

	# Initialize result
	current_result = MatchResult.new()
	current_result.match_id = config.match_index
	current_result.timestamp = Time.get_datetime_string_from_system()
	current_result.p1_champions = config.p1_champions.duplicate()
	current_result.p2_champions = config.p2_champions.duplicate()
	current_result.p1_difficulty = config.p1_difficulty
	current_result.p2_difficulty = config.p2_difficulty

	# Apply RNG seed
	if rng_manager != null:
		rng_manager.apply_match_seed(config.match_index)
		current_result.seed_used = rng_manager.current_match_seed
	elif config.seed_override != 0:
		seed(config.seed_override)
		current_result.seed_used = config.seed_override
	else:
		current_result.seed_used = randi()
		seed(current_result.seed_used)

	match_start_time = Time.get_ticks_msec()
	match_active = true
	consecutive_passes = 0

	match_started.emit(config)

	# Initialize game
	if not _initialize_game():
		current_result.winner = 0
		current_result.win_reason = "initialization_failed"
		if current_result.errors.is_empty():
			current_result.errors.append("Failed to initialize game (unknown reason)")
		_debug("  [ERROR] Match failed: %s" % str(current_result.errors))
		return current_result

	_debug("  [DEBUG] Game initialized, starting game loop...")

	# Main game loop
	_run_game_loop()

	# Finalize result
	current_result.duration_ms = Time.get_ticks_msec() - match_start_time
	_capture_final_state()

	match_active = false
	match_ended.emit(current_result)

	# Cleanup
	_cleanup()

	return current_result


func _initialize_game() -> bool:
	"""Initialize game controller and AI."""
	_debug("  [DEBUG] Initializing game...")

	# Verify CardDatabase is ready
	if not CardDatabase.is_loaded:
		_debug("  [ERROR] CardDatabase not loaded!")
		current_result.errors.append("CardDatabase not loaded")
		return false

	_debug("  [DEBUG] CardDatabase has %d cards" % CardDatabase.get_all_card_names().size())

	# Create game controller
	game_controller = GameController.new()
	if game_controller == null:
		_debug("  [ERROR] Failed to create GameController - class may have compile errors!")
		current_result.errors.append("GameController creation failed")
		return false

	_debug("  [DEBUG] GameController created, initializing with P1: %s, P2: %s" % [
		str(current_config.p1_champions), str(current_config.p2_champions)
	])

	var init_success: bool = false
	var init_error: String = ""

	# Try to initialize - catch any errors
	if current_config.p1_champions.size() != 2:
		init_error = "P1 needs exactly 2 champions, got %d" % current_config.p1_champions.size()
	elif current_config.p2_champions.size() != 2:
		init_error = "P2 needs exactly 2 champions, got %d" % current_config.p2_champions.size()
	else:
		init_success = game_controller.initialize(
			current_config.p1_champions,
			current_config.p2_champions
		)
		if not init_success:
			init_error = "GameController.initialize() returned false"

	if not init_success:
		_debug("  [ERROR] %s" % init_error)
		current_result.errors.append(init_error)
		return false

	_debug("  [DEBUG] GameController initialized successfully")

	# Verify game state exists
	if game_controller.game_state == null:
		_debug("  [ERROR] GameController.game_state is null!")
		current_result.errors.append("GameState is null after initialization")
		return false

	var state := game_controller.game_state
	_debug("  [DEBUG] GameState created - Round: %d, Active: P%d" % [state.round_number, state.active_player])

	# Check champions exist
	var p1_champs := state.get_champions(1)
	var p2_champs := state.get_champions(2)
	_debug("  [DEBUG] P1 has %d champions, P2 has %d champions" % [p1_champs.size(), p2_champs.size()])

	for c in p1_champs:
		_debug("    P1: %s HP=%d Power=%d at %s" % [c.champion_name, c.current_hp, c.current_power, c.position])
	for c in p2_champs:
		_debug("    P2: %s HP=%d Power=%d at %s" % [c.champion_name, c.current_hp, c.current_power, c.position])

	# Create AI controllers (convert int to Difficulty enum)
	ai_player1 = AIController.new(game_controller, 1)
	ai_player1.set_difficulty(current_config.p1_difficulty as AIController.Difficulty)

	ai_player2 = AIController.new(game_controller, 2)
	ai_player2.set_difficulty(current_config.p2_difficulty as AIController.Difficulty)
	_debug("  [DEBUG] AI controllers created")

	# Create effect tracker
	effect_tracker = EffectTracker.new()
	if game_controller.effect_processor != null:
		effect_tracker.connect_to_processor(
			game_controller.effect_processor,
			game_controller.game_state
		)
		effect_tracker.card_play_tracked.connect(_on_card_play_tracked)
		_debug("  [DEBUG] Effect tracker connected")
	else:
		_debug("  [WARN] No effect_processor on GameController")

	# Connect game controller signals
	if game_controller.has_signal("champion_died"):
		game_controller.champion_died.connect(_on_champion_died)
	if game_controller.has_signal("game_ended"):
		game_controller.game_ended.connect(_on_game_ended)

	_debug("  [DEBUG] Initialization complete")
	return true


func _run_game_loop() -> void:
	"""Main game loop - execute turns until game over."""
	var state := game_controller.game_state

	_debug("  [DEBUG] Starting game loop...")

	# Start the game (this triggers first turn)
	if game_controller.has_method("start_game"):
		game_controller.start_game()
		_debug("  [DEBUG] start_game() called")
	else:
		_debug("  [WARN] GameController has no start_game method")

	# Initialize round tracking
	last_round_number = 0
	_start_new_round(state.round_number)

	_debug("  [DEBUG] Loop conditions: active=%s, game_over=%s, round=%d" % [
		match_active, state.game_over, state.round_number
	])

	var loop_count := 0
	while match_active and not state.game_over and state.round_number <= MAX_ROUNDS:
		loop_count += 1
		if loop_count > 500:
			_debug("  [ERROR] Loop safety limit reached!")
			current_result.errors.append("Loop safety limit (500 iterations)")
			break

		# Execute turn for current player
		_debug("  [TURN] Round %d, Player %d's turn" % [state.round_number, state.active_player])
		_execute_player_turn(state.active_player)

		# Check for game over
		state.check_win_condition()
		if state.game_over:
			_debug("  [DEBUG] Game over! Winner: P%d" % state.winner)
			current_result.winner = state.winner
			current_result.win_reason = "champions_defeated"
			break

		# End turn and switch to next player
		_end_current_turn()

		# Safety: check for stalemate
		if consecutive_passes >= MAX_CONSECUTIVE_PASSES:
			_debug("  [WARN] Stalemate - %d consecutive passes" % consecutive_passes)
			current_result.warnings.append("Stalemate detected - too many consecutive passes")
			break

	_debug("  [DEBUG] Game loop ended. Rounds: %d, Winner: %d" % [state.round_number, current_result.winner])

	# Check round limit
	if state.round_number > MAX_ROUNDS and not state.game_over:
		_debug("  [DEBUG] Round limit reached, determining winner by HP")
		_determine_winner_by_hp(state)


func _execute_player_turn(player_id: int) -> void:
	"""Execute a single player's turn."""
	var state := game_controller.game_state
	var ai: AIController = ai_player1 if player_id == 1 else ai_player2

	current_turn += 1

	# Check for round change (new round starts when P1 turn begins again)
	_check_round_change()

	# Create turn log
	turn_log = MatchResult.TurnLog.new()
	turn_log.turn_number = current_turn
	turn_log.round_number = state.round_number
	turn_log.player_id = player_id
	turn_log.starting_mana = state.get_mana(player_id)

	var actions_this_turn := 0
	var passed := false

	while actions_this_turn < MAX_ACTIONS_PER_TURN and not state.game_over:
		# Wait for any response windows to close
		if game_controller.response_stack != null and game_controller.response_stack.is_open():
			_process_response_window(player_id)

		# Get all valid actions
		var valid_actions := _get_valid_actions(state, player_id)

		if valid_actions.is_empty():
			_debug("    [DEBUG] No valid actions for P%d" % player_id)
			passed = true
			break

		_debug("    [DEBUG] P%d has %d valid actions" % [player_id, valid_actions.size()])

		# Have AI choose and execute action
		var action := _ai_choose_action(ai, valid_actions, state)

		if action.is_empty() or action.get("type") == "end_turn":
			_debug("    [DEBUG] AI chose to end turn")
			passed = true
			break

		_debug("    [ACTION] %s: %s" % [action.get("type", "?"), action])

		# Execute the action
		var result := _execute_action(action, state)

		if result.get("success", false):
			actions_this_turn += 1
			_record_action(action, result)
			passed = false
			_debug("    [OK] Action succeeded")

			# Check for deaths
			state.check_win_condition()
			if state.game_over:
				_debug("    [DEBUG] Game over after action")
				break
		else:
			# Action failed, try another
			var err_msg: String = result.get("error", "unknown")
			_debug("    [FAIL] Action failed: %s" % err_msg)
			if err_msg != "":
				current_result.warnings.append("Action failed: %s" % err_msg)
			break

	_debug("    [DEBUG] Turn ended: %d actions, passed=%s" % [actions_this_turn, passed])

	# Update consecutive passes counter
	if passed:
		consecutive_passes += 1
	else:
		consecutive_passes = 0

	# Finalize turn log
	turn_log.ending_mana = state.get_mana(player_id)
	turn_log.actions_taken = actions_this_turn
	current_result.turn_logs.append(turn_log)

	turn_completed.emit(player_id, current_turn)


func _get_valid_actions(state: GameState, player_id: int) -> Array:
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
				if pos != champ.position:
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
			var hand: Array = state.get_hand(player_id)
			var mana: int = state.get_mana(player_id)

			var deck_size: int = state.get_deck(player_id).size()
			var discard_size: int = state.get_discard(player_id).size()

			for card_name in hand:
				var card_data := CardDatabase.get_card(str(card_name))
				var cost: int = _to_int(card_data.get("cost", 0))
				var card_type: String = str(card_data.get("type", ""))

				# Skip response cards
				if card_type == "Response":
					continue

				# Skip draw cards if they can't draw anything
				if _is_draw_card(card_data):
					if not _can_draw_card(card_data, state, player_id):
						continue

				if cost <= mana:
					var target_sets := _get_cast_targets(state, champ, card_data)
					for targets: Array in target_sets:
						actions.append({
							"type": "cast",
							"champion": champ.unique_id,
							"card": str(card_name),
							"targets": targets
						})

	return actions


func _ai_choose_action(ai: AIController, valid_actions: Array, state: GameState) -> Dictionary:
	"""Have AI choose from valid actions."""
	if valid_actions.is_empty():
		return {"type": "end_turn"}

	var best_action: Dictionary = {}
	var best_score := -999.0

	for action: Dictionary in valid_actions:
		var score := _score_action(action, state, ai.player_id)
		# Add randomization based on AI difficulty
		var randomization := 0.15  # Medium default
		match ai.difficulty:
			AIController.Difficulty.EASY:
				randomization = 0.35
			AIController.Difficulty.HARD:
				randomization = 0.05
		score *= randf_range(1.0 - randomization, 1.0 + randomization)

		if score > best_score:
			best_score = score
			best_action = action

	return best_action


func _score_action(action: Dictionary, state: GameState, player_id: int) -> float:
	"""Score an action for AI decision making."""
	var score := 1.0
	var action_type: String = action.get("type", "")

	match action_type:
		"attack":
			# Attacks are HIGHEST priority - always attack when possible
			score = 25.0
			var target_id: String = action.get("target", "")
			var attacker_id: String = action.get("champion", "")
			var target := state.get_champion(target_id)
			var attacker := state.get_champion(attacker_id)
			if target and attacker:
				# Kill bonus - VERY high priority
				if target.current_hp <= attacker.current_power:
					score += 50.0
				# Low HP target bonus - focus damaged enemies aggressively
				score += (20.0 - target.current_hp) * 1.5
				# Bonus for attacking with high power
				score += attacker.current_power * 3.0
				# Extra bonus if target is the only enemy left
				var opp_id: int = 2 if attacker.owner_id == 1 else 1
				if state.get_living_champions(opp_id).size() == 1:
					score += 15.0

		"move":
			# Moving toward enemies is important when can't attack
			score = 5.0
			var champ_id: String = action.get("champion", "")
			var champion := state.get_champion(champ_id)
			var target_pos: Vector2i = action.get("target", Vector2i.ZERO)
			if champion:
				var opp_id: int = 2 if player_id == 1 else 1
				var enemies := state.get_living_champions(opp_id)
				var current_pos: Vector2i = champion.position

				# Calculate distance improvement to nearest enemy
				var best_current_dist := 999
				var best_new_dist := 999
				for enemy: ChampionState in enemies:
					var current_dist: int = absi(current_pos.x - enemy.position.x) + absi(current_pos.y - enemy.position.y)
					var new_dist: int = absi(target_pos.x - enemy.position.x) + absi(target_pos.y - enemy.position.y)
					best_current_dist = mini(best_current_dist, current_dist)
					best_new_dist = mini(best_new_dist, new_dist)

				# Big bonus for moving closer to enemies - be aggressive
				if best_new_dist < best_current_dist:
					score += 12.0 + (best_current_dist - best_new_dist) * 3.0
				elif best_new_dist > best_current_dist:
					score -= 8.0  # Strong penalty for retreating

				# BIG bonus if this move puts us in attack range
				for enemy: ChampionState in enemies:
					var chebyshev: int = maxi(absi(target_pos.x - enemy.position.x), absi(target_pos.y - enemy.position.y))
					if chebyshev <= champion.current_range:
						score += 20.0  # Getting in range is very valuable
						break

		"cast":
			score = 6.0
			var card_name: String = action.get("card", "")
			var card_data := CardDatabase.get_card(card_name)
			var effects: Array = card_data.get("effect", [])
			var targets: Array = action.get("targets", [])
			var caster_id: String = action.get("champion", "")
			var caster := state.get_champion(caster_id)

			for effect: Dictionary in effects:
				var effect_type: String = str(effect.get("type", ""))
				var effect_value: int = _to_int(effect.get("value", 0))
				match effect_type:
					"damage":
						# Damage cards are high priority - scale by damage value
						var target_type: String = str(card_data.get("target", ""))
						if target_type == "direction":
							# Direction card - bonus if enemies are in that direction
							if targets.size() > 0 and caster:
								var dir: String = str(targets[0])
								var opp_id: int = 1 if caster.owner_id == 2 else 2
								var enemies := state.get_living_champions(opp_id)
								if _has_enemy_in_direction(caster, dir, enemies, state):
									score += 15.0 + effect_value * 2.0
								else:
									score -= 8.0  # Penalty for wasting card
						else:
							score += 12.0 + effect_value * 2.0
							# Extra bonus if target is low HP (potential kill)
							for target_id in targets:
								var target := state.get_champion(str(target_id))
								if target and target.current_hp <= effect_value:
									score += 25.0  # Kill potential!
					"heal":
						# Check if heal target actually needs healing
						var heal_useful := false
						var target_type: String = str(card_data.get("target", ""))
						if target_type == "self" or target_type == "none" or target_type == "":
							if caster and caster.current_hp < caster.max_hp:
								heal_useful = true
								score += 8.0 * (1.0 - float(caster.current_hp) / caster.max_hp)
						elif target_type == "friendly" or target_type == "ally" or target_type == "allyorself":
							for target_id in targets:
								var target := state.get_champion(str(target_id))
								if target and target.current_hp < target.max_hp:
									heal_useful = true
									score += 8.0 * (1.0 - float(target.current_hp) / target.max_hp)
									break
						elif target_type == "position":
							# AOE heal - check if any allies need healing
							for ally: ChampionState in state.get_living_champions(player_id):
								if ally.current_hp < ally.max_hp:
									heal_useful = true
									score += 4.0 * (1.0 - float(ally.current_hp) / ally.max_hp)
						if not heal_useful:
							score -= 10.0  # Strong penalty for useless heal
					"buff":
						score += 4.0
					"debuff":
						# Debuffs that disable enemies are valuable
						var debuff_name: String = str(effect.get("name", ""))
						if debuff_name in ["canAttack", "canCast", "canMove", "stunned"]:
							score += 10.0  # Disabling effects are strong
						else:
							score += 5.0
					"draw":
						# Drawing is good if hand isn't full
						var hand := state.get_hand(player_id)
						if hand.size() < 5:
							score += 3.0
						elif hand.size() >= 7:
							score -= 2.0  # Will have to discard

	return score


func _execute_action(action: Dictionary, state: GameState) -> Dictionary:
	"""Execute an action through GameController."""
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
			var card_name: String = action.get("card", "")
			var caster_id: String = action.get("champion", "")
			var targets: Array = action.get("targets", [])

			# Track the card play
			var caster := state.get_champion(caster_id)
			if caster:
				effect_tracker.begin_card_tracking(card_name, caster_id, caster.owner_id)

			var result := game_controller.cast_card(card_name, caster_id, targets)

			# End tracking
			if caster:
				var effect_result := effect_tracker.end_card_tracking()
				_record_card_play(card_name, caster_id, caster.owner_id, targets, effect_result)

			return result

	return {"success": false, "error": "Unknown action type"}


func _record_action(action: Dictionary, result: Dictionary) -> void:
	"""Record an action to the turn log."""
	var action_type: String = action.get("type", "")
	var state := game_controller.game_state

	match action_type:
		"move":
			turn_log.moves_made += 1
			var champ_id: String = action.get("champion", "")
			_record_round_move(champ_id)
		"attack":
			turn_log.attacks_made += 1
			var damage: int = result.get("damage", 0)
			turn_log.damage_dealt += damage
			# Record to round summary
			var attacker_id: String = action.get("champion", "")
			var target_id: String = action.get("target", "")
			_record_round_attack(attacker_id)
			if damage > 0:
				_record_round_damage(attacker_id, target_id, damage)
		"cast":
			turn_log.cards_played.append(str(action.get("card", "")))

	# Record for replay
	current_result.record_replay_action(
		action,
		result,
		state.round_number,
		current_turn,
		state.active_player
	)

	action_executed.emit(action_type, action)


func _record_card_play(card_name: String, caster_id: String, player_id: int, targets: Array, effect_result: EffectTracker.EffectResult) -> void:
	"""Record a card play to the match result."""
	var record := MatchResult.CardPlayRecord.new()
	record.card_name = card_name
	record.caster_id = caster_id
	record.player_id = player_id
	record.targets = targets
	record.turn_number = current_turn
	record.round_number = game_controller.game_state.round_number

	var card_data := CardDatabase.get_card(card_name)
	record.card_type = str(card_data.get("type", ""))
	record.mana_cost = _to_int(card_data.get("cost", 0))
	record.mana_available = game_controller.game_state.get_mana(player_id) + record.mana_cost

	var caster := game_controller.game_state.get_champion(caster_id)
	if caster:
		record.caster_name = caster.champion_name

	# Copy effect tracking data
	record.damage_dealt = effect_result.damage_dealt
	record.healing_done = effect_result.healing_done
	record.buffs_applied = effect_result.buffs_applied
	record.debuffs_applied = effect_result.debuffs_applied
	record.movements_caused = effect_result.movements_caused
	record.cards_drawn = effect_result.cards_drawn
	record.is_noop = effect_result.is_noop
	record.noop_reason = effect_result.noop_reason

	current_result.card_plays.append(record)

	# Also record to round summary
	_record_round_card_play(
		caster_id, card_name,
		effect_result.damage_dealt, effect_result.healing_done,
		targets, effect_result.is_noop
	)

	# Record damage dealt to specific targets at round level
	if effect_result.damage_dealt > 0 and not targets.is_empty():
		# Distribute damage tracking (simplified - attribute all to first target)
		for target in targets:
			var target_id: String = str(target)
			_record_round_damage(caster_id, target_id, effect_result.damage_dealt)

	# Record healing at round level
	if effect_result.healing_done > 0:
		# Healing targets might be self or allies
		if targets.is_empty():
			_record_round_healing(caster_id, caster_id, effect_result.healing_done)
		else:
			for target in targets:
				_record_round_healing(caster_id, str(target), effect_result.healing_done)

	card_played.emit(card_name, effect_result)


func _process_response_window(player_id: int) -> void:
	"""Process response window (simplified - just pass for testing)."""
	# In testing mode, AI would play responses or pass
	# For simplicity, we just close the window
	if game_controller.response_stack.is_open():
		game_controller.response_stack.pass_priority()
		if game_controller.response_stack.is_open():
			game_controller.response_stack.pass_priority()


func _end_current_turn() -> void:
	"""End the current turn and start the next."""
	var state := game_controller.game_state
	var current_player := state.active_player

	# Track cards held at end of turn (before discard)
	var hand: Array = state.get_hand(current_player)
	for card_name in hand:
		current_result.record_card_held(str(card_name))

	# Discard down to 7 cards
	while hand.size() > 7:
		var discarded = hand.pop_back()
		state.get_discard(current_player).append(discarded)
		current_result.record_card_discarded(str(discarded), true)  # From hand limit

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

	# Start of turn effects
	state.reset_mana(next_player)
	for champ: ChampionState in state.get_champions(next_player):
		champ.reset_turn()

	# Draw card and track it
	if state.get_hand(next_player).size() < 10:
		var drawn := state.draw_card(next_player)
		if not drawn.is_empty():
			current_result.record_card_drawn(drawn)


func _determine_winner_by_hp(state: GameState) -> void:
	"""Determine winner by total HP when round limit reached."""
	var p1_hp := 0
	var p2_hp := 0

	for champ: ChampionState in state.get_champions(1):
		p1_hp += maxi(0, champ.current_hp)
	for champ: ChampionState in state.get_champions(2):
		p2_hp += maxi(0, champ.current_hp)

	if p1_hp > p2_hp:
		current_result.winner = 1
	elif p2_hp > p1_hp:
		current_result.winner = 2
	else:
		current_result.winner = 0  # Draw

	current_result.win_reason = "round_limit_hp_advantage"
	current_result.total_rounds = MAX_ROUNDS


func _capture_final_state() -> void:
	"""Capture final state for the result."""
	if game_controller == null or game_controller.game_state == null:
		return

	var state := game_controller.game_state
	current_result.total_rounds = state.round_number
	current_result.total_turns = current_turn

	# Finalize the last round
	_finalize_round_summary()

	for champ: ChampionState in state.get_all_champions():
		current_result.final_champion_hp[champ.unique_id] = champ.current_hp


func _cleanup() -> void:
	"""Clean up after match."""
	if effect_tracker != null:
		effect_tracker.disconnect_from_processor()
		effect_tracker = null

	game_controller = null
	ai_player1 = null
	ai_player2 = null


func _get_cast_targets(state: GameState, caster: ChampionState, card_data: Dictionary) -> Array:
	"""Get valid target combinations for a card."""
	var target_sets: Array = []
	var target_type: String = str(card_data.get("target", "none"))
	var player_id: int = caster.owner_id

	var target_type_lower := target_type.to_lower()
	match target_type_lower:
		"none", "self":
			# For self-heal cards, don't offer if at full HP
			if _is_heal_card(card_data) and caster.current_hp >= caster.max_hp:
				pass  # Don't offer this card
			else:
				target_sets.append([])
		"enemy":
			var opp_id: int = 1 if player_id == 2 else 2
			for enemy: ChampionState in state.get_living_champions(opp_id):
				target_sets.append([enemy.unique_id])
		"ally", "friendly":
			# Check if this is a heal card - only offer targets that need healing
			var is_heal_card := _is_heal_card(card_data)
			for ally: ChampionState in state.get_living_champions(player_id):
				# For "ally", exclude self. For "friendly", include self.
				if target_type_lower == "ally" and ally.unique_id == caster.unique_id:
					continue
				# Skip full HP allies for heal cards
				if is_heal_card and ally.current_hp >= ally.max_hp:
					continue
				target_sets.append([ally.unique_id])
		"champion", "any":
			for champ: ChampionState in state.get_all_champions():
				if champ.is_alive():
					target_sets.append([champ.unique_id])
		"allyorself":
			var is_heal_card := _is_heal_card(card_data)
			for ally: ChampionState in state.get_living_champions(player_id):
				# Skip full HP allies for heal cards
				if is_heal_card and ally.current_hp >= ally.max_hp:
					continue
				target_sets.append([ally.unique_id])
		"direction":
			# Direction-based cards (like Ground Pound) - offer all 4 directions
			# Only include directions that have potential targets (enemies in LOS)
			var opp_id: int = 1 if player_id == 2 else 2
			var enemies := state.get_living_champions(opp_id)
			for dir: String in ["up", "down", "left", "right"]:
				# Check if any enemy is in this direction
				if _has_enemy_in_direction(caster, dir, enemies, state):
					target_sets.append([dir])
			# If no enemies in any direction, still allow casting (might hit allies or just miss)
			if target_sets.is_empty():
				for dir: String in ["up", "down", "left", "right"]:
					target_sets.append([dir])
		"position":
			# Position-based cards (like Healing Rain AOE) - find positions near targets
			var range_val: int = _get_card_range(card_data, caster)
			var positions := _get_valid_aoe_positions(state, caster, card_data, range_val)
			for pos: Vector2i in positions:
				target_sets.append([pos])
			# Fallback: caster's own position
			if target_sets.is_empty():
				target_sets.append([caster.position])
		_:
			target_sets.append([])

	return target_sets


func _is_heal_card(card_data: Dictionary) -> bool:
	"""Check if a card has healing effects."""
	var effects: Array = card_data.get("effect", [])
	for effect: Dictionary in effects:
		if str(effect.get("type", "")) == "heal":
			return true
	return false


func _is_draw_card(card_data: Dictionary) -> bool:
	"""Check if a card has draw effects."""
	var effects: Array = card_data.get("effect", [])
	for effect: Dictionary in effects:
		if str(effect.get("type", "")) == "draw":
			return true
	return false


func _can_draw_card(card_data: Dictionary, state: GameState, player_id: int) -> bool:
	"""Check if a draw card can actually draw anything."""
	var effects: Array = card_data.get("effect", [])
	var deck: Array = state.get_deck(player_id)
	var discard: Array = state.get_discard(player_id)
	var opp_id: int = 2 if player_id == 1 else 1
	var opp_discard: Array = state.get_discard(opp_id)

	for effect: Dictionary in effects:
		if str(effect.get("type", "")) != "draw":
			continue

		var condition: Dictionary = effect.get("condition", {})
		var from_source: String = str(condition.get("from", "deck"))

		# Check the source pile
		var source_pile: Array = []
		match from_source:
			"discard":
				source_pile = discard
			"oppDiscard":
				source_pile = opp_discard
			_:  # "deck" or unspecified
				source_pile = deck

		if source_pile.is_empty():
			continue  # This effect can't draw, check next effect

		# Check if there are valid cards matching the filter
		var filter_char: String = str(condition.get("filter", ""))
		var max_cost: int = condition.get("maxCost", 999)

		if filter_char.is_empty() and max_cost >= 999:
			return true  # No filter, can draw anything from non-empty pile

		# Check if any card in source matches filter
		for card_name in source_pile:
			var check_card := CardDatabase.get_card(str(card_name))
			var card_char: String = str(check_card.get("character", ""))
			var card_cost: int = _to_int(check_card.get("cost", 0))

			var matches_char := filter_char.is_empty() or card_char == filter_char
			var matches_cost := card_cost <= max_cost

			if matches_char and matches_cost:
				return true  # Found a valid card to draw

	return false  # No draw effect can actually draw anything


func _has_enemy_in_direction(caster: ChampionState, direction: String, enemies: Array, state: GameState) -> bool:
	"""Check if any enemy is in line of sight in the given direction."""
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
			return false

	var pos: Vector2i = caster.position + dir_vec
	while state.is_valid_position(pos):
		var terrain := state.get_terrain(pos)
		if terrain == GameState.Terrain.WALL:
			break
		# Check for any champion at this position
		for enemy: ChampionState in enemies:
			if enemy.position == pos:
				return true
		pos += dir_vec

	return false


func _get_card_range(card_data: Dictionary, caster: ChampionState) -> int:
	"""Get the range of a card, defaulting to caster's range."""
	var range_str: String = str(card_data.get("range", ""))
	if range_str.is_valid_int():
		return range_str.to_int()
	elif range_str == "melee":
		return 1
	elif range_str == "AOE":
		return 3  # Default AOE range
	else:
		return caster.current_range


func _get_valid_aoe_positions(state: GameState, caster: ChampionState, card_data: Dictionary, range_val: int) -> Array[Vector2i]:
	"""Get valid positions for AOE cards that would hit targets."""
	var positions: Array[Vector2i] = []
	var effects: Array = card_data.get("effect", [])

	# Determine if this heals allies or damages enemies
	var heals := false
	var damages := false
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", ""))
		if etype == "heal":
			heals = true
		elif etype == "damage":
			damages = true

	# Get potential targets based on card effect
	var targets: Array[ChampionState] = []
	if heals:
		targets.assign(state.get_living_champions(caster.owner_id))
	if damages:
		var opp_id: int = 1 if caster.owner_id == 2 else 2
		for enemy: ChampionState in state.get_living_champions(opp_id):
			if enemy not in targets:
				targets.append(enemy)

	# For each potential target, their position is a valid AOE center
	for target: ChampionState in targets:
		if target.position not in positions:
			positions.append(target.position)

	return positions


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


func _on_card_play_tracked(card_name: String, result: EffectTracker.EffectResult) -> void:
	"""Handle card play tracking completion."""
	pass  # Already handled in _record_card_play


func _on_champion_died(champion_id: String) -> void:
	"""Handle champion death."""
	pass  # Deaths are tracked through win condition


func _on_game_ended(winner: int, reason: String) -> void:
	"""Handle game end signal."""
	match_active = false
	current_result.winner = winner
	current_result.win_reason = reason


## ===== ROUND TRACKING =====

func _start_new_round(round_number: int) -> void:
	"""Start tracking a new round."""
	# Finalize previous round if any
	if current_round_summary != null:
		_finalize_round_summary()

	# Create new round summary
	current_round_summary = MatchResult.RoundSummary.new()
	current_round_summary.round_number = round_number
	last_round_number = round_number

	# Capture HP at start of round
	var state := game_controller.game_state
	for champ: ChampionState in state.get_all_champions():
		current_round_summary.hp_at_start[champ.unique_id] = champ.current_hp
		# Pre-create champion stats entries
		current_round_summary.get_or_create_champion_stats(
			champ.unique_id,
			champ.champion_name,
			champ.owner_id
		)


func _finalize_round_summary() -> void:
	"""Finalize current round and add to result."""
	if current_round_summary == null:
		return

	# Capture HP at end of round
	var state := game_controller.game_state
	for champ: ChampionState in state.get_all_champions():
		current_round_summary.hp_at_end[champ.unique_id] = champ.current_hp

		# Check if champion died this round
		var start_hp: int = current_round_summary.hp_at_start.get(champ.unique_id, 0)
		if start_hp > 0 and champ.current_hp <= 0:
			current_round_summary.champions_killed.append(champ.unique_id)
			var champ_stats = current_round_summary.champion_stats.get(champ.unique_id)
			if champ_stats:
				champ_stats.killed_this_round = true
				# Try to find killer
				var max_damage := 0
				var killer_id := ""
				for source_id: String in champ_stats.damage_by_source:
					if champ_stats.damage_by_source[source_id] > max_damage:
						max_damage = champ_stats.damage_by_source[source_id]
						killer_id = source_id
				champ_stats.killed_by = killer_id

	# Check if game ended
	if state.game_over:
		current_round_summary.game_ended = true
		current_round_summary.winner = state.winner

	current_result.round_summaries.append(current_round_summary)


func _check_round_change() -> void:
	"""Check if round number changed and start new round tracking if needed."""
	var state := game_controller.game_state
	if state.round_number != last_round_number:
		_start_new_round(state.round_number)


func _record_round_damage(attacker_id: String, target_id: String, amount: int) -> void:
	"""Record damage to current round summary."""
	if current_round_summary == null:
		return

	var state := game_controller.game_state
	var attacker := state.get_champion(attacker_id)
	var target := state.get_champion(target_id)

	if attacker:
		var attacker_stats = current_round_summary.get_or_create_champion_stats(
			attacker_id, attacker.champion_name, attacker.owner_id
		)
		attacker_stats.record_damage_dealt(amount, target_id)

	if target:
		var target_stats = current_round_summary.get_or_create_champion_stats(
			target_id, target.champion_name, target.owner_id
		)
		target_stats.record_damage_taken(amount, attacker_id)


func _record_round_healing(source_id: String, target_id: String, amount: int) -> void:
	"""Record healing to current round summary."""
	if current_round_summary == null:
		return

	var state := game_controller.game_state
	var source := state.get_champion(source_id)
	var target := state.get_champion(target_id)

	if source:
		var source_stats = current_round_summary.get_or_create_champion_stats(
			source_id, source.champion_name, source.owner_id
		)
		source_stats.healing_done += amount

	if target:
		var target_stats = current_round_summary.get_or_create_champion_stats(
			target_id, target.champion_name, target.owner_id
		)
		target_stats.healing_received += amount


func _record_round_card_play(caster_id: String, card_name: String, damage: int, healing: int, targets: Array, is_noop: bool) -> void:
	"""Record card play to current round summary."""
	if current_round_summary == null:
		return

	var state := game_controller.game_state
	var caster := state.get_champion(caster_id)
	if caster == null:
		return

	var caster_stats = current_round_summary.get_or_create_champion_stats(
		caster_id, caster.champion_name, caster.owner_id
	)
	caster_stats.record_card_played(card_name, damage, healing, targets, is_noop)

	# Also add to round's overall card list
	current_round_summary.cards_played.append(card_name)
	current_round_summary.card_play_details.append({
		"card_name": card_name,
		"caster": caster_id,
		"caster_name": caster.champion_name,
		"player": caster.owner_id,
		"damage": damage,
		"healing": healing,
		"targets": targets,
		"is_noop": is_noop
	})


func _record_round_attack(attacker_id: String) -> void:
	"""Record an attack to current round summary."""
	if current_round_summary == null:
		return

	var state := game_controller.game_state
	var attacker := state.get_champion(attacker_id)
	if attacker:
		var attacker_stats = current_round_summary.get_or_create_champion_stats(
			attacker_id, attacker.champion_name, attacker.owner_id
		)
		attacker_stats.attacks_made += 1


func _record_round_move(champion_id: String) -> void:
	"""Record a move to current round summary."""
	if current_round_summary == null:
		return

	var state := game_controller.game_state
	var champ := state.get_champion(champion_id)
	if champ:
		var champ_stats = current_round_summary.get_or_create_champion_stats(
			champion_id, champ.champion_name, champ.owner_id
		)
		champ_stats.moves_made += 1
