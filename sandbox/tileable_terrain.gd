@tool
class_name TileableTerrain
extends MeshInstance3D

@export_group("Grid Settings")
@export var terrain_size: Vector2 = Vector2(20.0, 20.0):
	set(value):
		terrain_size = value
		_generate_terrain()

@export var resolution: Vector2i = Vector2i(32, 32):
	set(value):
		resolution = Vector2i(max(2, value.x), max(2, value.y))
		_generate_terrain()

@export var height_scale: float = 4.0:
	set(value):
		height_scale = value
		_generate_terrain()

@export_group("Noise Settings")
@export var noise: FastNoiseLite:
	set(value):
		noise = value
		if noise and not noise.changed.is_connected(_generate_terrain):
			noise.changed.connect(_generate_terrain)
		_generate_terrain()

func _ready() -> void:
	if not noise:
		noise = FastNoiseLite.new()
		noise.seed = randi()
		noise.frequency = 0.02
		noise.changed.connect(_generate_terrain)
	_generate_terrain()

func _generate_terrain() -> void:
	if resolution.x < 2 or resolution.y < 2:
		return

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1. Generate Vertices and Seamless Normals
	for z in range(resolution.y):
		for x in range(resolution.x):
			# Normalized coordinates (0.0 to 1.0)
			var u = float(x) / float(resolution.x - 1)
			var v = float(z) / float(resolution.y - 1)

			# Centered world positions
			var pos_x = (u - 0.5) * terrain_size.x
			var pos_z = (v - 0.5) * terrain_size.y

			# Seamless height & normal
			var height = _get_seamless_height(u, v) * height_scale
			var normal = _get_seamless_normal(u, v)

			st.set_uv(Vector2(u, v))
			st.set_normal(normal)
			st.add_vertex(Vector3(pos_x, height, pos_z))

	# 2. Generate Triangles (Indices - Clockwise Winding Order)
	for z in range(resolution.y - 1):
		for x in range(resolution.x - 1):
			var top_left = z * resolution.x + x
			var top_right = top_left + 1
			var bottom_left = (z + 1) * resolution.x + x
			var bottom_right = bottom_left + 1

			# Triangle 1 (Top-Right half)
			st.add_index(top_left)
			st.add_index(top_right)
			st.add_index(bottom_right)

			# Triangle 2 (Bottom-Left half)
			st.add_index(top_left)
			st.add_index(bottom_right)
			st.add_index(bottom_left)

	st.generate_tangents()
	mesh = st.commit()

# Seamless 2D Noise Crossfading across tile boundaries
func _get_seamless_height(u: float, v: float) -> float:
	if not noise:
		return 0.0

	# Keep coordinates wrapped cleanly between 0.0 and 1.0
	u = wrapf(u, 0.0, 1.0)
	v = wrapf(v, 0.0, 1.0)

	var x = u * terrain_size.x
	var z = v * terrain_size.y
	var sx = terrain_size.x
	var sz = terrain_size.y

	# Sample 4 tile corners
	var v1 = noise.get_noise_2d(x, z)
	var v2 = noise.get_noise_2d(x - sx, z)
	var v3 = noise.get_noise_2d(x, z - sz)
	var v4 = noise.get_noise_2d(x - sx, z - sz)

	# Smoothstep blending weights
	var blend_x = smoothstep(0.0, 1.0, u)
	var blend_z = smoothstep(0.0, 1.0, v)

	# Interpolate height
	var top = lerp(v1, v2, blend_x)
	var bottom = lerp(v3, v4, blend_x)
	return lerp(top, bottom, blend_z)

# Normal calculation using wrapped finite differences
func _get_seamless_normal(u: float, v: float) -> Vector3:
	var eps = 0.005
	var h = _get_seamless_height(u, v)
	var h_du = _get_seamless_height(u + eps, v)
	var h_dv = _get_seamless_height(u, v + eps)

	var tangent_u = Vector3(eps * terrain_size.x, (h_du - h) * height_scale, 0.0)
	var tangent_v = Vector3(0.0, (h_dv - h) * height_scale, eps * terrain_size.y)

	return tangent_v.cross(tangent_u).normalized()
    