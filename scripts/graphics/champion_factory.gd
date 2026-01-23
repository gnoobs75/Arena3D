extends RefCounted
class_name ChampionFactory
## ChampionFactory - Creates complete 3D champion models from body parts
## Assembles body, head, limbs, and applies materials/colors

# === CHAMPION 3D SCENE ===
# Structure of generated champion:
#   Champion3D (Node3D)
#   ├── Body (MeshInstance3D)
#   ├── Head (MeshInstance3D)
#   ├── LeftArm (MeshInstance3D)
#   ├── RightArm (MeshInstance3D)
#   ├── LeftLeg (MeshInstance3D)
#   ├── RightLeg (MeshInstance3D)
#   ├── Robe (MeshInstance3D) - optional
#   ├── TeamRing (MeshInstance3D)
#   └── SelectionGlow (OmniLight3D)


static func create_champion(champion_name: String, owner_id: int) -> Champion3D:
	"""Create a complete 3D champion model with animations."""
	var root: Champion3D = Champion3D.new()
	root.name = champion_name
	root.champion_name = champion_name
	root.owner_id = owner_id

	# Get body parameters
	var params: BodyBuilder.BodyParams = BodyBuilder.get_body_params(champion_name)

	# Get colors
	var colors: Dictionary = VisualTheme.get_champion_colors(champion_name)
	var team_color: Color = VisualTheme.get_player_color(owner_id)

	# Create materials
	var body_mat: StandardMaterial3D = _create_champion_material(colors["primary"], team_color)
	var secondary_mat: StandardMaterial3D = _create_champion_material(colors["secondary"], team_color, 0.1)

	# === BUILD BODY PARTS ===

	# Torso
	var torso: MeshInstance3D = MeshInstance3D.new()
	torso.name = "Body"
	torso.mesh = BodyBuilder.build_torso(params)
	torso.material_override = body_mat
	torso.position.y = 0.3 * params.leg_length  # Above legs
	if params.hunched:
		torso.rotation_degrees.x = 15  # Lean forward
	root.add_child(torso)

	# Head
	var head: MeshInstance3D = MeshInstance3D.new()
	head.name = "Head"
	head.mesh = BodyBuilder.build_head(params)
	head.material_override = secondary_mat
	head.position.y = 0.3 * params.leg_length + 0.4 * params.height  # On top of torso
	if params.hunched:
		head.position.z = 0.05  # Forward with hunched posture
	root.add_child(head)

	# Left Arm
	var left_arm: MeshInstance3D = MeshInstance3D.new()
	left_arm.name = "LeftArm"
	left_arm.mesh = BodyBuilder.build_arm(params, true)
	left_arm.material_override = body_mat
	left_arm.position = Vector3(
		-0.25 * params.shoulder_width * params.bulk,
		0.3 * params.leg_length + 0.33 * params.height,
		0
	)
	left_arm.rotation_degrees.z = 15  # Slight outward angle
	root.add_child(left_arm)

	# Right Arm
	var right_arm: MeshInstance3D = MeshInstance3D.new()
	right_arm.name = "RightArm"
	right_arm.mesh = BodyBuilder.build_arm(params, false)
	right_arm.material_override = body_mat
	right_arm.position = Vector3(
		0.25 * params.shoulder_width * params.bulk,
		0.3 * params.leg_length + 0.33 * params.height,
		0
	)
	right_arm.rotation_degrees.z = -15  # Slight outward angle
	root.add_child(right_arm)

	# Left Leg
	var left_leg: MeshInstance3D = MeshInstance3D.new()
	left_leg.name = "LeftLeg"
	left_leg.mesh = BodyBuilder.build_leg(params, true)
	left_leg.material_override = body_mat
	left_leg.position = Vector3(-0.08 * params.bulk, 0.3 * params.leg_length, 0)
	root.add_child(left_leg)

	# Right Leg
	var right_leg: MeshInstance3D = MeshInstance3D.new()
	right_leg.name = "RightLeg"
	right_leg.mesh = BodyBuilder.build_leg(params, false)
	right_leg.material_override = body_mat
	right_leg.position = Vector3(0.08 * params.bulk, 0.3 * params.leg_length, 0)
	root.add_child(right_leg)

	# Robe (for robed champions)
	if params.robed:
		var robe: MeshInstance3D = MeshInstance3D.new()
		robe.name = "Robe"
		robe.mesh = BodyBuilder.build_robe(params)
		robe.material_override = _create_robe_material(colors["secondary"])
		root.add_child(robe)

	# Team Ring (at base)
	var ring: MeshInstance3D = _create_team_ring(team_color)
	root.add_child(ring)

	# Selection Glow (initially off)
	var glow: OmniLight3D = _create_selection_glow(colors["primary"])
	root.add_child(glow)

	# Floating offset for floating champions
	if params.floating:
		root.position.y = 0.15

	# Add champion-specific equipment/features
	_add_champion_features(root, champion_name, colors, body_mat, secondary_mat)

	return root


static func _create_champion_material(base_color: Color, team_color: Color, team_blend: float = 0.2) -> StandardMaterial3D:
	"""Create material with champion color blended with team color."""
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = base_color.lerp(team_color, team_blend)
	mat.roughness = 0.7
	mat.metallic = 0.1
	return mat


static func _create_robe_material(color: Color) -> StandardMaterial3D:
	"""Create material for robes with cloth-like properties."""
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.2)
	mat.roughness = 0.9
	mat.metallic = 0.0
	# Robes should be double-sided
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _create_team_ring(team_color: Color) -> MeshInstance3D:
	"""Create glowing team indicator ring at base."""
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = "TeamRing"

	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = 0.28
	mesh.outer_radius = 0.35

	ring.mesh = mesh
	ring.position.y = 0.02
	ring.rotation_degrees.x = 90

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = team_color
	mat.emission_enabled = true
	mat.emission = team_color
	mat.emission_energy_multiplier = 0.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.8

	ring.material_override = mat

	return ring


static func _create_selection_glow(color: Color) -> OmniLight3D:
	"""Create selection highlight glow."""
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "SelectionGlow"
	light.light_color = color
	light.light_energy = 0.0  # Off by default
	light.omni_range = 1.0
	light.position.y = 0.4
	return light


static func _add_champion_features(root: Node3D, champion_name: String, colors: Dictionary, body_mat: StandardMaterial3D, secondary_mat: StandardMaterial3D) -> void:
	"""Add champion-specific equipment and features."""
	match champion_name:
		"Brute":
			# Big fists / gauntlets
			_add_fist_gauntlets(root, colors["secondary"])

		"Ranger":
			# Bow on back, hood hint
			_add_bow(root, colors["secondary"])

		"Beast":
			# Claws, ears
			_add_claws(root, colors["primary"])

		"Redeemer":
			# Staff, halo
			_add_staff(root, colors["secondary"])
			_add_halo(root, colors["secondary"])

		"Confessor":
			# Chains, dark aura
			_add_chains(root, colors["secondary"])

		"Barbarian":
			# Axes
			_add_axes(root, colors["secondary"])

		"Burglar":
			# Daggers, hood
			_add_daggers(root, colors["secondary"])

		"Berserker":
			# Large weapon
			_add_large_weapon(root, colors["secondary"])

		"Shaman":
			# Staff with orb
			_add_spirit_staff(root, colors["secondary"])

		"Illusionist":
			# Mirror/crystal effects
			_add_mirror_shard(root, colors["secondary"])

		"DarkWizard":
			# Skull staff
			_add_skull_staff(root, colors["secondary"])

		"Alchemist":
			# Backpack, goggles hint
			_add_backpack(root, colors["secondary"])


# === EQUIPMENT HELPERS ===

static func _add_fist_gauntlets(root: Node3D, color: Color) -> void:
	"""Add oversized fist gauntlets to Brute."""
	for side in [-1, 1]:
		var fist: MeshInstance3D = MeshInstance3D.new()
		fist.name = "Gauntlet" + ("L" if side < 0 else "R")
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(0.12, 0.1, 0.1)
		fist.mesh = mesh
		fist.position = Vector3(side * 0.35, 0.25, 0)

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = color.darkened(0.3)
		mat.metallic = 0.5
		fist.material_override = mat

		root.add_child(fist)


static func _add_bow(root: Node3D, color: Color) -> void:
	"""Add bow to Ranger."""
	var bow: MeshInstance3D = MeshInstance3D.new()
	bow.name = "Bow"
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = 0.15
	mesh.outer_radius = 0.17
	mesh.rings = 12
	bow.mesh = mesh
	bow.position = Vector3(-0.15, 0.5, -0.1)
	bow.rotation_degrees = Vector3(0, 0, 90)
	bow.scale = Vector3(1, 0.3, 1)  # Flatten into bow shape

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.2)
	bow.material_override = mat

	root.add_child(bow)


static func _add_claws(root: Node3D, color: Color) -> void:
	"""Add claws to Beast."""
	var claw_mat: StandardMaterial3D = StandardMaterial3D.new()
	claw_mat.albedo_color = color.lightened(0.2)

	for side in [-1, 1]:
		for i in range(3):
			var claw: MeshInstance3D = MeshInstance3D.new()
			claw.name = "Claw%d%s" % [i, "L" if side < 0 else "R"]
			var mesh: CylinderMesh = CylinderMesh.new()
			mesh.top_radius = 0.005
			mesh.bottom_radius = 0.015
			mesh.height = 0.08
			claw.mesh = mesh
			claw.position = Vector3(side * 0.28, 0.15, 0.02 + i * 0.025)
			claw.rotation_degrees.x = 45
			claw.material_override = claw_mat
			root.add_child(claw)


static func _add_staff(root: Node3D, color: Color) -> void:
	"""Add healing staff to Redeemer."""
	var staff: MeshInstance3D = MeshInstance3D.new()
	staff.name = "Staff"
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.025
	mesh.height = 0.8
	staff.mesh = mesh
	staff.position = Vector3(0.25, 0.4, 0)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.3
	staff.material_override = mat

	root.add_child(staff)


static func _add_halo(root: Node3D, color: Color) -> void:
	"""Add halo to Redeemer."""
	var halo: MeshInstance3D = MeshInstance3D.new()
	halo.name = "Halo"
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = 0.1
	mesh.outer_radius = 0.12
	halo.mesh = mesh
	halo.position = Vector3(0, 0.85, 0)
	halo.rotation_degrees.x = 90

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.0
	halo.material_override = mat

	root.add_child(halo)


static func _add_chains(root: Node3D, color: Color) -> void:
	"""Add chains to Confessor."""
	var chain_mat: StandardMaterial3D = StandardMaterial3D.new()
	chain_mat.albedo_color = color.darkened(0.4)
	chain_mat.metallic = 0.7

	# Hanging chains
	for i in range(3):
		var chain: MeshInstance3D = MeshInstance3D.new()
		chain.name = "Chain%d" % i
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = 0.01
		mesh.bottom_radius = 0.01
		mesh.height = 0.2 + i * 0.05
		chain.mesh = mesh
		chain.position = Vector3(-0.1 + i * 0.1, 0.2, 0.12)
		chain.material_override = chain_mat
		root.add_child(chain)


static func _add_axes(root: Node3D, color: Color) -> void:
	"""Add axes to Barbarian."""
	var axe_mat: StandardMaterial3D = StandardMaterial3D.new()
	axe_mat.albedo_color = color.darkened(0.2)
	axe_mat.metallic = 0.6

	for side in [-1, 1]:
		# Axe handle
		var handle: MeshInstance3D = MeshInstance3D.new()
		handle.name = "AxeHandle" + ("L" if side < 0 else "R")
		var h_mesh: CylinderMesh = CylinderMesh.new()
		h_mesh.top_radius = 0.015
		h_mesh.bottom_radius = 0.02
		h_mesh.height = 0.4
		handle.mesh = h_mesh
		handle.position = Vector3(side * 0.35, 0.35, 0)
		handle.rotation_degrees.z = side * -30
		handle.material_override = axe_mat
		root.add_child(handle)

		# Axe blade (flattened box)
		var blade: MeshInstance3D = MeshInstance3D.new()
		blade.name = "AxeBlade" + ("L" if side < 0 else "R")
		var b_mesh: BoxMesh = BoxMesh.new()
		b_mesh.size = Vector3(0.15, 0.1, 0.02)
		blade.mesh = b_mesh
		blade.position = Vector3(side * 0.45, 0.55, 0)

		var blade_mat: StandardMaterial3D = StandardMaterial3D.new()
		blade_mat.albedo_color = Color(0.7, 0.7, 0.75)
		blade_mat.metallic = 0.8
		blade.material_override = blade_mat
		root.add_child(blade)


static func _add_daggers(root: Node3D, color: Color) -> void:
	"""Add daggers to Burglar."""
	var dagger_mat: StandardMaterial3D = StandardMaterial3D.new()
	dagger_mat.albedo_color = Color(0.6, 0.6, 0.65)
	dagger_mat.metallic = 0.7

	for side in [-1, 1]:
		var dagger: MeshInstance3D = MeshInstance3D.new()
		dagger.name = "Dagger" + ("L" if side < 0 else "R")
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = 0.005
		mesh.bottom_radius = 0.02
		mesh.height = 0.2
		dagger.mesh = mesh
		dagger.position = Vector3(side * 0.25, 0.2, 0.05)
		dagger.rotation_degrees.x = 30
		dagger.material_override = dagger_mat
		root.add_child(dagger)


static func _add_large_weapon(root: Node3D, color: Color) -> void:
	"""Add large weapon to Berserker."""
	# Giant sword/axe on back
	var weapon: MeshInstance3D = MeshInstance3D.new()
	weapon.name = "GreatWeapon"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.15, 0.7, 0.03)
	weapon.mesh = mesh
	weapon.position = Vector3(0, 0.5, -0.15)
	weapon.rotation_degrees.z = 15

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.55)
	mat.metallic = 0.7
	weapon.material_override = mat

	root.add_child(weapon)


static func _add_spirit_staff(root: Node3D, color: Color) -> void:
	"""Add spirit staff to Shaman."""
	# Staff
	var staff: MeshInstance3D = MeshInstance3D.new()
	staff.name = "Staff"
	var s_mesh: CylinderMesh = CylinderMesh.new()
	s_mesh.top_radius = 0.02
	s_mesh.bottom_radius = 0.025
	s_mesh.height = 0.7
	staff.mesh = s_mesh
	staff.position = Vector3(0.22, 0.35, 0)

	var wood_mat: StandardMaterial3D = StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.4, 0.3, 0.2)
	staff.material_override = wood_mat
	root.add_child(staff)

	# Spirit orb at top
	var orb: MeshInstance3D = MeshInstance3D.new()
	orb.name = "SpiritOrb"
	var o_mesh: SphereMesh = SphereMesh.new()
	o_mesh.radius = 0.06
	orb.mesh = o_mesh
	orb.position = Vector3(0.22, 0.75, 0)

	var orb_mat: StandardMaterial3D = StandardMaterial3D.new()
	orb_mat.albedo_color = color
	orb_mat.emission_enabled = true
	orb_mat.emission = color
	orb_mat.emission_energy_multiplier = 0.8
	orb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	orb_mat.albedo_color.a = 0.7
	orb.material_override = orb_mat
	root.add_child(orb)


static func _add_mirror_shard(root: Node3D, color: Color) -> void:
	"""Add mirror shard effect to Illusionist."""
	var shard: MeshInstance3D = MeshInstance3D.new()
	shard.name = "MirrorShard"
	var mesh: PrismMesh = PrismMesh.new()
	mesh.size = Vector3(0.15, 0.25, 0.02)
	shard.mesh = mesh
	shard.position = Vector3(0.2, 0.5, 0.1)
	shard.rotation_degrees = Vector3(0, 30, 15)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color.lightened(0.3)
	mat.metallic = 0.9
	mat.roughness = 0.1
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.6
	shard.material_override = mat

	root.add_child(shard)


static func _add_skull_staff(root: Node3D, color: Color) -> void:
	"""Add skull staff to DarkWizard."""
	# Staff
	var staff: MeshInstance3D = MeshInstance3D.new()
	staff.name = "Staff"
	var s_mesh: CylinderMesh = CylinderMesh.new()
	s_mesh.top_radius = 0.018
	s_mesh.bottom_radius = 0.025
	s_mesh.height = 0.75
	staff.mesh = s_mesh
	staff.position = Vector3(0.22, 0.38, 0)

	var dark_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.15, 0.1, 0.2)
	staff.material_override = dark_mat
	root.add_child(staff)

	# Skull at top (simplified as sphere with features)
	var skull: MeshInstance3D = MeshInstance3D.new()
	skull.name = "Skull"
	var sk_mesh: SphereMesh = SphereMesh.new()
	sk_mesh.radius = 0.07
	skull.mesh = sk_mesh
	skull.position = Vector3(0.22, 0.8, 0)

	var skull_mat: StandardMaterial3D = StandardMaterial3D.new()
	skull_mat.albedo_color = Color(0.9, 0.85, 0.75)
	skull_mat.emission_enabled = true
	skull_mat.emission = color
	skull_mat.emission_energy_multiplier = 0.4
	skull.material_override = skull_mat
	root.add_child(skull)


static func _add_backpack(root: Node3D, color: Color) -> void:
	"""Add backpack to Alchemist."""
	var backpack: MeshInstance3D = MeshInstance3D.new()
	backpack.name = "Backpack"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.2, 0.25, 0.12)
	backpack.mesh = mesh
	backpack.position = Vector3(0, 0.45, -0.15)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.3)
	backpack.material_override = mat
	root.add_child(backpack)

	# Flask on side
	var flask: MeshInstance3D = MeshInstance3D.new()
	flask.name = "Flask"
	var f_mesh: CylinderMesh = CylinderMesh.new()
	f_mesh.top_radius = 0.025
	f_mesh.bottom_radius = 0.035
	f_mesh.height = 0.1
	flask.mesh = f_mesh
	flask.position = Vector3(0.18, 0.35, -0.08)

	var flask_mat: StandardMaterial3D = StandardMaterial3D.new()
	flask_mat.albedo_color = color
	flask_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flask_mat.albedo_color.a = 0.7
	flask.material_override = flask_mat
	root.add_child(flask)
