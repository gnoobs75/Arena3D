class_name TestOrchestrator
extends RefCounted
## Central coordinator for AI vs AI test sessions
## Manages configuration, match execution, and statistics collection


signal session_started(config: TestSessionConfig)
signal session_progress(completed: int, total: int, current_result: MatchResult)
signal session_completed(report: SessionReport)
signal match_started(match_number: int, p1_champs: Array, p2_champs: Array)
signal match_completed(match_number: int, result: MatchResult)
signal error_occurred(match_number: int, error: String)
signal debug_message(message: String)

## Whether to emit verbose debug messages
var verbose: bool = true


## RNG manager for reproducibility
var rng_manager: RNGManager

## Statistics collector
var statistics: StatisticsCollector

## Match runner
var match_runner: MatchRunner

## Session state
var session_config: TestSessionConfig
var session_active: bool = false
var session_paused: bool = false
var session_aborted: bool = false

## Progress tracking
var matches_completed: int = 0
var matches_total: int = 0
var current_match_index: int = 0

## Results
var match_results: Array[MatchResult] = []
var session_start_time: int = 0

## All champions for random matchup generation
const ALL_CHAMPIONS: Array[String] = [
	"Brute", "Ranger", "Beast", "Redeemer", "Confessor", "Barbarian",
	"Burglar", "Berserker", "Shaman", "Illusionist", "DarkWizard", "Alchemist"
]


func _init() -> void:
	rng_manager = RNGManager.new()
	statistics = StatisticsCollector.new()
	match_results = []


func run_session(config: TestSessionConfig) -> SessionReport:
	"""Run a complete test session and return the report."""
	session_config = config
	session_active = true
	session_paused = false
	session_aborted = false
	matches_completed = 0
	matches_total = config.num_matches
	match_results = []
	session_start_time = Time.get_ticks_msec()

	# Initialize RNG
	rng_manager.set_session_seed(config.base_seed)

	# Reset statistics
	statistics.reset()

	print("")
	print("=" .repeat(60))
	print("   ARENA AI VS AI TEST SESSION")
	print("=" .repeat(60))
	print("Matches: %d | Seed: %d | Mode: %s" % [
		config.num_matches,
		rng_manager.base_seed,
		TestSessionConfig.ExecutionMode.keys()[config.execution_mode]
	])
	print("=" .repeat(60))
	print("")

	session_started.emit(config)

	# Generate or use provided matchups
	var matchups: Array[TestSessionConfig.MatchConfig] = []
	if config.matchups.is_empty():
		matchups = _generate_random_matchups(config.num_matches, config)
	else:
		matchups = config.matchups

	# Run each match
	print(">>> Starting %d matches" % matchups.size())
	for i in range(matchups.size()):
		print(">>> Match %d starting..." % (i + 1))
		if session_aborted:
			print("[SESSION] Aborted by user")
			break

		while session_paused and not session_aborted:
			# In a real async context we'd await, for now just a note
			pass

		current_match_index = i
		var match_config: TestSessionConfig.MatchConfig = matchups[i]

		print("[MATCH %d/%d] %s vs %s" % [
			i + 1, matches_total,
			"/".join(match_config.p1_champions),
			"/".join(match_config.p2_champions)
		])

		match_started.emit(i + 1, match_config.p1_champions, match_config.p2_champions)

		# Track match start for statistics
		statistics.begin_match(match_config.p1_champions, match_config.p2_champions)

		# Run the match
		match_runner = MatchRunner.new()
		match_runner.verbose = verbose
		match_runner.card_played.connect(_on_card_played)
		match_runner.debug_message.connect(_on_debug_message)

		var result := match_runner.run_match(match_config, rng_manager)
		match_results.append(result)

		# Record to statistics
		statistics.record_match_result(result)
		for play: MatchResult.CardPlayRecord in result.card_plays:
			statistics.record_card_play(play)

		# Record card usage statistics (draws, discards, held)
		for card_name: String in result.cards_drawn:
			var draw_count: int = result.cards_drawn[card_name]
			for _d in range(draw_count):
				statistics.record_card_drawn(card_name)
		for card_name: String in result.cards_discarded:
			var from_hand_limit: int = result.cards_discarded_hand_limit.get(card_name, 0)
			var other_discard: int = result.cards_discarded[card_name] - from_hand_limit
			for _h in range(from_hand_limit):
				statistics.record_card_discarded(card_name, true)
			for _o in range(other_discard):
				statistics.record_card_discarded(card_name, false)
		for card_name: String in result.cards_held_end_turn:
			var held_count: int = result.cards_held_end_turn[card_name]
			for _e in range(held_count):
				statistics.record_card_held_end_turn(card_name)

		matches_completed += 1

		# Report progress
		var winner_str := "Draw"
		if result.winner == 1:
			winner_str = "P1 (%s)" % "/".join(match_config.p1_champions)
		elif result.winner == 2:
			winner_str = "P2 (%s)" % "/".join(match_config.p2_champions)

		print("  → Winner: %s | Rounds: %d | No-ops: %d" % [
			winner_str,
			result.total_rounds,
			result.get_noop_plays().size()
		])

		if not result.errors.is_empty():
			for err: String in result.errors:
				print("  [ERROR] %s" % err)
				debug_message.emit("  [ERROR] Match %d: %s" % [i + 1, err])
				error_occurred.emit(i + 1, err)

		match_completed.emit(i + 1, result)
		session_progress.emit(matches_completed, matches_total, result)

	# Generate final report
	var report := _generate_report()

	print("")
	print("=" .repeat(60))
	print("   SESSION COMPLETE")
	print("=" .repeat(60))
	print(report.to_console_summary())

	session_active = false
	session_completed.emit(report)

	return report


func run_single_match(config: TestSessionConfig.MatchConfig) -> MatchResult:
	"""Run a single match without full session tracking."""
	match_runner = MatchRunner.new()
	return match_runner.run_match(config, rng_manager)


func pause_session() -> void:
	"""Pause the current session."""
	if session_active:
		session_paused = true
		print("[SESSION] Paused")


func resume_session() -> void:
	"""Resume a paused session."""
	if session_active and session_paused:
		session_paused = false
		print("[SESSION] Resumed")


func abort_session() -> void:
	"""Abort the current session."""
	if session_active:
		session_aborted = true
		print("[SESSION] Aborting...")


func get_progress() -> Dictionary:
	"""Get current session progress."""
	return {
		"completed": matches_completed,
		"total": matches_total,
		"percentage": float(matches_completed) / float(maxi(1, matches_total)) * 100.0,
		"active": session_active,
		"paused": session_paused
	}


func _generate_random_matchups(count: int, config: TestSessionConfig) -> Array[TestSessionConfig.MatchConfig]:
	"""Generate random champion matchups."""
	var matchups: Array[TestSessionConfig.MatchConfig] = []

	for i in range(count):
		var match_config := TestSessionConfig.MatchConfig.new()
		match_config.match_index = i
		match_config.p1_difficulty = config.p1_difficulty
		match_config.p2_difficulty = config.p2_difficulty

		# Pick random champions ensuring no duplicates
		var available := ALL_CHAMPIONS.duplicate()
		available.shuffle()

		# Must use typed arrays for GameController.initialize()
		var p1: Array[String] = []
		p1.append(available[0])
		p1.append(available[1])
		var p2: Array[String] = []
		p2.append(available[2])
		p2.append(available[3])

		match_config.p1_champions = p1
		match_config.p2_champions = p2

		matchups.append(match_config)

	return matchups


func generate_all_combinations(config: TestSessionConfig) -> Array[TestSessionConfig.MatchConfig]:
	"""Generate all possible champion pair matchups."""
	var matchups: Array[TestSessionConfig.MatchConfig] = []
	var match_index := 0

	# Generate all pairs for team 1
	var pairs: Array = []
	for i in range(ALL_CHAMPIONS.size()):
		for j in range(i + 1, ALL_CHAMPIONS.size()):
			pairs.append([ALL_CHAMPIONS[i], ALL_CHAMPIONS[j]])

	# Generate all matchups (each pair vs each pair)
	for i in range(pairs.size()):
		for j in range(i, pairs.size()):  # Include mirror matches
			var match_config := TestSessionConfig.MatchConfig.new()
			match_config.match_index = match_index
			match_config.p1_champions = pairs[i].duplicate()
			match_config.p2_champions = pairs[j].duplicate()
			match_config.p1_difficulty = config.p1_difficulty
			match_config.p2_difficulty = config.p2_difficulty
			matchups.append(match_config)
			match_index += 1

	return matchups


func _generate_report() -> SessionReport:
	"""Generate final session report."""
	var report := statistics.generate_report()

	# Session info
	report.session_id = "test_%s" % Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	report.started_at = Time.get_datetime_string_from_system()
	report.completed_at = Time.get_datetime_string_from_system()
	report.duration_seconds = float(Time.get_ticks_msec() - session_start_time) / 1000.0
	report.execution_mode = TestSessionConfig.ExecutionMode.keys()[session_config.execution_mode]
	report.base_seed = rng_manager.base_seed
	report.total_matches_requested = session_config.num_matches
	report.matches_errored = match_results.filter(func(r): return not r.errors.is_empty()).size()

	# Include match details if configured
	if session_config.save_match_details:
		for result: MatchResult in match_results:
			report.match_results.append(result.to_dict())

	return report


func _on_card_played(card_name: String, effect_result: EffectTracker.EffectResult) -> void:
	"""Handle card played signal from match runner."""
	# Statistics are recorded from the match result, this is for real-time tracking
	pass


func _on_debug_message(message: String) -> void:
	"""Forward debug messages."""
	debug_message.emit(message)


## Create a quick test configuration
static func create_quick_test(num_matches: int = 10, seed_value: int = 0) -> TestSessionConfig:
	"""Create a quick test configuration."""
	var config := TestSessionConfig.new()
	config.execution_mode = TestSessionConfig.ExecutionMode.HEADLESS
	config.num_matches = num_matches
	config.base_seed = seed_value
	config.p1_difficulty = 1  # MEDIUM
	config.p2_difficulty = 1  # MEDIUM
	return config


## Create a full combination test configuration
static func create_full_test(games_per_matchup: int = 1) -> TestSessionConfig:
	"""Create a configuration for testing all champion combinations."""
	var config := TestSessionConfig.new()
	config.execution_mode = TestSessionConfig.ExecutionMode.HEADLESS
	config.p1_difficulty = 1
	config.p2_difficulty = 1

	# Generate all matchups
	var orchestrator := TestOrchestrator.new()
	config.matchups = orchestrator.generate_all_combinations(config)

	# Duplicate for multiple games per matchup
	if games_per_matchup > 1:
		var expanded: Array[TestSessionConfig.MatchConfig] = []
		for matchup: TestSessionConfig.MatchConfig in config.matchups:
			for i in range(games_per_matchup):
				var copy := TestSessionConfig.MatchConfig.new()
				copy.match_index = expanded.size()
				copy.p1_champions = matchup.p1_champions.duplicate()
				copy.p2_champions = matchup.p2_champions.duplicate()
				copy.p1_difficulty = matchup.p1_difficulty
				copy.p2_difficulty = matchup.p2_difficulty
				expanded.append(copy)
		config.matchups = expanded

	config.num_matches = config.matchups.size()
	return config


## Create a specific matchup test configuration
static func create_matchup_test(
	p1_champs: Array[String],
	p2_champs: Array[String],
	num_matches: int = 10,
	seed_value: int = 0
) -> TestSessionConfig:
	"""Create a configuration for testing a specific matchup."""
	var config := TestSessionConfig.new()
	config.execution_mode = TestSessionConfig.ExecutionMode.HEADLESS
	config.num_matches = num_matches
	config.base_seed = seed_value
	config.p1_difficulty = 1
	config.p2_difficulty = 1

	# Generate matchups for the specific combination
	for i in range(num_matches):
		var match_config := TestSessionConfig.MatchConfig.new()
		match_config.match_index = i
		match_config.p1_champions = p1_champs.duplicate()
		match_config.p2_champions = p2_champs.duplicate()
		match_config.p1_difficulty = config.p1_difficulty
		match_config.p2_difficulty = config.p2_difficulty
		config.matchups.append(match_config)

	return config
