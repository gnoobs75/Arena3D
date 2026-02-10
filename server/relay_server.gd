extends Node
## RelayServer - Standalone WebSocket relay server for Arena multiplayer
## Run headless: godot --headless --path arena_godot server/relay_server.tscn
##
## Handles:
## - WebSocket connections via TCPServer + WebSocketPeer
## - Room creation/joining with 4-char codes
## - Message relaying between room partners
## - Matchmaking queue (FIFO pairing)
## - Heartbeat monitoring (30s timeout)
## - Room listing for browser

const PORT := 8765
const HEARTBEAT_TIMEOUT := 30.0
const MAX_ROOMS := 100
const ROOM_CODE_LENGTH := 4
const MAX_MESSAGE_LENGTH := 65536
const CHAT_RATE_LIMIT := 1.0  # seconds between chat messages

# === DATA CLASSES ===

class PeerState:
	var ws: WebSocketPeer
	var stream: StreamPeerTCP
	var peer_id: int
	var display_name: String = ""
	var room_code: String = ""
	var last_heartbeat: float = 0.0
	var last_chat_time: float = 0.0
	var connected_at: float = 0.0
	var welcomed: bool = false  # Track if welcome message has been sent

	func _init(p_ws: WebSocketPeer, p_stream: StreamPeerTCP, p_id: int, p_time: float) -> void:
		ws = p_ws
		stream = p_stream
		peer_id = p_id
		last_heartbeat = p_time
		connected_at = p_time


class RoomState:
	var code: String
	var host_peer_id: int
	var guest_peer_id: int = 0
	var state: String = "waiting"  # waiting, drafting, playing, finished
	var created_at: float
	var settings: Dictionary = {}
	var host_name: String = ""
	var guest_name: String = ""
	# Reconnection
	var disconnected_peer_id: int = 0
	var disconnect_time: float = 0.0

	func _init(p_code: String, p_host_id: int, p_time: float) -> void:
		code = p_code
		host_peer_id = p_host_id
		created_at = p_time

	func is_full() -> bool:
		return guest_peer_id != 0

	func get_partner_id(my_peer_id: int) -> int:
		if my_peer_id == host_peer_id:
			return guest_peer_id
		elif my_peer_id == guest_peer_id:
			return host_peer_id
		return 0

	func has_peer(p_id: int) -> bool:
		return p_id == host_peer_id or p_id == guest_peer_id

	func remove_peer(p_id: int) -> void:
		if p_id == guest_peer_id:
			guest_peer_id = 0
			guest_name = ""
		# Don't remove host - room dies without host


# === STATE ===

var _tcp_server: TCPServer
var _peers: Dictionary = {}          # peer_id -> PeerState
var _pending_peers: Array = []       # TCPServer connections not yet upgraded to WebSocket
var _rooms: Dictionary = {}          # room_code -> RoomState
var _matchmaking_queue: Array = []   # Array of peer_ids
var _next_peer_id: int = 1
var _time: float = 0.0
var _used_codes: Dictionary = {}     # Track used room codes


func _ready() -> void:
	_tcp_server = TCPServer.new()
	var err := _tcp_server.listen(PORT)
	if err != OK:
		push_error("RelayServer: Failed to listen on port %d: %s" % [PORT, error_string(err)])
		get_tree().quit(1)
		return

	print("=== Arena Relay Server ===")
	print("Listening on port %d" % PORT)
	print("Max rooms: %d" % MAX_ROOMS)
	print("Heartbeat timeout: %ds" % int(HEARTBEAT_TIMEOUT))
	print("========================")


func _process(delta: float) -> void:
	_time += delta

	# Accept new TCP connections
	while _tcp_server.is_connection_available():
		var tcp_conn: StreamPeerTCP = _tcp_server.take_connection()
		if tcp_conn:
			var ws := WebSocketPeer.new()
			ws.accept_stream(tcp_conn)
			var p_id := _next_peer_id
			_next_peer_id += 1
			var peer := PeerState.new(ws, tcp_conn, p_id, _time)
			_peers[p_id] = peer
			# Don't send welcome yet - wait for WebSocket handshake to complete
			print("  [+] Peer %d TCP accepted (total: %d)" % [p_id, _peers.size()])

	# Poll all peers
	var to_remove: Array[int] = []
	for p_id: int in _peers:
		var peer: PeerState = _peers[p_id]
		peer.ws.poll()

		var ws_state := peer.ws.get_ready_state()
		match ws_state:
			WebSocketPeer.STATE_OPEN:
				# Send welcome once handshake completes
				if not peer.welcomed:
					peer.welcomed = true
					_send_to_peer(p_id, {
						"type": "s_welcome",
						"peer_id": p_id
					})
					print("  [+] Peer %d WebSocket ready (total: %d)" % [p_id, _peers.size()])

				# Read messages
				while peer.ws.get_available_packet_count() > 0:
					var packet := peer.ws.get_packet()
					var text := packet.get_string_from_utf8()
					if text.length() <= MAX_MESSAGE_LENGTH:
						_handle_message(p_id, text)

				# Check heartbeat timeout
				if _time - peer.last_heartbeat > HEARTBEAT_TIMEOUT:
					print("  [!] Peer %d heartbeat timeout" % p_id)
					to_remove.append(p_id)

			WebSocketPeer.STATE_CLOSED:
				to_remove.append(p_id)

	# Remove disconnected peers
	for p_id: int in to_remove:
		_on_peer_disconnected(p_id)

	# Clean up old rooms with no players (every 60 seconds)
	if int(_time) % 60 == 0 and int(_time * 10) % 10 == 0:
		_cleanup_stale_rooms()


# === MESSAGE HANDLING ===

func _handle_message(peer_id: int, text: String) -> void:
	"""Parse and route incoming message."""
	var json := JSON.new()
	if json.parse(text) != OK:
		_send_error(peer_id, "Invalid JSON")
		return

	var msg: Dictionary = json.data
	if not msg is Dictionary:
		_send_error(peer_id, "Message must be a JSON object")
		return

	var msg_type: String = msg.get("type", "")
	var peer: PeerState = _peers.get(peer_id)
	if peer == null:
		return

	# Update heartbeat on any message
	peer.last_heartbeat = _time

	match msg_type:
		"c_heartbeat":
			_send_to_peer(peer_id, {"type": "s_heartbeat_ack"})

		"c_set_name":
			peer.display_name = str(msg.get("name", "Player")).left(32)

		"c_create_room":
			_handle_create_room(peer_id, msg)

		"c_join_room":
			_handle_join_room(peer_id, msg)

		"c_leave_room":
			_handle_leave_room(peer_id)

		"c_list_rooms":
			_handle_list_rooms(peer_id)

		"c_matchmake":
			_handle_matchmake(peer_id, msg)

		"c_cancel_matchmake":
			_handle_cancel_matchmake(peer_id)

		"c_reconnect":
			_handle_reconnect(peer_id, msg)

		"c_relay":
			_handle_relay(peer_id, msg)

		_:
			_send_error(peer_id, "Unknown message type: %s" % msg_type)


# === ROOM MANAGEMENT ===

func _handle_create_room(peer_id: int, msg: Dictionary) -> void:
	"""Create a new room for the peer."""
	var peer: PeerState = _peers[peer_id]

	# Check if already in a room
	if not peer.room_code.is_empty():
		_send_error(peer_id, "Already in a room. Leave first.")
		return

	# Check room limit
	if _rooms.size() >= MAX_ROOMS:
		_send_error(peer_id, "Server is full. Try again later.")
		return

	# Generate unique room code
	var code := _generate_room_code()
	var settings: Dictionary = msg.get("settings", {})
	var name: String = str(msg.get("name", peer.display_name)).left(32)
	if not name.is_empty():
		peer.display_name = name

	# Create room
	var room := RoomState.new(code, peer_id, _time)
	room.settings = settings
	room.host_name = peer.display_name
	_rooms[code] = room
	peer.room_code = code

	print("  [R] Room %s created by peer %d (%s)" % [code, peer_id, peer.display_name])

	_send_to_peer(peer_id, {
		"type": "s_room_created",
		"code": code
	})


func _handle_join_room(peer_id: int, msg: Dictionary) -> void:
	"""Join an existing room."""
	var peer: PeerState = _peers[peer_id]
	var code: String = str(msg.get("code", "")).to_upper()
	var name: String = str(msg.get("name", peer.display_name)).left(32)
	if not name.is_empty():
		peer.display_name = name

	# Check if already in a room
	if not peer.room_code.is_empty():
		_send_error(peer_id, "Already in a room. Leave first.")
		return

	# Find room
	if not _rooms.has(code):
		_send_error(peer_id, "Room not found: %s" % code)
		return

	var room: RoomState = _rooms[code]

	# Check if full
	if room.is_full():
		_send_error(peer_id, "Room is full")
		return

	# Join as guest
	room.guest_peer_id = peer_id
	room.guest_name = peer.display_name
	peer.room_code = code

	print("  [R] Peer %d (%s) joined room %s" % [peer_id, peer.display_name, code])

	# Notify joiner
	_send_to_peer(peer_id, {
		"type": "s_room_joined",
		"code": code,
		"role": "guest",
		"opponent_name": room.host_name
	})

	# Notify host
	_send_to_peer(room.host_peer_id, {
		"type": "s_opponent_joined",
		"name": peer.display_name
	})


func _handle_leave_room(peer_id: int) -> void:
	"""Remove peer from their current room."""
	var peer: PeerState = _peers[peer_id]
	if peer.room_code.is_empty():
		return

	var room: RoomState = _rooms.get(peer.room_code)
	if room == null:
		peer.room_code = ""
		return

	var code := peer.room_code
	var partner_id := room.get_partner_id(peer_id)

	# Notify partner
	if partner_id != 0 and _peers.has(partner_id):
		_send_to_peer(partner_id, {
			"type": "s_opponent_left",
			"reason": "leave"
		})
		# Remove partner from room too
		var partner: PeerState = _peers[partner_id]
		partner.room_code = ""

	# Clean up room
	peer.room_code = ""
	_rooms.erase(code)
	_used_codes.erase(code)
	print("  [R] Room %s closed (peer %d left)" % [code, peer_id])


func _handle_list_rooms(peer_id: int) -> void:
	"""Send list of rooms waiting for players."""
	var room_list: Array = []
	for code: String in _rooms:
		var room: RoomState = _rooms[code]
		if room.state == "waiting" and not room.is_full():
			room_list.append({
				"code": code,
				"host": room.host_name,
				"state": room.state
			})

	_send_to_peer(peer_id, {
		"type": "s_room_list",
		"rooms": room_list
	})


# === MATCHMAKING ===

func _handle_matchmake(peer_id: int, msg: Dictionary) -> void:
	"""Add peer to matchmaking queue."""
	var peer: PeerState = _peers[peer_id]
	var name: String = str(msg.get("name", peer.display_name)).left(32)
	if not name.is_empty():
		peer.display_name = name

	if not peer.room_code.is_empty():
		_send_error(peer_id, "Leave your room before matchmaking")
		return

	if peer_id in _matchmaking_queue:
		_send_error(peer_id, "Already in matchmaking queue")
		return

	_matchmaking_queue.append(peer_id)
	print("  [M] Peer %d added to matchmaking (queue size: %d)" % [peer_id, _matchmaking_queue.size()])

	# Try to pair
	_try_pair_matchmaking()


func _handle_cancel_matchmake(peer_id: int) -> void:
	"""Remove peer from matchmaking queue."""
	var idx := _matchmaking_queue.find(peer_id)
	if idx >= 0:
		_matchmaking_queue.remove_at(idx)
		print("  [M] Peer %d left matchmaking (queue size: %d)" % [peer_id, _matchmaking_queue.size()])


func _try_pair_matchmaking() -> void:
	"""Try to pair two players from the queue."""
	# Clean queue of disconnected peers
	_matchmaking_queue = _matchmaking_queue.filter(func(pid: int) -> bool: return _peers.has(pid))

	while _matchmaking_queue.size() >= 2:
		var host_id: int = _matchmaking_queue.pop_front()
		var guest_id: int = _matchmaking_queue.pop_front()

		# Verify both still connected and not in rooms
		var host_peer: PeerState = _peers.get(host_id)
		var guest_peer: PeerState = _peers.get(guest_id)
		if host_peer == null or guest_peer == null:
			continue
		if not host_peer.room_code.is_empty() or not guest_peer.room_code.is_empty():
			continue

		# Create room
		var code := _generate_room_code()
		var room := RoomState.new(code, host_id, _time)
		room.guest_peer_id = guest_id
		room.host_name = host_peer.display_name
		room.guest_name = guest_peer.display_name
		_rooms[code] = room

		host_peer.room_code = code
		guest_peer.room_code = code

		print("  [M] Matched peer %d + %d -> room %s" % [host_id, guest_id, code])

		# Notify both
		_send_to_peer(host_id, {
			"type": "s_matchmake_found",
			"code": code,
			"role": "host",
			"opponent_name": guest_peer.display_name
		})
		_send_to_peer(guest_id, {
			"type": "s_matchmake_found",
			"code": code,
			"role": "guest",
			"opponent_name": host_peer.display_name
		})


# === RECONNECTION ===

func _handle_reconnect(peer_id: int, msg: Dictionary) -> void:
	"""Handle reconnection attempt."""
	var code: String = str(msg.get("room_code", "")).to_upper()
	var old_peer_id: int = msg.get("peer_id", 0)

	if not _rooms.has(code):
		_send_to_peer(peer_id, {
			"type": "s_reconnect_failed",
			"reason": "Room no longer exists"
		})
		return

	var room: RoomState = _rooms[code]

	# Check if this was the disconnected peer
	if room.disconnected_peer_id != old_peer_id:
		_send_to_peer(peer_id, {
			"type": "s_reconnect_failed",
			"reason": "Not the disconnected player"
		})
		return

	# Reconnect: replace old peer_id with new one in room
	var peer: PeerState = _peers[peer_id]
	peer.room_code = code

	if old_peer_id == room.host_peer_id:
		room.host_peer_id = peer_id
	elif old_peer_id == room.guest_peer_id:
		room.guest_peer_id = peer_id

	room.disconnected_peer_id = 0
	room.disconnect_time = 0.0

	print("  [R] Peer %d reconnected to room %s (was peer %d)" % [peer_id, code, old_peer_id])

	_send_to_peer(peer_id, {
		"type": "s_reconnect_ok"
	})

	# Notify partner
	var partner_id := room.get_partner_id(peer_id)
	if partner_id != 0 and _peers.has(partner_id):
		_send_to_peer(partner_id, {
			"type": "s_opponent_reconnected"
		})


# === MESSAGE RELAY ===

func _handle_relay(peer_id: int, msg: Dictionary) -> void:
	"""Relay a game message to the room partner."""
	var peer: PeerState = _peers[peer_id]
	if peer.room_code.is_empty():
		_send_error(peer_id, "Not in a room")
		return

	var room: RoomState = _rooms.get(peer.room_code)
	if room == null:
		_send_error(peer_id, "Room not found")
		return

	var partner_id := room.get_partner_id(peer_id)
	if partner_id == 0 or not _peers.has(partner_id):
		# No partner (or partner disconnected) - silently drop
		return

	var payload: Dictionary = msg.get("payload", {})

	# Rate-limit chat
	var payload_type: String = payload.get("type", "")
	if payload_type == "g_chat":
		if _time - peer.last_chat_time < CHAT_RATE_LIMIT:
			return  # Rate limited, drop message
		peer.last_chat_time = _time

	# Relay to partner
	_send_to_peer(partner_id, {
		"type": "s_relay",
		"payload": payload
	})


# === PEER LIFECYCLE ===

func _on_peer_disconnected(peer_id: int) -> void:
	"""Handle peer disconnection."""
	var peer: PeerState = _peers.get(peer_id)
	if peer == null:
		return

	# Remove from matchmaking
	var mm_idx := _matchmaking_queue.find(peer_id)
	if mm_idx >= 0:
		_matchmaking_queue.remove_at(mm_idx)

	# Handle room
	if not peer.room_code.is_empty():
		var room: RoomState = _rooms.get(peer.room_code)
		if room != null:
			var partner_id := room.get_partner_id(peer_id)

			if room.state == "playing":
				# Game in progress - keep room for reconnection
				room.disconnected_peer_id = peer_id
				room.disconnect_time = _time

				if partner_id != 0 and _peers.has(partner_id):
					_send_to_peer(partner_id, {
						"type": "s_opponent_reconnecting"
					})
				print("  [R] Peer %d disconnected from game room %s (waiting for reconnect)" % [peer_id, peer.room_code])
			else:
				# Not in game - close room
				if partner_id != 0 and _peers.has(partner_id):
					_send_to_peer(partner_id, {
						"type": "s_opponent_left",
						"reason": "disconnect"
					})
					var partner: PeerState = _peers[partner_id]
					partner.room_code = ""

				_rooms.erase(peer.room_code)
				_used_codes.erase(peer.room_code)
				print("  [R] Room %s closed (peer %d disconnected)" % [peer.room_code, peer_id])

	_peers.erase(peer_id)
	print("  [-] Peer %d disconnected (total: %d)" % [peer_id, _peers.size()])


func _cleanup_stale_rooms() -> void:
	"""Clean up rooms where disconnected players haven't returned."""
	var to_remove: Array[String] = []
	for code: String in _rooms:
		var room: RoomState = _rooms[code]
		# Room with disconnected player waiting > 30s
		if room.disconnected_peer_id != 0 and _time - room.disconnect_time > HEARTBEAT_TIMEOUT:
			var partner_id := room.get_partner_id(room.disconnected_peer_id)
			if partner_id != 0 and _peers.has(partner_id):
				# Notify remaining player of AI takeover
				var disconnected_player := 2 if room.disconnected_peer_id == room.guest_peer_id else 1
				_send_to_peer(partner_id, {
					"type": "s_ai_takeover",
					"player_id": disconnected_player
				})
			room.disconnected_peer_id = 0
			# Don't close room yet - let the remaining player finish with AI

		# Room waiting for > 30 minutes with no guest
		if not room.is_full() and room.state == "waiting" and _time - room.created_at > 1800:
			if room.host_peer_id != 0 and _peers.has(room.host_peer_id):
				_send_to_peer(room.host_peer_id, {
					"type": "s_room_closed",
					"reason": "Room expired (30 min)"
				})
				var host: PeerState = _peers[room.host_peer_id]
				host.room_code = ""
			to_remove.append(code)

	for code: String in to_remove:
		_rooms.erase(code)
		_used_codes.erase(code)
		print("  [R] Stale room %s cleaned up" % code)


# === UTILITIES ===

func _send_to_peer(peer_id: int, msg: Dictionary) -> void:
	"""Send a JSON message to a specific peer."""
	var peer: PeerState = _peers.get(peer_id)
	if peer == null:
		return
	if peer.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var json_str := JSON.stringify(msg)
	peer.ws.send_text(json_str)


func _send_error(peer_id: int, message: String) -> void:
	"""Send an error message to a peer."""
	_send_to_peer(peer_id, {
		"type": "s_error",
		"message": message
	})


func _generate_room_code() -> String:
	"""Generate a unique 4-character alphanumeric room code."""
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # No I/O/0/1 to avoid confusion
	var code := ""
	for attempt in range(100):
		code = ""
		for i in range(ROOM_CODE_LENGTH):
			code += CHARS[randi() % CHARS.length()]
		if not _used_codes.has(code):
			_used_codes[code] = true
			return code
	# Fallback - should never reach here with 30^4 = 810000 combinations
	return code


# === SERVER STATUS (print periodically) ===

var _status_timer: float = 0.0
const STATUS_INTERVAL := 60.0

func _physics_process(delta: float) -> void:
	_status_timer += delta
	if _status_timer >= STATUS_INTERVAL:
		_status_timer = 0.0
		print("  [S] Status: %d peers, %d rooms, %d in matchmaking" % [
			_peers.size(), _rooms.size(), _matchmaking_queue.size()
		])
