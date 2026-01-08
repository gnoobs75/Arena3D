class_name TurnManager
extends RefCounted
## TurnManager - Controls turn flow and phase transitions
## Phases: START → ACTION → END (with RESPONSE interrupts)

signal phase_changed(phase: String)
signal turn_started(player_id: int, round_number: int)
signal turn_ended(player_id: int)
signal response_window_opened(trigger: String, context: Dictionary)
signal response_window_closed()

enum Phase {
	START,      # Reset mana, reset flags, draw card
	ACTION,     # Player can move/attack/cast
	RESPONSE,   # Response window active
	END         # Discard to 7, clear thisTurn buffs, check win
}

var game_state: GameState
var current_phase: Phase = Phase.START
var response_trigger: String = ""
var consecutive_passes: int = 0

# Track who has priority for responses
var priority_player: int = 1


func _init(state: GameState) -> void:
	game_state = state


func start_game() -> void:
	"""Begin the game with player 1's first turn."""
	game_state.round_number = 1
	start_turn(1)


func start_turn(player_id: int) -> void:
	"""Begin a player's turn."""
	game_state.active_player = player_id

	# If it's player 1's turn and not round 1, increment round
	if player_id == 1 and game_state.round_number > 0:
		game_state.round_number += 1

	_enter_phase(Phase.START)

	# Execute START phase
	_execute_start_phase()

	# NOTE: startTurn response triggers are handled by GameController._on_turn_started
	# The ResponseStack system handles response windows, not TurnManager

	# Move to ACTION phase
	_enter_phase(Phase.ACTION)

	# Emit turn_started after we're in ACTION phase so UI is ready
	turn_started.emit(player_id, game_state.round_number)


func _execute_start_phase() -> void:
	"""Handle START phase logic."""
	var player_id := game_state.active_player

	# Reset mana to 5
	game_state.reset_mana(player_id)

	# Reset champion action flags
	for champion: ChampionState in game_state.get_champions(player_id):
		champion.reset_turn()

	# Draw 1 card
	var _drawn := game_state.draw_card(player_id)
	# NOTE: onDraw response triggers would be handled by GameController if needed
	# The ResponseStack system handles response windows, not TurnManager


func end_turn() -> void:
	"""Called when active player ends their turn."""
	print("TurnManager.end_turn() called, current_phase=%s" % Phase.keys()[current_phase])
	if current_phase != Phase.ACTION:
		push_warning("TurnManager: Cannot end turn during %s phase" % Phase.keys()[current_phase])
		return

	print("  Entering END phase")
	_enter_phase(Phase.END)
	_execute_end_phase()


func _execute_end_phase() -> void:
	"""Handle END phase logic."""
	var player_id := game_state.active_player

	# Discard down to hand limit (7)
	_enforce_hand_limit(player_id)

	# Clear thisTurn effects
	for champion: ChampionState in game_state.get_champions(player_id):
		champion.clear_this_turn_effects()

	# Clear temporary terrain (Pit of Despair pits, etc.)
	game_state.clear_temporary_terrain()

	# NOTE: endTurn response triggers are handled by GameController before calling this
	# The ResponseStack system handles response windows, not TurnManager

	_finish_end_phase()


func _finish_end_phase() -> void:
	"""Complete end phase and start next turn."""
	var player_id := game_state.active_player
	print("TurnManager._finish_end_phase() called for player %d" % player_id)

	# Check win condition
	game_state.check_win_condition()
	if game_state.game_over:
		print("  Game over, not starting next turn")
		return

	turn_ended.emit(player_id)

	# Switch to other player
	var next_player := 2 if player_id == 1 else 1
	print("  Starting turn for player %d" % next_player)
	start_turn(next_player)


func _enforce_hand_limit(player_id: int) -> void:
	"""Discard down to 7 cards."""
	var hand := game_state.get_hand(player_id)
	while hand.size() > 7:
		# For AI, would choose worst card
		# For now, discard last card
		var card_name: String = hand.pop_back()
		game_state.get_discard(player_id).append(card_name)


func _enter_phase(phase: Phase) -> void:
	"""Transition to a new phase."""
	print("TurnManager: Entering phase %s" % Phase.keys()[phase])
	current_phase = phase
	game_state.current_phase = Phase.keys()[phase]
	phase_changed.emit(Phase.keys()[phase])


# --- Response System ---

func _check_response_trigger(trigger: String, context: Dictionary = {}) -> bool:
	"""Check if any player has response cards for this trigger."""
	response_trigger = trigger
	game_state.response_context = context
	game_state.response_context["trigger"] = trigger

	var has_responses := false

	# Check both players for response cards matching this trigger
	for player_id in [1, 2]:
		var hand := game_state.get_hand(player_id)
		for card_name: String in hand:
			var card_data := CardDatabase.get_card(card_name)
			if card_data.get("type") == "Response":
				var card_trigger: String = card_data.get("trigger", "")
				if card_trigger.to_lower() == trigger.to_lower():
					has_responses = true
					break

	if has_responses:
		open_response_window(trigger, context)
		return true

	return false


func open_response_window(trigger: String, context: Dictionary) -> void:
	"""Open response window for both players."""
	_enter_phase(Phase.RESPONSE)
	game_state.awaiting_response = true
	consecutive_passes = 0

	# Active player gets priority first, then opponent
	priority_player = game_state.active_player

	response_window_opened.emit(trigger, context)


func pass_priority() -> void:
	"""Current priority player passes."""
	consecutive_passes += 1

	if consecutive_passes >= 2:
		# Both players passed, resolve stack
		resolve_response_stack()
	else:
		# Switch priority
		priority_player = 2 if priority_player == 1 else 1


func play_response(player_id: int, card_name: String, targets: Array) -> bool:
	"""Player plays a response card."""
	if player_id != priority_player:
		return false

	# Validate card can be played
	var card_data := CardDatabase.get_card(card_name)
	if card_data.is_empty():
		return false

	var cost: int = card_data.get("cost", 0)
	if game_state.get_mana(player_id) < cost:
		return false

	# Spend mana
	game_state.spend_mana(player_id, cost)

	# Remove from hand
	game_state.play_card(player_id, card_name)

	# Push to response stack
	game_state.push_response(card_name, player_id, targets)

	# Reset pass counter (new response allows more responses)
	consecutive_passes = 0

	# Give opponent priority to respond to this response
	priority_player = 2 if player_id == 1 else 1

	return true


func resolve_response_stack() -> void:
	"""Resolve all responses in LIFO order."""
	while not game_state.response_stack.is_empty():
		var response: Dictionary = game_state.pop_response()
		_resolve_single_response(response)

	close_response_window()


func _resolve_single_response(response: Dictionary) -> void:
	"""Resolve a single response card."""
	var card_name: String = response.get("card_name", "")
	var player_id: int = response.get("player_id", 0)
	var targets: Array = response.get("targets", [])

	# Get card effects and apply them
	# This will be handled by EffectProcessor
	print("TurnManager: Resolving response '%s' by player %d" % [card_name, player_id])

	# Card goes to discard after resolution
	game_state.get_discard(player_id).append(card_name)


func close_response_window() -> void:
	"""Close response window and return to previous phase."""
	game_state.clear_response_stack()
	response_window_closed.emit()

	# NOTE: Response windows are now handled by ResponseStack in GameController
	# This function is kept for backwards compatibility but should not be called
	# Return to ACTION phase as default
	_enter_phase(Phase.ACTION)
	response_trigger = ""


# --- Action Validation ---

func can_perform_action() -> bool:
	"""Check if player can perform actions (in ACTION phase)."""
	return current_phase == Phase.ACTION and not game_state.game_over


func is_response_phase() -> bool:
	return current_phase == Phase.RESPONSE


func get_priority_player() -> int:
	return priority_player
