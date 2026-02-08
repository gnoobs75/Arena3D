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

	# Connect effect processor signals for AI auto-resolution
	if game_controller.effect_processor != null:
		game_controller.effect_processor.immediate_movement_required.connect(_on_immediate_movement_required)
		game_controller.effect_processor.discard_selection_required.connect(_on_discard_selection_required)
		game_controller.effect_processor.cards_drawn.connect(_on_cards_drawn)
		if game_controller.effect_processor.has_signal("intel_choice_required"):
			game_controller.effect_processor.intel_choice_required.connect(_on_intel_choice_required)
		if game_controller.effect_processor.has_signal("x_value_required"):
			game_controller.effect_processor.x_value_required.connect(_on_x_value_required)
		if game_controller.effect_processor.has_signal("discard_choice_required"):
			game_controller.effect_processor.discard_choice_required.connect(_on_discard_choice_required)
		_debug("  [DEBUG] Effect processor signals connected")

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
			_determine_winner_by_hp(state)  # Determine winner even in stalemate
			current_result.win_reason = "stalemate_hp_advantage"
			break

	_debug("  [DEBUG] Game loop ended. Rounds: %d, Winner: %d" % [state.round_number, current_result.winner])

	# Check round limit - determine winner if game ended without clear victor
	if current_result.winner == 0 and not state.game_over:
		_debug("  [DEBUG] No winner yet, determining winner by HP")
		_determine_winner_by_hp(state)


func _execute_player_turn(player_id: int) -> void:
	"""Execute a single player's turn."""
	var state := game_controller.game_state
	var ai: AIController = ai_player1 if player_id == 1 else ai_player2

	current_turn += 1

	# Check for round change (new round starts when P1 turn begins again)
	_check_round_change()

	# Fire startTurn trigger
	_fire_trigger("startTurn", {"player": player_id})

	# AI manages response slot at start of turn (using public API)
	if ai != null:
		ai.manage_response_slot()

	# Create turn log
	turn_log = MatchResult.TurnLog.new()
	turn_log.turn_number = current_turn
	turn_log.round_number = state.round_number
	turn_log.player_id = player_id
	turn_log.starting_mana = state.get_mana(player_id)

	var actions_this_turn := 0
	var passed := false
	var consecutive_action_failures := 0
	var failed_action_keys: Dictionary = {}  # Track failed actions to avoid retrying them

	while actions_this_turn < MAX_ACTIONS_PER_TURN and not state.game_over:
		# Wait for any response windows to close
		if game_controller.response_stack != null and game_controller.response_stack.is_open():
			_process_response_window(player_id)

		# Get all valid actions using AI controller's logic (single source of truth)
		var valid_actions := ai.get_valid_actions_for_player()

		# Filter out previously failed actions
		if not failed_action_keys.is_empty():
			valid_actions = valid_actions.filter(func(a: Dictionary) -> bool:
				var key := _make_action_key(a)
				return not failed_action_keys.has(key)
			)

		if valid_actions.is_empty():
			_debug("    [DEBUG] No valid actions for P%d" % player_id)
			# Only count as a "pass" if NO actions were taken this turn
			# Having no more actions after taking some is normal gameplay
			if actions_this_turn == 0:
				passed = true
			break

		_debug("    [DEBUG] P%d has %d valid actions" % [player_id, valid_actions.size()])

		# Have AI choose action using its own scoring logic (single source of truth)
		var action := ai.choose_best_action(valid_actions)

		if action.is_empty() or action.get("type") == "end_turn":
			_debug("    [DEBUG] AI chose to end turn")
			# Only count as a "pass" if NO actions were taken this turn
			if actions_this_turn == 0:
				passed = true
			break

		_debug("    [ACTION] %s: %s" % [action.get("type", "?"), action])

		# Execute the action
		var result := _execute_action(action, state)

		if result.get("success", false):
			actions_this_turn += 1
			_record_action(action, result)
			passed = false
			consecutive_action_failures = 0
			_debug("    [OK] Action succeeded")

			# Check for deaths
			state.check_win_condition()
			if state.game_over:
				_debug("    [DEBUG] Game over after action")
				break
		else:
			# Action failed - mark it as failed and try another
			var err_msg: String = result.get("error", "unknown")
			_debug("    [FAIL] Action failed: %s" % err_msg)
			if err_msg != "":
				current_result.warnings.append("Action failed: %s" % err_msg)

			# Track this failed action to avoid retrying it
			var action_key := _make_action_key(action)
			failed_action_keys[action_key] = true

			consecutive_action_failures += 1
			if consecutive_action_failures >= 5:
				_debug("    [DEBUG] Too many consecutive failures, ending turn")
				break
			# Continue loop to try other actions

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


func _execute_action(action: Dictionary, state: GameState) -> Dictionary:
	"""Execute an action through GameController."""
	var action_type: String = action.get("type", "")

	match action_type:
		"move":
			var champ_id: String = action.get("champion", "")
			var target_pos: Vector2i = action.get("target", Vector2i.ZERO)
			var old_pos: Vector2i = Vector2i.ZERO
			var champ := state.get_champion(champ_id)
			if champ:
				old_pos = champ.position

			var result := game_controller.move_champion(champ_id, target_pos)

			# Fire onMove trigger after successful move
			if result.get("success", false):
				_fire_trigger("onMove", {
					"champion": champ_id,
					"from": old_pos,
					"to": target_pos,
					"player": champ.owner_id if champ else 0
				})
			return result

		"attack":
			var attacker_id: String = action.get("champion", "")
			var target_id: String = action.get("target", "")
			var attacker := state.get_champion(attacker_id)
			var target := state.get_champion(target_id)

			# Fire beforeDamage trigger
			if attacker and target:
				_fire_trigger("beforeDamage", {
					"attacker": attacker_id,
					"target": target_id,
					"source": "attack",
					"damage": attacker.current_power,
					"player": attacker.owner_id
				})

			var result := game_controller.attack_champion(attacker_id, target_id)

			# Fire afterDamage trigger after successful attack
			if result.get("success", false) and attacker and target:
				_fire_trigger("afterDamage", {
					"attacker": attacker_id,
					"target": target_id,
					"source": "attack",
					"damage": result.get("damage", 0),
					"player": attacker.owner_id
				})
			return result

		"cast":
			var card_name: String = action.get("card", "")
			var caster_id: String = action.get("champion", "")
			var targets: Array = action.get("targets", [])

			# Track the card play
			var caster := state.get_champion(caster_id)
			if caster:
				effect_tracker.begin_card_tracking(card_name, caster_id, caster.owner_id)

			# NOTE: Don't fire onCast trigger here - game_controller.cast_card handles it
			# Firing it here causes double-triggering and state changes after validation

			# Pre-validate heal - skip if heal wouldn't have effect
			# This check runs BEFORE the onCast trigger in game_controller
			var card_data := CardDatabase.get_card(card_name)
			var is_heal := _is_heal_card(card_data)
			if is_heal:
				var would_have_effect := _would_heal_have_effect_now(card_data, caster, targets, state)
				if not would_have_effect:
					_debug("    [SKIP] Heal would have no effect, skipping")
					if caster:
						effect_tracker.end_card_tracking()  # End tracking without recording
					return {"success": false, "error": "heal_would_have_no_effect"}

			var result := game_controller.cast_card(card_name, caster_id, targets)

			# End tracking
			if caster:
				var effect_result := effect_tracker.end_card_tracking()
				_record_card_play(card_name, caster_id, caster.owner_id, targets, effect_result)

				# Fire additional triggers based on card effects
				if effect_result.damage_dealt > 0:
					for target in targets:
						var target_str: String = str(target)
						# Fire afterDamage for spell damage
						_fire_trigger("afterDamage", {
							"attacker": caster_id,
							"target": target_str,
							"source": "spell",
							"card": card_name,
							"damage": effect_result.damage_dealt,
							"player": caster.owner_id
						})

				if effect_result.healing_done > 0:
					_fire_trigger("onHeal", {
						"healer": caster_id,
						"card": card_name,
						"amount": effect_result.healing_done,
						"player": caster.owner_id
					})

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
	record.is_success = not effect_result.is_noop
	record.success_effects = effect_result.success_effects.duplicate()

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


func _fire_trigger(trigger: String, context: Dictionary) -> void:
	"""Fire a trigger and let response slots auto-cast if applicable."""
	if game_controller == null:
		return

	# Use GameController's trigger checking which handles response slot auto-cast
	if game_controller.has_method("_check_trigger"):
		game_controller._check_trigger(trigger, context)
	else:
		# Fallback: manually check response slots for both players
		_try_auto_cast_response(1, trigger, context)
		_try_auto_cast_response(2, trigger, context)


func _try_auto_cast_response(player_id: int, trigger: String, context: Dictionary) -> void:
	"""Try to auto-cast from a player's response slot."""
	var state := game_controller.game_state
	var slot_card := state.get_response_slot(player_id)

	if slot_card.is_empty():
		return

	var card_data := CardDatabase.get_card(slot_card)
	if card_data.is_empty():
		return

	# Check if trigger matches
	var card_trigger: String = card_data.get("trigger", "")
	if card_trigger != trigger:
		return

	# Check mana
	var cost: int = card_data.get("cost", 0)
	var mana := state.get_mana(player_id)
	if mana < cost:
		_debug("    [RESPONSE] P%d: %s trigger matched but insufficient mana (%d/%d)" % [player_id, slot_card, mana, cost])
		return

	# Find a caster for the response
	var card_character: String = card_data.get("character", "")
	var caster: ChampionState = null

	for champ: ChampionState in state.get_living_champions(player_id):
		if card_character.is_empty() or champ.champion_name == card_character:
			caster = champ
			break

	if caster == null:
		return

	# Check range condition for cards like Pit of Despair (must be cast when enemy in range)
	var card_range = card_data.get("range", "")
	if card_range is int and card_range > 0 and trigger == "onMove":
		# For onMove triggers with range, check if mover is within range of caster
		var mover_id: String = context.get("champion", "")
		var mover := state.get_champion(mover_id)
		if mover == null:
			return
		# Check if mover is an enemy that just moved into range
		if mover.owner_id == player_id:
			return  # Only trigger on enemy moves
		var target_pos: Vector2i = context.get("to", mover.position)
		var dist: int = maxi(absi(target_pos.x - caster.position.x), absi(target_pos.y - caster.position.y))
		if dist > card_range:
			_debug("    [RESPONSE] P%d: %s - mover not in range (dist=%d, required=%d)" % [player_id, slot_card, dist, card_range])
			return

	# Check onDraw trigger condition - Hypocrite should only trigger on OPPONENT's extra draws
	if trigger == "onDraw":
		var drawing_player: int = context.get("player", 0)
		var is_extra: bool = context.get("is_extra", false)
		# Hypocrite triggers when opponent draws extra cards
		if drawing_player == player_id:
			return  # Don't trigger on own draws
		if not is_extra:
			return  # Don't trigger on normal start-of-turn draws
		_debug("    [RESPONSE] P%d: %s - opponent drew extra cards" % [player_id, slot_card])

	_debug("    [RESPONSE] P%d auto-casting %s (trigger: %s)" % [player_id, slot_card, trigger])

	# Track the card play
	effect_tracker.begin_card_tracking(slot_card, caster.unique_id, player_id)

	# Determine targets based on card and context
	var targets := _get_response_targets(card_data, caster, context, state)

	# Cast the card
	var result := game_controller.cast_card(slot_card, caster.unique_id, targets)

	# End tracking
	var effect_result := effect_tracker.end_card_tracking()
	_record_card_play(slot_card, caster.unique_id, player_id, targets, effect_result)

	# Clear the response slot
	state.clear_response_slot(player_id)

	if result.get("success", false):
		_debug("    [RESPONSE] %s cast successfully" % slot_card)
	else:
		_debug("    [RESPONSE] %s cast failed: %s" % [slot_card, result.get("error", "unknown")])


func _get_response_targets(card_data: Dictionary, caster: ChampionState, context: Dictionary, state: GameState) -> Array:
	"""Determine targets for a response card based on trigger context."""
	var target_type: String = str(card_data.get("target", "none")).to_lower()
	var targets: Array = []

	match target_type:
		"self", "none", "":
			# No targets needed
			pass
		"enemy":
			# Target the attacker if this is a damage response
			var attacker_id: String = context.get("attacker", "")
			if not attacker_id.is_empty():
				targets.append(attacker_id)
			else:
				# Default to nearest enemy
				var opp_id: int = 1 if caster.owner_id == 2 else 2
				var enemies := state.get_living_champions(opp_id)
				if not enemies.is_empty():
					targets.append(enemies[0].unique_id)
		"ally", "friendly", "allyorself":
			# Target self or the damaged champion
			var target_id: String = context.get("target", "")
			if not target_id.is_empty():
				targets.append(target_id)
			else:
				targets.append(caster.unique_id)
		"champion":
			# Context-dependent - usually the target of the trigger
			var target_id: String = context.get("target", "")
			if not target_id.is_empty():
				targets.append(target_id)
			else:
				var attacker_id: String = context.get("attacker", "")
				if not attacker_id.is_empty():
					targets.append(attacker_id)

	return targets


func _end_current_turn() -> void:
	"""End the current turn and start the next."""
	var state := game_controller.game_state
	var current_player := state.active_player

	# Fire endTurn trigger before turn cleanup
	_fire_trigger("endTurn", {"player": current_player})

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

	# Process bonusMana buffs (Pick Pocket) - grant extra mana at turn start
	for champ: ChampionState in state.get_champions(next_player):
		if champ.is_alive() and champ.has_buff("bonusMana"):
			var bonus := champ.get_buff_stacks("bonusMana")
			state.add_mana(next_player, bonus)
			_debug("    [MANA] %s grants %d bonus mana to P%d" % [champ.champion_name, bonus, next_player])

	for champ: ChampionState in state.get_champions(next_player):
		champ.reset_turn()

	# Draw card and track it
	if state.get_hand(next_player).size() < 10:
		var drawn := state.draw_card(next_player)
		if not drawn.is_empty():
			current_result.record_card_drawn(drawn)
			# Fire onDraw trigger
			_fire_trigger("onDraw", {
				"player": next_player,
				"card": drawn
			})


func _determine_winner_by_hp(state: GameState) -> void:
	"""Determine winner by total HP when round limit reached, with tiebreakers."""
	var p1_hp := 0
	var p2_hp := 0
	var p1_alive := 0
	var p2_alive := 0

	for champ: ChampionState in state.get_champions(1):
		p1_hp += maxi(0, champ.current_hp)
		if champ.is_alive():
			p1_alive += 1
	for champ: ChampionState in state.get_champions(2):
		p2_hp += maxi(0, champ.current_hp)
		if champ.is_alive():
			p2_alive += 1

	# Primary: Total HP
	if p1_hp > p2_hp:
		current_result.winner = 1
		current_result.win_reason = "round_limit_hp_advantage"
	elif p2_hp > p1_hp:
		current_result.winner = 2
		current_result.win_reason = "round_limit_hp_advantage"
	# Tiebreaker 1: Champions alive
	elif p1_alive > p2_alive:
		current_result.winner = 1
		current_result.win_reason = "round_limit_champions_alive"
	elif p2_alive > p1_alive:
		current_result.winner = 2
		current_result.win_reason = "round_limit_champions_alive"
	# Tiebreaker 2: Random (coin flip to avoid draws)
	else:
		current_result.winner = 1 if randf() < 0.5 else 2
		current_result.win_reason = "round_limit_coin_flip"
		_debug("  [TIEBREAKER] HP and champions equal, coin flip winner: P%d" % current_result.winner)

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


func _make_action_key(action: Dictionary) -> String:
	"""Create a unique key for an action to track failed attempts."""
	var action_type: String = action.get("type", "")
	var champion: String = action.get("champion", "")
	var target = action.get("target", "")
	var card: String = action.get("card", "")

	match action_type:
		"move":
			return "move_%s_%s" % [champion, str(target)]
		"attack":
			return "attack_%s_%s" % [champion, str(target)]
		"cast":
			return "cast_%s_%s_%s" % [champion, card, str(action.get("targets", []))]
		_:
			return "%s_%s" % [action_type, champion]


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


func _on_immediate_movement_required(champion_ids: Array, _movement_bonus: int) -> void:
	"""Handle immediate movement for AI - auto-resolve movement decisions."""
	_debug("  [DEBUG] Immediate movement required for %d champions" % champion_ids.size())

	var state := game_controller.game_state
	if state == null:
		return

	# Check if there's a pending attack — if so, move away from attacker (dodge)
	var attacker_id: String = game_controller._pending_action.get("attacker_id", "")
	var attacker: ChampionState = state.get_champion(attacker_id) if not attacker_id.is_empty() else null

	for champ_id in champion_ids:
		var champ := state.get_champion(str(champ_id))
		if champ == null or not champ.is_alive():
			continue

		# AI auto-moves: find best movement position
		var ai := ai_player1 if champ.owner_id == 1 else ai_player2
		if ai == null:
			continue

		# Get valid move targets and pick the best one
		var pathfinder := Pathfinder.new(state)
		var reachable := pathfinder.get_reachable_tiles(champ)

		if reachable.is_empty():
			_debug("    [MOVE] %s has no reachable tiles" % champ.champion_name)
			continue

		var best_pos: Vector2i = champ.position

		if attacker:
			# Dodge: move to tile furthest from attacker
			var best_dist: int = 0
			for tile: Vector2i in reachable:
				var dist: int = absi(tile.x - attacker.position.x) + absi(tile.y - attacker.position.y)
				if dist > best_dist:
					best_dist = dist
					best_pos = tile
		else:
			# No attacker context — move toward nearest enemy
			var opp_id: int = 1 if champ.owner_id == 2 else 2
			var enemies := state.get_living_champions(opp_id)
			var best_dist: int = 999
			for tile: Vector2i in reachable:
				for enemy: ChampionState in enemies:
					var dist: int = absi(tile.x - enemy.position.x) + absi(tile.y - enemy.position.y)
					if dist < best_dist:
						best_dist = dist
						best_pos = tile

		# Execute the move
		if best_pos != champ.position:
			var old_pos: Vector2i = champ.position
			champ.position = best_pos
			champ.has_moved = true
			_debug("    [MOVE] %s moved from %s to %s" % [champ.champion_name, old_pos, best_pos])

			# Emit movement signal for effect tracking
			if game_controller.effect_processor != null:
				game_controller.effect_processor.champion_moved.emit(champ.unique_id, old_pos, best_pos)

	# Resolve the pending attack/cast after all movements complete
	# Use call_deferred to avoid resolving during the trigger call stack
	game_controller.call_deferred("resolve_immediate_movement")


func _on_discard_selection_required(player_id: int, _caster_id: String, _damage_per_card: int) -> void:
	"""Handle discard selection for AI - auto-select cards to discard."""
	_debug("  [DEBUG] Discard selection required for P%d" % player_id)

	var state := game_controller.game_state
	if state == null:
		return

	var hand := state.get_hand(player_id)
	if hand.is_empty():
		# No cards to discard - pass empty typed array
		var empty_cards: Array[String] = []
		game_controller.effect_processor.complete_discard_selection(empty_cards)
		return

	# AI strategy: discard cards based on value
	# For damage cards, discard more cards = more damage, so discard lower-value cards
	var cards_to_discard: Array[String] = []

	# Simple AI: discard up to 3 low-cost cards for damage
	var sorted_hand := hand.duplicate()
	sorted_hand.sort_custom(func(a: String, b: String) -> bool:
		var cost_a: int = CardDatabase.get_card(a).get("cost", 0)
		var cost_b: int = CardDatabase.get_card(b).get("cost", 0)
		return cost_a < cost_b  # Lower cost first
	)

	# Discard up to 3 cards (or fewer if hand is small)
	var max_discard := mini(3, sorted_hand.size())
	for i in range(max_discard):
		cards_to_discard.append(sorted_hand[i])

	_debug("    [DISCARD] AI P%d discarding %d cards: %s" % [player_id, cards_to_discard.size(), cards_to_discard])

	# Complete the discard selection
	game_controller.effect_processor.complete_discard_selection(cards_to_discard)


func _on_cards_drawn(player_id: int, count: int, is_extra: bool) -> void:
	"""Handle cards drawn signal - fire onDraw trigger for Hypocrite, etc."""
	if not is_extra:
		return  # Only trigger on extra card draws (from effects), not start-of-turn draws

	_debug("  [DEBUG] Extra cards drawn: P%d drew %d cards" % [player_id, count])

	# Fire onDraw trigger with context that includes who drew and how many
	# Hypocrite (Confessor) triggers when OPPONENT draws extra cards
	_fire_trigger("onDraw", {
		"player": player_id,
		"count": count,
		"is_extra": true
	})


func _on_intel_choice_required(player_id: int, _own_card: String, _opp_card: String) -> void:
	"""Handle Intel card choice for AI - auto-resolve."""
	_debug("  [DEBUG] Intel choice required for P%d" % player_id)
	var ai := ai_player1 if player_id == 1 else ai_player2
	if ai and ai.has_method("evaluate_intel_choice"):
		var choices: Dictionary = ai.evaluate_intel_choice(_own_card, _opp_card)
		game_controller.effect_processor.complete_intel_choice(
			choices.get("own_to_bottom", false),
			choices.get("opp_to_bottom", false)
		)
	else:
		# Default: keep both on top
		game_controller.effect_processor.complete_intel_choice(false, false)


func _on_x_value_required(player_id: int, _card_name: String, _min_val: int, max_val: int) -> void:
	"""Handle X-value selection for AI - spend as much as possible."""
	_debug("  [DEBUG] X-value choice required for P%d (max=%d)" % [player_id, max_val])
	# AI strategy: spend all available mana on X for maximum disruption
	game_controller.effect_processor.complete_x_selection(max_val)


func _on_discard_choice_required(player_id: int, count: int) -> void:
	"""Handle discard choice for AI (Introspection) - discard lowest value cards."""
	_debug("  [DEBUG] Discard choice required for P%d (count=%d)" % [player_id, count])
	var state := game_controller.game_state
	var hand := state.get_hand(player_id)

	# Sort by cost ascending, pick lowest value cards
	var sorted_hand := hand.duplicate()
	sorted_hand.sort_custom(func(a: String, b: String) -> bool:
		var cost_a: int = CardDatabase.get_card(a).get("cost", 0)
		var cost_b: int = CardDatabase.get_card(b).get("cost", 0)
		return cost_a < cost_b
	)

	var to_discard: Array[String] = []
	for i in range(mini(count, sorted_hand.size())):
		to_discard.append(sorted_hand[i])

	_debug("    [DISCARD] AI P%d choosing to discard: %s" % [player_id, to_discard])
	game_controller.effect_processor.complete_discard_choice(to_discard)


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


func _is_heal_card(card_data: Dictionary) -> bool:
	"""Check if a card is primarily a heal card."""
	var effects: Array = card_data.get("effect", [])
	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		if etype == "heal":
			return true
	return false


func _would_heal_have_effect_now(card_data: Dictionary, caster: ChampionState, targets: Array, state: GameState) -> bool:
	"""Check if a heal card would have effect given current state (called after triggers)."""
	if caster == null:
		return false

	var effects: Array = card_data.get("effect", [])
	var target_type: String = str(card_data.get("target", "")).to_lower()
	var scope: String = ""
	var card_range: String = str(card_data.get("range", ""))

	for effect: Dictionary in effects:
		var etype: String = str(effect.get("type", "")).to_lower()
		if etype == "heal":
			scope = str(effect.get("scope", "target")).to_lower()
			break

	# Position-targeted AOE heals (like Healing Rain)
	if target_type == "position" and card_range == "AOE":
		var aoe_radius: int = card_data.get("aoeRadius", 1)
		if targets.is_empty():
			return false
		var target_str: String = str(targets[0])
		var parts := target_str.split(",")
		if parts.size() != 2:
			return false
		var target_pos := Vector2i(int(parts[0]), int(parts[1]))

		# Check if any champion in AOE needs healing
		for champ: ChampionState in state.get_all_champions():
			if champ.is_alive():
				var dist: int = maxi(absi(champ.position.x - target_pos.x), absi(champ.position.y - target_pos.y))
				if dist <= aoe_radius and champ.current_hp < champ.max_hp:
					return true  # At least one champion needs healing
		return false

	# Self-targeted heals
	if target_type == "self" or target_type == "none" or target_type == "":
		if scope == "friendlies" or scope == "allies":
			# AOE heal to all friendlies
			for ally: ChampionState in state.get_living_champions(caster.owner_id):
				if ally.current_hp < ally.max_hp:
					return true
			return false
		else:
			# Self heal
			return caster.current_hp < caster.max_hp

	# Friendly/ally targeted heals
	if target_type == "friendly" or target_type == "ally" or target_type == "allyorself":
		if targets.is_empty():
			return false
		var target := state.get_champion(str(targets[0]))
		if target == null:
			return false
		return target.current_hp < target.max_hp

	# Champion-targeted heals (could be anyone)
	if target_type == "champion" or target_type == "any":
		if targets.is_empty():
			return false
		var target := state.get_champion(str(targets[0]))
		if target == null:
			return false
		return target.current_hp < target.max_hp

	# Unknown target type - assume it would have effect
	return true
