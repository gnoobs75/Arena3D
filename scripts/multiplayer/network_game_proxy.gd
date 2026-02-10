extends RefCounted
## NetworkGameProxy - Bridges local game logic with network communication
## Host runs authoritative GameController; guest sends requests and receives state sync.
##
## Architecture:
## - Host: Executes all actions locally, sends action results + state snapshots to guest
## - Guest: Sends action requests to host, receives results, applies state sync locally
## - Both sides maintain a GameController for rendering, but host is source of truth

signal remote_action_received(action: Dictionary)
signal state_sync_applied()
signal opponent_end_turn()
signal opponent_disconnected()

var game_controller: GameController  # Reference to local GameController
var is_host: bool = false
var local_player_id: int = 0  # 1 for host, 2 for guest


func initialize(controller: GameController) -> void:
	"""Initialize proxy with the local game controller."""
	game_controller = controller
	is_host = NetworkManager.is_host()
	local_player_id = NetworkManager.local_player_id

	# Connect to NetworkManager signals
	NetworkManager.action_received.connect(_on_action_received)
	NetworkManager.state_sync_received.connect(_on_state_sync_received)
	NetworkManager.opponent_left.connect(_on_opponent_disconnected)

	print("NetworkGameProxy: Initialized as %s (player %d)" % [
		"HOST" if is_host else "GUEST", local_player_id
	])


func cleanup() -> void:
	"""Disconnect signals when game ends."""
	if NetworkManager.action_received.is_connected(_on_action_received):
		NetworkManager.action_received.disconnect(_on_action_received)
	if NetworkManager.state_sync_received.is_connected(_on_state_sync_received):
		NetworkManager.state_sync_received.disconnect(_on_state_sync_received)
	if NetworkManager.opponent_left.is_connected(_on_opponent_disconnected):
		NetworkManager.opponent_left.disconnect(_on_opponent_disconnected)


func is_local_player_turn() -> bool:
	"""Check if it's the local player's turn."""
	if game_controller == null or game_controller.game_state == null:
		return false
	return game_controller.game_state.active_player == local_player_id


# === Host: Sending action results ===

func broadcast_action(action_type: String, params: Dictionary, result: Dictionary) -> void:
	"""Host broadcasts an executed action to the guest."""
	if not is_host:
		return

	var msg := {
		"type": "g_action_result",
		"action_type": action_type,
		"params": params,
		"result": result,
	}
	NetworkManager.send_action(msg)


func broadcast_state_sync() -> void:
	"""Host sends a state snapshot to the guest after each action."""
	if not is_host or game_controller == null:
		return

	var state := game_controller.game_state
	var sync_data := _serialize_state(state)
	NetworkManager.send_state_sync(sync_data)


func broadcast_end_turn() -> void:
	"""Host or guest broadcasts end turn to opponent."""
	NetworkManager.send_action({
		"type": "g_end_turn",
		"player_id": local_player_id
	})


# === Guest: Sending action requests ===

func send_move_request(champion_id: String, target_pos: Vector2i) -> void:
	"""Guest sends a move request to host."""
	NetworkManager.send_action({
		"type": "g_action_request",
		"action": "move",
		"champion_id": champion_id,
		"target_x": target_pos.x,
		"target_y": target_pos.y
	})


func send_attack_request(attacker_id: String, target_id: String) -> void:
	"""Guest sends an attack request to host."""
	NetworkManager.send_action({
		"type": "g_action_request",
		"action": "attack",
		"attacker_id": attacker_id,
		"target_id": target_id
	})


func send_cast_request(card_name: String, caster_id: String, targets: Array) -> void:
	"""Guest sends a cast request to host."""
	NetworkManager.send_action({
		"type": "g_action_request",
		"action": "cast",
		"card_name": card_name,
		"caster_id": caster_id,
		"targets": targets
	})


func send_end_turn_request() -> void:
	"""Guest sends end turn request to host."""
	NetworkManager.send_action({
		"type": "g_action_request",
		"action": "end_turn"
	})


func send_response_slot_request(player_id: int, card_name: String) -> void:
	"""Send response slot update to opponent."""
	NetworkManager.send_action({
		"type": "g_response_slot",
		"player_id": player_id,
		"card_name": card_name
	})


# === Receiving messages ===

func _on_action_received(payload: Dictionary) -> void:
	"""Handle received game action message."""
	var msg_type: String = payload.get("type", "")

	match msg_type:
		"g_action_request":
			# Host receives a guest's action request
			if is_host:
				_handle_guest_action_request(payload)

		"g_action_result":
			# Guest receives host's action result
			if not is_host:
				_handle_host_action_result(payload)

		"g_end_turn":
			# Opponent ended their turn
			opponent_end_turn.emit()

		"g_response_slot":
			# Opponent updated their response slot
			_handle_response_slot_update(payload)

		"g_game_over":
			# Game ended (from host)
			pass


func _on_state_sync_received(state_data: Dictionary) -> void:
	"""Guest receives state sync from host."""
	if is_host:
		return  # Host doesn't apply syncs from guest

	_apply_state_sync(state_data)
	state_sync_applied.emit()


func _on_opponent_disconnected(_reason: String) -> void:
	opponent_disconnected.emit()


# === Host: Processing guest requests ===

func _handle_guest_action_request(payload: Dictionary) -> void:
	"""Host validates and executes a guest's action request."""
	var action: String = payload.get("action", "")
	var result: Dictionary = {}

	match action:
		"move":
			var champion_id: String = payload.get("champion_id", "")
			var target_pos := Vector2i(
				int(payload.get("target_x", 0)),
				int(payload.get("target_y", 0))
			)
			result = game_controller.move_champion(champion_id, target_pos)

			if result.get("success", false):
				broadcast_action("move", {
					"champion_id": champion_id,
					"target_x": target_pos.x,
					"target_y": target_pos.y,
					"path": _path_to_array(result.get("path", []))
				}, result)
				broadcast_state_sync()

		"attack":
			var attacker_id: String = payload.get("attacker_id", "")
			var target_id: String = payload.get("target_id", "")
			result = game_controller.attack_champion(attacker_id, target_id)

			if result.get("success", false) and not result.get("pending", false):
				broadcast_action("attack", {
					"attacker_id": attacker_id,
					"target_id": target_id
				}, result)
				broadcast_state_sync()

		"cast":
			var card_name: String = payload.get("card_name", "")
			var caster_id: String = payload.get("caster_id", "")
			var targets: Array = payload.get("targets", [])
			result = game_controller.cast_card(card_name, caster_id, targets)

			if result.get("success", false) and not result.get("pending", false):
				broadcast_action("cast", {
					"card_name": card_name,
					"caster_id": caster_id,
					"targets": targets
				}, result)
				broadcast_state_sync()

		"end_turn":
			result = game_controller.end_turn()
			if result.get("success", false):
				broadcast_action("end_turn", {}, result)
				# State sync happens on turn_started

	# Emit for local UI update on host
	if result.get("success", false):
		remote_action_received.emit(result)


# === Guest: Applying host results ===

func _handle_host_action_result(payload: Dictionary) -> void:
	"""Guest receives and displays the result of an action executed by host."""
	var action_type: String = payload.get("action_type", "")
	var params: Dictionary = payload.get("params", {})
	var result: Dictionary = payload.get("result", {})

	# The guest's GameController will be updated by state sync
	# We just emit the action for UI animation purposes
	match action_type:
		"move":
			var action_data := {
				"action": "move",
				"champion": params.get("champion_id", ""),
				"to": Vector2i(int(params.get("target_x", 0)), int(params.get("target_y", 0))),
				"path": _array_to_path(params.get("path", []))
			}
			remote_action_received.emit(action_data)

		"attack":
			var action_data := {
				"action": "attack",
				"attacker": params.get("attacker_id", ""),
				"target": params.get("target_id", ""),
				"damage": result.get("damage", 0)
			}
			remote_action_received.emit(action_data)

		"cast":
			var action_data := {
				"action": "cast",
				"card": params.get("card_name", ""),
				"caster": params.get("caster_id", ""),
				"targets": params.get("targets", [])
			}
			remote_action_received.emit(action_data)

		"end_turn":
			opponent_end_turn.emit()


func _handle_response_slot_update(payload: Dictionary) -> void:
	"""Apply opponent's response slot update."""
	var player_id: int = payload.get("player_id", 0)
	var card_name: String = payload.get("card_name", "")
	if game_controller and game_controller.game_state:
		if player_id == 1:
			game_controller.game_state.player1_response_slot = card_name
		else:
			game_controller.game_state.player2_response_slot = card_name


# === State Serialization ===

func _serialize_state(state: GameState) -> Dictionary:
	"""Serialize game state for network transmission."""
	var data := {
		"active_player": state.active_player,
		"round_number": state.round_number,
		"current_phase": state.current_phase,
		"game_over": state.game_over,
		"winner": state.winner,
		"p1_mana": state.player1_mana,
		"p2_mana": state.player2_mana,
		"p1_locked_mana": state.player1_locked_mana,
		"p2_locked_mana": state.player2_locked_mana,
		"p1_hand_size": state.player1_hand.size(),
		"p2_hand_size": state.player2_hand.size(),
		"p1_response_slot": state.player1_response_slot,
		"p2_response_slot": state.player2_response_slot,
		"champions": []
	}

	for champ: ChampionState in state.get_all_champions():
		data["champions"].append({
			"id": champ.unique_id,
			"name": champ.champion_name,
			"owner": champ.owner_id,
			"pos_x": champ.position.x,
			"pos_y": champ.position.y,
			"hp": champ.current_hp,
			"max_hp": champ.max_hp,
			"power": champ.current_power,
			"range": champ.current_range,
			"movement": champ.current_movement,
			"move_remaining": champ.movement_remaining,
			"has_moved": champ.has_moved,
			"has_attacked": champ.has_attacked,
			"death_processed": champ.death_processed,
			"buffs": champ.buffs.duplicate(true),
			"debuffs": champ.debuffs.duplicate(true),
			"equipment": champ.equipment.duplicate(true),
		})

	# Send the actual hand contents to the opponent (they see their own hand)
	# Guest is P2, so send P2's hand to the guest
	data["p2_hand"] = state.player2_hand.duplicate()
	data["p1_hand"] = state.player1_hand.duplicate()

	return data


func _apply_state_sync(data: Dictionary) -> void:
	"""Apply state snapshot from host to local GameController."""
	if game_controller == null or game_controller.game_state == null:
		return

	var state := game_controller.game_state

	state.active_player = data.get("active_player", state.active_player)
	state.round_number = data.get("round_number", state.round_number)
	state.current_phase = data.get("current_phase", state.current_phase)
	state.game_over = data.get("game_over", false)
	state.winner = data.get("winner", 0)
	state.player1_mana = data.get("p1_mana", state.player1_mana)
	state.player2_mana = data.get("p2_mana", state.player2_mana)
	state.player1_locked_mana = data.get("p1_locked_mana", 0)
	state.player2_locked_mana = data.get("p2_locked_mana", 0)
	state.player1_response_slot = data.get("p1_response_slot", "")
	state.player2_response_slot = data.get("p2_response_slot", "")

	# Apply hand data (guest gets their own hand from host)
	if local_player_id == 2:
		var hand: Array = data.get("p2_hand", [])
		state.player2_hand.clear()
		for card_name in hand:
			state.player2_hand.append(str(card_name))
	else:
		var hand: Array = data.get("p1_hand", [])
		state.player1_hand.clear()
		for card_name in hand:
			state.player1_hand.append(str(card_name))

	# Apply champion states
	var champion_data: Array = data.get("champions", [])
	for champ_data: Dictionary in champion_data:
		var champ_id: String = champ_data.get("id", "")
		var champ := state.get_champion(champ_id)
		if champ == null:
			continue

		champ.position = Vector2i(
			int(champ_data.get("pos_x", 0)),
			int(champ_data.get("pos_y", 0))
		)
		champ.current_hp = int(champ_data.get("hp", champ.current_hp))
		champ.max_hp = int(champ_data.get("max_hp", champ.max_hp))
		champ.current_power = int(champ_data.get("power", champ.current_power))
		champ.current_range = int(champ_data.get("range", champ.current_range))
		champ.current_movement = int(champ_data.get("movement", champ.current_movement))
		champ.movement_remaining = int(champ_data.get("move_remaining", champ.movement_remaining))
		champ.has_moved = champ_data.get("has_moved", false)
		champ.has_attacked = champ_data.get("has_attacked", false)
		champ.death_processed = champ_data.get("death_processed", false)
		champ.buffs = champ_data.get("buffs", {}).duplicate(true)
		champ.debuffs = champ_data.get("debuffs", {}).duplicate(true)
		champ.equipment = champ_data.get("equipment", {}).duplicate(true)


# === Utility ===

func _path_to_array(path) -> Array:
	"""Convert Array[Vector2i] to serializable array."""
	var result: Array = []
	if path is Array:
		for pos in path:
			if pos is Vector2i:
				result.append([pos.x, pos.y])
	return result


func _array_to_path(arr: Array) -> Array:
	"""Convert serialized array back to path."""
	var result: Array = []
	for item in arr:
		if item is Array and item.size() == 2:
			result.append(Vector2i(int(item[0]), int(item[1])))
	return result
