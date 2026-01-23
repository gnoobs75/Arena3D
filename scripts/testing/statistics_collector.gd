class_name StatisticsCollector
extends RefCounted
## Collects and aggregates statistics across multiple matches


signal statistics_updated()


## Card statistics (card_name -> CardStats)
var card_stats: Dictionary = {}

## Champion statistics (champion_name -> ChampionStats)
var champion_stats: Dictionary = {}

## Champion pair statistics ("ChampA+ChampB" -> PairStats)
var pair_stats: Dictionary = {}

## Matchup statistics ("TeamA vs TeamB" -> MatchupStats)
var matchup_stats: Dictionary = {}

## Match-level statistics
var total_matches: int = 0
var player1_wins: int = 0
var player2_wins: int = 0
var draws: int = 0
var total_rounds: int = 0
var total_turns: int = 0
var total_card_plays: int = 0
var total_noop_plays: int = 0
var total_errors: int = 0

## Cards played in current match (for win correlation tracking)
var _current_match_cards_p1: Array[String] = []
var _current_match_cards_p2: Array[String] = []

## Champions in current match
var _current_match_p1_champs: Array[String] = []
var _current_match_p2_champs: Array[String] = []


func _init() -> void:
	card_stats = {}
	champion_stats = {}
	pair_stats = {}
	matchup_stats = {}
	_current_match_cards_p1 = []
	_current_match_cards_p2 = []
	_current_match_p1_champs = []
	_current_match_p2_champs = []


func reset() -> void:
	"""Reset all statistics."""
	card_stats.clear()
	champion_stats.clear()
	pair_stats.clear()
	matchup_stats.clear()
	total_matches = 0
	player1_wins = 0
	player2_wins = 0
	draws = 0
	total_rounds = 0
	total_turns = 0
	total_card_plays = 0
	total_noop_plays = 0
	total_errors = 0


func begin_match(p1_champions: Array[String], p2_champions: Array[String]) -> void:
	"""Begin tracking a new match."""
	_current_match_cards_p1 = []
	_current_match_cards_p2 = []
	_current_match_p1_champs = p1_champions.duplicate()
	_current_match_p2_champs = p2_champions.duplicate()

	# Record champion picks
	for champ_name: String in p1_champions:
		_get_or_create_champion_stats(champ_name).record_pick(1)
	for champ_name: String in p2_champions:
		_get_or_create_champion_stats(champ_name).record_pick(2)

	# Record pair picks
	_record_pair_pick(p1_champions, 1)
	_record_pair_pick(p2_champions, 2)


func record_match_result(result: MatchResult) -> void:
	"""Record the result of a completed match."""
	total_matches += 1
	total_rounds += result.total_rounds
	total_turns += result.total_turns
	total_errors += result.errors.size()

	# Record win/loss
	match result.winner:
		0:
			draws += 1
		1:
			player1_wins += 1
		2:
			player2_wins += 1

	# Record champion outcomes
	var p1_won := result.winner == 1
	var p2_won := result.winner == 2

	for champ_name: String in result.p1_champions:
		var stats := _get_or_create_champion_stats(champ_name)
		stats.record_match_outcome(p1_won)

	for champ_name: String in result.p2_champions:
		var stats := _get_or_create_champion_stats(champ_name)
		stats.record_match_outcome(p2_won)

	# Record pair outcomes
	_record_pair_outcome(result.p1_champions, p1_won)
	_record_pair_outcome(result.p2_champions, p2_won)

	# Record matchup
	_record_matchup(result.p1_champions, result.p2_champions, result.winner)

	# Record card outcomes (win correlation)
	for card_name: String in _current_match_cards_p1:
		_get_or_create_card_stats(card_name).record_match_outcome(p1_won)
	for card_name: String in _current_match_cards_p2:
		_get_or_create_card_stats(card_name).record_match_outcome(p2_won)

	# Record final HP/survival
	for champ_id: String in result.final_champion_hp:
		var hp: int = result.final_champion_hp[champ_id]
		var champ_name := _extract_champion_name(champ_id)
		if champ_name.is_empty():
			continue

		var stats := _get_or_create_champion_stats(champ_name)
		if hp <= 0:
			stats.record_death(result.total_rounds)
		else:
			stats.record_survived_match(result.total_rounds)

	statistics_updated.emit()


func record_card_play(play: MatchResult.CardPlayRecord, effect_result: EffectTracker.EffectResult = null) -> void:
	"""Record a card being played."""
	total_card_plays += 1

	var stats := _get_or_create_card_stats(play.card_name)
	stats.record_play(play.player_id, play.mana_available)
	stats.total_mana_spent += play.mana_cost

	# Track cards for win correlation
	if play.player_id == 1:
		if play.card_name not in _current_match_cards_p1:
			_current_match_cards_p1.append(play.card_name)
	else:
		if play.card_name not in _current_match_cards_p2:
			_current_match_cards_p2.append(play.card_name)

	# Record effects
	if effect_result != null:
		stats.record_effect(
			effect_result.damage_dealt,
			effect_result.healing_done,
			effect_result.buffs_applied,
			effect_result.debuffs_applied,
			effect_result.movements_caused,
			effect_result.cards_drawn
		)

		if effect_result.is_noop:
			total_noop_plays += 1
			stats.record_noop(effect_result.noop_reason)
	elif play.is_noop:
		total_noop_plays += 1
		stats.record_noop(play.noop_reason)
		stats.record_effect(
			play.damage_dealt,
			play.healing_done,
			play.buffs_applied,
			play.debuffs_applied,
			play.movements_caused,
			play.cards_drawn
		)
	else:
		stats.record_effect(
			play.damage_dealt,
			play.healing_done,
			play.buffs_applied,
			play.debuffs_applied,
			play.movements_caused,
			play.cards_drawn
		)

	# Record champion card play
	var champ_name := play.caster_name
	if not champ_name.is_empty():
		_get_or_create_champion_stats(champ_name).record_card_played(play.is_noop)


func record_champion_damage(champion_name: String, damage: int, is_dealt: bool) -> void:
	"""Record damage dealt or taken by a champion."""
	var stats := _get_or_create_champion_stats(champion_name)
	if is_dealt:
		stats.record_damage_dealt(damage)
	else:
		stats.record_damage_taken(damage)


func record_champion_healing(champion_name: String, healing: int, is_done: bool) -> void:
	"""Record healing done or received by a champion."""
	var stats := _get_or_create_champion_stats(champion_name)
	if is_done:
		stats.record_healing_done(healing)
	else:
		stats.record_healing_received(healing)


func record_champion_kill(killer_name: String, card_name: String = "") -> void:
	"""Record a kill by a champion."""
	if not killer_name.is_empty():
		_get_or_create_champion_stats(killer_name).record_kill()
	if not card_name.is_empty():
		_get_or_create_card_stats(card_name).record_kill()


func record_card_drawn(card_name: String) -> void:
	"""Record that a card was drawn into hand."""
	_get_or_create_card_stats(card_name).record_drawn()


func record_card_held_end_turn(card_name: String) -> void:
	"""Record that a card was held at end of turn without being played."""
	_get_or_create_card_stats(card_name).record_held_end_turn()


func record_card_discarded(card_name: String, from_hand_limit: bool = false) -> void:
	"""Record that a card was discarded."""
	_get_or_create_card_stats(card_name).record_discarded(from_hand_limit)


func generate_report() -> SessionReport:
	"""Generate a complete session report."""
	var report := SessionReport.new()

	# Summary
	report.matches_completed = total_matches
	report.player1_wins = player1_wins
	report.player2_wins = player2_wins
	report.draws = draws
	report.total_rounds = total_rounds
	report.total_turns = total_turns
	report.total_card_plays = total_card_plays
	report.total_noop_plays = total_noop_plays

	if total_matches > 0:
		report.avg_rounds_per_match = float(total_rounds) / float(total_matches)
		report.avg_turns_per_match = float(total_turns) / float(total_matches)

	# Card statistics
	for card_name: String in card_stats:
		var stats: CardStats = card_stats[card_name]
		report.card_statistics[card_name] = stats.to_dict()

	# Champion statistics
	for champ_name: String in champion_stats:
		var stats: ChampionStats = champion_stats[champ_name]
		report.champion_statistics[champ_name] = stats.to_dict()
		report.win_rate_by_champion[champ_name] = stats.win_rate

	# Pair statistics
	for pair_key: String in pair_stats:
		report.pair_statistics[pair_key] = pair_stats[pair_key].to_dict()

	# Matchup statistics (team vs team)
	for matchup_key: String in matchup_stats:
		report.matchup_statistics[matchup_key] = matchup_stats[matchup_key].to_dict()

	# No-op analysis
	report.high_noop_cards = _get_high_noop_cards(0.20)

	# Impactful cards analysis
	report.most_impactful_cards = _get_most_impactful_cards(10)
	report.least_impactful_cards = _get_least_impactful_cards(10)

	# Card usage analysis
	report.low_usage_cards = _get_low_usage_cards(0.30)  # Cards played less than 30% of draws
	report.high_discard_cards = _get_high_discard_cards(0.30)  # Cards discarded more than 30% of draws
	report.never_played_cards = _get_never_played_cards()  # Cards drawn but never played

	return report


func _get_or_create_card_stats(card_name: String) -> CardStats:
	"""Get or create card stats entry."""
	if not card_stats.has(card_name):
		var card_data := CardDatabase.get_card(card_name)
		card_stats[card_name] = CardStats.new(
			card_name,
			str(card_data.get("character", "")),
			str(card_data.get("type", ""))
		)
	return card_stats[card_name]


func _get_or_create_champion_stats(champion_name: String) -> ChampionStats:
	"""Get or create champion stats entry."""
	if not champion_stats.has(champion_name):
		champion_stats[champion_name] = ChampionStats.new(champion_name)
	return champion_stats[champion_name]


func _record_pair_pick(champions: Array[String], player_id: int) -> void:
	"""Record a champion pair pick."""
	if champions.size() != 2:
		return
	var pair_key := _make_pair_key(champions[0], champions[1])
	if not pair_stats.has(pair_key):
		pair_stats[pair_key] = PairStats.new(champions[0], champions[1])
	pair_stats[pair_key].times_paired += 1


func _record_pair_outcome(champions: Array[String], won: bool) -> void:
	"""Record win/loss for a champion pair."""
	if champions.size() != 2:
		return
	var pair_key := _make_pair_key(champions[0], champions[1])
	if pair_stats.has(pair_key):
		if won:
			pair_stats[pair_key].wins += 1
		else:
			pair_stats[pair_key].losses += 1


func _record_matchup(p1_champs: Array[String], p2_champs: Array[String], winner: int) -> void:
	"""Record a matchup result."""
	var matchup_key := _make_matchup_key(p1_champs, p2_champs)
	if not matchup_stats.has(matchup_key):
		matchup_stats[matchup_key] = MatchupStats.new(p1_champs, p2_champs)

	var stats: MatchupStats = matchup_stats[matchup_key]
	stats.times_played += 1
	if winner == 1:
		stats.team1_wins += 1
	elif winner == 2:
		stats.team2_wins += 1
	else:
		stats.draws += 1


func _make_pair_key(champ1: String, champ2: String) -> String:
	"""Create consistent key for a champion pair."""
	var sorted_champs := [champ1, champ2]
	sorted_champs.sort()
	return "%s+%s" % [sorted_champs[0], sorted_champs[1]]


func _make_matchup_key(team1: Array[String], team2: Array[String]) -> String:
	"""Create consistent key for a matchup."""
	var t1 := team1.duplicate()
	var t2 := team2.duplicate()
	t1.sort()
	t2.sort()
	return "%s/%s vs %s/%s" % [t1[0], t1[1], t2[0], t2[1]]


func _extract_champion_name(champion_id: String) -> String:
	"""Extract champion name from unique ID (e.g., 'brute_p1_0' -> 'Brute')."""
	var parts := champion_id.split("_")
	if parts.size() > 0:
		return parts[0].capitalize()
	return ""


func _get_high_noop_cards(threshold: float) -> Array[Dictionary]:
	"""Get cards with no-op rate above threshold."""
	var result: Array[Dictionary] = []

	for card_name: String in card_stats:
		var stats: CardStats = card_stats[card_name]
		if stats.times_played >= 5 and stats.noop_rate >= threshold:
			result.append({
				"card_name": card_name,
				"champion": stats.champion,
				"times_played": stats.times_played,
				"noop_count": stats.noop_count,
				"noop_rate": stats.noop_rate,
				"common_reason": stats.get_most_common_noop_reason()
			})

	# Sort by no-op rate descending
	result.sort_custom(func(a, b): return a["noop_rate"] > b["noop_rate"])

	return result


func _get_most_impactful_cards(count: int) -> Array[Dictionary]:
	"""Get cards with highest win rate correlation."""
	var result: Array[Dictionary] = []

	for card_name: String in card_stats:
		var stats: CardStats = card_stats[card_name]
		if stats.times_played >= 10:  # Minimum sample size
			result.append({
				"card_name": card_name,
				"champion": stats.champion,
				"times_played": stats.times_played,
				"win_rate": stats.win_rate_when_played,
				"avg_damage": stats.avg_damage_per_play,
				"avg_healing": stats.avg_healing_per_play
			})

	# Sort by win rate descending
	result.sort_custom(func(a, b): return a["win_rate"] > b["win_rate"])

	return result.slice(0, count)


func _get_least_impactful_cards(count: int) -> Array[Dictionary]:
	"""Get cards with lowest win rate correlation (excluding high no-op)."""
	var result: Array[Dictionary] = []

	for card_name: String in card_stats:
		var stats: CardStats = card_stats[card_name]
		if stats.times_played >= 10 and stats.noop_rate < 0.3:  # Exclude mostly broken cards
			result.append({
				"card_name": card_name,
				"champion": stats.champion,
				"times_played": stats.times_played,
				"win_rate": stats.win_rate_when_played,
				"avg_damage": stats.avg_damage_per_play,
				"avg_healing": stats.avg_healing_per_play
			})

	# Sort by win rate ascending
	result.sort_custom(func(a, b): return a["win_rate"] < b["win_rate"])

	return result.slice(0, count)


func _get_low_usage_cards(threshold: float) -> Array[Dictionary]:
	"""Get cards with low usage rate (drawn but rarely played)."""
	var result: Array[Dictionary] = []

	for card_name: String in card_stats:
		var stats: CardStats = card_stats[card_name]
		if stats.times_drawn >= 5 and stats.usage_rate < threshold:
			result.append({
				"card_name": card_name,
				"champion": stats.champion,
				"times_drawn": stats.times_drawn,
				"times_played": stats.times_played,
				"usage_rate": stats.usage_rate,
				"times_held": stats.times_held_end_turn,
				"times_discarded": stats.times_discarded
			})

	# Sort by usage rate ascending (lowest first)
	result.sort_custom(func(a, b): return a["usage_rate"] < b["usage_rate"])

	return result


func _get_high_discard_cards(threshold: float) -> Array[Dictionary]:
	"""Get cards frequently discarded without being played."""
	var result: Array[Dictionary] = []

	for card_name: String in card_stats:
		var stats: CardStats = card_stats[card_name]
		if stats.times_drawn >= 5 and stats.discard_rate > threshold:
			result.append({
				"card_name": card_name,
				"champion": stats.champion,
				"times_drawn": stats.times_drawn,
				"times_discarded": stats.times_discarded,
				"times_discarded_hand_limit": stats.times_discarded_hand_limit,
				"discard_rate": stats.discard_rate
			})

	# Sort by discard rate descending (highest first)
	result.sort_custom(func(a, b): return a["discard_rate"] > b["discard_rate"])

	return result


func _get_never_played_cards() -> Array[Dictionary]:
	"""Get cards that were drawn but never played."""
	var result: Array[Dictionary] = []

	for card_name: String in card_stats:
		var stats: CardStats = card_stats[card_name]
		if stats.times_drawn > 0 and stats.times_played == 0:
			result.append({
				"card_name": card_name,
				"champion": stats.champion,
				"times_drawn": stats.times_drawn,
				"times_held": stats.times_held_end_turn,
				"times_discarded": stats.times_discarded
			})

	# Sort by times drawn descending
	result.sort_custom(func(a, b): return a["times_drawn"] > b["times_drawn"])

	return result


## Champion pair statistics
class PairStats extends RefCounted:
	var champion_a: String = ""
	var champion_b: String = ""
	var times_paired: int = 0
	var wins: int = 0
	var losses: int = 0

	func _init(a: String = "", b: String = "") -> void:
		champion_a = a
		champion_b = b

	var win_rate: float:
		get:
			if times_paired == 0:
				return 0.5
			return float(wins) / float(times_paired)

	func to_dict() -> Dictionary:
		return {
			"champion_a": champion_a,
			"champion_b": champion_b,
			"times_paired": times_paired,
			"wins": wins,
			"losses": losses,
			"win_rate": win_rate
		}


## Matchup statistics
class MatchupStats extends RefCounted:
	var team1: Array[String] = []
	var team2: Array[String] = []
	var times_played: int = 0
	var team1_wins: int = 0
	var team2_wins: int = 0
	var draws: int = 0

	func _init(t1: Array[String] = [], t2: Array[String] = []) -> void:
		team1 = t1.duplicate() if t1 else []
		team2 = t2.duplicate() if t2 else []

	var team1_win_rate: float:
		get:
			if times_played == 0:
				return 0.5
			return float(team1_wins) / float(times_played)

	func to_dict() -> Dictionary:
		return {
			"team1": team1,
			"team2": team2,
			"times_played": times_played,
			"team1_wins": team1_wins,
			"team2_wins": team2_wins,
			"draws": draws,
			"team1_win_rate": team1_win_rate
		}
