extends Node2D
## ArenaCrowdLayer - Colosseum spectator crowd around the arena board
## Draws articulated tiny people in tiered rows with varied poses, reactions,
## beer vendor walking aisles, jumping/cheering animations, and speech bubbles.
## Each spectator has head, torso, arms, and legs drawn individually.

var _board_size_px: int = 640
var _margin: int = 24
var _time: float = 0.0

# Spectator data
var _spectators: Array[Dictionary] = []
var _torches: Array[Dictionary] = []
var _beer_vendors: Array[Dictionary] = []

# Speech bubble data
var _speech_bubbles: Array[Dictionary] = []

# Reaction state
var _global_react_timer: float = 0.0
var _global_react_type: String = ""

# Wave state - Mexican wave sweeps through crowd
var _wave_timer: float = -1.0
var _wave_side: int = 0

# Spectator pose types
enum Pose { SITTING, STANDING, CHEERING, BEER_HOLD, FIST_PUMP, LEAN_FORWARD, CLAPPING }

# Clothing colors - varied arena audience palette
const SHIRT_COLORS := [
	Color(0.55, 0.15, 0.1),   # Red
	Color(0.15, 0.3, 0.55),   # Blue
	Color(0.5, 0.35, 0.1),    # Brown
	Color(0.15, 0.45, 0.2),   # Green
	Color(0.5, 0.1, 0.4),     # Purple
	Color(0.5, 0.45, 0.1),    # Gold
	Color(0.35, 0.35, 0.35),  # Grey
	Color(0.6, 0.3, 0.15),    # Orange
	Color(0.1, 0.35, 0.35),   # Teal
	Color(0.45, 0.2, 0.3),    # Mauve
]

const SKIN_TONES := [
	Color(0.85, 0.7, 0.55),   # Light
	Color(0.7, 0.55, 0.4),    # Medium
	Color(0.55, 0.4, 0.3),    # Tan
	Color(0.4, 0.3, 0.22),    # Brown
	Color(0.75, 0.6, 0.5),    # Warm light
	Color(0.65, 0.5, 0.38),   # Warm medium
]

# Beer color
const BEER_COLOR := Color(0.8, 0.65, 0.15, 0.9)
const MUG_COLOR := Color(0.55, 0.45, 0.3, 0.9)
const FOAM_COLOR := Color(0.95, 0.92, 0.8, 0.9)

# Funny crowd shouts
const SHOUTS_BIG_HIT := [
	"OHHH!", "BRUTAL!", "That's GOTTA hurt!", "MEDIC!",
	"He's DONE!", "RIP!", "WASTED!", "MY EYES!",
	"Did you SEE that?!", "Call the healer!", "Somebody stop this!",
	"FATALITY!", "I felt that from here!", "Is he alive?!",
	"I'm glad I paid for seats!", "OOOOF!", "DESTROYED!",
	"That was PERSONAL!", "He's seeing stars!", "GOODNIGHT!",
]

const SHOUTS_KILL := [
	"HE'S OUT!", "FINISH HIM!", "And STAY down!",
	"Another one bites the dust!", "GG!", "REST IN PIECES!",
	"ELIMINATED!", "Bye bye!", "Next challenger please!",
	"That's a wrap!", "Swept the floor with 'em!",
	"Someone tell his family!", "FLAWLESS!", "EZ!",
]

const SHOUTS_SPELL := [
	"MAGIC!", "Ooh, sparkly!", "Show-off!", "Nice trick!",
	"Do a fireball next!", "WIZARD!", "Fancy!",
	"I could do that...", "Read the card!", "COMBO!",
]

const SHOUTS_HEAL := [
	"Get up!", "Walk it off!", "He's fine!", "Rub some dirt on it!",
	"Second wind!", "Back in it!", "Not dead yet!",
]

const SHOUTS_IDLE := [
	"DO SOMETHING!", "BOOORING!", "I paid good money for this!",
	"Fight already!", "My grandma hits harder!",
	"Snack break!", "Wake me when it's over!",
	"GET ON WITH IT!", "Less talking, more smashing!",
	"I've seen better fights at a tavern!",
	"BEER GUY! Over here!", "Where's the beer man?!",
	"This seat is sticky!", "I can't see!",
]

const SHOUTS_CHEER := [
	"YEAH!", "LET'S GO!", "WOOO!", "MORE! MORE!",
	"This is AMAZING!", "Best fight ever!",
	"ENCORE!", "Worth every coin!",
]

const SHOUTS_BEER := [
	"COLD ONES! Get yer cold ones!",
	"BEER HERE!", "Fresh ale! Two coppers!",
	"Mead! Ale! Wine!", "Drinks! Get yer drinks!",
]


func setup(board_px: int, margin: int) -> void:
	_board_size_px = board_px
	_margin = margin
	_generate_spectators()
	_generate_torches()
	_generate_beer_vendors()
	_connect_events()


func _connect_events() -> void:
	if EventBus:
		EventBus.champion_attacked.connect(_on_champion_attacked)
		EventBus.champion_died.connect(_on_champion_died)
		EventBus.champion_healed.connect(_on_champion_healed)
		EventBus.card_played.connect(_on_card_played)
		EventBus.game_started.connect(_on_game_started)
		EventBus.game_ended.connect(_on_game_ended)


func _generate_spectators() -> void:
	_spectators.clear()
	var total_w := float(_board_size_px + _margin * 2)
	var crowd_depth := 120.0

	for row in range(VisualTheme.CROWD_ROWS):
		var row_t := float(row) / float(VisualTheme.CROWD_ROWS)
		var row_depth := 10.0 + float(row) * (crowd_depth / float(VisualTheme.CROWD_ROWS))
		var row_scale := 1.0 - row_t * 0.3
		var count := VisualTheme.CROWD_PER_SIDE - row * 1

		for side in range(4):
			for i in range(count):
				var t := (float(i) + 0.5) / float(count)
				var hash_val := sin(float(i) * 7.3 + float(side) * 13.7 + float(row) * 5.1)
				var hash2 := sin(float(i) * 3.1 + float(side) * 8.7 + float(row) * 2.3)
				var hash3 := sin(float(i) * 11.3 + float(side) * 4.1 + float(row) * 9.7)
				var offset_x := hash_val * 3.5
				var offset_y := sin(hash_val * 2.7) * 2.0

				var spec := {}
				spec["row"] = row
				spec["side"] = side
				spec["scale"] = row_scale
				spec["sway_phase"] = sin(float(i) * 2.7 + float(side) * 1.3 + float(row) * 3.1) * TAU

				# Assign a deterministic pose based on hash
				var pose_roll := absf(hash2)
				var pose: int
				if row >= 3:
					# Back rows: mostly sitting
					pose = Pose.SITTING
				elif pose_roll < 0.35:
					pose = Pose.SITTING
				elif pose_roll < 0.55:
					pose = Pose.STANDING
				elif pose_roll < 0.7:
					pose = Pose.BEER_HOLD
				elif pose_roll < 0.8:
					pose = Pose.LEAN_FORWARD
				elif pose_roll < 0.9:
					pose = Pose.FIST_PUMP
				else:
					pose = Pose.CLAPPING
				spec["pose"] = pose

				# Deterministic appearance
				var shirt_idx := int(absf(hash3 * 47.0)) % SHIRT_COLORS.size()
				var skin_idx := int(absf(hash_val * 31.0)) % SKIN_TONES.size()
				spec["shirt_color"] = SHIRT_COLORS[shirt_idx]
				spec["skin_color"] = SKIN_TONES[skin_idx]
				spec["has_hat"] = absf(hash2 * 5.0) > 3.5
				spec["hat_color"] = SHIRT_COLORS[(shirt_idx + 3) % SHIRT_COLORS.size()]
				spec["is_fat"] = absf(hash3 * 7.0) > 5.5
				spec["height_mult"] = 0.85 + absf(hash2 * 0.3)

				# Reaction state
				spec["react_offset"] = 0.0
				spec["react_timer"] = 0.0
				spec["jump_height"] = 0.0
				spec["jump_timer"] = 0.0

				# Position
				match side:
					0:
						spec["x"] = t * total_w + offset_x
						spec["y"] = -row_depth + offset_y
					1:
						spec["x"] = t * total_w + offset_x
						spec["y"] = total_w + row_depth + offset_y
					2:
						spec["x"] = -row_depth + offset_x
						spec["y"] = t * total_w + offset_y
					3:
						spec["x"] = total_w + row_depth + offset_x
						spec["y"] = t * total_w + offset_y

				_spectators.append(spec)


func _generate_torches() -> void:
	_torches.clear()
	var total := float(_board_size_px + _margin * 2)
	var offset := 14.0

	var corners := [
		Vector2(-offset, -offset),
		Vector2(total + offset, -offset),
		Vector2(-offset, total + offset),
		Vector2(total + offset, total + offset),
	]
	for i in range(corners.size()):
		_torches.append({
			"x": corners[i].x, "y": corners[i].y,
			"phase": float(i) * 1.7, "size": 1.4,
		})

	var mids := [
		Vector2(total * 0.5, -offset - 8),
		Vector2(total * 0.5, total + offset + 8),
		Vector2(-offset - 8, total * 0.5),
		Vector2(total + offset + 8, total * 0.5),
	]
	for i in range(mids.size()):
		_torches.append({
			"x": mids[i].x, "y": mids[i].y,
			"phase": float(i) * 2.3 + 1.0, "size": 0.9,
		})


func _generate_beer_vendors() -> void:
	_beer_vendors.clear()
	var total := float(_board_size_px + _margin * 2)

	# Two vendors: one on top/bottom aisle, one on left/right
	_beer_vendors.append({
		"side": 0, "t": 0.0, "speed": 0.04, "direction": 1,
		"x": 0.0, "y": 0.0, "shout_timer": 0.0,
		"walk_phase": 0.0, "paused": false, "pause_timer": 0.0,
	})
	_beer_vendors.append({
		"side": 3, "t": 0.5, "speed": 0.035, "direction": 1,
		"x": 0.0, "y": 0.0, "shout_timer": 0.0,
		"walk_phase": 0.0, "paused": false, "pause_timer": 0.0,
	})

	for vendor: Dictionary in _beer_vendors:
		_update_vendor_position(vendor)


func _update_vendor_position(vendor: Dictionary) -> void:
	var total := float(_board_size_px + _margin * 2)
	var aisle_depth := 45.0  # Between row 1 and 2
	var t_val := float(vendor["t"])
	var side_val := int(vendor["side"])
	match side_val:
		0:
			vendor["x"] = t_val * total
			vendor["y"] = -aisle_depth
		1:
			vendor["x"] = t_val * total
			vendor["y"] = total + aisle_depth
		2:
			vendor["x"] = -aisle_depth
			vendor["y"] = t_val * total
		3:
			vendor["x"] = total + aisle_depth
			vendor["y"] = t_val * total


func _process(delta: float) -> void:
	_time += delta

	# Update reaction timers and jump animations
	_global_react_timer = maxf(_global_react_timer - delta, 0.0)
	for spec: Dictionary in _spectators:
		if float(spec["react_timer"]) > 0:
			spec["react_timer"] = maxf(float(spec["react_timer"]) - delta, 0.0)
			var react_t := float(spec["react_timer"]) / VisualTheme.CROWD_REACT_DURATION
			spec["react_offset"] = sin(react_t * PI) * VisualTheme.CROWD_REACT_INTENSITY
		if float(spec["jump_timer"]) > 0:
			spec["jump_timer"] = maxf(float(spec["jump_timer"]) - delta, 0.0)
			var jump_t := float(spec["jump_timer"]) / 0.6
			spec["jump_height"] = sin(jump_t * PI) * 8.0 * float(spec["scale"])
		else:
			spec["jump_height"] = 0.0

	# Update wave
	if _wave_timer >= 0:
		_wave_timer += delta * 3.0
		if _wave_timer > float(VisualTheme.CROWD_PER_SIDE + 6):
			_wave_timer = -1.0

	# Update beer vendors
	for vendor: Dictionary in _beer_vendors:
		if bool(vendor["paused"]):
			vendor["pause_timer"] = float(vendor["pause_timer"]) - delta
			if float(vendor["pause_timer"]) <= 0:
				vendor["paused"] = false
		else:
			var spd := float(vendor["speed"]) * delta
			var dir := int(vendor["direction"])
			vendor["t"] = float(vendor["t"]) + spd * float(dir)
			vendor["walk_phase"] = float(vendor["walk_phase"]) + delta * 8.0

			if float(vendor["t"]) >= 1.0:
				vendor["t"] = 1.0
				vendor["direction"] = -1
				# Switch to next side
				vendor["side"] = (int(vendor["side"]) + 1) % 4
				vendor["paused"] = true
				vendor["pause_timer"] = 1.5
			elif float(vendor["t"]) <= 0.0:
				vendor["t"] = 0.0
				vendor["direction"] = 1
				vendor["side"] = (int(vendor["side"]) + 1) % 4
				vendor["paused"] = true
				vendor["pause_timer"] = 1.5

			_update_vendor_position(vendor)

		# Vendor shouts
		vendor["shout_timer"] = float(vendor["shout_timer"]) - delta
		if float(vendor["shout_timer"]) <= 0:
			vendor["shout_timer"] = 6.0 + sin(_time * 0.7) * 2.0
			if not bool(vendor["paused"]):
				_spawn_vendor_shout(vendor)

	# Update speech bubbles
	var idx := 0
	while idx < _speech_bubbles.size():
		_speech_bubbles[idx]["timer"] = float(_speech_bubbles[idx]["timer"]) - delta
		if float(_speech_bubbles[idx]["timer"]) <= 0:
			_speech_bubbles.remove_at(idx)
		else:
			idx += 1

	_check_idle_shout(delta)
	queue_redraw()


func _draw() -> void:
	_draw_tier_background()
	_draw_torches()
	# Draw spectators back-to-front by row
	for row in range(VisualTheme.CROWD_ROWS - 1, -1, -1):
		for spec: Dictionary in _spectators:
			if int(spec["row"]) == row:
				_draw_spectator(spec)
		# Draw beer vendors in their row layer
		if row == 2:
			for vendor: Dictionary in _beer_vendors:
				_draw_beer_vendor(vendor)
	_draw_speech_bubbles()


func _draw_tier_background() -> void:
	var total := float(_board_size_px + _margin * 2)
	var crowd_depth := 125.0

	for tier in range(VisualTheme.CROWD_ROWS + 1):
		var depth := 8.0 + float(tier) * (crowd_depth / float(VisualTheme.CROWD_ROWS))
		var next_depth := 8.0 + float(tier + 1) * (crowd_depth / float(VisualTheme.CROWD_ROWS))
		var alpha := 0.3 - float(tier) * 0.03
		var tier_col := Color(0.08, 0.05, 0.12, alpha)

		draw_rect(Rect2(-next_depth, -next_depth, total + next_depth * 2, next_depth - depth), tier_col)
		draw_rect(Rect2(-next_depth, total + depth, total + next_depth * 2, next_depth - depth), tier_col)
		draw_rect(Rect2(-next_depth, -depth, next_depth - depth, total + depth * 2), tier_col)
		draw_rect(Rect2(total + depth, -depth, next_depth - depth, total + depth * 2), tier_col)

	# Stone ledge / railing at front of crowd
	var rail_col := Color(0.2, 0.18, 0.22, 0.5)
	var rail_w := 3.0
	draw_rect(Rect2(-8, -8, total + 16, rail_w), rail_col)
	draw_rect(Rect2(-8, total + 5, total + 16, rail_w), rail_col)
	draw_rect(Rect2(-8, -8, rail_w, total + 16), rail_col)
	draw_rect(Rect2(total + 5, -8, rail_w, total + 16), rail_col)


func _draw_torches() -> void:
	for torch: Dictionary in _torches:
		var tx := float(torch["x"])
		var ty := float(torch["y"])
		var phase := float(torch["phase"])
		var sz := float(torch["size"])

		var flicker := 0.7 + sin(_time * VisualTheme.TORCH_FLICKER_SPEED + phase) * 0.15
		flicker += sin(_time * VisualTheme.TORCH_FLICKER_SPEED * 2.3 + phase * 1.7) * 0.1
		flicker += sin(_time * VisualTheme.TORCH_FLICKER_SPEED * 0.7 + phase * 3.1) * 0.05

		# Wide warm glow
		var glow := VisualTheme.TORCH_COLOR
		glow.a = 0.1 * flicker
		draw_circle(Vector2(tx, ty), VisualTheme.TORCH_RADIUS * 3.0 * sz, glow)
		glow.a = 0.2 * flicker
		draw_circle(Vector2(tx, ty), VisualTheme.TORCH_RADIUS * 1.5 * sz, glow)
		glow.a = 0.45 * flicker
		draw_circle(Vector2(tx, ty), VisualTheme.TORCH_RADIUS * 0.6 * sz, glow)
		# Bright core
		glow.a = 0.85 * flicker
		draw_circle(Vector2(tx, ty), VisualTheme.TORCH_RADIUS * 0.2 * sz, glow)

		# Brazier base
		var brazier_col := Color(0.25, 0.2, 0.18, 0.7)
		draw_rect(Rect2(tx - 4 * sz, ty + 2 * sz, 8 * sz, 5 * sz), brazier_col)
		var rim_col := Color(0.45, 0.35, 0.2, 0.6)
		draw_rect(Rect2(tx - 5 * sz, ty + 1 * sz, 10 * sz, 2 * sz), rim_col)

		# Sparks (deterministic)
		for s in range(3):
			var spark_t := fmod(_time * 1.5 + phase + float(s) * 2.1, 3.0)
			if spark_t < 1.5:
				var spark_x := tx + sin(phase + float(s) * 4.7) * 4.0 * sz
				var spark_y := ty - spark_t * 8.0 * sz
				var spark_alpha := (1.5 - spark_t) / 1.5
				var spark_col := Color(1.0, 0.8, 0.2, spark_alpha * 0.7 * flicker)
				draw_circle(Vector2(spark_x, spark_y), 1.0 * sz, spark_col)


func _draw_spectator(spec: Dictionary) -> void:
	var sx := float(spec["x"])
	var sy := float(spec["y"])
	var row := int(spec["row"])
	var side := int(spec["side"])
	var sc := float(spec["scale"])
	var sway_phase := float(spec["sway_phase"])
	var react_offset := float(spec["react_offset"])
	var pose := int(spec["pose"])
	var shirt_col: Color = spec["shirt_color"]
	var skin_col: Color = spec["skin_color"]
	var has_hat := bool(spec["has_hat"])
	var hat_col: Color = spec["hat_color"] if has_hat else Color.BLACK
	var is_fat := bool(spec["is_fat"])
	var h_mult := float(spec["height_mult"])
	var jump_h := float(spec["jump_height"])

	# Dim back rows
	var alpha := 0.85 - float(row) * 0.1
	shirt_col.a = alpha
	skin_col.a = alpha

	# Idle sway
	var sway := sin(_time * VisualTheme.CROWD_SWAY_SPEED + sway_phase) * VisualTheme.CROWD_SWAY_AMOUNT * sc

	# Wave animation
	if _wave_timer >= 0 and row < 3:
		var spec_pos := sx if side in [0, 1] else sy
		var total_w := float(_board_size_px + _margin * 2)
		var wave_pos := _wave_timer * (total_w / float(VisualTheme.CROWD_PER_SIDE))
		var dist := absf(spec_pos - wave_pos)
		if dist < 30.0:
			var wave_lift := (1.0 - dist / 30.0) * 6.0 * sc
			jump_h = maxf(jump_h, wave_lift)

	# Base dimensions
	var head_r := 4.0 * sc
	var torso_w := (7.0 if not is_fat else 9.0) * sc
	var torso_h := 8.0 * sc * h_mult
	var arm_len := 6.0 * sc * h_mult
	var arm_w := 1.8 * sc
	var leg_len := 5.0 * sc * h_mult
	var leg_w := 2.0 * sc

	# Determine "outward" direction (where the person faces - toward the arena)
	# All drawing assumes top-side perspective then we adjust per side
	var cx := sx + sway
	var cy := sy

	# Apply reaction offset (jump away from board)
	match side:
		0: cy -= react_offset + jump_h
		1: cy += react_offset; cy -= jump_h
		2: cx -= react_offset; cy -= jump_h
		3: cx += react_offset; cy -= jump_h

	# For simplicity, we draw all spectators as if viewed from the front
	# (facing the arena). Side 0=top faces down, 1=bottom faces up, etc.
	# We'll use a unified body drawing with directional flipping

	# Body anchor point (hip center)
	var hip := Vector2(cx, cy)
	var facing := 1.0  # 1 = facing down (top side), -1 = facing up

	match side:
		0:  # Top side - facing down into arena
			facing = 1.0
			_draw_person_vertical(hip, facing, sc, head_r, torso_w, torso_h, arm_len, arm_w, leg_len, leg_w, shirt_col, skin_col, has_hat, hat_col, pose, sway_phase, alpha, is_fat)
		1:  # Bottom side - facing up into arena
			facing = -1.0
			_draw_person_vertical(hip, facing, sc, head_r, torso_w, torso_h, arm_len, arm_w, leg_len, leg_w, shirt_col, skin_col, has_hat, hat_col, pose, sway_phase, alpha, is_fat)
		2:  # Left side - facing right into arena
			_draw_person_horizontal(hip, 1.0, sc, head_r, torso_w, torso_h, arm_len, arm_w, leg_len, leg_w, shirt_col, skin_col, has_hat, hat_col, pose, sway_phase, alpha, is_fat)
		3:  # Right side - facing left into arena
			_draw_person_horizontal(hip, -1.0, sc, head_r, torso_w, torso_h, arm_len, arm_w, leg_len, leg_w, shirt_col, skin_col, has_hat, hat_col, pose, sway_phase, alpha, is_fat)


func _draw_person_vertical(hip: Vector2, facing: float, sc: float,
		head_r: float, torso_w: float, torso_h: float,
		arm_len: float, arm_w: float, leg_len: float, leg_w: float,
		shirt_col: Color, skin_col: Color, has_hat: bool, hat_col: Color,
		pose: int, phase: float, alpha: float, is_fat: bool) -> void:
	# facing: 1 = body extends upward from hip (top crowd looking down)
	#        -1 = body extends downward from hip (bottom crowd looking up)
	var dir := -facing  # Drawing direction for body parts

	# Leg positions
	var left_leg_base := hip + Vector2(-torso_w * 0.3, 0)
	var right_leg_base := hip + Vector2(torso_w * 0.3, 0)
	var leg_end_offset := Vector2(0, -dir * leg_len)

	# Sitting: legs bent forward
	if pose == Pose.SITTING:
		leg_end_offset = Vector2(0, -dir * leg_len * 0.3)

	var leg_col := shirt_col.darkened(0.3)
	leg_col.a = alpha
	draw_line(left_leg_base, left_leg_base + leg_end_offset, leg_col, leg_w)
	draw_line(right_leg_base, right_leg_base + leg_end_offset, leg_col, leg_w)

	# Torso
	var torso_top := hip + Vector2(0, dir * torso_h)
	draw_line(hip, torso_top, shirt_col, torso_w)

	# Arms
	var shoulder_l := torso_top + Vector2(-torso_w * 0.5, -dir * 2.0 * sc)
	var shoulder_r := torso_top + Vector2(torso_w * 0.5, -dir * 2.0 * sc)

	var arm_anim := sin(_time * 2.5 + phase) * 0.3  # Subtle arm movement

	match pose:
		Pose.SITTING, Pose.STANDING:
			# Arms at sides, slight swing
			var la_end := shoulder_l + Vector2(-2.0 * sc + arm_anim * sc, -dir * arm_len * 0.7)
			var ra_end := shoulder_r + Vector2(2.0 * sc - arm_anim * sc, -dir * arm_len * 0.7)
			draw_line(shoulder_l, la_end, skin_col, arm_w)
			draw_line(shoulder_r, ra_end, skin_col, arm_w)

		Pose.CHEERING:
			# Both arms up with fists
			var arm_sway := sin(_time * 4.0 + phase) * 3.0 * sc
			var la_end := shoulder_l + Vector2(-3.0 * sc + arm_sway, dir * arm_len * 1.1)
			var ra_end := shoulder_r + Vector2(3.0 * sc + arm_sway, dir * arm_len * 1.1)
			draw_line(shoulder_l, la_end, skin_col, arm_w)
			draw_line(shoulder_r, ra_end, skin_col, arm_w)
			# Fist circles
			draw_circle(la_end, 1.5 * sc, skin_col)
			draw_circle(ra_end, 1.5 * sc, skin_col)

		Pose.BEER_HOLD:
			# Left arm at side, right arm holding beer mug up
			var la_end := shoulder_l + Vector2(-2.0 * sc, -dir * arm_len * 0.7)
			draw_line(shoulder_l, la_end, skin_col, arm_w)
			# Beer arm - angled up and forward
			var beer_elbow := shoulder_r + Vector2(2.0 * sc, dir * arm_len * 0.3)
			var beer_hand := beer_elbow + Vector2(1.0 * sc, dir * arm_len * 0.4)
			draw_line(shoulder_r, beer_elbow, skin_col, arm_w)
			draw_line(beer_elbow, beer_hand, skin_col, arm_w)
			# Draw mug
			_draw_beer_mug(beer_hand, sc, alpha, facing)

		Pose.FIST_PUMP:
			# One arm pumping up and down
			var pump_y := sin(_time * 3.5 + phase) * 4.0 * sc
			var la_end := shoulder_l + Vector2(-2.0 * sc, -dir * arm_len * 0.6)
			var ra_end := shoulder_r + Vector2(2.0 * sc, dir * (arm_len + pump_y))
			draw_line(shoulder_l, la_end, skin_col, arm_w)
			draw_line(shoulder_r, ra_end, skin_col, arm_w)
			draw_circle(ra_end, 1.5 * sc, skin_col)

		Pose.LEAN_FORWARD:
			# Arms resting on railing (bent forward)
			var lean := 3.0 * sc * facing
			var la_end := shoulder_l + Vector2(-1.0 * sc, -dir * arm_len * 0.5 - lean)
			var ra_end := shoulder_r + Vector2(1.0 * sc, -dir * arm_len * 0.5 - lean)
			draw_line(shoulder_l, la_end, skin_col, arm_w)
			draw_line(shoulder_r, ra_end, skin_col, arm_w)

		Pose.CLAPPING:
			# Hands meeting in front
			var clap_t := sin(_time * 6.0 + phase)
			var spread := absf(clap_t) * 4.0 * sc
			var clap_y := torso_top.y + dir * arm_len * 0.4
			var la_end := Vector2(hip.x - spread, clap_y)
			var ra_end := Vector2(hip.x + spread, clap_y)
			draw_line(shoulder_l, la_end, skin_col, arm_w)
			draw_line(shoulder_r, ra_end, skin_col, arm_w)

	# Head
	var neck := torso_top + Vector2(0, dir * 2.0 * sc)
	var head_center := neck + Vector2(0, dir * head_r)
	draw_circle(head_center, head_r, skin_col)

	# Hair/hat
	if has_hat:
		hat_col.a = alpha
		# Simple cap
		var hat_top := head_center + Vector2(0, dir * head_r * 0.5)
		draw_rect(Rect2(hat_top.x - head_r * 1.3, hat_top.y - 1.0 * sc, head_r * 2.6, 2.0 * sc), hat_col)
		draw_rect(Rect2(hat_top.x - head_r * 0.9, hat_top.y + (dir * 1.0 if facing > 0 else -dir * 3.0) * sc, head_r * 1.8, 3.0 * sc), hat_col)
	else:
		# Hair blob on top of head
		var hair_col := shirt_col.darkened(0.4)
		hair_col.a = alpha * 0.8
		var hair_center := head_center + Vector2(0, dir * head_r * 0.6)
		draw_circle(hair_center, head_r * 0.8, hair_col)


func _draw_person_horizontal(hip: Vector2, facing: float, sc: float,
		head_r: float, torso_w: float, torso_h: float,
		arm_len: float, arm_w: float, leg_len: float, leg_w: float,
		shirt_col: Color, skin_col: Color, has_hat: bool, hat_col: Color,
		pose: int, phase: float, alpha: float, is_fat: bool) -> void:
	# facing: 1 = facing right, -1 = facing left
	# Body extends horizontally from hip

	# Legs
	var left_leg_base := hip + Vector2(0, -torso_w * 0.3)
	var right_leg_base := hip + Vector2(0, torso_w * 0.3)
	var leg_end := Vector2(-facing * leg_len * 0.3, 0) if pose == Pose.SITTING else Vector2(-facing * leg_len, 0)

	var leg_col := shirt_col.darkened(0.3)
	leg_col.a = alpha
	draw_line(left_leg_base, left_leg_base + leg_end, leg_col, leg_w)
	draw_line(right_leg_base, right_leg_base + leg_end, leg_col, leg_w)

	# Torso
	var torso_end := hip + Vector2(facing * torso_h, 0)
	draw_line(hip, torso_end, shirt_col, torso_w)

	# Shoulders
	var shoulder_l := torso_end + Vector2(facing * 2.0 * sc, -torso_w * 0.5)
	var shoulder_r := torso_end + Vector2(facing * 2.0 * sc, torso_w * 0.5)

	var arm_anim := sin(_time * 2.5 + phase) * 0.3

	match pose:
		Pose.SITTING, Pose.STANDING, Pose.LEAN_FORWARD:
			var la_end := shoulder_l + Vector2(facing * arm_len * 0.5, -2.0 * sc)
			var ra_end := shoulder_r + Vector2(facing * arm_len * 0.5, 2.0 * sc)
			draw_line(shoulder_l, la_end, skin_col, arm_w)
			draw_line(shoulder_r, ra_end, skin_col, arm_w)

		Pose.CHEERING:
			var arm_sway := sin(_time * 4.0 + phase) * 2.0 * sc
			var la_end := shoulder_l + Vector2(facing * arm_len * 0.8, -3.0 * sc + arm_sway)
			var ra_end := shoulder_r + Vector2(facing * arm_len * 0.8, 3.0 * sc + arm_sway)
			draw_line(shoulder_l, la_end, skin_col, arm_w)
			draw_line(shoulder_r, ra_end, skin_col, arm_w)
			draw_circle(la_end, 1.5 * sc, skin_col)
			draw_circle(ra_end, 1.5 * sc, skin_col)

		Pose.BEER_HOLD:
			var la_end := shoulder_l + Vector2(facing * arm_len * 0.5, -2.0 * sc)
			draw_line(shoulder_l, la_end, skin_col, arm_w)
			var beer_hand := shoulder_r + Vector2(facing * arm_len * 0.6, 1.0 * sc)
			draw_line(shoulder_r, beer_hand, skin_col, arm_w)
			_draw_beer_mug(beer_hand, sc, alpha, 0.0)

		Pose.FIST_PUMP:
			var pump := sin(_time * 3.5 + phase) * 3.0 * sc
			var la_end := shoulder_l + Vector2(facing * arm_len * 0.5, -2.0 * sc)
			var ra_end := shoulder_r + Vector2(facing * (arm_len + pump), 1.0 * sc)
			draw_line(shoulder_l, la_end, skin_col, arm_w)
			draw_line(shoulder_r, ra_end, skin_col, arm_w)
			draw_circle(ra_end, 1.5 * sc, skin_col)

		Pose.CLAPPING:
			var clap_t := sin(_time * 6.0 + phase)
			var spread := absf(clap_t) * 3.0 * sc
			var clap_x := torso_end.x + facing * arm_len * 0.4
			var la_end := Vector2(clap_x, hip.y - spread)
			var ra_end := Vector2(clap_x, hip.y + spread)
			draw_line(shoulder_l, la_end, skin_col, arm_w)
			draw_line(shoulder_r, ra_end, skin_col, arm_w)

	# Head
	var neck := torso_end + Vector2(facing * 2.0 * sc, 0)
	var head_center := neck + Vector2(facing * head_r, 0)
	draw_circle(head_center, head_r, skin_col)

	if has_hat:
		hat_col.a = alpha
		var hat_center := head_center + Vector2(facing * head_r * 0.5, 0)
		draw_rect(Rect2(hat_center.x - 1.0 * sc, hat_center.y - head_r * 1.3, 2.0 * sc, head_r * 2.6), hat_col)
	else:
		var hair_col := shirt_col.darkened(0.4)
		hair_col.a = alpha * 0.8
		draw_circle(head_center + Vector2(facing * head_r * 0.5, 0), head_r * 0.75, hair_col)


func _draw_beer_mug(pos: Vector2, sc: float, alpha: float, _facing: float) -> void:
	var mug_w := 3.0 * sc
	var mug_h := 4.0 * sc
	# Mug body
	var mc := MUG_COLOR
	mc.a = alpha
	draw_rect(Rect2(pos.x - mug_w * 0.5, pos.y - mug_h, mug_w, mug_h), mc)
	# Beer inside
	var bc := BEER_COLOR
	bc.a = alpha
	draw_rect(Rect2(pos.x - mug_w * 0.4, pos.y - mug_h * 0.85, mug_w * 0.8, mug_h * 0.7), bc)
	# Foam top
	var fc := FOAM_COLOR
	fc.a = alpha
	draw_circle(Vector2(pos.x, pos.y - mug_h), mug_w * 0.5, fc)
	# Handle
	draw_line(Vector2(pos.x + mug_w * 0.5, pos.y - mug_h * 0.8),
			  Vector2(pos.x + mug_w * 0.9, pos.y - mug_h * 0.5), mc, 1.2 * sc)
	draw_line(Vector2(pos.x + mug_w * 0.9, pos.y - mug_h * 0.5),
			  Vector2(pos.x + mug_w * 0.5, pos.y - mug_h * 0.2), mc, 1.2 * sc)


func _draw_beer_vendor(vendor: Dictionary) -> void:
	var vx := float(vendor["x"])
	var vy := float(vendor["y"])
	var walk_phase := float(vendor["walk_phase"])
	var paused := bool(vendor["paused"])
	var side_val := int(vendor["side"])
	var sc := 1.2  # Vendors are slightly larger (closer to viewer)

	var skin_col := Color(0.65, 0.5, 0.38, 0.9)
	var apron_col := Color(0.85, 0.8, 0.7, 0.9)
	var pants_col := Color(0.3, 0.25, 0.2, 0.9)

	# Walk bob
	var bob := 0.0
	if not paused:
		bob = absf(sin(walk_phase)) * 2.0

	if side_val in [0, 1]:
		# Vertical sides - draw as walking left/right
		var dir := 1 if int(vendor["direction"]) > 0 else -1

		# Legs walking
		var leg_swing := sin(walk_phase) * 4.0 if not paused else 0.0
		draw_line(Vector2(vx - 2, vy - bob), Vector2(vx - 2 + leg_swing, vy - bob + 6 * sc), pants_col, 2.2 * sc)
		draw_line(Vector2(vx + 2, vy - bob), Vector2(vx + 2 - leg_swing, vy - bob + 6 * sc), pants_col, 2.2 * sc)

		# Torso
		draw_line(Vector2(vx, vy - bob), Vector2(vx, vy - bob - 9 * sc), apron_col, 7 * sc)

		# Arms carrying tray
		var tray_y := vy - bob - 5 * sc
		draw_line(Vector2(vx - 4 * sc, vy - bob - 6 * sc), Vector2(vx - 6 * sc, tray_y), skin_col, 2 * sc)
		draw_line(Vector2(vx + 4 * sc, vy - bob - 6 * sc), Vector2(vx + 6 * sc, tray_y), skin_col, 2 * sc)

		# Tray
		var tray_col := Color(0.45, 0.35, 0.25, 0.9)
		draw_rect(Rect2(vx - 8 * sc, tray_y - 1, 16 * sc, 2), tray_col)

		# Beer mugs on tray
		for m in range(3):
			var mx := vx + (float(m) - 1.0) * 4.0 * sc
			_draw_beer_mug(Vector2(mx, tray_y - 1), sc * 0.6, 0.9, 0.0)

		# Head
		var head_y := vy - bob - 11 * sc
		draw_circle(Vector2(vx, head_y), 4.0 * sc, skin_col)
		# Vendor hat/cap
		var vendor_hat := Color(0.6, 0.15, 0.1, 0.9)
		draw_rect(Rect2(vx - 5 * sc, head_y - 4 * sc, 10 * sc, 3 * sc), vendor_hat)
		draw_rect(Rect2(vx - 3.5 * sc, head_y - 6 * sc, 7 * sc, 3 * sc), vendor_hat)
	else:
		# Horizontal sides - draw as walking up/down
		var leg_swing := sin(walk_phase) * 3.0 if not paused else 0.0
		var facing := 1.0 if side_val == 2 else -1.0

		draw_line(Vector2(vx - bob * facing, vy - 2), Vector2(vx - bob * facing - 5 * sc * facing, vy - 2 + leg_swing), pants_col, 2.2 * sc)
		draw_line(Vector2(vx - bob * facing, vy + 2), Vector2(vx - bob * facing - 5 * sc * facing, vy + 2 - leg_swing), pants_col, 2.2 * sc)

		draw_line(Vector2(vx - bob * facing, vy), Vector2(vx - bob * facing + 9 * sc * facing, vy), apron_col, 7 * sc)

		var tray_x := vx - bob * facing + 5 * sc * facing
		draw_line(Vector2(vx - bob * facing + 6 * sc * facing, vy - 4 * sc), Vector2(tray_x, vy - 6 * sc), skin_col, 2 * sc)
		draw_line(Vector2(vx - bob * facing + 6 * sc * facing, vy + 4 * sc), Vector2(tray_x, vy + 6 * sc), skin_col, 2 * sc)

		var tray_col := Color(0.45, 0.35, 0.25, 0.9)
		draw_rect(Rect2(tray_x - 1, vy - 8 * sc, 2, 16 * sc), tray_col)

		for m in range(3):
			var my := vy + (float(m) - 1.0) * 4.0 * sc
			_draw_beer_mug(Vector2(tray_x, my), sc * 0.6, 0.9, 0.0)

		var head_x := vx - bob * facing + 11 * sc * facing
		draw_circle(Vector2(head_x, vy), 4.0 * sc, skin_col)
		var vendor_hat := Color(0.6, 0.15, 0.1, 0.9)
		draw_rect(Rect2(head_x - 4 * sc * absf(facing), vy - 5 * sc, 3 * sc, 10 * sc), vendor_hat)


func _draw_speech_bubbles() -> void:
	var font := ThemeDB.fallback_font
	for bubble: Dictionary in _speech_bubbles:
		var bx := float(bubble["x"])
		var by := float(bubble["y"])
		var text: String = bubble["text"]
		var timer := float(bubble["timer"])
		var duration := float(bubble["duration"])

		var life_t := timer / duration
		var alpha := 1.0
		if life_t > 0.85:
			alpha = (1.0 - life_t) / 0.15
		elif life_t < 0.2:
			alpha = life_t / 0.2

		var float_y := (1.0 - life_t) * 18.0
		by -= float_y

		# Pop-in scale
		var pop_scale := 1.0
		if life_t > 0.9:
			pop_scale = (1.0 - life_t) / 0.1
			pop_scale = pop_scale * 1.2  # Slight overshoot

		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		var pad := 5.0 * pop_scale
		var bg_rect := Rect2(
			bx - pad, by - text_size.y * pop_scale - pad,
			(text_size.x + pad * 2) * pop_scale,
			(text_size.y + pad * 2) * pop_scale
		)

		var bg_col := Color(0.95, 0.92, 0.85, 0.9 * alpha)
		var border_col := Color(0.3, 0.25, 0.2, 0.75 * alpha)
		var shadow_col := Color(0.1, 0.08, 0.05, 0.3 * alpha)

		# Shadow
		draw_rect(Rect2(bg_rect.position + Vector2(2, 2), bg_rect.size), shadow_col)
		# Bubble
		draw_rect(bg_rect, bg_col)
		draw_rect(bg_rect, border_col, false, 1.5)

		# Tail
		var tail_pts := PackedVector2Array([
			Vector2(bx + 4, by + pad * 0.5),
			Vector2(bx + 10, by + pad * 0.5 + 8),
			Vector2(bx + 14, by + pad * 0.5),
		])
		draw_colored_polygon(tail_pts, bg_col)

		var text_col := Color(0.15, 0.1, 0.05, alpha)
		draw_string(font, Vector2(bx, by), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, text_col)


func _spawn_shout(shouts: Array, intensity: float = 1.0) -> void:
	if _spectators.is_empty():
		return
	if randf() > VisualTheme.CROWD_SHOUT_CHANCE * intensity:
		return

	var candidates: Array[int] = []
	for i in range(_spectators.size()):
		if int(_spectators[i]["row"]) < 2:
			candidates.append(i)
	if candidates.is_empty():
		return

	var spec_idx := candidates[randi() % candidates.size()]
	var spec := _spectators[spec_idx]
	var text: String = shouts[randi() % shouts.size()]

	var bx := float(spec["x"])
	var by := float(spec["y"])
	var side := int(spec["side"])
	match side:
		0: by -= 25
		1: by += 30
		2: bx -= 25
		3: bx += 25

	var duration := 2.0 + randf() * 1.0
	_speech_bubbles.append({
		"x": bx, "y": by, "text": text,
		"timer": duration, "duration": duration,
	})

	while _speech_bubbles.size() > 5:
		_speech_bubbles.remove_at(0)


func _spawn_vendor_shout(vendor: Dictionary) -> void:
	var text: String = SHOUTS_BEER[randi() % SHOUTS_BEER.size()]
	var vx := float(vendor["x"])
	var vy := float(vendor["y"])
	var side_val := int(vendor["side"])
	match side_val:
		0: vy -= 20
		1: vy += 25
		2: vx -= 20
		3: vx += 25

	var duration := 2.5
	_speech_bubbles.append({
		"x": vx, "y": vy, "text": text,
		"timer": duration, "duration": duration,
	})
	while _speech_bubbles.size() > 5:
		_speech_bubbles.remove_at(0)


# === Idle shout timer ===
var _idle_timer: float = 0.0
const IDLE_SHOUT_INTERVAL := 8.0

func _check_idle_shout(delta: float) -> void:
	_idle_timer += delta
	if _idle_timer >= IDLE_SHOUT_INTERVAL:
		_idle_timer = 0.0
		if randf() < 0.35:
			_spawn_shout(SHOUTS_IDLE, 0.6)


# === Event Reactions ===

func _trigger_reaction(reaction_type: String, intensity: float = 1.0) -> void:
	_global_react_timer = VisualTheme.CROWD_REACT_DURATION
	_global_react_type = reaction_type

	for i in range(_spectators.size()):
		var spec: Dictionary = _spectators[i]
		var delay := sin(float(i) * 1.3) * 0.15
		spec["react_timer"] = VisualTheme.CROWD_REACT_DURATION * intensity + delay

		# Make some front-row spectators jump during big reactions
		if int(spec["row"]) < 3 and intensity >= 0.7:
			if sin(float(i) * 3.7) > 0.3:
				spec["jump_timer"] = 0.6 + delay
				# Also switch some to cheering pose temporarily
				if sin(float(i) * 5.1) > 0.4:
					spec["pose"] = Pose.CHEERING

	# Trigger wave on kills
	if reaction_type == "cheer" and intensity >= 1.0:
		_wave_timer = 0.0


func _on_champion_attacked(_attacker_id: String, _target_id: String, damage: int) -> void:
	if damage >= 6:
		_trigger_reaction("cheer", 1.0)
		_spawn_shout(SHOUTS_BIG_HIT, 1.5)
	elif damage >= 4:
		_trigger_reaction("gasp", 1.0)
		_spawn_shout(SHOUTS_BIG_HIT, 1.0)
	elif damage >= 3:
		_trigger_reaction("gasp", 0.7)
		_spawn_shout(SHOUTS_BIG_HIT, 0.5)
	elif damage >= 2:
		_trigger_reaction("stir", 0.5)
	else:
		_trigger_reaction("stir", 0.3)


func _on_champion_died(_champion_id: String, _killer_id: String) -> void:
	_trigger_reaction("cheer", 1.0)
	_spawn_shout(SHOUTS_KILL, 2.0)


func _on_champion_healed(_champion_id: String, amount: int, _source: String) -> void:
	if amount >= 3:
		_trigger_reaction("stir", 0.4)
		_spawn_shout(SHOUTS_HEAL, 0.6)


func _on_card_played(_player_id: int, _card_id: String, _targets: Array, _caster_id: String = "") -> void:
	_trigger_reaction("stir", 0.3)
	_spawn_shout(SHOUTS_SPELL, 0.3)


func _on_game_started(_p1_champs: Array, _p2_champs: Array) -> void:
	_trigger_reaction("cheer", 0.8)
	_spawn_shout(SHOUTS_CHEER, 1.5)


func _on_game_ended(_winner: int, _reason: String) -> void:
	_trigger_reaction("cheer", 1.0)
	_spawn_shout(SHOUTS_CHEER, 2.0)
