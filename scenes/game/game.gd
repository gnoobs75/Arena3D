extends Node2D
class_name GameScene
## GameScene - Main game scene coordinating all game elements
## Connects board, UI, and game logic

const BOARD_SCENE := preload("res://scenes/game/board/board.tscn")
const HAND_SCENE := preload("res://scenes/game/cards/hand.tscn")
const HUD_SCENE := preload("res://scenes/game/game_hud.tscn")

# Scene references
var board: GameBoard
var hand_ui: HandUI
var hud: GameHUD

# Game systems
var game_controller: GameController
var ai_controller: AIController

# Input state
enum InputMode {
	NONE,
	SELECT_CHAMPION,
	SELECT_MOVE,
	SELECT_ATTACK_TARGET,
	SELECT_CAST_TARGET,
	SELECT_DIRECTION,
	SELECT_POSITION,
	IMMEDIATE_MOVE  # Player selecting where to move during response
}

var input_mode: InputMode = InputMode.SELECT_CHAMPION
var selected_champion_id: String = ""
var selected_card: String = ""
var is_player_turn: bool = true
var ai_vs_ai_mode: bool = false
var ai_player1: AIController  # AI for player 1 in AI vs AI mode

# Immediate movement state
var _pending_immediate_moves: Array = []  # Champion IDs waiting for movement selection
var _immediate_move_champion_id: String = ""  # Currently selecting move for this champion


func _ready() -> void:
	# Check for AI vs AI mode
	ai_vs_ai_mode = get_meta("ai_vs_ai", false)
	if ai_vs_ai_mode:
		print("GameScene: AI vs AI mode enabled")

	_setup_scene()
	_start_game()


func _unhandled_input(event: InputEvent) -> void:
	# Handle keyboard shortcuts
	if event.is_action_pressed("end_turn"):
		print("Keyboard: End Turn pressed (Enter key)")
		_on_end_turn_pressed()


func _setup_scene() -> void:
	"""Create and position game elements."""
	# Layout constants - must match game_hud.gd
	const MARGIN := 10
	const PANEL_WIDTH := 220
	const TOP_BAR_HEIGHT := 160
	const TURN_INFO_HEIGHT := 90
	const BOARD_WIDTH := 688  # 10*64 tiles + 24*2 coord margins

	# Calculate centered board position
	# Left panel ends at: MARGIN + PANEL_WIDTH = 230
	# Right panel starts at: 1920 - MARGIN - PANEL_WIDTH = 1690
	# Center area: 1460px wide
	# Board X: 230 + (1460 - 688) / 2 = 616
	# Board Y: Below top bar and turn info = 160 + 90 + margin
	board = BOARD_SCENE.instantiate()
	board.position = Vector2(616, TOP_BAR_HEIGHT + TURN_INFO_HEIGHT + MARGIN)
	add_child(board)

	# Connect board signals
	board.tile_clicked.connect(_on_tile_clicked)
	board.champion_clicked.connect(_on_champion_clicked)

	# Connect AnimationController to board for Battle Chess animations
	if AnimationController:
		AnimationController.set_board(board)

	# Create HUD (CanvasLayer for UI elements)
	hud = HUD_SCENE.instantiate()
	add_child(hud)

	# Connect HUD signals
	hud.end_turn_pressed.connect(_on_end_turn_pressed)
	hud.undo_pressed.connect(_on_undo_pressed)
	hud.pass_priority_pressed.connect(_on_pass_priority_pressed)

	# Create hand UI - add to HUD's CanvasLayer so anchors work correctly
	hand_ui = HAND_SCENE.instantiate()
	hud.add_child(hand_ui)  # Add to CanvasLayer, not Node2D

	# Connect hand signals
	hand_ui.card_selected.connect(_on_card_selected)
	hand_ui.card_deselected.connect(_on_card_deselected)


func _start_game() -> void:
	"""Initialize and start a new game."""
	# Default champion selection (will be replaced with selection screen)
	var p1_champions: Array[String] = ["Brute", "Ranger"]
	var p2_champions: Array[String] = ["Berserker", "Shaman"]

	# Initialize game controller
	game_controller = GameController.new()
	game_controller.initialize(p1_champions, p2_champions)

	# Connect game controller signals
	game_controller.turn_started.connect(_on_turn_started)
	game_controller.turn_ended.connect(_on_turn_ended)
	game_controller.action_performed.connect(_on_action_performed)
	game_controller.response_window_opened.connect(_on_response_window_opened)
	game_controller.response_window_closed.connect(_on_response_window_closed)
	game_controller.champion_died.connect(_on_champion_died)
	game_controller.game_ended.connect(_on_game_ended)

	# Connect effect processor signals for immediate movements and combat text
	game_controller.effect_processor.immediate_movement_required.connect(_on_immediate_movement_required)
	game_controller.effect_processor.damage_dealt.connect(_on_damage_dealt)
	game_controller.effect_processor.healing_done.connect(_on_healing_done)

	# Initialize AI for player 2
	ai_controller = AIController.new(game_controller, 2)
	ai_controller.set_difficulty(AIController.Difficulty.MEDIUM)

	# Initialize AI for player 1 if AI vs AI mode
	if ai_vs_ai_mode:
		ai_player1 = AIController.new(game_controller, 1)
		ai_player1.set_difficulty(AIController.Difficulty.MEDIUM)

	# Initialize UI with game state
	var state := game_controller.get_game_state()
	board.initialize(state)
	hud.initialize(state)
	hand_ui.setup(1)

	# Start the game
	game_controller.start_game()


func _on_turn_started(player_id: int, round_number: int) -> void:
	"""Handle turn start."""
	is_player_turn = player_id == 1 and not ai_vs_ai_mode

	_update_ui()
	_reset_input_state()

	if ai_vs_ai_mode:
		# Both players are AI
		var current_ai: AIController = ai_player1 if player_id == 1 else ai_controller
		var ai_name: String = "AI 1 (Blue)" if player_id == 1 else "AI 2 (Red)"
		hud.show_message("%s is thinking..." % ai_name)
		hud.set_action_buttons_enabled(false)
		await get_tree().create_timer(0.8).timeout  # Longer delay for visibility
		await current_ai.take_turn()
	elif not is_player_turn:
		# Player 2 AI turn
		hud.show_message("AI is thinking...")
		hud.set_action_buttons_enabled(false)
		await get_tree().create_timer(0.5).timeout
		await ai_controller.take_turn()
	else:
		hud.show_message("Your turn!")
		hud.set_action_buttons_enabled(true)


func _on_turn_ended(player_id: int) -> void:
	"""Handle turn end."""
	_update_ui()


func _on_action_performed(action: Dictionary) -> void:
	"""Handle action completion."""
	var action_type: String = action.get("action", "")

	match action_type:
		"move":
			var raw_path: Array = action.get("path", [])
			if raw_path.size() > 0:
				var typed_path: Array[Vector2i] = []
				for pos in raw_path:
					if pos is Vector2i:
						typed_path.append(pos)
				if typed_path.size() > 0:
					board.animate_move(action.get("champion", ""), typed_path)
		"attack":
			board.animate_attack(action.get("attacker", ""), action.get("target", ""))

	# Update displays
	await get_tree().create_timer(0.3).timeout
	board.update_champion_positions()
	board.update_champion_hp()
	_update_ui()


func _on_champion_died(champion_id: String) -> void:
	"""Handle champion death."""
	hud.show_message("Champion defeated!")
	board.update_champion_positions()


func _on_damage_dealt(attacker_id: String, target_id: String, amount: int) -> void:
	"""Show floating damage number when damage is dealt."""
	var state := game_controller.get_game_state()
	var target := state.get_champion(target_id)
	if target and amount > 0:
		var screen_pos := board.get_champion_screen_position(target_id)
		if screen_pos != Vector2.ZERO:
			hud.show_damage_number(amount, screen_pos)


func _on_healing_done(source_id: String, target_id: String, amount: int) -> void:
	"""Show floating heal number when healing is done."""
	var state := game_controller.get_game_state()
	var target := state.get_champion(target_id)
	if target and amount > 0:
		var screen_pos := board.get_champion_screen_position(target_id)
		if screen_pos != Vector2.ZERO:
			hud.show_heal_number(amount, screen_pos)


func _on_game_ended(winner: int, reason: String) -> void:
	"""Handle game over."""
	var winner_name := "Player 1" if winner == 1 else "AI"
	hud.show_message("%s wins! %s" % [winner_name, reason], 10.0)
	hud.set_action_buttons_enabled(false)


func _on_response_window_opened(trigger: String, context: Dictionary) -> void:
	"""Handle response window."""
	var priority_player := game_controller.response_stack.get_priority_player()

	if priority_player == 1:
		# Human player gets to respond
		hud.show_response_window(trigger, priority_player)
		hud.show_message("You may respond or pass", 3.0)
	else:
		# AI gets to respond - handle automatically
		_handle_ai_response()


func _on_response_window_closed() -> void:
	"""Handle response window closing."""
	hud.hide_response_window()


# === Input Handling ===

func _on_champion_clicked(champion_id: String) -> void:
	"""Handle clicking on a champion."""
	if not is_player_turn:
		return

	var state := game_controller.get_game_state()
	var champion := state.get_champion(champion_id)

	if champion == null:
		return

	match input_mode:
		InputMode.SELECT_CHAMPION, InputMode.NONE:
			if champion.owner_id == 1:
				# Select own champion
				_select_champion(champion_id)
			else:
				# Clicked enemy - try to attack if we have a champion selected
				if not selected_champion_id.is_empty():
					_try_attack(champion_id)

		InputMode.SELECT_MOVE:
			# In move mode, clicking champions allows:
			# - Clicking own champion: switch selection
			# - Clicking enemy: attack if in range
			if champion.owner_id == 1:
				# Switch to different champion
				_select_champion(champion_id)
			else:
				# Try to attack the enemy
				if not selected_champion_id.is_empty():
					_try_attack(champion_id)

		InputMode.SELECT_ATTACK_TARGET:
			if champion.owner_id != 1:
				_try_attack(champion_id)

		InputMode.SELECT_CAST_TARGET:
			_try_cast_on_target(champion_id)


func _on_tile_clicked(position: Vector2i) -> void:
	"""Handle clicking on an empty tile."""
	# Immediate movement is allowed even when not player's turn (response phase)
	if input_mode == InputMode.IMMEDIATE_MOVE:
		_try_immediate_move(position)
		return

	if not is_player_turn:
		return

	match input_mode:
		InputMode.SELECT_MOVE:
			_try_move(position)
		InputMode.SELECT_CAST_TARGET:
			# Some cards target tiles - pass position as target
			pass
		InputMode.SELECT_DIRECTION:
			# Determine direction from caster to clicked tile
			_try_cast_direction(position)
		InputMode.SELECT_POSITION:
			# Cast on the clicked position
			_try_cast_on_position(position)
		_:
			# Clicking empty tile deselects
			_reset_input_state()


func _on_card_selected(card_name: String) -> void:
	"""Handle selecting a card from hand."""
	print("Game._on_card_selected: '%s', is_player_turn=%s" % [card_name, is_player_turn])

	var card_data := CardDatabase.get_card(card_name)
	var card_type: String = str(card_data.get("type", ""))

	# Check if this is a response card during a response window
	if card_type == "Response":
		if not game_controller.response_stack.is_open():
			print("Game: Response card but no response window open")
			return
		if game_controller.response_stack.get_priority_player() != 1:
			print("Game: Response card but player doesn't have priority")
			return
		# Handle response card - check if it needs a target
		_handle_response_card_selection(card_name, card_data)
		return

	# For non-response cards, must be player's turn
	if not is_player_turn:
		print("Game: Not player turn, ignoring card selection")
		return

	selected_card = card_name
	input_mode = InputMode.SELECT_CAST_TARGET

	# Show valid targets
	var target_type: String = str(card_data.get("target", "none"))
	print("Game: Card target type: '%s'" % target_type)

	board.clear_highlights()

	match target_type.to_lower():
		"enemy":
			var targets := _get_enemy_positions()
			board.show_attack_highlights(targets)
			input_mode = InputMode.SELECT_CAST_TARGET
		"ally", "friendly":
			var targets := _get_ally_positions()
			board.show_cast_highlights(targets)
			input_mode = InputMode.SELECT_CAST_TARGET
		"allyorself":
			var targets := _get_ally_positions()
			board.show_cast_highlights(targets)
			input_mode = InputMode.SELECT_CAST_TARGET
		"none":
			# No target needed - cast immediately
			print("Game: No target needed, casting immediately")
			_try_cast_no_target()
		"self":
			# Self-targeting - cast immediately on caster
			print("Game: Self-targeting, casting immediately")
			_try_cast_no_target()
		"direction":
			# Direction targeting - show direction options from caster
			print("Game: Direction targeting - select a direction")
			input_mode = InputMode.SELECT_DIRECTION
			_show_direction_highlights()
		"position":
			# Position targeting - player needs to click a tile
			print("Game: Position targeting - click a tile")
			input_mode = InputMode.SELECT_POSITION
			_show_position_highlights()
		_:
			# Unknown target type - try to cast anyway
			print("Game: Unknown target type '%s', attempting cast" % target_type)
			_try_cast_no_target()


func _handle_response_card_selection(card_name: String, card_data: Dictionary) -> void:
	"""Handle selection of a response card during response window."""
	var target_type: String = str(card_data.get("target", "none"))
	print("Game: Response card target type: '%s'" % target_type)

	# For Tantrum and similar cards that target "enemy", we need to target the attacker
	# from the trigger context
	var context := game_controller.response_stack.get_trigger_context()

	match target_type.to_lower():
		"enemy":
			# Target is typically the attacker from context
			var attacker_id: String = context.get("attacker", "")
			if attacker_id.is_empty():
				print("Game: No attacker in context for enemy-targeted response")
				return
			_play_response_card(card_name, [attacker_id])
		"self", "none":
			# No explicit target needed
			_play_response_card(card_name, [])
		_:
			# Default: try without targets
			_play_response_card(card_name, [])


func _play_response_card(card_name: String, targets: Array) -> void:
	"""Play a response card."""
	# Find a valid caster (any living champion of player 1)
	var state := game_controller.get_game_state()
	var caster_id := ""

	# For character-specific responses, use the specific character
	var card_data := CardDatabase.get_card(card_name)
	var card_character: String = card_data.get("character", "")

	for champ: ChampionState in state.get_champions(1):
		if champ.is_alive():
			if card_character.is_empty() or champ.champion_name == card_character:
				caster_id = champ.unique_id
				break

	if caster_id.is_empty():
		print("Game: No valid caster for response")
		return

	print("Game: Playing response '%s' with caster '%s' and targets %s" % [card_name, caster_id, targets])
	var result := game_controller.play_response(1, card_name, caster_id, targets)

	if result.get("success", false):
		hud.show_message("Response played: " + card_name)
		_update_ui()
	else:
		print("Game: Failed to play response: %s" % result.get("error", "unknown"))


func _on_card_deselected() -> void:
	"""Handle deselecting a card."""
	selected_card = ""
	if input_mode == InputMode.SELECT_CAST_TARGET:
		input_mode = InputMode.SELECT_CHAMPION
	board.clear_highlights()


func _select_champion(champion_id: String) -> void:
	"""Select a champion and show available actions."""
	selected_champion_id = champion_id
	board.select_champion(champion_id)

	# Highlight the portrait in the HUD
	hud.set_selected_champion(champion_id)

	var state := game_controller.get_game_state()
	var champion := state.get_champion(champion_id)

	if champion == null:
		return

	# Show valid moves (green)
	var valid_moves := game_controller.get_valid_moves(champion_id)
	board.show_move_highlights(valid_moves)

	# Show attack range (yellow) - all tiles in range
	var range_tiles := _get_range_tiles(champion, state)
	board.show_range_highlights(range_tiles)

	# Show valid attack targets (red) - enemies in range
	var valid_targets := game_controller.get_valid_attack_targets(champion_id)
	var target_positions: Array[Vector2i] = []
	for target_id: String in valid_targets:
		var target := state.get_champion(target_id)
		if target:
			target_positions.append(target.position)
	board.show_attack_highlights(target_positions)

	input_mode = InputMode.SELECT_MOVE


func _get_range_tiles(champion: ChampionState, state: GameState) -> Array[Vector2i]:
	"""Get all tiles within the champion's attack range."""
	var tiles: Array[Vector2i] = []
	var pos: Vector2i = champion.position
	var attack_range: int = champion.current_range
	var is_melee: bool = attack_range <= 1

	if is_melee:
		# Melee: 8-directional (Chebyshev distance)
		for dx in range(-attack_range, attack_range + 1):
			for dy in range(-attack_range, attack_range + 1):
				if dx == 0 and dy == 0:
					continue
				var tile: Vector2i = Vector2i(pos.x + dx, pos.y + dy)
				if state.is_valid_position(tile):
					tiles.append(tile)
	else:
		# Ranged: Adjacent squares (all 8) + cardinal directions at range
		# First add all 8 adjacent tiles (melee range)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var tile: Vector2i = Vector2i(pos.x + dx, pos.y + dy)
				if state.is_valid_position(tile):
					tiles.append(tile)
		# Then add cardinal directions beyond distance 1
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			for dist in range(2, attack_range + 1):
				var tile: Vector2i = pos + dir * dist
				if state.is_valid_position(tile):
					tiles.append(tile)

	return tiles


func _try_move(position: Vector2i) -> void:
	"""Attempt to move selected champion."""
	if selected_champion_id.is_empty():
		return

	var result := game_controller.move_champion(selected_champion_id, position)
	if result.get("success", false):
		_update_after_action()


func _try_attack(target_id: String) -> void:
	"""Attempt to attack with selected champion."""
	if selected_champion_id.is_empty():
		return

	var result := game_controller.attack_champion(selected_champion_id, target_id)
	if result.get("success", false):
		_update_after_action()


func _try_cast_on_target(target_id: String) -> void:
	"""Attempt to cast selected card on target."""
	if selected_card.is_empty():
		return

	# Auto-select caster if none selected
	var caster_id := selected_champion_id
	if caster_id.is_empty():
		var state := game_controller.get_game_state()
		for champ: ChampionState in state.get_living_champions(1):
			caster_id = champ.unique_id
			break

	if caster_id.is_empty():
		print("No valid caster found")
		return

	print("Casting %s with %s on %s" % [selected_card, caster_id, target_id])
	var result := game_controller.cast_card(selected_card, caster_id, [target_id])
	print("Cast result: %s" % result)

	if result.get("success", false):
		hand_ui.clear_selection()
		_update_after_action()
		_reset_input_state()
	else:
		# Show error message
		var error: String = result.get("error", "Cast failed")
		hud.show_message(error, 1.5)


func _try_cast_no_target() -> void:
	"""Attempt to cast selected card with no target."""
	print("_try_cast_no_target called, selected_card='%s'" % selected_card)
	if selected_card.is_empty():
		print("  ERROR: selected_card is empty!")
		return

	# Use selected champion or first living champion as caster
	var state := game_controller.get_game_state()
	var caster_id := selected_champion_id
	print("  selected_champion_id='%s'" % selected_champion_id)
	if caster_id.is_empty():
		print("  No champion selected, finding first living champion...")
		for champ: ChampionState in state.get_living_champions(1):
			caster_id = champ.unique_id
			print("  Found: %s" % caster_id)
			break

	if caster_id.is_empty():
		print("  ERROR: No caster found!")
		return

	# For "self" or "none" target cards, pass caster as target for effects that need it
	var card_data := CardDatabase.get_card(selected_card)
	var target_type: String = str(card_data.get("target", "none"))
	var targets: Array = []
	if target_type.to_lower() == "self":
		targets = [caster_id]  # Self-targeting cards apply to caster

	print("Casting %s with caster %s, targets %s" % [selected_card, caster_id, targets])
	var result := game_controller.cast_card(selected_card, caster_id, targets)
	print("Cast result: %s" % result)

	if result.get("success", false):
		print("  Cast successful! Updating UI...")
		hand_ui.clear_selection()
		_update_after_action()
		_reset_input_state()
	else:
		var error: String = result.get("error", "Cast failed")
		print("  Cast failed: %s" % error)
		hud.show_message(error, 1.5)


func _update_after_action() -> void:
	"""Update UI after an action."""
	board.update_champion_positions()
	board.update_champion_hp()
	board.update_terrain()  # Update terrain for temporary pits, etc.
	_update_ui()

	# Keep buttons enabled if it's still player's turn
	if is_player_turn:
		hud.set_action_buttons_enabled(true)

	# Re-select champion to update available actions
	if not selected_champion_id.is_empty():
		_select_champion(selected_champion_id)


func _reset_input_state() -> void:
	"""Reset input state."""
	selected_champion_id = ""
	selected_card = ""
	input_mode = InputMode.SELECT_CHAMPION
	board.clear_highlights()
	hand_ui.clear_selection()
	hud.clear_selection()  # Clear portrait highlighting


func _on_end_turn_pressed() -> void:
	"""Handle end turn button."""
	print("End Turn button pressed, is_player_turn=%s" % is_player_turn)
	if is_player_turn:
		_reset_input_state()
		var result := game_controller.end_turn()
		print("End turn result: %s" % result)
	else:
		print("Cannot end turn - not player's turn")


func _on_undo_pressed() -> void:
	"""Handle undo button."""
	if is_player_turn:
		if game_controller.undo_last_action():
			board.update_champion_positions()
			board.update_champion_hp()
			_update_ui()


func _on_pass_priority_pressed() -> void:
	"""Handle pass priority button in response window."""
	print("Game: _on_pass_priority_pressed called")
	if game_controller.response_stack.is_open():
		var priority_player := game_controller.response_stack.get_priority_player()
		print("  Response stack is open, priority_player=%d" % priority_player)
		if priority_player == 1:
			var should_resolve := game_controller.response_stack.pass_priority()
			print("  Player passed, should_resolve=%s" % should_resolve)
			if should_resolve:
				# Both players passed - resolve the stack
				var results := game_controller.response_stack.resolve()
				for result: Dictionary in results:
					print("Response resolved: %s" % result)
				_update_ui()
				board.update_champion_positions()
				board.update_champion_hp()
				board.update_terrain()  # Update for temporary pits
			else:
				# Priority passed to opponent - AI will respond
				_handle_ai_response()


func _handle_ai_response() -> void:
	"""Handle AI response during response window."""
	if not game_controller.response_stack.is_open():
		return

	var priority_player := game_controller.response_stack.get_priority_player()
	if priority_player != 2:
		return

	# AI decides whether to respond
	# For now, AI always passes (can be improved later)
	await get_tree().create_timer(0.5).timeout
	var should_resolve := game_controller.response_stack.pass_priority()
	if should_resolve:
		var results := game_controller.response_stack.resolve()
		for result: Dictionary in results:
			print("Response resolved: %s" % result)
		_update_ui()
		board.update_champion_positions()
		board.update_champion_hp()
		board.update_terrain()  # Update for temporary pits
	else:
		# Priority back to player
		hud.show_response_window(
			game_controller.response_stack.get_current_trigger(),
			game_controller.response_stack.get_priority_player()
		)


func _update_ui() -> void:
	"""Update all UI elements."""
	var state := game_controller.get_game_state()
	hud.update_display()

	# Update hand for player 1
	var hand := state.get_hand(1)
	var mana := state.get_mana(1)

	# Check if response window is open and get valid responses for player 1
	var valid_responses: Array[String] = []
	if game_controller.response_stack.is_open():
		var priority_player := game_controller.response_stack.get_priority_player()
		if priority_player == 1:
			valid_responses = game_controller.response_stack.get_valid_responses(1)

	hand_ui.update_hand(hand, mana, valid_responses)

	# Update discard pile for player 1
	var discard := state.get_discard(1)
	hand_ui.update_discard(discard)


func _get_enemy_positions() -> Array[Vector2i]:
	"""Get positions of enemy champions in range of caster."""
	var positions: Array[Vector2i] = []
	var state := game_controller.get_game_state()
	var caster := _get_caster()
	if caster == null:
		return positions

	var range_calc := RangeCalculator.new()
	for enemy: ChampionState in state.get_living_champions(2):
		if _is_in_cast_range(caster, enemy, state, range_calc):
			positions.append(enemy.position)
	return positions


func _get_ally_positions() -> Array[Vector2i]:
	"""Get positions of allied champions in range of caster."""
	var positions: Array[Vector2i] = []
	var state := game_controller.get_game_state()
	var caster := _get_caster()
	if caster == null:
		return positions

	var range_calc := RangeCalculator.new()
	for ally: ChampionState in state.get_living_champions(1):
		if _is_in_cast_range(caster, ally, state, range_calc):
			positions.append(ally.position)
	return positions


func _get_caster() -> ChampionState:
	"""Get the caster champion for the current card."""
	var state := game_controller.get_game_state()

	# Use selected champion or first living champion
	var caster_id := selected_champion_id
	if caster_id.is_empty():
		for champ: ChampionState in state.get_living_champions(1):
			return champ
		return null

	return state.get_champion(caster_id)


func _is_in_cast_range(caster: ChampionState, target: ChampionState, state: GameState, range_calc: RangeCalculator) -> bool:
	"""Check if target is within caster's range for card targeting."""
	# Self-targeting is always valid
	if caster.unique_id == target.unique_id:
		return true

	# Use same range rules as attacks - caster's range determines valid targets
	var caster_pos: Vector2i = caster.position
	var target_pos: Vector2i = target.position
	var is_melee: bool = caster.current_range <= 1

	if is_melee:
		# Melee: Chebyshev distance (8 directions)
		var dist: int = maxi(absi(target_pos.x - caster_pos.x), absi(target_pos.y - caster_pos.y))
		return dist <= caster.current_range
	else:
		# Ranged: Must be in cardinal direction and within range
		var dx: int = target_pos.x - caster_pos.x
		var dy: int = target_pos.y - caster_pos.y

		# Must be in a cardinal direction (one axis must be 0)
		if dx != 0 and dy != 0:
			return false

		var dist: int = absi(dx) + absi(dy)
		return dist <= caster.current_range


func _show_direction_highlights() -> void:
	"""Show tiles in the 4 cardinal directions from caster."""
	var caster_pos: Vector2i = _get_caster_position()
	if caster_pos == Vector2i(-1, -1):
		return

	var directions: Array[Vector2i] = []
	# Show one tile in each direction to indicate the direction
	for dir: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var pos: Vector2i = caster_pos + dir
		if game_controller.get_game_state().is_valid_position(pos):
			directions.append(pos)

	board.show_cast_highlights(directions)
	hud.show_message("Click a direction (up/down/left/right)", 3.0)


func _show_position_highlights() -> void:
	"""Show valid position tiles for position-targeting cards."""
	# For now, show all empty walkable tiles
	# TODO: Respect card's range property
	var state := game_controller.get_game_state()
	var valid_positions: Array[Vector2i] = []

	for x in range(1, 9):  # Exclude walls
		for y in range(1, 9):
			var pos := Vector2i(x, y)
			if state.is_walkable(pos):
				valid_positions.append(pos)

	board.show_cast_highlights(valid_positions)
	hud.show_message("Click a tile to target", 3.0)


func _get_caster_position() -> Vector2i:
	"""Get position of the caster for the current card."""
	var state := game_controller.get_game_state()

	# Use selected champion or first living champion
	var caster_id := selected_champion_id
	if caster_id.is_empty():
		for champ: ChampionState in state.get_living_champions(1):
			caster_id = champ.unique_id
			break

	if caster_id.is_empty():
		return Vector2i(-1, -1)

	var caster := state.get_champion(caster_id)
	if caster:
		return caster.position
	return Vector2i(-1, -1)


func _try_cast_direction(clicked_pos: Vector2i) -> void:
	"""Cast a direction-targeting card based on clicked position."""
	if selected_card.is_empty():
		return

	var caster_pos: Vector2i = _get_caster_position()
	if caster_pos == Vector2i(-1, -1):
		return

	# Determine direction from caster to clicked tile
	var diff: Vector2i = clicked_pos - caster_pos
	var direction: String = ""

	# Determine primary direction
	if abs(diff.x) >= abs(diff.y):
		direction = "right" if diff.x > 0 else "left"
	else:
		direction = "down" if diff.y > 0 else "up"

	print("Direction selected: %s (diff=%s)" % [direction, diff])

	# Get caster
	var state := game_controller.get_game_state()
	var caster_id := selected_champion_id
	if caster_id.is_empty():
		for champ: ChampionState in state.get_living_champions(1):
			caster_id = champ.unique_id
			break

	# Cast the card with direction as context
	# For now, pass direction as a string in targets array
	print("Casting %s in direction %s" % [selected_card, direction])
	var result := game_controller.cast_card(selected_card, caster_id, [direction])
	print("Cast result: %s" % result)

	if result.get("success", false):
		hand_ui.clear_selection()
		_update_after_action()
		_reset_input_state()
	else:
		var error: String = result.get("error", "Cast failed")
		print("Cast failed: %s" % error)
		hud.show_message(error, 1.5)
		_reset_input_state()


func _try_cast_on_position(target_pos: Vector2i) -> void:
	"""Cast a position-targeting card on the clicked tile."""
	if selected_card.is_empty():
		return

	# Get caster
	var state := game_controller.get_game_state()
	var caster_id := selected_champion_id
	if caster_id.is_empty():
		for champ: ChampionState in state.get_living_champions(1):
			caster_id = champ.unique_id
			break

	if caster_id.is_empty():
		return

	# Pass position as target (convert to string for now)
	var pos_str := "%d,%d" % [target_pos.x, target_pos.y]
	print("Casting %s at position %s" % [selected_card, pos_str])
	var result := game_controller.cast_card(selected_card, caster_id, [pos_str])
	print("Cast result: %s" % result)

	if result.get("success", false):
		hand_ui.clear_selection()
		_update_after_action()
		_reset_input_state()
	else:
		var error: String = result.get("error", "Cast failed")
		print("Cast failed: %s" % error)
		hud.show_message(error, 1.5)
		_reset_input_state()


# === Immediate Movement Handling ===

func _on_immediate_movement_required(champion_ids: Array, movement_bonus: int) -> void:
	"""Handle immediate movement request from response cards."""
	print("Immediate movement required for champions: %s (bonus: %d)" % [champion_ids, movement_bonus])

	# Filter to only player 1's champions (AI handles its own)
	var state := game_controller.get_game_state()
	_pending_immediate_moves = []

	for champ_id in champion_ids:
		var champ := state.get_champion(str(champ_id))
		if champ and champ.owner_id == 1:
			_pending_immediate_moves.append(str(champ_id))

	if _pending_immediate_moves.is_empty():
		print("No player 1 champions need immediate movement")
		return

	# Start immediate movement UI for first champion
	_start_immediate_movement_for_next_champion()


func _start_immediate_movement_for_next_champion() -> void:
	"""Start immediate movement UI for the next pending champion."""
	if _pending_immediate_moves.is_empty():
		# All immediate movements done - continue with response resolution
		print("All immediate movements completed")
		_immediate_move_champion_id = ""
		input_mode = InputMode.SELECT_CHAMPION
		board.clear_highlights()
		board.update_champion_positions()
		_update_ui()
		return

	# Get next champion
	_immediate_move_champion_id = _pending_immediate_moves.pop_front()
	var state := game_controller.get_game_state()
	var champion := state.get_champion(_immediate_move_champion_id)

	if champion == null or not champion.is_alive():
		# Skip dead champions
		_start_immediate_movement_for_next_champion()
		return

	print("Starting immediate movement for: %s" % champion.champion_name)
	input_mode = InputMode.IMMEDIATE_MOVE

	# Show valid move destinations
	var pathfinder := Pathfinder.new(state)
	var valid_moves := pathfinder.get_reachable_tiles(champion)

	board.clear_highlights()
	board.select_champion(_immediate_move_champion_id)
	board.show_move_highlights(valid_moves)

	hud.show_message("Move %s (immediate)" % champion.champion_name, 5.0)


func _try_immediate_move(position: Vector2i) -> void:
	"""Handle immediate movement selection."""
	if _immediate_move_champion_id.is_empty():
		return

	var state := game_controller.get_game_state()
	var champion := state.get_champion(_immediate_move_champion_id)

	if champion == null:
		_start_immediate_movement_for_next_champion()
		return

	# Validate move destination
	var pathfinder := Pathfinder.new(state)
	var valid_moves := pathfinder.get_reachable_tiles(champion)

	if position not in valid_moves:
		hud.show_message("Invalid move destination", 1.0)
		return

	# Execute the move directly (not through action system since this is mid-response)
	var old_pos: Vector2i = champion.position
	champion.position = position
	champion.has_moved = true

	print("Immediate move: %s from %s to %s" % [champion.champion_name, old_pos, position])

	# Animate the move
	var path: Array[Vector2i] = [position]
	board.animate_move(_immediate_move_champion_id, path)

	# Update board
	await get_tree().create_timer(0.3).timeout
	board.update_champion_positions()

	# Move to next champion or finish
	_start_immediate_movement_for_next_champion()
