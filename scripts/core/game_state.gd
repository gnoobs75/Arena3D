class_name GameState
extends RefCounted
## GameState - Complete snapshot of game state
## Designed for immutability to support AI simulation and undo

# Board constants
const BOARD_SIZE := 10
const PIT_MIN := 4
const PIT_MAX := 5

# Terrain types
enum Terrain {
	EMPTY,
	WALL,
	PIT
}

# Game tracking
var round_number: int = 0
var active_player: int = 1
var current_phase: String = "START"
var game_over: bool = false
var winner: int = 0

# Mana (fixed 5 per turn, no carryover)
var player1_mana: int = 5
var player2_mana: int = 5

# Locked mana (reduces mana gained at start of next turn)
var player1_locked_mana: int = 0
var player2_locked_mana: int = 0

# Champions (2 per player)
var player1_champions: Array[ChampionState] = []
var player2_champions: Array[ChampionState] = []

# Cards
var player1_hand: Array[String] = []  # Card names
var player2_hand: Array[String] = []
var player1_deck: Array[String] = []
var player2_deck: Array[String] = []
var player1_discard: Array[String] = []
var player2_discard: Array[String] = []

# Response slots - one card per player that auto-triggers when conditions met
var player1_response_slot: String = ""  # Card name or empty
var player2_response_slot: String = ""

# Board terrain (10x10)
var board_terrain: Array = []  # 2D array of Terrain enum

# Temporary terrain changes (cleared at end of turn)
var _temporary_terrain: Dictionary = {}  # Vector2i -> Terrain

# Response stack (LIFO)
var response_stack: Array[Dictionary] = []
var response_context: Dictionary = {}
var awaiting_response: bool = false
var response_priority_player: int = 0

# Action history for undo
var action_history: Array[Dictionary] = []


static func create_new_game(p1_champions: Array[String], p2_champions: Array[String]) -> GameState:
	"""Create a fresh game state with selected champions."""
	var state := GameState.new()
	state._initialize_board()
	state._initialize_champions(p1_champions, p2_champions)
	state._initialize_decks()
	state._place_champions()
	state._draw_initial_hands()
	state.round_number = 1
	state.active_player = 1
	state.current_phase = "START"
	return state


func duplicate() -> GameState:
	"""Create a deep copy for AI simulation."""
	var copy := GameState.new()

	copy.round_number = round_number
	copy.active_player = active_player
	copy.current_phase = current_phase
	copy.game_over = game_over
	copy.winner = winner

	copy.player1_mana = player1_mana
	copy.player2_mana = player2_mana
	copy.player1_locked_mana = player1_locked_mana
	copy.player2_locked_mana = player2_locked_mana

	# Deep copy champions
	for champion: ChampionState in player1_champions:
		copy.player1_champions.append(champion.duplicate())
	for champion: ChampionState in player2_champions:
		copy.player2_champions.append(champion.duplicate())

	# Copy card arrays
	copy.player1_hand = player1_hand.duplicate()
	copy.player2_hand = player2_hand.duplicate()
	copy.player1_deck = player1_deck.duplicate()
	copy.player2_deck = player2_deck.duplicate()
	copy.player1_discard = player1_discard.duplicate()
	copy.player2_discard = player2_discard.duplicate()

	# Copy response slots
	copy.player1_response_slot = player1_response_slot
	copy.player2_response_slot = player2_response_slot

	# Deep copy board
	copy.board_terrain = []
	for row: Array in board_terrain:
		copy.board_terrain.append(row.duplicate())

	# Copy temporary terrain
	copy._temporary_terrain = _temporary_terrain.duplicate()

	# Copy response state
	copy.response_stack = response_stack.duplicate(true)
	copy.response_context = response_context.duplicate(true)
	copy.awaiting_response = awaiting_response
	copy.response_priority_player = response_priority_player

	return copy


# --- Initialization ---

func _initialize_board() -> void:
	"""Set up 10x10 board with walls and central pit."""
	board_terrain = []
	for y in range(BOARD_SIZE):
		var row: Array = []
		for x in range(BOARD_SIZE):
			if _is_wall(x, y):
				row.append(Terrain.WALL)
			elif _is_pit(x, y):
				row.append(Terrain.PIT)
			else:
				row.append(Terrain.EMPTY)
		board_terrain.append(row)


func _is_wall(x: int, y: int) -> bool:
	"""Walls are on the edges of the board."""
	return x == 0 or x == BOARD_SIZE - 1 or y == 0 or y == BOARD_SIZE - 1


func _is_pit(x: int, y: int) -> bool:
	"""Central 2x2 pit."""
	return x >= PIT_MIN and x <= PIT_MAX and y >= PIT_MIN and y <= PIT_MAX


func _initialize_champions(p1_names: Array[String], p2_names: Array[String]) -> void:
	"""Create champion states for both players."""
	for i in range(p1_names.size()):
		var champion := ChampionState.create(p1_names[i], 1, i)
		player1_champions.append(champion)

	for i in range(p2_names.size()):
		var champion := ChampionState.create(p2_names[i], 2, i)
		player2_champions.append(champion)


func _initialize_decks() -> void:
	"""Build and shuffle decks for each champion."""
	for champion: ChampionState in player1_champions:
		var cards := CardDatabase.build_deck_for_champion(champion.champion_name)
		player1_deck.append_array(cards)
	player1_deck.shuffle()

	for champion: ChampionState in player2_champions:
		var cards := CardDatabase.build_deck_for_champion(champion.champion_name)
		player2_deck.append_array(cards)
	player2_deck.shuffle()


func _place_champions() -> void:
	"""Place champions on starting positions."""
	# Player 1: bottom of board (y = 8)
	if player1_champions.size() >= 1:
		player1_champions[0].position = Vector2i(2, 8)
		player1_champions[0].is_on_board = true
	if player1_champions.size() >= 2:
		player1_champions[1].position = Vector2i(7, 8)
		player1_champions[1].is_on_board = true

	# Player 2: top of board (y = 1)
	if player2_champions.size() >= 1:
		player2_champions[0].position = Vector2i(2, 1)
		player2_champions[0].is_on_board = true
	if player2_champions.size() >= 2:
		player2_champions[1].position = Vector2i(7, 1)
		player2_champions[1].is_on_board = true


func _draw_initial_hands() -> void:
	"""Draw starting hands (5 cards each)."""
	for i in range(5):
		draw_card(1)
		draw_card(2)


# --- Card Operations ---

func draw_card(player_id: int) -> String:
	"""Draw a card for player. Returns card name or empty if deck empty.
	Cards belonging to dead champions are automatically discarded."""
	var deck := get_deck(player_id)
	var hand := get_hand(player_id)
	var discard := get_discard(player_id)

	while not deck.is_empty():
		var card_name: String = deck.pop_back()
		var card_data := CardDatabase.get_card(card_name)
		var champion_name: String = card_data.get("character", "")

		# Check if this card's champion is dead
		if _is_champion_dead_by_name(player_id, champion_name):
			# Card goes directly to discard
			discard.append(card_name)
			continue

		# Valid card - add to hand
		hand.append(card_name)
		return card_name

	return ""


func _is_champion_dead_by_name(player_id: int, champion_name: String) -> bool:
	"""Check if a champion with the given name is dead for this player."""
	for champion: ChampionState in get_champions(player_id):
		if champion.champion_name == champion_name:
			return champion.is_dead()
	# Champion not found for this player - shouldn't happen but treat as dead
	return true


func discard_dead_champion_cards(player_id: int, champion_name: String) -> int:
	"""Discard all cards in hand belonging to a dead champion.
	Returns the number of cards discarded."""
	var hand := get_hand(player_id)
	var discard := get_discard(player_id)
	var discarded_count := 0

	# Iterate backwards to safely remove while iterating
	for i in range(hand.size() - 1, -1, -1):
		var card_name: String = hand[i]
		var card_data := CardDatabase.get_card(card_name)
		var card_champion: String = card_data.get("character", "")

		if card_champion == champion_name:
			hand.remove_at(i)
			discard.append(card_name)
			discarded_count += 1

	if discarded_count > 0:
		print("Discarded %d cards for dead champion %s (player %d)" % [discarded_count, champion_name, player_id])

	return discarded_count


func discard_card(player_id: int, card_name: String) -> bool:
	"""Move card from hand to discard. Returns success."""
	var hand := get_hand(player_id)
	var discard := get_discard(player_id)

	var index := hand.find(card_name)
	if index == -1:
		return false

	hand.remove_at(index)
	discard.append(card_name)
	return true


# --- Response Slot Operations ---

func get_response_slot(player_id: int) -> String:
	"""Get the card in player's response slot (empty string if none)."""
	return player1_response_slot if player_id == 1 else player2_response_slot


func set_response_slot(player_id: int, card_name: String) -> bool:
	"""Place a card from hand into the response slot. Returns success."""
	var hand := get_hand(player_id)

	# If there's already a card in the slot, return it to hand first
	var current_slot := get_response_slot(player_id)
	if not current_slot.is_empty():
		hand.append(current_slot)

	# If setting to empty, just clear the slot
	if card_name.is_empty():
		if player_id == 1:
			player1_response_slot = ""
		else:
			player2_response_slot = ""
		return true

	# Find and remove card from hand
	var index := hand.find(card_name)
	if index == -1:
		return false

	# Verify it's a response card
	var card_data := CardDatabase.get_card(card_name)
	if card_data.get("type", "") != "Response":
		return false

	hand.remove_at(index)

	if player_id == 1:
		player1_response_slot = card_name
	else:
		player2_response_slot = card_name

	return true


func clear_response_slot(player_id: int) -> String:
	"""Remove card from response slot and return it to hand. Returns the card name."""
	var card_name := get_response_slot(player_id)
	if card_name.is_empty():
		return ""

	var hand := get_hand(player_id)
	hand.append(card_name)

	if player_id == 1:
		player1_response_slot = ""
	else:
		player2_response_slot = ""

	return card_name


func discard_response_slot(player_id: int) -> String:
	"""Remove card from response slot and put it in discard. Returns the card name."""
	var card_name := get_response_slot(player_id)
	if card_name.is_empty():
		return ""

	var discard := get_discard(player_id)
	discard.append(card_name)

	if player_id == 1:
		player1_response_slot = ""
	else:
		player2_response_slot = ""

	return card_name


func play_card(player_id: int, card_name: String) -> bool:
	"""Remove card from hand (when played). Returns success."""
	var hand := get_hand(player_id)

	var index := hand.find(card_name)
	if index == -1:
		return false

	hand.remove_at(index)
	# Card goes to discard after effects resolve
	return true


func get_hand(player_id: int) -> Array:
	return player1_hand if player_id == 1 else player2_hand


func get_deck(player_id: int) -> Array:
	return player1_deck if player_id == 1 else player2_deck


func get_discard(player_id: int) -> Array:
	return player1_discard if player_id == 1 else player2_discard


func get_mana(player_id: int) -> int:
	return player1_mana if player_id == 1 else player2_mana


func spend_mana(player_id: int, amount: int) -> bool:
	"""Spend mana. Returns false if not enough."""
	if player_id == 1:
		if player1_mana < amount:
			return false
		player1_mana -= amount
	else:
		if player2_mana < amount:
			return false
		player2_mana -= amount
	return true


func reset_mana(player_id: int) -> void:
	"""Reset mana to 5 at start of turn, minus any locked mana."""
	if player_id == 1:
		var locked := player1_locked_mana
		player1_mana = maxi(0, 5 - locked)
		player1_locked_mana = 0  # Clear locked mana after applying
		if locked > 0:
			print("Player 1 mana reset to %d (was locked: %d)" % [player1_mana, locked])
	else:
		var locked := player2_locked_mana
		player2_mana = maxi(0, 5 - locked)
		player2_locked_mana = 0
		if locked > 0:
			print("Player 2 mana reset to %d (was locked: %d)" % [player2_mana, locked])


func lock_mana(player_id: int, amount: int) -> void:
	"""Lock mana for next turn (Mana Burn effect)."""
	if player_id == 1:
		player1_locked_mana += amount
	else:
		player2_locked_mana += amount
	print("Player %d has %d mana locked for next turn" % [player_id, amount])


func get_locked_mana(player_id: int) -> int:
	"""Get amount of locked mana for player."""
	return player1_locked_mana if player_id == 1 else player2_locked_mana


func add_mana(player_id: int, amount: int) -> void:
	"""Add mana to player (gainMana effect)."""
	if player_id == 1:
		player1_mana += amount
	else:
		player2_mana += amount
	print("Player %d gained %d mana" % [player_id, amount])


func steal_mana(from_player: int, to_player: int, amount: int) -> int:
	"""Steal mana from one player to another. Returns actual amount stolen."""
	var current := get_mana(from_player)
	var stolen := mini(amount, current)

	if stolen > 0:
		spend_mana(from_player, stolen)
		add_mana(to_player, stolen)
		print("Player %d stole %d mana from Player %d" % [to_player, stolen, from_player])

	return stolen


func shuffle_discard_into_deck(player_id: int) -> int:
	"""Shuffle all cards from discard pile into deck. Returns number of cards shuffled."""
	var discard := get_discard(player_id)
	var deck := get_deck(player_id)

	var count := discard.size()
	if count == 0:
		return 0

	deck.append_array(discard)
	discard.clear()
	deck.shuffle()

	print("Player %d shuffled %d cards from discard into deck" % [player_id, count])
	return count


func return_card_to_hand(player_id: int, card_name: String) -> bool:
	"""Return a card from discard to hand. Returns success."""
	var discard := get_discard(player_id)
	var hand := get_hand(player_id)

	var index := discard.find(card_name)
	if index == -1:
		return false

	discard.remove_at(index)
	hand.append(card_name)
	print("Player %d returned %s to hand from discard" % [player_id, card_name])
	return true


func can_cast_from_discard(player_id: int) -> bool:
	"""Check if player has castFromDiscard buff on any champion."""
	for champion: ChampionState in get_champions(player_id):
		if champion.is_alive() and champion.has_buff("castFromDiscard"):
			return true
	return false


func get_castable_from_discard(player_id: int) -> Array[String]:
	"""Get list of cards that can be cast from discard."""
	if not can_cast_from_discard(player_id):
		return []

	var castable: Array[String] = []
	var discard := get_discard(player_id)
	var mana := get_mana(player_id)

	for card_name: String in discard:
		var card_data := CardDatabase.get_card(card_name)
		var card_type: String = card_data.get("type", "")
		var cost: int = card_data.get("cost", 0)

		# Only Action cards can be cast from discard
		if card_type == "Action" and cost <= mana:
			castable.append(card_name)

	return castable


# --- Champion Queries ---

func get_champion(unique_id: String) -> ChampionState:
	"""Find champion by unique ID."""
	for champion: ChampionState in player1_champions:
		if champion.unique_id == unique_id:
			return champion
	for champion: ChampionState in player2_champions:
		if champion.unique_id == unique_id:
			return champion
	return null


func get_champions(player_id: int) -> Array[ChampionState]:
	return player1_champions if player_id == 1 else player2_champions


func get_all_champions() -> Array[ChampionState]:
	var all: Array[ChampionState] = []
	all.append_array(player1_champions)
	all.append_array(player2_champions)
	return all


func get_champion_at(pos: Vector2i) -> ChampionState:
	"""Find champion at board position."""
	for champion: ChampionState in get_all_champions():
		if champion.is_on_board and champion.position == pos:
			return champion
	return null


func get_living_champions(player_id: int) -> Array[ChampionState]:
	var living: Array[ChampionState] = []
	for champion: ChampionState in get_champions(player_id):
		if champion.is_alive():
			living.append(champion)
	return living


# --- Board Queries ---

func get_terrain(pos: Vector2i) -> Terrain:
	if pos.x < 0 or pos.x >= BOARD_SIZE or pos.y < 0 or pos.y >= BOARD_SIZE:
		return Terrain.WALL
	# Check temporary terrain first
	if _temporary_terrain.has(pos):
		return _temporary_terrain[pos]
	return board_terrain[pos.y][pos.x]


func is_walkable(pos: Vector2i) -> bool:
	var terrain := get_terrain(pos)
	if terrain != Terrain.EMPTY:
		return false
	if get_champion_at(pos) != null:
		return false
	return true


func is_valid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_SIZE and pos.y >= 0 and pos.y < BOARD_SIZE


# --- Temporary Terrain Management ---

func set_temporary_terrain(pos: Vector2i, terrain: Terrain) -> void:
	"""Set a temporary terrain override that lasts until end of turn."""
	if is_valid_position(pos):
		_temporary_terrain[pos] = terrain
		print("Temporary terrain set at %s: %s" % [pos, Terrain.keys()[terrain]])


func clear_temporary_terrain() -> void:
	"""Clear all temporary terrain (called at end of turn)."""
	if not _temporary_terrain.is_empty():
		print("Clearing %d temporary terrain tiles" % _temporary_terrain.size())
		_temporary_terrain.clear()


func get_temporary_terrain_positions() -> Array:
	"""Get all positions with temporary terrain (for visual updates)."""
	return _temporary_terrain.keys()


func create_pits_around(center_pos: Vector2i) -> Array[Vector2i]:
	"""Create temporary pits around a position (for Pit of Despair)."""
	var pit_positions: Array[Vector2i] = []

	# All 8 adjacent tiles
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue  # Skip center
			var pos := Vector2i(center_pos.x + dx, center_pos.y + dy)
			# Only create pit on empty tiles (not walls or existing pits)
			if is_valid_position(pos) and board_terrain[pos.y][pos.x] == Terrain.EMPTY:
				set_temporary_terrain(pos, Terrain.PIT)
				pit_positions.append(pos)

	return pit_positions


# --- Win Condition ---

func check_win_condition() -> void:
	"""Check if game is over."""
	var p1_alive := get_living_champions(1).size()
	var p2_alive := get_living_champions(2).size()

	if p1_alive == 0 and p2_alive == 0:
		# Tie - shouldn't happen but handle it
		game_over = true
		winner = 0
	elif p1_alive == 0:
		game_over = true
		winner = 2
	elif p2_alive == 0:
		game_over = true
		winner = 1


# --- Response Stack ---

func push_response(card_name: String, player_id: int, targets: Array) -> void:
	"""Add a response card to the stack."""
	response_stack.append({
		"card_name": card_name,
		"player_id": player_id,
		"targets": targets
	})


func pop_response() -> Dictionary:
	"""Remove and return top response from stack."""
	if response_stack.is_empty():
		return {}
	return response_stack.pop_back()


func clear_response_stack() -> void:
	response_stack.clear()
	awaiting_response = false
	response_context = {}


# --- Turn Management ---

func start_turn(player_id: int) -> void:
	"""Initialize state at start of turn."""
	active_player = player_id
	current_phase = "START"

	# Reset mana
	reset_mana(player_id)

	# Reset champion flags
	for champion: ChampionState in get_champions(player_id):
		champion.reset_turn()

	# Draw a card
	draw_card(player_id)


func end_turn(player_id: int) -> void:
	"""Cleanup at end of turn."""
	current_phase = "END"

	# Discard down to 7
	var hand := get_hand(player_id)
	while hand.size() > 7:
		# For now, discard last card (AI/UI would choose)
		var card_name: String = hand.pop_back()
		get_discard(player_id).append(card_name)

	# Clear temporary terrain (Pit of Despair pits, etc.)
	clear_temporary_terrain()

	# Tick effect durations
	for champion: ChampionState in get_champions(player_id):
		champion.clear_this_turn_effects()

	# Check win condition
	check_win_condition()


func _to_string() -> String:
	return "GameState<Round:%d Player:%d Phase:%s P1HP:%s P2HP:%s>" % [
		round_number,
		active_player,
		current_phase,
		_champions_hp_string(1),
		_champions_hp_string(2)
	]


func _champions_hp_string(player_id: int) -> String:
	var parts: Array[String] = []
	for champion: ChampionState in get_champions(player_id):
		parts.append("%d" % champion.current_hp)
	return "/".join(parts)
