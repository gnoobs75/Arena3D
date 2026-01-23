extends RefCounted
class_name BodyBuilder
## BodyBuilder - Procedurally generates champion body meshes
## Creates low-poly stylized body parts for the 12 champion archetypes

# === BODY PARAMETERS ===
# These define the shape of each body part

class BodyParams:
	# Overall scale multipliers
	var height: float = 1.0        # Total height multiplier
	var bulk: float = 1.0          # Width/depth multiplier
	var head_size: float = 1.0     # Head scale
	var arm_length: float = 1.0    # Arm length multiplier
	var leg_length: float = 1.0    # Leg length multiplier

	# Body proportions
	var shoulder_width: float = 1.0  # Shoulder broadness
	var torso_taper: float = 0.8     # Waist relative to shoulders
	var chest_depth: float = 1.0     # Front-to-back depth

	# Limb thickness
	var arm_thickness: float = 1.0
	var leg_thickness: float = 1.0

	# Special features
	var hunched: bool = false        # Forward lean (Beast)
	var floating: bool = false       # Hovers slightly (Confessor, Illusionist)
	var robed: bool = false          # Has robe/cloak (Redeemer, DarkWizard)

	func _init():
		pass


# === CHAMPION BODY PRESETS ===

static func get_body_params(champion_name: String) -> BodyParams:
	"""Get body parameters for a specific champion."""
	var params: BodyParams = BodyParams.new()

	match champion_name:
		"Brute":
			params.height = 1.1
			params.bulk = 1.5
			params.head_size = 0.9  # Small head, big body
			params.shoulder_width = 1.4
			params.torso_taper = 0.9
			params.arm_thickness = 1.4
			params.leg_thickness = 1.3

		"Ranger":
			params.height = 1.0
			params.bulk = 0.8
			params.head_size = 1.0
			params.shoulder_width = 0.9
			params.arm_length = 1.1
			params.leg_length = 1.05
			params.arm_thickness = 0.8
			params.leg_thickness = 0.85

		"Beast":
			params.height = 0.95
			params.bulk = 1.1
			params.head_size = 1.1
			params.shoulder_width = 1.2
			params.arm_length = 1.2
			params.hunched = true
			params.arm_thickness = 1.1

		"Redeemer":
			params.height = 1.15
			params.bulk = 0.85
			params.head_size = 0.95
			params.shoulder_width = 0.85
			params.torso_taper = 0.95  # More straight due to robes
			params.robed = true
			params.leg_thickness = 0.9

		"Confessor":
			params.height = 1.2
			params.bulk = 0.7
			params.head_size = 1.1  # Imposing head
			params.shoulder_width = 0.75
			params.torso_taper = 0.6  # Very thin waist
			params.floating = true
			params.arm_thickness = 0.7
			params.leg_thickness = 0.6

		"Barbarian":
			params.height = 1.05
			params.bulk = 1.3
			params.head_size = 1.0
			params.shoulder_width = 1.3
			params.chest_depth = 1.2
			params.arm_thickness = 1.3
			params.leg_thickness = 1.2

		"Burglar":
			params.height = 0.95
			params.bulk = 0.75
			params.head_size = 1.0
			params.shoulder_width = 0.85
			params.arm_length = 0.95
			params.leg_length = 1.0
			params.arm_thickness = 0.75
			params.leg_thickness = 0.8

		"Berserker":
			params.height = 1.1
			params.bulk = 1.4
			params.head_size = 0.95
			params.shoulder_width = 1.35
			params.chest_depth = 1.15
			params.arm_thickness = 1.35
			params.leg_thickness = 1.25

		"Shaman":
			params.height = 1.0
			params.bulk = 1.0
			params.head_size = 1.1  # Slightly larger head
			params.shoulder_width = 1.0
			params.arm_thickness = 0.95
			params.leg_thickness = 1.0

		"Illusionist":
			params.height = 1.0
			params.bulk = 0.85
			params.head_size = 1.05
			params.shoulder_width = 0.9
			params.floating = true
			params.arm_thickness = 0.8
			params.leg_thickness = 0.75

		"DarkWizard":
			params.height = 1.1
			params.bulk = 0.9
			params.head_size = 1.0
			params.shoulder_width = 0.95
			params.torso_taper = 0.85
			params.robed = true
			params.arm_thickness = 0.85

		"Alchemist":
			params.height = 0.95
			params.bulk = 1.0
			params.head_size = 1.1  # Goggles make head look bigger
			params.shoulder_width = 1.0
			params.chest_depth = 1.1  # Has backpack
			params.arm_thickness = 0.9
			params.leg_thickness = 0.95

	return params


# === MESH GENERATION ===

static func build_torso(params: BodyParams) -> ArrayMesh:
	"""Generate torso mesh based on parameters."""
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var shoulder_w: float = 0.25 * params.shoulder_width * params.bulk
	var waist_w: float = shoulder_w * params.torso_taper
	var depth: float = 0.15 * params.chest_depth * params.bulk
	var height: float = 0.35 * params.height

	# Build a tapered box (wider at top)
	# Front face
	_add_quad(st,
		Vector3(-waist_w, 0, depth),
		Vector3(waist_w, 0, depth),
		Vector3(shoulder_w, height, depth * 0.9),
		Vector3(-shoulder_w, height, depth * 0.9),
		Vector3(0, 0, 1)
	)

	# Back face
	_add_quad(st,
		Vector3(waist_w, 0, -depth),
		Vector3(-waist_w, 0, -depth),
		Vector3(-shoulder_w, height, -depth * 0.9),
		Vector3(shoulder_w, height, -depth * 0.9),
		Vector3(0, 0, -1)
	)

	# Left face
	_add_quad(st,
		Vector3(-waist_w, 0, -depth),
		Vector3(-waist_w, 0, depth),
		Vector3(-shoulder_w, height, depth * 0.9),
		Vector3(-shoulder_w, height, -depth * 0.9),
		Vector3(-1, 0, 0)
	)

	# Right face
	_add_quad(st,
		Vector3(waist_w, 0, depth),
		Vector3(waist_w, 0, -depth),
		Vector3(shoulder_w, height, -depth * 0.9),
		Vector3(shoulder_w, height, depth * 0.9),
		Vector3(1, 0, 0)
	)

	# Top face
	_add_quad(st,
		Vector3(-shoulder_w, height, depth * 0.9),
		Vector3(shoulder_w, height, depth * 0.9),
		Vector3(shoulder_w, height, -depth * 0.9),
		Vector3(-shoulder_w, height, -depth * 0.9),
		Vector3(0, 1, 0)
	)

	# Bottom face
	_add_quad(st,
		Vector3(-waist_w, 0, -depth),
		Vector3(waist_w, 0, -depth),
		Vector3(waist_w, 0, depth),
		Vector3(-waist_w, 0, depth),
		Vector3(0, -1, 0)
	)

	st.generate_normals()
	return st.commit()


static func build_head(params: BodyParams) -> ArrayMesh:
	"""Generate head mesh - simple sphere-ish shape."""
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var size: float = 0.12 * params.head_size

	# Build icosphere-like head (low poly)
	var segments: int = 8
	var rings: int = 6

	for i in range(rings):
		var lat0: float = PI * (float(i) / rings - 0.5)
		var lat1: float = PI * (float(i + 1) / rings - 0.5)

		for j in range(segments):
			var lon0: float = 2 * PI * float(j) / segments
			var lon1: float = 2 * PI * float(j + 1) / segments

			# Vertex positions on sphere
			var p0: Vector3 = Vector3(cos(lat0) * cos(lon0), sin(lat0), cos(lat0) * sin(lon0)) * size
			var p1: Vector3 = Vector3(cos(lat0) * cos(lon1), sin(lat0), cos(lat0) * sin(lon1)) * size
			var p2: Vector3 = Vector3(cos(lat1) * cos(lon1), sin(lat1), cos(lat1) * sin(lon1)) * size
			var p3: Vector3 = Vector3(cos(lat1) * cos(lon0), sin(lat1), cos(lat1) * sin(lon0)) * size

			# Two triangles per quad
			st.set_normal(p0.normalized())
			st.add_vertex(p0)
			st.set_normal(p1.normalized())
			st.add_vertex(p1)
			st.set_normal(p2.normalized())
			st.add_vertex(p2)

			st.set_normal(p0.normalized())
			st.add_vertex(p0)
			st.set_normal(p2.normalized())
			st.add_vertex(p2)
			st.set_normal(p3.normalized())
			st.add_vertex(p3)

	return st.commit()


static func build_arm(params: BodyParams, is_left: bool) -> ArrayMesh:
	"""Generate arm mesh - tapered cylinder."""
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var length: float = 0.25 * params.arm_length
	var thickness: float = 0.05 * params.arm_thickness

	# Upper arm
	_add_cylinder_segment(st, Vector3.ZERO, Vector3(0, -length * 0.5, 0), thickness, thickness * 0.9)

	# Forearm
	_add_cylinder_segment(st, Vector3(0, -length * 0.5, 0), Vector3(0, -length, 0), thickness * 0.85, thickness * 0.6)

	st.generate_normals()
	return st.commit()


static func build_leg(params: BodyParams, is_left: bool) -> ArrayMesh:
	"""Generate leg mesh - tapered cylinder."""
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var length: float = 0.3 * params.leg_length
	var thickness: float = 0.07 * params.leg_thickness

	# Upper leg
	_add_cylinder_segment(st, Vector3.ZERO, Vector3(0, -length * 0.5, 0), thickness, thickness * 0.85)

	# Lower leg
	_add_cylinder_segment(st, Vector3(0, -length * 0.5, 0), Vector3(0, -length, 0), thickness * 0.8, thickness * 0.5)

	st.generate_normals()
	return st.commit()


static func build_robe(params: BodyParams) -> ArrayMesh:
	"""Generate robe mesh for robed champions."""
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var shoulder_w: float = 0.28 * params.shoulder_width * params.bulk
	var bottom_w: float = shoulder_w * 1.3  # Flares out at bottom
	var height: float = 0.5 * params.height
	var depth: float = 0.18 * params.bulk

	# Robe is a flared cone shape
	var segments: int = 12
	for i in range(segments):
		var angle0: float = 2 * PI * float(i) / segments
		var angle1: float = 2 * PI * float(i + 1) / segments

		# Top ring (shoulder level)
		var top0: Vector3 = Vector3(cos(angle0) * shoulder_w, 0.35 * params.height, sin(angle0) * depth)
		var top1: Vector3 = Vector3(cos(angle1) * shoulder_w, 0.35 * params.height, sin(angle1) * depth)

		# Bottom ring (ground level)
		var bot0: Vector3 = Vector3(cos(angle0) * bottom_w, 0, sin(angle0) * depth * 1.2)
		var bot1: Vector3 = Vector3(cos(angle1) * bottom_w, 0, sin(angle1) * depth * 1.2)

		var normal: Vector3 = (bot0 - top0).cross(top1 - top0).normalized()

		st.set_normal(normal)
		st.add_vertex(top0)
		st.set_normal(normal)
		st.add_vertex(top1)
		st.set_normal(normal)
		st.add_vertex(bot1)

		st.set_normal(normal)
		st.add_vertex(top0)
		st.set_normal(normal)
		st.add_vertex(bot1)
		st.set_normal(normal)
		st.add_vertex(bot0)

	return st.commit()


# === HELPER FUNCTIONS ===

static func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3) -> void:
	"""Add a quad (two triangles) to the surface tool."""
	st.set_normal(normal)
	st.add_vertex(v0)
	st.set_normal(normal)
	st.add_vertex(v1)
	st.set_normal(normal)
	st.add_vertex(v2)

	st.set_normal(normal)
	st.add_vertex(v0)
	st.set_normal(normal)
	st.add_vertex(v2)
	st.set_normal(normal)
	st.add_vertex(v3)


static func _add_cylinder_segment(st: SurfaceTool, start: Vector3, end: Vector3, start_radius: float, end_radius: float) -> void:
	"""Add a tapered cylinder segment."""
	var segments: int = 8
	var dir: Vector3 = (end - start).normalized()

	# Create perpendicular vectors for cylinder orientation
	var perp1: Vector3 = Vector3(1, 0, 0)
	if abs(dir.dot(perp1)) > 0.9:
		perp1 = Vector3(0, 0, 1)
	perp1 = dir.cross(perp1).normalized()
	var perp2: Vector3 = dir.cross(perp1).normalized()

	for i in range(segments):
		var angle0: float = 2 * PI * float(i) / segments
		var angle1: float = 2 * PI * float(i + 1) / segments

		var offset0: Vector3 = perp1 * cos(angle0) + perp2 * sin(angle0)
		var offset1: Vector3 = perp1 * cos(angle1) + perp2 * sin(angle1)

		var v0: Vector3 = start + offset0 * start_radius
		var v1: Vector3 = start + offset1 * start_radius
		var v2: Vector3 = end + offset1 * end_radius
		var v3: Vector3 = end + offset0 * end_radius

		var normal: Vector3 = offset0

		st.set_normal(normal)
		st.add_vertex(v0)
		st.set_normal((offset0 + offset1).normalized())
		st.add_vertex(v1)
		st.set_normal((offset0 + offset1).normalized())
		st.add_vertex(v2)

		st.set_normal(normal)
		st.add_vertex(v0)
		st.set_normal((offset0 + offset1).normalized())
		st.add_vertex(v2)
		st.set_normal(offset0)
		st.add_vertex(v3)
