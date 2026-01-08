class_name RangeCalculator
extends RefCounted
## RangeCalculator - Handles attack and ability range calculations
## Melee (range 1): Can attack in 8 directions (adjacent tiles)
## Ranged (range 2+): Can only attack in 4 cardinal directions

# Range thresholds
const MELEE_MAX_RANGE := 1  # Only range 1 is melee (8 directions), range 2+ is ranged (cardinal)

# Direction constants
const CARDINAL_DIRS: Array[Vector2i] = [
	Vector2i(0, -1),  # Up
	Vector2i(0, 1),   # Down
	Vector2i(-1, 0),  # Left
	Vector2i(1, 0)    # Right
]

const ALL_DIRS: Array[Vector2i] = [
	Vector2i(0, -1),   # Up
	Vector2i(0, 1),    # Down
	Vector2i(-1, 0),   # Left
	Vector2i(1, 0),    # Right
	Vector2i(-1, -1),  # Up-Left
	Vector2i(1, -1),   # Up-Right
	Vector2i(-1, 1),   # Down-Left
	Vector2i(1, 1)     # Down-Right
]


func can_attack(attacker: ChampionState, target: ChampionState, state: GameState) -> bool:
	"""Check if attacker can attack target."""
	if not attacker.is_alive() or not target.is_alive():
		return false

	# Can't attack self
	if attacker.unique_id == target.unique_id:
		return false

	# Can't attack allies
	if attacker.owner_id == target.owner_id:
		return false

	var distance := _calculate_attack_distance(attacker, target, state)
	return distance >= 0 and distance <= attacker.current_range


func get_valid_targets(attacker: ChampionState, state: GameState) -> Array[ChampionState]:
	"""Get all valid attack targets for a champion."""
	var targets: Array[ChampionState] = []
	var opponent_id := 2 if attacker.owner_id == 1 else 1

	for enemy: ChampionState in state.get_champions(opponent_id):
		if can_attack(attacker, enemy, state):
			targets.append(enemy)

	return targets


func get_tiles_in_range(pos: Vector2i, range_value: int, is_melee: bool) -> Array[Vector2i]:
	"""Get all tiles within attack range of a position."""
	var tiles: Array[Vector2i] = []

	if is_melee:
		# Melee: 8 directions
		tiles = _get_tiles_in_chebyshev_range(pos, range_value)
	else:
		# Ranged: 4 cardinal directions only
		tiles = _get_tiles_in_cardinal_range(pos, range_value)

	return tiles


func _get_tiles_in_chebyshev_range(pos: Vector2i, range_value: int) -> Array[Vector2i]:
	"""Get tiles using Chebyshev distance (8-directional)."""
	var tiles: Array[Vector2i] = []

	for dy in range(-range_value, range_value + 1):
		for dx in range(-range_value, range_value + 1):
			if dx == 0 and dy == 0:
				continue

			var dist := maxi(absi(dx), absi(dy))
			if dist <= range_value:
				tiles.append(pos + Vector2i(dx, dy))

	return tiles


func _get_tiles_in_cardinal_range(pos: Vector2i, range_value: int) -> Array[Vector2i]:
	"""Get tiles in cardinal directions only (for ranged attacks)."""
	var tiles: Array[Vector2i] = []

	for dir: Vector2i in CARDINAL_DIRS:
		for dist in range(1, range_value + 1):
			tiles.append(pos + dir * dist)

	return tiles


func _calculate_attack_distance(attacker: ChampionState, target: ChampionState, _state: GameState) -> int:
	"""
	Calculate attack distance considering melee vs ranged rules.
	Melee (range 1): Uses Chebyshev distance (8 directions)
	Ranged (range 2+): Uses cardinal-only distance
	"""
	var from: Vector2i = attacker.position
	var to: Vector2i = target.position
	var is_melee: bool = attacker.current_range <= MELEE_MAX_RANGE

	if is_melee:
		# Chebyshev distance - max of x and y diff
		return maxi(absi(to.x - from.x), absi(to.y - from.y))
	else:
		# Ranged: Must be in a cardinal direction
		if not _is_cardinal_direction(from, to):
			return -1  # Invalid direction for ranged

		# Manhattan distance for cardinal
		return absi(to.x - from.x) + absi(to.y - from.y)


func _is_cardinal_direction(from: Vector2i, to: Vector2i) -> bool:
	"""Check if 'to' is in a cardinal direction from 'from'."""
	var dx := to.x - from.x
	var dy := to.y - from.y

	# Must be on same row OR same column (not both for non-self)
	return (dx == 0 and dy != 0) or (dy == 0 and dx != 0)


func is_melee_range(range_value: int) -> bool:
	"""Check if a range value is considered melee."""
	return range_value <= MELEE_MAX_RANGE


func get_attack_directions(is_melee: bool) -> Array[Vector2i]:
	"""Get valid attack directions based on range type."""
	return ALL_DIRS if is_melee else CARDINAL_DIRS


# --- Line of Sight (for future use with blocking terrain) ---

func has_line_of_sight(from: Vector2i, to: Vector2i, state: GameState) -> bool:
	"""Check if there's clear line of sight (no walls blocking)."""
	# For now, walls only block at edges, so LoS is always clear on the board
	# This could be expanded for more complex terrain

	var dx := to.x - from.x
	var dy := to.y - from.y

	# Cardinal direction check
	if dx == 0 or dy == 0:
		var step_x := 0 if dx == 0 else (1 if dx > 0 else -1)
		var step_y := 0 if dy == 0 else (1 if dy > 0 else -1)
		var current := from + Vector2i(step_x, step_y)

		while current != to:
			var terrain := state.get_terrain(current)
			if terrain == GameState.Terrain.WALL:
				return false
			current += Vector2i(step_x, step_y)

	return true


# --- Threat Assessment ---

func get_threatened_tiles(champion: ChampionState, state: GameState) -> Array[Vector2i]:
	"""Get all tiles this champion threatens (can attack)."""
	var threatened: Array[Vector2i] = []
	var is_melee := is_melee_range(champion.current_range)
	var tiles := get_tiles_in_range(champion.position, champion.current_range, is_melee)

	for tile: Vector2i in tiles:
		if state.is_valid_position(tile):
			threatened.append(tile)

	return threatened


func count_threats_to_champion(champion: ChampionState, state: GameState) -> int:
	"""Count how many enemies can attack this champion."""
	var threat_count := 0
	var opponent_id := 2 if champion.owner_id == 1 else 1

	for enemy: ChampionState in state.get_champions(opponent_id):
		if enemy.is_alive() and can_attack(enemy, champion, state):
			threat_count += 1

	return threat_count
