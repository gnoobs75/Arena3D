extends Node3D
class_name GameScene3D
## GameScene3D - Main 3D game scene using the Battle Chess-style board
## Drop-in replacement for GameScene that uses 3D visuals

const HUD_SCENE := preload("res://scenes/game/game_hud.tscn")
const HAND_SCENE := preload("res://scenes/game/cards/hand.tscn")

# === 3D COMPONENTS ===
var board_3d: Board3D
var board_3d_manager: Board3DManager
var vfx_library: VFXLibrary
var choreographer: CombatChoreographer

# === 2D UI (overlaid on 3D) ===
var hud: GameHUD
var hand_ui: HandUI
var response_slot: ResponseSlot

# === GAME SYSTEMS ===
var game_controller: GameController
var ai_controller: AIController

# === INPUT STATE ===
enum InputMode {
	NONE,
	SELECT_CHAMPION,
	SELECT_MOVE,
	SELECT_ATTACK_TARGET,
	SELECT_CAST_TARGET,
	SELECT_DIRECTION,
	SELECT_POSITION,
	IMMEDIATE_MOVE,
	SELECT_DISCARD
}

var input_mode: InputMode = InputMode.SELECT_CHAMPION
var selected_champion_id: String = ""
var selected_card: String = ""
var is_player_turn: bool = true
var ai_vs_ai_mode: bool = false


func _ready() -> void:
	ai_vs_ai_mode = get_meta("ai_vs_ai", false)
	_setup_scene()
	_start_game()


func _setup_scene() -> void:
	"""Create and configure all game elements."""
	# Create 3D board
	board_3d = Board3D.new()
	add_child(board_3d)

	# Wait for board initialization
	await get_tree().process_frame

	# Set up Board3DManager to bridge EventBus
	board_3d_manager = Board3DManager.new()
	add_child(board_3d_manager)
	board_3d_manager.set_board(board_3d)

	# Set up VFX library
	var vfx_container: Node = board_3d.get_node_or_null("VFX")
	if vfx_container:
		vfx_library = VFXLibrary.new(vfx_container)
		board_3d_manager.vfx_library = vfx_library

	# Set up combat choreographer
	choreographer = CombatChoreographer.new(board_3d)
	board_3d_manager.choreographer = choreographer

	# Connect board signals
	board_3d.tile_clicked.connect(_on_tile_clicked)
	board_3d.champion_clicked.connect(_on_champion_clicked)
	board_3d.tile_hovered.connect(_on_tile_hovered)
	board_3d.tile_unhovered.connect(_on_tile_unhovered)

	# Create 2D HUD overlay
	_setup_hud()


func _setup_hud() -> void:
	"""Set up 2D UI elements overlaid on 3D scene."""
	# HUD is a CanvasLayer so it renders over 3D
	hud = HUD_SCENE.instantiate()
	add_child(hud)

	# Connect HUD signals
	hud.end_turn_pressed.connect(_on_end_turn_pressed)
	hud.undo_pressed.connect(_on_undo_pressed)
	hud.pass_priority_pressed.connect(_on_pass_priority_pressed)

	# Hand UI
	hand_ui = HAND_SCENE.instantiate()
	hud.add_child(hand_ui)

	hand_ui.card_selected.connect(_on_card_selected)
	hand_ui.card_deselected.connect(_on_card_deselected)

	# Response slot
	response_slot = ResponseSlot.new()
	response_slot.position = Vector2(100, 700)
	add_child(response_slot)


func _start_game() -> void:
	"""Initialize and start a new game."""
	# Get champion selections from metadata (set by character select screen)
	var p1_champions: Array[String] = []
	var p2_champions: Array[String] = []

	var p1_meta = get_meta("p1_champions", null)
	var p2_meta = get_meta("p2_champions", null)

	# Convert metadata arrays to typed arrays
	if p1_meta != null and p1_meta is Array:
		for name in p1_meta:
			p1_champions.append(str(name))
	else:
		# Default fallback
		p1_champions = ["Brute", "Ranger"]

	if p2_meta != null and p2_meta is Array:
		for name in p2_meta:
			p2_champions.append(str(name))
	else:
		# Default fallback
		p2_champions = ["Berserker", "Shaman"]

	print("GameScene3D: Starting with P1 champions: %s, P2 champions: %s" % [p1_champions, p2_champions])

	# Initialize game controller
	game_controller = GameController.new()
	game_controller.initialize(p1_champions, p2_champions)

	# Initialize board manager with game state
	board_3d_manager.initialize(game_controller.game_state)

	# Set up terrain
	board_3d.set_terrain(game_controller.game_state.board_terrain)

	# Add champions to 3D board
	for player_id in [1, 2]:
		for champion in game_controller.game_state.get_champions(player_id):
			board_3d.add_champion(
				champion.unique_id,
				champion.position,
				champion.champion_name,
				champion.owner_id
			)

	# Connect game controller signals
	game_controller.action_performed.connect(_on_action_performed)
	game_controller.turn_ended.connect(_on_turn_ended)
	game_controller.game_over.connect(_on_game_over)

	# Set up AI
	if ai_vs_ai_mode:
		_setup_ai_vs_ai()
	else:
		ai_controller = AIController.new(game_controller, 2)
		ai_controller.set_difficulty(AIController.Difficulty.MEDIUM)

	# Update UI
	_update_ui()

	# Start first turn
	game_controller.start_turn()


func _setup_ai_vs_ai() -> void:
	"""Set up AI for both players."""
	# AI for player 2
	ai_controller = AIController.new(game_controller, 2)
	ai_controller.set_difficulty(AIController.Difficulty.HARD)


# === INPUT HANDLERS ===

func _on_tile_clicked(grid_pos: Vector2i) -> void:
	"""Handle tile click on 3D board."""
	match input_mode:
		InputMode.SELECT_MOVE:
			_try_move(grid_pos)
		InputMode.SELECT_CAST_TARGET, InputMode.SELECT_POSITION:
			_try_cast_at_position(grid_pos)
		_:
			_deselect_all()


func _on_champion_clicked(champion_id: String) -> void:
	"""Handle champion click on 3D board."""
	var champion: ChampionState = game_controller.game_state.get_champion(champion_id)
	if not champion:
		return

	match input_mode:
		InputMode.SELECT_CHAMPION:
			if champion.owner_id == 1:  # Player's champion
				_select_champion(champion_id)
		InputMode.SELECT_ATTACK_TARGET:
			if champion.owner_id != 1:  # Enemy champion
				_try_attack(champion_id)
		InputMode.SELECT_CAST_TARGET:
			_try_cast_at_champion(champion_id)
		_:
			if champion.owner_id == 1:
				_select_champion(champion_id)


func _on_tile_hovered(grid_pos: Vector2i) -> void:
	"""Handle tile hover."""
	board_3d.set_highlight(grid_pos, Board3D.HighlightType.HOVER)


func _on_tile_unhovered(grid_pos: Vector2i) -> void:
	"""Handle tile unhover."""
	board_3d.set_highlight(grid_pos, Board3D.HighlightType.NONE)


# === CHAMPION SELECTION ===

func _select_champion(champion_id: String) -> void:
	"""Select a champion and show valid actions."""
	_deselect_all()
	selected_champion_id = champion_id

	# Highlight selected champion
	board_3d.set_champion_selected(champion_id, true)

	var champion: ChampionState = game_controller.game_state.get_champion(champion_id)
	if not champion:
		return

	# Show valid move positions
	var valid_moves: Array[Vector2i] = game_controller.get_valid_moves(champion_id)
	var move_positions: Array = []
	for pos in valid_moves:
		move_positions.append(pos)
	board_3d.set_highlights(move_positions, Board3D.HighlightType.MOVE)

	# Show valid attack targets
	var valid_attacks: Array[String] = game_controller.get_valid_attack_targets(champion_id)
	for target_id in valid_attacks:
		var target: ChampionState = game_controller.game_state.get_champion(target_id)
		if target:
			board_3d.set_highlight(target.position, Board3D.HighlightType.ATTACK)

	input_mode = InputMode.SELECT_MOVE


func _deselect_all() -> void:
	"""Clear all selections and highlights."""
	if selected_champion_id != "":
		board_3d.set_champion_selected(selected_champion_id, false)
	selected_champion_id = ""
	selected_card = ""
	board_3d.clear_highlights()
	input_mode = InputMode.SELECT_CHAMPION


# === ACTIONS ===

func _try_move(grid_pos: Vector2i) -> void:
	"""Attempt to move selected champion to position."""
	if selected_champion_id == "":
		return

	var result: Dictionary = game_controller.move_champion(selected_champion_id, grid_pos)
	if result.success:
		# Animation handled by Board3DManager via EventBus
		await get_tree().create_timer(0.5).timeout
		_update_ui()
	else:
		print("Move failed: ", result.get("error", "unknown"))

	_deselect_all()


func _try_attack(target_id: String) -> void:
	"""Attempt to attack target champion."""
	if selected_champion_id == "":
		return

	var result: Dictionary = game_controller.attack_champion(selected_champion_id, target_id)
	if result.success:
		# Combat choreography handled by Board3DManager
		await get_tree().create_timer(1.0).timeout
		_update_ui()
	else:
		print("Attack failed: ", result.get("error", "unknown"))

	_deselect_all()


func _try_cast_at_position(grid_pos: Vector2i) -> void:
	"""Cast selected card at position."""
	# Implementation depends on card targeting
	_deselect_all()


func _try_cast_at_champion(champion_id: String) -> void:
	"""Cast selected card at champion."""
	# Implementation depends on card targeting
	_deselect_all()


# === UI HANDLERS ===

func _on_card_selected(card_id: String) -> void:
	"""Handle card selection from hand."""
	selected_card = card_id
	# Show valid targets based on card
	input_mode = InputMode.SELECT_CAST_TARGET


func _on_card_deselected() -> void:
	"""Handle card deselection."""
	selected_card = ""
	input_mode = InputMode.SELECT_CHAMPION


func _on_end_turn_pressed() -> void:
	"""Handle end turn button."""
	game_controller.end_turn()


func _on_undo_pressed() -> void:
	"""Handle undo button."""
	# Not implemented for 3D yet
	pass


func _on_pass_priority_pressed() -> void:
	"""Handle pass priority button."""
	# For response windows
	pass


# === GAME EVENTS ===

func _on_action_performed(action: Dictionary) -> void:
	"""Handle action performed - animations are handled by Board3DManager."""
	_update_ui()


func _on_turn_ended(player_id: int) -> void:
	"""Handle turn end."""
	is_player_turn = (game_controller.current_player == 1)

	if not is_player_turn and ai_controller:
		# AI's turn
		await get_tree().create_timer(0.5).timeout
		ai_controller.take_turn()


func _on_game_over(winner: int, reason: String) -> void:
	"""Handle game over."""
	print("Game Over! Winner: Player ", winner, " Reason: ", reason)
	# Show game over UI


func _update_ui() -> void:
	"""Update all UI elements."""
	if hud:
		hud.update_display()
	if hand_ui:
		var state := game_controller.game_state
		var hand := state.get_hand(1)
		var mana := state.get_mana(1)
		hand_ui.update_hand(hand, mana)
