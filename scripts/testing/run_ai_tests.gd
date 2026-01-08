extends Node
## RunAITests - Main entry point for running AI vs AI tests
## Can be run as a scene or from command line

const LOG_FILE_PATH := "user://ai_test_results.log"
const BUG_FILE_PATH := "user://bugs_found.log"

var runner: AIvsAIRunner
var test_configs: Array[Dictionary] = []


func _ready() -> void:
	print("")
	print("========================================")
	print("   Arena - AI vs AI Test Runner")
	print("========================================")
	print("")

	# Wait for CardDatabase to load
	if not CardDatabase.is_loaded:
		print("Waiting for CardDatabase to load...")
		await CardDatabase.database_loaded

	print("CardDatabase loaded. Starting tests...")
	print("")

	# Configure test matchups
	_configure_tests()

	# Run all tests
	await _run_all_tests()

	# Write results to file
	_write_results()

	print("")
	print("Tests complete! Check logs at:")
	print("  Results: %s" % ProjectSettings.globalize_path(LOG_FILE_PATH))
	print("  Bugs: %s" % ProjectSettings.globalize_path(BUG_FILE_PATH))
	print("")

	# Exit after tests (comment out for interactive mode)
	# get_tree().quit()


func _configure_tests() -> void:
	"""Configure test matchups to run."""

	# Test 1: Mirror match - Brute/Ranger vs Brute/Ranger
	test_configs.append({
		"name": "Mirror Match (Brute/Ranger)",
		"p1_champions": ["Brute", "Ranger"] as Array[String],
		"p2_champions": ["Brute", "Ranger"] as Array[String],
		"p1_difficulty": AIController.Difficulty.MEDIUM,
		"p2_difficulty": AIController.Difficulty.MEDIUM,
		"num_matches": 3
	})

	# Test 2: Melee vs Ranged
	test_configs.append({
		"name": "Melee vs Ranged (Brute/Berserker vs Ranger/Shaman)",
		"p1_champions": ["Brute", "Berserker"] as Array[String],
		"p2_champions": ["Ranger", "Shaman"] as Array[String],
		"p1_difficulty": AIController.Difficulty.MEDIUM,
		"p2_difficulty": AIController.Difficulty.MEDIUM,
		"num_matches": 3
	})

	# Test 3: Support vs Aggro
	test_configs.append({
		"name": "Support vs Aggro (Redeemer/Ranger vs Berserker/Barbarian)",
		"p1_champions": ["Redeemer", "Ranger"] as Array[String],
		"p2_champions": ["Berserker", "Barbarian"] as Array[String],
		"p1_difficulty": AIController.Difficulty.MEDIUM,
		"p2_difficulty": AIController.Difficulty.MEDIUM,
		"num_matches": 2
	})

	# Test 4: Easy vs Hard AI
	test_configs.append({
		"name": "Easy vs Hard AI",
		"p1_champions": ["Brute", "Ranger"] as Array[String],
		"p2_champions": ["Brute", "Ranger"] as Array[String],
		"p1_difficulty": AIController.Difficulty.EASY,
		"p2_difficulty": AIController.Difficulty.HARD,
		"num_matches": 2
	})


func _run_all_tests() -> void:
	"""Run all configured test matchups."""
	var all_bugs: Array[Dictionary] = []
	var total_matches := 0
	var total_errors := 0

	for config: Dictionary in test_configs:
		print("===========================================")
		print("Test: %s" % config.get("name", "Unknown"))
		print("===========================================")

		runner = AIvsAIRunner.new()

		var results := runner.run_matches(
			config.get("num_matches", 1),
			config.get("p1_champions", ["Brute", "Ranger"] as Array[String]),
			config.get("p2_champions", ["Brute", "Ranger"] as Array[String]),
			config.get("p1_difficulty", AIController.Difficulty.MEDIUM),
			config.get("p2_difficulty", AIController.Difficulty.MEDIUM)
		)

		all_bugs.append_array(results.get("bugs", []))
		total_matches += config.get("num_matches", 1)
		total_errors += results.get("errors", 0)

		print("")

	# Final summary
	print("===========================================")
	print("   FINAL SUMMARY")
	print("===========================================")
	print("Total matches run: %d" % total_matches)
	print("Total errors: %d" % total_errors)
	print("Total bugs found: %d" % all_bugs.size())
	print("")

	if not all_bugs.is_empty():
		print("BUGS FOUND:")
		for bug: Dictionary in all_bugs:
			print("  [%s] %s" % [bug.get("type", "?"), bug.get("description", "?")])
		print("")


func _write_results() -> void:
	"""Write test results to log files."""
	# Write main results
	var results_file := FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)
	if results_file:
		results_file.store_string("Arena AI vs AI Test Results\n")
		results_file.store_string("Generated: %s\n" % Time.get_datetime_string_from_system())
		results_file.store_string("=".repeat(50) + "\n\n")

		if runner:
			results_file.store_string(runner.get_full_log())

		results_file.close()
		print("Results written to: %s" % LOG_FILE_PATH)

	# Write bugs file
	var bugs_file := FileAccess.open(BUG_FILE_PATH, FileAccess.WRITE)
	if bugs_file:
		bugs_file.store_string("Arena - Bugs Found During Testing\n")
		bugs_file.store_string("Generated: %s\n" % Time.get_datetime_string_from_system())
		bugs_file.store_string("=".repeat(50) + "\n\n")

		if runner:
			var bugs := runner.get_bugs()
			if bugs.is_empty():
				bugs_file.store_string("No bugs found!\n")
			else:
				for bug: Dictionary in bugs:
					bugs_file.store_string("BUG: %s\n" % bug.get("type", "unknown"))
					bugs_file.store_string("  Description: %s\n" % bug.get("description", ""))
					bugs_file.store_string("  Match: %d\n" % bug.get("match", 0))
					bugs_file.store_string("  Context: %s\n" % str(bug.get("context", {})))
					bugs_file.store_string("\n")

		bugs_file.close()
		print("Bugs written to: %s" % BUG_FILE_PATH)
