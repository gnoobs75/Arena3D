extends Control
## ChatPanel - Reusable chat UI with messages, text input, and emotes
## Used in both lobby and in-game contexts

signal message_sent(text: String)
signal emote_sent(emote_id: String)

const EMOTES := {
	"gg": "Good Game",
	"gl": "Good Luck",
	"wp": "Well Played",
	"think": "Thinking...",
	"oops": "Oops!",
	"wow": "Wow!",
	"thanks": "Thanks!",
	"sorry": "Sorry!"
}

const MAX_MESSAGES := 100
const BG_COLOR := Color(0.08, 0.08, 0.1, 0.95)
const BORDER_COLOR := Color(0.25, 0.25, 0.3)
const INPUT_BG := Color(0.12, 0.12, 0.15)
const EMOTE_BG := Color(0.15, 0.13, 0.2, 0.9)

var _channel: String = "lobby"
var _messages: RichTextLabel
var _input: LineEdit
var _emote_container: HBoxContainer
var _message_count: int = 0


func _ready() -> void:
	_build_ui()
	NetworkManager.chat_message_received.connect(_on_network_chat)
	NetworkManager.emote_received.connect(_on_network_emote)


func _build_ui() -> void:
	"""Build the chat panel UI."""
	# Main background
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = BG_COLOR
	bg_style.border_color = BORDER_COLOR
	bg_style.set_border_width_all(1)
	bg_style.set_corner_radius_all(6)
	bg.add_theme_stylebox_override("panel", bg_style)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	bg.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "Chat"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	vbox.add_child(header)

	# Messages area
	_messages = RichTextLabel.new()
	_messages.bbcode_enabled = true
	_messages.scroll_following = true
	_messages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_messages.add_theme_font_size_override("normal_font_size", 13)
	_messages.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(_messages)

	# Emote bar
	_emote_container = HBoxContainer.new()
	_emote_container.add_theme_constant_override("separation", 4)
	var emote_scroll := ScrollContainer.new()
	emote_scroll.custom_minimum_size.y = 30
	emote_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	emote_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	emote_scroll.add_child(_emote_container)
	vbox.add_child(emote_scroll)

	for emote_id: String in EMOTES:
		var btn := Button.new()
		btn.text = EMOTES[emote_id]
		btn.custom_minimum_size = Vector2(0, 26)
		btn.add_theme_font_size_override("font_size", 11)
		_style_emote_button(btn)
		btn.pressed.connect(_on_emote_pressed.bind(emote_id))
		_emote_container.add_child(btn)

	# Input row
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	vbox.add_child(input_row)

	_input = LineEdit.new()
	_input.placeholder_text = "Type a message..."
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size.y = 32
	_input.add_theme_font_size_override("font_size", 13)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = INPUT_BG
	input_style.border_color = BORDER_COLOR
	input_style.set_border_width_all(1)
	input_style.set_corner_radius_all(4)
	input_style.content_margin_left = 8
	input_style.content_margin_right = 8
	_input.add_theme_stylebox_override("normal", input_style)
	_input.text_submitted.connect(_on_text_submitted)
	input_row.add_child(_input)

	var send_btn := Button.new()
	send_btn.text = "Send"
	send_btn.custom_minimum_size = Vector2(60, 32)
	send_btn.add_theme_font_size_override("font_size", 13)
	_style_send_button(send_btn)
	send_btn.pressed.connect(_on_send_pressed)
	input_row.add_child(send_btn)


# === PUBLIC API ===

func set_channel(channel: String) -> void:
	"""Set the chat channel (lobby or game)."""
	_channel = channel


func add_system_message(text: String) -> void:
	"""Add a system message (gray, italic)."""
	_messages.append_text("[color=#888888][i]%s[/i][/color]\n" % _escape_bbcode(text))
	_trim_messages()


func add_chat_message(sender: String, text: String) -> void:
	"""Add a chat message from a player."""
	var sender_color := "#6ba3d6" if sender == NetworkManager.display_name else "#d6856b"
	_messages.append_text("[color=%s][b]%s:[/b][/color] %s\n" % [
		sender_color,
		_escape_bbcode(sender),
		_escape_bbcode(text)
	])
	_trim_messages()


func add_emote(sender: String, emote_id: String) -> void:
	"""Add an emote message."""
	var emote_text: String = EMOTES.get(emote_id, emote_id)
	var sender_color := "#6ba3d6" if sender == NetworkManager.display_name else "#d6856b"
	_messages.append_text("[color=%s][b]%s[/b][/color] [color=#c8b84d]%s[/color]\n" % [
		sender_color,
		_escape_bbcode(sender),
		_escape_bbcode(emote_text)
	])
	_trim_messages()


func clear_messages() -> void:
	"""Clear all messages."""
	_messages.clear()
	_message_count = 0


func focus_input() -> void:
	"""Focus the text input field."""
	if _input:
		_input.grab_focus()


# === SIGNAL HANDLERS ===

func _on_text_submitted(text: String) -> void:
	_send_message(text)


func _on_send_pressed() -> void:
	_send_message(_input.text)


func _send_message(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	NetworkManager.send_chat_message(trimmed, _channel)
	add_chat_message(NetworkManager.display_name, trimmed)
	_input.clear()
	_input.grab_focus()
	message_sent.emit(trimmed)


func _on_emote_pressed(emote_id: String) -> void:
	NetworkManager.send_emote(emote_id)
	add_emote(NetworkManager.display_name, emote_id)
	emote_sent.emit(emote_id)


func _on_network_chat(sender: String, message: String, channel: String) -> void:
	if channel == _channel and sender != NetworkManager.display_name:
		add_chat_message(sender, message)


func _on_network_emote(sender: String, emote_id: String) -> void:
	if sender != NetworkManager.display_name:
		add_emote(sender, emote_id)


# === HELPERS ===

func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


func _trim_messages() -> void:
	_message_count += 1
	# RichTextLabel doesn't have easy line removal, just clear if too many
	if _message_count > MAX_MESSAGES:
		_messages.clear()
		_message_count = 0
		add_system_message("(Chat history cleared)")


func _style_emote_button(btn: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = EMOTE_BG
	style.border_color = Color(0.3, 0.28, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = Color(0.2, 0.18, 0.28, 0.95)
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.8))


func _style_send_button(btn: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.25, 0.4, 0.9)
	style.border_color = Color(0.3, 0.5, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = Color(0.2, 0.35, 0.5, 0.95)
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
