class_name StateSnapshot
extends RefCounted
## Captures complete game state for before/after comparison


## Unix timestamp when snapshot was taken
var timestamp: int = 0

## Game round number
var round_number: int = 0

## Active player (1 or 2)
var active_player: int = 0

## Current phase
var turn_phase: String = ""

## Player states
var player1_state: PlayerSnapshot
var player2_state: PlayerSnapshot

## Champion states (unique_id -> ChampionSnapshot)
var champion_snapshots: Dictionary = {}

## Quick hash for comparison
var state_hash: String = ""


func _init() -> void:
	champion_snapshots = {}


## Capture current game state
static func capture(game_state: GameState) -> StateSnapshot:
	"""Create a snapshot of the current game state."""
	var snapshot := StateSnapshot.new()
	snapshot.timestamp = Time.get_unix_time_from_system()
	snapshot.round_number = game_state.round_number
	snapshot.active_player = game_state.active_player
	snapshot.turn_phase = game_state.current_phase

	# Capture player states
	snapshot.player1_state = PlayerSnapshot.capture(game_state, 1)
	snapshot.player2_state = PlayerSnapshot.capture(game_state, 2)

	# Capture all champion states
	for champion: ChampionState in game_state.get_all_champions():
		snapshot.champion_snapshots[champion.unique_id] = ChampionSnapshot.capture(champion)

	# Generate hash for quick comparison
	snapshot.state_hash = snapshot._generate_hash()

	return snapshot


func _generate_hash() -> String:
	"""Generate a hash string representing state."""
	var parts: Array[String] = []

	# Basic game state
	parts.append("r%d" % round_number)
	parts.append("p%d" % active_player)

	# Player mana
	parts.append("m1_%d" % player1_state.mana)
	parts.append("m2_%d" % player2_state.mana)

	# Champion HP and positions
	var champ_ids: Array = champion_snapshots.keys()
	champ_ids.sort()
	for champ_id: String in champ_ids:
		var cs: ChampionSnapshot = champion_snapshots[champ_id]
		parts.append("%s_%d_%d_%d" % [champ_id.substr(0, 3), cs.current_hp, cs.position.x, cs.position.y])

	return "_".join(parts).md5_text().substr(0, 16)


## Get champion snapshot by ID
func get_champion(unique_id: String) -> ChampionSnapshot:
	return champion_snapshots.get(unique_id, null)


## Get player snapshot
func get_player(player_id: int) -> PlayerSnapshot:
	return player1_state if player_id == 1 else player2_state


## Compare two snapshots and return differences
static func diff(before: StateSnapshot, after: StateSnapshot) -> StateDiff:
	"""Compare two snapshots and return what changed."""
	var result := StateDiff.new()

	# Check round/phase changes
	result.round_changed = before.round_number != after.round_number
	result.player_changed = before.active_player != after.active_player

	# Check mana changes
	result.p1_mana_delta = after.player1_state.mana - before.player1_state.mana
	result.p2_mana_delta = after.player2_state.mana - before.player2_state.mana

	# Check hand size changes
	result.p1_hand_delta = after.player1_state.hand_size - before.player1_state.hand_size
	result.p2_hand_delta = after.player2_state.hand_size - before.player2_state.hand_size

	# Check champion changes
	for champ_id: String in after.champion_snapshots:
		var before_champ: ChampionSnapshot = before.champion_snapshots.get(champ_id)
		var after_champ: ChampionSnapshot = after.champion_snapshots[champ_id]

		if before_champ == null:
			continue

		var champ_diff := ChampionDiff.new()
		champ_diff.champion_id = champ_id

		# HP change
		champ_diff.hp_delta = after_champ.current_hp - before_champ.current_hp
		if champ_diff.hp_delta != 0:
			result.hp_changes[champ_id] = champ_diff.hp_delta

		# Position change
		if after_champ.position != before_champ.position:
			champ_diff.position_changed = true
			champ_diff.old_position = before_champ.position
			champ_diff.new_position = after_champ.position
			result.position_changes[champ_id] = {
				"from": before_champ.position,
				"to": after_champ.position
			}

		# Stat changes
		champ_diff.power_delta = after_champ.current_power - before_champ.current_power
		champ_diff.range_delta = after_champ.current_range - before_champ.current_range
		champ_diff.movement_delta = after_champ.current_movement - before_champ.current_movement

		# Buff changes
		for buff_name: String in after_champ.buffs:
			if not before_champ.buffs.has(buff_name):
				result.buffs_added.append({"champion": champ_id, "buff": buff_name})
		for buff_name: String in before_champ.buffs:
			if not after_champ.buffs.has(buff_name):
				result.buffs_removed.append({"champion": champ_id, "buff": buff_name})

		# Debuff changes
		for debuff_name: String in after_champ.debuffs:
			if not before_champ.debuffs.has(debuff_name):
				result.debuffs_added.append({"champion": champ_id, "debuff": debuff_name})
		for debuff_name: String in before_champ.debuffs:
			if not after_champ.debuffs.has(debuff_name):
				result.debuffs_removed.append({"champion": champ_id, "debuff": debuff_name})

		if champ_diff.has_changes():
			result.champion_diffs[champ_id] = champ_diff

	# Determine if anything meaningful changed
	result.has_any_changes = (
		result.round_changed or
		result.p1_mana_delta != 0 or
		result.p2_mana_delta != 0 or
		result.p1_hand_delta != 0 or
		result.p2_hand_delta != 0 or
		not result.hp_changes.is_empty() or
		not result.position_changes.is_empty() or
		not result.buffs_added.is_empty() or
		not result.buffs_removed.is_empty() or
		not result.debuffs_added.is_empty() or
		not result.debuffs_removed.is_empty()
	)

	return result


func to_dict() -> Dictionary:
	"""Convert to dictionary for serialization."""
	var champ_data: Dictionary = {}
	for champ_id: String in champion_snapshots:
		champ_data[champ_id] = champion_snapshots[champ_id].to_dict()

	return {
		"timestamp": timestamp,
		"round_number": round_number,
		"active_player": active_player,
		"turn_phase": turn_phase,
		"player1": player1_state.to_dict() if player1_state else {},
		"player2": player2_state.to_dict() if player2_state else {},
		"champions": champ_data,
		"state_hash": state_hash
	}


## Snapshot of a player's state
class PlayerSnapshot extends RefCounted:
	var player_id: int = 0
	var mana: int = 0
	var hand_size: int = 0
	var hand_cards: Array[String] = []
	var deck_size: int = 0
	var discard_size: int = 0
	var response_slot: String = ""

	func _init() -> void:
		hand_cards = []

	static func capture(game_state: GameState, player: int) -> PlayerSnapshot:
		var snap := PlayerSnapshot.new()
		snap.player_id = player
		snap.mana = game_state.get_mana(player)
		var hand: Array = game_state.get_hand(player)
		snap.hand_size = hand.size()
		snap.hand_cards = []
		for card in hand:
			snap.hand_cards.append(str(card))
		snap.deck_size = game_state.get_deck(player).size()
		snap.discard_size = game_state.get_discard(player).size()
		snap.response_slot = game_state.get_response_slot(player)
		return snap

	func to_dict() -> Dictionary:
		return {
			"player_id": player_id,
			"mana": mana,
			"hand_size": hand_size,
			"hand_cards": hand_cards,
			"deck_size": deck_size,
			"discard_size": discard_size,
			"response_slot": response_slot
		}


## Snapshot of a champion's state
class ChampionSnapshot extends RefCounted:
	var unique_id: String = ""
	var champion_name: String = ""
	var owner_id: int = 0
	var position: Vector2i = Vector2i.ZERO
	var current_hp: int = 0
	var max_hp: int = 0
	var current_power: int = 0
	var current_range: int = 0
	var current_movement: int = 0
	var has_moved: bool = false
	var has_attacked: bool = false
	var movement_remaining: int = 0
	var buffs: Dictionary = {}
	var debuffs: Dictionary = {}
	var is_alive: bool = true

	func _init() -> void:
		buffs = {}
		debuffs = {}

	static func capture(champion: ChampionState) -> ChampionSnapshot:
		var snap := ChampionSnapshot.new()
		snap.unique_id = champion.unique_id
		snap.champion_name = champion.champion_name
		snap.owner_id = champion.owner_id
		snap.position = champion.position
		snap.current_hp = champion.current_hp
		snap.max_hp = champion.max_hp
		snap.current_power = champion.current_power
		snap.current_range = champion.current_range
		snap.current_movement = champion.current_movement
		snap.has_moved = champion.has_moved
		snap.has_attacked = champion.has_attacked
		snap.movement_remaining = champion.movement_remaining
		snap.is_alive = champion.is_alive()

		# Deep copy buffs
		snap.buffs = {}
		for buff_name: String in champion.buffs:
			snap.buffs[buff_name] = champion.buffs[buff_name].duplicate()

		# Deep copy debuffs
		snap.debuffs = {}
		for debuff_name: String in champion.debuffs:
			snap.debuffs[debuff_name] = champion.debuffs[debuff_name].duplicate()

		return snap

	func to_dict() -> Dictionary:
		return {
			"unique_id": unique_id,
			"champion_name": champion_name,
			"owner_id": owner_id,
			"position": {"x": position.x, "y": position.y},
			"current_hp": current_hp,
			"max_hp": max_hp,
			"current_power": current_power,
			"current_range": current_range,
			"current_movement": current_movement,
			"has_moved": has_moved,
			"has_attacked": has_attacked,
			"movement_remaining": movement_remaining,
			"buffs": buffs,
			"debuffs": debuffs,
			"is_alive": is_alive
		}


## Difference between two state snapshots
class StateDiff extends RefCounted:
	var has_any_changes: bool = false
	var round_changed: bool = false
	var player_changed: bool = false

	var p1_mana_delta: int = 0
	var p2_mana_delta: int = 0
	var p1_hand_delta: int = 0
	var p2_hand_delta: int = 0

	var hp_changes: Dictionary = {}  # champion_id -> hp_delta
	var position_changes: Dictionary = {}  # champion_id -> {from, to}
	var buffs_added: Array = []  # [{champion, buff}]
	var buffs_removed: Array = []
	var debuffs_added: Array = []
	var debuffs_removed: Array = []

	var champion_diffs: Dictionary = {}  # champion_id -> ChampionDiff

	func _init() -> void:
		hp_changes = {}
		position_changes = {}
		buffs_added = []
		buffs_removed = []
		debuffs_added = []
		debuffs_removed = []
		champion_diffs = {}

	func total_damage_dealt() -> int:
		var total := 0
		for champ_id: String in hp_changes:
			var delta: int = hp_changes[champ_id]
			if delta < 0:
				total += abs(delta)
		return total

	func total_healing_done() -> int:
		var total := 0
		for champ_id: String in hp_changes:
			var delta: int = hp_changes[champ_id]
			if delta > 0:
				total += delta
		return total

	func to_dict() -> Dictionary:
		return {
			"has_any_changes": has_any_changes,
			"round_changed": round_changed,
			"player_changed": player_changed,
			"p1_mana_delta": p1_mana_delta,
			"p2_mana_delta": p2_mana_delta,
			"p1_hand_delta": p1_hand_delta,
			"p2_hand_delta": p2_hand_delta,
			"hp_changes": hp_changes,
			"position_changes": position_changes,
			"buffs_added": buffs_added,
			"buffs_removed": buffs_removed,
			"debuffs_added": debuffs_added,
			"debuffs_removed": debuffs_removed,
			"total_damage": total_damage_dealt(),
			"total_healing": total_healing_done()
		}


## Detailed diff for a single champion
class ChampionDiff extends RefCounted:
	var champion_id: String = ""
	var hp_delta: int = 0
	var position_changed: bool = false
	var old_position: Vector2i = Vector2i.ZERO
	var new_position: Vector2i = Vector2i.ZERO
	var power_delta: int = 0
	var range_delta: int = 0
	var movement_delta: int = 0

	func has_changes() -> bool:
		return (
			hp_delta != 0 or
			position_changed or
			power_delta != 0 or
			range_delta != 0 or
			movement_delta != 0
		)
