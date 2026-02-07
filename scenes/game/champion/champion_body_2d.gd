extends Node2D
class_name ChampionVisual
## ChampionBody2D - Articulated 2D champion with procedural body parts and animations
## Replaces the old single-sprite ChampionVisual with multi-part articulated characters

signal animation_finished(anim_name: String)

enum AnimState { IDLE, WALK, ATTACK, HIT, CAST, DEATH, HEAL, BUFF, DEBUFF }

const TOKEN_SIZE := 52
const SPRITE_SCALE := 0.12  # Kept for API compatibility

var champion_state: ChampionState
var owner_id: int = 1
var champion_name: String = ""
var current_hp: int = 20
var max_hp: int = 20
var is_selected: bool = false

# Appearance data
var appearance: ChampionAppearance

# Body part nodes
var _body_container: Node2D  # Main body (rotates for death)
var _head: Node2D
var _torso: Node2D
var _left_arm_joint: Node2D  # Shoulder pivot
var _right_arm_joint: Node2D
var _left_arm: Node2D
var _right_arm: Node2D
var _left_leg: Node2D
var _right_leg: Node2D
var _weapon: Node2D
var _left_weapon: Node2D
var _shadow: Node2D
var _effects: Node2D  # Glow, halo, etc.

# UI elements
var _hp_bar: Control
var _selection_indicator: Node2D

# Animation state
var _current_anim: AnimState = AnimState.IDLE
var _anim_tween: Tween
var _idle_tween: Tween
var _idle_time: float = 0.0
var _team_color: Color = Color.WHITE


func _ready() -> void:
	if appearance == null:
		appearance = ChampionAppearance.new()
	if _body_container == null:
		_build_body()
	_start_idle_animation()


func setup(champ: ChampionState) -> void:
	"""Initialize with champion data."""
	champion_state = champ
	current_hp = champ.current_hp
	max_hp = champ.max_hp
	owner_id = champ.owner_id
	champion_name = champ.champion_name

	# Create appearance from champion name
	appearance = ChampionAppearance.create_for_champion(champion_name)

	# Build the body
	_build_body()

	# Apply team color
	_team_color = VisualTheme.get_player_color(owner_id)
	_apply_team_tint()

	# Update HP bar
	_update_hp_bar()


func _build_body() -> void:
	"""Construct the articulated body hierarchy."""
	# Clean existing
	for child in get_children():
		child.queue_free()

	var app := appearance
	var scale_factor := app.body_scale

	# Shadow
	_shadow = Node2D.new()
	_shadow.name = "Shadow"
	_shadow.position = Vector2(0, (app.torso_height / 2 + app.leg_length) * scale_factor - 2)
	add_child(_shadow)
	var shadow_drawer := _ShadowDrawer.new()
	shadow_drawer.radius_x = app.shoulder_width * scale_factor * 0.6
	shadow_drawer.radius_y = 3.0
	_shadow.add_child(shadow_drawer)

	# Selection indicator
	_selection_indicator = Node2D.new()
	_selection_indicator.name = "SelectionIndicator"
	_selection_indicator.visible = false
	add_child(_selection_indicator)
	var ring := _SelectionRing.new()
	ring.ring_radius = TOKEN_SIZE * 0.55
	_selection_indicator.add_child(ring)

	# Body container (everything inside this rotates together for death)
	_body_container = Node2D.new()
	_body_container.name = "BodyContainer"
	if app.is_floating:
		_body_container.position.y = -app.float_height
	if app.is_hunched:
		_body_container.rotation = deg_to_rad(8)
		_body_container.position.y += 3
	add_child(_body_container)

	# Calculate vertical positions (character stands with feet near bottom)
	var foot_y := (app.torso_height / 2 + app.leg_length) * scale_factor
	var hip_y := foot_y - app.leg_length * scale_factor
	var torso_center_y := hip_y - app.torso_height * scale_factor / 2
	var shoulder_y := hip_y - app.torso_height * scale_factor
	var head_y := shoulder_y - app.head_radius * scale_factor

	# Offset everything up so character is centered vertically
	var center_offset_y := -foot_y / 2 - 4

	# Legs
	_left_leg = Node2D.new()
	_left_leg.name = "LeftLeg"
	_left_leg.position = Vector2(-app.torso_width * scale_factor * 0.25, hip_y + center_offset_y)
	_body_container.add_child(_left_leg)
	var ll := _LimbDrawer.new()
	ll.limb_length = app.leg_length * scale_factor
	ll.limb_width = app.leg_width * scale_factor
	ll.limb_color = app.primary_color.lerp(Color.BLACK, 0.3)
	ll.joint_color = app.primary_color.lerp(Color.BLACK, 0.2)
	_left_leg.add_child(ll)

	_right_leg = Node2D.new()
	_right_leg.name = "RightLeg"
	_right_leg.position = Vector2(app.torso_width * scale_factor * 0.25, hip_y + center_offset_y)
	_body_container.add_child(_right_leg)
	var rl := _LimbDrawer.new()
	rl.limb_length = app.leg_length * scale_factor
	rl.limb_width = app.leg_width * scale_factor
	rl.limb_color = app.primary_color.lerp(Color.BLACK, 0.3)
	rl.joint_color = app.primary_color.lerp(Color.BLACK, 0.2)
	_right_leg.add_child(rl)

	# Cloak (behind torso)
	if app.has_cloak:
		var cloak := _CloakDrawer.new()
		cloak.cloak_width = app.shoulder_width * scale_factor * 1.2
		cloak.cloak_height = (app.torso_height + app.leg_length * 0.6) * scale_factor
		cloak.cloak_color = app.secondary_color.lerp(Color.BLACK, 0.4)
		cloak.position = Vector2(0, shoulder_y + center_offset_y)
		_body_container.add_child(cloak)

	# Torso
	_torso = Node2D.new()
	_torso.name = "Torso"
	_torso.position = Vector2(0, torso_center_y + center_offset_y)
	_body_container.add_child(_torso)
	var torso_drawer := _TorsoDrawer.new()
	torso_drawer.torso_width = app.torso_width * scale_factor
	torso_drawer.torso_height = app.torso_height * scale_factor
	torso_drawer.shoulder_width = app.shoulder_width * scale_factor
	torso_drawer.primary_color = app.primary_color
	torso_drawer.secondary_color = app.secondary_color
	torso_drawer.has_robe = app.has_robe
	torso_drawer.has_lacing = app.has_lacing
	torso_drawer.has_coat = app.has_coat
	torso_drawer.coat_color = app.coat_color
	_torso.add_child(torso_drawer)

	# Backpack (behind arms, on torso)
	if app.has_backpack:
		var bp := _BackpackDrawer.new()
		bp.bp_color = app.accent_color.lerp(Color.BLACK, 0.3)
		bp.position = Vector2(app.torso_width * scale_factor * 0.4, 0)
		_torso.add_child(bp)

	# Arms
	_left_arm_joint = Node2D.new()
	_left_arm_joint.name = "LeftArmJoint"
	_left_arm_joint.position = Vector2(-app.shoulder_width * scale_factor / 2, shoulder_y + center_offset_y + 2)
	_body_container.add_child(_left_arm_joint)

	_left_arm = Node2D.new()
	_left_arm.name = "LeftArm"
	_left_arm_joint.add_child(_left_arm)
	var la := _LimbDrawer.new()
	la.limb_length = app.arm_length * scale_factor
	la.limb_width = app.arm_width * scale_factor
	la.limb_color = app.skin_color.lerp(app.primary_color, 0.3)
	la.joint_color = app.skin_color
	la.has_hand = true
	la.hand_color = app.skin_color
	_left_arm.add_child(la)

	_right_arm_joint = Node2D.new()
	_right_arm_joint.name = "RightArmJoint"
	_right_arm_joint.position = Vector2(app.shoulder_width * scale_factor / 2, shoulder_y + center_offset_y + 2)
	_body_container.add_child(_right_arm_joint)

	_right_arm = Node2D.new()
	_right_arm.name = "RightArm"
	_right_arm_joint.add_child(_right_arm)
	var ra := _LimbDrawer.new()
	ra.limb_length = app.arm_length * scale_factor
	ra.limb_width = app.arm_width * scale_factor
	ra.limb_color = app.skin_color.lerp(app.primary_color, 0.3)
	ra.joint_color = app.skin_color
	ra.has_hand = true
	ra.hand_color = app.skin_color
	_right_arm.add_child(ra)

	# Arm bands
	if app.has_arm_bands:
		var lab := _ArmBandDrawer.new()
		lab.band_color = app.arm_band_color
		lab.arm_width = app.arm_width * scale_factor
		lab.position = Vector2(0, app.arm_length * scale_factor * 0.25)
		_left_arm.add_child(lab)
		var rab := _ArmBandDrawer.new()
		rab.band_color = app.arm_band_color
		rab.arm_width = app.arm_width * scale_factor
		rab.position = Vector2(0, app.arm_length * scale_factor * 0.25)
		_right_arm.add_child(rab)

	# Weapon (attached to right arm)
	_weapon = Node2D.new()
	_weapon.name = "Weapon"
	if app.weapon_type != "none":
		var weapon_drawer := _WeaponDrawer.new()
		weapon_drawer.weapon_type = app.weapon_type
		weapon_drawer.weapon_color = app.accent_color
		weapon_drawer.arm_length = app.arm_length * scale_factor
		weapon_drawer.weapon_scale = app.weapon_scale
		weapon_drawer.has_crystal = app.has_staff_crystal
		weapon_drawer.crystal_color = app.crystal_color
		_weapon.add_child(weapon_drawer)
	_right_arm.add_child(_weapon)

	# Left weapon (dual-wield)
	if app.dual_wield and app.left_weapon_type != "none":
		_left_weapon = Node2D.new()
		_left_weapon.name = "LeftWeapon"
		var lw_drawer := _WeaponDrawer.new()
		lw_drawer.weapon_type = app.left_weapon_type
		lw_drawer.weapon_color = app.accent_color
		lw_drawer.arm_length = app.arm_length * scale_factor
		lw_drawer.weapon_scale = app.weapon_scale
		_left_weapon.add_child(lw_drawer)
		_left_arm.add_child(_left_weapon)

	# Head
	_head = Node2D.new()
	_head.name = "Head"
	_head.position = Vector2(0, head_y + center_offset_y)
	_body_container.add_child(_head)
	var head_drawer := _HeadDrawer.new()
	head_drawer.head_radius = app.head_radius * scale_factor
	head_drawer.skin_color = app.skin_color
	head_drawer.has_hood = app.has_hood
	head_drawer.hood_color = app.primary_color.lerp(Color.BLACK, 0.2)
	head_drawer.has_goggles = app.has_goggles
	head_drawer.goggle_color = app.accent_color
	head_drawer.has_blindfold = app.has_blindfold
	head_drawer.blindfold_color = app.blindfold_color
	head_drawer.has_antlers = (app.beast_form == "elk")
	# Art-inspired features
	head_drawer.hair_style = app.hair_style
	head_drawer.hair_color = app.hair_color
	head_drawer.hair_size = app.hair_size
	head_drawer.has_tusks = app.has_tusks
	head_drawer.has_beard = app.has_beard
	head_drawer.beard_color = app.beard_color
	head_drawer.has_horns = app.has_horns
	head_drawer.horn_color = app.horn_color
	head_drawer.has_pointed_ears = app.has_pointed_ears
	head_drawer.has_face_mask = app.has_face_mask
	head_drawer.mask_color = app.mask_color
	head_drawer.eye_style = app.eye_style
	head_drawer.eye_glow_color = app.eye_glow_color
	_head.add_child(head_drawer)

	# Halo
	if app.has_halo:
		var halo := _HaloDrawer.new()
		halo.halo_color = app.accent_color
		halo.position = Vector2(0, -app.head_radius * scale_factor - 4)
		_head.add_child(halo)

	# Effects layer (glow, aura)
	_effects = Node2D.new()
	_effects.name = "Effects"
	_body_container.add_child(_effects)
	if app.has_glow:
		var glow := _GlowDrawer.new()
		glow.glow_color = app.glow_color
		glow.glow_radius = TOKEN_SIZE * 0.5
		_effects.add_child(glow)

	# Hand glow (Redeemer)
	if app.has_hand_glow:
		var left_glow := _HandGlowDrawer.new()
		left_glow.glow_color = app.hand_glow_color
		_left_arm.add_child(left_glow)
		left_glow.position = Vector2(0, app.arm_length * scale_factor)
		var right_glow := _HandGlowDrawer.new()
		right_glow.glow_color = app.hand_glow_color
		_right_arm.add_child(right_glow)
		right_glow.position = Vector2(0, app.arm_length * scale_factor)

	# Electricity (Shaman)
	if app.has_electricity:
		var elec := _ElectricityDrawer.new()
		elec.electricity_color = app.electricity_color
		elec.body_height = (app.torso_height + app.leg_length * 0.5) * scale_factor
		_effects.add_child(elec)

	# Smoke wisps (Illusionist)
	if app.has_smoke_wisps:
		var wisps := _SmokeWispDrawer.new()
		wisps.smoke_color = app.smoke_color
		_effects.add_child(wisps)

	# Dark butterflies (DarkWizard)
	if app.has_dark_butterflies:
		var butterflies := _DarkButterflyDrawer.new()
		butterflies.butterfly_color = app.butterfly_color
		_effects.add_child(butterflies)

	# Dark aura (DarkWizard)
	if app.has_dark_aura:
		var aura := _DarkAuraDrawer.new()
		aura.aura_color = app.dark_aura_color
		_effects.add_child(aura)

	# Potion smoke (Alchemist)
	if app.has_potion_smoke:
		var psmoke := _PotionSmokeDrawer.new()
		psmoke.smoke_color = app.potion_smoke_color
		_effects.add_child(psmoke)

	# Shadow spirit (Beast)
	if app.has_shadow_spirit:
		var spirit := _ShadowSpiritDrawer.new()
		_effects.add_child(spirit)

	# HP bar at bottom
	_hp_bar = _HPBarDrawer.new()
	_hp_bar.name = "HPBar"
	_hp_bar.position = Vector2(-TOKEN_SIZE / 2, foot_y + center_offset_y + 4)
	add_child(_hp_bar)


func _apply_team_tint() -> void:
	"""Apply subtle team color to body parts."""
	# Tint is applied via modulate on body container
	_body_container.modulate = Color.WHITE.lerp(_team_color, 0.12)


func update_hp(hp: int, max_val: int) -> void:
	"""Update HP display."""
	var old_hp := current_hp
	current_hp = hp
	max_hp = max_val
	_update_hp_bar()
	if hp < old_hp:
		_flash_damage()


func _update_hp_bar() -> void:
	if _hp_bar and _hp_bar is _HPBarDrawer:
		(_hp_bar as _HPBarDrawer).set_hp(current_hp, max_hp, owner_id)


func set_selected(selected: bool) -> void:
	is_selected = selected
	if _selection_indicator:
		_selection_indicator.visible = selected
		var ring := _selection_indicator.get_child(0)
		if ring and ring.has_method("start_pulse") and selected:
			ring.start_pulse()


# === IDLE ANIMATION ===

func _start_idle_animation() -> void:
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_time = 0.0


func _process(delta: float) -> void:
	if _current_anim == AnimState.IDLE or _current_anim == AnimState.WALK:
		_idle_time += delta * (appearance.idle_speed if appearance else 1.0)
		_update_idle()


func _update_idle() -> void:
	"""Procedural idle animation - breathing, sway."""
	if _body_container == null or appearance == null:
		return
	if _current_anim != AnimState.IDLE:
		return

	var intensity := appearance.idle_intensity
	var t := _idle_time

	# Breathing - torso slight scale
	if _torso:
		_torso.scale.y = 1.0 + sin(t * 2.5) * 0.015 * intensity

	# Subtle body sway
	if _body_container and not appearance.is_floating:
		_body_container.rotation = sin(t * 1.2) * 0.012 * intensity

	# Head bob
	if _head:
		_head.position.y += sin(t * 2.5) * 0.08 * intensity - sin((t - 0.01) * 2.5) * 0.08 * intensity

	# Arm sway
	if _left_arm_joint:
		_left_arm_joint.rotation = sin(t * 1.5) * 0.06 * intensity
	if _right_arm_joint:
		_right_arm_joint.rotation = sin(t * 1.5 + PI) * 0.06 * intensity

	# Floating bob for floating champions
	if appearance.is_floating and _body_container:
		_body_container.position.y = -appearance.float_height + sin(t * 1.8) * 2.0


func _flash_damage() -> void:
	if _anim_tween and _anim_tween.is_valid():
		return  # Don't interrupt attack/cast animations
	var tween := create_tween()
	tween.tween_property(_body_container, "modulate", Color(1.5, 0.3, 0.3), 0.08)
	tween.tween_callback(func(): _body_container.modulate = Color.WHITE.lerp(_team_color, 0.12))


# === ANIMATION METHODS ===

func play_walk_animation(direction: Vector2) -> void:
	_current_anim = AnimState.WALK
	_kill_anim_tween()
	_anim_tween = create_tween()

	var dur := 0.35
	var step_count := 3

	# Face direction
	if direction.x < -0.1 and _body_container:
		_body_container.scale.x = -1.0
	elif direction.x > 0.1 and _body_container:
		_body_container.scale.x = 1.0

	for i in range(step_count):
		var t := float(i) / step_count
		# Leg swing
		_anim_tween.tween_property(_left_leg, "rotation", deg_to_rad(25), dur / step_count / 2)
		_anim_tween.parallel().tween_property(_right_leg, "rotation", deg_to_rad(-25), dur / step_count / 2)
		_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", deg_to_rad(-20), dur / step_count / 2)
		_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(20), dur / step_count / 2)
		# Body bob
		_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y - 2, dur / step_count / 2)

		_anim_tween.tween_property(_left_leg, "rotation", deg_to_rad(-25), dur / step_count / 2)
		_anim_tween.parallel().tween_property(_right_leg, "rotation", deg_to_rad(25), dur / step_count / 2)
		_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", deg_to_rad(20), dur / step_count / 2)
		_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(-20), dur / step_count / 2)
		_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y, dur / step_count / 2)

	# Return to neutral
	_anim_tween.tween_property(_left_leg, "rotation", 0.0, 0.1)
	_anim_tween.parallel().tween_property(_right_leg, "rotation", 0.0, 0.1)
	_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", 0.0, 0.1)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", 0.0, 0.1)
	_anim_tween.parallel().tween_property(_body_container, "scale:x", 1.0, 0.1)

	_anim_tween.tween_callback(func():
		_current_anim = AnimState.IDLE
		animation_finished.emit("walk")
	)


func play_attack_animation(target_direction: Vector2) -> void:
	_current_anim = AnimState.ATTACK
	_kill_anim_tween()
	_anim_tween = create_tween()

	# Face target
	if target_direction.x < -0.1 and _body_container:
		_body_container.scale.x = -1.0
	elif target_direction.x > 0.1 and _body_container:
		_body_container.scale.x = 1.0

	# Check for champion-specific override first
	var override := appearance.attack_style_override if appearance else ""
	if override != "":
		match override:
			"dance":
				_play_dance_attack()
			"dual_melee":
				_play_dual_melee_attack()
			"dual_axe":
				_play_dual_axe_attack()
			"electric":
				_play_electric_attack()
			_:
				_play_melee_attack(target_direction)
	else:
		var style := appearance.attack_style if appearance else "melee"
		match style:
			"heavy":
				_play_heavy_attack()
			"ranged":
				_play_ranged_attack(target_direction)
			"magic":
				_play_magic_attack()
			_:
				_play_melee_attack(target_direction)

	_anim_tween.tween_callback(func():
		_body_container.scale.x = 1.0
		_current_anim = AnimState.IDLE
		animation_finished.emit("attack")
	)


func _play_melee_attack(direction: Vector2) -> void:
	var lunge := direction.normalized() * 8
	# Wind up
	_anim_tween.tween_property(_right_arm_joint, "rotation", deg_to_rad(-60), 0.08)
	_anim_tween.parallel().tween_property(_torso, "rotation", deg_to_rad(-5), 0.08)
	# Lunge and swing
	_anim_tween.tween_property(_body_container, "position", _body_container.position + lunge, 0.06).set_trans(Tween.TRANS_BACK)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(45), 0.06)
	_anim_tween.parallel().tween_property(_torso, "rotation", deg_to_rad(8), 0.06)
	# Hold
	_anim_tween.tween_interval(0.06)
	# Return
	_anim_tween.tween_property(_body_container, "position", _body_container.position, 0.12)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", 0.0, 0.12)
	_anim_tween.parallel().tween_property(_torso, "rotation", 0.0, 0.12)


func _play_heavy_attack() -> void:
	# Big wind up with both arms
	_anim_tween.tween_property(_right_arm_joint, "rotation", deg_to_rad(-80), 0.12)
	_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", deg_to_rad(-40), 0.12)
	_anim_tween.parallel().tween_property(_torso, "rotation", deg_to_rad(-10), 0.12)
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y - 3, 0.12)
	# Slam down
	_anim_tween.tween_property(_right_arm_joint, "rotation", deg_to_rad(60), 0.06)
	_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", deg_to_rad(30), 0.06)
	_anim_tween.parallel().tween_property(_torso, "rotation", deg_to_rad(12), 0.06)
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y + 2, 0.06)
	# Hold impact
	_anim_tween.tween_interval(0.08)
	# Return
	_anim_tween.tween_property(_right_arm_joint, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_property(_torso, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y, 0.15)


func _play_ranged_attack(direction: Vector2) -> void:
	# Draw bow / aim
	_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(-40), 0.12)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(-70), 0.12)
	# Hold aim
	_anim_tween.tween_interval(0.1)
	# Release
	_anim_tween.tween_property(_right_arm_joint, "rotation", deg_to_rad(10), 0.04)
	_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", deg_to_rad(-10), 0.04)
	# Recoil
	_anim_tween.tween_interval(0.08)
	# Return
	_anim_tween.tween_property(_right_arm_joint, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", 0.0, 0.15)


func _play_magic_attack() -> void:
	# Raise both arms
	_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(-70), 0.12)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(-70), 0.12)
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y - 3, 0.12)
	# Flash glow
	_anim_tween.tween_property(_body_container, "modulate", Color(1.4, 1.4, 1.6), 0.08)
	# Thrust arms forward
	_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(20), 0.06)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(20), 0.06)
	# Hold
	_anim_tween.tween_interval(0.08)
	# Return
	_anim_tween.tween_property(_left_arm_joint, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y, 0.15)
	_anim_tween.parallel().tween_callback(_apply_team_tint)


func _play_dance_attack() -> void:
	"""Confessor - Spin 360 with arms extended, graceful landing."""
	# Arms out
	_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(-50), 0.08)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(-50), 0.08)
	# Rise up
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y - 5, 0.08)
	# Spin 360
	_anim_tween.tween_property(_body_container, "rotation", deg_to_rad(360), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# Flash on spin completion
	_anim_tween.tween_property(_body_container, "modulate", Color(1.3, 1.2, 1.5), 0.04)
	# Graceful landing
	_anim_tween.tween_property(_body_container, "position:y", _body_container.position.y, 0.12).set_trans(Tween.TRANS_BOUNCE)
	_anim_tween.parallel().tween_property(_body_container, "rotation", 0.0, 0.01)
	# Arms return
	_anim_tween.tween_property(_left_arm_joint, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_callback(_apply_team_tint)


func _play_dual_melee_attack() -> void:
	"""Burglar - Alternating quick left/right slashes, fast tempo."""
	# Quick left slash
	_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(40), 0.04)
	_anim_tween.parallel().tween_property(_torso, "rotation", deg_to_rad(5), 0.04)
	_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(-10), 0.04)
	# Quick right slash
	_anim_tween.tween_property(_right_arm_joint, "rotation", deg_to_rad(40), 0.04)
	_anim_tween.parallel().tween_property(_torso, "rotation", deg_to_rad(-5), 0.04)
	_anim_tween.tween_property(_right_arm_joint, "rotation", deg_to_rad(-10), 0.04)
	# Second left (faster)
	_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(35), 0.03)
	_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(-5), 0.03)
	# Second right
	_anim_tween.tween_property(_right_arm_joint, "rotation", deg_to_rad(35), 0.03)
	_anim_tween.tween_property(_right_arm_joint, "rotation", deg_to_rad(-5), 0.03)
	# Return
	_anim_tween.tween_property(_left_arm_joint, "rotation", 0.0, 0.08)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", 0.0, 0.08)
	_anim_tween.parallel().tween_property(_torso, "rotation", 0.0, 0.08)


func _play_dual_axe_attack() -> void:
	"""Berserker - Wide overhead slam with both axes, shake on impact."""
	# Both arms way up
	_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(-90), 0.1)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(-90), 0.1)
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y - 4, 0.1)
	# Hold at apex
	_anim_tween.tween_interval(0.05)
	# Slam down hard
	_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(50), 0.05)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(50), 0.05)
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y + 3, 0.05)
	# Impact shake
	_anim_tween.tween_property(_body_container, "position:x", _body_container.position.x + 3, 0.02)
	_anim_tween.tween_property(_body_container, "position:x", _body_container.position.x - 3, 0.02)
	_anim_tween.tween_property(_body_container, "position:x", _body_container.position.x + 2, 0.02)
	_anim_tween.tween_property(_body_container, "position:x", _body_container.position.x, 0.02)
	# Recover
	_anim_tween.tween_property(_left_arm_joint, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y, 0.15)


func _play_electric_attack() -> void:
	"""Shaman - Channel pose, electric blue flash, thrust forward."""
	# Channel pose - staff raised, arms up
	_anim_tween.tween_property(_right_arm_joint, "rotation", deg_to_rad(-75), 0.12)
	_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", deg_to_rad(-30), 0.12)
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y - 2, 0.12)
	# Hold and flash electric blue
	_anim_tween.tween_interval(0.06)
	_anim_tween.tween_property(_body_container, "modulate", Color(0.6, 1.2, 1.8), 0.04)
	# Thrust forward
	_anim_tween.tween_property(_right_arm_joint, "rotation", deg_to_rad(30), 0.06)
	_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", deg_to_rad(15), 0.06)
	# Brief bright flash
	_anim_tween.tween_property(_body_container, "modulate", Color(0.8, 1.5, 2.0), 0.03)
	# Hold
	_anim_tween.tween_interval(0.06)
	# Return
	_anim_tween.tween_property(_right_arm_joint, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", 0.0, 0.15)
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y, 0.15)
	_anim_tween.parallel().tween_callback(_apply_team_tint)


func play_hit_animation() -> void:
	_current_anim = AnimState.HIT
	_kill_anim_tween()
	_anim_tween = create_tween()

	# Flash red
	_anim_tween.tween_property(_body_container, "modulate", Color(1.5, 0.3, 0.3), 0.04)
	# Recoil
	_anim_tween.parallel().tween_property(_body_container, "position:x", _body_container.position.x - 3, 0.04)
	_anim_tween.tween_property(_body_container, "position:x", _body_container.position.x + 3, 0.04)
	_anim_tween.tween_property(_body_container, "position:x", _body_container.position.x - 2, 0.04)
	_anim_tween.tween_property(_body_container, "position:x", _body_container.position.x, 0.04)
	# Head snap back
	_anim_tween.parallel().tween_property(_head, "rotation", deg_to_rad(-15), 0.06)
	_anim_tween.tween_property(_head, "rotation", 0.0, 0.1)
	# Restore color
	_anim_tween.tween_callback(_apply_team_tint)
	_anim_tween.tween_callback(func():
		_current_anim = AnimState.IDLE
		animation_finished.emit("hit")
	)


func play_cast_animation() -> void:
	_current_anim = AnimState.CAST
	_kill_anim_tween()
	_anim_tween = create_tween()

	# Confessor uses dance-cast variant
	var override := appearance.attack_style_override if appearance else ""
	if override == "dance":
		# Graceful spin cast
		_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(-60), 0.1)
		_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(-60), 0.1)
		_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y - 4, 0.1)
		# Half spin with glow
		_anim_tween.tween_property(_body_container, "rotation", deg_to_rad(180), 0.15)
		_anim_tween.parallel().tween_property(_body_container, "modulate", Color(1.2, 1.1, 1.5), 0.1)
		# Complete spin
		_anim_tween.tween_property(_body_container, "rotation", deg_to_rad(360), 0.15)
		_anim_tween.tween_property(_body_container, "rotation", 0.0, 0.01)
		# Arms down, land
		_anim_tween.tween_property(_left_arm_joint, "rotation", 0.0, 0.15)
		_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", 0.0, 0.15)
		_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y, 0.15)
		_anim_tween.parallel().tween_callback(_apply_team_tint)
	else:
		# Standard cast
		# Raise arms
		_anim_tween.tween_property(_left_arm_joint, "rotation", deg_to_rad(-80), 0.15)
		_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(-80), 0.15)
		_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y - 4, 0.15)
		# Glow
		_anim_tween.tween_property(_body_container, "modulate", Color(1.3, 1.3, 1.6), 0.1)
		# Hold
		_anim_tween.tween_interval(0.15)
		# Release
		_anim_tween.tween_property(_left_arm_joint, "rotation", 0.0, 0.2)
		_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", 0.0, 0.2)
		_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y, 0.2)
		_anim_tween.parallel().tween_callback(_apply_team_tint)

	_anim_tween.tween_callback(func():
		_current_anim = AnimState.IDLE
		animation_finished.emit("cast")
	)


func play_death_animation() -> void:
	_current_anim = AnimState.DEATH
	_kill_anim_tween()
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()

	_anim_tween = create_tween()

	# Stagger
	_anim_tween.tween_property(_body_container, "position:x", _body_container.position.x - 2, 0.1)
	# Collapse legs
	_anim_tween.tween_property(_left_leg, "rotation", deg_to_rad(45), 0.2)
	_anim_tween.parallel().tween_property(_right_leg, "rotation", deg_to_rad(-45), 0.2)
	# Fall
	_anim_tween.parallel().tween_property(_body_container, "rotation", deg_to_rad(85), 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	_anim_tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y + 8, 0.35)
	# Arms go limp
	_anim_tween.parallel().tween_property(_left_arm_joint, "rotation", deg_to_rad(60), 0.25)
	_anim_tween.parallel().tween_property(_right_arm_joint, "rotation", deg_to_rad(60), 0.25)
	# Fade
	_anim_tween.tween_property(self, "modulate:a", 0.0, 0.4).set_delay(0.1)
	# HP bar and shadow
	_anim_tween.parallel().tween_property(_hp_bar, "modulate:a", 0.0, 0.2)
	_anim_tween.parallel().tween_property(_shadow, "modulate:a", 0.0, 0.2)
	_anim_tween.tween_callback(func(): animation_finished.emit("death"))


func play_heal_animation() -> void:
	if _anim_tween and _anim_tween.is_valid():
		return
	var tween := create_tween()
	tween.tween_property(_body_container, "modulate", Color(0.5, 1.5, 0.5), 0.15)
	tween.parallel().tween_property(_body_container, "position:y", _body_container.position.y - 3, 0.15)
	tween.tween_property(_body_container, "position:y", _body_container.position.y, 0.2)
	tween.parallel().tween_callback(_apply_team_tint)
	tween.tween_callback(func(): animation_finished.emit("heal"))


func play_buff_animation() -> void:
	if _anim_tween and _anim_tween.is_valid():
		return
	var tween := create_tween()
	tween.tween_property(_body_container, "modulate", Color(0.5, 1.3, 1.5), 0.12)
	tween.parallel().tween_property(_body_container, "scale", Vector2(1.08, 1.08), 0.12)
	tween.tween_property(_body_container, "scale", Vector2(1.0, 1.0), 0.15)
	tween.parallel().tween_callback(_apply_team_tint)
	tween.tween_callback(func(): animation_finished.emit("buff"))


func play_debuff_animation() -> void:
	if _anim_tween and _anim_tween.is_valid():
		return
	var tween := create_tween()
	tween.tween_property(_body_container, "modulate", Color(1.3, 0.5, 1.3), 0.12)
	tween.parallel().tween_property(_body_container, "scale", Vector2(0.93, 0.93), 0.12)
	tween.tween_property(_body_container, "scale", Vector2(1.0, 1.0), 0.15)
	tween.parallel().tween_callback(_apply_team_tint)
	tween.tween_callback(func(): animation_finished.emit("debuff"))


# === BEAST TRANSFORMATION ===

func set_beast_form(form: String) -> void:
	"""Transform Beast champion between forms. Forms: base, bear, elk, ape."""
	if appearance == null:
		return
	if form == appearance.beast_form:
		return
	appearance.beast_form = form

	var tween := create_tween()
	tween.set_parallel(true)

	match form:
		"bear":
			# Bigger, darker, bulkier
			tween.tween_property(_body_container, "scale", Vector2(1.2, 1.15), 0.3)
			tween.tween_property(_body_container, "modulate", Color(0.6, 0.45, 0.3).lerp(_team_color, 0.12), 0.3)
		"elk":
			# Taller, add antlers via head redraw
			tween.tween_property(_body_container, "scale", Vector2(0.95, 1.2), 0.3)
			tween.tween_property(_body_container, "modulate", Color(0.7, 0.6, 0.4).lerp(_team_color, 0.12), 0.3)
			# Update head to show antlers
			if _head and _head.get_child_count() > 0:
				var head_drawer = _head.get_child(0)
				if head_drawer is _HeadDrawer:
					head_drawer.has_antlers = true
					head_drawer.queue_redraw()
		"ape":
			# Hunched, big arms
			tween.tween_property(_body_container, "scale", Vector2(1.15, 1.0), 0.3)
			tween.tween_property(_body_container, "modulate", Color(0.45, 0.35, 0.3).lerp(_team_color, 0.12), 0.3)
			tween.tween_property(_body_container, "rotation", deg_to_rad(10), 0.3)
		_:  # "base" - revert
			tween.tween_property(_body_container, "scale", Vector2(1.0, 1.0), 0.3)
			tween.tween_callback(_apply_team_tint)
			if appearance.is_hunched:
				tween.tween_property(_body_container, "rotation", deg_to_rad(8), 0.3)
			else:
				tween.tween_property(_body_container, "rotation", 0.0, 0.3)
			# Remove antlers
			if _head and _head.get_child_count() > 0:
				var head_drawer = _head.get_child(0)
				if head_drawer is _HeadDrawer:
					head_drawer.has_antlers = false
					head_drawer.queue_redraw()


func _kill_anim_tween() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()


# =============================================================================
# INNER CLASSES - Body Part Drawers
# =============================================================================

class _ShadowDrawer extends Node2D:
	var radius_x: float = 12.0
	var radius_y: float = 3.0

	func _draw() -> void:
		# Ellipse shadow
		var points := PackedVector2Array()
		for i in range(16):
			var angle := TAU * i / 16.0
			points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
		draw_colored_polygon(points, Color(0, 0, 0, 0.25))


class _SelectionRing extends Node2D:
	var ring_radius: float = 28.0
	var _alpha: float = 0.8
	var _pulse_tween: Tween

	func _draw() -> void:
		var color := VisualTheme.HIGHLIGHT_SELECTED_BORDER
		color.a = _alpha
		draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 32, color, 2.5, true)

	func start_pulse() -> void:
		if _pulse_tween and _pulse_tween.is_valid():
			_pulse_tween.kill()
		_pulse_tween = create_tween()
		_pulse_tween.set_loops()
		_pulse_tween.tween_property(self, "_alpha", 0.3, 0.5)
		_pulse_tween.tween_property(self, "_alpha", 0.8, 0.5)

	func _process(_delta: float) -> void:
		queue_redraw()


class _TorsoDrawer extends Node2D:
	var torso_width: float = 12.0
	var torso_height: float = 14.0
	var shoulder_width: float = 14.0
	var primary_color: Color = Color(0.4, 0.4, 0.4)
	var secondary_color: Color = Color(0.5, 0.5, 0.5)
	var has_robe: bool = false
	var has_lacing: bool = false
	var has_coat: bool = false
	var coat_color: Color = Color(0.9, 0.9, 0.9)

	func _draw() -> void:
		var hw := shoulder_width / 2.0
		var bw := torso_width / 2.0
		var hh := torso_height / 2.0

		# Lab coat (behind main torso, Alchemist)
		if has_coat:
			var coat_hw := hw + 2
			var coat_pts := PackedVector2Array([
				Vector2(-coat_hw, -hh),
				Vector2(coat_hw, -hh),
				Vector2(bw + 4, hh + torso_height * 0.6),
				Vector2(-bw - 4, hh + torso_height * 0.6),
			])
			var coat_cols := PackedColorArray()
			coat_cols.append(coat_color)
			coat_cols.append(coat_color)
			coat_cols.append(coat_color.lerp(Color.BLACK, 0.15))
			coat_cols.append(coat_color.lerp(Color.BLACK, 0.15))
			draw_polygon(coat_pts, coat_cols)
			# Coat border
			for i in range(coat_pts.size()):
				var next := (i + 1) % coat_pts.size()
				draw_line(coat_pts[i], coat_pts[next], coat_color.lerp(Color.BLACK, 0.25), 0.8, true)

		# Torso shape (trapezoid - wider at shoulders)
		var points := PackedVector2Array([
			Vector2(-hw, -hh),
			Vector2(hw, -hh),
			Vector2(bw, hh),
			Vector2(-bw, hh),
		])

		# Gradient fill
		var colors := PackedColorArray()
		var top_color := secondary_color.lerp(Color.WHITE, 0.1)
		var bot_color := primary_color.lerp(Color.BLACK, 0.1)
		colors.append(top_color)
		colors.append(top_color)
		colors.append(bot_color)
		colors.append(bot_color)
		draw_polygon(points, colors)

		# Border
		for i in range(points.size()):
			var next := (i + 1) % points.size()
			draw_line(points[i], points[next], primary_color.lerp(Color.BLACK, 0.3), 1.0, true)

		# X-lacing (Brute vest)
		if has_lacing:
			var lace_col := Color(0.2, 0.2, 0.15)
			var lx := bw * 0.2
			var lace_top := -hh * 0.5
			var lace_bot := hh * 0.7
			var step := (lace_bot - lace_top) / 4.0
			for i in range(4):
				var y1 := lace_top + step * float(i)
				var y2 := y1 + step
				draw_line(Vector2(-lx, y1), Vector2(lx, y2), lace_col, 1.2)
				draw_line(Vector2(lx, y1), Vector2(-lx, y2), lace_col, 1.2)

		# Robe extension
		if has_robe:
			var robe_points := PackedVector2Array([
				Vector2(-bw, hh),
				Vector2(bw, hh),
				Vector2(bw + 4, hh + torso_height * 0.8),
				Vector2(-bw - 4, hh + torso_height * 0.8),
			])
			var robe_colors := PackedColorArray()
			robe_colors.append(primary_color)
			robe_colors.append(primary_color)
			robe_colors.append(primary_color.lerp(Color.BLACK, 0.4))
			robe_colors.append(primary_color.lerp(Color.BLACK, 0.4))
			draw_polygon(robe_points, robe_colors)


class _LimbDrawer extends Node2D:
	var limb_length: float = 14.0
	var limb_width: float = 4.0
	var limb_color: Color = Color(0.5, 0.4, 0.35)
	var joint_color: Color = Color(0.6, 0.5, 0.4)
	var has_hand: bool = false
	var hand_color: Color = Color(0.7, 0.55, 0.4)

	func _draw() -> void:
		var hw := limb_width / 2.0
		# Upper segment
		var upper_len := limb_length * 0.5
		# Tapered capsule shape
		var points := PackedVector2Array([
			Vector2(-hw, 0),
			Vector2(hw, 0),
			Vector2(hw * 0.8, upper_len),
			Vector2(-hw * 0.8, upper_len),
		])
		draw_colored_polygon(points, limb_color)

		# Lower segment (slightly thinner)
		var lower_hw := hw * 0.75
		var lower_points := PackedVector2Array([
			Vector2(-lower_hw, upper_len),
			Vector2(lower_hw, upper_len),
			Vector2(lower_hw * 0.7, limb_length),
			Vector2(-lower_hw * 0.7, limb_length),
		])
		draw_colored_polygon(lower_points, limb_color.lerp(Color.BLACK, 0.1))

		# Joint circle
		draw_circle(Vector2(0, upper_len), hw * 0.7, joint_color)

		# Hand/foot circle
		if has_hand:
			draw_circle(Vector2(0, limb_length), hw * 0.6, hand_color)


class _HeadDrawer extends Node2D:
	var head_radius: float = 7.0
	var skin_color: Color = Color(0.7, 0.55, 0.4)
	var has_hood: bool = false
	var hood_color: Color = Color(0.2, 0.3, 0.2)
	var has_goggles: bool = false
	var goggle_color: Color = Color(0.5, 0.8, 0.3)
	var has_blindfold: bool = false
	var blindfold_color: Color = Color(0.15, 0.12, 0.2)
	var has_antlers: bool = false
	# Hair
	var hair_style: String = "none"
	var hair_color: Color = Color(0.4, 0.3, 0.2)
	var hair_size: float = 1.0
	# Facial features
	var has_tusks: bool = false
	var has_beard: bool = false
	var beard_color: Color = Color(0.4, 0.3, 0.2)
	var has_horns: bool = false
	var horn_color: Color = Color(0.8, 0.8, 0.7)
	var has_pointed_ears: bool = false
	var has_face_mask: bool = false
	var mask_color: Color = Color(0.1, 0.1, 0.1)
	var eye_style: String = "normal"
	var eye_glow_color: Color = Color(1.0, 1.0, 1.0, 0.9)

	func _draw() -> void:
		var r := head_radius

		# Antlers (drawn behind head)
		if has_antlers:
			var antler_col := Color(0.5, 0.4, 0.25)
			draw_line(Vector2(-r * 0.4, -r * 0.7), Vector2(-r * 1.2, -r * 1.8), antler_col, 2.0)
			draw_line(Vector2(-r * 0.9, -r * 1.4), Vector2(-r * 1.5, -r * 1.6), antler_col, 1.5)
			draw_line(Vector2(-r * 1.0, -r * 1.6), Vector2(-r * 0.8, -r * 2.2), antler_col, 1.5)
			draw_line(Vector2(r * 0.4, -r * 0.7), Vector2(r * 1.2, -r * 1.8), antler_col, 2.0)
			draw_line(Vector2(r * 0.9, -r * 1.4), Vector2(r * 1.5, -r * 1.6), antler_col, 1.5)
			draw_line(Vector2(r * 1.0, -r * 1.6), Vector2(r * 0.8, -r * 2.2), antler_col, 1.5)

		# Viking horns (behind head, Barbarian)
		if has_horns:
			draw_line(Vector2(-r * 0.7, -r * 0.5), Vector2(-r * 1.6, -r * 1.4), horn_color, 2.5)
			draw_line(Vector2(-r * 1.6, -r * 1.4), Vector2(-r * 1.3, -r * 1.8), horn_color, 2.0)
			draw_line(Vector2(r * 0.7, -r * 0.5), Vector2(r * 1.6, -r * 1.4), horn_color, 2.5)
			draw_line(Vector2(r * 1.6, -r * 1.4), Vector2(r * 1.3, -r * 1.8), horn_color, 2.0)

		# Hair (drawn behind head for most styles)
		_draw_hair_behind(r)

		# Pointed ears (behind head circle)
		if has_pointed_ears:
			var ear_col := skin_color.lerp(Color.BLACK, 0.05)
			# Left ear
			var le := PackedVector2Array([
				Vector2(-r * 0.85, -r * 0.1),
				Vector2(-r * 1.4, -r * 0.6),
				Vector2(-r * 0.85, r * 0.2),
			])
			draw_colored_polygon(le, ear_col)
			# Right ear
			var re := PackedVector2Array([
				Vector2(r * 0.85, -r * 0.1),
				Vector2(r * 1.4, -r * 0.6),
				Vector2(r * 0.85, r * 0.2),
			])
			draw_colored_polygon(re, ear_col)

		if has_hood:
			# Hood (larger arc behind head)
			draw_circle(Vector2(0, -1), r + 3, hood_color)
			# Hood point at top
			var hood_top := PackedVector2Array([
				Vector2(-r * 0.5, -r - 2),
				Vector2(0, -r - 6),
				Vector2(r * 0.5, -r - 2),
			])
			draw_colored_polygon(hood_top, hood_color.lerp(Color.BLACK, 0.1))
			# Dark face shadow (face hidden in shadow)
			draw_circle(Vector2(0, 1), r * 0.82, Color(0.05, 0.05, 0.08))
		else:
			# Head
			draw_circle(Vector2.ZERO, r, skin_color)
			# Highlight
			draw_circle(Vector2(-r * 0.25, -r * 0.25), r * 0.3, skin_color.lerp(Color.WHITE, 0.2))

		# Face mask / eye band (Ranger)
		if has_face_mask and not has_hood:
			var mask_band_y := -r * 0.05
			var mask_h := r * 0.4
			draw_rect(Rect2(-r * 0.95, mask_band_y - mask_h / 2, r * 1.9, mask_h), mask_color)

		# Eyes
		_draw_eyes(r)

		# Tusks (Brute - small tusks from lower jaw)
		if has_tusks and not has_hood:
			var tusk_col := Color(0.9, 0.88, 0.8)
			draw_line(Vector2(-r * 0.25, r * 0.5), Vector2(-r * 0.35, r * 0.05), tusk_col, 1.8)
			draw_line(Vector2(r * 0.25, r * 0.5), Vector2(r * 0.35, r * 0.05), tusk_col, 1.8)

		# Beard
		if has_beard and not has_hood:
			var bw := r * 0.7
			var beard_pts := PackedVector2Array([
				Vector2(-bw, r * 0.3),
				Vector2(bw, r * 0.3),
				Vector2(bw * 0.6, r * 1.2),
				Vector2(0, r * 1.5),
				Vector2(-bw * 0.6, r * 1.2),
			])
			draw_colored_polygon(beard_pts, beard_color)

		# Blindfold
		if has_blindfold:
			var band_y := 0.0
			var band_h := r * 0.35
			draw_rect(Rect2(-r * 0.9, band_y - band_h / 2, r * 1.8, band_h), blindfold_color)
			draw_line(Vector2(r * 0.9, band_y), Vector2(r * 1.5, band_y + 3), blindfold_color, 1.5)
			draw_line(Vector2(r * 0.9, band_y), Vector2(r * 1.4, band_y + 5), blindfold_color, 1.2)

		# Goggles (drawn on top of everything)
		if has_goggles:
			var eye_y := 0.0
			var eye_spacing := r * 0.35
			# Goggle lenses (filled circles for round goggles)
			draw_circle(Vector2(-eye_spacing, eye_y), 3.5, Color(0.15, 0.15, 0.2, 0.7))
			draw_circle(Vector2(eye_spacing, eye_y), 3.5, Color(0.15, 0.15, 0.2, 0.7))
			draw_arc(Vector2(-eye_spacing, eye_y), 3.5, 0, TAU, 12, goggle_color, 1.5)
			draw_arc(Vector2(eye_spacing, eye_y), 3.5, 0, TAU, 12, goggle_color, 1.5)
			draw_line(Vector2(-eye_spacing + 3.5, eye_y), Vector2(eye_spacing - 3.5, eye_y), goggle_color, 1.0)
			# Strap
			draw_line(Vector2(-eye_spacing - 3.5, eye_y), Vector2(-r, eye_y), goggle_color.lerp(Color.BLACK, 0.3), 1.0)
			draw_line(Vector2(eye_spacing + 3.5, eye_y), Vector2(r, eye_y), goggle_color.lerp(Color.BLACK, 0.3), 1.0)

		# Hair on top (mohawk, spiky go in front)
		_draw_hair_front(r)

	func _draw_eyes(r: float) -> void:
		"""Draw eyes based on eye_style."""
		if has_blindfold:
			return
		var eye_y := 0.0
		var eye_spacing := r * 0.35
		match eye_style:
			"single_glow":
				# Single glowing eye (Burglar in hood)
				var glow_pos := Vector2(-eye_spacing * 0.3, eye_y)
				# Glow halo
				var outer := eye_glow_color
				outer.a = 0.3
				draw_circle(glow_pos, 4.0, outer)
				# Eye
				draw_circle(glow_pos, 2.0, eye_glow_color)
				# Bright core
				draw_circle(glow_pos, 0.8, Color.WHITE)
			"crescent":
				# Crescent moon eyes (Dark Wizard)
				for side in [-1.0, 1.0]:
					var cx: float = float(side) * eye_spacing
					# Outer arc (glow color)
					draw_arc(Vector2(cx, eye_y), 2.5, PI * 0.2, PI * 1.8, 8, eye_glow_color, 1.5)
					# Inner cutout (draws crescent shape)
					draw_arc(Vector2(cx + side * 0.8, eye_y), 2.0, PI * 0.2, PI * 1.8, 8, eye_glow_color, 1.0)
					# Small glow
					var g := eye_glow_color
					g.a = 0.25
					draw_circle(Vector2(cx, eye_y), 4.0, g)
			"hidden":
				pass  # No eyes
			_:
				# Normal eyes (skip if hood covers them and not single_glow)
				if has_hood:
					return
				draw_circle(Vector2(-eye_spacing, eye_y), 1.5, Color(0.1, 0.1, 0.15))
				draw_circle(Vector2(eye_spacing, eye_y), 1.5, Color(0.1, 0.1, 0.15))
				draw_circle(Vector2(-eye_spacing + 0.5, eye_y - 0.5), 0.6, Color(1, 1, 1, 0.7))
				draw_circle(Vector2(eye_spacing + 0.5, eye_y - 0.5), 0.6, Color(1, 1, 1, 0.7))

	func _draw_hair_behind(r: float) -> void:
		"""Draw hair styles that go behind the head."""
		if has_hood:
			return
		var s := hair_size
		match hair_style:
			"flowing":
				# Flowing hair (Redeemer, Ranger) - drapes down sides and back
				var hw := r * 0.9 * s
				var hair_pts := PackedVector2Array([
					Vector2(-hw, -r * 0.7),
					Vector2(-hw * 1.1, 0),
					Vector2(-hw * 0.9, r * 1.0 * s),
					Vector2(-hw * 0.5, r * 1.5 * s),
					Vector2(hw * 0.5, r * 1.5 * s),
					Vector2(hw * 0.9, r * 1.0 * s),
					Vector2(hw * 1.1, 0),
					Vector2(hw, -r * 0.7),
				])
				draw_colored_polygon(hair_pts, hair_color)
				# Top hair cap
				var cap := PackedVector2Array([
					Vector2(-hw, -r * 0.7),
					Vector2(-r * 0.3, -r * 1.1),
					Vector2(r * 0.3, -r * 1.1),
					Vector2(hw, -r * 0.7),
				])
				draw_colored_polygon(cap, hair_color.lerp(Color.BLACK, 0.1))
			"wild":
				# Wild messy hair (Barbarian, Illusionist) - big spiky mass
				var segments := 10
				var base_r := r * 1.1 * s
				var pts := PackedVector2Array()
				# Deterministic spike pattern (sin-based pseudo-random)
				for i in range(segments):
					var angle: float = -PI * 0.8 + (PI * 1.6) * float(i) / float(segments - 1)
					var spike_vary: float = abs(sin(float(i) * 2.7 + 0.5)) * r * 0.3 * s
					var spike: float = base_r + spike_vary * (1.0 if i % 2 == 0 else 0.4)
					pts.append(Vector2(cos(angle) * spike, sin(angle) * spike - r * 0.1))
				# Close the bottom
				pts.append(Vector2(r * 0.6 * s, r * 0.3))
				pts.append(Vector2(-r * 0.6 * s, r * 0.3))
				draw_colored_polygon(pts, hair_color)
			"tentacles":
				# Tentacle/flowing tendrils (Confessor) - multiple wavy strands
				for i in range(5):
					var base_x: float = (float(i) - 2.0) * r * 0.35
					var tendril_len: float = r * (1.2 + abs(sin(float(i) * 1.7)) * 0.4) * s
					var pts := PackedVector2Array()
					pts.append(Vector2(base_x - 1.5, -r * 0.3))
					pts.append(Vector2(base_x + 1.5, -r * 0.3))
					# Wavy body
					var end_x := base_x + sin(float(i) * 1.5) * r * 0.3 * s
					pts.append(Vector2(end_x + 1.0, tendril_len))
					pts.append(Vector2(end_x - 1.0, tendril_len))
					draw_colored_polygon(pts, hair_color.lerp(Color.BLACK, float(i) * 0.05))

	func _draw_hair_front(r: float) -> void:
		"""Draw hair styles that go on top of the head."""
		if has_hood:
			return
		var s := hair_size
		match hair_style:
			"mohawk":
				# Mohawk (Berserker) - tall central ridge
				var mw := r * 0.3
				var mh := r * 1.5 * s
				var pts := PackedVector2Array([
					Vector2(-mw, -r * 0.6),
					Vector2(-mw * 0.7, -r * 0.6 - mh),
					Vector2(0, -r * 0.6 - mh - r * 0.3 * s),
					Vector2(mw * 0.7, -r * 0.6 - mh),
					Vector2(mw, -r * 0.6),
				])
				draw_colored_polygon(pts, hair_color)
				# Highlight stripe
				var hl_pts := PackedVector2Array([
					Vector2(-mw * 0.3, -r * 0.6),
					Vector2(-mw * 0.2, -r * 0.6 - mh * 0.9),
					Vector2(mw * 0.2, -r * 0.6 - mh * 0.9),
					Vector2(mw * 0.3, -r * 0.6),
				])
				draw_colored_polygon(hl_pts, hair_color.lerp(Color.WHITE, 0.25))
			"flame":
				# Flame hair (Shaman) - rising flame-shaped strands
				var flame_w := r * 0.8 * s
				var flame_h := r * 1.6 * s
				# Multiple flame tongues
				for i in range(5):
					var fx: float = (float(i) - 2.0) * flame_w * 0.3
					var fh: float = flame_h * (0.7 + 0.3 * (1.0 - abs(float(i) - 2.0) / 2.0))
					var fw: float = flame_w * 0.25
					var flame := PackedVector2Array([
						Vector2(fx - fw, -r * 0.5),
						Vector2(fx, -r * 0.5 - fh),
						Vector2(fx + fw, -r * 0.5),
					])
					var alpha := 0.9 - float(i) * 0.05
					var fcol := hair_color
					fcol.a = alpha
					draw_colored_polygon(flame, fcol)
				# Bright core at base
				var core_col := hair_color.lerp(Color.WHITE, 0.4)
				draw_circle(Vector2(0, -r * 0.7), r * 0.35, core_col)
			"spiky":
				# Spiky hair (Alchemist) - multiple upward spikes
				for i in range(7):
					var sx: float = (float(i) - 3.0) * r * 0.25
					var spike_h: float = r * (0.6 + abs(sin(float(i) * 2.3 + 0.8)) * 0.5) * s
					var sw := r * 0.15
					var spike := PackedVector2Array([
						Vector2(sx - sw, -r * 0.5),
						Vector2(sx, -r * 0.5 - spike_h),
						Vector2(sx + sw, -r * 0.5),
					])
					draw_colored_polygon(spike, hair_color.lerp(Color.BLACK, float(i % 2) * 0.15))


class _WeaponDrawer extends Node2D:
	var weapon_type: String = "none"
	var weapon_color: Color = Color(0.6, 0.6, 0.6)
	var arm_length: float = 12.0
	var weapon_scale: float = 1.0
	var has_crystal: bool = false
	var crystal_color: Color = Color(0.8, 0.5, 0.9)

	func _draw() -> void:
		var attach_y := arm_length * 0.9
		var ws := weapon_scale
		match weapon_type:
			"bow":
				# Bow arc
				draw_arc(Vector2(-3, attach_y - 6), 8, -PI * 0.6, PI * 0.6, 12, weapon_color.lerp(Color.BLACK, 0.3), 2.0)
				# String
				draw_line(Vector2(-3, attach_y - 14), Vector2(-3, attach_y + 2), Color(0.8, 0.75, 0.6), 0.8)
			"staff":
				# Staff shaft
				draw_line(Vector2(0, attach_y - 20), Vector2(0, attach_y + 4), weapon_color.lerp(Color.BLACK, 0.2), 2.5)
				if has_crystal:
					# Crystal top - faceted diamond shape
					var cy := attach_y - 22
					var diamond := PackedVector2Array([
						Vector2(0, cy - 5),   # Top point
						Vector2(3.5, cy),      # Right
						Vector2(0, cy + 4),    # Bottom point
						Vector2(-3.5, cy),     # Left
					])
					draw_colored_polygon(diamond, crystal_color)
					# Inner facet highlight
					var inner := PackedVector2Array([
						Vector2(0, cy - 3),
						Vector2(2, cy),
						Vector2(0, cy + 2),
					])
					draw_colored_polygon(inner, crystal_color.lerp(Color.WHITE, 0.4))
					# Sparkle lines radiating out
					var spark_col := crystal_color.lerp(Color.WHITE, 0.6)
					spark_col.a = 0.6
					draw_line(Vector2(0, cy - 5), Vector2(0, cy - 8), spark_col, 1.0)
					draw_line(Vector2(3.5, cy), Vector2(6, cy), spark_col, 1.0)
					draw_line(Vector2(-3.5, cy), Vector2(-6, cy), spark_col, 1.0)
				else:
					# Standard orb on top
					draw_circle(Vector2(0, attach_y - 22), 3.0, weapon_color)
					draw_circle(Vector2(-0.5, attach_y - 23), 1.2, weapon_color.lerp(Color.WHITE, 0.5))
			"axe":
				# Handle
				var handle_top := attach_y - 8 * ws
				var handle_bot := attach_y + 4
				draw_line(Vector2(0, handle_top), Vector2(0, handle_bot), weapon_color.lerp(Color.BLACK, 0.4), 2.0)
				# Blade (scaled)
				var blade := PackedVector2Array([
					Vector2(0, attach_y - 10 * ws),
					Vector2(6 * ws, attach_y - 7 * ws),
					Vector2(6 * ws, attach_y - 3 * ws),
					Vector2(0, attach_y - 5 * ws),
				])
				draw_colored_polygon(blade, weapon_color)
				# Edge highlight
				if ws > 1.2:
					draw_line(Vector2(6 * ws, attach_y - 7 * ws), Vector2(6 * ws, attach_y - 3 * ws), weapon_color.lerp(Color.WHITE, 0.3), 1.0)
			"dagger":
				# Short blade
				draw_line(Vector2(0, attach_y - 2), Vector2(0, attach_y + 6), weapon_color, 1.5)
				# Guard
				draw_line(Vector2(-2.5, attach_y - 2), Vector2(2.5, attach_y - 2), weapon_color.lerp(Color.BLACK, 0.2), 1.5)
			"sword":
				# Long blade
				draw_line(Vector2(0, attach_y - 14), Vector2(0, attach_y + 2), weapon_color, 2.0)
				# Guard
				draw_line(Vector2(-4, attach_y + 2), Vector2(4, attach_y + 2), weapon_color.lerp(Color.BLACK, 0.2), 2.0)
				# Handle
				draw_line(Vector2(0, attach_y + 2), Vector2(0, attach_y + 6), weapon_color.lerp(Color.BLACK, 0.4), 2.5)
			"wand":
				# Thin wand
				draw_line(Vector2(0, attach_y - 6), Vector2(0, attach_y + 4), weapon_color, 1.5)
				# Sparkle tip
				draw_circle(Vector2(0, attach_y - 7), 2.0, weapon_color.lerp(Color.WHITE, 0.4))
			"flask":
				# Flask body
				draw_circle(Vector2(0, attach_y - 2), 3.5, weapon_color)
				# Neck
				draw_line(Vector2(0, attach_y - 5.5), Vector2(0, attach_y - 8), weapon_color.lerp(Color.BLACK, 0.2), 2.0)
				# Cork
				draw_circle(Vector2(0, attach_y - 9), 1.5, Color(0.6, 0.45, 0.3))
			"fists":
				# Bigger fists
				draw_circle(Vector2(0, attach_y), 3.5, weapon_color.lerp(Color.BLACK, 0.1))
				draw_circle(Vector2(-0.5, attach_y - 0.5), 1.2, weapon_color.lerp(Color.WHITE, 0.2))


class _HaloDrawer extends Node2D:
	var halo_color: Color = Color(1.0, 0.95, 0.6)
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var alpha := 0.4 + sin(_time * 2.0) * 0.15
		var color := halo_color
		color.a = alpha
		# Halo ring (tilted ellipse)
		var points := PackedVector2Array()
		for i in range(20):
			var angle := TAU * i / 20.0
			points.append(Vector2(cos(angle) * 8, sin(angle) * 2.5))
		for i in range(points.size()):
			var next := (i + 1) % points.size()
			draw_line(points[i], points[next], color, 1.5, true)


class _GlowDrawer extends Node2D:
	var glow_color: Color = Color(1, 1, 1, 0.2)
	var glow_radius: float = 24.0
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.7 + sin(_time * 1.5) * 0.3
		for i in range(3, 0, -1):
			var r := glow_radius * (float(i) / 3.0) * pulse
			var color := glow_color
			color.a = glow_color.a * (1.0 - float(i) / 3.0) * 0.5
			draw_circle(Vector2.ZERO, r, color)


class _CloakDrawer extends Node2D:
	var cloak_width: float = 18.0
	var cloak_height: float = 22.0
	var cloak_color: Color = Color(0.2, 0.2, 0.25)

	func _draw() -> void:
		var hw := cloak_width / 2.0
		var points := PackedVector2Array([
			Vector2(-hw * 0.8, 0),
			Vector2(hw * 0.8, 0),
			Vector2(hw, cloak_height),
			Vector2(-hw, cloak_height),
		])
		var colors := PackedColorArray()
		colors.append(cloak_color)
		colors.append(cloak_color)
		colors.append(cloak_color.lerp(Color.BLACK, 0.3))
		colors.append(cloak_color.lerp(Color.BLACK, 0.3))
		draw_polygon(points, colors)


class _BackpackDrawer extends Node2D:
	var bp_color: Color = Color(0.4, 0.35, 0.25)

	func _draw() -> void:
		# Backpack body
		draw_rect(Rect2(-3, -6, 6, 10), bp_color)
		draw_rect(Rect2(-3, -6, 6, 10), bp_color.lerp(Color.BLACK, 0.3), false, 1.0)
		# Strap
		draw_line(Vector2(-3, -6), Vector2(-6, -3), bp_color.lerp(Color.BLACK, 0.2), 1.0)


class _HandGlowDrawer extends Node2D:
	"""Pulsing glow at hand positions for Redeemer."""
	var glow_color: Color = Color(1.0, 0.95, 0.6, 0.6)
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.6 + sin(_time * 3.0) * 0.4
		var base_r := 5.0
		# Outer glow
		var outer_col := glow_color
		outer_col.a = glow_color.a * 0.3 * pulse
		draw_circle(Vector2.ZERO, base_r * 1.5, outer_col)
		# Mid glow
		var mid_col := glow_color
		mid_col.a = glow_color.a * 0.5 * pulse
		draw_circle(Vector2.ZERO, base_r, mid_col)
		# Core
		var core_col := glow_color.lerp(Color.WHITE, 0.5)
		core_col.a = glow_color.a * 0.8 * pulse
		draw_circle(Vector2.ZERO, base_r * 0.4, core_col)


class _ElectricityDrawer extends Node2D:
	"""Randomized lightning arcs around body for Shaman."""
	var electricity_color: Color = Color(0.4, 0.8, 1.0)
	var body_height: float = 20.0
	var _time: float = 0.0
	var _arcs: Array[Dictionary] = []
	var _next_arc_time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		if _time >= _next_arc_time:
			_spawn_arc()
			_next_arc_time = _time + randf_range(0.15, 0.4)
		# Remove expired arcs
		var alive: Array[Dictionary] = []
		for arc in _arcs:
			if _time - float(arc.spawn) < float(arc.lifetime):
				alive.append(arc)
		_arcs = alive
		queue_redraw()

	func _spawn_arc() -> void:
		var arc := {}
		arc.spawn = _time
		arc.lifetime = randf_range(0.08, 0.2)
		# Random start point on body
		var start_pt := Vector2(randf_range(-10, 10), randf_range(-body_height * 0.5, body_height * 0.3))
		arc.start = start_pt
		# Random end point nearby
		var angle := randf() * TAU
		var dist := randf_range(6, 14)
		var end_pt := start_pt + Vector2(cos(angle), sin(angle)) * dist
		arc.end_point = end_pt
		# Mid points for jagged lightning
		arc.mid1 = start_pt.lerp(end_pt, 0.33) + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		arc.mid2 = start_pt.lerp(end_pt, 0.66) + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		_arcs.append(arc)

	func _draw() -> void:
		for arc in _arcs:
			var age: float = float(_time - arc.spawn)
			var life: float = float(arc.lifetime)
			var alpha: float = 1.0 - (age / life)
			var col := electricity_color
			col.a = alpha * 0.9
			var bright := electricity_color.lerp(Color.WHITE, 0.6)
			bright.a = alpha * 0.7
			# Draw jagged line
			var s: Vector2 = arc.start
			var m1: Vector2 = arc.mid1
			var m2: Vector2 = arc.mid2
			var e: Vector2 = arc.end_point
			draw_line(s, m1, col, 1.5)
			draw_line(m1, m2, col, 1.5)
			draw_line(m2, e, col, 1.5)
			# Bright core
			draw_line(s, m1, bright, 0.8)
			draw_line(m1, m2, bright, 0.8)
			draw_line(m2, e, bright, 0.8)


class _SmokeWispDrawer extends Node2D:
	"""Rising, fading wisp particles for Illusionist staff."""
	var smoke_color: Color = Color(0.6, 0.3, 0.8, 0.5)
	var _time: float = 0.0
	var _wisps: Array[Dictionary] = []
	var _next_wisp: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		if _time >= _next_wisp:
			_spawn_wisp()
			_next_wisp = _time + randf_range(0.2, 0.5)
		# Update wisps
		var alive: Array[Dictionary] = []
		for w in _wisps:
			var age: float = float(w.age) + delta
			w.age = age
			if age < float(w.lifetime):
				var p: Vector2 = w.pos
				p.y -= delta * float(w.speed)
				p.x += sin(_time * 3.0 + float(w.offset)) * delta * 4.0
				w.pos = p
				alive.append(w)
		_wisps = alive
		queue_redraw()

	func _spawn_wisp() -> void:
		var w := {}
		w.pos = Vector2(randf_range(-6, 6), randf_range(-5, 5))
		w.speed = randf_range(8, 16)
		w.lifetime = randf_range(0.6, 1.2)
		w.age = 0.0
		w.size = randf_range(2.0, 4.0)
		w.offset = randf() * TAU
		_wisps.append(w)

	func _draw() -> void:
		for w in _wisps:
			var w_age: float = float(w.age)
			var w_life: float = float(w.lifetime)
			var w_size: float = float(w.size)
			var alpha: float = (1.0 - w_age / w_life) * smoke_color.a
			var col := smoke_color
			col.a = alpha * 0.6
			var p: Vector2 = w.pos
			draw_circle(p, w_size, col)
			# Lighter core
			var core := smoke_color.lerp(Color.WHITE, 0.3)
			core.a = alpha * 0.3
			draw_circle(p, w_size * 0.5, core)


class _DarkButterflyDrawer extends Node2D:
	"""Small butterfly silhouettes orbiting champion for Dark Wizard."""
	var butterfly_color: Color = Color(0.2, 0.0, 0.3)
	var _time: float = 0.0
	var _butterflies: Array[Dictionary] = []

	func _ready() -> void:
		# Create 4-6 persistent butterflies
		var count := randi_range(4, 6)
		for i in range(count):
			var b := {}
			b.orbit_radius = randf_range(14, 24)
			b.orbit_speed = randf_range(1.0, 2.5) * (1.0 if randf() > 0.5 else -1.0)
			b.orbit_offset = randf() * TAU
			b.vert_offset = randf_range(-12, 8)
			b.vert_speed = randf_range(0.8, 1.5)
			b.wing_speed = randf_range(6.0, 10.0)
			b.size = randf_range(2.0, 3.5)
			_butterflies.append(b)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		for b in _butterflies:
			var b_speed: float = float(b.orbit_speed)
			var b_offset: float = float(b.orbit_offset)
			var b_radius: float = float(b.orbit_radius)
			var b_voff: float = float(b.vert_offset)
			var b_vspd: float = float(b.vert_speed)
			var b_wspd: float = float(b.wing_speed)
			var s: float = float(b.size)
			var angle: float = _time * b_speed + b_offset
			var px: float = cos(angle) * b_radius
			var py: float = b_voff + sin(_time * b_vspd + b_offset) * 5.0
			var wing_flap: float = abs(sin(_time * b_wspd + b_offset))
			var pos := Vector2(px, py)
			# Wing spread based on flap
			var wing_w: float = s * (0.3 + wing_flap * 0.7)
			# Left wing
			var lw := PackedVector2Array([
				pos,
				pos + Vector2(-wing_w, -s * 0.5),
				pos + Vector2(-wing_w * 0.7, s * 0.3),
			])
			draw_colored_polygon(lw, butterfly_color)
			# Right wing
			var rw := PackedVector2Array([
				pos,
				pos + Vector2(wing_w, -s * 0.5),
				pos + Vector2(wing_w * 0.7, s * 0.3),
			])
			draw_colored_polygon(rw, butterfly_color)
			# Body dot
			draw_circle(pos, s * 0.2, butterfly_color.lerp(Color.BLACK, 0.3))


class _DarkAuraDrawer extends Node2D:
	"""Pulsing dark ring with tendrils for Dark Wizard."""
	var aura_color: Color = Color(0.1, 0.0, 0.15, 0.4)
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.8 + sin(_time * 1.2) * 0.2
		var base_r := 22.0 * pulse
		# Outer ring
		var ring_col := aura_color
		ring_col.a = aura_color.a * (0.5 + sin(_time * 1.8) * 0.2)
		draw_arc(Vector2.ZERO, base_r, 0, TAU, 24, ring_col, 2.0, true)
		# Inner softer ring
		var inner_col := aura_color
		inner_col.a = aura_color.a * 0.3
		draw_arc(Vector2.ZERO, base_r * 0.7, 0, TAU, 20, inner_col, 1.5, true)
		# Tendrils (4 wispy lines extending outward)
		for i in range(4):
			var base_angle := TAU * i / 4.0 + _time * 0.3
			var tendril_col := aura_color
			tendril_col.a = aura_color.a * (0.4 + sin(_time * 2.0 + i) * 0.2)
			var start := Vector2(cos(base_angle), sin(base_angle)) * base_r
			var end_dist := base_r + 6.0 + sin(_time * 1.5 + i * 1.7) * 4.0
			var end_angle := base_angle + sin(_time * 0.8 + i) * 0.3
			var end_pt := Vector2(cos(end_angle), sin(end_angle)) * end_dist
			draw_line(start, end_pt, tendril_col, 1.5)


class _PotionSmokeDrawer extends Node2D:
	"""Green bubbling smoke from flasks for Alchemist."""
	var smoke_color: Color = Color(0.3, 0.9, 0.15, 0.5)
	var _time: float = 0.0
	var _bubbles: Array[Dictionary] = []
	var _next_bubble: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		if _time >= _next_bubble:
			_spawn_bubble()
			_next_bubble = _time + randf_range(0.1, 0.3)
		var alive: Array[Dictionary] = []
		for b in _bubbles:
			var age: float = float(b.age) + delta
			b.age = age
			if age < float(b.lifetime):
				var p: Vector2 = b.pos
				p.y -= delta * float(b.speed)
				p.x += sin(_time * 4.0 + float(b.offset)) * delta * 3.0
				b.pos = p
				alive.append(b)
		_bubbles = alive
		queue_redraw()

	func _spawn_bubble() -> void:
		var b := {}
		# Emit from near hands/flasks
		b.pos = Vector2(randf_range(-12, 12), randf_range(2, 10))
		b.speed = randf_range(10, 20)
		b.lifetime = randf_range(0.4, 0.9)
		b.age = 0.0
		b.size = randf_range(1.5, 3.5)
		b.offset = randf() * TAU
		_bubbles.append(b)

	func _draw() -> void:
		for b in _bubbles:
			var b_age: float = float(b.age)
			var b_life: float = float(b.lifetime)
			var b_size: float = float(b.size)
			var alpha: float = (1.0 - b_age / b_life) * smoke_color.a
			var col := smoke_color
			col.a = alpha
			var p: Vector2 = b.pos
			draw_circle(p, b_size, col)
			# Bubble highlight
			var hl := Color.WHITE
			hl.a = alpha * 0.3
			draw_circle(p + Vector2(-b_size * 0.2, -b_size * 0.2), b_size * 0.3, hl)


class _ArmBandDrawer extends Node2D:
	"""Arm band / bracer wrapped around upper arm."""
	var band_color: Color = Color(0.3, 0.3, 0.3)
	var arm_width: float = 4.0

	func _draw() -> void:
		var hw := arm_width * 0.6
		var bh := arm_width * 0.5
		draw_rect(Rect2(-hw, -bh / 2, hw * 2, bh), band_color)
		# Highlight edge
		draw_line(Vector2(-hw, -bh / 2), Vector2(hw, -bh / 2), band_color.lerp(Color.WHITE, 0.2), 0.8)


class _ShadowSpiritDrawer extends Node2D:
	"""Dark antlered shadow spirit hovering behind Beast champion."""
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		# Spirit hovers and pulses behind the champion
		var bob := sin(_time * 1.5) * 2.0
		var alpha := 0.2 + sin(_time * 1.0) * 0.08
		var spirit_col := Color(0.05, 0.08, 0.05, alpha)
		var offset := Vector2(0, -18 + bob)
		# Spirit body (tall shadowy oval)
		var pts := PackedVector2Array()
		for i in range(16):
			var angle := TAU * i / 16.0
			pts.append(offset + Vector2(cos(angle) * 8, sin(angle) * 14))
		draw_colored_polygon(pts, spirit_col)
		# Head
		var head_pos := offset + Vector2(0, -16)
		draw_circle(head_pos, 5.0, spirit_col)
		# Antlers
		var antler_col := Color(0.15, 0.2, 0.15, alpha * 1.5)
		# Left antler
		draw_line(head_pos + Vector2(-3, -3), head_pos + Vector2(-10, -14), antler_col, 1.5)
		draw_line(head_pos + Vector2(-7, -10), head_pos + Vector2(-12, -11), antler_col, 1.2)
		draw_line(head_pos + Vector2(-9, -13), head_pos + Vector2(-7, -18), antler_col, 1.2)
		# Right antler
		draw_line(head_pos + Vector2(3, -3), head_pos + Vector2(10, -14), antler_col, 1.5)
		draw_line(head_pos + Vector2(7, -10), head_pos + Vector2(12, -11), antler_col, 1.2)
		draw_line(head_pos + Vector2(9, -13), head_pos + Vector2(7, -18), antler_col, 1.2)
		# Glowing eyes
		var eye_col := Color(0.2, 0.5, 0.2, alpha * 2.5)
		draw_circle(head_pos + Vector2(-2, 0), 1.2, eye_col)
		draw_circle(head_pos + Vector2(2, 0), 1.2, eye_col)


class _HPBarDrawer extends Control:
	var _current_hp: int = 20
	var _max_hp: int = 20
	var _owner_id: int = 1

	func _init() -> void:
		size = Vector2(TOKEN_SIZE, 10)
		custom_minimum_size = size

	func set_hp(hp: int, max_val: int, owner: int) -> void:
		_current_hp = hp
		_max_hp = max_val
		_owner_id = owner
		queue_redraw()

	func _draw() -> void:
		var bar_width := size.x
		var bar_height := 6.0
		var bar_y := 2.0

		# Background
		draw_rect(Rect2(0, bar_y, bar_width, bar_height), VisualTheme.HP_BAR_BG)

		# HP fill
		var hp_pct := float(_current_hp) / float(_max_hp) if _max_hp > 0 else 0.0
		var hp_color := VisualTheme.get_hp_color(_current_hp, _max_hp)
		draw_rect(Rect2(0, bar_y, bar_width * hp_pct, bar_height), hp_color)

		# Border
		draw_rect(Rect2(0, bar_y, bar_width, bar_height), VisualTheme.HP_BAR_BORDER, false, 1.0)

		# HP text
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(bar_width / 2 - 4, bar_y + 5), str(_current_hp), HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)
