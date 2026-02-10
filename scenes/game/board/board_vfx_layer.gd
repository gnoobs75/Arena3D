extends Node2D
class_name BoardVFXLayer
## BoardVFXLayer - Centralized procedural particle system for board visual effects
## Renders all particles in a single _draw() call for performance.
## Create two instances: vfx_below (under champions) and vfx_above (over champions).

const MAX_PARTICLES := 200

# Particle pool
var _particles: Array[Dictionary] = []
var _ambient_timer: float = 0.0
var _pit_tiles: Array[Vector2i] = []  # Cached pit tile positions
var _tile_size: int = 64

# Types of particles
enum ParticleType {
	DUST, SPARK, MAGIC, CAST_SHIMMER, DEATH_RING, DEATH_SOUL,
	DEATH_DEBRIS, HEAL, AMBIENT, PIT_SMOKE, RANGED_TRAIL,
	ENERGY_BEAM, CAST_BURST, SHIELD_FLASH, EQUIP_GLOW, SMOKE_POOF
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
	"""Spawn purple wisps from pit tiles."""
	if _pit_tiles.is_empty() or _particles.size() > MAX_PARTICLES - 10:
		return

	# Pick a deterministic pit tile based on timer
	var idx := int(abs(sin(_ambient_timer * 2.1)) * _pit_tiles.size()) % _pit_tiles.size()
	var pit_pos := _pit_tiles[idx]
	var world_x := float(pit_pos.x * _tile_size + _tile_size / 2)
	var world_y := float(pit_pos.y * _tile_size + _tile_size / 2)

	_add_particle({
		"type": ParticleType.PIT_SMOKE,
		"x": world_x + sin(_ambient_timer * 5.3) * 10.0,
		"y": world_y,
		"vx": sin(_ambient_timer * 3.1) * 4.0,
		"vy": -6.0,
		"size": 4.0 + sin(_ambient_timer * 2.7) * 2.0,
		"age": 0.0,
		"lifetime": 1.5 + sin(_ambient_timer * 4.3) * 0.5,
		"color": VisualTheme.VFX_PIT_SMOKE,
	})


func get_particle_count() -> int:
	return _particles.size()
