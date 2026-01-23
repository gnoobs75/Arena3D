class_name CardStats
extends RefCounted
## Statistics for a single card across all test matches


## Card name
var card_name: String = ""

## Champion this card belongs to
var champion: String = ""

## Card type (Action, Response, Equipment)
var card_type: String = ""

## Total times this card was played
var times_played: int = 0

## Times played by player 1
var times_played_p1: int = 0

## Times played by player 2
var times_played_p2: int = 0

## Times the card was a no-op (cast but had no effect)
var noop_count: int = 0

## Reasons for no-ops (reason_code -> count)
var noop_reasons: Dictionary = {}

## Total damage dealt by this card
var total_damage_dealt: int = 0

## Total healing done by this card
var total_healing_done: int = 0

## Number of buffs applied
var buffs_applied: int = 0

## Number of debuffs applied
var debuffs_applied: int = 0

## Number of forced movements caused
var movements_caused: int = 0

## Cards drawn from this card's effect
var cards_drawn: int = 0

## Times target died the same turn this card was played
var kills_contributed: int = 0

## Wins in matches where this card was played
var wins_when_played: int = 0

## Losses in matches where this card was played
var losses_when_played: int = 0

## Average mana available when this card was played
var _mana_sum: float = 0.0

## Mana costs paid (for average calculation)
var total_mana_spent: int = 0

## Card usage tracking
## Times this card was drawn into hand
var times_drawn: int = 0

## Times this card was in hand at end of turn but not played
var times_held_end_turn: int = 0

## Times this card was discarded (from hand limit or effects)
var times_discarded: int = 0

## Times this card was discarded specifically from hand limit
var times_discarded_hand_limit: int = 0


func _init(name: String = "", champ: String = "", type: String = "") -> void:
	card_name = name
	champion = champ
	card_type = type
	noop_reasons = {}


## No-op rate as percentage (0.0 to 1.0)
var noop_rate: float:
	get:
		if times_played == 0:
			return 0.0
		return float(noop_count) / float(times_played)


## Win rate when this card is played (0.0 to 1.0)
var win_rate_when_played: float:
	get:
		var total := wins_when_played + losses_when_played
		if total == 0:
			return 0.5
		return float(wins_when_played) / float(total)


## Average mana available when played
var avg_mana_when_played: float:
	get:
		if times_played == 0:
			return 0.0
		return _mana_sum / float(times_played)


## Average damage per play
var avg_damage_per_play: float:
	get:
		if times_played == 0:
			return 0.0
		return float(total_damage_dealt) / float(times_played)


## Average healing per play
var avg_healing_per_play: float:
	get:
		if times_played == 0:
			return 0.0
		return float(total_healing_done) / float(times_played)


func record_play(player_id: int, mana_available: int) -> void:
	"""Record that this card was played."""
	times_played += 1
	if player_id == 1:
		times_played_p1 += 1
	else:
		times_played_p2 += 1
	_mana_sum += mana_available


func record_noop(reason: String) -> void:
	"""Record that the card was a no-op."""
	noop_count += 1
	if not noop_reasons.has(reason):
		noop_reasons[reason] = 0
	noop_reasons[reason] += 1


func record_effect(damage: int, healing: int, buffs: int, debuffs: int, moves: int, draws: int) -> void:
	"""Record the effects of playing this card."""
	total_damage_dealt += damage
	total_healing_done += healing
	buffs_applied += buffs
	debuffs_applied += debuffs
	movements_caused += moves
	cards_drawn += draws


func record_kill() -> void:
	"""Record that this card contributed to a kill."""
	kills_contributed += 1


func record_match_outcome(won: bool) -> void:
	"""Record win/loss for a match where this card was played."""
	if won:
		wins_when_played += 1
	else:
		losses_when_played += 1


func record_drawn() -> void:
	"""Record that this card was drawn into hand."""
	times_drawn += 1


func record_held_end_turn() -> void:
	"""Record that this card was held at end of turn without being played."""
	times_held_end_turn += 1


func record_discarded(from_hand_limit: bool = false) -> void:
	"""Record that this card was discarded."""
	times_discarded += 1
	if from_hand_limit:
		times_discarded_hand_limit += 1


## Usage rate: times played vs times drawn
var usage_rate: float:
	get:
		if times_drawn == 0:
			return 0.0
		return float(times_played) / float(times_drawn)


## Hold rate: times held at end turn vs times drawn
var hold_rate: float:
	get:
		if times_drawn == 0:
			return 0.0
		return float(times_held_end_turn) / float(times_drawn)


## Discard rate: times discarded vs times drawn
var discard_rate: float:
	get:
		if times_drawn == 0:
			return 0.0
		return float(times_discarded) / float(times_drawn)


func get_most_common_noop_reason() -> String:
	"""Get the most common reason for no-ops."""
	if noop_reasons.is_empty():
		return ""
	var max_count := 0
	var max_reason := ""
	for reason: String in noop_reasons:
		if noop_reasons[reason] > max_count:
			max_count = noop_reasons[reason]
			max_reason = reason
	return max_reason


func to_dict() -> Dictionary:
	"""Convert to dictionary for serialization."""
	return {
		"card_name": card_name,
		"champion": champion,
		"card_type": card_type,
		"times_played": times_played,
		"times_played_p1": times_played_p1,
		"times_played_p2": times_played_p2,
		"noop_count": noop_count,
		"noop_rate": noop_rate,
		"noop_reasons": noop_reasons,
		"total_damage_dealt": total_damage_dealt,
		"total_healing_done": total_healing_done,
		"buffs_applied": buffs_applied,
		"debuffs_applied": debuffs_applied,
		"movements_caused": movements_caused,
		"cards_drawn": cards_drawn,
		"kills_contributed": kills_contributed,
		"wins_when_played": wins_when_played,
		"losses_when_played": losses_when_played,
		"win_rate_when_played": win_rate_when_played,
		"avg_damage_per_play": avg_damage_per_play,
		"avg_healing_per_play": avg_healing_per_play,
		"avg_mana_when_played": avg_mana_when_played,
		"total_mana_spent": total_mana_spent,
		# Card usage tracking
		"times_drawn": times_drawn,
		"times_held_end_turn": times_held_end_turn,
		"times_discarded": times_discarded,
		"times_discarded_hand_limit": times_discarded_hand_limit,
		"usage_rate": usage_rate,
		"hold_rate": hold_rate,
		"discard_rate": discard_rate
	}


static func from_dict(data: Dictionary) -> CardStats:
	"""Create from dictionary."""
	var stats := CardStats.new(
		data.get("card_name", ""),
		data.get("champion", ""),
		data.get("card_type", "")
	)
	stats.times_played = data.get("times_played", 0)
	stats.times_played_p1 = data.get("times_played_p1", 0)
	stats.times_played_p2 = data.get("times_played_p2", 0)
	stats.noop_count = data.get("noop_count", 0)
	stats.noop_reasons = data.get("noop_reasons", {})
	stats.total_damage_dealt = data.get("total_damage_dealt", 0)
	stats.total_healing_done = data.get("total_healing_done", 0)
	stats.buffs_applied = data.get("buffs_applied", 0)
	stats.debuffs_applied = data.get("debuffs_applied", 0)
	stats.movements_caused = data.get("movements_caused", 0)
	stats.cards_drawn = data.get("cards_drawn", 0)
	stats.kills_contributed = data.get("kills_contributed", 0)
	stats.wins_when_played = data.get("wins_when_played", 0)
	stats.losses_when_played = data.get("losses_when_played", 0)
	stats.total_mana_spent = data.get("total_mana_spent", 0)
	# Card usage tracking
	stats.times_drawn = data.get("times_drawn", 0)
	stats.times_held_end_turn = data.get("times_held_end_turn", 0)
	stats.times_discarded = data.get("times_discarded", 0)
	stats.times_discarded_hand_limit = data.get("times_discarded_hand_limit", 0)
	return stats
