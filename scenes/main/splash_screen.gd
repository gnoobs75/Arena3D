extends Control
class_name SplashScreen
## SplashScreen - Title screen with Enter Arena button

signal enter_game_pressed

@onready var background: TextureRect = $Background
@onready var enter_button: Button = $EnterButton
@onready var title_label: Label = $TitleLabel


func _ready() -> void:
	# Load splash background
	var splash_texture := load("res://assets/art/Splash.png")
	if splash_texture:
		background.texture = splash_texture

	# Connect button
	enter_button.pressed.connect(_on_enter_button_pressed)

	# Style the button
	_style_button()


func _style_button() -> void:
	"""Apply custom styling to the Enter Arena button."""
	enter_button.text = "Enter Arena"

	# Create a stylish button theme
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.15, 0.12, 0.25, 0.9)
	style_normal.border_color = Color(0.7, 0.5, 0.2)
	style_normal.set_border_width_all(3)
	style_normal.set_corner_radius_all(8)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.25, 0.2, 0.35, 0.95)
	style_hover.border_color = Color(1.0, 0.8, 0.3)
	style_hover.set_border_width_all(3)
	style_hover.set_corner_radius_all(8)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.1, 0.08, 0.15, 0.95)
	style_pressed.border_color = Color(0.5, 0.4, 0.1)
	style_pressed.set_border_width_all(3)
	style_pressed.set_corner_radius_all(8)

	enter_button.add_theme_stylebox_override("normal", style_normal)
	enter_button.add_theme_stylebox_override("hover", style_hover)
	enter_button.add_theme_stylebox_override("pressed", style_pressed)

	enter_button.add_theme_font_size_override("font_size", 28)
	enter_button.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	enter_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.8))


func _on_enter_button_pressed() -> void:
	enter_game_pressed.emit()
