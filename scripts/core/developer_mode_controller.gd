class_name DeveloperModeController
extends RefCounted
## DeveloperModeController - Manages step-through control flow for AI execution
## Allows pausing between AI actions for debugging/analysis

signal action_ready(action_data: Dictionary)  # AI has chosen an action, waiting to execute
signal waiting_for_input()  # Paused, waiting for user to step or execute all
signal action_executed(action_data: Dictionary)  # Action was executed
signal turn_completed(player_id: int)  # AI turn finished

enum StepMode {
	PAUSED,       # Waiting for user input
	STEP_ONE,     # Execute one action then pause
	EXECUTE_ALL   # Run until turn ends
}

var current_mode: StepMode = StepMode.PAUSED
var is_waiting: bool = false
var pending_action: Dictionary = {}
var current_player_id: int = 0

# Track actions for the current turn
var actions_this_turn: Array[Dictionary] = []


func reset_for_new_turn(player_id: int) -> void:
	"""Reset state at the start of a new AI turn."""
	current_mode = StepMode.PAUSED
	is_waiting = false
	pending_action = {}
	current_player_id = player_id
	actions_this_turn.clear()


func set_pending_action(action_data: Dictionary) -> void:
	"""Called when AI has chosen an action but hasn't executed it yet."""
	pending_action = action_data
	actions_this_turn.append(action_data)
	action_ready.emit(action_data)

	# If not in execute all mode, pause and wait
	if current_mode != StepMode.EXECUTE_ALL:
		is_waiting = true
		waiting_for_input.emit()


func should_wait_for_input() -> bool:
	"""Check if we should wait for user input before executing."""
	return current_mode == StepMode.PAUSED and is_waiting


func request_step() -> void:
	"""User pressed 'Step' button - execute one action then pause."""
	current_mode = StepMode.STEP_ONE
	is_waiting = false


func request_execute_all() -> void:
	"""User pressed 'Execute All' button - run remaining turn without pausing."""
	current_mode = StepMode.EXECUTE_ALL
	is_waiting = false


func on_action_executed() -> void:
	"""Called after an action has been executed."""
	action_executed.emit(pending_action)
	pending_action = {}

	# If in step mode, go back to paused
	if current_mode == StepMode.STEP_ONE:
		current_mode = StepMode.PAUSED


func on_turn_completed() -> void:
	"""Called when the AI turn is complete."""
	turn_completed.emit(current_player_id)
	current_mode = StepMode.PAUSED
	is_waiting = false


func is_execute_all_mode() -> bool:
	"""Check if we're in execute all mode (no pausing)."""
	return current_mode == StepMode.EXECUTE_ALL


func get_actions_this_turn() -> Array[Dictionary]:
	"""Get all actions taken this turn."""
	return actions_this_turn


func get_status_text() -> String:
	"""Get human-readable status for UI display."""
	match current_mode:
		StepMode.PAUSED:
			if is_waiting:
				return "Waiting for input..."
			return "Paused"
		StepMode.STEP_ONE:
			return "Stepping..."
		StepMode.EXECUTE_ALL:
			return "Executing turn..."
	return "Unknown"
