class_name SessionReport
extends RefCounted
## Complete report for a test session


## Unique session identifier
var session_id: String = ""

## When session started
var started_at: String = ""

## When session completed
var completed_at: String = ""

## Total duration in seconds
var duration_seconds: float = 0.0

## Configuration used
var execution_mode: String = "headless"
var base_seed: int = 0
var total_matches_requested: int = 0

## Match results summary
var matches_completed: int = 0
var matches_errored: int = 0
var player1_wins: int = 0
var player2_wins: int = 0
var draws: int = 0

## Aggregate statistics
var total_rounds: int = 0
var total_turns: int = 0
var avg_rounds_per_match: float = 0.0
var avg_turns_per_match: float = 0.0

## Card statistics (card_name -> CardStats.to_dict())
var card_statistics: Dictionary = {}

## Champion statistics (champion_name -> ChampionStats.to_dict())
var champion_statistics: Dictionary = {}

## Champion pair statistics ("ChampA+ChampB" -> pair_data)
var pair_statistics: Dictionary = {}

## Matchup statistics ("TeamA vs TeamB" -> matchup_data)
var matchup_statistics: Dictionary = {}

## No-op analysis
var high_noop_cards: Array[Dictionary] = []  # Cards with >20% no-op rate
var total_card_plays: int = 0
var total_noop_plays: int = 0

## Balance indicators
var win_rate_by_champion: Dictionary = {}  # champion_name -> win_rate
var most_impactful_cards: Array[Dictionary] = []  # Top 10 by win correlation
var least_impactful_cards: Array[Dictionary] = []  # Bottom 10 by win correlation

## Card usage analysis
var low_usage_cards: Array[Dictionary] = []  # Cards drawn but rarely played
var high_discard_cards: Array[Dictionary] = []  # Cards frequently discarded
var never_played_cards: Array[Dictionary] = []  # Cards drawn but never played

## Individual match results (if save_match_details is true)
var match_results: Array[Dictionary] = []


func _init() -> void:
	card_statistics = {}
	champion_statistics = {}
	pair_statistics = {}
	matchup_statistics = {}
	high_noop_cards = []
	win_rate_by_champion = {}
	most_impactful_cards = []
	least_impactful_cards = []
	low_usage_cards = []
	high_discard_cards = []
	never_played_cards = []
	match_results = []


## Overall no-op rate
var overall_noop_rate: float:
	get:
		if total_card_plays == 0:
			return 0.0
		return float(total_noop_plays) / float(total_card_plays)


## Player 1 win rate
var p1_win_rate: float:
	get:
		if matches_completed == 0:
			return 0.5
		return float(player1_wins) / float(matches_completed)


## Player 2 win rate
var p2_win_rate: float:
	get:
		if matches_completed == 0:
			return 0.5
		return float(player2_wins) / float(matches_completed)


func to_json() -> String:
	"""Convert to JSON string."""
	return JSON.stringify(to_dict(), "\t")


func to_dict() -> Dictionary:
	"""Convert to dictionary for serialization."""
	return {
		"session_info": {
			"session_id": session_id,
			"started_at": started_at,
			"completed_at": completed_at,
			"duration_seconds": duration_seconds,
			"execution_mode": execution_mode,
			"base_seed": base_seed
		},
		"summary": {
			"matches_requested": total_matches_requested,
			"matches_completed": matches_completed,
			"matches_errored": matches_errored,
			"player1_wins": player1_wins,
			"player2_wins": player2_wins,
			"draws": draws,
			"p1_win_rate": p1_win_rate,
			"p2_win_rate": p2_win_rate,
			"total_rounds": total_rounds,
			"total_turns": total_turns,
			"avg_rounds_per_match": avg_rounds_per_match,
			"avg_turns_per_match": avg_turns_per_match
		},
		"card_statistics": card_statistics,
		"champion_statistics": champion_statistics,
		"pair_statistics": pair_statistics,
		"matchup_statistics": matchup_statistics,
		"noop_analysis": {
			"total_card_plays": total_card_plays,
			"total_noop_plays": total_noop_plays,
			"overall_noop_rate": overall_noop_rate,
			"high_noop_cards": high_noop_cards
		},
		"balance_indicators": {
			"win_rate_by_champion": win_rate_by_champion,
			"most_impactful_cards": most_impactful_cards,
			"least_impactful_cards": least_impactful_cards
		},
		"card_usage_analysis": {
			"low_usage_cards": low_usage_cards,
			"high_discard_cards": high_discard_cards,
			"never_played_cards": never_played_cards
		},
		"match_results": match_results
	}


func to_console_summary() -> String:
	"""Generate console-friendly summary."""
	var lines: Array[String] = []

	lines.append("=" .repeat(70))
	lines.append("                 ARENA AI VS AI TEST REPORT")
	lines.append("=" .repeat(70))
	lines.append("")
	lines.append("Session: %s" % session_id)
	lines.append("Duration: %.1fs | Seed: %d" % [duration_seconds, base_seed])
	lines.append("")
	lines.append("SUMMARY")
	lines.append("-" .repeat(70))
	lines.append("Matches: %d/%d completed | Errors: %d" % [matches_completed, total_matches_requested, matches_errored])
	lines.append("P1 Wins: %d (%.1f%%) | P2 Wins: %d (%.1f%%) | Draws: %d" % [
		player1_wins, p1_win_rate * 100,
		player2_wins, p2_win_rate * 100,
		draws
	])
	lines.append("Avg Rounds: %.1f | Avg Turns: %.1f" % [avg_rounds_per_match, avg_turns_per_match])
	lines.append("")

	# Champion win rates
	if not win_rate_by_champion.is_empty():
		lines.append("CHAMPION WIN RATES")
		lines.append("-" .repeat(70))
		var sorted_champs: Array = win_rate_by_champion.keys()
		sorted_champs.sort_custom(func(a, b): return win_rate_by_champion[b] < win_rate_by_champion[a])
		for champ: String in sorted_champs:
			var rate: float = win_rate_by_champion[champ]
			var bar := _make_bar(rate, 20)
			lines.append("  %s: %s %.1f%%" % [champ.substr(0, 12).rpad(12), bar, rate * 100])
		lines.append("")

	# No-op cards
	if not high_noop_cards.is_empty():
		lines.append("NO-OP CARDS (>20%% no-op rate)")
		lines.append("-" .repeat(70))
		lines.append("  %-20s | %s | %s | %s" % ["Card", "Played", "No-Op", "Rate"])
		lines.append("  " + "-" .repeat(60))
		for card: Dictionary in high_noop_cards.slice(0, 10):
			lines.append("  %-20s | %6d | %6d | %5.1f%%" % [
				card.get("card_name", "?").substr(0, 20),
				card.get("times_played", 0),
				card.get("noop_count", 0),
				card.get("noop_rate", 0) * 100
			])
		lines.append("")

	# Most impactful cards
	if not most_impactful_cards.is_empty():
		lines.append("MOST IMPACTFUL CARDS (highest win correlation)")
		lines.append("-" .repeat(70))
		for card: Dictionary in most_impactful_cards.slice(0, 5):
			lines.append("  %-20s: %.1f%% win rate when played" % [
				card.get("card_name", "?").substr(0, 20),
				card.get("win_rate", 0.5) * 100
			])
		lines.append("")

	lines.append("=" .repeat(70))

	return "\n".join(lines)


func _make_bar(value: float, width: int) -> String:
	"""Create a simple text bar chart."""
	var filled := int(value * width)
	var empty := width - filled
	return "[" + "#" .repeat(filled) + "-" .repeat(empty) + "]"


func save_to_file(path: String) -> bool:
	"""Save report to JSON file."""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_json())
	file.close()
	return true


static func load_from_file(path: String) -> SessionReport:
	"""Load report from JSON file."""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_str)
	if error != OK:
		return null

	var report := SessionReport.new()
	var data: Dictionary = json.data

	# Session info
	var info: Dictionary = data.get("session_info", {})
	report.session_id = info.get("session_id", "")
	report.started_at = info.get("started_at", "")
	report.completed_at = info.get("completed_at", "")
	report.duration_seconds = info.get("duration_seconds", 0.0)
	report.execution_mode = info.get("execution_mode", "headless")
	report.base_seed = info.get("base_seed", 0)

	# Summary
	var summary: Dictionary = data.get("summary", {})
	report.total_matches_requested = summary.get("matches_requested", 0)
	report.matches_completed = summary.get("matches_completed", 0)
	report.matches_errored = summary.get("matches_errored", 0)
	report.player1_wins = summary.get("player1_wins", 0)
	report.player2_wins = summary.get("player2_wins", 0)
	report.draws = summary.get("draws", 0)
	report.total_rounds = summary.get("total_rounds", 0)
	report.total_turns = summary.get("total_turns", 0)
	report.avg_rounds_per_match = summary.get("avg_rounds_per_match", 0.0)
	report.avg_turns_per_match = summary.get("avg_turns_per_match", 0.0)

	# Statistics
	report.card_statistics = data.get("card_statistics", {})
	report.champion_statistics = data.get("champion_statistics", {})
	report.pair_statistics = data.get("pair_statistics", {})

	# No-op analysis
	var noop: Dictionary = data.get("noop_analysis", {})
	report.total_card_plays = noop.get("total_card_plays", 0)
	report.total_noop_plays = noop.get("total_noop_plays", 0)
	report.high_noop_cards = []
	for card_data in noop.get("high_noop_cards", []):
		report.high_noop_cards.append(card_data)

	# Balance indicators
	var balance: Dictionary = data.get("balance_indicators", {})
	report.win_rate_by_champion = balance.get("win_rate_by_champion", {})
	report.most_impactful_cards = []
	for card_data in balance.get("most_impactful_cards", []):
		report.most_impactful_cards.append(card_data)
	report.least_impactful_cards = []
	for card_data in balance.get("least_impactful_cards", []):
		report.least_impactful_cards.append(card_data)

	# Match results
	report.match_results = []
	for match_data in data.get("match_results", []):
		report.match_results.append(match_data)

	return report
