extends Node
class_name CombatLogClass
## CombatLog - Tracks and stores all game events for review and debugging
## Listens to EventBus signals and creates formatted log entries

signal entry_added(entry: Dictionary)
signal log_cleared()

enum EntryType {
	TURN_START,
	TURN_END,
	MOVEMENT,
	ATTACK,
	DAMAGE,
	HEAL,
	DEATH,
	CARD_PLAYED,
	BUFF_APPLIED,
	DEBUFF_APPLIED,
	RESPONSE_WINDOW,
	MANA_SPENT,
	GAME_START,
	GAME_END,
	INFO
}

# Color coding for different entry types
const ENTRY_COLORS := {
	EntryType.TURN_START: Color(0.5, 0.7, 1.0),      # Light blue
	EntryType.TURN_END: Color(0.4, 0.5, 0.7),        # Dim blue
	EntryType.MOVEMENT: Color(0.6, 0.8, 0.6),        # Light green
	EntryType.ATTACK: Color(1.0, 0.6, 0.4),          # Orange
	EntryType.DAMAGE: Color(1.0, 0.4, 0.4),          # Red
	EntryType.HEAL: Color(0.4, 1.0, 0.5),            # Green
	EntryType.DEATH: Color(0.8, 0.2, 0.2),           # Dark red
	EntryType.CARD_PLAYED: Color(0.9, 0.8, 0.4),     # Gold
	EntryType.BUFF_APPLIED: Color(0.5, 0.9, 1.0),    # Cyan
	EntryType.DEBUFF_APPLIED: Color(0.9, 0.5, 0.9),  # Purple
	EntryType.RESPONSE_WINDOW: Color(1.0, 0.7, 0.3), # Amber
	EntryType.MANA_SPENT: Color(0.4, 0.6, 1.0),      # Blue
	EntryType.GAME_START: Color(1.0, 1.0, 1.0),      # White
	EntryType.GAME_END: Color(1.0, 0.9, 0.5),        # Bright gold
	EntryType.INFO: Color(0.7, 0.7, 0.7),            # Gray
}

# Log storage
var entries: Array[Dictionary] = []
var max_entries: int = 500
var current_round: int = 0
var current_turn_player: int = 0

# Reference to game state for champion name lookups
var _game_state: GameState = null


func _ready() -> void:
	_connect_signals()


func _connect_signals() -> void:
	"""Connect to EventBus signals for automatic logging."""
	# Game flow
	EventBus.game_started.connect(_on_game_started)
	EventBus.game_ended.connect(_on_game_ended)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.turn_ended.connect(_on_turn_ended)

	# Champion actions
	EventBus.champion_moved.connect(_on_champion_moved)
	EventBus.champion_attacked.connect(_on_champion_attacked)
	EventBus.champion_damaged.connect(_on_champion_damaged)
	EventBus.champion_healed.connect(_on_champion_healed)
	EventBus.champion_died.connect(_on_champion_died)

	# Buffs/Debuffs
	EventBus.champion_buff_applied.connect(_on_buff_applied)
	EventBus.champion_debuff_applied.connect(_on_debuff_applied)

	# Cards
	EventBus.card_played.connect(_on_card_played)

	# Mana
	EventBus.mana_spent.connect(_on_mana_spent)

	# Response system
	EventBus.response_window_opened.connect(_on_response_window_opened)


func set_game_state(state: GameState) -> void:
	"""Set reference to game state for champion lookups."""
	_game_state = state


func clear() -> void:
	"""Clear all log entries."""
	entries.clear()
	current_round = 0
	current_turn_player = 0
	log_cleared.emit()


func add_entry(type: EntryType, message: String, details: Dictionary = {}) -> void:
	"""Add a new log entry."""
	var entry := {
		"type": type,
		"message": message,
		"details": details,
		"timestamp": Time.get_ticks_msec(),
		"round": current_round,
		"turn_player": current_turn_player,
		"color": ENTRY_COLORS.get(type, Color.WHITE)
	}

	entries.append(entry)

	# Trim old entries if needed
	while entries.size() > max_entries:
		entries.pop_front()

	entry_added.emit(entry)

	# Also print to console for debugging
	print("[CombatLog] %s" % message)


func add_info(message: String) -> void:
	"""Add an informational log entry."""
	add_entry(EntryType.INFO, message)


func get_champion_name(champion_id: String) -> String:
	"""Get display name for a champion ID."""
	if _game_state == null:
		return champion_id

	var champion := _game_state.get_champion(champion_id)
	if champion:
		return champion.champion_name
	return champion_id


func get_champion_hp_string(champion_id: String) -> String:
	"""Get current HP string for a champion."""
	if _game_state == null:
		return ""

	var champion := _game_state.get_champion(champion_id)
	if champion:
		return " (%d/%d HP)" % [champion.current_hp, champion.max_hp]
	return ""


# === Signal Handlers ===

func _on_game_started(p1_champions: Array, p2_champions: Array) -> void:
	clear()
	var p1_names: Array[String] = []
	var p2_names: Array[String] = []

	for c in p1_champions:
		if c is ChampionState:
			p1_names.append(c.champion_name)

	for c in p2_champions:
		if c is ChampionState:
			p2_names.append(c.champion_name)

	add_entry(EntryType.GAME_START,
		"=== GAME STARTED ===\nPlayer 1: %s\nPlayer 2: %s" % [
			", ".join(p1_names) if p1_names.size() > 0 else "Unknown",
			", ".join(p2_names) if p2_names.size() > 0 else "Unknown"
		])


func _on_game_ended(winner: int, reason: String) -> void:
	var winner_text := "Player %d" % winner if winner > 0 else "Draw"
	add_entry(EntryType.GAME_END,
		"=== GAME OVER ===\nWinner: %s\nReason: %s" % [winner_text, reason])


func _on_turn_started(player_id: int, round_number: int) -> void:
	current_round = round_number
	current_turn_player = player_id
	var player_name := "Player 1" if player_id == 1 else "Player 2 (AI)"
	add_entry(EntryType.TURN_START,
		"--- Round %d: %s's Turn ---" % [round_number, player_name])


func _on_turn_ended(player_id: int) -> void:
	var player_name := "Player 1" if player_id == 1 else "Player 2 (AI)"
	add_entry(EntryType.TURN_END, "%s ends turn" % player_name)


func _on_champion_moved(champion_id: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	var name := get_champion_name(champion_id)
	add_entry(EntryType.MOVEMENT,
		"%s moved from (%d,%d) to (%d,%d)" % [name, from_pos.x, from_pos.y, to_pos.x, to_pos.y],
		{"champion_id": champion_id, "from": from_pos, "to": to_pos})


func _on_champion_attacked(attacker_id: String, target_id: String, damage: int) -> void:
	var attacker := get_champion_name(attacker_id)
	var target := get_champion_name(target_id)
	var hp_str := get_champion_hp_string(target_id)
	add_entry(EntryType.ATTACK,
		"%s attacks %s for %d damage%s" % [attacker, target, damage, hp_str],
		{"attacker_id": attacker_id, "target_id": target_id, "damage": damage})


func _on_champion_damaged(champion_id: String, amount: int, source: String) -> void:
	var name := get_champion_name(champion_id)
	var hp_str := get_champion_hp_string(champion_id)
	add_entry(EntryType.DAMAGE,
		"%s takes %d damage from %s%s" % [name, amount, source, hp_str],
		{"champion_id": champion_id, "amount": amount, "source": source})


func _on_champion_healed(champion_id: String, amount: int, source: String) -> void:
	var name := get_champion_name(champion_id)
	var hp_str := get_champion_hp_string(champion_id)
	add_entry(EntryType.HEAL,
		"%s heals %d HP from %s%s" % [name, amount, source, hp_str],
		{"champion_id": champion_id, "amount": amount, "source": source})


func _on_champion_died(champion_id: String, killer_id: String) -> void:
	var name := get_champion_name(champion_id)
	var killer := get_champion_name(killer_id) if killer_id else "unknown"
	add_entry(EntryType.DEATH,
		"*** %s has been DEFEATED by %s! ***" % [name, killer],
		{"champion_id": champion_id, "killer_id": killer_id})


func _on_buff_applied(champion_id: String, buff_name: String, duration: int) -> void:
	var name := get_champion_name(champion_id)
	var dur_text := " for %d turn(s)" % duration if duration > 0 else ""
	add_entry(EntryType.BUFF_APPLIED,
		"%s gains buff: %s%s" % [name, buff_name, dur_text],
		{"champion_id": champion_id, "buff": buff_name, "duration": duration})


func _on_debuff_applied(champion_id: String, debuff_name: String, duration: int) -> void:
	var name := get_champion_name(champion_id)
	var dur_text := " for %d turn(s)" % duration if duration > 0 else ""
	add_entry(EntryType.DEBUFF_APPLIED,
		"%s gains debuff: %s%s" % [name, debuff_name, dur_text],
		{"champion_id": champion_id, "debuff": debuff_name, "duration": duration})


func _on_card_played(player_id: int, card_id: String, targets: Array) -> void:
	var player_name := "Player 1" if player_id == 1 else "Player 2 (AI)"
	var card_data := CardDatabase.get_card(card_id)
	var card_name: String = card_data.get("name", card_id) if not card_data.is_empty() else card_id
	var cost: int = card_data.get("cost", 0) if not card_data.is_empty() else 0

	var target_text := ""
	if targets.size() > 0:
		var target_names: Array[String] = []
		for t in targets:
			if t is String:
				target_names.append(get_champion_name(t))
			elif t is Vector2i:
				target_names.append("(%d,%d)" % [t.x, t.y])
		target_text = " targeting %s" % ", ".join(target_names)

	add_entry(EntryType.CARD_PLAYED,
		"%s plays %s (cost %d)%s" % [player_name, card_name, cost, target_text],
		{"player_id": player_id, "card_id": card_id, "targets": targets})


func _on_mana_spent(player_id: int, amount: int, card_id: String) -> void:
	var player_name := "Player 1" if player_id == 1 else "Player 2 (AI)"
	add_entry(EntryType.MANA_SPENT,
		"%s spends %d mana" % [player_name, amount],
		{"player_id": player_id, "amount": amount, "card_id": card_id})


func _on_response_window_opened(trigger: String, context: Dictionary) -> void:
	add_entry(EntryType.RESPONSE_WINDOW,
		"Response window: %s" % trigger,
		{"trigger": trigger, "context": context})


# === Export Functions ===

func get_full_log_text() -> String:
	"""Get entire log as plain text for export."""
	var lines: Array[String] = []
	for entry in entries:
		var time_str := "[R%d] " % entry.round if entry.round > 0 else ""
		lines.append(time_str + entry.message)
	return "\n".join(lines)


func save_to_file(path: String = "user://combat_log.txt") -> bool:
	"""Save log to file."""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("Arena Combat Log\n")
		file.store_string("Generated: %s\n" % Time.get_datetime_string_from_system())
		file.store_string("=".repeat(50) + "\n\n")
		file.store_string(get_full_log_text())
		file.close()
		add_info("Log saved to %s" % path)
		return true
	return false
