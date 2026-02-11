extends Node2D
class_name BoardVFXLayer
## BoardVFXLayer - Centralized procedural particle system for board visual effects
## Renders all particles in a single _draw() call for performance.
## Create two instances: vfx_below (under champions) and vfx_above (over champions).

const MAX_PARTICLES := 400

# Particle pool
var _particles: Array[Dictionary] = []
var _ambient_timer: float = 0.0
var _pit_tiles: Array[Vector2i] = []  # Cached pit tile positions
var _tile_size: int = 64

# Types of particles
enum ParticleType {
	DUST, SPARK, MAGIC, CAST_SHIMMER, DEATH_RING, DEATH_SOUL,
	DEATH_DEBRIS, HEAL, AMBIENT, PIT_SMOKE, RANGED_TRAIL,
	ENERGY_BEAM, CAST_BURST, SHIELD_FLASH, EQUIP_GLOW, SMOKE_POOF,
	LIGHTNING_ARC, HOLY_PILLAR, SHADOW_TENDRIL, BLOOD_DROP,
	LEAF_SWIRL, GROUND_CRACK, ARROW_VOLLEY, FLASK_BUBBLE,
	MIRROR_SHARD, DAGGER_GLINT, CHAIN_LINK, SHOCKWAVE
}


func setup(tile_sz: int, pits: Array[Vector2i]) -> void:
	"""Initialize VFX layer with tile size and pit positions."""
	_tile_size = tile_sz
	_pit_tiles = pits


func _process(delta: float) -> void:
	# Update all particles
	var i := _particles.size() - 1
	while i >= 0:
		var p: Dictionary = _particles[i]
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) >= float(p["lifetime"]):
			_particles.remove_at(i)
		else:
			_update_particle(p, delta)
		i -= 1

	# Ambient effects
	_ambient_timer += delta
	if _ambient_timer > 0.3:
		_ambient_timer -= 0.3
		_spawn_ambient_dust()
		_spawn_pit_smoke()

	if _particles.size() > 0:
		queue_redraw()


func _update_particle(p: Dictionary, delta: float) -> void:
	"""Update a single particle's position and properties."""
	p["x"] = float(p["x"]) + float(p["vx"]) * delta
	p["y"] = float(p["y"]) + float(p["vy"]) * delta

	# Apply gravity for some types
	var ptype: int = int(p["type"])
	match ptype:
		ParticleType.DUST:
			p["vy"] = float(p["vy"]) - 15.0 * delta  # Float upward
		ParticleType.SPARK:
			p["vy"] = float(p["vy"]) + 80.0 * delta  # Fall with gravity
			p["vx"] = float(p["vx"]) * 0.96  # Drag
		ParticleType.MAGIC:
			# Spiral inward
			var angle := float(p["angle"]) + 4.0 * delta
			var radius := float(p["radius"]) - 20.0 * delta
			p["angle"] = angle
			p["radius"] = maxf(radius, 0.0)
			p["x"] = float(p["cx"]) + cos(angle) * radius
			p["y"] = float(p["cy"]) + sin(angle) * radius
		ParticleType.CAST_SHIMMER:
			p["vy"] = float(p["vy"]) - 25.0 * delta  # Rise faster
		ParticleType.DEATH_RING:
			p["radius"] = float(p["radius"]) + 40.0 * delta  # Expand
		ParticleType.DEATH_SOUL:
			p["vy"] = float(p["vy"]) - 20.0 * delta
			p["x"] = float(p["x"]) + sin(float(p["age"]) * 5.0) * 0.8
		ParticleType.DEATH_DEBRIS:
			p["vy"] = float(p["vy"]) + 60.0 * delta
		ParticleType.HEAL:
			p["vy"] = float(p["vy"]) - 10.0 * delta
			p["x"] = float(p["x"]) + sin(float(p["age"]) * 6.0 + float(p.get("phase", 0.0))) * 0.5
		ParticleType.AMBIENT:
			p["x"] = float(p["x"]) + sin(float(p["age"]) * 1.5 + float(p.get("phase", 0.0))) * 0.3
		ParticleType.PIT_SMOKE:
			p["vy"] = float(p["vy"]) - 8.0 * delta
			p["x"] = float(p["x"]) + sin(float(p["age"]) * 2.0) * 0.4
		ParticleType.ENERGY_BEAM:
			# Beam wobble intensifies then fades
			p["wobble_phase"] = float(p.get("wobble_phase", 0.0)) + VisualTheme.ENERGY_BEAM_SPEED * delta
		ParticleType.CAST_BURST:
			# Radial expansion with deceleration
			p["vx"] = float(p["vx"]) * (1.0 - 2.0 * delta)
			p["vy"] = float(p["vy"]) * (1.0 - 2.0 * delta)
		ParticleType.SHIELD_FLASH:
			# Expanding ring
			p["radius"] = float(p["radius"]) + VisualTheme.VFX_SHIELD_EXPAND_SPEED * delta
		ParticleType.EQUIP_GLOW:
			# Orbit around center then converge
			var eq_angle := float(p["angle"]) + 5.0 * delta
			var eq_radius := float(p["radius"]) * (1.0 - float(p["age"]) / float(p["lifetime"]))
			p["angle"] = eq_angle
			p["radius"] = eq_radius
			p["x"] = float(p["cx"]) + cos(eq_angle) * eq_radius
			p["y"] = float(p["cy"]) + sin(eq_angle) * eq_radius
		ParticleType.LIGHTNING_ARC:
			p["wobble_phase"] = float(p.get("wobble_phase", 0.0)) + 25.0 * delta
		ParticleType.HOLY_PILLAR:
			p["vy"] = float(p["vy"]) - 30.0 * delta
			p["x"] = float(p["x"]) + sin(float(p["age"]) * 8.0 + float(p.get("phase", 0.0))) * 0.3
		ParticleType.SHADOW_TENDRIL:
			var tend_angle := float(p["angle"]) + float(p.get("angle_speed", 2.0)) * delta
			var tend_radius := float(p["radius"]) + 20.0 * delta
			p["angle"] = tend_angle
			p["radius"] = tend_radius
			p["x"] = float(p["cx"]) + cos(tend_angle) * tend_radius
			p["y"] = float(p["cy"]) + sin(tend_angle) * tend_radius + sin(tend_angle * 3.0) * 2.0
		ParticleType.BLOOD_DROP:
			p["vy"] = float(p["vy"]) + 120.0 * delta  # Heavy gravity
			p["vx"] = float(p["vx"]) * 0.98
		ParticleType.LEAF_SWIRL:
			var leaf_angle := float(p["angle"]) + 3.5 * delta
			var leaf_radius := float(p["radius"]) * (1.0 - float(p["age"]) / float(p["lifetime"]) * 0.4)
			p["angle"] = leaf_angle
			p["radius"] = leaf_radius
			p["x"] = float(p["cx"]) + cos(leaf_angle) * leaf_radius
			p["y"] = float(p["cy"]) + sin(leaf_angle) * leaf_radius
			p["vy"] = float(p["vy"]) - 15.0 * delta  # Rise upward
		ParticleType.GROUND_CRACK:
			# Expand outward from center along angle, decelerate
			p["vx"] = float(p["vx"]) * (1.0 - 3.0 * delta)
			p["vy"] = float(p["vy"]) * (1.0 - 3.0 * delta)
		ParticleType.ARROW_VOLLEY:
			p["vy"] = float(p["vy"]) + 60.0 * delta  # Fall
		ParticleType.FLASK_BUBBLE:
			p["vy"] = float(p["vy"]) - 12.0 * delta  # Float up
			p["x"] = float(p["x"]) + sin(float(p["age"]) * 7.0 + float(p.get("phase", 0.0))) * 0.6
			p["size"] = float(p["size"]) * (1.0 + 0.3 * delta)  # Grow slightly
		ParticleType.MIRROR_SHARD:
			p["angle"] = float(p.get("angle", 0.0)) + 8.0 * delta
			p["vx"] = float(p["vx"]) * (1.0 - 1.5 * delta)
			p["vy"] = float(p["vy"]) * (1.0 - 1.5 * delta)
		ParticleType.DAGGER_GLINT:
			pass  # Linear motion, no extra update needed
		ParticleType.CHAIN_LINK:
			var ch_angle := float(p["angle"]) + 4.0 * delta
			var ch_radius := float(p["radius"])
			p["angle"] = ch_angle
			p["x"] = float(p["cx"]) + cos(ch_angle) * ch_radius
			p["y"] = float(p["cy"]) + sin(ch_angle) * ch_radius
		ParticleType.SHOCKWAVE:
			p["radius"] = float(p["radius"]) + 80.0 * delta


func _draw() -> void:
	for p: Dictionary in _particles:
		var t := float(p["age"]) / float(p["lifetime"])
		var alpha := 1.0 - t  # Default fade out
		var ptype: int = int(p["type"])
		var col: Color = p["color"] as Color

		match ptype:
			ParticleType.DUST:
				alpha = (1.0 - t) * 0.6
				col.a = alpha
				draw_circle(Vector2(float(p["x"]), float(p["y"])), float(p["size"]) * (1.0 - t * 0.5), col)

			ParticleType.SPARK:
				alpha = (1.0 - t * t) * 0.9
				col.a = alpha
				var px := float(p["x"])
				var py := float(p["y"])
				var vx := float(p["vx"])
				var vy := float(p["vy"])
				var tail_len := Vector2(vx, vy).normalized() * float(p["size"]) * 3.0
				draw_line(Vector2(px, py), Vector2(px, py) - tail_len, col, 1.5)

			ParticleType.MAGIC:
				alpha = (1.0 - t) * 0.8
				col.a = alpha
				var sz := float(p["size"]) * (0.5 + (1.0 - t) * 0.5)
				draw_circle(Vector2(float(p["x"]), float(p["y"])), sz, col)

			ParticleType.CAST_SHIMMER:
				# Twinkle: pulse alpha
				alpha = (1.0 - t) * (0.5 + sin(float(p["age"]) * 12.0) * 0.5)
				col.a = alpha
				var sz := float(p["size"]) * (1.0 - t * 0.3)
				# Draw as tiny star (4-point)
				var cx := float(p["x"])
				var cy := float(p["y"])
				draw_line(Vector2(cx - sz, cy), Vector2(cx + sz, cy), col, 1.0)
				draw_line(Vector2(cx, cy - sz), Vector2(cx, cy + sz), col, 1.0)

			ParticleType.DEATH_RING:
				alpha = (1.0 - t) * 0.8
				col.a = alpha
				draw_arc(Vector2(float(p["cx"]), float(p["cy"])), float(p["radius"]),
					0, TAU, 32, col, 2.5 * (1.0 - t))

			ParticleType.DEATH_SOUL:
				alpha = (1.0 - t * t) * 0.5
				col.a = alpha
				var sz := float(p["size"]) * (1.0 + t * 0.5)
				draw_circle(Vector2(float(p["x"]), float(p["y"])), sz, col)

			ParticleType.DEATH_DEBRIS:
				alpha = (1.0 - t) * 0.7
				col.a = alpha
				var sz := float(p["size"]) * (1.0 - t * 0.5)
				draw_rect(Rect2(float(p["x"]) - sz, float(p["y"]) - sz, sz * 2, sz * 2), col)

			ParticleType.HEAL:
				alpha = (1.0 - t) * 0.7
				col.a = alpha
				draw_circle(Vector2(float(p["x"]), float(p["y"])), float(p["size"]) * (1.0 - t * 0.3), col)

			ParticleType.AMBIENT:
				# Very faint, slow fade
				alpha = sin(t * PI) * 0.08
				col.a = alpha
				draw_circle(Vector2(float(p["x"]), float(p["y"])), float(p["size"]), col)

			ParticleType.PIT_SMOKE:
				alpha = sin(t * PI) * 0.3
				col.a = alpha
				var sz := float(p["size"]) * (1.0 + t * 0.8)
				draw_circle(Vector2(float(p["x"]), float(p["y"])), sz, col)

			ParticleType.RANGED_TRAIL:
				alpha = (1.0 - t) * 0.8
				col.a = alpha
				draw_circle(Vector2(float(p["x"]), float(p["y"])), float(p["size"]) * (1.0 - t), col)

			ParticleType.ENERGY_BEAM:
				_draw_energy_beam(p, t)

			ParticleType.CAST_BURST:
				# Expanding colored dot with trail
				alpha = (1.0 - t * t) * 0.85
				col.a = alpha
				var sz := float(p["size"]) * (1.0 - t * 0.4)
				draw_circle(Vector2(float(p["x"]), float(p["y"])), sz, col)
				# Small glow core
				var core := col
				core.a = alpha * 0.5
				draw_circle(Vector2(float(p["x"]), float(p["y"])), sz * 1.8, core)

			ParticleType.SHIELD_FLASH:
				# Expanding protective arc/ring
				alpha = (1.0 - t) * 0.8
				col.a = alpha
				var r := float(p["radius"])
				draw_arc(Vector2(float(p["cx"]), float(p["cy"])), r,
					0, TAU, 24, col, 2.0 * (1.0 - t))
				# Inner shimmer ring
				var inner := col
				inner.a = alpha * 0.3
				draw_arc(Vector2(float(p["cx"]), float(p["cy"])), r * 0.7,
					0, TAU, 16, inner, 1.0)

			ParticleType.EQUIP_GLOW:
				# Metallic sparkle orbiting then converging
				alpha = (1.0 - t * 0.5) * 0.8
				col.a = alpha
				var sz := float(p["size"]) * (0.6 + sin(float(p["age"]) * 10.0) * 0.4)
				var cx := float(p["x"])
				var cy := float(p["y"])
				# Draw as diamond shape
				var pts := PackedVector2Array([
					Vector2(cx, cy - sz),
					Vector2(cx + sz * 0.6, cy),
					Vector2(cx, cy + sz),
					Vector2(cx - sz * 0.6, cy)
				])
				draw_colored_polygon(pts, col)

			ParticleType.SMOKE_POOF:
				# Expanding smoke cloud that billows outward and fades
				var smoke_t := clampf(t, 0.0, 1.0)
				alpha = sin(smoke_t * PI) * 0.65  # Fade in then out
				if smoke_t > 0.6:
					alpha *= (1.0 - (smoke_t - 0.6) / 0.4)  # Faster fade at end
				col.a = alpha
				var expand := 1.0 + smoke_t * 2.5  # Grow over time
				var sz2 := float(p["size"]) * expand
				draw_circle(Vector2(float(p["x"]), float(p["y"])), sz2, col)
				# Inner brighter core
				var inner2 := col
				inner2.a = alpha * 0.4
				draw_circle(Vector2(float(p["x"]), float(p["y"])), sz2 * 0.5, inner2)

			ParticleType.LIGHTNING_ARC:
				_draw_lightning_arc(p, t)

			ParticleType.HOLY_PILLAR:
				alpha = (1.0 - t) * 0.75
				col.a = alpha
				var hp_sz := float(p["size"]) * (1.0 + t * 0.3)
				draw_circle(Vector2(float(p["x"]), float(p["y"])), hp_sz, col)
				# Sparkle core
				var hp_core := Color(1.0, 1.0, 0.8, alpha * 0.6)
				draw_circle(Vector2(float(p["x"]), float(p["y"])), hp_sz * 0.4, hp_core)

			ParticleType.SHADOW_TENDRIL:
				alpha = (1.0 - t) * 0.7
				col.a = alpha
				var st_pos := Vector2(float(p["x"]), float(p["y"]))
				var st_cx := Vector2(float(p["cx"]), float(p["cy"]))
				# Draw wavy line from center to current position
				var st_segments := 6
				var prev_pt := st_cx
				for si in range(1, st_segments + 1):
					var st_t := float(si) / float(st_segments)
					var pt := st_cx.lerp(st_pos, st_t)
					var wave := sin(st_t * PI * 2.0 + float(p["age"]) * 5.0) * 3.0
					var st_perp := (st_pos - st_cx).normalized()
					pt += Vector2(-st_perp.y, st_perp.x) * wave
					var seg_col := col
					seg_col.a = alpha * (1.0 - st_t * 0.3)
					draw_line(prev_pt, pt, seg_col, 2.0 * (1.0 - t * 0.5))
					prev_pt = pt

			ParticleType.BLOOD_DROP:
				alpha = (1.0 - t) * 0.85
				col.a = alpha
				var bd_pos := Vector2(float(p["x"]), float(p["y"]))
				var bd_sz := float(p["size"])
				# Teardrop shape: circle + small trail
				draw_circle(bd_pos, bd_sz, col)
				var bd_vy := float(p["vy"])
				if bd_vy > 20.0:
					# Splatter streaks when falling fast
					draw_line(bd_pos, bd_pos - Vector2(0, bd_sz * 2.0), col, 1.0)

			ParticleType.LEAF_SWIRL:
				alpha = (1.0 - t) * 0.8
				col.a = alpha
				var lf_pos := Vector2(float(p["x"]), float(p["y"]))
				var lf_sz := float(p["size"])
				var lf_angle := float(p.get("angle", 0.0))
				# Draw as rotated ellipse (leaf shape)
				var lf_pts := PackedVector2Array()
				for li in range(8):
					var la := float(li) / 8.0 * TAU
					var lx := cos(la) * lf_sz
					var ly := sin(la) * lf_sz * 0.4
					# Rotate by leaf angle
					var rx := lx * cos(lf_angle) - ly * sin(lf_angle)
					var ry := lx * sin(lf_angle) + ly * cos(lf_angle)
					lf_pts.append(lf_pos + Vector2(rx, ry))
				draw_colored_polygon(lf_pts, col)

			ParticleType.GROUND_CRACK:
				alpha = (1.0 - t) * 0.8
				col.a = alpha
				var gc_pos := Vector2(float(p["x"]), float(p["y"]))
				var gc_sz := float(p["size"]) * (1.0 + t * 0.5)
				# Draw as jagged line from origin
				var gc_dir := Vector2(float(p["vx"]), float(p["vy"]))
				if gc_dir.length() > 0.1:
					gc_dir = gc_dir.normalized()
				else:
					gc_dir = Vector2(1, 0)
				var gc_end := gc_pos + gc_dir * gc_sz * 3.0
				draw_line(gc_pos, gc_end, col, 2.5 * (1.0 - t))
				# Branch crack
				var gc_mid := gc_pos.lerp(gc_end, 0.6)
				var gc_branch := gc_mid + Vector2(-gc_dir.y, gc_dir.x) * gc_sz * 1.5
				var branch_col := col
				branch_col.a = alpha * 0.6
				draw_line(gc_mid, gc_branch, branch_col, 1.5 * (1.0 - t))

			ParticleType.ARROW_VOLLEY:
				alpha = (1.0 - t) * 0.85
				col.a = alpha
				var av_pos := Vector2(float(p["x"]), float(p["y"]))
				var av_vx := float(p["vx"])
				var av_vy := float(p["vy"])
				var av_dir := Vector2(av_vx, av_vy).normalized()
				var av_sz := float(p["size"])
				# Arrow: line with small V at tip
				var av_tip := av_pos
				var av_tail := av_pos - av_dir * av_sz * 4.0
				draw_line(av_tail, av_tip, col, 1.5)
				# Arrowhead
				var av_perp := Vector2(-av_dir.y, av_dir.x)
				draw_line(av_tip, av_tip - av_dir * av_sz + av_perp * av_sz * 0.5, col, 1.5)
				draw_line(av_tip, av_tip - av_dir * av_sz - av_perp * av_sz * 0.5, col, 1.5)

			ParticleType.FLASK_BUBBLE:
				alpha = sin(t * PI) * 0.7
				col.a = alpha
				var fb_pos := Vector2(float(p["x"]), float(p["y"]))
				var fb_sz := float(p["size"])
				# Bubble: circle with highlight
				draw_arc(fb_pos, fb_sz, 0, TAU, 16, col, 1.5)
				# Highlight dot
				var fb_hl := Color(1, 1, 1, alpha * 0.5)
				draw_circle(fb_pos + Vector2(-fb_sz * 0.3, -fb_sz * 0.3), fb_sz * 0.25, fb_hl)

			ParticleType.MIRROR_SHARD:
				alpha = (1.0 - t) * 0.8
				col.a = alpha
				var ms_pos := Vector2(float(p["x"]), float(p["y"]))
				var ms_sz := float(p["size"])
				var ms_angle := float(p.get("angle", 0.0))
				# Angular reflective shard (triangle)
				var ms_pts := PackedVector2Array([
					ms_pos + Vector2(cos(ms_angle), sin(ms_angle)) * ms_sz,
					ms_pos + Vector2(cos(ms_angle + 2.0), sin(ms_angle + 2.0)) * ms_sz * 0.7,
					ms_pos + Vector2(cos(ms_angle + 4.0), sin(ms_angle + 4.0)) * ms_sz * 0.5
				])
				draw_colored_polygon(ms_pts, col)
				# Bright edge highlight
				var ms_hl := Color(1, 1, 1, alpha * 0.6)
				draw_line(ms_pts[0], ms_pts[1], ms_hl, 1.0)

			ParticleType.DAGGER_GLINT:
				# Fast slash line with bright tip
				var dg_alpha: float
				if t < 0.3:
					dg_alpha = t / 0.3
				else:
					dg_alpha = (1.0 - (t - 0.3) / 0.7) * 0.9
				col.a = dg_alpha
				var dg_pos := Vector2(float(p["x"]), float(p["y"]))
				var dg_dir := Vector2(float(p["vx"]), float(p["vy"]))
				if dg_dir.length() > 0.1:
					dg_dir = dg_dir.normalized()
				var dg_len := float(p["size"]) * 5.0
				var dg_tail := dg_pos - dg_dir * dg_len
				# Glow
				var dg_glow := col
				dg_glow.a = dg_alpha * 0.3
				draw_line(dg_tail, dg_pos, dg_glow, 4.0)
				# Core
				draw_line(dg_tail, dg_pos, col, 1.5)
				# Bright tip
				draw_circle(dg_pos, 2.0, Color(1, 1, 1, dg_alpha * 0.8))

			ParticleType.CHAIN_LINK:
				alpha = (1.0 - t) * 0.75
				col.a = alpha
				var cl_pos := Vector2(float(p["x"]), float(p["y"]))
				var cl_sz := float(p["size"])
				# Draw chain link as two overlapping ovals
				var cl_angle := float(p.get("angle", 0.0))
				draw_arc(cl_pos, cl_sz, cl_angle, cl_angle + PI, 8, col, 2.0)
				draw_arc(cl_pos, cl_sz * 0.6, cl_angle + PI, cl_angle + TAU, 8, col, 2.0)

			ParticleType.SHOCKWAVE:
				alpha = (1.0 - t) * 0.7
				col.a = alpha
				var sw_r := float(p["radius"])
				var sw_center := Vector2(float(p["cx"]), float(p["cy"]))
				draw_arc(sw_center, sw_r, 0, TAU, 32, col, 2.5 * (1.0 - t))
				# Second inner ring
				var sw_inner := col
				sw_inner.a = alpha * 0.4
				draw_arc(sw_center, sw_r * 0.6, 0, TAU, 24, sw_inner, 1.5 * (1.0 - t))


func _draw_energy_beam(p: Dictionary, t: float) -> void:
	"""Draw a segmented energy beam from source to target."""
	var from_x := float(p["from_x"])
	var from_y := float(p["from_y"])
	var to_x := float(p["to_x"])
	var to_y := float(p["to_y"])
	var col: Color = p["color"] as Color
	var wobble_phase := float(p.get("wobble_phase", 0.0))

	# Beam appears quickly then fades
	var beam_alpha: float
	if t < 0.15:
		beam_alpha = t / 0.15  # Quick fade in
	else:
		beam_alpha = (1.0 - (t - 0.15) / 0.85) * 0.9  # Slower fade out

	var segments := VisualTheme.ENERGY_BEAM_SEGMENTS
	var wobble_amp := VisualTheme.ENERGY_BEAM_WOBBLE * (1.0 - t * 0.5)
	var direction := Vector2(to_x - from_x, to_y - from_y)
	var length := direction.length()
	if length < 1.0:
		return
	var dir_norm := direction.normalized()
	var perp := Vector2(-dir_norm.y, dir_norm.x)

	var prev_point := Vector2(from_x, from_y)
	for i in range(1, segments + 1):
		var seg_t := float(i) / float(segments)
		var base_point := Vector2(from_x, from_y).lerp(Vector2(to_x, to_y), seg_t)
		# Add sine wobble perpendicular to beam direction
		var wobble := sin(seg_t * PI * 3.0 + wobble_phase) * wobble_amp * sin(seg_t * PI)
		var point := base_point + perp * wobble

		# Outer glow
		var glow_col := col
		glow_col.a = beam_alpha * 0.3
		draw_line(prev_point, point, glow_col, VisualTheme.ENERGY_BEAM_WIDTH * 3.0)
		# Core beam
		col.a = beam_alpha * 0.85
		draw_line(prev_point, point, col, VisualTheme.ENERGY_BEAM_WIDTH)
		# Bright inner core
		var core_col := VisualTheme.ENERGY_BEAM_GLOW
		core_col.a = beam_alpha * 0.6
		draw_line(prev_point, point, core_col, 1.0)
		prev_point = point


func _draw_lightning_arc(p: Dictionary, t: float) -> void:
	"""Draw a jagged segmented lightning bolt with branch forks."""
	var from_x := float(p["from_x"])
	var from_y := float(p["from_y"])
	var to_x := float(p["to_x"])
	var to_y := float(p["to_y"])
	var col: Color = p["color"] as Color
	var wobble_phase := float(p.get("wobble_phase", 0.0))

	var bolt_alpha: float
	if t < 0.1:
		bolt_alpha = t / 0.1
	else:
		bolt_alpha = (1.0 - (t - 0.1) / 0.9) * 0.95

	var direction := Vector2(to_x - from_x, to_y - from_y)
	var length := direction.length()
	if length < 1.0:
		return
	var dir_norm := direction.normalized()
	var perp := Vector2(-dir_norm.y, dir_norm.x)

	# Main bolt: jagged segments
	var segments := 10
	var jag_amp := 12.0 * (1.0 - t * 0.3)
	var prev_pt := Vector2(from_x, from_y)
	var branch_points: Array[Vector2] = []
	for i in range(1, segments + 1):
		var seg_t := float(i) / float(segments)
		var base_pt := Vector2(from_x, from_y).lerp(Vector2(to_x, to_y), seg_t)
		# Jagged offset: use sin with high frequency for that electric look
		var jag := sin(seg_t * 17.0 + wobble_phase) * jag_amp * sin(seg_t * PI)
		var pt := base_pt + perp * jag
		# Outer glow
		var glow := col
		glow.a = bolt_alpha * 0.25
		draw_line(prev_pt, pt, glow, 6.0)
		# Core
		col.a = bolt_alpha * 0.9
		draw_line(prev_pt, pt, col, 2.0)
		# White-hot center
		draw_line(prev_pt, pt, Color(1, 1, 1, bolt_alpha * 0.7), 1.0)
		# Mark branch points
		if i == 3 or i == 7:
			branch_points.append(pt)
		prev_pt = pt

	# Branch forks
	for bp in branch_points:
		var branch_dir := perp * (15.0 + sin(wobble_phase) * 8.0) + dir_norm * 10.0
		var branch_end := bp + branch_dir
		var bm := bp.lerp(branch_end, 0.5) + perp * sin(wobble_phase * 2.0) * 5.0
		var branch_col := col
		branch_col.a = bolt_alpha * 0.5
		draw_line(bp, bm, branch_col, 1.5)
		draw_line(bm, branch_end, branch_col, 1.0)


# === Spawn Methods ===

func _add_particle(data: Dictionary) -> void:
	"""Add a particle, respecting cap."""
	if _particles.size() >= MAX_PARTICLES:
		_particles.pop_front()  # Remove oldest
	_particles.append(data)


func spawn_dust_trail(world_pos: Vector2) -> void:
	"""Spawn dust particles when a champion moves to a tile."""
	for i in range(6):
		var offset_x := (sin(float(i) * 2.3) * 0.5 + 0.5) * float(_tile_size) * 0.6 - float(_tile_size) * 0.3
		var offset_y := float(_tile_size) * 0.3 + sin(float(i) * 3.7) * 4.0
		_add_particle({
			"type": ParticleType.DUST,
			"x": world_pos.x + offset_x,
			"y": world_pos.y + offset_y,
			"vx": (sin(float(i) * 1.7)) * 12.0,
			"vy": -8.0 - sin(float(i) * 2.1) * 10.0,
			"size": 2.0 + sin(float(i) * 4.3) * 1.0,
			"age": 0.0,
			"lifetime": 0.4 + sin(float(i) * 5.1) * 0.15,
			"color": VisualTheme.VFX_DUST,
		})


func spawn_melee_impact(world_pos: Vector2) -> void:
	"""Spawn spark lines radiating from impact point."""
	for i in range(12):
		var angle := float(i) / 12.0 * TAU + sin(float(i) * 7.1) * 0.3
		var speed := 60.0 + sin(float(i) * 3.3) * 30.0
		_add_particle({
			"type": ParticleType.SPARK,
			"x": world_pos.x,
			"y": world_pos.y,
			"vx": cos(angle) * speed,
			"vy": sin(angle) * speed,
			"size": 2.0 + sin(float(i) * 5.7) * 1.5,
			"age": 0.0,
			"lifetime": 0.3 + sin(float(i) * 2.9) * 0.1,
			"color": VisualTheme.VFX_SPARK,
		})


func spawn_ranged_trail(from_pos: Vector2, to_pos: Vector2) -> void:
	"""Spawn fading dots along a projectile path."""
	var count := 8
	for i in range(count):
		var t := float(i) / float(count - 1)
		var pos := from_pos.lerp(to_pos, t)
		_add_particle({
			"type": ParticleType.RANGED_TRAIL,
			"x": pos.x,
			"y": pos.y,
			"vx": 0.0,
			"vy": 0.0,
			"size": 3.0 - t * 1.5,
			"age": t * 0.1,  # Stagger appearance
			"lifetime": 0.5,
			"color": VisualTheme.VFX_RANGED,
		})


func spawn_magic_swirl(world_pos: Vector2, color: Color = VisualTheme.VFX_MAGIC) -> void:
	"""Spawn orbiting particles spiraling inward to a target."""
	for i in range(15):
		var angle := float(i) / 15.0 * TAU
		var radius := 25.0 + sin(float(i) * 3.1) * 8.0
		_add_particle({
			"type": ParticleType.MAGIC,
			"x": world_pos.x + cos(angle) * radius,
			"y": world_pos.y + sin(angle) * radius,
			"vx": 0.0,
			"vy": 0.0,
			"cx": world_pos.x,
			"cy": world_pos.y,
			"angle": angle,
			"radius": radius,
			"size": 2.5 + sin(float(i) * 4.7) * 1.0,
			"age": 0.0,
			"lifetime": 0.7 + sin(float(i) * 2.3) * 0.15,
			"color": color,
		})


func spawn_cast_shimmer(world_pos: Vector2) -> void:
	"""Spawn sparkles rising from a caster position."""
	for i in range(10):
		var offset_x := (sin(float(i) * 3.7) * 0.5) * float(_tile_size) * 0.5
		_add_particle({
			"type": ParticleType.CAST_SHIMMER,
			"x": world_pos.x + offset_x,
			"y": world_pos.y + float(_tile_size) * 0.2,
			"vx": sin(float(i) * 2.3) * 8.0,
			"vy": -20.0 - sin(float(i) * 4.1) * 15.0,
			"size": 3.0 + sin(float(i) * 5.9) * 1.5,
			"age": sin(float(i) * 1.7) * 0.5 * 0.1,  # Slight stagger
			"lifetime": 0.6 + sin(float(i) * 3.3) * 0.15,
			"color": VisualTheme.VFX_CAST,
		})


func spawn_death_vfx(world_pos: Vector2) -> void:
	"""Spawn dark ring + debris + soul wisps for champion death."""
	# Dark expanding ring
	_add_particle({
		"type": ParticleType.DEATH_RING,
		"x": world_pos.x,
		"y": world_pos.y,
		"vx": 0.0,
		"vy": 0.0,
		"cx": world_pos.x,
		"cy": world_pos.y,
		"radius": 5.0,
		"size": 0.0,
		"age": 0.0,
		"lifetime": 0.8,
		"color": VisualTheme.VFX_DEATH_RING,
	})

	# Debris chunks
	for i in range(8):
		var angle := float(i) / 8.0 * TAU + sin(float(i) * 5.3) * 0.4
		var speed := 30.0 + sin(float(i) * 3.7) * 20.0
		_add_particle({
			"type": ParticleType.DEATH_DEBRIS,
			"x": world_pos.x,
			"y": world_pos.y,
			"vx": cos(angle) * speed,
			"vy": sin(angle) * speed - 40.0,
			"size": 2.0 + sin(float(i) * 2.9) * 1.0,
			"age": 0.0,
			"lifetime": 0.5 + sin(float(i) * 4.1) * 0.15,
			"color": Color(0.3, 0.25, 0.2, 0.7),
		})

	# Soul wisps rising
	for i in range(4):
		var offset_x := sin(float(i) * 4.3) * 10.0
		_add_particle({
			"type": ParticleType.DEATH_SOUL,
			"x": world_pos.x + offset_x,
			"y": world_pos.y,
			"vx": sin(float(i) * 2.7) * 5.0,
			"vy": -15.0,
			"size": 3.0 + sin(float(i) * 3.1) * 1.5,
			"age": 0.0,
			"lifetime": 1.2,
			"color": VisualTheme.VFX_DEATH_SOUL,
			"phase": float(i) * 1.5,
		})


func spawn_heal_sparkles(world_pos: Vector2) -> void:
	"""Spawn green/golden sparkles rising from healed champion."""
	for i in range(10):
		var offset_x := (sin(float(i) * 3.1) * 0.5) * float(_tile_size) * 0.4
		var color: Color = VisualTheme.VFX_HEAL if i % 2 == 0 else VisualTheme.VFX_HEAL_GOLD
		_add_particle({
			"type": ParticleType.HEAL,
			"x": world_pos.x + offset_x,
			"y": world_pos.y + 5.0,
			"vx": sin(float(i) * 2.7) * 6.0,
			"vy": -12.0 - sin(float(i) * 4.3) * 8.0,
			"size": 2.5 + sin(float(i) * 5.1) * 1.0,
			"age": 0.0,
			"lifetime": 0.8 + sin(float(i) * 3.7) * 0.2,
			"color": color,
			"phase": float(i) * 0.8,
		})


func spawn_energy_beam(from_pos: Vector2, to_pos: Vector2, color: Color) -> void:
	"""Spawn a segmented energy beam arc from caster to target (Action cards)."""
	_add_particle({
		"type": ParticleType.ENERGY_BEAM,
		"x": 0.0, "y": 0.0,
		"vx": 0.0, "vy": 0.0,
		"from_x": from_pos.x, "from_y": from_pos.y,
		"to_x": to_pos.x, "to_y": to_pos.y,
		"wobble_phase": 0.0,
		"size": VisualTheme.ENERGY_BEAM_WIDTH,
		"age": 0.0,
		"lifetime": VisualTheme.ENERGY_BEAM_LIFETIME,
		"color": color,
	})


func spawn_cast_burst(world_pos: Vector2, color: Color) -> void:
	"""Spawn a radial burst of particles (Action card explosion)."""
	var count := VisualTheme.VFX_CAST_BURST_COUNT
	for i in range(count):
		var angle := float(i) / float(count) * TAU + sin(float(i) * 5.3) * 0.2
		var speed := VisualTheme.VFX_CAST_BURST_SPEED + sin(float(i) * 3.7) * 20.0
		_add_particle({
			"type": ParticleType.CAST_BURST,
			"x": world_pos.x,
			"y": world_pos.y,
			"vx": cos(angle) * speed,
			"vy": sin(angle) * speed,
			"size": 2.5 + sin(float(i) * 4.1) * 1.0,
			"age": 0.0,
			"lifetime": VisualTheme.VFX_CAST_BURST_LIFETIME + sin(float(i) * 2.9) * 0.1,
			"color": color,
		})


func spawn_shield_flash(world_pos: Vector2) -> void:
	"""Spawn an expanding protective ring (Response card)."""
	_add_particle({
		"type": ParticleType.SHIELD_FLASH,
		"x": world_pos.x, "y": world_pos.y,
		"vx": 0.0, "vy": 0.0,
		"cx": world_pos.x, "cy": world_pos.y,
		"radius": 5.0,
		"size": 0.0,
		"age": 0.0,
		"lifetime": VisualTheme.VFX_SHIELD_LIFETIME,
		"color": VisualTheme.VFX_SHIELD_COLOR,
	})


func spawn_equip_glow(world_pos: Vector2) -> void:
	"""Spawn orbiting metallic sparkles that converge on champion (Equipment card)."""
	for i in range(8):
		var angle := float(i) / 8.0 * TAU
		var radius := 20.0 + sin(float(i) * 3.1) * 5.0
		var col: Color = VisualTheme.VFX_EQUIP_COLOR if i % 2 == 0 else VisualTheme.VFX_EQUIP_GOLD
		_add_particle({
			"type": ParticleType.EQUIP_GLOW,
			"x": world_pos.x + cos(angle) * radius,
			"y": world_pos.y + sin(angle) * radius,
			"vx": 0.0, "vy": 0.0,
			"cx": world_pos.x, "cy": world_pos.y,
			"angle": angle,
			"radius": radius,
			"size": 3.0 + sin(float(i) * 4.7) * 1.0,
			"age": 0.0,
			"lifetime": VisualTheme.VFX_EQUIP_LIFETIME,
			"color": col,
		})


func spawn_lightning_arc(from_pos: Vector2, to_pos: Vector2, color: Color = Color(0.6, 0.8, 1.0)) -> void:
	"""Spawn a jagged lightning bolt from source to target with branch forks."""
	_add_particle({
		"type": ParticleType.LIGHTNING_ARC,
		"x": 0.0, "y": 0.0,
		"vx": 0.0, "vy": 0.0,
		"from_x": from_pos.x, "from_y": from_pos.y,
		"to_x": to_pos.x, "to_y": to_pos.y,
		"wobble_phase": 0.0,
		"size": 2.0,
		"age": 0.0,
		"lifetime": 0.4,
		"color": color,
	})
	# Spawn spark impacts at target
	for i in range(6):
		var angle := float(i) / 6.0 * TAU + sin(float(i) * 3.1) * 0.5
		_add_particle({
			"type": ParticleType.SPARK,
			"x": to_pos.x, "y": to_pos.y,
			"vx": cos(angle) * 50.0,
			"vy": sin(angle) * 50.0,
			"size": 2.0, "age": 0.0, "lifetime": 0.25,
			"color": color,
		})


func spawn_holy_pillar(world_pos: Vector2) -> void:
	"""Spawn a rising golden column with sparkle ring at base."""
	# Rising column particles
	for i in range(16):
		var offset_x := sin(float(i) * 2.7) * 8.0
		_add_particle({
			"type": ParticleType.HOLY_PILLAR,
			"x": world_pos.x + offset_x,
			"y": world_pos.y + 10.0,
			"vx": sin(float(i) * 3.1) * 3.0,
			"vy": -30.0 - sin(float(i) * 4.3) * 20.0,
			"size": 2.5 + sin(float(i) * 5.7) * 1.0,
			"age": float(i) * 0.02,
			"lifetime": 0.8 + sin(float(i) * 2.1) * 0.2,
			"color": Color(1.0, 0.85, 0.3),
			"phase": float(i) * 1.2,
		})
	# Base ring sparkles
	for i in range(8):
		var angle := float(i) / 8.0 * TAU
		_add_particle({
			"type": ParticleType.CAST_SHIMMER,
			"x": world_pos.x + cos(angle) * 15.0,
			"y": world_pos.y + sin(angle) * 6.0,
			"vx": cos(angle) * 8.0,
			"vy": sin(angle) * 3.0 - 5.0,
			"size": 2.0, "age": 0.0, "lifetime": 0.5,
			"color": Color(1.0, 0.9, 0.5),
		})


func spawn_shadow_tendrils(world_pos: Vector2, color: Color = Color(0.15, 0.05, 0.2)) -> void:
	"""Spawn wavy dark tendrils crawling outward from center."""
	for i in range(7):
		var angle := float(i) / 7.0 * TAU + sin(float(i) * 5.3) * 0.3
		_add_particle({
			"type": ParticleType.SHADOW_TENDRIL,
			"x": world_pos.x, "y": world_pos.y,
			"vx": 0.0, "vy": 0.0,
			"cx": world_pos.x, "cy": world_pos.y,
			"angle": angle,
			"angle_speed": 1.5 + sin(float(i) * 3.7) * 1.0,
			"radius": 3.0,
			"size": 2.0,
			"age": 0.0,
			"lifetime": 0.7 + sin(float(i) * 2.9) * 0.15,
			"color": color,
		})


func spawn_blood_splatter(world_pos: Vector2) -> void:
	"""Spawn gravity-affected red droplets."""
	for i in range(10):
		var angle := float(i) / 10.0 * TAU + sin(float(i) * 4.1) * 0.4
		var speed := 40.0 + sin(float(i) * 3.3) * 25.0
		_add_particle({
			"type": ParticleType.BLOOD_DROP,
			"x": world_pos.x, "y": world_pos.y,
			"vx": cos(angle) * speed,
			"vy": sin(angle) * speed - 50.0,
			"size": 1.5 + sin(float(i) * 5.7) * 1.0,
			"age": 0.0,
			"lifetime": 0.5 + sin(float(i) * 2.3) * 0.15,
			"color": Color(0.7, 0.05, 0.05),
		})


func spawn_leaf_swirl(world_pos: Vector2) -> void:
	"""Spawn upward spiraling leaf particles."""
	for i in range(10):
		var angle := float(i) / 10.0 * TAU
		var radius := 12.0 + sin(float(i) * 3.1) * 6.0
		var leaf_hue := 0.3 + sin(float(i) * 4.7) * 0.08  # Vary green
		_add_particle({
			"type": ParticleType.LEAF_SWIRL,
			"x": world_pos.x + cos(angle) * radius,
			"y": world_pos.y + sin(angle) * radius,
			"vx": 0.0, "vy": -10.0,
			"cx": world_pos.x, "cy": world_pos.y,
			"angle": angle,
			"radius": radius,
			"size": 3.0 + sin(float(i) * 2.3) * 1.5,
			"age": 0.0,
			"lifetime": 0.9 + sin(float(i) * 3.7) * 0.2,
			"color": Color.from_hsv(leaf_hue, 0.7, 0.6),
		})


func spawn_ground_crack(world_pos: Vector2) -> void:
	"""Spawn radiating crack lines from impact point."""
	for i in range(8):
		var angle := float(i) / 8.0 * TAU + sin(float(i) * 5.1) * 0.25
		var speed := 50.0 + sin(float(i) * 3.3) * 20.0
		_add_particle({
			"type": ParticleType.GROUND_CRACK,
			"x": world_pos.x, "y": world_pos.y,
			"vx": cos(angle) * speed,
			"vy": sin(angle) * speed,
			"size": 3.0 + sin(float(i) * 4.7) * 1.5,
			"age": 0.0,
			"lifetime": 0.6 + sin(float(i) * 2.9) * 0.1,
			"color": Color(0.5, 0.4, 0.25),
		})
	# Central dust burst
	for i in range(4):
		_add_particle({
			"type": ParticleType.DUST,
			"x": world_pos.x + sin(float(i) * 3.1) * 5.0,
			"y": world_pos.y,
			"vx": sin(float(i) * 2.3) * 15.0,
			"vy": -12.0 - sin(float(i) * 4.7) * 8.0,
			"size": 3.0, "age": 0.0, "lifetime": 0.5,
			"color": Color(0.45, 0.38, 0.28, 0.6),
		})


func spawn_arrow_volley(world_pos: Vector2) -> void:
	"""Spawn angled arrows falling from above into target area."""
	for i in range(8):
		var offset_x := sin(float(i) * 3.7) * 20.0
		var offset_y := sin(float(i) * 5.1) * 10.0
		_add_particle({
			"type": ParticleType.ARROW_VOLLEY,
			"x": world_pos.x + offset_x - 15.0,
			"y": world_pos.y - 60.0 + offset_y,
			"vx": 25.0 + sin(float(i) * 2.3) * 10.0,
			"vy": 20.0 + sin(float(i) * 4.1) * 10.0,
			"size": 2.0 + sin(float(i) * 3.3) * 0.5,
			"age": float(i) * 0.04,
			"lifetime": 0.5 + sin(float(i) * 2.7) * 0.1,
			"color": Color(0.55, 0.42, 0.2),
		})


func spawn_flask_splash(world_pos: Vector2, flask_color: Color = Color(0.3, 0.9, 0.15)) -> void:
	"""Spawn colored bubble burst."""
	for i in range(12):
		var angle := float(i) / 12.0 * TAU + sin(float(i) * 4.3) * 0.3
		var speed := 20.0 + sin(float(i) * 3.1) * 12.0
		_add_particle({
			"type": ParticleType.FLASK_BUBBLE,
			"x": world_pos.x, "y": world_pos.y,
			"vx": cos(angle) * speed,
			"vy": sin(angle) * speed - 5.0,
			"size": 2.0 + sin(float(i) * 5.7) * 1.5,
			"age": 0.0,
			"lifetime": 0.7 + sin(float(i) * 2.9) * 0.15,
			"color": flask_color,
			"phase": float(i) * 0.9,
		})


func spawn_mirror_shards(world_pos: Vector2) -> void:
	"""Spawn spinning angular reflective fragments."""
	for i in range(10):
		var angle := float(i) / 10.0 * TAU + sin(float(i) * 3.7) * 0.4
		var speed := 35.0 + sin(float(i) * 4.1) * 15.0
		_add_particle({
			"type": ParticleType.MIRROR_SHARD,
			"x": world_pos.x, "y": world_pos.y,
			"vx": cos(angle) * speed,
			"vy": sin(angle) * speed,
			"angle": float(i) * 1.3,
			"size": 3.0 + sin(float(i) * 5.3) * 1.5,
			"age": 0.0,
			"lifetime": 0.6 + sin(float(i) * 2.1) * 0.15,
			"color": Color(0.8, 0.7, 0.9, 0.9),
		})


func spawn_dagger_glint(from_pos: Vector2, to_pos: Vector2) -> void:
	"""Spawn fast-moving slash line with bright tip."""
	var dir := (to_pos - from_pos).normalized()
	var speed := 200.0
	_add_particle({
		"type": ParticleType.DAGGER_GLINT,
		"x": from_pos.x, "y": from_pos.y,
		"vx": dir.x * speed,
		"vy": dir.y * speed,
		"size": 2.5,
		"age": 0.0,
		"lifetime": 0.3,
		"color": Color(0.9, 0.85, 0.7),
	})
	# Second slash at slight angle
	var perp := Vector2(-dir.y, dir.x)
	_add_particle({
		"type": ParticleType.DAGGER_GLINT,
		"x": from_pos.x + perp.x * 5.0, "y": from_pos.y + perp.y * 5.0,
		"vx": dir.x * speed * 0.9 + perp.x * 30.0,
		"vy": dir.y * speed * 0.9 + perp.y * 30.0,
		"size": 2.0,
		"age": 0.05,
		"lifetime": 0.25,
		"color": Color(0.8, 0.75, 0.6),
	})


func spawn_chain_wrap(world_pos: Vector2) -> void:
	"""Spawn circling chain segments around target."""
	for i in range(8):
		var angle := float(i) / 8.0 * TAU
		var radius := 18.0 + sin(float(i) * 3.1) * 4.0
		_add_particle({
			"type": ParticleType.CHAIN_LINK,
			"x": world_pos.x + cos(angle) * radius,
			"y": world_pos.y + sin(angle) * radius,
			"vx": 0.0, "vy": 0.0,
			"cx": world_pos.x, "cy": world_pos.y,
			"angle": angle,
			"radius": radius,
			"size": 3.0 + sin(float(i) * 4.7) * 1.0,
			"age": 0.0,
			"lifetime": 0.8 + sin(float(i) * 2.3) * 0.15,
			"color": Color(0.3, 0.28, 0.25),
		})


func spawn_shockwave(world_pos: Vector2, color: Color = Color(0.8, 0.7, 0.5)) -> void:
	"""Spawn expanding concentric rings."""
	_add_particle({
		"type": ParticleType.SHOCKWAVE,
		"x": world_pos.x, "y": world_pos.y,
		"vx": 0.0, "vy": 0.0,
		"cx": world_pos.x, "cy": world_pos.y,
		"radius": 5.0,
		"size": 0.0,
		"age": 0.0,
		"lifetime": 0.5,
		"color": color,
	})
	# Second delayed ring
	_add_particle({
		"type": ParticleType.SHOCKWAVE,
		"x": world_pos.x, "y": world_pos.y,
		"vx": 0.0, "vy": 0.0,
		"cx": world_pos.x, "cy": world_pos.y,
		"radius": 3.0,
		"size": 0.0,
		"age": -0.1,  # Delayed start
		"lifetime": 0.5,
		"color": color,
	})


func spawn_smoke_poof(world_pos: Vector2) -> void:
	"""Spawn a billowing smoke cloud effect (Smoke Bomb response)."""
	var smoke_color := Color(0.55, 0.5, 0.45, 1.0)  # Earthy grey-brown
	# Central large cloud puffs
	for i in range(8):
		var angle := float(i) / 8.0 * TAU + sin(float(i) * 2.3) * 0.3
		var speed := 15.0 + sin(float(i) * 3.7) * 8.0
		var size := 8.0 + sin(float(i) * 4.1) * 3.0
		_add_particle({
			"type": ParticleType.SMOKE_POOF,
			"x": world_pos.x + cos(angle) * 3.0,
			"y": world_pos.y + sin(angle) * 3.0,
			"vx": cos(angle) * speed,
			"vy": sin(angle) * speed - 10.0,  # Drift upward
			"size": size,
			"age": 0.0,
			"lifetime": 0.8 + sin(float(i) * 5.3) * 0.2,
			"color": smoke_color,
		})
	# Smaller wisp particles
	for i in range(6):
		var angle := float(i) / 6.0 * TAU + 0.5
		var speed := 25.0 + sin(float(i) * 2.1) * 10.0
		_add_particle({
			"type": ParticleType.SMOKE_POOF,
			"x": world_pos.x,
			"y": world_pos.y,
			"vx": cos(angle) * speed,
			"vy": sin(angle) * speed - 15.0,
			"size": 4.0 + sin(float(i) * 3.3) * 2.0,
			"age": 0.0,
			"lifetime": 0.6,
			"color": Color(0.65, 0.6, 0.55, 1.0),
		})


func _spawn_ambient_dust() -> void:
	"""Spawn slow-floating faint particles across the board."""
	if _particles.size() > MAX_PARTICLES - 20:
		return  # Don't overload with ambients

	var board_px := float(_tile_size * 10)
	var x := sin(_ambient_timer * 7.3) * 0.5 + 0.5
	var y := sin(_ambient_timer * 5.1 + 2.0) * 0.5 + 0.5
	_add_particle({
		"type": ParticleType.AMBIENT,
		"x": x * board_px,
		"y": y * board_px,
		"vx": sin(_ambient_timer * 3.7) * 3.0,
		"vy": -2.0 + sin(_ambient_timer * 2.3) * 1.5,
		"size": 1.5 + sin(_ambient_timer * 4.1) * 0.5,
		"age": 0.0,
		"lifetime": 3.0 + sin(_ambient_timer * 1.9) * 1.0,
		"color": VisualTheme.VFX_AMBIENT,
		"phase": _ambient_timer,
	})


func _spawn_pit_smoke() -> void:
	"""Spawn purple wisps + orange embers from pit tiles, with occasional flash."""
	if _pit_tiles.is_empty() or _particles.size() > MAX_PARTICLES - 20:
		return

	# Spawn TWO smoke particles per cycle (doubled rate)
	for burst in range(2):
		var idx := int(abs(sin(_ambient_timer * 2.1 + float(burst) * 1.7)) * _pit_tiles.size()) % _pit_tiles.size()
		var pit_pos := _pit_tiles[idx]
		var world_x := float(pit_pos.x * _tile_size + _tile_size / 2)
		var world_y := float(pit_pos.y * _tile_size + _tile_size / 2)

		# Purple smoke wisp
		_add_particle({
			"type": ParticleType.PIT_SMOKE,
			"x": world_x + sin(_ambient_timer * 5.3 + float(burst) * 3.0) * 10.0,
			"y": world_y,
			"vx": sin(_ambient_timer * 3.1 + float(burst) * 2.0) * 4.0,
			"vy": -6.0,
			"size": 4.0 + sin(_ambient_timer * 2.7) * 2.0,
			"age": 0.0,
			"lifetime": 1.5 + sin(_ambient_timer * 4.3) * 0.5,
			"color": VisualTheme.VFX_PIT_SMOKE,
		})

	# Orange ember particles rising from pits (every other cycle)
	if int(_ambient_timer * 10.0) % 3 == 0:
		var ember_idx := int(abs(sin(_ambient_timer * 3.7)) * _pit_tiles.size()) % _pit_tiles.size()
		var ember_pos := _pit_tiles[ember_idx]
		var ex := float(ember_pos.x * _tile_size + _tile_size / 2)
		var ey := float(ember_pos.y * _tile_size + _tile_size / 2)
		_add_particle({
			"type": ParticleType.SPARK,
			"x": ex + sin(_ambient_timer * 7.1) * 8.0,
			"y": ey,
			"vx": sin(_ambient_timer * 4.5) * 6.0,
			"vy": -20.0 - sin(_ambient_timer * 3.3) * 8.0,
			"size": 1.5 + sin(_ambient_timer * 5.1) * 0.5,
			"age": 0.0,
			"lifetime": 0.8 + sin(_ambient_timer * 2.9) * 0.3,
			"color": Color(1.0, 0.5, 0.1, 0.9),  # Orange ember
		})

	# Occasional bright flash pulse from pit center
	if int(_ambient_timer * 10.0) % 50 == 0:
		var flash_idx := int(abs(sin(_ambient_timer * 1.3)) * _pit_tiles.size()) % _pit_tiles.size()
		var flash_pos := _pit_tiles[flash_idx]
		var fx := float(flash_pos.x * _tile_size + _tile_size / 2)
		var fy := float(flash_pos.y * _tile_size + _tile_size / 2)
		# Burst of bright sparks
		for s in range(5):
			var angle := float(s) / 5.0 * TAU
			_add_particle({
				"type": ParticleType.SPARK,
				"x": fx,
				"y": fy,
				"vx": cos(angle) * 30.0,
				"vy": sin(angle) * 30.0 - 15.0,
				"size": 2.0,
				"age": 0.0,
				"lifetime": 0.5,
				"color": Color(1.0, 0.7, 0.3, 1.0),  # Bright orange-yellow
			})


func get_particle_count() -> int:
	return _particles.size()
