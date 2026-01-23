extends Node
## Main scene - entry point for the game
## Press F9 to run AI vs AI tests

var status_label: Label = null
var ai_test_running: bool = false
var splash_screen: SplashScreen = null
var character_select: CharacterSelect = null
var database_ready: bool = false


func _ready() -> void:
	print("Main: _ready called")

	# Find StatusLabel with multiple fallback methods
	_find_status_label()

	_connect_signals()
	_initialize()


func _find_status_label() -> void:
	"""Find the StatusLabel node using multiple methods."""
	# Method 1: Direct path
	status_label = get_node_or_null("UI/StatusLabel")
	if status_label:
		print("Main: Found StatusLabel via UI/StatusLabel")
		return

	# Method 2: Find UI first, then StatusLabel
	var ui = get_node_or_null("UI")
	if ui:
		print("Main: Found UI node")
		status_label = ui.get_node_or_null("StatusLabel")
		if status_label:
			print("Main: Found StatusLabel as child of UI")
			return

		# Method 3: Search all children of UI
		for child in ui.get_children():
			print("Main: UI child: %s (%s)" % [child.name, child.get_class()])
			if child.name == "StatusLabel" or child is Label:
				if child.name == "StatusLabel":
					status_label = child
					print("Main: Found StatusLabel by searching UI children")
					return
	else:
		print("Main: UI node not found!")
		# Print all children of Main
		print("Main: Children of Main node:")
		for child in get_children():
			print("  - %s (%s)" % [child.name, child.get_class()])

	push_error("Main: Could not find StatusLabel!")


func _set_status(text: String) -> void:
	"""Safely set status label text."""
	if status_label and is_instance_valid(status_label):
		status_label.text = text
	else:
		print("Main: [STATUS] %s" % text)


func _connect_signals() -> void:
	print("Main: Connecting signals")
	CardDatabase.database_loaded.connect(_on_database_loaded)
	CardDatabase.database_load_failed.connect(_on_database_load_failed)
	GameManager.state_changed.connect(_on_game_state_changed)
	print("Main: Signals connected")


func _initialize() -> void:
	print("Main: _initialize called, CardDatabase.is_loaded = %s" % CardDatabase.is_loaded)
	_set_status("Initializing...")

	# Check if database already loaded (shouldn't happen with deferred loading, but just in case)
	if CardDatabase.is_loaded:
		print("Main: Database already loaded, calling _on_database_loaded directly")
		_on_database_loaded()


func _on_database_loaded() -> void:
	print("Main: _on_database_loaded called!")

	var card_count = CardDatabase.get_all_card_names().size()
	var champion_count = CardDatabase.get_all_champion_names().size()
	_set_status("Database loaded! %d cards, %d champions" % [card_count, champion_count])

	# Print some debug info
	print("=== Arena Game Initialized ===")
	print("  Cards: %d" % card_count)
	print("  Champions: %d" % champion_count)
	for champion_name in CardDatabase.get_all_champion_names():
		var deck_size := CardDatabase.get_deck_size_for_champion(champion_name)
		var stats := CardDatabase.get_champion_stats(champion_name)
		print("  %s: %d cards in deck, stats=%s" % [champion_name, deck_size, stats])

	database_ready = true

	# Show splash screen
	print("Main: Showing splash screen...")
	_show_splash_screen()


func _show_splash_screen() -> void:
	"""Show the splash screen with mode selection."""
	# Hide the loading UI
	var ui: Node = get_node_or_null("UI")
	if ui:
		ui.visible = false

	# Load and add splash screen
	var splash_scene: PackedScene = preload("res://scenes/main/splash_screen.tscn")
	splash_screen = splash_scene.instantiate()
	splash_screen.mode_selected.connect(_on_mode_selected)
	add_child(splash_screen)
	print("Main: Splash screen displayed")


func _on_mode_selected(use_3d: bool) -> void:
	"""Handle mode selection from splash screen."""
	print("Main: Mode selected - 3D: %s" % use_3d)

	# Remove splash screen
	if splash_screen and is_instance_valid(splash_screen):
		splash_screen.queue_free()
		splash_screen = null

	# Show character selection screen
	_show_character_select(use_3d)


func _show_character_select(use_3d: bool) -> void:
	"""Show the character selection screen."""
	print("Main: Showing character select screen...")
	var char_select_scene: PackedScene = preload("res://scenes/main/character_select.tscn")
	character_select = char_select_scene.instantiate()
	character_select.use_3d_mode = use_3d
	character_select.selection_complete.connect(_on_selection_complete)
	add_child(character_select)
	print("Main: Character select displayed")


func _on_selection_complete(p1_champions: Array, p2_champions: Array, use_3d: bool) -> void:
	"""Handle champion selection complete - start the game."""
	print("Main: Selection complete - P1: %s, P2: %s, 3D: %s" % [p1_champions, p2_champions, use_3d])

	# Remove character select
	if character_select and is_instance_valid(character_select):
		character_select.queue_free()
		character_select = null

	# Start game with selected champions
	_start_game_with_champions(p1_champions, p2_champions, use_3d)


func _start_game(use_3d: bool = false) -> void:
	"""Start game with default champions (legacy, used by F10 AI test)."""
	_start_game_with_champions(["Brute", "Ranger"], ["Berserker", "Shaman"], use_3d)


func _start_game_with_champions(p1_champions: Array, p2_champions: Array, use_3d: bool = false) -> void:
	"""Start the game with selected champions."""
	# Hide the loading UI
	var ui: Node = get_node_or_null("UI")
	if ui:
		ui.visible = false

	# Load and add game scene based on mode
	if use_3d:
		print("Main: Loading 3D game scene...")
		var game_scene: PackedScene = preload("res://scenes/game/game_3d.tscn")
		var game: Node = game_scene.instantiate()
		game.set_meta("p1_champions", p1_champions)
		game.set_meta("p2_champions", p2_champions)
		add_child(game)
		print("Main: 3D Game scene added with champions P1:%s P2:%s" % [p1_champions, p2_champions])
	else:
		print("Main: Loading 2D game scene...")
		var game_scene: PackedScene = preload("res://scenes/game/game.tscn")
		var game: Node = game_scene.instantiate()
		game.set_meta("p1_champions", p1_champions)
		game.set_meta("p2_champions", p2_champions)
		add_child(game)
		print("Main: 2D Game scene added with champions P1:%s P2:%s" % [p1_champions, p2_champions])


func _on_database_load_failed(error: String) -> void:
	_set_status("ERROR: " + error)
	push_error("Database load failed: " + error)


func _on_game_state_changed(old_state: GameManager.ManagerState, new_state: GameManager.ManagerState) -> void:
	print("Game state: %s -> %s" % [
		GameManager.ManagerState.keys()[old_state],
		GameManager.ManagerState.keys()[new_state]
	])

	match new_state:
		GameManager.ManagerState.MAIN_MENU:
			_set_status("Main Menu (not yet implemented)")
		GameManager.ManagerState.CHARACTER_SELECT:
			_set_status("Character Select (not yet implemented)")
		GameManager.ManagerState.PLAYING:
			_set_status("Playing...")
		GameManager.ManagerState.GAME_OVER:
			_set_status("Game Over")


func _input(event: InputEvent) -> void:
	# F9 - Run AI vs AI tests (headless, fast)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		if not ai_test_running:
			_run_ai_tests()

	# F10 - Start visual AI vs AI game
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		_start_ai_vs_ai_game()


func _run_ai_tests() -> void:
	"""Run AI vs AI test suite."""
	if ai_test_running:
		print("Tests already running!")
		return

	ai_test_running = true
	print("")
	print("========================================")
	print("   AI vs AI Test Suite - Press F9")
	print("========================================")
	print("")

	# Run tests in background
	var runner := AIvsAIRunner.new()

	# Configure matches
	var p1_champs: Array[String] = ["Brute", "Ranger"]
	var p2_champs: Array[String] = ["Berserker", "Shaman"]

	print("Running 5 AI vs AI matches...")
	print("P1: %s vs P2: %s" % [p1_champs, p2_champs])
	print("")

	var results := runner.run_matches(
		5,  # Number of matches
		p1_champs,
		p2_champs,
		AIController.Difficulty.MEDIUM,
		AIController.Difficulty.MEDIUM
	)

	# Output results
	print("")
	print("========================================")
	print("   TEST RESULTS")
	print("========================================")
	print("P1 Wins: %d" % results.get("p1_wins", 0))
	print("P2 Wins: %d" % results.get("p2_wins", 0))
	print("Draws: %d" % results.get("draws", 0))
	print("Errors: %d" % results.get("errors", 0))
	print("")

	var bugs: Array = results.get("bugs", [])
	if bugs.size() > 0:
		print("BUGS FOUND: %d" % bugs.size())
		for bug: Dictionary in bugs:
			print("  - [%s] %s" % [bug.get("type", "?"), bug.get("description", "?")])
			print("    Context: %s" % str(bug.get("context", {})))
	else:
		print("No bugs detected!")

	# Write to file
	_write_test_results(runner)

	ai_test_running = false
	print("")
	print("Tests complete! Results saved to user://ai_test_results.log")
	print("Press F9 to run again.")


func _write_test_results(runner: AIvsAIRunner) -> void:
	"""Write test results to log file."""
	var file := FileAccess.open("user://ai_test_results.log", FileAccess.WRITE)
	if file:
		file.store_string("Arena AI vs AI Test Results\n")
		file.store_string("Generated: %s\n" % Time.get_datetime_string_from_system())
		file.store_string("=".repeat(50) + "\n\n")
		file.store_string(runner.get_full_log())
		file.close()


func _start_ai_vs_ai_game() -> void:
	"""Start a visual AI vs AI game."""
	print("")
	print("========================================")
	print("   Starting AI vs AI Visual Game")
	print("   (Watch the AI play!)")
	print("========================================")
	print("")

	# Remove existing game if any
	for child in get_children():
		if child is GameScene:
			child.queue_free()

	# Hide loading UI
	var ui = get_node_or_null("UI")
	if ui:
		ui.visible = false

	# Load game scene with AI vs AI flag
	var game_scene := preload("res://scenes/game/game.tscn")
	var game: GameScene = game_scene.instantiate()
	game.set_meta("ai_vs_ai", true)  # Flag to enable AI for player 1
	add_child(game)
	print("AI vs AI game started - watch the battle!")
