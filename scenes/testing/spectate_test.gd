extends "res://scenes/game/game.gd"
class_name SpectateTestScene
## Spectate mode - watch AI battles with full animations
## Extends GameScene to add test tracking and controls


signal spectate_session_started(config: TestSessionConfig)
signal spectate_session_completed(report: SessionReport)
signal spectate_match_started(match_number: int)
signal spectate_match_ended(match_number: int, result: MatchResult)


## Test system components
var test_orchestrator: TestOrchestrator
var effect_tracker: EffectTracker
var statistics: StatisticsCollector
var rng_manager: RNGManager

## Match queue
var match_queue: Array[TestSessionConfig.MatchConfig] = []
var current_match_config: TestSessionConfig.MatchConfig
var current_match_index: int = 0
var total_matches: int = 0

## Session state
var spectate_active: bool = false
var auto_advance: bool = true
var match_delay: float = 3.0

## Current match tracking
var current_match_result: MatchResult
var match_start_time: int = 0

## UI overlays
var spectate_hud: Control
var control_panel: Control
var stats_overlay: Control


func _ready() -> void:
	# Force AI vs AI mode
	ai_vs_ai_mode = true

	# Initialize test components
	test_orchestrator = TestOrchestrator.new()
	statistics = StatisticsCollector.new()
	rng_manager = RNGManager.new()
	effect_tracker = EffectTracker.new()

	# Call parent ready
	super._ready()

	# Setup spectate UI
	_setup_spectate_ui()


func _setup_spectate_ui() -> void:
	"""Create spectate mode UI overlays."""
	# Create HUD overlay
	spectate_hud = _create_spectate_hud()
	add_child(spectate_hud)

	# Create control panel
	control_panel = _create_control_panel()
	add_child(control_panel)

	# Create stats overlay
	stats_overlay = _create_stats_overlay()
	add_child(stats_overlay)


func _create_spectate_hud() -> Control:
	"""Create the spectate mode HUD overlay."""
	var hud := Control.new()
	hud.name = "SpectateHUD"
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_bottom = 60

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(bg)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 20)
	hud.add_child(hbox)

	var match_label := Label.new()
	match_label.name = "MatchLabel"
	match_label.text = "Match 0 / 0"
	match_label.add_theme_font_size_override("font_size", 20)
	hbox.add_child(match_label)

	var wins_label := Label.new()
	wins_label.name = "WinsLabel"
	wins_label.text = "P1: 0 | P2: 0 | Draws: 0"
	wins_label.add_theme_font_size_override("font_size", 20)
	hbox.add_child(wins_label)

	var noop_label := Label.new()
	noop_label.name = "NoopLabel"
	noop_label.text = "No-ops: 0"
	noop_label.add_theme_font_size_override("font_size", 20)
	hbox.add_child(noop_label)

	return hud


func _create_control_panel() -> Control:
	"""Create the control panel for spectate mode."""
	var panel := Control.new()
	panel.name = "ControlPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -300
	panel.offset_top = -100

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	# Speed control
	var speed_hbox := HBoxContainer.new()
	vbox.add_child(speed_hbox)

	var speed_label := Label.new()
	speed_label.text = "Speed:"
	speed_hbox.add_child(speed_label)

	var speed_slider := HSlider.new()
	speed_slider.name = "SpeedSlider"
	speed_slider.min_value = 0.5
	speed_slider.max_value = 3.0
	speed_slider.value = 1.0
	speed_slider.step = 0.25
	speed_slider.custom_minimum_size.x = 150
	speed_slider.value_changed.connect(_on_speed_changed)
	speed_hbox.add_child(speed_slider)

	# Buttons
	var button_hbox := HBoxContainer.new()
	vbox.add_child(button_hbox)

	var pause_btn := Button.new()
	pause_btn.name = "PauseButton"
	pause_btn.text = "Pause"
	pause_btn.pressed.connect(_on_pause_pressed)
	button_hbox.add_child(pause_btn)

	var next_btn := Button.new()
	next_btn.name = "NextButton"
	next_btn.text = "Next Match"
	next_btn.pressed.connect(_on_next_match_pressed)
	button_hbox.add_child(next_btn)

	var auto_check := CheckButton.new()
	auto_check.name = "AutoAdvance"
	auto_check.text = "Auto"
	auto_check.button_pressed = true
	auto_check.toggled.connect(_on_auto_advance_toggled)
	button_hbox.add_child(auto_check)

	return panel


func _create_stats_overlay() -> Control:
	"""Create the statistics overlay."""
	var overlay := Control.new()
	overlay.name = "StatsOverlay"
	overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	overlay.offset_right = 250
	overlay.offset_bottom = 200
	overlay.offset_top = 70
	overlay.offset_left = 10
	overlay.visible = false  # Hidden by default, toggle with key

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var label := RichTextLabel.new()
	label.name = "StatsText"
	label.bbcode_enabled = true
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.text = "[b]Statistics[/b]\nWaiting for data..."
	overlay.add_child(label)

	return overlay


func start_spectate_session(config: TestSessionConfig) -> void:
	"""Start a spectate test session."""
	spectate_active = true
	total_matches = config.num_matches
	current_match_index = 0

	# Initialize RNG
	rng_manager.set_session_seed(config.base_seed)

	# Reset statistics
	statistics.reset()

	# Generate matchups
	if config.matchups.is_empty():
		match_queue = test_orchestrator.generate_all_combinations(config) if config.num_matches > 100 else _generate_random_matchups(config)
	else:
		match_queue = config.matchups.duplicate()

	total_matches = match_queue.size()

	spectate_session_started.emit(config)

	# Start first match
	_start_next_match()


func _generate_random_matchups(config: TestSessionConfig) -> Array[TestSessionConfig.MatchConfig]:
	"""Generate random matchups for spectate mode."""
	var matchups: Array[TestSessionConfig.MatchConfig] = []
	var all_champs: Array[String] = [
		"Brute", "Ranger", "Beast", "Redeemer", "Confessor", "Barbarian",
		"Burglar", "Berserker", "Shaman", "Illusionist", "DarkWizard", "Alchemist"
	]

	for i in range(config.num_matches):
		var match_config := TestSessionConfig.MatchConfig.new()
		match_config.match_index = i
		match_config.p1_difficulty = config.p1_difficulty
		match_config.p2_difficulty = config.p2_difficulty

		var available := all_champs.duplicate()
		available.shuffle()
		match_config.p1_champions = [available[0], available[1]]
		match_config.p2_champions = [available[2], available[3]]

		matchups.append(match_config)

	return matchups


func _start_next_match() -> void:
	"""Start the next match in the queue."""
	if match_queue.is_empty():
		_finish_session()
		return

	current_match_config = match_queue.pop_front()
	current_match_index += 1

	# Update HUD
	_update_spectate_hud()

	# Apply RNG seed
	rng_manager.apply_match_seed(current_match_config.match_index)

	# Initialize match result
	current_match_result = MatchResult.new()
	current_match_result.match_id = current_match_config.match_index
	current_match_result.seed_used = rng_manager.current_match_seed
	current_match_result.timestamp = Time.get_datetime_string_from_system()
	current_match_result.p1_champions = current_match_config.p1_champions.duplicate()
	current_match_result.p2_champions = current_match_config.p2_champions.duplicate()
	match_start_time = Time.get_ticks_msec()

	# Track match start
	statistics.begin_match(current_match_config.p1_champions, current_match_config.p2_champions)

	spectate_match_started.emit(current_match_index)

	# Set up game with match champions
	set_meta("p1_champions", current_match_config.p1_champions)
	set_meta("p2_champions", current_match_config.p2_champions)

	# Start the game (calls parent's _start_game)
	_start_game()

	# Connect effect tracker
	if game_controller != null:
		effect_tracker.connect_to_processor(
			game_controller.effect_processor,
			game_controller.game_state
		)


func _on_game_ended(winner: int, reason: String) -> void:
	"""Override to handle match end in spectate mode."""
	super._on_game_ended(winner, reason)

	if not spectate_active:
		return

	# Finalize match result
	current_match_result.winner = winner
	current_match_result.win_reason = reason
	current_match_result.duration_ms = Time.get_ticks_msec() - match_start_time
	current_match_result.total_rounds = game_controller.game_state.round_number

	# Capture final HP
	for champ: ChampionState in game_controller.game_state.get_all_champions():
		current_match_result.final_champion_hp[champ.unique_id] = champ.current_hp

	# Record to statistics
	statistics.record_match_result(current_match_result)

	# Update HUD
	_update_spectate_hud()

	# Disconnect effect tracker
	effect_tracker.disconnect_from_processor()

	spectate_match_ended.emit(current_match_index, current_match_result)

	# Auto-advance or wait
	if auto_advance and not match_queue.is_empty():
		await get_tree().create_timer(match_delay).timeout
		_start_next_match()


func _finish_session() -> void:
	"""Finish the spectate session."""
	spectate_active = false

	# Generate report
	var report := statistics.generate_report()
	report.session_id = "spectate_%s" % Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")

	# Save report
	var json_reporter := JsonReporter.new()
	json_reporter.write_report(report)

	spectate_session_completed.emit(report)

	# Show completion message
	if hud:
		hud.show_message("Session complete! Report saved.")


func _update_spectate_hud() -> void:
	"""Update the spectate HUD with current stats."""
	if spectate_hud == null:
		return

	var match_label: Label = spectate_hud.get_node_or_null("HBoxContainer/MatchLabel")
	if match_label:
		match_label.text = "Match %d / %d" % [current_match_index, total_matches]

	var wins_label: Label = spectate_hud.get_node_or_null("HBoxContainer/WinsLabel")
	if wins_label:
		wins_label.text = "P1: %d | P2: %d | Draws: %d" % [
			statistics.player1_wins,
			statistics.player2_wins,
			statistics.draws
		]

	var noop_label: Label = spectate_hud.get_node_or_null("HBoxContainer/NoopLabel")
	if noop_label:
		noop_label.text = "No-ops: %d" % statistics.total_noop_plays


func _update_stats_overlay() -> void:
	"""Update the statistics overlay."""
	if stats_overlay == null:
		return

	var stats_text: RichTextLabel = stats_overlay.get_node_or_null("StatsText")
	if stats_text:
		stats_text.text = """[b]Session Statistics[/b]
Matches: %d / %d
P1 Wins: %d (%.1f%%)
P2 Wins: %d (%.1f%%)
Draws: %d
No-ops: %d / %d
""" % [
			current_match_index, total_matches,
			statistics.player1_wins, statistics.player1_wins / float(maxi(1, statistics.total_matches)) * 100,
			statistics.player2_wins, statistics.player2_wins / float(maxi(1, statistics.total_matches)) * 100,
			statistics.draws,
			statistics.total_noop_plays, statistics.total_card_plays
		]


func _on_speed_changed(value: float) -> void:
	"""Handle speed slider change."""
	Engine.time_scale = value


func _on_pause_pressed() -> void:
	"""Handle pause button press."""
	get_tree().paused = not get_tree().paused
	var pause_btn: Button = control_panel.get_node_or_null("VBoxContainer/HBoxContainer/PauseButton")
	if pause_btn:
		pause_btn.text = "Resume" if get_tree().paused else "Pause"


func _on_next_match_pressed() -> void:
	"""Handle next match button press."""
	if not match_queue.is_empty():
		_start_next_match()


func _on_auto_advance_toggled(pressed: bool) -> void:
	"""Handle auto-advance toggle."""
	auto_advance = pressed


func _input(event: InputEvent) -> void:
	"""Handle input for spectate controls."""
	if event.is_action_pressed("ui_cancel"):
		# Toggle stats overlay with Escape
		if stats_overlay:
			stats_overlay.visible = not stats_overlay.visible
			if stats_overlay.visible:
				_update_stats_overlay()


## Quick start spectate with default settings
func quick_start(num_matches: int = 10) -> void:
	"""Start spectating with default settings."""
	var config := TestSessionConfig.new()
	config.execution_mode = TestSessionConfig.ExecutionMode.SPECTATE
	config.num_matches = num_matches
	start_spectate_session(config)
