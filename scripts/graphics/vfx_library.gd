extends Node
class_name VFXLibrary
## VFXLibrary - Manages particle effects and visual feedback
## Creates and spawns VFX for spells, impacts, healing, buffs, etc.

# === EFFECT TYPES ===
enum EffectType {
	SLASH_IMPACT,
	ARROW_TRAIL,
	BLOOD_SPRAY,
	HEAL_GLOW,
	BUFF_AURA,
	DEBUFF_CHAINS,
	DEATH_SOUL,
	SPELL_GENERIC,
	SPELL_FIRE,
	SPELL_ICE,
	SPELL_LIGHTNING,
	SPELL_HOLY,
	SPELL_DARK,
	SPELL_NATURE
}

# === CHAMPION EFFECT THEMES ===
const CHAMPION_THEMES: Dictionary = {
	"Brute": { "primary": EffectType.SLASH_IMPACT, "spell": EffectType.SPELL_GENERIC },
	"Ranger": { "primary": EffectType.ARROW_TRAIL, "spell": EffectType.SPELL_NATURE },
	"Beast": { "primary": EffectType.SLASH_IMPACT, "spell": EffectType.SPELL_NATURE },
	"Redeemer": { "primary": EffectType.SPELL_HOLY, "spell": EffectType.SPELL_HOLY },
	"Confessor": { "primary": EffectType.SPELL_DARK, "spell": EffectType.SPELL_DARK },
	"Barbarian": { "primary": EffectType.BLOOD_SPRAY, "spell": EffectType.SPELL_FIRE },
	"Burglar": { "primary": EffectType.SLASH_IMPACT, "spell": EffectType.SPELL_DARK },
	"Berserker": { "primary": EffectType.BLOOD_SPRAY, "spell": EffectType.SPELL_FIRE },
	"Shaman": { "primary": EffectType.SPELL_LIGHTNING, "spell": EffectType.SPELL_LIGHTNING },
	"Illusionist": { "primary": EffectType.SPELL_GENERIC, "spell": EffectType.SPELL_GENERIC },
	"DarkWizard": { "primary": EffectType.SPELL_DARK, "spell": EffectType.SPELL_DARK },
	"Alchemist": { "primary": EffectType.SPELL_NATURE, "spell": EffectType.SPELL_NATURE }
}

# Parent node for spawned effects
var _vfx_container: Node3D


func _init(container: Node3D = null) -> void:
	_vfx_container = container


func set_container(container: Node3D) -> void:
	"""Set the container node for spawned VFX."""
	_vfx_container = container


# === SPAWN FUNCTIONS ===

func spawn_effect(effect_type: EffectType, position: Vector3, color: Color = Color.WHITE, duration: float = 1.0) -> GPUParticles3D:
	"""Spawn a particle effect at position."""
	var particles: GPUParticles3D = _create_particles(effect_type, color)
	if not particles:
		return null

	particles.position = position
	particles.one_shot = true
	particles.emitting = true

	if _vfx_container:
		_vfx_container.add_child(particles)
	else:
		push_warning("VFXLibrary: No container set, effect not added to scene")
		return null

	# Auto-cleanup after duration
	var timer: SceneTreeTimer = particles.get_tree().create_timer(duration + 1.0)
	timer.timeout.connect(particles.queue_free)

	return particles


func spawn_impact(position: Vector3, color: Color = Color.RED) -> void:
	"""Spawn melee impact effect."""
	spawn_effect(EffectType.SLASH_IMPACT, position, color, 0.5)


func spawn_projectile(start: Vector3, end: Vector3, color: Color = Color.WHITE, speed: float = 10.0) -> void:
	"""Spawn a projectile traveling from start to end."""
	var particles: GPUParticles3D = _create_particles(EffectType.ARROW_TRAIL, color)
	if not particles or not _vfx_container:
		return

	particles.position = start
	particles.emitting = true
	_vfx_container.add_child(particles)

	# Animate projectile travel
	var distance: float = start.distance_to(end)
	var duration: float = distance / speed

	var tween: Tween = particles.create_tween()
	tween.tween_property(particles, "position", end, duration)
	tween.tween_callback(func():
		particles.emitting = false
		# Spawn impact at end
		spawn_impact(end, color)
	)

	# Cleanup after travel + impact
	var timer: SceneTreeTimer = particles.get_tree().create_timer(duration + 1.0)
	timer.timeout.connect(particles.queue_free)


func spawn_heal(position: Vector3, color: Color = Color.GREEN) -> void:
	"""Spawn healing effect."""
	spawn_effect(EffectType.HEAL_GLOW, position + Vector3(0, 0.3, 0), color, 1.0)


func spawn_buff(position: Vector3, color: Color = Color.CYAN) -> void:
	"""Spawn buff aura effect."""
	spawn_effect(EffectType.BUFF_AURA, position, color, 0.8)


func spawn_debuff(position: Vector3, color: Color = Color.PURPLE) -> void:
	"""Spawn debuff effect."""
	spawn_effect(EffectType.DEBUFF_CHAINS, position, color, 0.8)


func spawn_death(position: Vector3, color: Color = Color.WHITE) -> void:
	"""Spawn death/soul effect."""
	spawn_effect(EffectType.DEATH_SOUL, position + Vector3(0, 0.5, 0), color, 2.0)


func spawn_spell(position: Vector3, spell_type: EffectType = EffectType.SPELL_GENERIC, color: Color = Color.WHITE) -> void:
	"""Spawn spell effect at position."""
	spawn_effect(spell_type, position + Vector3(0, 0.3, 0), color, 1.0)


func spawn_champion_attack(champion_name: String, position: Vector3) -> void:
	"""Spawn attack effect themed for champion."""
	var theme: Dictionary = CHAMPION_THEMES.get(champion_name, { "primary": EffectType.SLASH_IMPACT })
	var colors: Dictionary = VisualTheme.get_champion_colors(champion_name)
	spawn_effect(theme["primary"], position, colors["primary"], 0.5)


func spawn_champion_spell(champion_name: String, position: Vector3) -> void:
	"""Spawn spell effect themed for champion."""
	var theme: Dictionary = CHAMPION_THEMES.get(champion_name, { "spell": EffectType.SPELL_GENERIC })
	var colors: Dictionary = VisualTheme.get_champion_colors(champion_name)
	spawn_effect(theme["spell"], position + Vector3(0, 0.5, 0), colors["primary"], 1.0)


# === PARTICLE CREATION ===

func _create_particles(effect_type: EffectType, color: Color) -> GPUParticles3D:
	"""Create a GPUParticles3D for the given effect type."""
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.amount = 32
	particles.lifetime = 0.5
	particles.explosiveness = 0.8
	particles.one_shot = true

	# Create process material
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	particles.process_material = mat

	# Configure based on effect type
	match effect_type:
		EffectType.SLASH_IMPACT:
			_configure_slash_impact(mat, color)
			particles.amount = 24
			particles.lifetime = 0.3

		EffectType.ARROW_TRAIL:
			_configure_arrow_trail(mat, color)
			particles.amount = 16
			particles.lifetime = 0.2
			particles.explosiveness = 0.0  # Continuous trail

		EffectType.BLOOD_SPRAY:
			_configure_blood_spray(mat, color)
			particles.amount = 40
			particles.lifetime = 0.5

		EffectType.HEAL_GLOW:
			_configure_heal_glow(mat, color)
			particles.amount = 48
			particles.lifetime = 1.0
			particles.explosiveness = 0.3

		EffectType.BUFF_AURA:
			_configure_buff_aura(mat, color)
			particles.amount = 32
			particles.lifetime = 0.8

		EffectType.DEBUFF_CHAINS:
			_configure_debuff(mat, color)
			particles.amount = 24
			particles.lifetime = 0.6

		EffectType.DEATH_SOUL:
			_configure_death_soul(mat, color)
			particles.amount = 64
			particles.lifetime = 2.0
			particles.explosiveness = 0.2

		EffectType.SPELL_GENERIC:
			_configure_spell_generic(mat, color)
			particles.amount = 48
			particles.lifetime = 0.8

		EffectType.SPELL_FIRE:
			_configure_spell_fire(mat, color)
			particles.amount = 64
			particles.lifetime = 0.6

		EffectType.SPELL_ICE:
			_configure_spell_ice(mat, color)
			particles.amount = 32
			particles.lifetime = 1.0

		EffectType.SPELL_LIGHTNING:
			_configure_spell_lightning(mat, color)
			particles.amount = 20
			particles.lifetime = 0.2
			particles.explosiveness = 1.0

		EffectType.SPELL_HOLY:
			_configure_spell_holy(mat, color)
			particles.amount = 48
			particles.lifetime = 1.0

		EffectType.SPELL_DARK:
			_configure_spell_dark(mat, color)
			particles.amount = 40
			particles.lifetime = 0.8

		EffectType.SPELL_NATURE:
			_configure_spell_nature(mat, color)
			particles.amount = 36
			particles.lifetime = 0.8

	# Create draw pass (simple quad particles)
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(0.05, 0.05)
	particles.draw_pass_1 = mesh

	# Create material for rendering
	var draw_mat: StandardMaterial3D = StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = draw_mat

	return particles


# === EFFECT CONFIGURATIONS ===

func _configure_slash_impact(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure slash/melee impact particles."""
	mat.direction = Vector3(0, 0.5, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -5, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	mat.color = color

	# Color ramp: bright to dark
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, color.darkened(0.8))
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = gradient
	mat.color_ramp = texture


func _configure_arrow_trail(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure arrow/projectile trail."""
	mat.direction = Vector3(0, 0, -1)
	mat.spread = 5.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.3
	mat.scale_max = 0.6
	mat.color = color


func _configure_blood_spray(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure blood/damage spray."""
	mat.direction = Vector3(0, 0.3, 0.5)
	mat.spread = 45.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, -10, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.8
	mat.color = Color(0.8, 0.1, 0.1).lerp(color, 0.3)


func _configure_heal_glow(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure healing particles."""
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3(0, 0.5, 0)  # Float upward
	mat.scale_min = 0.4
	mat.scale_max = 0.8
	mat.color = Color(0.3, 1.0, 0.5).lerp(color, 0.5)

	# Fade out
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, mat.color)
	gradient.set_color(1, Color(mat.color, 0))
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = gradient
	mat.color_ramp = texture


func _configure_buff_aura(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure buff aura particles."""
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0  # All directions
	mat.initial_velocity_min = 0.8
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3(0, 1, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.6
	mat.color = Color(0.5, 1.0, 1.0).lerp(color, 0.5)


func _configure_debuff(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure debuff particles."""
	mat.direction = Vector3(0, -0.5, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 0.8
	mat.gravity = Vector3(0, -0.5, 0)
	mat.scale_min = 0.4
	mat.scale_max = 0.7
	mat.color = Color(0.5, 0.2, 0.6).lerp(color, 0.4)


func _configure_death_soul(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure death/soul rising particles."""
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 20.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.0
	mat.gravity = Vector3(0, 0.3, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	mat.color = Color(0.9, 0.9, 1.0, 0.8)

	# Fade out over time
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.8))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = gradient
	mat.color_ramp = texture


func _configure_spell_generic(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure generic spell burst."""
	mat.direction = Vector3(0, 0.5, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -1, 0)
	mat.scale_min = 0.4
	mat.scale_max = 0.8
	mat.color = color


func _configure_spell_fire(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure fire spell."""
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, 1, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.2
	mat.color = Color(1.0, 0.5, 0.1).lerp(color, 0.3)

	# Fire gradient
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1, 0.8, 0.2))
	gradient.set_color(0.5, Color(1, 0.3, 0.1))
	gradient.set_color(1, Color(0.2, 0.1, 0.1, 0))
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = gradient
	mat.color_ramp = texture


func _configure_spell_ice(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure ice spell."""
	mat.direction = Vector3(0, 0.2, 0)
	mat.spread = 90.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 2.0
	mat.gravity = Vector3(0, -2, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.7
	mat.color = Color(0.7, 0.9, 1.0).lerp(color, 0.3)


func _configure_spell_lightning(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure lightning spell."""
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 10.0
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 15.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.2
	mat.scale_max = 0.5
	mat.color = Color(0.8, 0.9, 1.0).lerp(color, 0.3)


func _configure_spell_holy(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure holy/light spell."""
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3(0, 0.5, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	mat.color = Color(1.0, 0.95, 0.7).lerp(color, 0.3)


func _configure_spell_dark(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure dark/shadow spell."""
	mat.direction = Vector3(0, -0.3, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 0.8
	mat.initial_velocity_max = 2.0
	mat.gravity = Vector3(0, -1, 0)
	mat.scale_min = 0.4
	mat.scale_max = 0.9
	mat.color = Color(0.3, 0.1, 0.4).lerp(color, 0.4)


func _configure_spell_nature(mat: ParticleProcessMaterial, color: Color) -> void:
	"""Configure nature/earth spell."""
	mat.direction = Vector3(0, 0.5, 0)
	mat.spread = 120.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 2.0
	mat.gravity = Vector3(0, -2, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.7
	mat.color = Color(0.4, 0.7, 0.3).lerp(color, 0.4)
