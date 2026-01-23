extends Control
## AI vs AI Test Application - Simple robust version

const VisualizationPanelScript = preload("res://scripts/testing/ui/visualization_panel.gd")
const ReplayPanelScript = preload("res://scripts/testing/ui/replay_panel.gd")

var output_text: RichTextLabel
var progress_bar: ProgressBar
var progress_label: Label
var start_button: Button
var matches_input: SpinBox
var seed_input: SpinBox
var status_label: Label

# Tab system
var main_tab_bar: TabBar
var main_content_stack: Control
var output_panel: Control
var viz_panel: Control  # VisualizationPanel
var replay_panel: Control  # ReplayPanel

# Match results for replay
var match_results_list: Array[MatchResult] = []

var orchestrator: TestOrchestrator
var test_running: bool = false
var current_report: SessionReport


func _ready() -> void:
	var headless := DisplayServer.get_name() == "headless"

	if not headless:
		# IMPORTANT: Disable project's content scaling so UI renders at native size
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		get_tree().root.content_scale_size = Vector2i.ZERO

		# Set window size and title
		get_window().size = Vector2i(1000, 750)
		get_window().min_size = Vector2i(800, 600)
		get_window().title = "Arena AI vs AI Tester"

		# Center window on screen
		var screen_size := DisplayServer.screen_get_size()
		var window_size := get_window().size
		get_window().position = (screen_size - window_size) / 2

		# Wait a frame for window to initialize
		await get_tree().process_frame

		_build_ui()

	# Wait for CardDatabase
	if not CardDatabase.is_loaded:
		if status_label:
			status_label.text = "Loading card database..."
		await CardDatabase.database_loaded

	if headless:
		print("=== Arena AI vs AI Tester (Headless Mode) ===")
		print("CardDatabase loaded with %d cards." % CardDatabase.get_all_card_names().size())
		_run_headless_tests()
	else:
		status_label.text = "Ready - Click Start to begin testing"
		_log("[color=green]Ready![/color] CardDatabase loaded with %d cards." % CardDatabase.get_all_card_names().size())
		_log("Set number of matches and click Start.")


func _build_ui() -> void:
	# Clear any existing children
	for child in get_children():
		child.queue_free()

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.18)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	# Main VBox with margins
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(main_vbox)

	# Title
	var title := Label.new()
	title.text = "Arena AI vs AI Tester"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color.WHITE)
	main_vbox.add_child(title)

	# Separator
	main_vbox.add_child(HSeparator.new())

	# Config row
	var config_hbox := HBoxContainer.new()
	config_hbox.add_theme_constant_override("separation", 15)
	main_vbox.add_child(config_hbox)

	var lbl1 := Label.new()
	lbl1.text = "Matches:"
	lbl1.add_theme_font_size_override("font_size", 18)
	config_hbox.add_child(lbl1)

	matches_input = SpinBox.new()
	matches_input.min_value = 1
	matches_input.max_value = 500
	matches_input.value = 20
	matches_input.custom_minimum_size.x = 100
	config_hbox.add_child(matches_input)

	var lbl2 := Label.new()
	lbl2.text = "   Seed (0=random):"
	lbl2.add_theme_font_size_override("font_size", 18)
	config_hbox.add_child(lbl2)

	seed_input = SpinBox.new()
	seed_input.min_value = 0
	seed_input.max_value = 999999999
	seed_input.value = 0
	seed_input.custom_minimum_size.x = 150
	config_hbox.add_child(seed_input)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	config_hbox.add_child(spacer)

	start_button = Button.new()
	start_button.text = "  START TESTS  "
	start_button.custom_minimum_size = Vector2(150, 40)
	start_button.add_theme_font_size_override("font_size", 18)
	start_button.pressed.connect(_on_start_pressed)
	config_hbox.add_child(start_button)

	var export_btn := Button.new()
	export_btn.text = "Export JSON"
	export_btn.custom_minimum_size = Vector2(120, 40)
	export_btn.pressed.connect(_on_export_pressed)
	config_hbox.add_child(export_btn)

	# Progress row
	var progress_hbox := HBoxContainer.new()
	progress_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(progress_hbox)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 30
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_hbox.add_child(progress_bar)

	progress_label = Label.new()
	progress_label.text = "0 / 0"
	progress_label.custom_minimum_size.x = 100
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_label.add_theme_font_size_override("font_size", 18)
	progress_hbox.add_child(progress_label)

	# Status
	status_label = Label.new()
	status_label.text = "Initializing..."
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	main_vbox.add_child(status_label)

	# Separator
	main_vbox.add_child(HSeparator.new())

	# Main tab bar for switching between Output and Visualizations
	main_tab_bar = TabBar.new()
	main_tab_bar.add_tab("Output")
	main_tab_bar.add_tab("Charts")
	main_tab_bar.add_tab("Replay")
	main_tab_bar.tab_changed.connect(_on_main_tab_changed)
	main_tab_bar.add_theme_font_size_override("font_size", 16)
	main_vbox.add_child(main_tab_bar)

	# Content stack (holds different views)
	main_content_stack = Control.new()
	main_content_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(main_content_stack)

	# Output panel (tab 0)
	output_panel = PanelContainer.new()
	output_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	output_panel.add_theme_stylebox_override("panel", style)
	main_content_stack.add_child(output_panel)

	output_text = RichTextLabel.new()
	output_text.bbcode_enabled = true
	output_text.scroll_following = true
	output_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output_text.add_theme_font_size_override("normal_font_size", 16)
	output_text.add_theme_font_size_override("mono_font_size", 16)
	output_text.add_theme_font_size_override("bold_font_size", 16)
	output_panel.add_child(output_text)

	# Visualization panel (tab 1)
	viz_panel = VisualizationPanelScript.new()
	viz_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	viz_panel.visible = false
	main_content_stack.add_child(viz_panel)

	# Replay panel (tab 2)
	replay_panel = ReplayPanelScript.new()
	replay_panel.name = "replay_panel"
	replay_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	replay_panel.visible = false
	main_content_stack.add_child(replay_panel)


func _log(text: String) -> void:
	var time_str := Time.get_time_string_from_system()
	output_text.append_text("[color=#666666][%s][/color] %s\n" % [time_str, text])
	print(text.replace("[color=", "").replace("[/color]", "").replace("]", ""))


func _on_main_tab_changed(tab_idx: int) -> void:
	# Hide all panels
	output_panel.visible = false
	viz_panel.visible = false
	replay_panel.visible = false

	# Show selected panel
	match tab_idx:
		0:  # Output
			output_panel.visible = true
		1:  # Charts
			viz_panel.visible = true
			if current_report:
				viz_panel.set_report(current_report)
		2:  # Replay
			replay_panel.visible = true
			if not match_results_list.is_empty():
				replay_panel.set_available_matches(match_results_list)


func _on_start_pressed() -> void:
	print("=== _on_start_pressed called ===")
	if test_running:
		return

	test_running = true
	start_button.disabled = true
	output_text.clear()

	var num_matches := int(matches_input.value)
	var rng_seed := int(seed_input.value)

	_log("[color=yellow]" + "=".repeat(50) + "[/color]")
	_log("[color=green]Starting AI vs AI Test Session[/color]")
	_log("[color=yellow]" + "=".repeat(50) + "[/color]")
	_log("Matches: %d | Seed: %s" % [num_matches, "random" if rng_seed == 0 else str(rng_seed)])
	_log("")

	progress_bar.max_value = num_matches
	progress_bar.value = 0
	progress_label.text = "0 / %d" % num_matches
	status_label.text = "Running tests..."

	# Force UI update
	await get_tree().process_frame

	# Quick sanity check - can we create a GameController?
	print("=== Testing GameController creation ===")
	var test_gc = GameController.new()
	if test_gc == null:
		_log("[color=red]ERROR: Cannot create GameController![/color]")
		print("ERROR: GameController.new() returned null")
	else:
		print("GameController created OK")
		var test_init = test_gc.initialize(["Brute", "Ranger"] as Array[String], ["Beast", "Shaman"] as Array[String])
		print("GameController.initialize() returned: %s" % test_init)
		if test_init and test_gc.game_state:
			print("GameState exists, champions: P1=%d P2=%d" % [
				test_gc.game_state.get_champions(1).size(),
				test_gc.game_state.get_champions(2).size()
			])
		else:
			print("GameState is null or init failed")

	# Create orchestrator
	orchestrator = TestOrchestrator.new()
	orchestrator.verbose = true
	orchestrator.session_progress.connect(_on_progress)
	orchestrator.match_started.connect(_on_match_started)
	orchestrator.debug_message.connect(_on_debug)

	# Config
	var config := TestSessionConfig.new()
	config.execution_mode = TestSessionConfig.ExecutionMode.MINIMAL_UI
	config.num_matches = num_matches
	config.base_seed = rng_seed

	# Run
	current_report = orchestrator.run_session(config)

	# Results
	_show_results(current_report)

	test_running = false
	start_button.disabled = false
	status_label.text = "Complete! Seed: %d" % current_report.base_seed


func _on_progress(completed: int, total: int, _result: MatchResult) -> void:
	progress_bar.value = completed
	progress_label.text = "%d / %d" % [completed, total]


func _on_match_started(match_num: int, p1: Array, p2: Array) -> void:
	status_label.text = "Match %d: %s vs %s" % [match_num, "/".join(p1), "/".join(p2)]


func _on_debug(message: String) -> void:
	# Color code debug messages by type
	var color := "#888888"  # Default grey
	if "[ERROR]" in message:
		color = "#ff4444"  # Red
	elif "[WARN]" in message:
		color = "#ffaa00"  # Orange
	elif "[TURN]" in message:
		color = "#44aaff"  # Blue
	elif "[ACTION]" in message:
		color = "#44ff44"  # Green
	elif "[OK]" in message:
		color = "#00ff00"  # Bright green
	elif "[FAIL]" in message:
		color = "#ff6666"  # Light red

	output_text.append_text("[color=%s]%s[/color]\n" % [color, message])


func _show_results(report: SessionReport) -> void:
	# Update visualization panel
	if viz_panel:
		viz_panel.set_report(report)

	# Store match results for replay
	if orchestrator and orchestrator.match_results:
		match_results_list = []
		for r: MatchResult in orchestrator.match_results:
			match_results_list.append(r)
		if replay_panel:
			replay_panel.set_available_matches(match_results_list)

	_log("")
	_log("[color=yellow]" + "=".repeat(50) + "[/color]")
	_log("[color=green]RESULTS[/color]")
	_log("[color=yellow]" + "=".repeat(50) + "[/color]")
	_log("")

	_log("[color=cyan]SUMMARY[/color]")
	_log("  Matches: %d completed in %.1f seconds" % [report.matches_completed, report.duration_seconds])
	_log("  P1 Wins: %d (%.1f%%)" % [report.player1_wins, report.p1_win_rate * 100])
	_log("  P2 Wins: %d (%.1f%%)" % [report.player2_wins, report.p2_win_rate * 100])
	_log("  Draws: %d" % report.draws)
	_log("  Avg Rounds: %.1f" % report.avg_rounds_per_match)
	_log("")

	# No-ops
	if not report.high_noop_cards.is_empty():
		_log("[color=orange]NO-OP CARDS (cast but did nothing)[/color]")
		for card: Dictionary in report.high_noop_cards.slice(0, 8):
			_log("  %-18s %3d plays, %3d no-op (%.0f%%) - %s" % [
				str(card.get("card_name", "?")).substr(0, 18),
				card.get("times_played", 0),
				card.get("noop_count", 0),
				card.get("noop_rate", 0) * 100,
				str(card.get("common_reason", ""))
			])
		_log("")

	# Champion win rates
	if not report.win_rate_by_champion.is_empty():
		_log("[color=cyan]CHAMPION WIN RATES[/color]")
		var champs: Array = report.win_rate_by_champion.keys()
		champs.sort_custom(func(a, b): return report.win_rate_by_champion[b] < report.win_rate_by_champion[a])

		for champ: String in champs:
			var rate: float = report.win_rate_by_champion[champ]
			var bar := "[" + "#".repeat(int(rate * 15)) + "-".repeat(15 - int(rate * 15)) + "]"
			var color := "green" if rate > 0.52 else ("red" if rate < 0.48 else "white")
			_log("  [color=%s]%-12s %s %.1f%%[/color]" % [color, champ, bar, rate * 100])
		_log("")

	# Never played cards
	if not report.never_played_cards.is_empty():
		_log("[color=orange]NEVER PLAYED CARDS (drawn but not used)[/color]")
		for card: Dictionary in report.never_played_cards.slice(0, 5):
			_log("  %-18s drawn %d times, held %d, discarded %d" % [
				str(card.get("card_name", "?")).substr(0, 18),
				card.get("times_drawn", 0),
				card.get("times_held", 0),
				card.get("times_discarded", 0)
			])
		_log("")

	# Low usage cards
	if not report.low_usage_cards.is_empty():
		_log("[color=yellow]LOW USAGE CARDS (<30%% of draws played)[/color]")
		for card: Dictionary in report.low_usage_cards.slice(0, 5):
			_log("  %-18s drawn %d, played %d (%.0f%% usage)" % [
				str(card.get("card_name", "?")).substr(0, 18),
				card.get("times_drawn", 0),
				card.get("times_played", 0),
				card.get("usage_rate", 0) * 100
			])
		_log("")

	_log("[color=yellow]" + "=".repeat(50) + "[/color]")
	_log("Use seed [color=white]%d[/color] to reproduce these results" % report.base_seed)
	_log("[color=cyan]Click the 'Charts' tab above to see visualizations[/color]")


func _on_export_pressed() -> void:
	if current_report == null:
		_log("[color=red]No results to export![/color]")
		return

	var dir_path := "user://test_reports/"
	DirAccess.make_dir_recursive_absolute(dir_path)

	var path := dir_path + "report_%s.json" % current_report.session_id
	if current_report.save_to_file(path):
		var global_path := ProjectSettings.globalize_path(path)
		_log("[color=green]Exported to:[/color] %s" % global_path)
		# Open folder
		OS.shell_open(ProjectSettings.globalize_path(dir_path))
	else:
		_log("[color=red]Export failed![/color]")


func _run_headless_tests() -> void:
	"""Run tests in headless mode (auto-start)."""
	# Parse command line args for match count and seed
	var num_matches := 20
	var rng_seed := 0

	var cmd_args := OS.get_cmdline_user_args()
	for arg: String in cmd_args:
		if arg.begins_with("--matches="):
			num_matches = int(arg.split("=")[1])
		elif arg.begins_with("--seed="):
			rng_seed = int(arg.split("=")[1])

	print("")
	print("=" .repeat(50))
	print("Starting AI vs AI Test Session (Headless)")
	print("=" .repeat(50))
	print("Matches: %d | Seed: %s" % [num_matches, "random" if rng_seed == 0 else str(rng_seed)])
	print("")

	# Create orchestrator
	orchestrator = TestOrchestrator.new()
	orchestrator.verbose = true
	orchestrator.session_progress.connect(_on_headless_progress)
	orchestrator.debug_message.connect(_on_headless_debug)

	# Config
	var config := TestSessionConfig.new()
	config.execution_mode = TestSessionConfig.ExecutionMode.HEADLESS
	config.num_matches = num_matches
	config.base_seed = rng_seed

	# Run
	current_report = orchestrator.run_session(config)

	# Show results
	_show_headless_results(current_report)

	# Exit
	get_tree().quit(0 if current_report.matches_errored == 0 else 1)


func _on_headless_progress(completed: int, total: int, _result: MatchResult) -> void:
	print("  Progress: %d / %d (%.0f%%)" % [completed, total, float(completed) / total * 100])


func _on_headless_debug(message: String) -> void:
	print("  %s" % message)


func _show_headless_results(report: SessionReport) -> void:
	print("")
	print("=" .repeat(50))
	print("RESULTS")
	print("=" .repeat(50))
	print("")

	print("SUMMARY")
	print("  Matches: %d completed in %.1f seconds" % [report.matches_completed, report.duration_seconds])
	print("  P1 Wins: %d (%.1f%%)" % [report.player1_wins, report.p1_win_rate * 100])
	print("  P2 Wins: %d (%.1f%%)" % [report.player2_wins, report.p2_win_rate * 100])
	print("  Draws: %d" % report.draws)
	print("  Avg Rounds: %.1f" % report.avg_rounds_per_match)
	print("")

	# No-ops
	if not report.high_noop_cards.is_empty():
		print("NO-OP CARDS (cast but did nothing)")
		for card: Dictionary in report.high_noop_cards.slice(0, 8):
			print("  %-18s %3d plays, %3d no-op (%.0f%%) - %s" % [
				str(card.get("card_name", "?")).substr(0, 18),
				card.get("times_played", 0),
				card.get("noop_count", 0),
				card.get("noop_rate", 0) * 100,
				str(card.get("common_reason", ""))
			])
		print("")

	# Champion win rates
	if not report.win_rate_by_champion.is_empty():
		print("CHAMPION WIN RATES")
		var champs: Array = report.win_rate_by_champion.keys()
		champs.sort_custom(func(a, b): return report.win_rate_by_champion[b] < report.win_rate_by_champion[a])

		for champ: String in champs:
			var rate: float = report.win_rate_by_champion[champ]
			var bar := "[" + "#".repeat(int(rate * 15)) + "-".repeat(15 - int(rate * 15)) + "]"
			print("  %-12s %s %.1f%%" % [champ, bar, rate * 100])
		print("")

	# Team pair win rates
	if not report.pair_statistics.is_empty():
		print("TEAM PAIR WIN RATES")
		var pairs: Array = []
		for pair_key: String in report.pair_statistics:
			var stats: Dictionary = report.pair_statistics[pair_key]
			if stats.get("times_paired", 0) >= 2:
				pairs.append({
					"key": pair_key,
					"win_rate": stats.get("win_rate", 0.5),
					"times": stats.get("times_paired", 0),
					"wins": stats.get("wins", 0),
					"losses": stats.get("losses", 0)
				})
		pairs.sort_custom(func(a, b): return a["win_rate"] > b["win_rate"])

		for pair: Dictionary in pairs.slice(0, 10):
			var bar := "[" + "#".repeat(int(pair["win_rate"] * 15)) + "-".repeat(15 - int(pair["win_rate"] * 15)) + "]"
			print("  %-20s %s %.1f%% (%d-%d)" % [
				pair["key"].substr(0, 20),
				bar,
				pair["win_rate"] * 100,
				pair["wins"],
				pair["losses"]
			])
		print("")

	# Matchup statistics
	if not report.matchup_statistics.is_empty():
		print("TEAM VS TEAM MATCHUPS")
		var matchups: Array = []
		for matchup_key: String in report.matchup_statistics:
			var stats: Dictionary = report.matchup_statistics[matchup_key]
			if stats.get("times_played", 0) >= 1:
				matchups.append({
					"key": matchup_key,
					"team1": stats.get("team1", []),
					"team2": stats.get("team2", []),
					"times": stats.get("times_played", 0),
					"team1_wins": stats.get("team1_wins", 0),
					"team2_wins": stats.get("team2_wins", 0),
					"draws": stats.get("draws", 0),
					"team1_win_rate": stats.get("team1_win_rate", 0.5)
				})
		matchups.sort_custom(func(a, b): return a["times"] > b["times"])

		for matchup: Dictionary in matchups.slice(0, 8):
			var t1 := "/".join(matchup["team1"]) if matchup["team1"] else "?"
			var t2 := "/".join(matchup["team2"]) if matchup["team2"] else "?"
			print("  %s vs %s: %d-%d-%d" % [
				t1.substr(0, 15),
				t2.substr(0, 15),
				matchup["team1_wins"],
				matchup["team2_wins"],
				matchup["draws"]
			])
		print("")

	print("=" .repeat(50))
	print("Use seed %d to reproduce these results" % report.base_seed)
