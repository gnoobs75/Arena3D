extends Control
class_name VignetteOverlay
## VignetteOverlay - Dark edge vignette for atmospheric depth
## Drawn once (static) - uses bands instead of per-pixel lines for performance.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return

	var max_alpha := VisualTheme.VIGNETTE_COLOR.a
	var edge_size := 180.0
	var band_width := 6.0  # Draw in bands of 6px for performance
	var steps := int(edge_size / band_width)

	# Top edge
	for i in range(steps):
		var t := 1.0 - float(i) / float(steps)
		var alpha := max_alpha * t * t
		var y_pos := float(i) * band_width
		draw_rect(Rect2(0, y_pos, w, band_width), Color(0, 0, 0, alpha))

	# Bottom edge
	for i in range(steps):
		var t := 1.0 - float(i) / float(steps)
		var alpha := max_alpha * t * t
		var y_pos := h - float(i + 1) * band_width
		draw_rect(Rect2(0, y_pos, w, band_width), Color(0, 0, 0, alpha))

	# Left edge
	for i in range(steps):
		var t := 1.0 - float(i) / float(steps)
		var alpha := max_alpha * t * t * 0.6
		var x_pos := float(i) * band_width
		draw_rect(Rect2(x_pos, 0, band_width, h), Color(0, 0, 0, alpha))

	# Right edge
	for i in range(steps):
		var t := 1.0 - float(i) / float(steps)
		var alpha := max_alpha * t * t * 0.6
		var x_pos := w - float(i + 1) * band_width
		draw_rect(Rect2(x_pos, 0, band_width, h), Color(0, 0, 0, alpha))
