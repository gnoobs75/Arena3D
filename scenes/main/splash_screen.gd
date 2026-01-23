extends Control
class_name SplashScreen
## SplashScreen - Title screen with 2D/3D mode selection

signal mode_selected(use_3d: bool)

@onready var background: TextureRect = $Background
@onready var button_2d: Button = $ButtonContainer/Button2D
@onready var button_3d: Button = $ButtonContainer/Button3D
@onready var title_label: Label = $TitleLabel


func _ready() -> void:
	# Load splash background
	var splash_texture: Texture2D = load("res://assets/art/Splash.png")
	if splash_texture:
		background.texture = splash_texture

	# Connect buttons
	button_2d.pressed.connect(_on_2d_pressed)
	button_3d.pressed.connect(_on_3d_pressed)

	# Style the buttons
	_style_button(button_2d, Color(0.15, 0.2, 0.15), Color(0.4, 0.7, 0.4))
	_style_button(button_3d, Color(0.15, 0.12, 0.25), Color(0.5, 0.4, 0.7))


func _style_button(button: Button, bg_color: Color, border_color: Color) -> void:
	"""Apply custom styling to a button."""
	var style_normal: StyleBoxFlat = StyleBoxFlat.new()
	style_normal.bg_color = Color(bg_color.r, bg_color.g, bg_color.b, 0.9)
	style_normal.border_color = border_color
	style_normal.set_border_width_all(3)
	style_normal.set_corner_radius_all(8)

	var style_hover: StyleBoxFlat = StyleBoxFlat.new()
	style_hover.bg_color = Color(bg_color.r + 0.1, bg_color.g + 0.1, bg_color.b + 0.1, 0.95)
	style_hover.border_color = Color(border_color.r + 0.2, border_color.g + 0.2, border_color.b + 0.2)
	style_hover.set_border_width_all(3)
	style_hover.set_corner_radius_all(8)

	var style_pressed: StyleBoxFlat = StyleBoxFlat.new()
	style_pressed.bg_color = Color(bg_color.r - 0.05, bg_color.g - 0.05, bg_color.b - 0.05, 0.95)
	style_pressed.border_color = Color(border_color.r - 0.2, border_color.g - 0.2, border_color.b - 0.2)
	style_pressed.set_border_width_all(3)
	style_pressed.set_corner_radius_all(8)

	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)

	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.9))


func _on_2d_pressed() -> void:
	mode_selected.emit(false)


func _on_3d_pressed() -> void:
	mode_selected.emit(true)
