class_name MatchResult
extends RefCounted
## Complete record of a single match


## Unique match identifier within session
var match_id: int = 0

## RNG seed used for this match (for reproducibility)
var seed_used: int = 0

## Timestamp when match started
var timestamp: String = ""

## Player 1 champion names
var p1_champions: Array[String] = []

## Player 2 champion names
var p2_champions: Array[String] = []

## Player 1 AI difficulty
var p1_difficulty: int = 1

## Player 2 AI difficulty
var p2_difficulty: int = 1

## Winner (0 = draw, 1 = player 1, 2 = player 2)
var winner: int = 0

## Reason for win
var win_reason: String = ""  # "champions_defeated", "round_limit", "forfeit", "error"

## Total rounds played
var total_rounds: int = 0

## Total turns (both players combined)
var total_turns: int = 0

## Match duration in milliseconds
var duration_ms: int = 0

## All card plays during the match
var card_plays: Array[CardPlayRecord] = []

## Turn-by-turn log
var turn_logs: Array[TurnLog] = []

## Round-by-round summaries with detailed champion stats
var round_summaries: Array[RoundSummary] = []

## Final HP for each champion
var final_champion_hp: Dictionary = {}  # unique_id -> hp

## Errors encountered during match
var errors: Array[String] = []

## Warnings generated during match
var warnings: Array[String] = []

## Card usage tracking
var cards_drawn: Dictionary = {}  # card_name -> count
var cards_discarded: Dictionary = {}  # card_name -> count
var cards_discarded_hand_limit: Dictionary = {}  # card_name -> count
var cards_held_end_turn: Dictionary = {}  # card_name -> count

## Replay data - stores all actions for playback
var replay_actions: Array[ReplayAction] = []


func _init() -> void:
	p1_champions = []
	p2_champions = []
	card_plays = []
	turn_logs = []
	round_summaries = []
	final_champion_hp = {}
	errors = []
	warnings = []
	cards_drawn = {}
	cards_discarded = {}
	cards_discarded_hand_limit = {}
	cards_held_end_turn = {}
	replay_actions = []


func record_replay_action(action: Dictionary, result: Dictionary, round_num: int, turn_num: int, player_id: int) -> void:
	"""Record an action for replay purposes."""
	var replay := ReplayAction.new()
	replay.action_type = action.get("type", "")
	replay.action_data = action.duplicate()
	replay.result_data = result.duplicate()
	replay.round_number = round_num
	replay.turn_number = turn_num
	replay.player_id = player_id
	replay_actions.append(replay)


func record_card_drawn(card_name: String) -> void:
	"""Record that a card was drawn."""
	if not cards_drawn.has(card_name):
		cards_drawn[card_name] = 0
	cards_drawn[card_name] += 1


func record_card_discarded(card_name: String, from_hand_limit: bool = false) -> void:
	"""Record that a card was discarded."""
	if not cards_discarded.has(card_name):
		cards_discarded[card_name] = 0
	cards_discarded[card_name] += 1
	if from_hand_limit:
		if not cards_discarded_hand_limit.has(card_name):
			cards_discarded_hand_limit[card_name] = 0
		cards_discarded_hand_limit[card_name] += 1


func record_card_held(card_name: String) -> void:
	"""Record that a card was held at end of turn without being played."""
	if not cards_held_end_turn.has(card_name):
		cards_held_end_turn[card_name] = 0
	cards_held_end_turn[card_name] += 1


## Get all no-op card plays
func get_noop_plays() -> Array[CardPlayRecord]:
	var noops: Array[CardPlayRecord] = []
	for play: CardPlayRecord in card_plays:
		if play.is_noop:
			noops.append(play)
	return noops


## Get card plays by champion
func get_plays_by_champion(champion_id: String) -> Array[CardPlayRecord]:
	var plays: Array[CardPlayRecord] = []
	for play: CardPlayRecord in card_plays:
		if play.caster_id == champion_id:
			plays.append(play)
	return plays


## Get card plays by card name
func get_plays_by_card(card_name: String) -> Array[CardPlayRecord]:
	var plays: Array[CardPlayRecord] = []
	for play: CardPlayRecord in card_plays:
		if play.card_name == card_name:
			plays.append(play)
	return plays


func to_dict() -> Dictionary:
	"""Convert to dictionary for serialization."""
	var plays_data: Array = []
	for play: CardPlayRecord in card_plays:
		plays_data.append(play.to_dict())

	var turns_data: Array = []
	for turn_log: TurnLog in turn_logs:
		turns_data.append(turn_log.to_dict())

	var rounds_data: Array = []
	for round_summary: RoundSummary in round_summaries:
		rounds_data.append(round_summary.to_dict())

	var replay_data: Array = []
	for replay_action: ReplayAction in replay_actions:
		replay_data.append(replay_action.to_dict())

	return {
		"match_id": match_id,
		"seed_used": seed_used,
		"timestamp": timestamp,
		"p1_champions": p1_champions,
		"p2_champions": p2_champions,
		"p1_difficulty": p1_difficulty,
		"p2_difficulty": p2_difficulty,
		"winner": winner,
		"win_reason": win_reason,
		"total_rounds": total_rounds,
		"total_turns": total_turns,
		"duration_ms": duration_ms,
		"card_plays": plays_data,
		"turn_logs": turns_data,
		"round_summaries": rounds_data,
		"replay_actions": replay_data,
		"final_champion_hp": final_champion_hp,
		"errors": errors,
		"warnings": warnings,
		"noop_count": get_noop_plays().size()
	}


## Record of a single card being played
class CardPlayRecord extends RefCounted:
	var card_name: String = ""
	var card_type: String = ""  # Action, Response, Equipment
	var caster_id: String = ""  # Champion unique ID
	var caster_name: String = ""  # Champion name
	var player_id: int = 0
	var targets: Array = []  # Target champion IDs
	var mana_cost: int = 0
	var mana_available: int = 0  # Mana before playing
	var turn_number: int = 0
	var round_number: int = 0

	## Effect tracking
	var damage_dealt: int = 0
	var healing_done: int = 0
	var buffs_applied: int = 0
	var debuffs_applied: int = 0
	var movements_caused: int = 0
	var cards_drawn: int = 0

	## No-op detection
	var is_noop: bool = false
	var noop_reason: String = ""

	## State tracking (optional, for debugging)
	var state_before_hash: String = ""
	var state_after_hash: String = ""

	func to_dict() -> Dictionary:
		return {
			"card_name": card_name,
			"card_type": card_type,
			"caster_id": caster_id,
			"caster_name": caster_name,
			"player_id": player_id,
			"targets": targets,
			"mana_cost": mana_cost,
			"mana_available": mana_available,
			"turn_number": turn_number,
			"round_number": round_number,
			"damage_dealt": damage_dealt,
			"healing_done": healing_done,
			"buffs_applied": buffs_applied,
			"debuffs_applied": debuffs_applied,
			"movements_caused": movements_caused,
			"cards_drawn": cards_drawn,
			"is_noop": is_noop,
			"noop_reason": noop_reason
		}


## Log of a single turn
class TurnLog extends RefCounted:
	var turn_number: int = 0
	var round_number: int = 0
	var player_id: int = 0
	var starting_mana: int = 0
	var ending_mana: int = 0
	var actions_taken: int = 0
	var cards_played: Array[String] = []
	var attacks_made: int = 0
	var moves_made: int = 0
	var damage_dealt: int = 0
	var damage_taken: int = 0
	var healing_done: int = 0

	func _init() -> void:
		cards_played = []

	func to_dict() -> Dictionary:
		return {
			"turn_number": turn_number,
			"round_number": round_number,
			"player_id": player_id,
			"starting_mana": starting_mana,
			"ending_mana": ending_mana,
			"actions_taken": actions_taken,
			"cards_played": cards_played,
			"attacks_made": attacks_made,
			"moves_made": moves_made,
			"damage_dealt": damage_dealt,
			"damage_taken": damage_taken,
			"healing_done": healing_done
		}


## Summary of a complete round (both players' turns)
class RoundSummary extends RefCounted:
	var round_number: int = 0

	## Champion stats for this round (champion_id -> ChampionRoundStats)
	var champion_stats: Dictionary = {}

	## Cards played this round by card name
	var cards_played: Array[String] = []

	## Card play details
	var card_play_details: Array[Dictionary] = []

	## HP at start and end of round
	var hp_at_start: Dictionary = {}  # champion_id -> hp
	var hp_at_end: Dictionary = {}    # champion_id -> hp

	## Round outcomes
	var champions_killed: Array[String] = []
	var game_ended: bool = false
	var winner: int = 0  # 0 = ongoing, 1 = P1 won, 2 = P2 won

	func _init() -> void:
		champion_stats = {}
		cards_played = []
		card_play_details = []
		hp_at_start = {}
		hp_at_end = {}
		champions_killed = []

	func get_or_create_champion_stats(champion_id: String, champion_name: String, player_id: int) -> ChampionRoundStats:
		if not champion_stats.has(champion_id):
			champion_stats[champion_id] = ChampionRoundStats.new(champion_id, champion_name, player_id)
		return champion_stats[champion_id]

	func to_dict() -> Dictionary:
		var champ_stats_dict := {}
		for champ_id: String in champion_stats:
			champ_stats_dict[champ_id] = champion_stats[champ_id].to_dict()

		return {
			"round_number": round_number,
			"champion_stats": champ_stats_dict,
			"cards_played": cards_played,
			"card_play_details": card_play_details,
			"hp_at_start": hp_at_start,
			"hp_at_end": hp_at_end,
			"champions_killed": champions_killed,
			"game_ended": game_ended,
			"winner": winner
		}


## Per-champion stats within a single round
class ChampionRoundStats extends RefCounted:
	var champion_id: String = ""
	var champion_name: String = ""
	var player_id: int = 0

	## Damage
	var damage_dealt: int = 0        # Total damage this champion dealt
	var damage_taken: int = 0        # Total damage this champion received
	var damage_by_source: Dictionary = {}  # source_champion_id -> amount
	var damage_to_target: Dictionary = {}  # target_champion_id -> amount

	## Healing
	var healing_done: int = 0
	var healing_received: int = 0

	## Cards
	var cards_played: Array[String] = []
	var cards_played_details: Array[Dictionary] = []  # {card_name, damage, healing, targets, is_noop}

	## Actions
	var attacks_made: int = 0
	var moves_made: int = 0

	## Status
	var killed_this_round: bool = false
	var killed_by: String = ""  # Champion ID that killed this one

	func _init(id: String = "", name: String = "", pid: int = 0) -> void:
		champion_id = id
		champion_name = name
		player_id = pid
		damage_by_source = {}
		damage_to_target = {}
		cards_played = []
		cards_played_details = []

	func record_damage_dealt(amount: int, target_id: String) -> void:
		damage_dealt += amount
		if not damage_to_target.has(target_id):
			damage_to_target[target_id] = 0
		damage_to_target[target_id] += amount

	func record_damage_taken(amount: int, source_id: String) -> void:
		damage_taken += amount
		if not damage_by_source.has(source_id):
			damage_by_source[source_id] = 0
		damage_by_source[source_id] += amount

	func record_card_played(card_name: String, damage: int, healing: int, targets: Array, is_noop: bool) -> void:
		cards_played.append(card_name)
		cards_played_details.append({
			"card_name": card_name,
			"damage": damage,
			"healing": healing,
			"targets": targets,
			"is_noop": is_noop
		})

	func to_dict() -> Dictionary:
		return {
			"champion_id": champion_id,
			"champion_name": champion_name,
			"player_id": player_id,
			"damage_dealt": damage_dealt,
			"damage_taken": damage_taken,
			"damage_by_source": damage_by_source,
			"damage_to_target": damage_to_target,
			"healing_done": healing_done,
			"healing_received": healing_received,
			"cards_played": cards_played,
			"cards_played_details": cards_played_details,
			"attacks_made": attacks_made,
			"moves_made": moves_made,
			"killed_this_round": killed_this_round,
			"killed_by": killed_by
		}


## Single action recorded for replay
class ReplayAction extends RefCounted:
	var action_type: String = ""  # "move", "attack", "cast"
	var action_data: Dictionary = {}  # Full action dictionary
	var result_data: Dictionary = {}  # Result from execution
	var round_number: int = 0
	var turn_number: int = 0
	var player_id: int = 0

	func to_dict() -> Dictionary:
		return {
			"action_type": action_type,
			"action_data": action_data,
			"result_data": result_data,
			"round_number": round_number,
			"turn_number": turn_number,
			"player_id": player_id
		}

	static func from_dict(data: Dictionary) -> ReplayAction:
		var action := ReplayAction.new()
		action.action_type = data.get("action_type", "")
		action.action_data = data.get("action_data", {})
		action.result_data = data.get("result_data", {})
		action.round_number = data.get("round_number", 0)
		action.turn_number = data.get("turn_number", 0)
		action.player_id = data.get("player_id", 0)
		return action
