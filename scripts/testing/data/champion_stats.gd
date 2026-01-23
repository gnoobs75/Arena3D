class_name ChampionStats
extends RefCounted
## Statistics for a single champion across all test matches


## Champion name
var champion_name: String = ""

## Total times this champion was picked
var times_picked: int = 0

## Times picked by player 1
var times_picked_p1: int = 0

## Times picked by player 2
var times_picked_p2: int = 0

## Total wins when on the winning team
var wins: int = 0

## Total losses when on the losing team
var losses: int = 0

## Total damage dealt by this champion
var total_damage_dealt: int = 0

## Total damage taken by this champion
var total_damage_taken: int = 0

## Total healing done by this champion
var total_healing_done: int = 0

## Total healing received
var total_healing_received: int = 0

## Total kills (last hit on enemy champion)
var total_kills: int = 0

## Total deaths
var total_deaths: int = 0

## Sum of rounds survived (for average calculation)
var _survival_rounds_sum: int = 0

## Number of matches for survival calculation
var _survival_matches: int = 0

## Cards played by this champion
var cards_played: int = 0

## No-op cards played
var noop_cards_played: int = 0

## Attacks made
var attacks_made: int = 0

## Tiles moved
var tiles_moved: int = 0


func _init(name: String = "") -> void:
	champion_name = name


## Win rate (0.0 to 1.0)
var win_rate: float:
	get:
		var total := wins + losses
		if total == 0:
			return 0.5
		return float(wins) / float(total)


## Kill/Death ratio
var kd_ratio: float:
	get:
		if total_deaths == 0:
			return float(total_kills)
		return float(total_kills) / float(total_deaths)


## Average damage dealt per match
var avg_damage_per_match: float:
	get:
		if times_picked == 0:
			return 0.0
		return float(total_damage_dealt) / float(times_picked)


## Average damage taken per match
var avg_damage_taken_per_match: float:
	get:
		if times_picked == 0:
			return 0.0
		return float(total_damage_taken) / float(times_picked)


## Average healing done per match
var avg_healing_per_match: float:
	get:
		if times_picked == 0:
			return 0.0
		return float(total_healing_done) / float(times_picked)


## Average rounds survived
var avg_survival_rounds: float:
	get:
		if _survival_matches == 0:
			return 0.0
		return float(_survival_rounds_sum) / float(_survival_matches)


## Average kills per match
var avg_kills_per_match: float:
	get:
		if times_picked == 0:
			return 0.0
		return float(total_kills) / float(times_picked)


## Pick rate relative to total matches
func get_pick_rate(total_matches: int) -> float:
	if total_matches == 0:
		return 0.0
	# Each match has 4 champion slots (2 per team)
	return float(times_picked) / float(total_matches * 4)


func record_pick(player_id: int) -> void:
	"""Record that this champion was picked."""
	times_picked += 1
	if player_id == 1:
		times_picked_p1 += 1
	else:
		times_picked_p2 += 1


func record_match_outcome(won: bool) -> void:
	"""Record match win/loss."""
	if won:
		wins += 1
	else:
		losses += 1


func record_damage_dealt(amount: int) -> void:
	"""Record damage dealt."""
	total_damage_dealt += amount


func record_damage_taken(amount: int) -> void:
	"""Record damage taken."""
	total_damage_taken += amount


func record_healing_done(amount: int) -> void:
	"""Record healing done."""
	total_healing_done += amount


func record_healing_received(amount: int) -> void:
	"""Record healing received."""
	total_healing_received += amount


func record_kill() -> void:
	"""Record a kill."""
	total_kills += 1


func record_death(round_survived: int) -> void:
	"""Record a death and rounds survived."""
	total_deaths += 1
	_survival_rounds_sum += round_survived
	_survival_matches += 1


func record_survived_match(total_rounds: int) -> void:
	"""Record that champion survived the entire match."""
	_survival_rounds_sum += total_rounds
	_survival_matches += 1


func record_card_played(was_noop: bool) -> void:
	"""Record a card played."""
	cards_played += 1
	if was_noop:
		noop_cards_played += 1


func record_attack() -> void:
	"""Record an attack made."""
	attacks_made += 1


func record_movement(tiles: int) -> void:
	"""Record tiles moved."""
	tiles_moved += tiles


func to_dict() -> Dictionary:
	"""Convert to dictionary for serialization."""
	return {
		"champion_name": champion_name,
		"times_picked": times_picked,
		"times_picked_p1": times_picked_p1,
		"times_picked_p2": times_picked_p2,
		"wins": wins,
		"losses": losses,
		"win_rate": win_rate,
		"total_damage_dealt": total_damage_dealt,
		"total_damage_taken": total_damage_taken,
		"total_healing_done": total_healing_done,
		"total_healing_received": total_healing_received,
		"total_kills": total_kills,
		"total_deaths": total_deaths,
		"kd_ratio": kd_ratio,
		"avg_damage_per_match": avg_damage_per_match,
		"avg_damage_taken_per_match": avg_damage_taken_per_match,
		"avg_healing_per_match": avg_healing_per_match,
		"avg_survival_rounds": avg_survival_rounds,
		"avg_kills_per_match": avg_kills_per_match,
		"cards_played": cards_played,
		"noop_cards_played": noop_cards_played,
		"attacks_made": attacks_made,
		"tiles_moved": tiles_moved
	}


static func from_dict(data: Dictionary) -> ChampionStats:
	"""Create from dictionary."""
	var stats := ChampionStats.new(data.get("champion_name", ""))
	stats.times_picked = data.get("times_picked", 0)
	stats.times_picked_p1 = data.get("times_picked_p1", 0)
	stats.times_picked_p2 = data.get("times_picked_p2", 0)
	stats.wins = data.get("wins", 0)
	stats.losses = data.get("losses", 0)
	stats.total_damage_dealt = data.get("total_damage_dealt", 0)
	stats.total_damage_taken = data.get("total_damage_taken", 0)
	stats.total_healing_done = data.get("total_healing_done", 0)
	stats.total_healing_received = data.get("total_healing_received", 0)
	stats.total_kills = data.get("total_kills", 0)
	stats.total_deaths = data.get("total_deaths", 0)
	stats.cards_played = data.get("cards_played", 0)
	stats.noop_cards_played = data.get("noop_cards_played", 0)
	stats.attacks_made = data.get("attacks_made", 0)
	stats.tiles_moved = data.get("tiles_moved", 0)
	return stats
