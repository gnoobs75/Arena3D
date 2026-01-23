extends Node3D
class_name Champion3D
## Champion3D - Animated 3D champion with procedural animations
## Handles idle, walk, attack, hit, cast, and death animations

# === SIGNALS ===
signal animation_finished(anim_name: String)
signal walk_step  # Emitted on each footstep for sound/VFX

# === ANIMATION STATES ===
enum AnimState { IDLE, WALK, ATTACK, HIT, CAST, DEATH, BUFF, DEBUFF }

# === CONFIGURATION ===
var champion_name: String = ""
var owner_id: int = 0

# Animation parameters (tuned per champion)
var idle_bob_amount: float = 0.02
var idle_bob_speed: float = 2.0
var idle_sway_amount: float = 0.01
var walk_bob_amount: float = 0.05
var walk_speed: float = 8.0
var attack_lunge_distance: float = 0.2
var attack_speed: float = 1.5

# === STATE ===
var _current_state: AnimState = AnimState.IDLE
var _is_animating: bool = false
var _original_position: Vector3 = Vector3.ZERO
var _base_y: float = 0.0
var _time: float = 0.0
var _is_alive: bool = true

# Body part references
var _body: Node3D
var _head: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D

# Animation tweens
var _current_tween: Tween


func _ready() -> void:
	_cache_body_parts()
	_original_position = position
	_base_y = position.y
	_start_idle_animation()


func _process(delta: float) -> void:
	_time += delta

	if _current_state == AnimState.IDLE and _is_alive:
		_update_idle_animation(delta)


func _cache_body_parts() -> void:
	"""Cache references to body parts for animation."""
	_body = get_node_or_null("Body")
	_head = get_node_or_null("Head")
	_left_arm = get_node_or_null("LeftArm")
	_right_arm = get_node_or_null("RightArm")
	_left_leg = get_node_or_null("LeftLeg")
	_right_leg = get_node_or_null("RightLeg")


# === IDLE ANIMATION ===

func _start_idle_animation() -> void:
	"""Start the idle breathing/swaying animation."""
	_current_state = AnimState.IDLE


func _update_idle_animation(delta: float) -> void:
	"""Update procedural idle animation each frame with champion-specific quirks."""
	# Gentle body bob (breathing)
	var bob: float = sin(_time * idle_bob_speed) * idle_bob_amount
	position.y = _base_y + bob

	# Subtle body sway
	var sway: float = sin(_time * idle_bob_speed * 0.7) * idle_sway_amount
	if _body:
		_body.rotation.z = sway

	# Head slight movement
	if _head:
		_head.rotation.y = sin(_time * idle_bob_speed * 0.5) * 0.05
		_head.rotation.x = sin(_time * idle_bob_speed * 0.3) * 0.02

	# Arms subtle swing
	if _left_arm:
		_left_arm.rotation.x = sin(_time * idle_bob_speed * 0.6) * 0.03
	if _right_arm:
		_right_arm.rotation.x = sin(_time * idle_bob_speed * 0.6 + PI) * 0.03

	# Champion-specific idle quirks
	_update_champion_quirk(delta)


# === WALK ANIMATION ===

func play_walk_animation(direction: Vector3, duration: float = 0.4) -> void:
	"""Play walking animation in a direction."""
	if not _is_alive:
		return

	_kill_current_tween()
	_current_state = AnimState.WALK
	_is_animating = true

	# Face movement direction
	if direction.length_squared() > 0.01:
		var target_angle: float = atan2(direction.x, direction.z)
		rotation.y = target_angle

	# Animate walk cycle
	var walk_tween: Tween = create_tween()
	walk_tween.set_loops(int(duration / 0.2))

	# Bob up and down
	walk_tween.tween_property(self, "position:y", _base_y + walk_bob_amount, 0.1)
	walk_tween.tween_property(self, "position:y", _base_y, 0.1)

	# Leg and arm swing (if we have body parts)
	if _left_leg and _right_leg:
		var leg_tween: Tween = create_tween()
		leg_tween.set_loops(int(duration / 0.2))
		leg_tween.tween_property(_left_leg, "rotation:x", 0.4, 0.1)
		leg_tween.parallel().tween_property(_right_leg, "rotation:x", -0.4, 0.1)
		leg_tween.tween_property(_left_leg, "rotation:x", -0.4, 0.1)
		leg_tween.parallel().tween_property(_right_leg, "rotation:x", 0.4, 0.1)

	if _left_arm and _right_arm:
		var arm_tween: Tween = create_tween()
		arm_tween.set_loops(int(duration / 0.2))
		arm_tween.tween_property(_left_arm, "rotation:x", -0.3, 0.1)
		arm_tween.parallel().tween_property(_right_arm, "rotation:x", 0.3, 0.1)
		arm_tween.tween_property(_left_arm, "rotation:x", 0.3, 0.1)
		arm_tween.parallel().tween_property(_right_arm, "rotation:x", -0.3, 0.1)

	await walk_tween.finished

	# Reset to neutral
	_reset_pose()
	_current_state = AnimState.IDLE
	_is_animating = false
	animation_finished.emit("walk")


# === ATTACK ANIMATION ===

func play_attack_animation(target_direction: Vector3 = Vector3.FORWARD) -> void:
	"""Play melee attack animation."""
	if not _is_alive:
		return

	_kill_current_tween()
	_current_state = AnimState.ATTACK
	_is_animating = true

	# Face target
	if target_direction.length_squared() > 0.01:
		var target_angle: float = atan2(target_direction.x, target_direction.z)
		rotation.y = target_angle

	_current_tween = create_tween()
	_current_tween.set_ease(Tween.EASE_OUT)
	_current_tween.set_trans(Tween.TRANS_BACK)

	# Wind up (pull back slightly)
	_current_tween.tween_property(self, "position", position - target_direction.normalized() * 0.1, 0.08)

	# Lunge forward
	_current_tween.set_ease(Tween.EASE_IN)
	_current_tween.tween_property(self, "position", position + target_direction.normalized() * attack_lunge_distance, 0.12)

	# Arm swing
	if _right_arm:
		_current_tween.parallel().tween_property(_right_arm, "rotation:x", -1.2, 0.12)

	# Return
	_current_tween.set_ease(Tween.EASE_OUT)
	_current_tween.tween_property(self, "position", _original_position, 0.15)

	if _right_arm:
		_current_tween.parallel().tween_property(_right_arm, "rotation:x", 0, 0.15)

	await _current_tween.finished

	_reset_pose()
	_current_state = AnimState.IDLE
	_is_animating = false
	animation_finished.emit("attack")


# === HIT ANIMATION ===

func play_hit_animation(damage_amount: int = 1) -> void:
	"""Play hit reaction animation."""
	if not _is_alive:
		return

	_kill_current_tween()
	@warning_ignore("unused_variable")
	var prev_state: AnimState = _current_state
	_current_state = AnimState.HIT

	_current_tween = create_tween()

	# Stagger back
	var stagger_amount: float = 0.05 + minf(float(damage_amount) * 0.01, 0.1)
	_current_tween.tween_property(self, "position:z", position.z - stagger_amount, 0.05)
	_current_tween.tween_property(self, "position:z", _original_position.z, 0.1)

	# Flash body red (if we have access to materials)
	if _body and _body is MeshInstance3D:
		var body_mesh: MeshInstance3D = _body as MeshInstance3D
		if body_mesh.material_override and body_mesh.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = body_mesh.material_override as StandardMaterial3D
			var original_color: Color = mat.albedo_color
			_current_tween.parallel().tween_property(mat, "albedo_color", Color(1.0, 0.3, 0.3), 0.05)
			_current_tween.tween_property(mat, "albedo_color", original_color, 0.1)

	# Head recoil
	if _head:
		_current_tween.parallel().tween_property(_head, "rotation:x", -0.3, 0.05)
		_current_tween.tween_property(_head, "rotation:x", 0, 0.1)

	await _current_tween.finished

	_current_state = AnimState.IDLE if _is_alive else AnimState.DEATH
	animation_finished.emit("hit")


# === CAST ANIMATION ===

func play_cast_animation(is_channeling: bool = false) -> void:
	"""Play spell casting animation."""
	if not _is_alive:
		return

	_kill_current_tween()
	_current_state = AnimState.CAST
	_is_animating = true

	_current_tween = create_tween()

	# Raise arms
	if _left_arm and _right_arm:
		_current_tween.tween_property(_left_arm, "rotation:x", -1.0, 0.15)
		_current_tween.parallel().tween_property(_right_arm, "rotation:x", -1.0, 0.15)
		_current_tween.parallel().tween_property(_left_arm, "rotation:z", -0.3, 0.15)
		_current_tween.parallel().tween_property(_right_arm, "rotation:z", 0.3, 0.15)

	# Rise up slightly
	_current_tween.parallel().tween_property(self, "position:y", _base_y + 0.1, 0.15)

	# Glow effect via selection light
	var glow: Node = get_node_or_null("SelectionGlow")
	if glow and glow is OmniLight3D:
		_current_tween.parallel().tween_property(glow, "light_energy", 1.5, 0.15)

	# Hold if channeling, otherwise release
	if not is_channeling:
		await _current_tween.finished

		# Release
		var release_tween: Tween = create_tween()
		release_tween.tween_property(self, "position:y", _base_y, 0.1)

		if _left_arm and _right_arm:
			release_tween.parallel().tween_property(_left_arm, "rotation:x", 0, 0.1)
			release_tween.parallel().tween_property(_right_arm, "rotation:x", 0, 0.1)
			release_tween.parallel().tween_property(_left_arm, "rotation:z", 0.26, 0.1)  # Back to default
			release_tween.parallel().tween_property(_right_arm, "rotation:z", -0.26, 0.1)

		if glow:
			release_tween.parallel().tween_property(glow, "light_energy", 0, 0.1)

		await release_tween.finished

	_reset_pose()
	_current_state = AnimState.IDLE
	_is_animating = false
	animation_finished.emit("cast")


# === DEATH ANIMATION ===

func play_death_animation() -> void:
	"""Play death animation."""
	_kill_current_tween()
	_is_alive = false
	_current_state = AnimState.DEATH
	_is_animating = true

	_current_tween = create_tween()
	_current_tween.set_ease(Tween.EASE_IN)
	_current_tween.set_trans(Tween.TRANS_QUAD)

	# Stagger
	_current_tween.tween_property(self, "position:z", position.z - 0.1, 0.15)

	# Fall forward
	_current_tween.set_ease(Tween.EASE_IN)
	_current_tween.tween_property(self, "rotation:x", PI / 2, 0.4)
	_current_tween.parallel().tween_property(self, "position:y", -0.2, 0.4)

	# Fade out body
	if _body and _body is MeshInstance3D:
		var body_mesh: MeshInstance3D = _body as MeshInstance3D
		if body_mesh.material_override and body_mesh.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = body_mesh.material_override as StandardMaterial3D
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_current_tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.5)

	await _current_tween.finished

	_is_animating = false
	animation_finished.emit("death")


# === BUFF/DEBUFF ANIMATIONS ===

func play_buff_animation() -> void:
	"""Play buff received animation."""
	_kill_current_tween()

	_current_tween = create_tween()

	# Scale up briefly
	_current_tween.tween_property(self, "scale", Vector3.ONE * 1.15, 0.15)
	_current_tween.tween_property(self, "scale", Vector3.ONE, 0.15)

	# Glow
	var glow: Node = get_node_or_null("SelectionGlow")
	if glow and glow is OmniLight3D:
		var original_color: Color = glow.light_color
		glow.light_color = Color(0.3, 1.0, 0.5)  # Green glow
		_current_tween.parallel().tween_property(glow, "light_energy", 1.0, 0.15)
		_current_tween.tween_property(glow, "light_energy", 0, 0.15)
		glow.light_color = original_color

	await _current_tween.finished
	animation_finished.emit("buff")


func play_debuff_animation() -> void:
	"""Play debuff received animation."""
	_kill_current_tween()

	_current_tween = create_tween()

	# Scale down briefly
	_current_tween.tween_property(self, "scale", Vector3.ONE * 0.9, 0.15)
	_current_tween.tween_property(self, "scale", Vector3.ONE, 0.15)

	# Flash dark
	if _body and _body is MeshInstance3D:
		var body_mesh: MeshInstance3D = _body as MeshInstance3D
		if body_mesh.material_override and body_mesh.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = body_mesh.material_override as StandardMaterial3D
			var original_color: Color = mat.albedo_color
			_current_tween.parallel().tween_property(mat, "albedo_color", original_color.darkened(0.5), 0.1)
			_current_tween.tween_property(mat, "albedo_color", original_color, 0.15)

	await _current_tween.finished
	animation_finished.emit("debuff")


# === SELECTION ===

func set_selected(is_selected: bool) -> void:
	"""Show/hide selection highlight."""
	var glow: Node = get_node_or_null("SelectionGlow")
	if glow and glow is OmniLight3D:
		var target_energy: float = 0.8 if is_selected else 0.0
		var tween: Tween = create_tween()
		tween.tween_property(glow, "light_energy", target_energy, 0.1)


# === HELPERS ===

func _kill_current_tween() -> void:
	"""Stop any running animation tween."""
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()


func _reset_pose() -> void:
	"""Reset all body parts to neutral pose."""
	if _body:
		_body.rotation = Vector3.ZERO
	if _head:
		_head.rotation = Vector3.ZERO
	if _left_arm:
		_left_arm.rotation = Vector3(0, 0, 0.26)  # Slight outward
	if _right_arm:
		_right_arm.rotation = Vector3(0, 0, -0.26)
	if _left_leg:
		_left_leg.rotation = Vector3.ZERO
	if _right_leg:
		_right_leg.rotation = Vector3.ZERO


func is_animating() -> bool:
	"""Check if currently playing an animation."""
	return _is_animating


func get_current_state() -> AnimState:
	"""Get current animation state."""
	return _current_state


# === CHAMPION-SPECIFIC QUIRKS ===

func _update_champion_quirk(delta: float) -> void:
	"""Update champion-specific idle behaviors."""
	match champion_name:
		"Brute":
			# Scratches head occasionally, heavy breathing
			if fmod(_time, 8.0) < 0.5 and _right_arm:
				_right_arm.rotation.x = lerp(_right_arm.rotation.x, -0.8, delta * 3)
			idle_bob_amount = 0.03  # Heavy breathing

		"Ranger":
			# Alert stance, looks around more
			if _head:
				_head.rotation.y = sin(_time * 1.2) * 0.15
			idle_sway_amount = 0.005  # Very still

		"Beast":
			# Sniffs the air, hunched and twitchy
			if fmod(_time, 3.0) < 0.3 and _head:
				_head.rotation.x = lerp(_head.rotation.x, 0.2, delta * 5)
			idle_bob_speed = 3.0  # Faster breathing

		"Redeemer":
			# Serene, gentle floating/swaying, hands in prayer
			idle_bob_speed = 1.5  # Slow, calm
			idle_bob_amount = 0.025

		"Confessor":
			# Hovers slightly, ominous stillness
			position.y = _base_y + 0.1 + sin(_time * 0.8) * 0.03
			idle_sway_amount = 0.0  # Unnaturally still

		"Barbarian":
			# Flexes, shifts weight, aggressive stance
			if fmod(_time, 5.0) < 0.4:
				if _left_arm:
					_left_arm.rotation.z = lerp(_left_arm.rotation.z, 0.5, delta * 4)
				if _right_arm:
					_right_arm.rotation.z = lerp(_right_arm.rotation.z, -0.5, delta * 4)

		"Burglar":
			# Shifty, looks around nervously, touches daggers
			if _head:
				_head.rotation.y = sin(_time * 2.5) * 0.2
			idle_bob_speed = 2.5

		"Berserker":
			# Twitchy, barely contained rage
			var twitch: bool = randf() < 0.02
			if twitch and _body:
				_body.rotation.z += (randf() - 0.5) * 0.1
			idle_bob_speed = 3.5

		"Shaman":
			# Communes with spirits, subtle glow pulsing
			if fmod(_time, 4.0) < 1.0:
				var glow: Node = get_node_or_null("SelectionGlow")
				if glow and glow is OmniLight3D:
					glow.light_energy = sin(_time * 3) * 0.3

		"Illusionist":
			# Slightly distorted, shifting presence
			var shift: float = sin(_time * 4) * 0.01
			position.x = _original_position.x + shift
			# Subtle scale fluctuation
			scale = Vector3.ONE * (1.0 + sin(_time * 2) * 0.02)

		"DarkWizard":
			# Dark energy pulsing, skulls floating
			idle_bob_speed = 1.8
			if fmod(_time, 3.0) < 0.1:
				var glow: Node = get_node_or_null("SelectionGlow")
				if glow and glow is OmniLight3D:
					glow.light_color = Color(0.5, 0.2, 0.8)
					glow.light_energy = 0.4

		"Alchemist":
			# Checks equipment, adjusts goggles, shakes flasks
			if fmod(_time, 6.0) < 0.5 and _right_arm:
				_right_arm.rotation.x = lerp(_right_arm.rotation.x, -0.6, delta * 3)
			idle_bob_speed = 2.2


func get_attack_style() -> String:
	"""Get attack animation style for this champion."""
	match champion_name:
		"Brute", "Barbarian", "Berserker":
			return "heavy_melee"
		"Ranger":
			return "ranged_bow"
		"Beast", "Burglar":
			return "quick_melee"
		"Redeemer", "Shaman", "Illusionist", "DarkWizard", "Alchemist":
			return "magic_cast"
		"Confessor":
			return "dark_grasp"
		_:
			return "melee"


func get_death_style() -> String:
	"""Get death animation style for this champion."""
	match champion_name:
		"Brute":
			return "fall_backward"
		"Ranger":
			return "kneel_fall"
		"Beast":
			return "writhe"
		"Redeemer":
			return "peaceful"
		"Confessor":
			return "dissolve"
		"Barbarian":
			return "defiant"
		"Burglar":
			return "fade"
		"Berserker":
			return "rage"
		"Shaman":
			return "spirit_leave"
		"Illusionist":
			return "shatter"
		"DarkWizard":
			return "implode"
		"Alchemist":
			return "explosion"
		_:
			return "fall"


# === HP DISPLAY ===

var _current_hp: int = 20
var _max_hp: int = 20
var _hp_bar: Node3D  # 3D HP bar billboard

func update_hp(current_hp: int, max_hp: int) -> void:
	"""Update HP display."""
	_current_hp = current_hp
	_max_hp = max_hp

	# Update HP bar if it exists
	if _hp_bar:
		_update_hp_bar_visual()

	# Show damage feedback if HP decreased
	if current_hp <= 0 and _is_alive:
		play_death_animation()


func _update_hp_bar_visual() -> void:
	"""Update the visual HP bar representation."""
	var hp_fill_node: Node = _hp_bar.get_node_or_null("Fill")
	if hp_fill_node and hp_fill_node is MeshInstance3D:
		var hp_fill: MeshInstance3D = hp_fill_node as MeshInstance3D
		var ratio: float = float(_current_hp) / float(_max_hp)
		hp_fill.scale.x = ratio

		# Color based on HP
		if hp_fill.material_override and hp_fill.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = hp_fill.material_override as StandardMaterial3D
			if ratio > 0.5:
				mat.albedo_color = Color(0.2, 0.8, 0.2)  # Green
			elif ratio > 0.25:
				mat.albedo_color = Color(0.9, 0.7, 0.1)  # Yellow
			else:
				mat.albedo_color = Color(0.9, 0.2, 0.2)  # Red
