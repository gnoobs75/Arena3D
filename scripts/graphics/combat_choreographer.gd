extends RefCounted
class_name CombatChoreographer
## CombatChoreographer - Orchestrates complex Battle Chess-style combat sequences
## Coordinates multiple champions, camera movements, and VFX

# === SIGNALS ===
signal choreography_started(attacker_id: String, target_id: String)
signal choreography_finished(attacker_id: String, target_id: String)
signal phase_changed(phase_name: String)

# === REFERENCES ===
var board: Board3D
var camera: Camera3D

# === CONFIGURATION ===
var approach_speed: float = 0.35  # Time to walk to target
var attack_speed: float = 0.25   # Time for attack animation
var return_speed: float = 0.3    # Time to walk back
var pause_between_phases: float = 0.1

# Camera settings
var use_combat_camera: bool = true
var combat_zoom: float = 1.5
var camera_transition_time: float = 0.25


func _init(game_board: Board3D = null) -> void:
	board = game_board
	if board:
		camera = board.get_node_or_null("Camera3D")


func set_board(game_board: Board3D) -> void:
	"""Set the board reference."""
	board = game_board
	if board:
		camera = board.get_node_or_null("Camera3D")


# === MAIN CHOREOGRAPHY FUNCTIONS ===

func play_melee_attack(attacker_id: String, target_id: String, damage: int = 0) -> void:
	"""Full Battle Chess melee attack sequence."""
	if not board:
		return

	var attacker: Node3D = board.get_champion_node(attacker_id)
	var target: Node3D = board.get_champion_node(target_id)
	if not attacker or not target:
		return

	choreography_started.emit(attacker_id, target_id)

	var original_pos: Vector3 = attacker.position
	var target_pos: Vector3 = target.position
	var direction: Vector3 = (target_pos - original_pos).normalized()

	# Calculate approach position
	var attack_distance: float = 0.75
	var approach_pos: Vector3 = target_pos - direction * attack_distance

	# Phase 1: Camera zoom (optional)
	phase_changed.emit("camera_focus")
	if use_combat_camera and camera:
		await _focus_camera_on_combat(attacker.position, target.position)

	# Phase 2: Approach
	phase_changed.emit("approach")
	if attacker.position.distance_to(approach_pos) > 0.2:
		await _animate_approach(attacker, approach_pos, direction)
	await _wait(pause_between_phases)

	# Phase 3: Attack
	phase_changed.emit("attack")
	if attacker is Champion3D:
		attacker.play_attack_animation(direction)
		await attacker.animation_finished

	# Phase 4: Hit reaction
	phase_changed.emit("hit_reaction")
	if target is Champion3D:
		target.play_hit_animation(damage)
		# Brief pause to let hit register visually
		await _wait(0.1)

	# Phase 5: Return
	phase_changed.emit("return")
	await _animate_return(attacker, original_pos)

	# Phase 6: Camera reset
	phase_changed.emit("camera_reset")
	if use_combat_camera and camera:
		await _reset_camera()

	choreography_finished.emit(attacker_id, target_id)


func play_ranged_attack(attacker_id: String, target_id: String, damage: int = 0) -> void:
	"""Ranged attack with projectile (no approach)."""
	if not board:
		return

	var attacker: Node3D = board.get_champion_node(attacker_id)
	var target: Node3D = board.get_champion_node(target_id)
	if not attacker or not target:
		return

	choreography_started.emit(attacker_id, target_id)

	var direction: Vector3 = (target.position - attacker.position).normalized()

	# Face target
	if direction.length_squared() > 0.01:
		var target_angle: float = atan2(direction.x, direction.z)
		attacker.rotation.y = target_angle

	# Phase 1: Draw/aim
	phase_changed.emit("aim")
	if attacker is Champion3D:
		attacker.play_cast_animation(true)  # Channeling = hold pose
		await _wait(0.2)

	# Phase 2: Fire (would spawn projectile VFX here)
	phase_changed.emit("fire")
	# TODO: Spawn arrow/projectile VFX traveling to target
	await _wait(0.15)

	# Phase 3: Hit
	phase_changed.emit("hit_reaction")
	if target is Champion3D:
		target.play_hit_animation(damage)
		await _wait(0.1)

	# Return to idle
	if attacker is Champion3D:
		attacker._reset_pose()
		attacker._current_state = Champion3D.AnimState.IDLE

	choreography_finished.emit(attacker_id, target_id)


func play_spell_cast(caster_id: String, target_ids: Array, effect_name: String = "") -> void:
	"""Spell casting sequence with optional targets."""
	if not board:
		return

	var caster: Node3D = board.get_champion_node(caster_id)
	if not caster:
		return

	choreography_started.emit(caster_id, "spell")

	# Gather target positions
	var target_positions: Array = []
	for target_id in target_ids:
		var target: Node3D = board.get_champion_node(target_id)
		if target:
			target_positions.append(target.position)

	# Face toward targets if any
	if target_positions.size() > 0:
		var center: Vector3 = Vector3.ZERO
		for pos in target_positions:
			center += pos
		center /= target_positions.size()

		var direction: Vector3 = (center - caster.position).normalized()
		if direction.length_squared() > 0.01:
			var target_angle: float = atan2(direction.x, direction.z)
			caster.rotation.y = target_angle

	# Phase 1: Channel
	phase_changed.emit("channel")
	if caster is Champion3D:
		caster.play_cast_animation(false)
		await caster.animation_finished

	# Phase 2: Effect on targets (VFX would go here)
	phase_changed.emit("effect")
	# TODO: Spawn spell VFX based on effect_name
	await _wait(0.1)

	# Phase 3: Target reactions
	phase_changed.emit("reactions")
	for target_id in target_ids:
		var target: Node3D = board.get_champion_node(target_id)
		if target and target is Champion3D:
			# Could be hit, buff, debuff, heal based on effect
			target.play_hit_animation(1)

	await _wait(0.2)

	choreography_finished.emit(caster_id, "spell")


func play_death_sequence(champion_id: String, killer_id: String = "") -> void:
	"""Dramatic death sequence."""
	if not board:
		return

	var champion: Node3D = board.get_champion_node(champion_id)
	if not champion:
		return

	choreography_started.emit(champion_id, "death")

	# Optional: killer turns to watch
	if killer_id != "":
		var killer: Node3D = board.get_champion_node(killer_id)
		if killer:
			var direction: Vector3 = (champion.position - killer.position).normalized()
			if direction.length_squared() > 0.01:
				var target_angle: float = atan2(direction.x, direction.z)
				killer.rotation.y = target_angle

	# Camera focus on dying champion
	phase_changed.emit("death_focus")
	if use_combat_camera and camera:
		await _focus_camera_on_position(champion.position, 2.0)

	# Death animation
	phase_changed.emit("death")
	if champion is Champion3D:
		champion.play_death_animation()
		await champion.animation_finished

	# Pause for dramatic effect
	await _wait(0.3)

	# Reset camera
	if use_combat_camera and camera:
		await _reset_camera()

	choreography_finished.emit(champion_id, "death")


# === HELPER FUNCTIONS ===

func _animate_approach(champion: Node3D, target_pos: Vector3, direction: Vector3) -> void:
	"""Animate champion walking toward target position."""
	# Face direction
	if direction.length_squared() > 0.01:
		var target_angle: float = atan2(direction.x, direction.z)
		champion.rotation.y = target_angle

	# Start walk animation
	if champion is Champion3D:
		# Walk animation runs during tween
		@warning_ignore("return_value_discarded")
		champion.play_walk_animation(direction, approach_speed)

	# Tween position
	var tween: Tween = champion.create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(champion, "position", target_pos, approach_speed)

	await tween.finished


func _animate_return(champion: Node3D, original_pos: Vector3) -> void:
	"""Animate champion returning to original position."""
	var direction: Vector3 = (original_pos - champion.position).normalized()

	# Face direction
	if direction.length_squared() > 0.01:
		var target_angle: float = atan2(direction.x, direction.z)
		champion.rotation.y = target_angle

	# Walk animation
	if champion is Champion3D:
		champion.play_walk_animation(-direction, return_speed)

	# Tween position
	var tween: Tween = champion.create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(champion, "position", original_pos, return_speed)

	await tween.finished


func _focus_camera_on_combat(pos_a: Vector3, pos_b: Vector3) -> void:
	"""Focus camera on the combat area."""
	var center: Vector3 = (pos_a + pos_b) / 2
	await _focus_camera_on_position(center, combat_zoom)


func _focus_camera_on_position(world_pos: Vector3, zoom: float = 1.5) -> void:
	"""Smoothly focus camera on a position."""
	if not camera or not camera is CameraController3D:
		return

	var ctrl: CameraController3D = camera
	await ctrl.focus_on_position(world_pos, ctrl.DEFAULT_SIZE / zoom)


func _reset_camera() -> void:
	"""Reset camera to default overview."""
	if not camera or not camera is CameraController3D:
		return

	var ctrl: CameraController3D = camera
	await ctrl.reset_view()


func _wait(duration: float) -> void:
	"""Wait for a duration."""
	if board:
		await board.get_tree().create_timer(duration).timeout
