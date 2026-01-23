class_name JsonReporter
extends RefCounted
## Outputs session reports as JSON files


## Default output directory
const DEFAULT_OUTPUT_DIR := "user://test_reports/"


func write_report(report: SessionReport, path: String = "") -> bool:
	"""Write report to a JSON file."""
	var output_path := path
	if output_path.is_empty():
		output_path = _get_default_path(report)

	# Ensure directory exists
	var dir := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

	# Write JSON
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("JsonReporter: Failed to open file: %s" % output_path)
		return false

	file.store_string(report.to_json())
	file.close()

	print("[JSON] Report saved to: %s" % ProjectSettings.globalize_path(output_path))
	return true


func write_match_result(result: MatchResult, path: String = "") -> bool:
	"""Write a single match result to JSON."""
	var output_path := path
	if output_path.is_empty():
		output_path = DEFAULT_OUTPUT_DIR + "match_%d_%s.json" % [
			result.match_id,
			Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		]

	var dir := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(result.to_dict(), "\t"))
	file.close()

	return true


func write_card_stats(card_stats: Dictionary, path: String = "") -> bool:
	"""Write card statistics to a separate JSON file."""
	var output_path := path
	if output_path.is_empty():
		output_path = DEFAULT_OUTPUT_DIR + "card_stats_%s.json" % [
			Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		]

	var dir := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(card_stats, "\t"))
	file.close()

	print("[JSON] Card stats saved to: %s" % ProjectSettings.globalize_path(output_path))
	return true


func write_champion_stats(champion_stats: Dictionary, path: String = "") -> bool:
	"""Write champion statistics to a separate JSON file."""
	var output_path := path
	if output_path.is_empty():
		output_path = DEFAULT_OUTPUT_DIR + "champion_stats_%s.json" % [
			Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		]

	var dir := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(champion_stats, "\t"))
	file.close()

	print("[JSON] Champion stats saved to: %s" % ProjectSettings.globalize_path(output_path))
	return true


func write_noop_analysis(report: SessionReport, path: String = "") -> bool:
	"""Write no-op analysis to a separate JSON file."""
	var output_path := path
	if output_path.is_empty():
		output_path = DEFAULT_OUTPUT_DIR + "noop_analysis_%s.json" % [
			Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		]

	var dir := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return false

	var noop_data := {
		"total_card_plays": report.total_card_plays,
		"total_noop_plays": report.total_noop_plays,
		"overall_noop_rate": report.overall_noop_rate,
		"high_noop_cards": report.high_noop_cards,
		"cards_by_noop_rate": _sort_cards_by_noop_rate(report.card_statistics)
	}

	file.store_string(JSON.stringify(noop_data, "\t"))
	file.close()

	print("[JSON] No-op analysis saved to: %s" % ProjectSettings.globalize_path(output_path))
	return true


func _get_default_path(report: SessionReport) -> String:
	"""Generate default output path for a report."""
	return DEFAULT_OUTPUT_DIR + "report_%s.json" % report.session_id


func _sort_cards_by_noop_rate(card_stats: Dictionary) -> Array:
	"""Sort cards by no-op rate for analysis."""
	var cards: Array = []

	for card_name: String in card_stats:
		var stats: Dictionary = card_stats[card_name]
		cards.append({
			"card_name": card_name,
			"champion": stats.get("champion", ""),
			"times_played": stats.get("times_played", 0),
			"noop_count": stats.get("noop_count", 0),
			"noop_rate": stats.get("noop_rate", 0.0)
		})

	cards.sort_custom(func(a, b): return a["noop_rate"] > b["noop_rate"])
	return cards


## Load a report from JSON file
static func load_report(path: String) -> SessionReport:
	"""Load a session report from a JSON file."""
	return SessionReport.load_from_file(path)
