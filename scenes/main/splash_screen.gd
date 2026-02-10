extends Control
class_name SplashScreen
## SplashScreen - Title screen with 2D/3D/Developer mode selection
## Features entrance animations and polished button effects

signal mode_selected(use_3d: bool)
signal developer_mode_selected()
signal multiplayer_selected()

@onready var background: TextureRect = $Background
@onready var button_2d: Button = $ButtonContainer/Button2D
@onready var button_3d: Button = $ButtonContainer/Button3D
@onready var button_mp: Button = $ButtonContainer/ButtonMP
@onready var button_dev: Button = $ButtonContainer/ButtonDev
@onready var button_host: Button = $ButtonContainer/ButtonHost
@onready var title_label: Label = $TitleLabel

var _buttons_ready: bool = false

# Host panel state
var _host_panel: PanelContainer = null
var _relay_pid: int = -1
var _web_pid: int = -1
var _relay_status_label: Label = null
var _web_status_label: Label = null
var _relay_url_label: Label = null
var _web_url_label: Label = null
var _share_url_label: Label = null
var _relay_button: Button = null
var _web_button: Button = null
var _copy_button: Button = null
var _ip_label: Label = null
var _web_error_label: Label = null


func _ready() -> void:
	# Load splash background
	var splash_texture: Texture2D = load("res://assets/art/Splash.png")
	if splash_texture:
		background.texture = splash_texture

	# Connect buttons
	button_2d.pressed.connect(_on_2d_pressed)
	button_3d.pressed.connect(_on_3d_pressed)
	button_mp.pressed.connect(_on_mp_pressed)
	button_dev.pressed.connect(_on_dev_pressed)
	button_host.pressed.connect(_on_host_pressed)

	# Style the buttons
	_style_button(button_2d, Color(0.15, 0.2, 0.15), Color(0.4, 0.7, 0.4))
	_style_button(button_3d, Color(0.15, 0.12, 0.25), Color(0.5, 0.4, 0.7))
	_style_button(button_mp, Color(0.12, 0.18, 0.25), Color(0.3, 0.6, 0.9))
	_style_button(button_dev, Color(0.25, 0.18, 0.12), Color(0.8, 0.55, 0.3))
	_style_button(button_host, Color(0.1, 0.2, 0.22), Color(0.3, 0.8, 0.8))

	# Connect hover effects
	for btn in [button_2d, button_3d, button_mp, button_dev, button_host]:
		btn.mouse_entered.connect(_on_button_hover.bind(btn))
		btn.mouse_exited.connect(_on_button_unhover.bind(btn))

	# Play entrance animations
	_play_entrance_animations()


func _play_entrance_animations() -> void:
	# Title fades in from above
	if title_label:
		title_label.modulate.a = 0.0
		var title_offset := title_label.position.y
		title_label.position.y -= 40
		var tween := create_tween()
		tween.tween_property(title_label, "position:y", title_offset, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.parallel().tween_property(title_label, "modulate:a", 1.0, 0.4)

	# Background fades in
	if background:
		background.modulate.a = 0.0
		var bg_tween := create_tween()
		bg_tween.tween_property(background, "modulate:a", 1.0, 0.8).set_ease(Tween.EASE_OUT)

	# Buttons slide in from below with stagger
	var buttons := [button_2d, button_3d, button_mp, button_dev, button_host]
	for i in range(buttons.size()):
		var btn: Button = buttons[i]
		if btn == null:
			continue
		btn.modulate.a = 0.0
		btn.pivot_offset = btn.size / 2
		btn.scale = Vector2(0.8, 0.8)
		var delay := 0.3 + i * 0.12
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_property(btn, "modulate:a", 1.0, 0.35).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(btn, "scale", Vector2.ONE, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	_buttons_ready = true


func _on_button_hover(button: Button) -> void:
	if not _buttons_ready:
		return
	button.pivot_offset = button.size / 2
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.06, 1.06), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _on_button_unhover(button: Button) -> void:
	if not _buttons_ready:
		return
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_IN_OUT)


func _style_button(button: Button, bg_color: Color, border_color: Color) -> void:
	var style_normal: StyleBoxFlat = StyleBoxFlat.new()
	style_normal.bg_color = Color(bg_color.r, bg_color.g, bg_color.b, 0.9)
	style_normal.border_color = border_color
	style_normal.set_border_width_all(3)
	style_normal.set_corner_radius_all(8)
	style_normal.shadow_color = Color(0, 0, 0, 0.4)
	style_normal.shadow_size = 6
	style_normal.shadow_offset = Vector2(2, 3)

	var style_hover: StyleBoxFlat = StyleBoxFlat.new()
	style_hover.bg_color = Color(bg_color.r + 0.1, bg_color.g + 0.1, bg_color.b + 0.1, 0.95)
	style_hover.border_color = Color(border_color.r + 0.2, border_color.g + 0.2, border_color.b + 0.2)
	style_hover.set_border_width_all(3)
	style_hover.set_corner_radius_all(8)
	style_hover.shadow_color = Color(0, 0, 0, 0.5)
	style_hover.shadow_size = 8
	style_hover.shadow_offset = Vector2(3, 4)

	var style_pressed: StyleBoxFlat = StyleBoxFlat.new()
	style_pressed.bg_color = Color(bg_color.r - 0.05, bg_color.g - 0.05, bg_color.b - 0.05, 0.95)
	style_pressed.border_color = Color(border_color.r - 0.2, border_color.g - 0.2, border_color.b - 0.2)
	style_pressed.set_border_width_all(3)
	style_pressed.set_corner_radius_all(8)
	style_pressed.shadow_color = Color(0, 0, 0, 0.2)
	style_pressed.shadow_size = 2
	style_pressed.shadow_offset = Vector2(1, 1)

	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)

	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.9))


func _on_2d_pressed() -> void:
	if UIAnimator:
		await UIAnimator.transition_fade_out(0.3)
	mode_selected.emit(false)


func _on_3d_pressed() -> void:
	if UIAnimator:
		await UIAnimator.transition_fade_out(0.3)
	mode_selected.emit(true)


func _on_mp_pressed() -> void:
	if UIAnimator:
		await UIAnimator.transition_fade_out(0.3)
	multiplayer_selected.emit()


func _on_dev_pressed() -> void:
	if UIAnimator:
		await UIAnimator.transition_fade_out(0.3)
	developer_mode_selected.emit()


# ── Host for Friends Panel ──────────────────────────────────────────────

func _on_host_pressed() -> void:
	if _host_panel and _host_panel.visible:
		_host_panel.visible = false
		return
	if not _host_panel:
		_build_host_panel()
	_host_panel.visible = true


func _process(_delta: float) -> void:
	if _host_panel == null or not _host_panel.visible:
		return
	_poll_server_status()


func _poll_server_status() -> void:
	# Relay server
	if _relay_pid > 0:
		if OS.is_process_running(_relay_pid):
			_relay_status_label.text = "Running"
			_relay_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
			_relay_button.text = "Stop Server"
		else:
			_relay_pid = -1
			_relay_status_label.text = "Stopped (exited)"
			_relay_status_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
			_relay_button.text = "Start Server"
	# Web server
	if _web_pid > 0:
		if OS.is_process_running(_web_pid):
			_web_status_label.text = "Running"
			_web_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
			_web_button.text = "Stop Server"
		else:
			_web_pid = -1
			_web_status_label.text = "Stopped (exited)"
			_web_status_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
			_web_button.text = "Start Server"


func _build_host_panel() -> void:
	var local_ip := _get_local_ip()

	# Overlay panel on right side
	_host_panel = PanelContainer.new()
	_host_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_host_panel.anchor_left = 1.0
	_host_panel.anchor_right = 1.0
	_host_panel.anchor_top = 0.5
	_host_panel.anchor_bottom = 0.5
	_host_panel.offset_left = -420
	_host_panel.offset_right = -20
	_host_panel.offset_top = -240
	_host_panel.offset_bottom = 240
	_host_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# Panel background style
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.12, 0.14, 0.95)
	panel_style.border_color = Color(0.3, 0.8, 0.8, 0.8)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 10
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	_host_panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_host_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "HOST FOR FRIENDS"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_make_separator())

	# ── Relay Server Section ──
	var relay_header := Label.new()
	relay_header.text = "Relay Server (Multiplayer)"
	relay_header.add_theme_font_size_override("font_size", 15)
	relay_header.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	vbox.add_child(relay_header)

	var relay_row := HBoxContainer.new()
	relay_row.add_theme_constant_override("separation", 10)
	vbox.add_child(relay_row)

	_relay_button = Button.new()
	_relay_button.text = "Start Server"
	_relay_button.custom_minimum_size = Vector2(130, 34)
	_style_panel_button(_relay_button, Color(0.15, 0.3, 0.3), Color(0.3, 0.7, 0.7))
	_relay_button.pressed.connect(_toggle_relay_server)
	relay_row.add_child(_relay_button)

	var relay_status_hbox := HBoxContainer.new()
	relay_status_hbox.add_theme_constant_override("separation", 5)
	relay_row.add_child(relay_status_hbox)
	var relay_status_lbl := Label.new()
	relay_status_lbl.text = "Status: "
	relay_status_lbl.add_theme_font_size_override("font_size", 14)
	relay_status_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	relay_status_hbox.add_child(relay_status_lbl)
	_relay_status_label = Label.new()
	_relay_status_label.text = "Stopped"
	_relay_status_label.add_theme_font_size_override("font_size", 14)
	_relay_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	relay_status_hbox.add_child(_relay_status_label)

	_relay_url_label = Label.new()
	_relay_url_label.text = "ws://" + local_ip + ":8765"
	_relay_url_label.add_theme_font_size_override("font_size", 13)
	_relay_url_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.8))
	vbox.add_child(_relay_url_label)

	vbox.add_child(_make_separator())

	# ── Web Server Section ──
	var web_header := Label.new()
	web_header.text = "Web Server (Browser Play)"
	web_header.add_theme_font_size_override("font_size", 15)
	web_header.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	vbox.add_child(web_header)

	var web_row := HBoxContainer.new()
	web_row.add_theme_constant_override("separation", 10)
	vbox.add_child(web_row)

	_web_button = Button.new()
	_web_button.text = "Start Server"
	_web_button.custom_minimum_size = Vector2(130, 34)
	_style_panel_button(_web_button, Color(0.15, 0.3, 0.3), Color(0.3, 0.7, 0.7))
	_web_button.pressed.connect(_toggle_web_server)
	web_row.add_child(_web_button)

	var web_status_hbox := HBoxContainer.new()
	web_status_hbox.add_theme_constant_override("separation", 5)
	web_row.add_child(web_status_hbox)
	var web_status_lbl := Label.new()
	web_status_lbl.text = "Status: "
	web_status_lbl.add_theme_font_size_override("font_size", 14)
	web_status_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	web_status_hbox.add_child(web_status_lbl)
	_web_status_label = Label.new()
	_web_status_label.text = "Stopped"
	_web_status_label.add_theme_font_size_override("font_size", 14)
	_web_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	web_status_hbox.add_child(_web_status_label)

	_web_url_label = Label.new()
	_web_url_label.text = "http://" + local_ip + ":8080"
	_web_url_label.add_theme_font_size_override("font_size", 13)
	_web_url_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.8))
	vbox.add_child(_web_url_label)

	_web_error_label = Label.new()
	_web_error_label.text = ""
	_web_error_label.add_theme_font_size_override("font_size", 12)
	_web_error_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
	_web_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_web_error_label)

	vbox.add_child(_make_separator())

	# ── Share Section ──
	var share_header := Label.new()
	share_header.text = "Share with friends:"
	share_header.add_theme_font_size_override("font_size", 15)
	share_header.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	vbox.add_child(share_header)

	_share_url_label = Label.new()
	_share_url_label.text = "http://" + local_ip + ":8080"
	_share_url_label.add_theme_font_size_override("font_size", 16)
	_share_url_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	_share_url_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_share_url_label)

	_copy_button = Button.new()
	_copy_button.text = "Copy URL"
	_copy_button.custom_minimum_size = Vector2(130, 32)
	_style_panel_button(_copy_button, Color(0.15, 0.25, 0.15), Color(0.4, 0.7, 0.4))
	_copy_button.pressed.connect(_on_copy_url)
	var copy_center := CenterContainer.new()
	copy_center.add_child(_copy_button)
	vbox.add_child(copy_center)

	# ── IP + Close ──
	_ip_label = Label.new()
	_ip_label.text = "Your IP: " + local_ip
	_ip_label.add_theme_font_size_override("font_size", 13)
	_ip_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_ip_label)

	var close_center := CenterContainer.new()
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(100, 30)
	_style_panel_button(close_btn, Color(0.2, 0.12, 0.12), Color(0.7, 0.3, 0.3))
	close_btn.pressed.connect(func(): _host_panel.visible = false)
	close_center.add_child(close_btn)
	vbox.add_child(close_center)

	add_child(_host_panel)


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	sep.add_theme_constant_override("separation", 4)
	return sep


func _style_panel_button(button: Button, bg_color: Color, border_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", style)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(bg_color.r + 0.08, bg_color.g + 0.08, bg_color.b + 0.08)
	hover.border_color = Color(border_color.r + 0.15, border_color.g + 0.15, border_color.b + 0.15)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	button.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(bg_color.r - 0.03, bg_color.g - 0.03, bg_color.b - 0.03)
	pressed.border_color = border_color
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(6)
	button.add_theme_stylebox_override("pressed", pressed)

	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))


# ── Server Control ──────────────────────────────────────────────────────

func _toggle_relay_server() -> void:
	if _relay_pid > 0 and OS.is_process_running(_relay_pid):
		OS.kill(_relay_pid)
		_relay_pid = -1
		_relay_status_label.text = "Stopped"
		_relay_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_relay_button.text = "Start Server"
		return

	var godot_exe := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var scene_path := "res://server/relay_server.tscn"
	_relay_pid = OS.create_process(godot_exe, ["--headless", "--path", project_path, scene_path])
	if _relay_pid <= 0:
		_relay_status_label.text = "Failed to start"
		_relay_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		_relay_status_label.text = "Starting..."
		_relay_status_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
		_relay_button.text = "Stop Server"


func _toggle_web_server() -> void:
	if _web_pid > 0 and OS.is_process_running(_web_pid):
		OS.kill(_web_pid)
		_web_pid = -1
		_web_status_label.text = "Stopped"
		_web_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_web_button.text = "Start Server"
		_web_error_label.text = ""
		return

	# Check web_build/ exists
	var project_path := ProjectSettings.globalize_path("res://")
	var web_build_path := project_path.path_join("web_build")
	if not DirAccess.dir_exists_absolute(web_build_path):
		_web_error_label.text = "web_build/ not found. Export your project first:\nGodot Editor > Project > Export > Web > Export Project"
		_web_status_label.text = "No web build"
		_web_status_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
		return

	var serve_script := project_path.path_join("serve_web.py")
	_web_pid = OS.create_process("python", [serve_script])
	if _web_pid <= 0:
		# Try python3 as fallback
		_web_pid = OS.create_process("python3", [serve_script])
	if _web_pid <= 0:
		_web_error_label.text = "Failed to start. Is Python installed and in PATH?"
		_web_status_label.text = "Failed"
		_web_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		_web_status_label.text = "Starting..."
		_web_status_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
		_web_button.text = "Stop Server"
		_web_error_label.text = ""


func _on_copy_url() -> void:
	var url := _share_url_label.text
	DisplayServer.clipboard_set(url)
	_copy_button.text = "Copied!"
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(_copy_button):
			_copy_button.text = "Copy URL"
	)


func _get_local_ip() -> String:
	var addresses := IP.get_local_addresses()
	for addr in addresses:
		# Filter for typical LAN IPv4 addresses
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	# Fallback
	return "127.0.0.1"


# ── Cleanup ─────────────────────────────────────────────────────────────

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_kill_servers()


func _exit_tree() -> void:
	_kill_servers()


func _kill_servers() -> void:
	if _relay_pid > 0 and OS.is_process_running(_relay_pid):
		OS.kill(_relay_pid)
		_relay_pid = -1
	if _web_pid > 0 and OS.is_process_running(_web_pid):
		OS.kill(_web_pid)
		_web_pid = -1
