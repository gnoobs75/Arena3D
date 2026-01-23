extends Control
## Minimal UI for AI vs AI testing
## Shows progress, live stats, and controls


@onready var progress_bar: ProgressBar = $VBoxContainer/ProgressSection/ProgressBar
@onready var progress_label: Label = $VBoxContainer/ProgressSection/ProgressLabel
@onready var status_label: Label = $VBoxContainer/StatusSection/StatusLabel
@onready var stats_label: RichTextLabel = $VBoxContainer/StatsSection/StatsLabel
@onready var speed_slider: HSlider = $VBoxContainer/ControlsSection/SpeedSlider
@onready var speed_label: Label = $VBoxContainer/ControlsSection/SpeedLabel
@onready var start_button: Button = $VBoxContainer/ControlsSection/StartButton
@onready var pause_button: Button = $VBoxContainer/ControlsSection/PauseButton
@onready var export_button: Button = $VBoxContainer/ControlsSection/ExportButton
@onready var matches_spinbox: SpinBox = $VBoxContainer/ConfigSection/MatchesSpinBox
@onready var seed_spinbox: SpinBox = $VBoxContainer/ConfigSection/SeedSpinBox


var orchestrator: TestOrchestrator
var console_reporter: ConsoleReporter
var json_reporter: JsonReporter

var current_report: SessionReport = null
var test_running: bool = false


func _ready() -> void:
	# Initialize reporters
	console_reporter = ConsoleReporter.new()
	json_reporter = JsonReporter.new()

	# Setup UI
	_setup_ui()

	# Wait for CardDatabase
	if not CardDatabase.is_loaded:
		status_label.text = "Loading card database..."
		await CardDatabase.database_loaded

	status_label.text = "Ready to start testing"


func _setup_ui() -> void:
	"""Setup UI elements."""
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0

	matches_spinbox.min_value = 1
	matches_spinbox.max_value = 1000
	matches_spinbox.value = 20

	seed_spinbox.min_value = 0
	seed_spinbox.max_value = 999999999
	seed_spinbox.value = 0

	speed_slider.min_value = 0.1
	speed_slider.max_value = 10.0
	speed_slider.value = 1.0
	speed_slider.step = 0.1

	pause_button.disabled = true
	export_button.disabled = true

	# Connect signals
	start_button.pressed.connect(_on_start_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	export_button.pressed.connect(_on_export_pressed)
	speed_slider.value_changed.connect(_on_speed_changed)


func _on_start_pressed() -> void:
	"""Start the test session."""
	if test_running:
		return

	test_running = true
	start_button.disabled = true
	pause_button.disabled = false
	export_button.disabled = true

	# Create orchestrator
	orchestrator = TestOrchestrator.new()
	orchestrator.session_started.connect(_on_session_started)
	orchestrator.session_progress.connect(_on_session_progress)
	orchestrator.session_completed.connect(_on_session_completed)
	orchestrator.match_started.connect(_on_match_started)

	# Create configuration
	var config := TestSessionConfig.new()
	config.execution_mode = TestSessionConfig.ExecutionMode.MINIMAL_UI
	config.num_matches = int(matches_spinbox.value)
	config.base_seed = int(seed_spinbox.value)

	# Run in background (would need async in real implementation)
	progress_bar.max_value = config.num_matches
	progress_bar.value = 0

	status_label.text = "Starting test session..."

	# Run the session
	# Note: In a real implementation, this would be async
	current_report = orchestrator.run_session(config)


func _on_pause_pressed() -> void:
	"""Toggle pause state."""
	if orchestrator == null:
		return

	if orchestrator.session_paused:
		orchestrator.resume_session()
		pause_button.text = "Pause"
		status_label.text = "Running..."
	else:
		orchestrator.pause_session()
		pause_button.text = "Resume"
		status_label.text = "Paused"


func _on_export_pressed() -> void:
	"""Export results to file."""
	if current_report == null:
		return

	var path := "user://test_reports/manual_export_%s.json" % Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	if json_reporter.write_report(current_report, path):
		status_label.text = "Exported to: %s" % path
	else:
		status_label.text = "Export failed!"


func _on_speed_changed(value: float) -> void:
	"""Update speed label."""
	speed_label.text = "%.1fx" % value


func _on_session_started(config: TestSessionConfig) -> void:
	"""Handle session start."""
	status_label.text = "Running %d matches..." % config.num_matches


func _on_session_progress(completed: int, total: int, result: MatchResult) -> void:
	"""Handle progress update."""
	progress_bar.value = completed
	progress_label.text = "%d / %d" % [completed, total]

	# Update live stats
	if orchestrator != null:
		var stats := orchestrator.statistics
		var win_rate := 0.0
		if stats.total_matches > 0:
			win_rate = float(stats.player1_wins) / float(stats.total_matches) * 100.0

		stats_label.text = """[b]Live Statistics[/b]
Matches: %d
P1 Wins: %d (%.1f%%)
P2 Wins: %d
Draws: %d
No-ops: %d / %d (%.1f%%)
""" % [
			stats.total_matches,
			stats.player1_wins, win_rate,
			stats.player2_wins,
			stats.draws,
			stats.total_noop_plays, stats.total_card_plays,
			stats.total_noop_plays / float(maxi(1, stats.total_card_plays)) * 100.0
		]


func _on_match_started(match_number: int, p1_champs: Array, p2_champs: Array) -> void:
	"""Handle match start."""
	status_label.text = "Match %d: %s vs %s" % [
		match_number,
		"/".join(p1_champs),
		"/".join(p2_champs)
	]


func _on_session_completed(report: SessionReport) -> void:
	"""Handle session completion."""
	test_running = false
	current_report = report

	start_button.disabled = false
	pause_button.disabled = true
	export_button.disabled = false

	status_label.text = "Complete! P1: %d wins | P2: %d wins | Draws: %d" % [
		report.player1_wins,
		report.player2_wins,
		report.draws
	]

	# Show final stats
	stats_label.text = report.to_console_summary()

	# Print to console too
	console_reporter.print_report(report)
