class_name Pathfinder
extends RefCounted
## Pathfinder - BFS pathfinding with agility buff support
## Handles movement on 10x10 grid with walls, pits, and champions as obstacles

# Direction vectors - 4 cardinal directions (default)
const CARDINAL_DIRS: Array[Vector2i] = [
	Vector2i(0, -1),  # Up
	Vector2i(0, 1),   # Down
	Vector2i(-1, 0),  # Left
	Vector2i(1, 0)    # Right
]

# 8 directions including diagonals (with agility buff)
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

var game_state: GameState


func _init(state: GameState) -> void:
	game_state = state


func find_path(from: Vector2i, to: Vector2i, champion: ChampionState) -> Array[Vector2i]:
	"""
	Find shortest path from 'from' to 'to' using BFS.
	Returns array of positions (not including start).
	Empty array if no path exists.
	"""
	if from == to:
		return []

	if not _is_valid_destination(to, champion):
		return []

	var directions := _get_move_directions(champion)
	var queue: Array[Vector2i] = [from]
	var came_from: Dictionary = {from: null}
	var found := false

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		if current == to:
			found = true
			break

		for dir: Vector2i in directions:
			var next := current + dir

			if came_from.has(next):
				continue

			if not _is_walkable(next, champion):
				continue

			came_from[next] = current
			queue.append(next)

	if not found:
		return []

	# Reconstruct path
	var path: Array[Vector2i] = []
	var current := to
	while current != from:
		path.push_front(current)
		current = came_from[current]

	return path


func get_reachable_tiles(champion: ChampionState) -> Array[Vector2i]:
	"""
	Get all tiles reachable within champion's movement range.
	Uses BFS with distance tracking.
	"""
	var reachable: Array[Vector2i] = []
	var start: Vector2i = champion.position
	var max_distance: int = champion.movement_remaining
	var directions: Array[Vector2i] = _get_move_directions(champion)

	# BFS with distance tracking
	var queue: Array[Dictionary] = [{"pos": start, "dist": 0}]
	var visited: Dictionary = {start: 0}

	while not queue.is_empty():
		var entry: Dictionary = queue.pop_front()
		var current: Vector2i = entry["pos"]
		var dist: int = entry["dist"]

		if dist > 0:  # Don't include starting position
			reachable.append(current)

		if dist >= max_distance:
			continue

		for dir: Vector2i in directions:
			var next := current + dir

			if visited.has(next) and visited[next] <= dist + 1:
				continue

			if not _is_walkable(next, champion):
				continue

			visited[next] = dist + 1
			queue.append({"pos": next, "dist": dist + 1})

	return reachable


func get_distance(from: Vector2i, to: Vector2i, champion: ChampionState) -> int:
	"""
	Get movement distance between two positions.
	Returns -1 if unreachable.
	"""
	var path := find_path(from, to, champion)
	if path.is_empty() and from != to:
		return -1
	return path.size()


func _get_move_directions(champion: ChampionState) -> Array[Vector2i]:
	"""Get available move directions based on buffs."""
	if champion.has_buff("agility"):
		return ALL_DIRS
	return CARDINAL_DIRS


func _is_walkable(pos: Vector2i, champion: ChampionState) -> bool:
	"""Check if a tile can be walked on."""
	# Check bounds
	if not game_state.is_valid_position(pos):
		return false

	# Check terrain
	var terrain := game_state.get_terrain(pos)

	# Walls block movement (unless has specific buff)
	if terrain == GameState.Terrain.WALL:
		if champion.has_buff("overWall"):
			return true
		return false

	# Pits block movement
	if terrain == GameState.Terrain.PIT:
		return false

	# Check for other champions (can't walk through them)
	var occupant := game_state.get_champion_at(pos)
	if occupant != null:
		return false

	return true


func _is_valid_destination(pos: Vector2i, champion: ChampionState) -> bool:
	"""Check if a position is a valid movement destination."""
	# Must be walkable
	if not _is_walkable(pos, champion):
		return false

	# Additional destination-specific checks could go here
	return true


func get_adjacent_tiles(pos: Vector2i, include_diagonals: bool = false) -> Array[Vector2i]:
	"""Get all adjacent tiles to a position."""
	var adjacent: Array[Vector2i] = []
	var directions := ALL_DIRS if include_diagonals else CARDINAL_DIRS

	for dir: Vector2i in directions:
		var neighbor := pos + dir
		if game_state.is_valid_position(neighbor):
			adjacent.append(neighbor)

	return adjacent


func get_empty_adjacent_tiles(pos: Vector2i, include_diagonals: bool = false) -> Array[Vector2i]:
	"""Get adjacent tiles that are empty and walkable."""
	var empty: Array[Vector2i] = []

	for neighbor: Vector2i in get_adjacent_tiles(pos, include_diagonals):
		var terrain := game_state.get_terrain(neighbor)
		if terrain == GameState.Terrain.EMPTY:
			if game_state.get_champion_at(neighbor) == null:
				empty.append(neighbor)

	return empty


func manhattan_distance(from: Vector2i, to: Vector2i) -> int:
	"""Calculate Manhattan distance between two points."""
	return absi(to.x - from.x) + absi(to.y - from.y)


func chebyshev_distance(from: Vector2i, to: Vector2i) -> int:
	"""Calculate Chebyshev distance (allows diagonals as 1 step)."""
	return maxi(absi(to.x - from.x), absi(to.y - from.y))
