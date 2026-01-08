extends Node
## GameManager - Central coordinator for all game systems
## Manages game state, turn flow, and coordinates between systems

# Game States (renamed to avoid conflict with ManagerState class)
enum ManagerState {
	NONE,
	MAIN_MENU,
	CHARACTER_SELECT,
	GAME_OPTIONS,
	LOADING,
	PLAYING,
	PAUSED,
	GAME_OVER
}

# Turn Phases
enum TurnPhase {
	START,      # Reset mana, reset flags, draw card
	ACTION,     # Player can move/attack/cast
	RESPONSE,   # Response window active
	END         # Discard to 7, clear thisTurn buffs, check win
}

# Player IDs
const PLAYER_1 := 1
const PLAYER_2 := 2

# Current state
var current_state: ManagerState = ManagerState.NONE
var previous_state: ManagerState = ManagerState.NONE

# Game settings
var ai_enabled: bool = true
var ai_difficulty: String = "Medium"  # Easy, Medium, Hard
var is_network_game: bool = false

# Turn tracking
var current_player: int = PLAYER_1
var current_phase: TurnPhase = TurnPhase.START
var round_number: int = 0

# Champion selections
var player1_champions: Array[String] = []
var player2_champions: Array[String] = []

# Active game state reference (set when game starts)
var game_state = null  # Will be ManagerState class instance

# Signals
signal state_changed(old_state: ManagerState, new_state: ManagerState)
signal game_ready()
signal loading_progress(percent: float)


func _ready() -> void:
	_connect_signals()


func _connect_signals() -> void:
	# Connect to EventBus signals we need to handle
	EventBus.game_ended.connect(_on_game_ended)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.turn_ended.connect(_on_turn_ended)


# --- State Management ---

func change_state(new_state: ManagerState) -> void:
	if new_state == current_state:
		return

	previous_state = current_state
	current_state = new_state

	_handle_state_exit(previous_state)
	_handle_state_enter(new_state)

	state_changed.emit(previous_state, new_state)


func _handle_state_exit(state: ManagerState) -> void:
	match state:
		ManagerState.PLAYING:
			# Cleanup game resources if needed
			pass
		ManagerState.PAUSED:
			# Resume any paused systems
			pass


func _handle_state_enter(state: ManagerState) -> void:
	match state:
		ManagerState.MAIN_MENU:
			_load_main_menu()
		ManagerState.CHARACTER_SELECT:
			_load_character_select()
		ManagerState.LOADING:
			_start_game_loading()
		ManagerState.PLAYING:
			_start_gameplay()
		ManagerState.PAUSED:
			get_tree().paused = true
		ManagerState.GAME_OVER:
			_show_game_over()


func _load_main_menu() -> void:
	# Will load main menu scene
	pass


func _load_character_select() -> void:
	# Will load character selection scene
	pass


func _start_game_loading() -> void:
	# Load game scene and initialize
	loading_progress.emit(0.0)
	# Actual loading logic will be implemented with scene loading
	loading_progress.emit(1.0)
	change_state(ManagerState.PLAYING)


func _start_gameplay() -> void:
	get_tree().paused = false
	game_ready.emit()


func _show_game_over() -> void:
	# Will show game over screen
	pass


# --- Game Control ---

func start_new_game(p1_champions: Array[String], p2_champions: Array[String]) -> void:
	player1_champions = p1_champions
	player2_champions = p2_champions
	round_number = 0
	current_player = PLAYER_1
	current_phase = TurnPhase.START

	change_state(ManagerState.LOADING)


func pause_game() -> void:
	if current_state == ManagerState.PLAYING:
		change_state(ManagerState.PAUSED)


func resume_game() -> void:
	if current_state == ManagerState.PAUSED:
		change_state(ManagerState.PLAYING)
		get_tree().paused = false


func forfeit_game(player_id: int) -> void:
	var winner := PLAYER_2 if player_id == PLAYER_1 else PLAYER_1
	EventBus.game_ended.emit(winner, "Forfeit")


func return_to_menu() -> void:
	change_state(ManagerState.MAIN_MENU)


# --- Turn Management ---

func start_turn(player_id: int) -> void:
	current_player = player_id
	current_phase = TurnPhase.START

	if player_id == PLAYER_1:
		round_number += 1

	EventBus.turn_started.emit(player_id, round_number)
	EventBus.phase_changed.emit("START")


func advance_phase() -> void:
	match current_phase:
		TurnPhase.START:
			current_phase = TurnPhase.ACTION
			EventBus.phase_changed.emit("ACTION")
		TurnPhase.ACTION:
			current_phase = TurnPhase.END
			EventBus.phase_changed.emit("END")
		TurnPhase.END:
			_end_current_turn()


func enter_response_phase() -> void:
	current_phase = TurnPhase.RESPONSE
	EventBus.phase_changed.emit("RESPONSE")


func exit_response_phase() -> void:
	current_phase = TurnPhase.ACTION
	EventBus.phase_changed.emit("ACTION")


func _end_current_turn() -> void:
	EventBus.turn_ended.emit(current_player)

	# Switch to other player
	var next_player := PLAYER_2 if current_player == PLAYER_1 else PLAYER_1
	start_turn(next_player)


func end_turn() -> void:
	"""Called when player clicks 'End Turn' button."""
	if current_phase == TurnPhase.ACTION:
		advance_phase()  # Go to END phase
		advance_phase()  # Process END and start next turn


func is_current_player(player_id: int) -> bool:
	return current_player == player_id


func is_player_turn(player_id: int) -> bool:
	return current_player == player_id and current_phase == TurnPhase.ACTION


# --- AI Configuration ---

func set_ai_difficulty(difficulty: String) -> void:
	ai_difficulty = difficulty


func enable_ai(enabled: bool) -> void:
	ai_enabled = enabled


func is_ai_controlled(player_id: int) -> bool:
	# In single player, player 2 is AI
	return ai_enabled and player_id == PLAYER_2 and not is_network_game


# --- Signal Handlers ---

func _on_game_ended(winner: int, _reason: String) -> void:
	change_state(ManagerState.GAME_OVER)


func _on_turn_started(_player_id: int, _round: int) -> void:
	# Could trigger AI thinking here
	pass


func _on_turn_ended(_player_id: int) -> void:
	pass


# --- Utility ---

func get_opponent(player_id: int) -> int:
	return PLAYER_2 if player_id == PLAYER_1 else PLAYER_1


func get_current_phase_name() -> String:
	match current_phase:
		TurnPhase.START:
			return "START"
		TurnPhase.ACTION:
			return "ACTION"
		TurnPhase.RESPONSE:
			return "RESPONSE"
		TurnPhase.END:
			return "END"
	return "UNKNOWN"
