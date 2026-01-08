extends Node
## EventBus - Global signal hub for decoupled communication
## Centralizes all game events to allow loose coupling between systems

# Game Flow Signals
signal game_started(player1_champions: Array, player2_champions: Array)
signal game_ended(winner: int, reason: String)
signal turn_started(player_id: int, round_number: int)
signal turn_ended(player_id: int)
signal phase_changed(new_phase: String)

# Champion Signals
signal champion_moved(champion_id: String, from_pos: Vector2i, to_pos: Vector2i)
signal champion_attacked(attacker_id: String, target_id: String, damage: int)
signal champion_damaged(champion_id: String, amount: int, source: String)
signal champion_healed(champion_id: String, amount: int, source: String)
signal champion_died(champion_id: String, killer_id: String)
signal champion_stats_changed(champion_id: String, stat: String, old_value: int, new_value: int)
signal champion_buff_applied(champion_id: String, buff_name: String, duration: int)
signal champion_buff_removed(champion_id: String, buff_name: String)
signal champion_debuff_applied(champion_id: String, debuff_name: String, duration: int)
signal champion_debuff_removed(champion_id: String, debuff_name: String)

# Card Signals
signal card_drawn(player_id: int, card_id: String)
signal card_played(player_id: int, card_id: String, targets: Array)
signal card_discarded(player_id: int, card_id: String)
signal card_hovered(card_id: String)
signal card_unhovered(card_id: String)

# Response Stack Signals
signal response_window_opened(trigger: String, context: Dictionary)
signal response_window_closed()
signal response_added(player_id: int, card_id: String)
signal response_stack_resolving()
signal response_stack_resolved()
signal priority_granted(player_id: int)
signal priority_passed(player_id: int)

# Mana Signals
signal mana_changed(player_id: int, old_amount: int, new_amount: int)
signal mana_spent(player_id: int, amount: int, card_id: String)

# UI Signals
signal tile_clicked(position: Vector2i)
signal tile_hovered(position: Vector2i)
signal tile_unhovered(position: Vector2i)
signal champion_selected(champion_id: String)
signal champion_deselected(champion_id: String)
signal valid_moves_requested(champion_id: String)
signal valid_targets_requested(card_id: String)
signal action_cancelled()

# AI Signals
signal ai_thinking_started(player_id: int)
signal ai_thinking_finished(player_id: int)
signal ai_action_chosen(action: Dictionary)

# Network Signals
signal player_connected(player_id: int)
signal player_disconnected(player_id: int)
signal sync_received(state: Dictionary)
signal network_error(message: String)


func _ready() -> void:
	pass
