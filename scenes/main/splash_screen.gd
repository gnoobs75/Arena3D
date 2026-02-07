extends Control
class_name SplashScreen
## SplashScreen - Title screen with 2D/3D/Developer mode selection
## Features entrance animations and polished button effects

signal mode_selected(use_3d: bool)
signal developer_mode_selected()

@onready var background: TextureRect = $Background
@onready var button_2d: Button = $ButtonContainer/Button2D
@onready var button_3d: Button = $ButtonContainer/Button3D
@onready var button_dev: Button = $ButtonContainer/ButtonDev
@onready var title_label: Label = $TitleLabel

var _buttons_ready: bool = false


func _ready() -> void:
	# Load splash background
	var splash_texture: Texture2D = load("res://assets/art/Splash.png")
	if splash_texture:
		background.texture = splash_texture

	# Connect buttons
	button_2d.pressed.connect(_on_2d_pressed)
	button_3d.pressed.connect(_on_3d_pressed)
	button_dev.pressed.connect(_on_dev_pressed)

	# Style the buttons
	_style_button(button_2d, Color(0.15, 0.2, 0.15), Color(0.4, 0.7, 0.4))
	_style_button(button_3d, Color(0.15, 0.12, 0.25), Color(0.5, 0.4, 0.7))
	_style_button(button_dev, Color(0.25, 0.18, 0.12), Color(0.8, 0.55, 0.3))

	# Connect hover effects
	button_2d.mouse_entered.connect(_on_button_hover.bind(button_2d))
	button_2d.mouse_exited.connect(_on_button_unhover.bind(button_2d))
	button_3d.mouse_entered.connect(_on_button_hover.bind(button_3d))
	button_3d.mouse_exited.connect(_on_button_unhover.bind(button_3d))
	button_dev.mouse_entered.connect(_on_button_hover.bind(button_dev))
	button_dev.mouse_exited.connect(_on_button_unhover.bind(button_dev))

	# Play entrance animations
	_play_entrance_animations()


func _play_entrance_animations() -> void:
	"""Animate title and buttons into view."""
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
	var buttons := [button_2d, button_3d, button_dev]
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
	"""Button hover pop effect."""
	if not _buttons_ready:
		return
	button.pivot_offset = button.size / 2
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.06, 1.06), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _on_button_unhover(button: Button) -> void:
	"""Button unhover return."""
	if not _buttons_ready:
		return
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_IN_OUT)


func _style_button(button: Button, bg_color: Color, border_color: Color) -> void:
	"""Apply custom styling to a button."""
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
	# Fade transition before emitting
	if UIAnimator:
		await UIAnimator.transition_fade_out(0.3)
	mode_selected.emit(false)


func _on_3d_pressed() -> void:
	if UIAnimator:
		await UIAnimator.transition_fade_out(0.3)
	mode_selected.emit(true)


func _on_dev_pressed() -> void:
	if UIAnimator:
		await UIAnimator.transition_fade_out(0.3)
	developer_mode_selected.emit()
