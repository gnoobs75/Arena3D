extends Control
## LobbyScene - Multiplayer lobby with room management, matchmaking, and chat
## Flow: Connect to server -> Create/Join/Browse/Matchmake -> Opponent joins -> Start game

signal game_starting(room_code: String, use_3d: bool)
signal back_to_menu()

# === CONSTANTS ===
const BG_COLOR := Color(0.06, 0.06, 0.08)
const PANEL_BG := Color(0.1, 0.1, 0.13, 0.95)
const PANEL_BORDER := Color(0.25, 0.25, 0.3)
const ACCENT := Color(0.3, 0.6, 0.9)
const ACCENT_GREEN := Color(0.3, 0.8, 0.4)
const ACCENT_RED := Color(0.8, 0.3, 0.3)
const TEXT_COLOR := Color(0.9, 0.9, 0.9)
const TEXT_DIM := Color(0.6, 0.6, 0.65)

# === STATE ===
var _opponent_name: String = ""
var _is_ready: bool = false  # Both players in room
var _room_list_timer: float = 0.0
const ROOM_LIST_REFRESH := 5.0

# === UI REFERENCES ===
var _status_label: Label
var _name_input: LineEdit
var _room_code_label: Label
var _room_code_display: Label
var _opponent_label: Label
var _start_button: Button
var _back_button: Button
var _tab_container: TabContainer
var _chat_panel: Control  # ChatPanel
var _matchmaking_button: Button
var _matchmaking_cancel_button: Button
var _matchmaking_status: Label
var _create_button: Button
var _join_input: LineEdit
var _join_button: Button
var _room_list_container: VBoxContainer
var _refresh_button: Button
var _room_status_panel: Control
var _server_url_input: LineEdit
var _connect_button: Button


func _ready() -> void:
	_build_ui()
	_connect_signals()
	# Auto-connect to server
	if not NetworkManager.is_connected_to_server():
		_set_status("Connecting to server...", ACCENT)
		NetworkManager.connect_to_server(_server_url_input.text.strip_edges())
	else:
		_set_status("Connected", ACCENT_GREEN)
		_update_ui_state()


func _process(delta: float) -> void:
	# Refresh room list periodically when on Browse tab
	if _tab_container and _tab_container.current_tab == 2:  # Browse tab
		_room_list_timer += delta
		if _room_list_timer >= ROOM_LIST_REFRESH:
			_room_list_timer = 0.0
			NetworkManager.request_room_list()


func _connect_signals() -> void:
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)
	NetworkManager.server_error.connect(_on_server_error)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.opponent_joined.connect(_on_opponent_joined)
	NetworkManager.opponent_left.connect(_on_opponent_left)
	NetworkManager.room_list_received.connect(_on_room_list)
	NetworkManager.room_closed.connect(_on_room_closed)
	NetworkManager.matchmaking_found.connect(_on_matchmaking_found)
	NetworkManager.game_start_received.connect(_on_game_start_received)


func _build_ui() -> void:
	"""Build the complete lobby UI."""
	# Full screen background
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main layout: margin container
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 30)
	margin.add_child(main_hbox)

	# LEFT SIDE: Room controls (60% width)
	var left_panel := VBoxContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 1.5
	left_panel.add_theme_constant_override("separation", 20)
	main_hbox.add_child(left_panel)

	# Title + back button row
	var title_row := HBoxContainer.new()
	left_panel.add_child(title_row)

	_back_button = Button.new()
	_back_button.text = "< Back"
	_back_button.custom_minimum_size = Vector2(80, 36)
	_back_button.add_theme_font_size_override("font_size", 14)
	_style_button_subtle(_back_button)
	_back_button.pressed.connect(_on_back_pressed)
	title_row.add_child(_back_button)

	var title := Label.new()
	title.text = "  MULTIPLAYER LOBBY"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	# Status bar
	_status_label = Label.new()
	_status_label.text = "Disconnected"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", TEXT_DIM)
	left_panel.add_child(_status_label)

	# Server URL input
	var server_row := HBoxContainer.new()
	server_row.add_theme_constant_override("separation", 10)
	left_panel.add_child(server_row)

	var server_label := Label.new()
	server_label.text = "Server:"
	server_label.add_theme_font_size_override("font_size", 16)
	server_label.add_theme_color_override("font_color", TEXT_COLOR)
	server_row.add_child(server_label)

	_server_url_input = LineEdit.new()
	_server_url_input.text = NetworkManager.server_url
	_server_url_input.placeholder_text = "ws://localhost:8765"
	_server_url_input.custom_minimum_size = Vector2(300, 36)
	_server_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server_url_input.add_theme_font_size_override("font_size", 14)
	_style_line_edit(_server_url_input)
	_server_url_input.text_submitted.connect(func(_t: String) -> void: _on_connect_pressed())
	server_row.add_child(_server_url_input)

	_connect_button = Button.new()
	_connect_button.text = "Connect"
	_connect_button.custom_minimum_size = Vector2(90, 36)
	_connect_button.add_theme_font_size_override("font_size", 14)
	_style_button_primary(_connect_button)
	_connect_button.pressed.connect(_on_connect_pressed)
	server_row.add_child(_connect_button)

	# Player name input
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	left_panel.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "Your Name:"
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	name_row.add_child(name_label)

	_name_input = LineEdit.new()
	_name_input.text = "Player"
	_name_input.max_length = 20
	_name_input.custom_minimum_size = Vector2(200, 36)
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.add_theme_font_size_override("font_size", 16)
	_style_line_edit(_name_input)
	_name_input.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_input)

	# Tab container for Create/Join/Browse/Matchmake
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.add_theme_font_size_override("font_size", 15)
	left_panel.add_child(_tab_container)

	_build_create_tab()
	_build_join_tab()
	_build_browse_tab()
	_build_matchmake_tab()

	# Room status panel (shown when in a room)
	_room_status_panel = _build_room_status_panel()
	_room_status_panel.visible = false
	left_panel.add_child(_room_status_panel)

	# RIGHT SIDE: Chat (40% width)
	var right_panel := VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	main_hbox.add_child(right_panel)

	# Load chat panel script
	var chat_script: GDScript = load("res://scenes/ui/chat_panel.gd")
	_chat_panel = Control.new()
	_chat_panel.set_script(chat_script)
	_chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_panel.set("_channel", "lobby")
	right_panel.add_child(_chat_panel)

	# Entrance animation
	_play_entrance()


func _build_create_tab() -> void:
	"""Build the Create Room tab."""
	var panel := _create_tab_panel("Create Room")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	var desc := Label.new()
	desc.text = "Create a new room and share the code with your opponent."
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	vbox.add_child(spacer)

	_create_button = Button.new()
	_create_button.text = "Create Room"
	_create_button.custom_minimum_size = Vector2(200, 50)
	_create_button.add_theme_font_size_override("font_size", 18)
	_style_button_primary(_create_button)
	_create_button.pressed.connect(_on_create_pressed)
	vbox.add_child(_create_button)


func _build_join_tab() -> void:
	"""Build the Join Room tab."""
	var panel := _create_tab_panel("Join Room")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	var desc := Label.new()
	desc.text = "Enter a room code to join an existing room."
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	vbox.add_child(join_row)

	var code_label := Label.new()
	code_label.text = "Room Code:"
	code_label.add_theme_font_size_override("font_size", 16)
	code_label.add_theme_color_override("font_color", TEXT_COLOR)
	join_row.add_child(code_label)

	_join_input = LineEdit.new()
	_join_input.placeholder_text = "ABCD"
	_join_input.max_length = 4
	_join_input.custom_minimum_size = Vector2(120, 40)
	_join_input.add_theme_font_size_override("font_size", 22)
	_join_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_line_edit(_join_input)
	_join_input.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	join_row.add_child(_join_input)

	_join_button = Button.new()
	_join_button.text = "Join"
	_join_button.custom_minimum_size = Vector2(100, 40)
	_join_button.add_theme_font_size_override("font_size", 16)
	_style_button_primary(_join_button)
	_join_button.pressed.connect(_on_join_pressed)
	join_row.add_child(_join_button)


func _build_browse_tab() -> void:
	"""Build the Browse Rooms tab."""
	var panel := _create_tab_panel("Browse")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)

	var desc := Label.new()
	desc.text = "Available Rooms"
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", TEXT_COLOR)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(desc)

	_refresh_button = Button.new()
	_refresh_button.text = "Refresh"
	_refresh_button.custom_minimum_size = Vector2(80, 30)
	_refresh_button.add_theme_font_size_override("font_size", 13)
	_style_button_subtle(_refresh_button)
	_refresh_button.pressed.connect(func() -> void: NetworkManager.request_room_list())
	header_row.add_child(_refresh_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_room_list_container = VBoxContainer.new()
	_room_list_container.add_theme_constant_override("separation", 6)
	_room_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_room_list_container)

	# Empty state
	var empty := Label.new()
	empty.name = "EmptyLabel"
	empty.text = "No rooms available. Create one or use matchmaking!"
	empty.add_theme_font_size_override("font_size", 13)
	empty.add_theme_color_override("font_color", TEXT_DIM)
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	_room_list_container.add_child(empty)


func _build_matchmake_tab() -> void:
	"""Build the Matchmaking tab."""
	var panel := _create_tab_panel("Matchmake")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	var desc := Label.new()
	desc.text = "Find a random opponent automatically."
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	vbox.add_child(spacer)

	_matchmaking_button = Button.new()
	_matchmaking_button.text = "Find Match"
	_matchmaking_button.custom_minimum_size = Vector2(200, 50)
	_matchmaking_button.add_theme_font_size_override("font_size", 18)
	_style_button_primary(_matchmaking_button)
	_matchmaking_button.pressed.connect(_on_matchmake_pressed)
	vbox.add_child(_matchmaking_button)

	_matchmaking_status = Label.new()
	_matchmaking_status.text = ""
	_matchmaking_status.add_theme_font_size_override("font_size", 14)
	_matchmaking_status.add_theme_color_override("font_color", ACCENT)
	_matchmaking_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_matchmaking_status)

	_matchmaking_cancel_button = Button.new()
	_matchmaking_cancel_button.text = "Cancel"
	_matchmaking_cancel_button.custom_minimum_size = Vector2(120, 36)
	_matchmaking_cancel_button.add_theme_font_size_override("font_size", 14)
	_matchmaking_cancel_button.visible = false
	_style_button_subtle(_matchmaking_cancel_button)
	_matchmaking_cancel_button.pressed.connect(_on_matchmake_cancel)
	vbox.add_child(_matchmaking_cancel_button)


func _build_room_status_panel() -> Control:
	"""Build the panel shown when in a room."""
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 120
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.18, 0.95)
	style.border_color = ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Room code display
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	vbox.add_child(code_row)

	_room_code_label = Label.new()
	_room_code_label.text = "Room Code:"
	_room_code_label.add_theme_font_size_override("font_size", 16)
	_room_code_label.add_theme_color_override("font_color", TEXT_DIM)
	code_row.add_child(_room_code_label)

	_room_code_display = Label.new()
	_room_code_display.text = "----"
	_room_code_display.add_theme_font_size_override("font_size", 28)
	_room_code_display.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	code_row.add_child(_room_code_display)

	var share_hint := Label.new()
	share_hint.text = "  (share this with your opponent)"
	share_hint.add_theme_font_size_override("font_size", 12)
	share_hint.add_theme_color_override("font_color", TEXT_DIM)
	share_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(share_hint)

	# Opponent status
	_opponent_label = Label.new()
	_opponent_label.text = "Waiting for opponent..."
	_opponent_label.add_theme_font_size_override("font_size", 18)
	_opponent_label.add_theme_color_override("font_color", TEXT_DIM)
	vbox.add_child(_opponent_label)

	# Button row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 15)
	vbox.add_child(btn_row)

	_start_button = Button.new()
	_start_button.text = "Start Game"
	_start_button.custom_minimum_size = Vector2(160, 45)
	_start_button.add_theme_font_size_override("font_size", 18)
	_start_button.disabled = true
	_style_button_start(_start_button)
	_start_button.pressed.connect(_on_start_pressed)
	btn_row.add_child(_start_button)

	var leave_btn := Button.new()
	leave_btn.text = "Leave Room"
	leave_btn.custom_minimum_size = Vector2(120, 45)
	leave_btn.add_theme_font_size_override("font_size", 14)
	_style_button_subtle(leave_btn)
	leave_btn.pressed.connect(_on_leave_room_pressed)
	btn_row.add_child(leave_btn)

	return panel


# === ACTIONS ===

func _on_connect_pressed() -> void:
	var url := _server_url_input.text.strip_edges()
	if url.is_empty():
		url = "ws://localhost:8765"
		_server_url_input.text = url
	if NetworkManager.is_connected_to_server():
		NetworkManager.disconnect_from_server()
		await get_tree().create_timer(0.2).timeout
	_set_status("Connecting to %s..." % url, ACCENT)
	NetworkManager.connect_to_server(url)


func _on_back_pressed() -> void:
	if NetworkManager.is_in_room():
		NetworkManager.leave_room()
	NetworkManager.disconnect_from_server()
	if UIAnimator:
		await UIAnimator.transition_fade_out(0.3)
	back_to_menu.emit()


func _on_name_changed(new_name: String) -> void:
	NetworkManager.display_name = new_name.strip_edges().left(20)
	if NetworkManager.display_name.is_empty():
		NetworkManager.display_name = "Player"


func _on_create_pressed() -> void:
	if not NetworkManager.is_connected_to_server():
		_set_status("Not connected to server", ACCENT_RED)
		return
	NetworkManager.display_name = _name_input.text.strip_edges().left(20)
	if NetworkManager.display_name.is_empty():
		NetworkManager.display_name = "Player"
	NetworkManager.create_room()


func _on_join_pressed() -> void:
	if not NetworkManager.is_connected_to_server():
		_set_status("Not connected to server", ACCENT_RED)
		return
	var code := _join_input.text.strip_edges().to_upper()
	if code.length() != 4:
		_set_status("Room code must be 4 characters", ACCENT_RED)
		return
	NetworkManager.display_name = _name_input.text.strip_edges().left(20)
	if NetworkManager.display_name.is_empty():
		NetworkManager.display_name = "Player"
	NetworkManager.join_room(code)


func _on_matchmake_pressed() -> void:
	if not NetworkManager.is_connected_to_server():
		_set_status("Not connected to server", ACCENT_RED)
		return
	NetworkManager.display_name = _name_input.text.strip_edges().left(20)
	if NetworkManager.display_name.is_empty():
		NetworkManager.display_name = "Player"
	NetworkManager.start_matchmaking()
	_matchmaking_button.visible = false
	_matchmaking_cancel_button.visible = true
	_matchmaking_status.text = "Searching for opponent..."


func _on_matchmake_cancel() -> void:
	NetworkManager.cancel_matchmaking()
	_matchmaking_button.visible = true
	_matchmaking_cancel_button.visible = false
	_matchmaking_status.text = ""


func _on_leave_room_pressed() -> void:
	NetworkManager.leave_room()
	_show_tabs()
	_set_status("Left room", TEXT_DIM)


func _on_start_pressed() -> void:
	if not _is_ready:
		return
	# Tell opponent we're starting
	NetworkManager.send_action({"type": "g_game_start"})
	NetworkManager.set_state_drafting()
	if UIAnimator:
		await UIAnimator.transition_fade_out(0.3)
	game_starting.emit(NetworkManager.room_code, false)


# === NETWORK CALLBACKS ===

func _on_connection_state_changed(_old: int, _new: int) -> void:
	_update_ui_state()


func _on_connected() -> void:
	_set_status("Connected to server", ACCENT_GREEN)
	_update_ui_state()
	if _chat_panel and _chat_panel.has_method("add_system_message"):
		_chat_panel.add_system_message("Connected to server")


func _on_disconnected(reason: String) -> void:
	_set_status("Disconnected: %s" % reason, ACCENT_RED)
	_show_tabs()
	_update_ui_state()


func _on_server_error(message: String) -> void:
	_set_status("Error: %s" % message, ACCENT_RED)
	if _chat_panel and _chat_panel.has_method("add_system_message"):
		_chat_panel.add_system_message("Error: %s" % message)


func _on_room_created(code: String) -> void:
	_show_room_status(code)
	_set_status("Room created: %s" % code, ACCENT_GREEN)
	if _chat_panel and _chat_panel.has_method("add_system_message"):
		_chat_panel.add_system_message("Room %s created. Share this code!" % code)


func _on_room_joined(code: String, _role: int) -> void:
	_show_room_status(code)
	_set_status("Joined room: %s" % code, ACCENT_GREEN)
	if _chat_panel and _chat_panel.has_method("add_system_message"):
		_chat_panel.add_system_message("Joined room %s" % code)


func _on_opponent_joined(name: String) -> void:
	_opponent_name = name
	_is_ready = true
	_opponent_label.text = "Opponent: %s" % name
	_opponent_label.add_theme_color_override("font_color", ACCENT_GREEN)
	# Only host can start
	_start_button.disabled = not NetworkManager.is_host()
	if _chat_panel and _chat_panel.has_method("add_system_message"):
		_chat_panel.add_system_message("%s has joined!" % name)


func _on_opponent_left(reason: String) -> void:
	_opponent_name = ""
	_is_ready = false
	_opponent_label.text = "Opponent left (%s). Waiting..." % reason
	_opponent_label.add_theme_color_override("font_color", ACCENT_RED)
	_start_button.disabled = true
	if _chat_panel and _chat_panel.has_method("add_system_message"):
		_chat_panel.add_system_message("Opponent left: %s" % reason)


func _on_room_list(rooms: Array) -> void:
	_update_room_list(rooms)


func _on_room_closed(reason: String) -> void:
	_show_tabs()
	_set_status("Room closed: %s" % reason, ACCENT_RED)
	_is_ready = false


func _on_game_start_received() -> void:
	"""Guest received game start from host - transition to draft."""
	NetworkManager.set_state_drafting()
	if UIAnimator:
		await UIAnimator.transition_fade_out(0.3)
	game_starting.emit(NetworkManager.room_code, false)


func _on_matchmaking_found(code: String) -> void:
	_matchmaking_button.visible = true
	_matchmaking_cancel_button.visible = false
	_matchmaking_status.text = "Match found!"
	_show_room_status(code)
	_set_status("Match found! Room: %s" % code, ACCENT_GREEN)


# === UI HELPERS ===

func _set_status(text: String, color: Color = TEXT_DIM) -> void:
	if _status_label:
		_status_label.text = text
		_status_label.add_theme_color_override("font_color", color)


func _show_room_status(code: String) -> void:
	"""Show the room status panel and hide tabs."""
	_tab_container.visible = false
	_room_status_panel.visible = true
	_room_code_display.text = code
	_opponent_label.text = "Waiting for opponent..."
	_opponent_label.add_theme_color_override("font_color", TEXT_DIM)
	_start_button.disabled = true
	_is_ready = false


func _show_tabs() -> void:
	"""Show tabs and hide room status."""
	_tab_container.visible = true
	_room_status_panel.visible = false
	_is_ready = false


func _update_ui_state() -> void:
	"""Update UI based on connection state."""
	var connected := NetworkManager.is_connected_to_server()
	if _create_button:
		_create_button.disabled = not connected
	if _join_button:
		_join_button.disabled = not connected
	if _matchmaking_button:
		_matchmaking_button.disabled = not connected
	if _connect_button:
		_connect_button.text = "Reconnect" if connected else "Connect"
	if _server_url_input:
		_server_url_input.editable = not NetworkManager.is_in_room()


func _update_room_list(rooms: Array) -> void:
	"""Rebuild the room list display."""
	# Clear existing entries
	for child in _room_list_container.get_children():
		child.queue_free()

	if rooms.is_empty():
		var empty := Label.new()
		empty.text = "No rooms available. Create one or use matchmaking!"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", TEXT_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		_room_list_container.add_child(empty)
		return

	for room_data: Dictionary in rooms:
		var entry := _create_room_list_entry(room_data)
		_room_list_container.add_child(entry)


func _create_room_list_entry(room_data: Dictionary) -> Control:
	"""Create a single room list entry."""
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.custom_minimum_size.y = 40

	var bg := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.8)
	style.border_color = Color(0.2, 0.2, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	bg.add_theme_stylebox_override("panel", style)

	bg.add_child(hbox)

	var code_label := Label.new()
	code_label.text = room_data.get("code", "????")
	code_label.add_theme_font_size_override("font_size", 18)
	code_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	code_label.custom_minimum_size.x = 80
	hbox.add_child(code_label)

	var host_label := Label.new()
	host_label.text = "Host: %s" % room_data.get("host", "Unknown")
	host_label.add_theme_font_size_override("font_size", 14)
	host_label.add_theme_color_override("font_color", TEXT_COLOR)
	host_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(host_label)

	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.custom_minimum_size = Vector2(70, 30)
	join_btn.add_theme_font_size_override("font_size", 13)
	_style_button_primary(join_btn)
	var code: String = room_data.get("code", "")
	join_btn.pressed.connect(func() -> void: NetworkManager.join_room(code))
	hbox.add_child(join_btn)

	return bg


func _create_tab_panel(tab_name: String) -> Control:
	"""Create a styled panel for a tab."""
	var margin := MarginContainer.new()
	margin.name = tab_name
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	_tab_container.add_child(margin)
	return margin


func _play_entrance() -> void:
	"""Fade in animation."""
	if UIAnimator:
		UIAnimator.transition_fade_in(0.4)


# === BUTTON STYLES ===

func _style_button_primary(btn: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.3, 0.5, 0.9)
	style.border_color = ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = Color(0.2, 0.4, 0.6, 0.95)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := style.duplicate()
	pressed.bg_color = Color(0.1, 0.2, 0.35, 0.95)
	btn.add_theme_stylebox_override("pressed", pressed)

	var disabled := style.duplicate()
	disabled.bg_color = Color(0.12, 0.12, 0.15, 0.6)
	disabled.border_color = Color(0.2, 0.2, 0.25)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.45))


func _style_button_start(btn: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.4, 0.2, 0.9)
	style.border_color = ACCENT_GREEN
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = Color(0.2, 0.5, 0.3, 0.95)
	btn.add_theme_stylebox_override("hover", hover)

	var disabled := style.duplicate()
	disabled.bg_color = Color(0.1, 0.12, 0.1, 0.6)
	disabled.border_color = Color(0.2, 0.25, 0.2)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.4, 0.35))


func _style_button_subtle(btn: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.7)
	style.border_color = Color(0.25, 0.25, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = Color(0.18, 0.18, 0.22, 0.8)
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_color_override("font_color", TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", TEXT_COLOR)


func _style_line_edit(input: LineEdit) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15)
	style.border_color = PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	input.add_theme_stylebox_override("normal", style)

	var focus := style.duplicate()
	focus.border_color = ACCENT
	input.add_theme_stylebox_override("focus", focus)

	input.add_theme_color_override("font_color", TEXT_COLOR)
	input.add_theme_color_override("font_placeholder_color", TEXT_DIM)
