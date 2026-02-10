extends Node
class_name UIAnimatorClass
## UIAnimator - Reusable animation utilities for UI polish
## Provides static-style functions for common UI animations

# === FADE ANIMATIONS ===

func fade_in(node: CanvasItem, duration: float = 0.3, delay: float = 0.0) -> Tween:
	"""Fade a node from invisible to visible."""
	node.modulate.a = 0.0
	var tween := node.create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.tween_property(node, "modulate:a", 1.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return tween


func fade_out(node: CanvasItem, duration: float = 0.3, delay: float = 0.0) -> Tween:
	"""Fade a node from visible to invisible."""
	var tween := node.create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.tween_property(node, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	return tween


# === SLIDE ANIMATIONS ===

func slide_in_from_bottom(node: Control, distance: float = 50.0, duration: float = 0.4, delay: float = 0.0) -> Tween:
	"""Slide a node in from below its current position."""
	var target_y := node.position.y
	node.position.y += distance
	node.modulate.a = 0.0
	var tween := node.create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.tween_property(node, "position:y", target_y, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(node, "modulate:a", 1.0, duration * 0.6)
	return tween


func slide_in_from_top(node: Control, distance: float = 50.0, duration: float = 0.4, delay: float = 0.0) -> Tween:
	"""Slide a node in from above its current position."""
	var target_y := node.position.y
	node.position.y -= distance
	node.modulate.a = 0.0
	var tween := node.create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.tween_property(node, "position:y", target_y, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(node, "modulate:a", 1.0, duration * 0.6)
	return tween


func slide_in_from_left(node: Control, distance: float = 80.0, duration: float = 0.4, delay: float = 0.0) -> Tween:
	"""Slide a node in from the left."""
	var target_x := node.position.x
	node.position.x -= distance
	node.modulate.a = 0.0
	var tween := node.create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.tween_property(node, "position:x", target_x, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(node, "modulate:a", 1.0, duration * 0.6)
	return tween


func slide_in_from_right(node: Control, distance: float = 80.0, duration: float = 0.4, delay: float = 0.0) -> Tween:
	"""Slide a node in from the right."""
	var target_x := node.position.x
	node.position.x += distance
	node.modulate.a = 0.0
	var tween := node.create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.tween_property(node, "position:x", target_x, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(node, "modulate:a", 1.0, duration * 0.6)
	return tween


# === SCALE ANIMATIONS ===

func scale_bounce_in(node: CanvasItem, duration: float = 0.4, delay: float = 0.0) -> Tween:
	"""Scale a node from 0 to 1 with elastic bounce."""
	node.scale = Vector2.ZERO
	var tween := node.create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.tween_property(node, "scale", Vector2.ONE, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	return tween


func scale_pop(node: CanvasItem, target_scale: float = 1.1, duration: float = 0.2) -> Tween:
	"""Quick scale pop then return - great for button feedback."""
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2(target_scale, target_scale), duration * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(node, "scale", Vector2.ONE, duration * 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	return tween


func pulse_loop(node: CanvasItem, min_scale: float = 0.95, max_scale: float = 1.05, duration: float = 1.0) -> Tween:
	"""Continuous pulsing scale loop."""
	var tween := node.create_tween()
	tween.set_loops()
	tween.tween_property(node, "scale", Vector2(max_scale, max_scale), duration * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "scale", Vector2(min_scale, min_scale), duration * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	return tween


# === SHAKE ANIMATIONS ===

func shake(node: CanvasItem, intensity: float = 5.0, duration: float = 0.3) -> Tween:
	"""Shake a node (great for damage feedback)."""
	var original_pos: Vector2 = node.position
	var tween := node.create_tween()
	var steps := 6
	var step_dur := duration / steps
	for i in range(steps):
		var offset := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		offset *= (1.0 - float(i) / steps)  # Decay
		tween.tween_property(node, "position", original_pos + offset, step_dur)
	tween.tween_property(node, "position", original_pos, step_dur)
	return tween


# === COLOR FLASH ANIMATIONS ===

func flash_color(node: CanvasItem, color: Color, duration: float = 0.3) -> Tween:
	"""Flash a node a color then return to white."""
	var tween := node.create_tween()
	tween.tween_property(node, "modulate", color, duration * 0.3)
	tween.tween_property(node, "modulate", Color.WHITE, duration * 0.7)
	return tween


func glow_pulse(node: CanvasItem, color: Color, duration: float = 0.4) -> Tween:
	"""Bright glow then fade back."""
	var tween := node.create_tween()
	tween.tween_property(node, "modulate", color, duration * 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate", Color.WHITE, duration * 0.7).set_ease(Tween.EASE_IN)
	return tween


# === STAGGER UTILITIES ===

func stagger_fade_in(nodes: Array, stagger_delay: float = 0.05, duration: float = 0.3) -> void:
	"""Fade in multiple nodes with staggered timing."""
	for i in range(nodes.size()):
		var node: CanvasItem = nodes[i]
		node.modulate.a = 0.0
		fade_in(node, duration, i * stagger_delay)


func stagger_slide_in(nodes: Array, from_direction: String = "bottom", distance: float = 40.0, stagger_delay: float = 0.06, duration: float = 0.35) -> void:
	"""Slide in multiple nodes with staggered timing."""
	for i in range(nodes.size()):
		var node: Control = nodes[i]
		match from_direction:
			"bottom":
				slide_in_from_bottom(node, distance, duration, i * stagger_delay)
			"top":
				slide_in_from_top(node, distance, duration, i * stagger_delay)
			"left":
				slide_in_from_left(node, distance, duration, i * stagger_delay)
			"right":
				slide_in_from_right(node, distance, duration, i * stagger_delay)


func stagger_scale_in(nodes: Array, stagger_delay: float = 0.04, duration: float = 0.3) -> void:
	"""Scale in multiple nodes with stagger."""
	for i in range(nodes.size()):
		var node: CanvasItem = nodes[i]
		node.scale = Vector2.ZERO
		node.modulate.a = 0.0
		var tween := node.create_tween()
		tween.tween_interval(i * stagger_delay)
		tween.tween_property(node, "scale", Vector2.ONE, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.parallel().tween_property(node, "modulate:a", 1.0, duration * 0.5)


# === SCREEN EFFECTS ===

var _screen_shake_tween: Tween

func screen_shake(intensity: float = 4.0, duration: float = 0.2) -> void:
	"""Shake the entire viewport for impact feedback (e.g. big damage)."""
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_2d()
	if camera:
		# Use camera offset for shake
		if _screen_shake_tween and _screen_shake_tween.is_valid():
			_screen_shake_tween.kill()
		_screen_shake_tween = create_tween()
		var steps := 5
		var step_dur := duration / steps
		for i in range(steps):
			var offset := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
			offset *= (1.0 - float(i) / steps)
			_screen_shake_tween.tween_property(camera, "offset", offset, step_dur)
		_screen_shake_tween.tween_property(camera, "offset", Vector2.ZERO, step_dur)
	else:
		# Fallback: shake the root canvas via a CanvasLayer trick
		# This works even without a Camera2D
		var root := get_tree().root
		if root and root.get_child_count() > 0:
			var scene := root.get_child(root.get_child_count() - 1)
			if scene is CanvasItem:
				if _screen_shake_tween and _screen_shake_tween.is_valid():
					_screen_shake_tween.kill()
				var original_pos: Vector2 = scene.position
				_screen_shake_tween = create_tween()
				var steps := 5
				var step_dur := duration / steps
				for i in range(steps):
					var offset := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
					offset *= (1.0 - float(i) / steps)
					_screen_shake_tween.tween_property(scene, "position", original_pos + offset, step_dur)
				_screen_shake_tween.tween_property(scene, "position", original_pos, step_dur)


# === SCREEN FLASH ===

var _flash_overlay: ColorRect = null
var _flash_tween: Tween

func screen_flash(color: Color = Color(1, 1, 1, 0.25), duration: float = 0.3) -> void:
	"""Flash the screen a color (for card plays, big hits, etc.)."""
	if _flash_overlay == null:
		_flash_overlay = ColorRect.new()
		_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash_overlay.modulate.a = 0.0
		_flash_overlay.z_index = 90
		var canvas := CanvasLayer.new()
		canvas.layer = 90
		canvas.add_child(_flash_overlay)
		add_child(canvas)

	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	_flash_overlay.color = Color(color.r, color.g, color.b)
	_flash_overlay.modulate.a = color.a
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_overlay, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)


# === SCREEN TRANSITION ===

var _transition_overlay: ColorRect = null

func _ready() -> void:
	_create_transition_overlay()


func _create_transition_overlay() -> void:
	"""Create a full-screen overlay for fade transitions."""
	_transition_overlay = ColorRect.new()
	_transition_overlay.color = Color.BLACK
	_transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.modulate.a = 0.0
	_transition_overlay.z_index = 100
	# Use a CanvasLayer so it's always on top
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.add_child(_transition_overlay)
	add_child(canvas)


func transition_fade_out(duration: float = 0.4) -> void:
	"""Fade screen to black."""
	if _transition_overlay:
		_transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		var tween := create_tween()
		tween.tween_property(_transition_overlay, "modulate:a", 1.0, duration)
		await tween.finished


func transition_fade_in(duration: float = 0.4) -> void:
	"""Fade from black to visible."""
	if _transition_overlay:
		_transition_overlay.modulate.a = 1.0
		var tween := create_tween()
		tween.tween_property(_transition_overlay, "modulate:a", 0.0, duration)
		await tween.finished
		_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
