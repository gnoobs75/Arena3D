extends Node
## Quick connectivity test - connects to relay server and tests basic operations
## Run: godot --headless res://server/test_connectivity.tscn

var _test_phase: int = 0
var _timer: float = 0.0
var _passed: int = 0
var _failed: int = 0
var _tests_done: bool = false


func _ready() -> void:
	print("")
	print("=== Connectivity Test ===")
	print("")

	# Connect signals
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.server_error.connect(_on_error)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)

	# Test 1: Connect to server
	print("Test 1: Connecting to relay server...")
	NetworkManager.connect_to_server("ws://localhost:8765")


func _process(delta: float) -> void:
	if _tests_done:
		return

	_timer += delta

	# Timeout after 10 seconds
	if _timer > 10.0:
		print("")
		print("TIMEOUT - Server may not be running")
		print("Start the server first: run_server.bat")
		_finish()


func _on_connected() -> void:
	_pass("Connected to server (peer_id=%d)" % NetworkManager.peer_id)

	# Test 2: Create room
	print("Test 2: Creating room...")
	NetworkManager.display_name = "TestPlayer"
	NetworkManager.create_room({"test": true})


func _on_room_created(code: String) -> void:
	_pass("Room created: %s" % code)
	_pass("Player role: %s" % ("HOST" if NetworkManager.is_host() else "GUEST"))
	_pass("Local player ID: %d" % NetworkManager.local_player_id)
	_pass("Connection state: %d" % NetworkManager.connection_state)

	# Test 3: Request room list
	print("Test 6: Requesting room list...")
	NetworkManager.room_list_received.connect(_on_room_list)
	NetworkManager.request_room_list()


func _on_room_list(rooms: Array) -> void:
	_pass("Room list received: %d rooms" % rooms.size())
	if rooms.size() > 0:
		var room: Dictionary = rooms[0]
		_pass("  Room: %s (host: %s, state: %s)" % [room.get("code", "?"), room.get("host", "?"), room.get("state", "?")])

	# Test 4: Leave room
	print("Test 8: Leaving room...")
	NetworkManager.leave_room()
	if NetworkManager.room_code.is_empty():
		_pass("Room left successfully")
	else:
		_fail("Still in room after leaving")

	# Test 5: Disconnect
	print("Test 9: Disconnecting...")
	NetworkManager.disconnect_from_server()


func _on_disconnected(reason: String) -> void:
	_pass("Disconnected: %s" % reason)
	_finish()


func _on_error(message: String) -> void:
	_fail("Server error: %s" % message)


func _pass(msg: String) -> void:
	_passed += 1
	print("  PASS [%d]: %s" % [_passed, msg])


func _fail(msg: String) -> void:
	_failed += 1
	print("  FAIL [%d]: %s" % [_failed, msg])


func _finish() -> void:
	_tests_done = true
	print("")
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	print("")

	# Wait a frame then quit
	await get_tree().process_frame
	get_tree().quit(1 if _failed > 0 else 0)
