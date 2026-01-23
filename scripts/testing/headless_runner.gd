extends SceneTree
## Headless CLI runner for AI vs AI tests
## Run from command line: godot --headless --script res://scripts/testing/headless_runner.gd -- [options]
##
## Options:
##   --matches=N       Number of matches to run (default: 10)
##   --seed=N          Base RNG seed for reproducibility (default: random)
##   --output=PATH     Output directory for reports (default: user://test_reports/)
##   --p1-diff=N       Player 1 AI difficulty: 0=Easy, 1=Medium, 2=Hard (default: 1)
##   --p2-diff=N       Player 2 AI difficulty: 0=Easy, 1=Medium, 2=Hard (default: 1)
##   --p1=Champ1,Champ2  Specific champions for player 1
##   --p2=Champ1,Champ2  Specific champions for player 2
##   --full            Run all champion combinations
##   --quick           Quick test with 5 matches
##   --verbose         Enable verbose output
##   --json            Output JSON report only (no console summary)


var orchestrator: TestOrchestrator
var console_reporter: ConsoleReporter
var json_reporter: JsonReporter

var verbose: bool = false
var json_only: bool = false


func _init() -> void:
	# Parse command line arguments
	var args := _parse_args()

	# Wait for autoloads
	await _wait_for_autoloads()

	# Run tests
	var report := await _run_tests(args)

	# Output results
	_output_results(report, args)

	# Exit
	quit(0 if report.matches_errored == 0 else 1)


func _wait_for_autoloads() -> void:
	"""Wait for CardDatabase to load."""
	# Create minimal loop to allow autoloads to initialize
	for i in range(10):
		await create_timer(0.1).timeout
		if CardDatabase != null and CardDatabase.is_loaded:
			break

	if CardDatabase == null or not CardDatabase.is_loaded:
		print("[ERROR] CardDatabase failed to load")
		quit(1)


func _parse_args() -> Dictionary:
	"""Parse command line arguments."""
	var args := {
		"matches": 10,
		"seed": 0,
		"output": "user://test_reports/",
		"p1_difficulty": 1,
		"p2_difficulty": 1,
		"p1_champions": [] as Array[String],
		"p2_champions": [] as Array[String],
		"full": false,
		"quick": false,
		"verbose": false,
		"json_only": false
	}

	var cmd_args := OS.get_cmdline_user_args()

	for arg: String in cmd_args:
		if arg.begins_with("--matches="):
			args["matches"] = int(arg.split("=")[1])
		elif arg.begins_with("--seed="):
			args["seed"] = int(arg.split("=")[1])
		elif arg.begins_with("--output="):
			args["output"] = arg.split("=")[1]
		elif arg.begins_with("--p1-diff="):
			args["p1_difficulty"] = int(arg.split("=")[1])
		elif arg.begins_with("--p2-diff="):
			args["p2_difficulty"] = int(arg.split("=")[1])
		elif arg.begins_with("--p1="):
			var champs := arg.split("=")[1].split(",")
			args["p1_champions"] = []
			for c: String in champs:
				args["p1_champions"].append(c.strip_edges())
		elif arg.begins_with("--p2="):
			var champs := arg.split("=")[1].split(",")
			args["p2_champions"] = []
			for c: String in champs:
				args["p2_champions"].append(c.strip_edges())
		elif arg == "--full":
			args["full"] = true
		elif arg == "--quick":
			args["quick"] = true
			args["matches"] = 5
		elif arg == "--verbose":
			args["verbose"] = true
		elif arg == "--json":
			args["json_only"] = true
		elif arg == "--help" or arg == "-h":
			_print_help()
			quit(0)

	verbose = args["verbose"]
	json_only = args["json_only"]

	return args


func _print_help() -> void:
	"""Print help message."""
	print("""
Arena AI vs AI Test Runner
==========================

Usage: godot --headless --script res://scripts/testing/headless_runner.gd -- [options]

Options:
  --matches=N         Number of matches to run (default: 10)
  --seed=N            Base RNG seed for reproducibility (default: random)
  --output=PATH       Output directory for reports (default: user://test_reports/)
  --p1-diff=N         Player 1 AI difficulty: 0=Easy, 1=Medium, 2=Hard (default: 1)
  --p2-diff=N         Player 2 AI difficulty: 0=Easy, 1=Medium, 2=Hard (default: 1)
  --p1=Champ1,Champ2  Specific champions for player 1
  --p2=Champ1,Champ2  Specific champions for player 2
  --full              Run all champion combinations
  --quick             Quick test with 5 matches
  --verbose           Enable verbose output
  --json              Output JSON report only
  --help, -h          Show this help message

Examples:
  # Run 100 random matches
  godot --headless --script res://scripts/testing/headless_runner.gd -- --matches=100

  # Run with specific seed for reproducibility
  godot --headless --script res://scripts/testing/headless_runner.gd -- --matches=50 --seed=12345

  # Test specific matchup
  godot --headless --script res://scripts/testing/headless_runner.gd -- --p1=Brute,Ranger --p2=Berserker,Shaman --matches=20

  # Run all combinations
  godot --headless --script res://scripts/testing/headless_runner.gd -- --full

Champions: Brute, Ranger, Beast, Redeemer, Confessor, Barbarian,
           Burglar, Berserker, Shaman, Illusionist, DarkWizard, Alchemist
""")


func _run_tests(args: Dictionary) -> SessionReport:
	"""Run tests based on parsed arguments."""
	orchestrator = TestOrchestrator.new()
	console_reporter = ConsoleReporter.new()
	json_reporter = JsonReporter.new()

	# Create configuration
	var config: TestSessionConfig

	if args["full"]:
		config = TestOrchestrator.create_full_test(1)
		if verbose:
			print("[CONFIG] Full combination test: %d matchups" % config.num_matches)
	elif args["p1_champions"].size() == 2 and args["p2_champions"].size() == 2:
		config = TestOrchestrator.create_matchup_test(
			args["p1_champions"],
			args["p2_champions"],
			args["matches"],
			args["seed"]
		)
		if verbose:
			print("[CONFIG] Specific matchup: %s vs %s" % [
				"/".join(args["p1_champions"]),
				"/".join(args["p2_champions"])
			])
	else:
		config = TestOrchestrator.create_quick_test(args["matches"], args["seed"])
		if verbose:
			print("[CONFIG] Random matchups: %d matches" % args["matches"])

	# Apply difficulty settings
	config.p1_difficulty = args["p1_difficulty"]
	config.p2_difficulty = args["p2_difficulty"]
	config.output_directory = args["output"]

	# Connect progress signal for verbose mode
	if verbose:
		orchestrator.session_progress.connect(_on_progress)

	# Run the session
	var report := orchestrator.run_session(config)

	return report


func _on_progress(completed: int, total: int, result: MatchResult) -> void:
	"""Handle progress updates in verbose mode."""
	if not json_only:
		console_reporter.print_progress(completed, total, result)


func _output_results(report: SessionReport, args: Dictionary) -> void:
	"""Output results in requested formats."""
	# Always write JSON
	var json_path: String = args["output"]
	if not json_path.ends_with("/"):
		json_path += "/"
	json_path += "report_%s.json" % report.session_id

	json_reporter.write_report(report, json_path)

	# Write additional analysis files
	json_reporter.write_noop_analysis(report, args["output"] + "noop_analysis_%s.json" % report.session_id)

	# Console output unless json_only
	if not json_only:
		console_reporter.print_report(report)

	print("")
	print("Reports saved to: %s" % ProjectSettings.globalize_path(args["output"]))
