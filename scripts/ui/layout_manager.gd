class_name LayoutManager extends RefCounted
## LayoutManager - Calculates responsive layout zones based on viewport size.
## Board-first layout: maximize board vertically, center horizontally,
## wider panels pinned to edges, hand at bottom with response slot embedded.

const MIN_SIDE_PANEL_W := 180
const MAX_SIDE_PANEL_W := 420
const TOP_BAR_H := 0  # No top bar - board gets full vertical space
const HAND_H := 160
const MARGIN := 10
const BOARD_NATIVE := 688  # 10*64 tiles + 24*2 coord margins
const MIN_CROWD_GAP := 50  # Minimum gap between panel edge and board for crowd

var board_rect: Rect2
var board_scale: float
var left_panel_rect: Rect2
var right_panel_rect: Rect2
var hand_rect: Rect2
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

	# Panels pinned to screen edges - wider than before
	# Use most of the side space, but ensure minimum crowd gap
	var total_side_space := board_x - MARGIN
	var max_panel_for_gap := total_side_space - MIN_CROWD_GAP
	var panel_w := clampf(total_side_space * 0.75, MIN_SIDE_PANEL_W, min(MAX_SIDE_PANEL_W, max_panel_for_gap))
	left_panel_rect = Rect2(MARGIN, board_y, panel_w, board_avail_h)
	right_panel_rect = Rect2(viewport.x - panel_w - MARGIN, board_y, panel_w, board_avail_h)

	# Hand full width at bottom (response slot is now embedded inside hand)
	hand_rect = Rect2(MARGIN, viewport.y - HAND_H, viewport.x - MARGIN * 2, HAND_H)
