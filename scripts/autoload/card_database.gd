extends Node
## CardDatabase - Loads and manages card/champion data from JSON files
## Provides access to card definitions and handles deck building

const CARDS_PATH := "res://data/cards.json"
const CHAMPIONS_PATH := "res://data/champions.json"

# Card data indexed by card name (unique identifier)
var _cards: Dictionary = {}
# Cards grouped by champion name
var _cards_by_champion: Dictionary = {}
# Champion base stats
var _champions: Dictionary = {}
# All champion names
var _champion_names: Array[String] = []

signal database_loaded()
signal database_load_failed(error: String)

var is_loaded: bool = false


func _ready() -> void:
	print("CardDatabase: _ready called")
	# Defer loading to allow scenes to connect to signals first
	call_deferred("_load_database")


func _load_database() -> void:
	print("CardDatabase: _load_database called (deferred)")
	var cards_loaded := _load_cards()
	print("CardDatabase: cards_loaded = %s" % cards_loaded)
	var champions_loaded := _load_champions()
	print("CardDatabase: champions_loaded = %s" % champions_loaded)

	if cards_loaded and champions_loaded:
		is_loaded = true
		print("CardDatabase: Loaded %d cards for %d champions" % [_cards.size(), _champion_names.size()])
		print("CardDatabase: Emitting database_loaded signal")
		database_loaded.emit()
		print("CardDatabase: Signal emitted")
	else:
		var error := "Failed to load game data"
		database_load_failed.emit(error)
		push_error("CardDatabase: " + error)


func _load_cards() -> bool:
	print("CardDatabase: _load_cards() - Opening file: %s" % CARDS_PATH)
	var file := FileAccess.open(CARDS_PATH, FileAccess.READ)
	if not file:
		var err := FileAccess.get_open_error()
		push_error("CardDatabase: Cannot open cards.json - Error: %d" % err)
		return false

	print("CardDatabase: File opened successfully")
	var json_text := file.get_as_text()
	file.close()
	print("CardDatabase: Read %d characters from file" % json_text.length())

	var json := JSON.new()
	var parse_result := json.parse(json_text)
	if parse_result != OK:
		push_error("CardDatabase: Failed to parse cards.json - %s at line %d" % [json.get_error_message(), json.get_error_line()])
		return false

	print("CardDatabase: JSON parsed successfully")
	var data: Array = json.data
	print("CardDatabase: Found %d card entries" % data.size())
	for card_data: Dictionary in data:
		var card_name: String = card_data.get("name", "")
		var champion: String = card_data.get("character", "")

		if card_name.is_empty():
			continue

		_cards[card_name] = card_data

		if not champion.is_empty():
			if not _cards_by_champion.has(champion):
				_cards_by_champion[champion] = []
				_champion_names.append(champion)
			_cards_by_champion[champion].append(card_name)

	print("CardDatabase: _load_cards() complete - %d cards, %d champions found" % [_cards.size(), _champion_names.size()])
	return true


func _load_champions() -> bool:
	print("CardDatabase: _load_champions() - Opening file: %s" % CHAMPIONS_PATH)
	var file := FileAccess.open(CHAMPIONS_PATH, FileAccess.READ)
	if not file:
		push_warning("CardDatabase: champions.json not found, will be created")
		return true  # Not fatal - champions.json will be created separately

	print("CardDatabase: champions.json opened successfully")
	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_text)
	if parse_result != OK:
		push_error("CardDatabase: Failed to parse champions.json - %s" % json.get_error_message())
		return false

	_champions = json.data
	print("CardDatabase: _load_champions() complete - %d champion stats loaded" % _champions.size())
	return true


# --- Card Access ---

func get_card(card_name: String) -> Dictionary:
	"""Get card data by name. Returns empty dict if not found."""
	return _cards.get(card_name, {})


func get_cards_for_champion(champion_name: String) -> Array:
	"""Get all card names for a champion."""
	return _cards_by_champion.get(champion_name, [])


func get_all_card_names() -> Array:
	"""Get all card names in the database."""
	return _cards.keys()


func card_exists(card_name: String) -> bool:
	"""Check if a card exists in the database."""
	return _cards.has(card_name)


# --- Champion Access ---

func get_champion_stats(champion_name: String) -> Dictionary:
	"""Get base stats for a champion. Returns empty dict if not found."""
	return _champions.get(champion_name, {})


func get_all_champion_names() -> Array[String]:
	"""Get list of all champion names."""
	return _champion_names


func champion_exists(champion_name: String) -> bool:
	"""Check if a champion exists."""
	return _champions.has(champion_name) or _cards_by_champion.has(champion_name)


# --- Deck Building ---

func build_deck_for_champion(champion_name: String) -> Array[String]:
	"""
	Build a 40-card deck for a champion using 'Number in Deck' values.
	Returns an array of card names (with duplicates based on copies).
	"""
	var deck: Array[String] = []
	var card_names := get_cards_for_champion(champion_name)

	for card_name: String in card_names:
		var card_data := get_card(card_name)
		var copies: int = card_data.get("Number in Deck", 1)

		for i in range(copies):
			deck.append(card_name)

	return deck


func get_deck_size_for_champion(champion_name: String) -> int:
	"""Calculate total deck size for a champion based on 'Number in Deck' values."""
	var total := 0
	var card_names := get_cards_for_champion(champion_name)

	for card_name: String in card_names:
		var card_data := get_card(card_name)
		total += card_data.get("Number in Deck", 1)

	return total


# --- Card Filtering ---

func get_cards_by_type(champion_name: String, card_type: String) -> Array[String]:
	"""Get cards of a specific type (Action, Response, Equipment) for a champion."""
	var result: Array[String] = []
	var card_names := get_cards_for_champion(champion_name)

	for card_name: String in card_names:
		var card_data := get_card(card_name)
		if card_data.get("type", "") == card_type:
			result.append(card_name)

	return result


func get_cards_by_trigger(champion_name: String, trigger: String) -> Array[String]:
	"""Get response cards with a specific trigger type."""
	var result: Array[String] = []
	var card_names := get_cards_for_champion(champion_name)

	for card_name: String in card_names:
		var card_data := get_card(card_name)
		if card_data.get("trigger", "") == trigger:
			result.append(card_name)

	return result


func get_cards_by_cost(champion_name: String, max_cost: int) -> Array[String]:
	"""Get cards that cost at most max_cost mana."""
	var result: Array[String] = []
	var card_names := get_cards_for_champion(champion_name)

	for card_name: String in card_names:
		var card_data := get_card(card_name)
		if card_data.get("cost", 0) <= max_cost:
			result.append(card_name)

	return result
