extends Node2D
class_name GameScene
## GameScene - Main game scene coordinating all game elements
## Connects board, UI, and game logic

const BOARD_SCENE := preload("res://scenes/game/board/board.tscn")
const BOARD_3D_SCENE := preload("res://scenes/game/board_3d/board_3d.tscn")
const HAND_SCENE := preload("res://scenes/game/cards/hand.tscn")
const HUD_SCENE := preload("res://scenes/game/game_hud.tscn")

# 3D Mode toggle - set to false for 2D Classic mode (game_3d.tscn is used for 3D mode)
var use_3d_board: bool = false

# Scene references
var board: GameBoard  # 2D board
var board_3d: Board3D  # 3D board
var board_3d_viewport: SubViewportContainer
var board_3d_manager: Board3DManager
var hand_ui: HandUI
var hud: GameHUD
var response_slot: ResponseSlot  # Player's response card slot

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
	IMMEDIATE_MOVE,  # Player selecting where to move during response
	IMMEDIATE_CONTROL_MOVE,  # Player moving a mind-controlled enemy champion
	IMMEDIATE_CONTROL_ATTACK,  # Player attacking with a mind-controlled enemy champion
	SELECT_DISCARD,  # Player selecting cards to discard (e.g., From the Sky)
	INTEL_CHOICE,  # Player choosing top/bottom for Intel card
	X_VALUE_CHOICE  # Player choosing X mana value (e.g., Guess Again)
}

var input_mode: InputMode = InputMode.SELECT_CHAMPION
var selected_champion_id: String = ""
var selected_card: String = ""
var is_player_turn: bool = true
var ai_vs_ai_mode: bool = false
var ai_player1: AIController  # AI for player 1 in AI vs AI mode

# Developer mode for step-through debugging
var developer_mode: bool = false
var dev_controller: DeveloperModeController = null
var decision_log: DecisionLogPanel = null

# Immediate movement state
var _pending_immediate_moves: Array = []  # Champion IDs waiting for movement selection
var _immediate_move_champion_id: String = ""  # Currently selecting move for this champion

# Mind control state (Betrayal)
var _control_champion_id: String = ""  # Enemy champion being controlled
var _control_player_id: int = 0  # Player who has control


# Helper to get the active board (works with both 2D and 3D)
func get_active_board():
	"""Returns the active board instance (2D or 3D)."""
	if use_3d_board and board_3d:
		return board_3d
	return board

# X value choice state
var _x_value_panel: Control = null
var _x_chosen_value: int = 0
var _x_max_value: int = 0
var _x_card_name: String = ""

# Intel choice state
var _intel_own_card: String = ""
var _intel_opp_card: String = ""
var _intel_panel: Control = null
var _intel_own_to_bottom: bool = false
var _intel_opp_to_bottom: bool = false

# Discard selection state (for From the Sky, etc.)
var _discard_selection_active: bool = false
var _discard_selected_cards: Array[String] = []
var _discard_caster_id: String = ""
var _discard_confirm_button: Button = null

# Discard choice state (for Introspection — choose exactly N cards to discard)
var _discard_choice_active: bool = false
var _discard_choice_count: int = 0
var _discard_choice_selected: Array[String] = []
var _discard_choice_confirm_button: Button = null


func _ready() -> void:
	# Check for AI vs AI mode
	ai_vs_ai_mode = get_meta("ai_vs_ai", false)
	if ai_vs_ai_mode:
		print("GameScene: AI vs AI mode enabled")

	# Check for Developer mode (step-through AI debugging)
	developer_mode = get_meta("developer_mode", false)
	if developer_mode:
		print("GameScene: Developer Mode enabled - step-through debugging active")
		dev_controller = DeveloperModeController.new()

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
	const BOTTOM_BAR_HEIGHT := 200  # Hand UI height (increased for larger cards)
	const BOARD_SIZE := 688  # 10*64 tiles + 24*2 coord margins
	const SCREEN_WIDTH := 1920
	const SCREEN_HEIGHT := 1080

	# Calculate available vertical space for board - maximize it
	var top_offset := TOP_BAR_HEIGHT + MARGIN
	var available_height := SCREEN_HEIGHT - top_offset - BOTTOM_BAR_HEIGHT - MARGIN * 2

	# Scale board to fill available vertical space
	var board_scale := available_height / float(BOARD_SIZE)

	# Calculate centered board position horizontally
	# Left panel ends at: MARGIN + PANEL_WIDTH = 230
	# Right panel starts at: 1920 - MARGIN - PANEL_WIDTH = 1690
	# Center area: 1460px wide
	var center_area_start := MARGIN + PANEL_WIDTH
	var center_area_width := SCREEN_WIDTH - 2 * (MARGIN + PANEL_WIDTH)
	var board_x := center_area_start + (center_area_width - BOARD_SIZE * board_scale) / 2

	# Position board at top of available space to maximize vertical usage
	var board_y := top_offset

	if use_3d_board:
		# Create 3D board with SubViewport for rendering
		_setup_3d_board(board_x, board_y, BOARD_SIZE * board_scale)
	else:
		# Use traditional 2D board
		board = BOARD_SCENE.instantiate()
		board.position = Vector2(board_x, board_y)
		board.scale = Vector2(board_scale, board_scale)
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
	hand_ui.card_toggled.connect(_on_discard_card_toggled)

	# Create response slot - positioned to the LEFT of the board, vertically centered
	response_slot = ResponseSlot.new()
	var slot_x := board_x - ResponseSlot.SLOT_WIDTH - 20  # Left of board with gap
	var slot_y := top_offset + (available_height - ResponseSlot.SLOT_HEIGHT) / 2  # Vertically centered
	response_slot.position = Vector2(slot_x, slot_y)
	add_child(response_slot)

	# Connect response slot signals
	response_slot.slot_clicked.connect(_on_response_slot_clicked)
	response_slot.card_removed.connect(_on_response_card_removed)

	# === Developer Mode: draggable/resizable panels ===
	if developer_mode:
		# Decision log panel
		decision_log = DecisionLogPanel.new()
		var log_default_pos := Vector2(SCREEN_WIDTH - DecisionLogPanel.PANEL_WIDTH - MARGIN, TOP_BAR_HEIGHT + MARGIN)
		var log_default_size := Vector2(DecisionLogPanel.PANEL_WIDTH, DecisionLogPanel.PANEL_HEIGHT + DraggableWrapper.TITLE_BAR_HEIGHT)
		var log_wrapper := DraggableWrapper.wrap(
			decision_log, "decision_log", "Decision Log",
			log_default_pos, log_default_size)
		hud.add_child(log_wrapper)

		# Connect step controls
		decision_log.step_requested.connect(_on_step_requested)
		decision_log.execute_all_requested.connect(_on_execute_all_requested)
		decision_log.set_status("Developer Mode - Waiting for game start...")

		# Wrap the board in a draggable overlay
		var board_visual_size := BOARD_SIZE * board_scale
		_setup_board_drag_overlay(board_x, board_y, board_visual_size, board_scale)

		# Wrap hand UI (lives in HUD CanvasLayer)
		var hand_default_pos := Vector2(240, SCREEN_HEIGHT - BOTTOM_BAR_HEIGHT - DraggableWrapper.TITLE_BAR_HEIGHT)
		var hand_default_size := Vector2(SCREEN_WIDTH - 480, BOTTOM_BAR_HEIGHT + DraggableWrapper.TITLE_BAR_HEIGHT)
		# Remove from HUD, clear anchors, wrap, re-add
		hud.remove_child(hand_ui)
		hand_ui.anchor_left = 0
		hand_ui.anchor_top = 0
		hand_ui.anchor_right = 0
		hand_ui.anchor_bottom = 0
		hand_ui.offset_left = 0
		hand_ui.offset_top = 0
		hand_ui.offset_right = 0
		hand_ui.offset_bottom = 0
		var hand_wrapper := DraggableWrapper.wrap(
			hand_ui, "player_hand", "Player Hand",
			hand_default_pos, hand_default_size)
		hud.add_child(hand_wrapper)

		# Wrap response slot — move from Node2D scene to HUD CanvasLayer for proper Control positioning
		var rs_pos := response_slot.position
		remove_child(response_slot)
		response_slot.position = Vector2.ZERO
		var rs_default_size := Vector2(ResponseSlot.SLOT_WIDTH, ResponseSlot.SLOT_HEIGHT + DraggableWrapper.TITLE_BAR_HEIGHT)
		var rs_wrapper := DraggableWrapper.wrap(
			response_slot, "response_slot", "Response Slot",
			rs_pos, rs_default_size)
		hud.add_child(rs_wrapper)

		# Enable HUD developer layout (sidebars, turn info, combat log)
		hud.enable_developer_layout()

		print("GameScene: Developer Mode layout enabled — all panels draggable/resizable")


var _board_drag_overlay: Control = null

func _setup_board_drag_overlay(board_x: float, board_y: float, board_visual_size: float, base_scale: float) -> void:
	"""Create a transparent draggable overlay for the game board (Node2D).
	Dragging/resizing the overlay moves/scales the underlying board."""
	var default_pos := Vector2(board_x, board_y)
	var default_size := Vector2(board_visual_size, board_visual_size)

	# Check for saved layout
	var saved: Dictionary = {}
	if DevLayout and DevLayout.has_layout("game_board"):
		saved = DevLayout.get_layout("game_board")
	var pos: Vector2 = saved.get("position", default_pos)
	var sz: Vector2 = saved.get("size", default_size)

	# Apply saved position/scale to board
	if board:
		board.position = pos
		var new_scale := sz.x / (688.0)  # BOARD_SIZE without margins
		board.scale = Vector2(new_scale, new_scale)

	# Create overlay control for drag/resize
	_board_drag_overlay = Control.new()
	_board_drag_overlay.name = "BoardDragOverlay"
	_board_drag_overlay.position = pos
	_board_drag_overlay.size = sz
	_board_drag_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_board_drag_overlay)

	# Title bar for dragging
	var title_bar := PanelContainer.new()
	title_bar.custom_minimum_size = Vector2(0, 22)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_board_drag_overlay.add_child(title_bar)
	title_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_bar.offset_bottom = 22

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.18, 0.16, 0.22, 0.8)
	bar_style.border_color = Color(0.4, 0.35, 0.5)
	bar_style.border_width_bottom = 1
	title_bar.add_theme_stylebox_override("panel", bar_style)

	var lbl := Label.new()
	lbl.text = "  ⠿  Game Board"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(lbl)

	# Drag logic
	var dragging := [false]
	var drag_offset := [Vector2.ZERO]
	title_bar.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging[0] = true
				drag_offset[0] = _board_drag_overlay.get_global_mouse_position() - _board_drag_overlay.global_position
			else:
				dragging[0] = false
				if DevLayout and board:
					DevLayout.save_layout("game_board", _board_drag_overlay.position, _board_drag_overlay.size)
		elif event is InputEventMouseMotion and dragging[0]:
			var new_pos: Vector2 = _board_drag_overlay.get_global_mouse_position() - drag_offset[0]
			_board_drag_overlay.position = new_pos
			if board:
				board.position = new_pos
	)

	# Resize handle
	var resize := Control.new()
	resize.custom_minimum_size = Vector2(14, 14)
	resize.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	resize.offset_left = -14
	resize.offset_top = -14
	resize.mouse_filter = Control.MOUSE_FILTER_STOP
	resize.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_board_drag_overlay.add_child(resize)

	var resizing := [false]
	var resize_start_mouse := [Vector2.ZERO]
	var resize_start_size := [Vector2.ZERO]
	resize.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				resizing[0] = true
				resize_start_mouse[0] = _board_drag_overlay.get_global_mouse_position()
				resize_start_size[0] = _board_drag_overlay.size
			else:
				resizing[0] = false
				if DevLayout and board:
					DevLayout.save_layout("game_board", _board_drag_overlay.position, _board_drag_overlay.size)
		elif event is InputEventMouseMotion and resizing[0]:
			var delta: Vector2 = _board_drag_overlay.get_global_mouse_position() - resize_start_mouse[0]
			# Keep square aspect ratio
			var max_delta: float = maxf(delta.x, delta.y)
			var new_s: float = maxf(resize_start_size[0].x + max_delta, 200.0)
			_board_drag_overlay.size = Vector2(new_s, new_s)
			if board:
				var new_scale: float = new_s / 688.0
				board.scale = Vector2(new_scale, new_scale)
	)

	# Draw resize grip
	resize.draw.connect(func() -> void:
		var c: Color = Color(0.5, 0.45, 0.55, 0.7)
		for i: int in range(3):
			for j: int in range(3 - i):
				resize.draw_circle(Vector2(14 - 4 - j * 4, 14 - 4 - i * 4), 1.5, c)
	)


func _setup_3d_board(board_x: float, board_y: float, board_size: float) -> void:
	"""Set up the 3D Battle Chess board using SubViewport."""
	print("Setting up 3D Battle Chess board...")

	# Create SubViewportContainer to display 3D content in 2D scene
	board_3d_viewport = SubViewportContainer.new()
	board_3d_viewport.name = "Board3DViewport"
	board_3d_viewport.position = Vector2(board_x, board_y)
	board_3d_viewport.size = Vector2(board_size, board_size)
	board_3d_viewport.stretch = true
	add_child(board_3d_viewport)

	# Create SubViewport
	var viewport := SubViewport.new()
	viewport.name = "SubViewport"
	viewport.size = Vector2i(int(board_size), int(board_size))
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true
	board_3d_viewport.add_child(viewport)

	# Create 3D board inside viewport
	board_3d = BOARD_3D_SCENE.instantiate()
	viewport.add_child(board_3d)

	# Wait a frame for board to initialize
	await get_tree().process_frame

	# Connect 3D board signals
	if board_3d:
		board_3d.tile_clicked.connect(_on_tile_clicked)
		board_3d.champion_clicked.connect(_on_champion_clicked)
		board_3d.tile_hovered.connect(_on_tile_hovered_3d)
		board_3d.tile_unhovered.connect(_on_tile_unhovered_3d)
		print("Board3D signals connected")

	# Create Board3DManager to bridge EventBus
	board_3d_manager = Board3DManager.new()
	add_child(board_3d_manager)
	board_3d_manager.set_board(board_3d)

	print("3D Board setup complete!")


func _on_tile_hovered_3d(grid_pos: Vector2i) -> void:
	"""Handle 3D tile hover."""
	if board_3d:
		board_3d.set_highlight(grid_pos, Board3D.HighlightType.HOVER)


func _on_tile_unhovered_3d(grid_pos: Vector2i) -> void:
	"""Handle 3D tile unhover."""
	if board_3d:
		board_3d.set_highlight(grid_pos, Board3D.HighlightType.NONE)


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

	print("GameScene: Starting with P1 champions: %s, P2 champions: %s" % [p1_champions, p2_champions])

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
	game_controller.response_slot_triggered.connect(_on_response_slot_triggered)

	# Connect effect processor signals for immediate movements and combat text
	game_controller.effect_processor.immediate_movement_required.connect(_on_immediate_movement_required)
	game_controller.effect_processor.immediate_control_required.connect(_on_immediate_control_required)
	game_controller.effect_processor.damage_dealt.connect(_on_damage_dealt)
	game_controller.effect_processor.healing_done.connect(_on_healing_done)
	game_controller.effect_processor.discard_selection_required.connect(_on_discard_selection_required)
	game_controller.effect_processor.intel_choice_required.connect(_on_intel_choice_required)
	game_controller.effect_processor.x_value_required.connect(_on_x_value_required)
	game_controller.effect_processor.discard_choice_required.connect(_on_discard_choice_required)

	# Initialize AI for player 2
	ai_controller = AIController.new(game_controller, 2)
	ai_controller.set_difficulty(AIController.Difficulty.MEDIUM)

	# Initialize AI for player 1 if AI vs AI mode
	if ai_vs_ai_mode:
		ai_player1 = AIController.new(game_controller, 1)
		ai_player1.set_difficulty(AIController.Difficulty.MEDIUM)

	# Initialize UI with game state
	var state := game_controller.get_game_state()

	if use_3d_board and board_3d:
		# Initialize 3D board
		_initialize_3d_board(state)
	else:
		# Initialize 2D board
		board.initialize(state)

	hud.initialize(state)
	hand_ui.setup(1)
	response_slot.setup(1, state)

	# Start the game
	game_controller.start_game()


func _initialize_3d_board(state: GameState) -> void:
	"""Initialize the 3D board with terrain and champions."""
	print("Initializing 3D board with game state...")

	# Use the Board3D initialize method which sets up terrain, champions, and stores game state reference
	board_3d.initialize(state)

	# Log what was added
	for player_id in [1, 2]:
		for champion in state.get_champions(player_id):
			print("  3D champion ready: %s at %s" % [champion.champion_name, champion.position])

	# Initialize board manager for EventBus bridging
	if board_3d_manager:
		board_3d_manager.initialize(state)

	print("3D board initialization complete")


func _on_turn_started(player_id: int, round_number: int) -> void:
	"""Handle turn start."""
	is_player_turn = player_id == 1 and not ai_vs_ai_mode

	_update_ui()
	_reset_input_state()

	if developer_mode:
		# Developer mode: step-through AI debugging
		await _handle_developer_mode_turn(player_id)
	elif ai_vs_ai_mode:
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

	if use_3d_board and board_3d:
		# 3D Board animations
		match action_type:
			"move":
				var raw_path: Array = action.get("path", [])
				if raw_path.size() > 0:
					var typed_path: Array[Vector2i] = []
					for pos in raw_path:
						if pos is Vector2i:
							typed_path.append(pos)
					if typed_path.size() > 0:
						await board_3d.animate_move(action.get("champion", ""), typed_path)
			"attack":
				await board_3d.animate_attack(action.get("attacker", ""), action.get("target", ""))
	else:
		# 2D Board animations
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
	if use_3d_board and board_3d:
		# 3D board updates positions automatically
		pass
	else:
		board.update_champion_positions()
		board.update_champion_hp()
	_update_ui()


func _on_champion_died(champion_id: String) -> void:
	"""Handle champion death."""
	hud.show_message("Champion defeated!")
	var active_board = get_active_board()
	if active_board:
		active_board.update_champion_positions()


func _on_damage_dealt(attacker_id: String, target_id: String, amount: int) -> void:
	"""Show floating damage number when damage is dealt."""
	var state := game_controller.get_game_state()
	var target := state.get_champion(target_id)
	if target and amount > 0:
		var active_board = get_active_board()
		if active_board:
			var screen_pos := active_board.get_champion_screen_position(target_id)
			if screen_pos != Vector2.ZERO:
				hud.show_damage_number(amount, screen_pos)


func _on_healing_done(source_id: String, target_id: String, amount: int) -> void:
	"""Show floating heal number when healing is done."""
	var state := game_controller.get_game_state()
	var target := state.get_champion(target_id)
	if target and amount > 0:
		var active_board = get_active_board()
		if active_board:
			var screen_pos := active_board.get_champion_screen_position(target_id)
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


func _on_response_slot_triggered(player_id: int, card_name: String, trigger: String) -> void:
	"""Handle response card auto-triggered from slot."""
	var player_name := "Your" if player_id == 1 else "Enemy's"
	hud.show_message("%s %s triggered! (%s)" % [player_name, card_name, trigger], 2.5)

	# Update the response slot UI (card is now gone)
	if response_slot and player_id == 1:
		response_slot.update_slot()

	# Update displays
	var active_board = get_active_board()
	if active_board:
		active_board.update_champion_hp()
		active_board.update_champion_positions()
	_update_ui()


# === Input Handling ===

func _on_champion_clicked(champion_id: String) -> void:
	"""Handle clicking on a champion."""
	# Mind control modes bypass normal turn check
	if input_mode == InputMode.IMMEDIATE_CONTROL_ATTACK:
		_try_control_attack(champion_id)
		return
	if input_mode == InputMode.IMMEDIATE_CONTROL_MOVE:
		# Clicking a champion during control move — ignore, must click tile
		return

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

	if input_mode == InputMode.IMMEDIATE_CONTROL_MOVE:
		_try_control_move(position)
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
	print("  Card type: '%s'" % card_type)

	# Response cards go to the response slot (can be done any time, not just on your turn)
	if card_type == "Response":
		print("  Detected Response card, placing in slot...")
		_place_card_in_response_slot(card_name)
		hand_ui.clear_selection()  # Clear the visual selection
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

	var active_board = get_active_board()
	if active_board:
		active_board.clear_highlights()

	match target_type.to_lower():
		"enemy":
			var targets := _get_enemy_positions()
			if active_board:
				active_board.show_attack_highlights(targets)
			input_mode = InputMode.SELECT_CAST_TARGET
		"ally", "friendly":
			var targets := _get_ally_positions()
			if active_board:
				active_board.show_cast_highlights(targets)
			input_mode = InputMode.SELECT_CAST_TARGET
		"allyorself":
			var targets := _get_ally_positions()
			if active_board:
				active_board.show_cast_highlights(targets)
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
	var active_board = get_active_board()
	if active_board:
		active_board.clear_highlights()


func _select_champion(champion_id: String) -> void:
	"""Select a champion and show available actions."""
	selected_champion_id = champion_id
	var active_board = get_active_board()
	if active_board:
		active_board.select_champion(champion_id)

	# Highlight the portrait in the HUD
	hud.set_selected_champion(champion_id)

	var state := game_controller.get_game_state()
	var champion := state.get_champion(champion_id)

	if champion == null:
		return

	# Show valid moves (green)
	var valid_moves := game_controller.get_valid_moves(champion_id)
	if active_board:
		active_board.show_move_highlights(valid_moves)

	# Show attack range (yellow) - all tiles in range
	var range_tiles := _get_range_tiles(champion, state)
	if active_board:
		active_board.show_range_highlights(range_tiles)

	# Show valid attack targets (red) - enemies in range
	var valid_targets := game_controller.get_valid_attack_targets(champion_id)
	var target_positions: Array[Vector2i] = []
	for target_id: String in valid_targets:
		var target := state.get_champion(target_id)
		if target:
			target_positions.append(target.position)
	if active_board:
		active_board.show_attack_highlights(target_positions)

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
	var active_board = get_active_board()
	if active_board:
		active_board.update_champion_positions()
		active_board.update_champion_hp()
		active_board.update_terrain()  # Update terrain for temporary pits, etc.
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
	var active_board = get_active_board()
	if active_board:
		active_board.clear_highlights()
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
			var active_board = get_active_board()
			if active_board:
				active_board.update_champion_positions()
				active_board.update_champion_hp()
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
				var active_board = get_active_board()
				if active_board:
					active_board.update_champion_positions()
					active_board.update_champion_hp()
					active_board.update_terrain()  # Update for temporary pits
			else:
				# Priority passed to opponent - AI will respond
				_handle_ai_response()


# === Developer Mode Step-Through ===

var _dev_pending_actions: Array = []  # Actions queued for current turn
var _dev_current_player: int = 0
var _dev_current_ai: AIController = null
var _dev_waiting_for_input: bool = false


func _handle_developer_mode_turn(player_id: int) -> void:
	"""Handle a turn in developer mode with step-through controls."""
	_dev_current_player = player_id
	_dev_current_ai = ai_player1 if player_id == 1 else ai_controller
	var ai_name: String = "AI 1 (Blue)" if player_id == 1 else "AI 2 (Red)"

	hud.show_message("%s's turn - Analyzing options..." % ai_name)
	hud.set_action_buttons_enabled(false)

	var state := game_controller.get_game_state()

	# Get first champion name from the player's living champions
	var player_champs := state.get_living_champions(player_id)
	var first_champ_name: String = "Team"
	if player_champs.size() > 0:
		first_champ_name = player_champs[0].champion_name

	# Add turn header to log
	if decision_log:
		decision_log.add_turn_header(player_id, first_champ_name)
		decision_log.set_status("Round %d - %s's Turn" % [state.round_number, ai_name])

	# Enable reasoning capture on AI
	_dev_current_ai.capture_reasoning = true

	# Evaluate all possible actions and capture reasoning
	_dev_pending_actions = _dev_current_ai.evaluate_and_capture_actions(state)

	# Show the first action's reasoning
	if _dev_pending_actions.size() > 0:
		var best_action: Dictionary = _dev_pending_actions[0]
		if decision_log:
			decision_log.add_decision(player_id, best_action)
			decision_log.add_alternatives(_dev_pending_actions, 3)
			decision_log.set_buttons_enabled(true)
			decision_log.set_status("Action ready - Press Step or Execute All")
	else:
		if decision_log:
			decision_log.set_status("No valid actions - ending turn")
		# No actions available, end turn after brief pause
		await get_tree().create_timer(0.5).timeout
		game_controller.end_turn()
		return

	# Wait for user input
	_dev_waiting_for_input = true
	while _dev_waiting_for_input:
		await get_tree().process_frame


func _on_step_requested() -> void:
	"""Handle step button press - execute one action."""
	if not _dev_waiting_for_input or _dev_pending_actions.is_empty():
		return

	# Execute the best action (extract from wrapper)
	var action_wrapper: Dictionary = _dev_pending_actions[0]
	var action: Dictionary = action_wrapper.get("action", {})
	_dev_pending_actions.remove_at(0)

	await _execute_dev_action(action)

	# Check if more actions available
	if _dev_current_ai and game_controller:
		var state := game_controller.get_game_state()
		_dev_pending_actions = _dev_current_ai.evaluate_and_capture_actions(state)

		if _dev_pending_actions.size() > 0:
			var best_action: Dictionary = _dev_pending_actions[0]
			if decision_log:
				decision_log.add_decision(_dev_current_player, best_action)
				decision_log.add_alternatives(_dev_pending_actions, 3)
				decision_log.set_buttons_enabled(true)
				decision_log.set_status("Next action ready")
		else:
			# No more actions, end turn
			if decision_log:
				decision_log.set_status("No more actions - ending turn")
				decision_log.set_buttons_enabled(false)
			_dev_waiting_for_input = false
			await get_tree().create_timer(0.3).timeout
			game_controller.end_turn()


func _on_execute_all_requested() -> void:
	"""Handle execute all button press - run all remaining actions."""
	if not _dev_waiting_for_input:
		return

	if decision_log:
		decision_log.set_buttons_enabled(false)
		decision_log.set_status("Executing all actions...")

	# Execute all pending actions
	while not _dev_pending_actions.is_empty():
		var action_wrapper: Dictionary = _dev_pending_actions[0]
		var action: Dictionary = action_wrapper.get("action", {})
		_dev_pending_actions.remove_at(0)

		await _execute_dev_action(action)
		await get_tree().create_timer(0.3).timeout

		# Re-evaluate for more actions
		if _dev_current_ai and game_controller:
			var state := game_controller.get_game_state()
			_dev_pending_actions = _dev_current_ai.evaluate_and_capture_actions(state)

			if not _dev_pending_actions.is_empty() and decision_log:
				var best_action: Dictionary = _dev_pending_actions[0]
				decision_log.add_decision(_dev_current_player, best_action)

	# Turn complete
	if decision_log:
		decision_log.set_status("Turn complete")
	_dev_waiting_for_input = false
	await get_tree().create_timer(0.3).timeout
	game_controller.end_turn()


func _execute_dev_action(action: Dictionary) -> void:
	"""Execute a single action in developer mode."""
	var action_type: String = action.get("type", "")
	var success: bool = false
	var result_msg: String = ""

	match action_type:
		"move":
			var champ_id: String = action.get("champion", "")
			var target: Vector2i = action.get("target", Vector2i.ZERO)
			var result := game_controller.move_champion(champ_id, target)
			success = result.get("success", false)
			result_msg = "Moved to (%d, %d)" % [target.x, target.y] if success else result.get("error", "Move failed")

		"attack":
			var attacker_id: String = action.get("champion", "")  # AI uses "champion" not "attacker"
			var target_id: String = action.get("target", "")
			var result := game_controller.attack_champion(attacker_id, target_id)
			success = result.get("success", false)
			var damage: int = result.get("damage", 0)
			result_msg = "Dealt %d damage" % damage if success else result.get("error", "Attack failed")

		"cast":
			var card_name: String = action.get("card", "")
			var caster_id: String = action.get("champion", "")  # AI uses "champion" not "caster"
			var targets: Array = action.get("targets", [])
			var result := game_controller.cast_card(card_name, caster_id, targets)
			success = result.get("success", false)
			result_msg = "Cast %s" % card_name if success else result.get("error", "Cast failed")

		"place_response":
			var card_name: String = action.get("card", "")
			var state := game_controller.get_game_state()
			success = state.set_response_slot(_dev_current_player, card_name)
			result_msg = "Placed '%s' in response slot" % card_name if success else "Failed to place response"

		"end_turn":
			success = true
			result_msg = "Ending turn"

	# Log the result
	if decision_log:
		decision_log.add_action_result(success, result_msg)

	# Wait for any animations
	await get_tree().create_timer(0.4).timeout

	# Update visuals
	var active_board = get_active_board()
	if active_board:
		active_board.update_champion_positions()
		active_board.update_champion_hp()
	_update_ui()


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
		var active_board = get_active_board()
		if active_board:
			active_board.update_champion_positions()
			active_board.update_champion_hp()
			active_board.update_terrain()  # Update for temporary pits
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

	# Update response slot
	if response_slot:
		response_slot.update_slot()


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

	var active_board = get_active_board()
	if active_board:
		active_board.show_cast_highlights(directions)
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

	var active_board = get_active_board()
	if active_board:
		active_board.show_cast_highlights(valid_positions)
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
	var active_board = get_active_board()
	if _pending_immediate_moves.is_empty():
		# All immediate movements done - continue with response resolution
		print("All immediate movements completed")
		_immediate_move_champion_id = ""
		input_mode = InputMode.SELECT_CHAMPION
		if active_board:
			active_board.clear_highlights()
			active_board.update_champion_positions()
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

	if active_board:
		active_board.clear_highlights()
		active_board.select_champion(_immediate_move_champion_id)
		active_board.show_move_highlights(valid_moves)

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
	var active_board = get_active_board()
	if active_board:
		active_board.animate_move(_immediate_move_champion_id, path)

	# Update board
	await get_tree().create_timer(0.3).timeout
	if active_board:
		active_board.update_champion_positions()

	# Move to next champion or finish
	_start_immediate_movement_for_next_champion()


# === Mind Control Handling (Betrayal) ===

func _on_immediate_control_required(champion_id: String, controller_player_id: int) -> void:
	"""Handle mind control request - controller gets to move and attack with enemy champion."""
	print("Mind control: Player %d controls champion %s" % [controller_player_id, champion_id])

	var state := game_controller.get_game_state()
	var champion := state.get_champion(champion_id)
	if champion == null or not champion.is_alive():
		print("Mind control: target champion invalid or dead")
		return

	_control_champion_id = champion_id
	_control_player_id = controller_player_id

	if controller_player_id == 1:
		# Human player controls — start move phase
		_start_control_move_phase()
	else:
		# AI controls — let AI handle it
		_ai_handle_mind_control(champion_id)


func _start_control_move_phase() -> void:
	"""Start the move phase for a mind-controlled champion."""
	var state := game_controller.get_game_state()
	var champion := state.get_champion(_control_champion_id)
	if champion == null or not champion.is_alive():
		_end_control()
		return

	input_mode = InputMode.IMMEDIATE_CONTROL_MOVE

	var pathfinder := Pathfinder.new(state)
	var valid_moves := pathfinder.get_reachable_tiles(champion)

	var active_board = get_active_board()
	if active_board:
		active_board.clear_highlights()
		active_board.select_champion(_control_champion_id)
		active_board.show_move_highlights(valid_moves)

	hud.show_message("MIND CONTROL: Move %s (right-click to skip)" % champion.champion_name, 10.0)


func _try_control_move(position: Vector2i) -> void:
	"""Handle move selection for a mind-controlled champion."""
	if _control_champion_id.is_empty():
		return

	var state := game_controller.get_game_state()
	var champion := state.get_champion(_control_champion_id)
	if champion == null:
		_end_control()
		return

	var pathfinder := Pathfinder.new(state)
	var valid_moves := pathfinder.get_reachable_tiles(champion)

	if position not in valid_moves:
		hud.show_message("Invalid move destination", 1.0)
		return

	# Execute the move directly
	var old_pos: Vector2i = champion.position
	champion.position = position
	champion.has_moved = true

	print("Mind control move: %s from %s to %s" % [champion.champion_name, old_pos, position])

	var path: Array[Vector2i] = [position]
	var active_board = get_active_board()
	if active_board:
		active_board.animate_move(_control_champion_id, path)

	await get_tree().create_timer(0.3).timeout
	if active_board:
		active_board.update_champion_positions()

	# Transition to attack phase
	_start_control_attack_phase()


func _start_control_attack_phase() -> void:
	"""Start the attack phase for a mind-controlled champion."""
	var state := game_controller.get_game_state()
	var champion := state.get_champion(_control_champion_id)
	if champion == null or not champion.is_alive():
		_end_control()
		return

	# Valid attack targets are the controlled champion's allies (same owner_id) in range
	var range_calc := RangeCalculator.new()
	var valid_targets: Array = []
	for ally: ChampionState in state.get_living_champions(champion.owner_id):
		if ally.unique_id == champion.unique_id:
			continue
		if range_calc.can_attack(champion, ally, state):
			valid_targets.append(ally)

	if valid_targets.is_empty():
		print("Mind control: No valid attack targets in range")
		hud.show_message("No allies in attack range", 2.0)
		_end_control()
		return

	input_mode = InputMode.IMMEDIATE_CONTROL_ATTACK

	# Highlight valid attack targets
	var active_board = get_active_board()
	if active_board:
		active_board.clear_highlights()
		active_board.select_champion(_control_champion_id)
		var target_positions: Array[Vector2i] = []
		for t: ChampionState in valid_targets:
			target_positions.append(t.position)
		active_board.show_attack_highlights(target_positions)

	hud.show_message("MIND CONTROL: Attack with %s (right-click to skip)" % champion.champion_name, 10.0)


func _try_control_attack(target_id: String) -> void:
	"""Handle attack selection for a mind-controlled champion."""
	if _control_champion_id.is_empty():
		return

	var state := game_controller.get_game_state()
	var attacker := state.get_champion(_control_champion_id)
	var target := state.get_champion(target_id)

	if attacker == null or target == null:
		_end_control()
		return

	# Validate: target must be an ally of the controlled champion (same owner)
	if target.owner_id != attacker.owner_id or target.unique_id == attacker.unique_id:
		hud.show_message("Must attack an ally of the controlled champion", 1.0)
		return

	# Check range
	var range_calc := RangeCalculator.new()
	if not range_calc.can_attack(attacker, target, state):
		hud.show_message("Target not in range", 1.0)
		return

	# Execute the attack directly (bypass action system owner check)
	var damage: int = attacker.current_power
	var actual_damage: int = target.take_damage(damage)
	attacker.has_attacked = true

	print("Mind control attack: %s hits %s for %d damage (%d HP remaining)" % [
		attacker.champion_name, target.champion_name, actual_damage, target.current_hp])

	game_controller.effect_processor.damage_dealt.emit(attacker.unique_id, target.unique_id, actual_damage)

	# Check for death
	if not target.is_alive():
		print("Mind control kill: %s defeated %s!" % [attacker.champion_name, target.champion_name])

	var active_board = get_active_board()
	if active_board:
		active_board.update_champion_positions()

	_update_ui()
	_end_control()


func _end_control() -> void:
	"""Clean up mind control state."""
	_control_champion_id = ""
	_control_player_id = 0
	input_mode = InputMode.SELECT_CHAMPION

	var active_board = get_active_board()
	if active_board:
		active_board.clear_highlights()
		active_board.update_champion_positions()
	_update_ui()


func _ai_handle_mind_control(champion_id: String) -> void:
	"""Let the AI handle mind control of an enemy champion."""
	if ai_controller:
		ai_controller.handle_mind_control(champion_id, game_controller.get_game_state())


# === Discard Selection Handling (From the Sky, etc.) ===

func _on_discard_selection_required(player_id: int, caster_id: String, damage_per_card: int) -> void:
	"""Handle request to select cards to discard."""
	print("Discard selection required for player %d (caster: %s, %d damage per card)" % [player_id, caster_id, damage_per_card])

	if player_id != 1:
		# AI handles its own discard selection
		_ai_handle_discard_selection(caster_id, damage_per_card)
		return

	# Set up discard selection mode
	_discard_selection_active = true
	_discard_selected_cards = []
	_discard_caster_id = caster_id
	input_mode = InputMode.SELECT_DISCARD

	# Create confirm button
	_create_discard_confirm_button()

	# Update hand to show ALL cards as selectable (multi-select mode)
	hand_ui.set_multi_select_mode(true)

	# Refresh the hand display so all cards appear playable
	var state := game_controller.get_game_state()
	var hand := state.get_hand(1)
	var mana := state.get_mana(1)
	hand_ui.update_hand(hand, mana)  # This will now mark all cards playable due to multi_select_mode

	hud.show_message("Select cards to discard (click Confirm when done)", 10.0)


func _create_discard_confirm_button() -> void:
	"""Create the confirm button for discard selection."""
	if _discard_confirm_button != null:
		_discard_confirm_button.queue_free()

	_discard_confirm_button = Button.new()
	_discard_confirm_button.text = "Confirm Discard (0 cards)"
	_discard_confirm_button.custom_minimum_size = Vector2(200, 40)

	# Position at bottom center
	_discard_confirm_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_discard_confirm_button.offset_left = -100
	_discard_confirm_button.offset_right = 100
	_discard_confirm_button.offset_top = -120
	_discard_confirm_button.offset_bottom = -80

	# Style the button
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.5, 0.3)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.7, 0.4)
	style.set_corner_radius_all(6)
	_discard_confirm_button.add_theme_stylebox_override("normal", style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.6, 0.35)
	hover_style.set_border_width_all(2)
	hover_style.border_color = Color(0.4, 0.8, 0.5)
	hover_style.set_corner_radius_all(6)
	_discard_confirm_button.add_theme_stylebox_override("hover", hover_style)

	_discard_confirm_button.pressed.connect(_on_discard_confirm_pressed)

	hud.add_child(_discard_confirm_button)


func _on_discard_card_toggled(card_name: String, selected: bool) -> void:
	"""Handle toggling a card for discard selection (From the Sky or Introspection)."""
	if _discard_choice_active:
		# Introspection-style: choose exactly N cards
		if selected:
			if card_name not in _discard_choice_selected:
				# Enforce max selection
				if _discard_choice_selected.size() >= _discard_choice_count:
					# Deselect the oldest selection to replace
					hand_ui.multi_selected_cards.erase(card_name)
					return
				_discard_choice_selected.append(card_name)
		else:
			_discard_choice_selected.erase(card_name)

		if _discard_choice_confirm_button:
			var count := _discard_choice_selected.size()
			_discard_choice_confirm_button.text = "Discard (%d/%d)" % [count, _discard_choice_count]
			_discard_choice_confirm_button.disabled = count != _discard_choice_count
		return

	if not _discard_selection_active:
		return

	if selected:
		if card_name not in _discard_selected_cards:
			_discard_selected_cards.append(card_name)
	else:
		_discard_selected_cards.erase(card_name)

	# Update button text
	if _discard_confirm_button:
		var damage := _discard_selected_cards.size() * 2
		_discard_confirm_button.text = "Confirm Discard (%d cards = %d damage)" % [_discard_selected_cards.size(), damage]


func _on_discard_confirm_pressed() -> void:
	"""Handle confirming discard selection."""
	print("Confirming discard of %d cards: %s" % [_discard_selected_cards.size(), _discard_selected_cards])

	# Complete the effect
	var result := game_controller.effect_processor.complete_discard_selection(_discard_selected_cards)
	print("Discard result: %s" % result)

	# Clean up UI
	_cleanup_discard_selection()

	# Check for deaths and update UI
	_update_after_action()


func _cleanup_discard_selection() -> void:
	"""Clean up discard selection state and UI."""
	_discard_selection_active = false
	_discard_selected_cards = []
	_discard_caster_id = ""
	input_mode = InputMode.SELECT_CHAMPION

	if _discard_confirm_button:
		_discard_confirm_button.queue_free()
		_discard_confirm_button = null

	hand_ui.set_multi_select_mode(false)
	hand_ui.clear_selection()


func _ai_handle_discard_selection(caster_id: String, damage_per_card: int) -> void:
	"""AI decides which cards to discard."""
	var state := game_controller.get_game_state()
	var caster := state.get_champion(caster_id)
	if caster == null:
		return

	var hand := state.get_hand(caster.owner_id)

	# AI strategy: discard cards for dead champions first, then lowest cost cards
	# For now, simple strategy: discard up to 3 cards if we have enemies to hit
	var opp_id := 1 if caster.owner_id == 2 else 2
	var living_enemies := state.get_living_champions(opp_id)

	if living_enemies.is_empty():
		# No enemies, don't discard
		game_controller.effect_processor.complete_discard_selection([])
		return

	# Discard up to half the hand (simple strategy)
	var to_discard: Array[String] = []
	var max_discard := mini(hand.size(), 3)

	for i in range(max_discard):
		if i < hand.size():
			to_discard.append(hand[i])

	game_controller.effect_processor.complete_discard_selection(to_discard)
	_update_after_action()


# === Intel Choice Handling ===

func _on_intel_choice_required(caster_owner_id: int, own_top_card: String, opp_top_card: String) -> void:
	"""Handle Intel card — show top cards and let player choose top/bottom."""
	print("Intel choice required for player %d (own: %s, opp: %s)" % [caster_owner_id, own_top_card, opp_top_card])

	_intel_own_card = own_top_card
	_intel_opp_card = opp_top_card
	_intel_own_to_bottom = false
	_intel_opp_to_bottom = false

	if caster_owner_id != 1 or ai_vs_ai_mode:
		# AI handles this
		_ai_handle_intel(caster_owner_id, own_top_card, opp_top_card)
		return

	# Human player — show Intel UI overlay
	input_mode = InputMode.INTEL_CHOICE
	_create_intel_panel()
	hud.show_message("INTEL: Choose to keep on top or put on bottom", 10.0)


func _create_intel_panel() -> void:
	"""Create the Intel choice overlay panel."""
	if _intel_panel:
		_intel_panel.queue_free()

	var card_scene := preload("res://scenes/game/cards/card_visual.tscn")

	# Overlay background
	_intel_panel = Panel.new()
	_intel_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.7)
	_intel_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(_intel_panel)

	# Title
	var title := Label.new()
	title.text = "INTEL — Reveal Top Cards"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 40
	title.offset_left = -200
	title.offset_right = 200
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	_intel_panel.add_child(title)

	var center_y := 250.0
	var card_spacing := 250.0

	# === Own card section ===
	if not _intel_own_card.is_empty():
		var own_label := Label.new()
		own_label.text = "Your Deck"
		own_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		own_label.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - card_spacing - 70, center_y - 40)
		own_label.size = Vector2(140, 30)
		own_label.add_theme_font_size_override("font_size", 16)
		own_label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
		_intel_panel.add_child(own_label)

		var own_card: CardVisual = card_scene.instantiate()
		own_card.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - card_spacing - 70, center_y)
		_intel_panel.add_child(own_card)
		own_card.setup(_intel_own_card, false)

		var own_btn := Button.new()
		own_btn.text = "Keep on Top"
		own_btn.custom_minimum_size = Vector2(140, 35)
		own_btn.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - card_spacing - 70, center_y + 195)
		own_btn.pressed.connect(_toggle_intel_own.bind(own_btn))
		_style_intel_button(own_btn, false)
		_intel_panel.add_child(own_btn)
	else:
		var empty_label := Label.new()
		empty_label.text = "Your Deck\n(Empty)"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - card_spacing - 70, center_y + 60)
		empty_label.size = Vector2(140, 60)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_intel_panel.add_child(empty_label)

	# === Opponent card section ===
	if not _intel_opp_card.is_empty():
		var opp_label := Label.new()
		opp_label.text = "Opponent's Deck"
		opp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		opp_label.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 + card_spacing - 70, center_y - 40)
		opp_label.size = Vector2(140, 30)
		opp_label.add_theme_font_size_override("font_size", 16)
		opp_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		_intel_panel.add_child(opp_label)

		var opp_card: CardVisual = card_scene.instantiate()
		opp_card.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 + card_spacing - 70, center_y)
		_intel_panel.add_child(opp_card)
		opp_card.setup(_intel_opp_card, false)

		var opp_btn := Button.new()
		opp_btn.text = "Keep on Top"
		opp_btn.custom_minimum_size = Vector2(140, 35)
		opp_btn.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 + card_spacing - 70, center_y + 195)
		opp_btn.pressed.connect(_toggle_intel_opp.bind(opp_btn))
		_style_intel_button(opp_btn, false)
		_intel_panel.add_child(opp_btn)
	else:
		var empty_label := Label.new()
		empty_label.text = "Opponent's Deck\n(Empty)"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 + card_spacing - 70, center_y + 60)
		empty_label.size = Vector2(140, 60)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_intel_panel.add_child(empty_label)

	# === Confirm button ===
	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm"
	confirm_btn.custom_minimum_size = Vector2(180, 45)
	confirm_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	confirm_btn.offset_left = -90
	confirm_btn.offset_right = 90
	confirm_btn.offset_top = -80
	confirm_btn.offset_bottom = -35
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.5, 0.3)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.7, 0.4)
	style.set_corner_radius_all(6)
	confirm_btn.add_theme_stylebox_override("normal", style)
	confirm_btn.add_theme_font_size_override("font_size", 18)
	confirm_btn.pressed.connect(_on_intel_confirm)
	_intel_panel.add_child(confirm_btn)


func _style_intel_button(btn: Button, is_bottom: bool) -> void:
	"""Style an Intel toggle button based on current state."""
	var style := StyleBoxFlat.new()
	if is_bottom:
		style.bg_color = Color(0.6, 0.2, 0.2)
		style.border_color = Color(0.8, 0.3, 0.3)
	else:
		style.bg_color = Color(0.2, 0.3, 0.5)
		style.border_color = Color(0.3, 0.5, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)


func _toggle_intel_own(btn: Button) -> void:
	_intel_own_to_bottom = not _intel_own_to_bottom
	btn.text = "Put on Bottom" if _intel_own_to_bottom else "Keep on Top"
	_style_intel_button(btn, _intel_own_to_bottom)


func _toggle_intel_opp(btn: Button) -> void:
	_intel_opp_to_bottom = not _intel_opp_to_bottom
	btn.text = "Put on Bottom" if _intel_opp_to_bottom else "Keep on Top"
	_style_intel_button(btn, _intel_opp_to_bottom)


func _on_intel_confirm() -> void:
	"""Finalize Intel choice."""
	print("Intel confirm: own_to_bottom=%s, opp_to_bottom=%s" % [_intel_own_to_bottom, _intel_opp_to_bottom])
	game_controller.effect_processor.complete_intel_choice(_intel_own_to_bottom, _intel_opp_to_bottom)
	_cleanup_intel()
	_update_after_action()


func _cleanup_intel() -> void:
	"""Clean up Intel UI state."""
	if _intel_panel:
		_intel_panel.queue_free()
		_intel_panel = null
	_intel_own_card = ""
	_intel_opp_card = ""
	_intel_own_to_bottom = false
	_intel_opp_to_bottom = false
	input_mode = InputMode.SELECT_CHAMPION


func _ai_handle_intel(caster_owner_id: int, own_card: String, opp_card: String) -> void:
	"""AI decides what to do with Intel cards."""
	var ai := ai_controller
	if caster_owner_id == 1 and ai_player1:
		ai = ai_player1

	var choice: Dictionary = ai.evaluate_intel_choice(own_card, opp_card)
	game_controller.effect_processor.complete_intel_choice(
		choice.get("own_to_bottom", false),
		choice.get("opp_to_bottom", false)
	)
	_update_after_action()


# === X Value Choice Handling ===

func _on_x_value_required(player_id: int, card_name: String, min_val: int, max_val: int) -> void:
	"""Handle X-cost card — let player choose how much extra mana to spend."""
	print("X value required for player %d, card %s (range %d-%d)" % [player_id, card_name, min_val, max_val])

	_x_card_name = card_name
	_x_max_value = max_val
	_x_chosen_value = 0

	if player_id != 1 or ai_vs_ai_mode:
		_ai_handle_x_value(player_id, card_name, max_val)
		return

	input_mode = InputMode.X_VALUE_CHOICE
	_create_x_value_panel(card_name, max_val)
	hud.show_message("Choose X value for %s" % card_name, 10.0)


func _create_x_value_panel(card_name: String, max_val: int) -> void:
	"""Create the X value selection overlay."""
	if _x_value_panel:
		_x_value_panel.queue_free()

	_x_value_panel = Panel.new()
	_x_value_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.7)
	_x_value_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(_x_value_panel)

	# Title
	var title := Label.new()
	title.text = "%s — Choose X Value" % card_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 80
	title.offset_left = -250
	title.offset_right = 250
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	_x_value_panel.add_child(title)

	# Description
	var desc := Label.new()
	desc.text = "Spend additional mana to increase X.\nOpponents cannot cast spells costing X or less."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	desc.offset_top = 120
	desc.offset_left = -250
	desc.offset_right = 250
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_x_value_panel.add_child(desc)

	# Value display
	var value_label := Label.new()
	value_label.name = "XValueLabel"
	value_label.text = "X = 0"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.set_anchors_preset(Control.PRESET_CENTER)
	value_label.offset_top = -40
	value_label.offset_left = -100
	value_label.offset_right = 100
	value_label.add_theme_font_size_override("font_size", 36)
	value_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	_x_value_panel.add_child(value_label)

	# Mana cost display
	var mana_label := Label.new()
	mana_label.name = "XManaLabel"
	mana_label.text = "Additional mana: 0"
	mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_label.set_anchors_preset(Control.PRESET_CENTER)
	mana_label.offset_top = 10
	mana_label.offset_left = -100
	mana_label.offset_right = 100
	mana_label.add_theme_font_size_override("font_size", 16)
	mana_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.8))
	_x_value_panel.add_child(mana_label)

	# Buttons for each value (0 to max)
	var btn_container := HBoxContainer.new()
	btn_container.set_anchors_preset(Control.PRESET_CENTER)
	btn_container.offset_top = 50
	btn_container.offset_bottom = 90
	btn_container.offset_left = -((max_val + 1) * 25)
	btn_container.offset_right = ((max_val + 1) * 25)
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 8)
	_x_value_panel.add_child(btn_container)

	for i in range(max_val + 1):
		var btn := Button.new()
		btn.text = str(i)
		btn.custom_minimum_size = Vector2(42, 42)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.3, 0.5) if i == 0 else Color(0.15, 0.2, 0.35)
		style.set_border_width_all(2)
		style.border_color = Color(0.3, 0.5, 0.7) if i == 0 else Color(0.2, 0.3, 0.5)
		style.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.pressed.connect(_on_x_value_button.bind(i, btn_container))
		btn_container.add_child(btn)

	# Confirm button
	var confirm := Button.new()
	confirm.text = "Confirm (X = 0)"
	confirm.name = "XConfirmBtn"
	confirm.custom_minimum_size = Vector2(180, 45)
	confirm.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	confirm.offset_left = -90
	confirm.offset_right = 90
	confirm.offset_top = -80
	confirm.offset_bottom = -35
	var confirm_style := StyleBoxFlat.new()
	confirm_style.bg_color = Color(0.2, 0.5, 0.3)
	confirm_style.set_border_width_all(2)
	confirm_style.border_color = Color(0.3, 0.7, 0.4)
	confirm_style.set_corner_radius_all(6)
	confirm.add_theme_stylebox_override("normal", confirm_style)
	confirm.add_theme_font_size_override("font_size", 18)
	confirm.pressed.connect(_on_x_value_confirm)
	_x_value_panel.add_child(confirm)


func _on_x_value_button(value: int, container: HBoxContainer) -> void:
	"""Handle clicking an X value button."""
	_x_chosen_value = value

	# Update button highlights
	for i in range(container.get_child_count()):
		var btn: Button = container.get_child(i)
		var style := StyleBoxFlat.new()
		if i == value:
			style.bg_color = Color(0.3, 0.5, 0.7)
			style.border_color = Color(0.4, 0.7, 1.0)
		else:
			style.bg_color = Color(0.15, 0.2, 0.35)
			style.border_color = Color(0.2, 0.3, 0.5)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)

	# Update labels
	var value_label: Label = _x_value_panel.get_node("XValueLabel")
	if value_label:
		value_label.text = "X = %d" % value
	var mana_label: Label = _x_value_panel.get_node("XManaLabel")
	if mana_label:
		mana_label.text = "Additional mana: %d" % value
	var confirm_btn: Button = _x_value_panel.get_node("XConfirmBtn")
	if confirm_btn:
		confirm_btn.text = "Confirm (X = %d)" % value


func _on_x_value_confirm() -> void:
	"""Finalize X value choice."""
	print("X value confirmed: %d for %s" % [_x_chosen_value, _x_card_name])
	game_controller.effect_processor.complete_x_selection(_x_chosen_value)
	_cleanup_x_value()
	_update_after_action()


func _cleanup_x_value() -> void:
	"""Clean up X value UI."""
	if _x_value_panel:
		_x_value_panel.queue_free()
		_x_value_panel = null
	_x_chosen_value = 0
	_x_max_value = 0
	_x_card_name = ""
	input_mode = InputMode.SELECT_CHAMPION


# === Discard Choice Handling (Introspection) ===

func _on_discard_choice_required(player_id: int, count: int) -> void:
	"""Handle Introspection-style discard — player must choose exactly N cards to discard."""
	print("Discard choice required: player %d must discard %d cards" % [player_id, count])

	if player_id != 1 or ai_vs_ai_mode:
		_ai_handle_discard_choice(player_id, count)
		return

	_discard_choice_active = true
	_discard_choice_count = count
	_discard_choice_selected = []
	input_mode = InputMode.SELECT_DISCARD

	# Create confirm button
	if _discard_choice_confirm_button:
		_discard_choice_confirm_button.queue_free()
	_discard_choice_confirm_button = Button.new()
	_discard_choice_confirm_button.text = "Discard (0/%d)" % count
	_discard_choice_confirm_button.disabled = true
	_discard_choice_confirm_button.custom_minimum_size = Vector2(200, 40)
	_discard_choice_confirm_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_discard_choice_confirm_button.offset_left = -100
	_discard_choice_confirm_button.offset_right = 100
	_discard_choice_confirm_button.offset_top = -120
	_discard_choice_confirm_button.offset_bottom = -80
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.2, 0.2)
	style.set_border_width_all(2)
	style.border_color = Color(0.7, 0.3, 0.3)
	style.set_corner_radius_all(6)
	_discard_choice_confirm_button.add_theme_stylebox_override("normal", style)
	_discard_choice_confirm_button.add_theme_font_size_override("font_size", 16)
	_discard_choice_confirm_button.pressed.connect(_on_discard_choice_confirm)
	add_child(_discard_choice_confirm_button)

	hand_ui.set_multi_select_mode(true)
	var state := game_controller.get_game_state()
	var hand := state.get_hand(1)
	var mana := state.get_mana(1)
	hand_ui.update_hand(hand, mana)

	hud.show_message("Select %d cards to discard" % count, 10.0)


func _on_discard_choice_confirm() -> void:
	"""Finalize discard choice."""
	if _discard_choice_selected.size() != _discard_choice_count:
		return
	print("Discard choice confirmed: %s" % str(_discard_choice_selected))
	game_controller.effect_processor.complete_discard_choice(_discard_choice_selected)
	_cleanup_discard_choice()
	_update_after_action()


func _cleanup_discard_choice() -> void:
	"""Clean up discard choice UI."""
	_discard_choice_active = false
	_discard_choice_count = 0
	_discard_choice_selected = []
	if _discard_choice_confirm_button:
		_discard_choice_confirm_button.queue_free()
		_discard_choice_confirm_button = null
	hand_ui.set_multi_select_mode(false)
	hand_ui.clear_selection()
	input_mode = InputMode.SELECT_CHAMPION


func _ai_handle_discard_choice(player_id: int, count: int) -> void:
	"""AI chooses which cards to discard — pick least useful."""
	var state := game_controller.get_game_state()
	var hand := state.get_hand(player_id)
	if hand.is_empty():
		game_controller.effect_processor.complete_discard_choice([])
		return

	# Score each card — lower score = discard first
	var scored: Array = []
	for card_name: String in hand:
		var card_data := CardDatabase.get_card(card_name)
		var card_cost: int = card_data.get("cost", 0)
		var card_type: String = str(card_data.get("type", "")).to_lower()
		var score := 5  # Base
		# Response cards are valuable to keep
		if card_type == "response":
			score += 3
		# Low cost cards are more castable
		if card_cost <= 1:
			score += 2
		elif card_cost >= 4:
			score -= 2
		scored.append({"name": card_name, "score": score})

	# Sort ascending — discard the lowest scored
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] < b["score"])

	var to_discard: Array[String] = []
	for i in range(mini(count, scored.size())):
		to_discard.append(scored[i]["name"])

	game_controller.effect_processor.complete_discard_choice(to_discard)
	_update_after_action()


func _ai_handle_x_value(player_id: int, card_name: String, max_val: int) -> void:
	"""AI decides X value — maximize disruption by spending all available mana."""
	var x_value := max_val  # AI spends maximum for maximum effect
	print("AI choosing X = %d for %s" % [x_value, card_name])
	game_controller.effect_processor.complete_x_selection(x_value)
	_update_after_action()


# === Response Slot Handling ===

func _on_response_slot_clicked() -> void:
	"""Handle clicking the empty response slot - show hint."""
	hud.show_message("Click a Response card to place it here", 2.0)


func _on_response_card_removed(card_name: String) -> void:
	"""Handle removing a card from the response slot - return to hand."""
	print("Game: _on_response_card_removed called for: %s" % card_name)
	var state := game_controller.get_game_state()
	var returned := state.clear_response_slot(1)
	print("Game: clear_response_slot returned: %s" % returned)
	if not returned.is_empty():
		hud.show_message("Returned " + returned + " to hand", 1.5)
		print("Game: Card returned to hand successfully")
		_update_ui()
		response_slot.update_slot()
	else:
		print("Game: WARNING - clear_response_slot returned empty (card may have been auto-played by trigger)")


func _place_card_in_response_slot(card_name: String) -> void:
	"""Place a response card in the response slot."""
	print("_place_card_in_response_slot called with: %s" % card_name)

	if game_controller == null:
		print("  ERROR: game_controller is null!")
		return

	var state := game_controller.get_game_state()
	if state == null:
		print("  ERROR: game_state is null!")
		return

	# Check if it's actually a response card
	var card_data := CardDatabase.get_card(card_name)
	print("  Card data: %s" % card_data)
	if card_data.get("type", "") != "Response":
		hud.show_message("Only Response cards can be placed in the slot", 1.5)
		print("  Card is not a Response type")
		return

	# Check if card is in hand
	var hand := state.get_hand(1)
	print("  Hand contents: %s" % hand)
	if card_name not in hand:
		hud.show_message("Card not in hand", 1.5)
		print("  Card not found in hand!")
		return

	# Place the card in the slot
	print("  Attempting to set response slot...")
	if state.set_response_slot(1, card_name):
		var trigger: String = card_data.get("trigger", "")
		hud.show_message("Response ready: " + card_name + " (triggers on " + trigger + ")", 2.0)
		print("  SUCCESS: Card placed in slot")
		_update_ui()
		response_slot.update_slot()
	else:
		hud.show_message("Failed to place card in slot", 1.5)
		print("  FAILED: set_response_slot returned false")


func _update_response_slot() -> void:
	"""Update the response slot display."""
	if response_slot:
		response_slot.update_slot()
