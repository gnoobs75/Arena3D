class_name LayoutManager extends RefCounted
## LayoutManager - Calculates responsive layout zones based on viewport size.
## Board-first layout: maximize board vertically, center horizontally,
## panels adjacent to board, hand at bottom.

const MIN_SIDE_PANEL_W := 180
const MAX_SIDE_PANEL_W := 320
const TOP_BAR_H := 0  # No top bar - board gets full vertical space
const HAND_H := 160
const MARGIN := 10
const BOARD_NATIVE := 688  # 10*64 tiles + 24*2 coord margins

var board_rect: Rect2
var board_scale: float
var left_panel_rect: Rect2
var right_panel_rect: Rect2
var hand_rect: Rect2
var response_slot_rect: Rect2
var viewport_size: Vector2


func calculate(viewport: Vector2) -> void:
	viewport_size = viewport

	# Board fills available vertical space (no top bar, just margins)
	var board_avail_h := viewport.y - HAND_H - MARGIN * 2
	board_scale = board_avail_h / float(BOARD_NATIVE)
	var board_px := BOARD_NATIVE * board_scale
	var board_x := (viewport.x - board_px) / 2.0
	var board_y := MARGIN
	board_rect = Rect2(board_x, board_y, board_px, board_px)

	# Panels pinned to screen edges (not adjacent to board)
	# This creates a wide gap for the arena crowd/spectators
	var total_side_space := board_x - MARGIN
	var panel_w := clampf(total_side_space * 0.55, MIN_SIDE_PANEL_W, MAX_SIDE_PANEL_W)
	left_panel_rect = Rect2(MARGIN, board_y, panel_w, board_avail_h)
	right_panel_rect = Rect2(viewport.x - panel_w - MARGIN, board_y, panel_w, board_avail_h)

	# Hand full width at bottom
	hand_rect = Rect2(MARGIN, viewport.y - HAND_H, viewport.x - MARGIN * 2, HAND_H)

	# Response slot in the gap between left panel and board, vertically centered
	var slot_w := 145.0
	var slot_h := 195.0
	var gap_left := left_panel_rect.position.x + left_panel_rect.size.x + MARGIN
	var gap_right := board_x - MARGIN
	var slot_x := gap_left + (gap_right - gap_left - slot_w) / 2.0
	# Fallback if gap is too narrow
	if slot_x < gap_left:
		slot_x = gap_left
	var slot_y := board_y + (board_px - slot_h) / 2.0
	response_slot_rect = Rect2(slot_x, slot_y, slot_w, slot_h)
