class_name ConsoleReporter
extends RefCounted
## Formats and prints session reports to the console


const SEPARATOR := "=" .repeat(70)
const LINE := "-" .repeat(70)


func print_report(report: SessionReport) -> void:
	"""Print complete session report to console."""
	print("")
	print(SEPARATOR)
	print("                 ARENA AI VS AI TEST REPORT")
	print(SEPARATOR)
	print("")

	_print_session_info(report)
	_print_summary(report)
	_print_champion_stats(report)
	_print_pair_stats(report)
	_print_matchup_stats(report)
	_print_noop_analysis(report)
	_print_card_usage_analysis(report)
	_print_impactful_cards(report)

	print(SEPARATOR)
	print("")


func print_progress(completed: int, total: int, last_result: MatchResult = null) -> void:
	"""Print progress update."""
	var pct := float(completed) / float(maxi(1, total)) * 100.0
	var bar := _make_progress_bar(pct, 30)

	print("[%s] %d/%d (%.1f%%)" % [bar, completed, total, pct])

	if last_result != null:
		var winner_str := "Draw"
		if last_result.winner == 1:
			winner_str = "P1"
		elif last_result.winner == 2:
			winner_str = "P2"
		print("  Last: %s won in %d rounds" % [winner_str, last_result.total_rounds])


func _print_session_info(report: SessionReport) -> void:
	"""Print session information."""
	print("Session: %s" % report.session_id)
	print("Duration: %.1fs | Seed: %d | Mode: %s" % [
		report.duration_seconds,
		report.base_seed,
		report.execution_mode
	])
	print("")


func _print_summary(report: SessionReport) -> void:
	"""Print summary statistics."""
	print("SUMMARY")
	print(LINE)
	print("Matches: %d/%d completed | Errors: %d" % [
		report.matches_completed,
		report.total_matches_requested,
		report.matches_errored
	])
	print("P1 Wins: %d (%.1f%%) | P2 Wins: %d (%.1f%%) | Draws: %d" % [
		report.player1_wins, report.p1_win_rate * 100,
		report.player2_wins, report.p2_win_rate * 100,
		report.draws
	])
	print("Avg Rounds: %.1f | Avg Turns: %.1f" % [
		report.avg_rounds_per_match,
		report.avg_turns_per_match
	])
	print("Card Plays: %d | No-ops: %d (%.1f%%)" % [
		report.total_card_plays,
		report.total_noop_plays,
		report.overall_noop_rate * 100
	])
	print("")


func _print_champion_stats(report: SessionReport) -> void:
	"""Print champion statistics."""
	if report.champion_statistics.is_empty():
		return

	print("CHAMPION WIN RATES")
	print(LINE)

	# Sort by win rate
	var sorted_champs: Array = report.win_rate_by_champion.keys()
	sorted_champs.sort_custom(func(a, b): return report.win_rate_by_champion[b] < report.win_rate_by_champion[a])

	print("%-15s | %s | %s | %s" % ["Champion", "Win Rate", "Picks", "K/D"])
	print("-" .repeat(50))

	for champ: String in sorted_champs:
		var stats: Dictionary = report.champion_statistics.get(champ, {})
		var win_rate: float = stats.get("win_rate", 0.5)
		var picks: int = stats.get("times_picked", 0)
		var kd: float = stats.get("kd_ratio", 0.0)
		var bar := _make_bar(win_rate, 10)

		print("%-15s | %s %.1f%% | %5d | %.2f" % [
			champ.substr(0, 15),
			bar,
			win_rate * 100,
			picks,
			kd
		])

	print("")


func _print_pair_stats(report: SessionReport) -> void:
	"""Print champion pair (team) statistics."""
	if report.pair_statistics.is_empty():
		return

	print("TEAM PAIR WIN RATES (champions paired together)")
	print(LINE)

	# Collect and sort pairs by win rate
	var pairs: Array = []
	for pair_key: String in report.pair_statistics:
		var stats: Dictionary = report.pair_statistics[pair_key]
		if stats.get("times_paired", 0) >= 2:  # Minimum sample
			pairs.append({
				"key": pair_key,
				"win_rate": stats.get("win_rate", 0.5),
				"times": stats.get("times_paired", 0),
				"wins": stats.get("wins", 0),
				"losses": stats.get("losses", 0)
			})

	pairs.sort_custom(func(a, b): return a["win_rate"] > b["win_rate"])

	print("%-25s | %s | %s | %s" % ["Team", "Win Rate", "W-L", "Games"])
	print("-" .repeat(55))

	for pair: Dictionary in pairs.slice(0, 15):
		var bar := _make_bar(pair["win_rate"], 10)
		print("%-25s | %s %5.1f%% | %2d-%2d | %3d" % [
			pair["key"].substr(0, 25),
			bar,
			pair["win_rate"] * 100,
			pair["wins"],
			pair["losses"],
			pair["times"]
		])

	print("")


func _print_matchup_stats(report: SessionReport) -> void:
	"""Print team vs team matchup statistics."""
	if report.matchup_statistics.is_empty():
		return

	print("TEAM VS TEAM MATCHUPS")
	print(LINE)

	# Collect and sort matchups by total games
	var matchups: Array = []
	for matchup_key: String in report.matchup_statistics:
		var stats: Dictionary = report.matchup_statistics[matchup_key]
		if stats.get("times_played", 0) >= 2:  # Minimum sample
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

	print("%-40s | %s | %s" % ["Matchup", "Record", "T1 WR"])
	print("-" .repeat(60))

	for matchup: Dictionary in matchups.slice(0, 12):
		var t1_str := "/".join(matchup["team1"]) if matchup["team1"] else "?"
		var t2_str := "/".join(matchup["team2"]) if matchup["team2"] else "?"
		var matchup_str := "%s vs %s" % [t1_str.substr(0, 18), t2_str.substr(0, 18)]
		var record_str := "%d-%d-%d" % [matchup["team1_wins"], matchup["team2_wins"], matchup["draws"]]

		print("%-40s | %7s | %5.1f%%" % [
			matchup_str,
			record_str,
			matchup["team1_win_rate"] * 100
		])

	print("")


func _print_noop_analysis(report: SessionReport) -> void:
	"""Print no-op card analysis."""
	if report.high_noop_cards.is_empty():
		return

	print("NO-OP CARDS (>20%% no-op rate)")
	print(LINE)
	print("%-20s | %s | %s | %s | %s" % ["Card", "Played", "No-Op", "Rate", "Reason"])
	print("-" .repeat(65))

	for card: Dictionary in report.high_noop_cards.slice(0, 15):
		print("%-20s | %6d | %6d | %5.1f%% | %s" % [
			str(card.get("card_name", "?")).substr(0, 20),
			card.get("times_played", 0),
			card.get("noop_count", 0),
			card.get("noop_rate", 0) * 100,
			str(card.get("common_reason", "")).substr(0, 20)
		])

	print("")


func _print_impactful_cards(report: SessionReport) -> void:
	"""Print most and least impactful cards."""
	if not report.most_impactful_cards.is_empty():
		print("MOST IMPACTFUL CARDS (highest win correlation)")
		print(LINE)

		for card: Dictionary in report.most_impactful_cards.slice(0, 5):
			print("  %-20s: %.1f%% win rate (%d plays)" % [
				str(card.get("card_name", "?")).substr(0, 20),
				card.get("win_rate", 0.5) * 100,
				card.get("times_played", 0)
			])

		print("")

	if not report.least_impactful_cards.is_empty():
		print("LEAST IMPACTFUL CARDS (lowest win correlation)")
		print(LINE)

		for card: Dictionary in report.least_impactful_cards.slice(0, 5):
			print("  %-20s: %.1f%% win rate (%d plays)" % [
				str(card.get("card_name", "?")).substr(0, 20),
				card.get("win_rate", 0.5) * 100,
				card.get("times_played", 0)
			])

		print("")


func _print_card_usage_analysis(report: SessionReport) -> void:
	"""Print card usage analysis (never used, always discarded)."""
	# Never played cards
	if not report.never_played_cards.is_empty():
		print("NEVER PLAYED CARDS (drawn but never used)")
		print(LINE)
		print("%-20s | %s | %s | %s" % ["Card", "Drawn", "Held", "Discarded"])
		print("-" .repeat(55))

		for card: Dictionary in report.never_played_cards.slice(0, 10):
			print("%-20s | %6d | %6d | %6d" % [
				str(card.get("card_name", "?")).substr(0, 20),
				card.get("times_drawn", 0),
				card.get("times_held", 0),
				card.get("times_discarded", 0)
			])

		print("")

	# Low usage cards (drawn but rarely played)
	if not report.low_usage_cards.is_empty():
		print("LOW USAGE CARDS (<30%% of draws played)")
		print(LINE)
		print("%-20s | %s | %s | %s" % ["Card", "Drawn", "Played", "Usage%"])
		print("-" .repeat(55))

		for card: Dictionary in report.low_usage_cards.slice(0, 10):
			print("%-20s | %6d | %6d | %5.1f%%" % [
				str(card.get("card_name", "?")).substr(0, 20),
				card.get("times_drawn", 0),
				card.get("times_played", 0),
				card.get("usage_rate", 0) * 100
			])

		print("")

	# High discard cards
	if not report.high_discard_cards.is_empty():
		print("HIGH DISCARD CARDS (>30%% of draws discarded)")
		print(LINE)
		print("%-20s | %s | %s | %s | %s" % ["Card", "Drawn", "Discarded", "HandLim", "Rate%"])
		print("-" .repeat(65))

		for card: Dictionary in report.high_discard_cards.slice(0, 10):
			print("%-20s | %6d | %6d | %6d | %5.1f%%" % [
				str(card.get("card_name", "?")).substr(0, 20),
				card.get("times_drawn", 0),
				card.get("times_discarded", 0),
				card.get("times_discarded_hand_limit", 0),
				card.get("discard_rate", 0) * 100
			])

		print("")


func _make_bar(value: float, width: int) -> String:
	"""Create a simple text bar."""
	var filled := int(value * width)
	var empty := width - filled
	return "[" + "#" .repeat(filled) + "-" .repeat(empty) + "]"


func _make_progress_bar(percent: float, width: int) -> String:
	"""Create a progress bar."""
	var filled := int(percent / 100.0 * width)
	var empty := width - filled
	return "#" .repeat(filled) + "-" .repeat(empty)
