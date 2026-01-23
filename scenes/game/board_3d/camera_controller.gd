extends Camera3D
class_name CameraController3D
## CameraController3D - Controls the isometric camera for Arena
## Handles zoom, pan, and combat focus animations

# === SIGNALS ===
signal camera_moved
signal zoom_changed(new_zoom: float)

# === CONSTANTS ===
const DEFAULT_SIZE := 12.0
const MIN_SIZE := 6.0
const MAX_SIZE := 18.0
const ZOOM_SPEED := 2.0
const PAN_SPEED := 10.0

# Default isometric angles
const DEFAULT_ROTATION := Vector3(-35, 45, 0)
const DEFAULT_DISTANCE := 15.0

# === STATE ===
var _target_size: float = DEFAULT_SIZE
var _target_position: Vector3 = Vector3.ZERO
var _is_animating: bool = false
var _board_center: Vector3 = Vector3.ZERO

func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = DEFAULT_SIZE
	_setup_default_view()


func _setup_default_view() -> void:
	"""Position camera for classic isometric view of the board."""
	rotation_degrees = DEFAULT_ROTATION

	# Calculate position based on rotation and distance
	var dir: Vector3 = Vector3(1, 0.7, 1).normalized()
	position = _board_center + dir * DEFAULT_DISTANCE
	look_at(_board_center)


func _process(delta: float) -> void:
	# Smooth zoom
	if abs(size - _target_size) > 0.01:
		size = lerpf(size, _target_size, delta * ZOOM_SPEED * 3)
		zoom_changed.emit(size)


# === ZOOM CONTROLS ===

func zoom_in(amount: float = 1.0) -> void:
	"""Zoom camera in (decrease orthographic size)."""
	_target_size = clampf(_target_size - amount, MIN_SIZE, MAX_SIZE)


func zoom_out(amount: float = 1.0) -> void:
	"""Zoom camera out (increase orthographic size)."""
	_target_size = clampf(_target_size + amount, MIN_SIZE, MAX_SIZE)


func set_zoom(new_size: float) -> void:
	"""Set zoom level directly."""
	_target_size = clampf(new_size, MIN_SIZE, MAX_SIZE)


func reset_zoom() -> void:
	"""Reset to default zoom level."""
	_target_size = DEFAULT_SIZE


# === FOCUS CONTROLS ===

func focus_on_position(world_pos: Vector3, zoom_level: float = -1) -> void:
	"""Smoothly move camera to focus on a world position."""
	_board_center = world_pos
	if zoom_level > 0:
		_target_size = clampf(zoom_level, MIN_SIZE, MAX_SIZE)

	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	var dir: Vector3 = Vector3(1, 0.7, 1).normalized()
	var new_pos: Vector3 = world_pos + dir * DEFAULT_DISTANCE

	tween.tween_property(self, "position", new_pos, 0.3)

	await tween.finished
	camera_moved.emit()


func focus_on_combat(pos_a: Vector3, pos_b: Vector3, zoom_amount: float = 1.5) -> void:
	"""Focus on the midpoint between two combatants."""
	var center: Vector3 = (pos_a + pos_b) / 2
	await focus_on_position(center, DEFAULT_SIZE / zoom_amount)


func reset_view() -> void:
	"""Reset to default overview of the board."""
	_board_center = Vector3.ZERO
	_target_size = DEFAULT_SIZE

	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	var dir: Vector3 = Vector3(1, 0.7, 1).normalized()
	var default_pos: Vector3 = dir * DEFAULT_DISTANCE

	tween.tween_property(self, "position", default_pos, 0.3)

	await tween.finished
	camera_moved.emit()


# === INPUT HANDLING ===

func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in(0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out(0.5)


# === SCREEN SHAKE ===

var _shake_intensity: float = 0.0
var _shake_decay: float = 5.0
var _shake_offset: Vector3 = Vector3.ZERO

func shake(intensity: float = 0.1, duration: float = 0.3) -> void:
	"""Apply screen shake effect."""
	_shake_intensity = intensity

	# Decay shake over duration
	var tween: Tween = create_tween()
	tween.tween_property(self, "_shake_intensity", 0.0, duration)


func _apply_shake(delta: float) -> void:
	"""Apply shake offset each frame."""
	if _shake_intensity > 0.01:
		_shake_offset = Vector3(
			randf_range(-1, 1) * _shake_intensity,
			randf_range(-1, 1) * _shake_intensity * 0.5,
			randf_range(-1, 1) * _shake_intensity
		)
		# Apply offset to position (temporary)
		# In practice, you'd apply this to a shake node parent


# === COMBAT CAMERA ===

func focus_on_champion(world_pos: Vector3, zoom_level: float = 1.3) -> void:
	"""Focus on a single champion."""
	await focus_on_position(world_pos, DEFAULT_SIZE / zoom_level)


func orbit_around(center: Vector3, angle_delta: float, duration: float = 0.5) -> void:
	"""Orbit camera around a point."""
	var current_angle: float = rotation_degrees.y
	var target_angle: float = current_angle + angle_delta

	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "rotation_degrees:y", target_angle, duration)

	await tween.finished


func dramatic_zoom(world_pos: Vector3, zoom_factor: float = 2.0, duration: float = 0.3) -> void:
	"""Quick dramatic zoom for impact moments."""
	var original_size: float = size
	var target_size: float = DEFAULT_SIZE / zoom_factor

	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)

	# Zoom in
	tween.tween_property(self, "size", target_size, duration * 0.4)

	# Brief pause
	tween.tween_interval(duration * 0.2)

	# Zoom back
	tween.tween_property(self, "size", original_size, duration * 0.4)

	await tween.finished
