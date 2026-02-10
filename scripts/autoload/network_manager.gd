extends Node
## NetworkManager - Client-side networking autoload
## Manages WebSocket connection to relay server, room lifecycle, and message protocol

# === CONNECTION STATE ===
enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,       # Connected to relay, not in room
	IN_LOBBY,        # In a room, waiting for opponent
	DRAFTING,        # Character select phase
	IN_GAME,         # Game in progress
	RECONNECTING     # Attempting reconnect
}

enum PlayerRole { NONE, HOST, GUEST }

# Connection
var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var player_role: PlayerRole = PlayerRole.NONE
var local_player_id: int = 0  # 1 for host, 2 for guest
var display_name: String = "Player"
var room_code: String = ""
var peer_id: int = 0  # Assigned by server

# Server URL
var server_url: String = "ws://localhost:8765"

# WebSocket
var _ws: WebSocketPeer = null

# Reconnection
var _reconnect_attempts: int = 0
var _reconnect_timer: float = 0.0
var _should_reconnect: bool = false
var _last_room_code: String = ""
var _last_peer_id: int = 0
const MAX_RECONNECT_ATTEMPTS := 6
const RECONNECT_INTERVAL := 5.0

# Heartbeat
var _heartbeat_timer: float = 0.0
const HEARTBEAT_INTERVAL := 10.0

# Message sequence (for ordering)
var _send_seq: int = 0

# === SIGNALS ===

# Connection
signal connection_state_changed(old_state: ConnectionState, new_state: ConnectionState)
signal connected_to_server()
signal disconnected_from_server(reason: String)
signal server_error(message: String)

# Room
signal room_created(room_code: String)
signal room_joined(room_code: String, role: PlayerRole)
signal opponent_joined(opponent_name: String)
signal opponent_left(reason: String)
signal room_list_received(rooms: Array)
signal room_closed(reason: String)

# Matchmaking
signal matchmaking_started()
signal matchmaking_found(room_code: String)
signal matchmaking_cancelled()

# Draft
signal game_start_received()
signal draft_pick_received(player_id: int, champion_name: String)
signal draft_complete(p1_champions: Array, p2_champions: Array)

# Game
signal action_received(action: Dictionary)
signal state_sync_received(state: Dictionary)
signal game_over_received(winner: int, reason: String)
signal response_window_received(trigger: String, context: Dictionary, priority_player: int)
signal input_required(input_type: String, context: Dictionary)
signal turn_started_received(player_id: int, round_number: int)

# Chat
signal chat_message_received(sender: String, message: String, channel: String)
signal emote_received(sender: String, emote_id: String)

# Reconnection
signal reconnect_started()
signal reconnect_succeeded()
signal reconnect_failed()
signal opponent_reconnecting()
signal opponent_reconnected()
signal ai_takeover_started(player_id: int)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep processing even when paused


func _process(delta: float) -> void:
	if _ws == null:
		if _should_reconnect:
			_handle_reconnect_timer(delta)
		return

	_ws.poll()

	var state := _ws.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			# Handle heartbeat
			_heartbeat_timer += delta
			if _heartbeat_timer >= HEARTBEAT_INTERVAL:
				_heartbeat_timer = 0.0
				_send_message({"type": "c_heartbeat"})

			# Read all available messages
			while _ws.get_available_packet_count() > 0:
				var packet := _ws.get_packet()
				var text := packet.get_string_from_utf8()
				_on_message_received(text)

		WebSocketPeer.STATE_CONNECTING:
			pass  # Still connecting

		WebSocketPeer.STATE_CLOSING:
			pass  # Closing

		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			var reason := _ws.get_close_reason()
			_ws = null
			if connection_state != ConnectionState.DISCONNECTED:
				print("NetworkManager: WebSocket closed (code=%d, reason=%s)" % [code, reason])
				if connection_state == ConnectionState.IN_GAME:
					# Unexpected disconnect during game - try reconnect
					_should_reconnect = true
					_last_room_code = room_code
					_last_peer_id = peer_id
					_reconnect_attempts = 0
					_change_state(ConnectionState.RECONNECTING)
					reconnect_started.emit()
				else:
					_change_state(ConnectionState.DISCONNECTED)
					disconnected_from_server.emit(reason if reason else "Connection closed")


# === PUBLIC API: Connection ===

func connect_to_server(url: String = "") -> void:
	"""Connect to the relay server."""
	if url:
		server_url = url

	if connection_state != ConnectionState.DISCONNECTED and connection_state != ConnectionState.RECONNECTING:
		push_warning("NetworkManager: Already connected or connecting")
		return

	print("NetworkManager: Connecting to %s..." % server_url)
	_change_state(ConnectionState.CONNECTING)

	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(server_url)
	if err != OK:
		push_error("NetworkManager: Failed to connect: %s" % error_string(err))
		_ws = null
		_change_state(ConnectionState.DISCONNECTED)
		server_error.emit("Failed to connect to server")


func disconnect_from_server() -> void:
	"""Disconnect from the relay server."""
	_should_reconnect = false
	if _ws != null:
		_ws.close(1000, "Client disconnect")
		# Don't null _ws here - let _process handle the CLOSED state
		# to avoid race conditions with _process polling
	room_code = ""
	peer_id = 0
	player_role = PlayerRole.NONE
	local_player_id = 0
	_change_state(ConnectionState.DISCONNECTED)
	disconnected_from_server.emit("Client disconnected")


func is_connected_to_server() -> bool:
	return connection_state != ConnectionState.DISCONNECTED and connection_state != ConnectionState.CONNECTING


# === PUBLIC API: Room Management ===

func create_room(settings: Dictionary = {}) -> void:
	"""Create a new room on the server."""
	if not is_connected_to_server():
		push_warning("NetworkManager: Not connected")
		return
	_send_message({
		"type": "c_create_room",
		"settings": settings,
		"name": display_name
	})


func join_room(code: String) -> void:
	"""Join an existing room by code."""
	if not is_connected_to_server():
		push_warning("NetworkManager: Not connected")
		return
	_send_message({
		"type": "c_join_room",
		"code": code.to_upper(),
		"name": display_name
	})


func leave_room() -> void:
	"""Leave the current room."""
	if room_code.is_empty():
		return
	_send_message({"type": "c_leave_room"})
	room_code = ""
	player_role = PlayerRole.NONE
	local_player_id = 0
	_change_state(ConnectionState.CONNECTED)


func request_room_list() -> void:
	"""Request list of available rooms."""
	if not is_connected_to_server():
		return
	_send_message({"type": "c_list_rooms"})


# === PUBLIC API: Matchmaking ===

func start_matchmaking() -> void:
	"""Enter the matchmaking queue."""
	if not is_connected_to_server():
		return
	_send_message({"type": "c_matchmake", "name": display_name})
	matchmaking_started.emit()


func cancel_matchmaking() -> void:
	"""Leave the matchmaking queue."""
	if not is_connected_to_server():
		return
	_send_message({"type": "c_cancel_matchmake"})
	matchmaking_cancelled.emit()


# === PUBLIC API: Draft ===

func send_draft_pick(champion_name: String) -> void:
	"""Send a champion draft pick to opponent."""
	_send_game_message({
		"type": "g_draft_pick",
		"player_id": local_player_id,
		"champion": champion_name
	})


func send_draft_complete(p1_champions: Array, p2_champions: Array) -> void:
	"""Signal that the draft is complete."""
	_send_game_message({
		"type": "g_draft_complete",
		"p1_champions": p1_champions,
		"p2_champions": p2_champions
	})


# === PUBLIC API: Game Actions ===

func send_action(action_data: Dictionary) -> void:
	"""Send a game action (request from guest, or result from host)."""
	_send_game_message(action_data)


func send_state_sync(state: Dictionary) -> void:
	"""Send state synchronization data (host -> guest)."""
	_send_game_message({
		"type": "g_state_sync",
		"state": state
	})


func send_game_over(winner: int, reason: String) -> void:
	"""Send game over notification."""
	_send_game_message({
		"type": "g_game_over",
		"winner": winner,
		"reason": reason
	})


# === PUBLIC API: Chat ===

func send_chat_message(message: String, channel: String = "lobby") -> void:
	"""Send a chat message."""
	var trimmed := message.strip_edges().left(256)  # Limit to 256 chars
	if trimmed.is_empty():
		return
	_send_game_message({
		"type": "g_chat",
		"sender": display_name,
		"message": trimmed,
		"channel": channel
	})


func send_emote(emote_id: String) -> void:
	"""Send an emote."""
	_send_game_message({
		"type": "g_emote",
		"sender": display_name,
		"emote_id": emote_id
	})


# === INTERNAL: Message Handling ===

func _send_message(msg: Dictionary) -> void:
	"""Send a JSON message to the server."""
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	msg["seq"] = _send_seq
	_send_seq += 1
	var json_str := JSON.stringify(msg)
	_ws.send_text(json_str)


func _send_game_message(msg: Dictionary) -> void:
	"""Send a game message (relayed through server to opponent)."""
	_send_message({
		"type": "c_relay",
		"payload": msg
	})


func _on_message_received(text: String) -> void:
	"""Handle incoming JSON message from server."""
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_warning("NetworkManager: Failed to parse message: %s" % text.left(100))
		return

	var msg: Dictionary = json.data
	if not msg is Dictionary:
		return

	var msg_type: String = msg.get("type", "")
	_handle_message(msg_type, msg)


func _handle_message(msg_type: String, msg: Dictionary) -> void:
	"""Route message to appropriate handler."""
	match msg_type:
		# Connection
		"s_welcome":
			_on_welcome(msg)
		"s_error":
			_on_server_error(msg)
		"s_heartbeat_ack":
			pass  # Heartbeat acknowledged

		# Room
		"s_room_created":
			_on_room_created(msg)
		"s_room_joined":
			_on_room_joined(msg)
		"s_opponent_joined":
			_on_opponent_joined(msg)
		"s_opponent_left":
			_on_opponent_left(msg)
		"s_room_list":
			_on_room_list(msg)
		"s_room_closed":
			_on_room_closed(msg)

		# Matchmaking
		"s_matchmake_found":
			_on_matchmake_found(msg)

		# Reconnection
		"s_reconnect_ok":
			_on_reconnect_ok(msg)
		"s_reconnect_failed":
			_on_reconnect_failed(msg)
		"s_opponent_reconnecting":
			opponent_reconnecting.emit()
		"s_opponent_reconnected":
			opponent_reconnected.emit()
		"s_ai_takeover":
			ai_takeover_started.emit(msg.get("player_id", 0))

		# Relayed game messages
		"s_relay":
			_on_relay_message(msg.get("payload", {}))

		_:
			print("NetworkManager: Unknown message type: %s" % msg_type)


func _on_welcome(msg: Dictionary) -> void:
	"""Handle server welcome after connection."""
	peer_id = msg.get("peer_id", 0)
	print("NetworkManager: Connected! Peer ID: %d" % peer_id)
	_heartbeat_timer = 0.0
	_change_state(ConnectionState.CONNECTED)
	connected_to_server.emit()


func _on_server_error(msg: Dictionary) -> void:
	"""Handle server error message."""
	var error_msg: String = msg.get("message", "Unknown error")
	print("NetworkManager: Server error: %s" % error_msg)
	server_error.emit(error_msg)


func _on_room_created(msg: Dictionary) -> void:
	"""Handle room creation confirmation."""
	room_code = msg.get("code", "")
	player_role = PlayerRole.HOST
	local_player_id = 1
	print("NetworkManager: Room created: %s (role=HOST)" % room_code)
	_change_state(ConnectionState.IN_LOBBY)
	room_created.emit(room_code)
	room_joined.emit(room_code, player_role)


func _on_room_joined(msg: Dictionary) -> void:
	"""Handle joining an existing room."""
	room_code = msg.get("code", "")
	var role_str: String = msg.get("role", "guest")
	if role_str == "host":
		player_role = PlayerRole.HOST
		local_player_id = 1
	else:
		player_role = PlayerRole.GUEST
		local_player_id = 2
	var opponent_name: String = msg.get("opponent_name", "")
	print("NetworkManager: Joined room %s (role=%s)" % [room_code, role_str.to_upper()])
	_change_state(ConnectionState.IN_LOBBY)
	room_joined.emit(room_code, player_role)
	if not opponent_name.is_empty():
		opponent_joined.emit(opponent_name)


func _on_opponent_joined(msg: Dictionary) -> void:
	"""Handle opponent joining our room."""
	var name: String = msg.get("name", "Opponent")
	print("NetworkManager: Opponent joined: %s" % name)
	opponent_joined.emit(name)


func _on_opponent_left(msg: Dictionary) -> void:
	"""Handle opponent leaving or disconnecting."""
	var reason: String = msg.get("reason", "unknown")
	print("NetworkManager: Opponent left: %s" % reason)
	opponent_left.emit(reason)


func _on_room_list(msg: Dictionary) -> void:
	"""Handle room list response."""
	var rooms: Array = msg.get("rooms", [])
	room_list_received.emit(rooms)


func _on_room_closed(msg: Dictionary) -> void:
	"""Handle room being closed by server."""
	var reason: String = msg.get("reason", "Room closed")
	print("NetworkManager: Room closed: %s" % reason)
	room_code = ""
	player_role = PlayerRole.NONE
	local_player_id = 0
	_change_state(ConnectionState.CONNECTED)
	room_closed.emit(reason)


func _on_matchmake_found(msg: Dictionary) -> void:
	"""Handle matchmaking finding an opponent."""
	room_code = msg.get("code", "")
	var role_str: String = msg.get("role", "guest")
	if role_str == "host":
		player_role = PlayerRole.HOST
		local_player_id = 1
	else:
		player_role = PlayerRole.GUEST
		local_player_id = 2
	print("NetworkManager: Match found! Room: %s, Role: %s" % [room_code, role_str.to_upper()])
	_change_state(ConnectionState.IN_LOBBY)
	matchmaking_found.emit(room_code)
	room_joined.emit(room_code, player_role)


func _on_relay_message(payload: Dictionary) -> void:
	"""Handle relayed game message from opponent."""
	var payload_type: String = payload.get("type", "")

	match payload_type:
		# Game start (host tells guest to begin draft)
		"g_game_start":
			game_start_received.emit()

		# Draft
		"g_draft_pick":
			draft_pick_received.emit(
				payload.get("player_id", 0),
				payload.get("champion", "")
			)
		"g_draft_complete":
			draft_complete.emit(
				payload.get("p1_champions", []),
				payload.get("p2_champions", [])
			)

		# Game actions
		"g_action_request", "g_action_result":
			action_received.emit(payload)
		"g_state_sync":
			state_sync_received.emit(payload.get("state", {}))
		"g_full_state":
			state_sync_received.emit(payload.get("state", {}))
		"g_game_over":
			game_over_received.emit(
				payload.get("winner", 0),
				payload.get("reason", "")
			)
		"g_turn_started":
			turn_started_received.emit(
				payload.get("player_id", 0),
				payload.get("round_number", 0)
			)
		"g_response_window":
			response_window_received.emit(
				payload.get("trigger", ""),
				payload.get("context", {}),
				payload.get("priority_player", 0)
			)
		"g_input_required":
			input_required.emit(
				payload.get("input_type", ""),
				payload.get("context", {})
			)

		# Chat
		"g_chat":
			chat_message_received.emit(
				payload.get("sender", ""),
				payload.get("message", ""),
				payload.get("channel", "game")
			)
		"g_emote":
			emote_received.emit(
				payload.get("sender", ""),
				payload.get("emote_id", "")
			)

		_:
			print("NetworkManager: Unknown relay message: %s" % payload_type)


# === INTERNAL: Reconnection ===

func _handle_reconnect_timer(delta: float) -> void:
	"""Handle reconnection attempts."""
	_reconnect_timer += delta
	if _reconnect_timer >= RECONNECT_INTERVAL:
		_reconnect_timer = 0.0
		_reconnect_attempts += 1
		if _reconnect_attempts > MAX_RECONNECT_ATTEMPTS:
			print("NetworkManager: Max reconnect attempts reached")
			_should_reconnect = false
			_change_state(ConnectionState.DISCONNECTED)
			reconnect_failed.emit()
			return

		print("NetworkManager: Reconnect attempt %d/%d..." % [_reconnect_attempts, MAX_RECONNECT_ATTEMPTS])
		_ws = WebSocketPeer.new()
		var err := _ws.connect_to_url(server_url)
		if err != OK:
			_ws = null
			return

		# Wait for connection to establish, then send reconnect message
		# The _process loop will handle the state change to OPEN
		# and we'll send the reconnect message in _on_welcome


func _on_reconnect_ok(msg: Dictionary) -> void:
	"""Handle successful reconnection."""
	print("NetworkManager: Reconnected successfully!")
	_should_reconnect = false
	_reconnect_attempts = 0
	room_code = _last_room_code
	_change_state(ConnectionState.IN_GAME)
	reconnect_succeeded.emit()
	# Server will also send full state
	var full_state: Dictionary = msg.get("full_state", {})
	if not full_state.is_empty():
		state_sync_received.emit(full_state)


func _on_reconnect_failed(msg: Dictionary) -> void:
	"""Handle failed reconnection."""
	var reason: String = msg.get("reason", "Unknown")
	print("NetworkManager: Reconnect failed: %s" % reason)
	_should_reconnect = false
	_change_state(ConnectionState.CONNECTED)
	reconnect_failed.emit()


# === INTERNAL: State Management ===

func _change_state(new_state: ConnectionState) -> void:
	"""Change connection state and emit signal."""
	if new_state == connection_state:
		return
	var old_state := connection_state
	connection_state = new_state
	print("NetworkManager: State %s -> %s" % [
		ConnectionState.keys()[old_state],
		ConnectionState.keys()[new_state]
	])
	connection_state_changed.emit(old_state, new_state)


# === PUBLIC: State Transitions ===

func set_state_drafting() -> void:
	"""Transition to drafting state (called when entering character select)."""
	if connection_state == ConnectionState.IN_LOBBY:
		_change_state(ConnectionState.DRAFTING)


func set_state_in_game() -> void:
	"""Transition to in-game state (called when game starts)."""
	if connection_state == ConnectionState.DRAFTING or connection_state == ConnectionState.IN_LOBBY:
		_change_state(ConnectionState.IN_GAME)


# === PUBLIC: Utility ===

func get_opponent_player_id() -> int:
	"""Get the opponent's player ID."""
	return 2 if local_player_id == 1 else 1


func is_host() -> bool:
	"""Check if local player is the host."""
	return player_role == PlayerRole.HOST


func is_in_room() -> bool:
	"""Check if currently in a room."""
	return not room_code.is_empty()


func is_multiplayer_game() -> bool:
	"""Check if currently in a multiplayer game."""
	return connection_state == ConnectionState.IN_GAME
