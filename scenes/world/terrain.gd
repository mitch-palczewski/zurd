@tool
class_name Terrain
extends MeshInstance3D

## Procedural landscape: continents and coasts, ridged mountain ranges, rolling hills and
## river valleys. Sea level is this node's local y = 0, so a water plane at y = 0 fills the
## seas and rivers. The mesh is rebuilt from the settings in _ready, not saved in the scene.

@export_group("Grid Settings")
@export var terrain_size: Vector2 = Vector2(800.0, 800.0):
	set(value):
		terrain_size = value
		_queue_generate()

@export var resolution: Vector2i = Vector2i(128, 128):
	set(value):
		resolution = Vector2i(max(2, value.x), max(2, value.y))
		_queue_generate()

@export_group("Shape")
@export var noise_seed: int = 0:
	set(value):
		noise_seed = value
		_queue_generate()

@export_tool_button("New Seed", "RandomNumberGenerator") var new_seed := _randomize_seed

## Multiplies the horizontal size of every feature. Bigger means broader mountains and seas.
@export_range(0.1, 5.0, 0.01, "or_greater") var feature_scale: float = 1.0:
	set(value):
		feature_scale = maxf(value, 0.01)
		_queue_generate()

## Height of the highest peak above sea level, in meters.
@export var height_scale: float = 80.0:
	set(value):
		height_scale = value
		_queue_generate()

## Share of the map that lies below sea level.
@export_range(0.0, 0.95, 0.01) var sea_coverage: float = 0.3:
	set(value):
		sea_coverage = value
		_queue_generate()

## Depth of the deepest seabed below sea level, in meters.
@export var sea_depth: float = 15.0:
	set(value):
		sea_depth = value
		_queue_generate()

## Above 1 flattens the lowlands and sharpens the peaks.
@export_range(0.5, 4.0, 0.01) var height_curve: float = 1.3:
	set(value):
		height_curve = value
		_queue_generate()

## How far, in meters, coasts and ridges are bent so they curve instead of looking like blobs.
@export_range(0.0, 300.0, 1.0) var warp_strength: float = 80.0:
	set(value):
		warp_strength = value
		_queue_generate()

## Lowers the land toward the map edges so the map becomes an island. 0 turns it off.
@export_range(0.0, 0.5, 0.01) var edge_falloff: float = 0.0:
	set(value):
		edge_falloff = value
		_queue_generate()

@export_group("Mountains")
## Share of the map covered by mountain ranges.
@export_range(0.0, 1.0, 0.01) var mountain_amount: float = 0.4:
	set(value):
		mountain_amount = value
		_queue_generate()

## Higher gives thinner, sharper ridges.
@export_range(1.0, 4.0, 0.01) var mountain_sharpness: float = 2.0:
	set(value):
		mountain_sharpness = value
		_queue_generate()

@export_group("Hills")
@export_range(0.0, 1.0, 0.01) var hill_amount: float = 0.25:
	set(value):
		hill_amount = value
		_queue_generate()

@export_group("Rivers")
## Width of river valleys. 0 turns rivers off.
@export_range(0.0, 0.2, 0.001) var river_width: float = 0.04:
	set(value):
		river_width = value
		_queue_generate()

## How far below sea level the river beds are cut, in meters.
@export var river_depth: float = 3.0:
	set(value):
		river_depth = value
		_queue_generate()

@export_group("Collision")
## Builds a static trimesh collider from the terrain mesh.
@export var generate_collision: bool = true:
	set(value):
		generate_collision = value
		_queue_generate()

## Layer 1 is Environment, which the ship's ground ray and the Zurds' avoidance rays hit.
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		if _collision_body:
			_collision_body.collision_layer = value

var _generate_queued := false
var _collision_body: StaticBody3D
var _warp_noise: FastNoiseLite
var _continent_noise: FastNoiseLite
var _range_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _hill_noise: FastNoiseLite
var _river_noise: FastNoiseLite

func _ready() -> void:
	_generate_terrain()

# The mesh is rebuilt in _ready, so keep it out of the saved scene.
func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage &= ~PROPERTY_USAGE_STORAGE

# Coalesces setter calls into one rebuild per frame and skips the ones made while the scene loads.
func _queue_generate() -> void:
	if _generate_queued or not is_node_ready():
		return
	_generate_queued = true
	_generate_terrain.call_deferred()

func _randomize_seed() -> void:
	noise_seed = randi()
	notify_property_list_changed()

func _generate_terrain() -> void:
	_generate_queued = false
	_setup_noises()

	var count := resolution.x * resolution.y
	var heights := PackedFloat32Array()
	var rivers := PackedFloat32Array()
	heights.resize(count)
	rivers.resize(count)

	for z in resolution.y:
		for x in resolution.x:
			var i := z * resolution.x + x
			var pos := _grid_position(x, z)
			var warped := _warp(pos)
			heights[i] = _base_height(warped, x, z)
			if river_width > 0.0:
				rivers[i] = 1.0 - smoothstep(0.0, river_width, absf(_river_noise.get_noise_2dv(warped)))

	_shape_heights(heights, rivers)
	var array_mesh := _build_mesh(heights)
	mesh = array_mesh
	_update_collision(array_mesh)

# The body is an internal child, so it is rebuilt with the mesh and never saved in the scene.
func _update_collision(array_mesh: ArrayMesh) -> void:
	if not generate_collision:
		if _collision_body:
			_collision_body.queue_free()
			_collision_body = null
		return

	if not _collision_body:
		_collision_body = StaticBody3D.new()
		_collision_body.name = "TerrainCollision"
		_collision_body.collision_layer = collision_layer
		_collision_body.collision_mask = 0
		_collision_body.add_child(CollisionShape3D.new())
		add_child(_collision_body, false, INTERNAL_MODE_BACK)
	var collision_shape: CollisionShape3D = _collision_body.get_child(0)
	collision_shape.shape = array_mesh.create_trimesh_shape()

func _setup_noises() -> void:
	_warp_noise = _make_noise(0, 400.0, 3)
	_continent_noise = _make_noise(1, 700.0, 4)
	_range_noise = _make_noise(2, 500.0, 2)
	_ridge_noise = _make_noise(3, 180.0, 5, FastNoiseLite.FRACTAL_RIDGED)
	_hill_noise = _make_noise(4, 120.0, 4)
	_river_noise = _make_noise(5, 600.0, 2)

# feature_size is roughly the distance in meters between the noise's largest bumps.
func _make_noise(index: int, feature_size: float, octaves: int, fractal: FastNoiseLite.FractalType = FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = noise_seed + index * 1013
	n.frequency = 1.0 / (feature_size * feature_scale)
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n

func _grid_position(x: int, z: int) -> Vector2:
	var u := float(x) / float(resolution.x - 1)
	var v := float(z) / float(resolution.y - 1)
	return Vector2((u - 0.5) * terrain_size.x, (v - 0.5) * terrain_size.y)

func _warp(pos: Vector2) -> Vector2:
	var offset := Vector2(
		_warp_noise.get_noise_2dv(pos),
		_warp_noise.get_noise_2d(pos.x + 5200.0, pos.y - 1300.0))
	return pos + offset * warp_strength * feature_scale

# Unitless height: broad continents, hills everywhere, ridged mountains inside the ranges.
func _base_height(pos: Vector2, x: int, z: int) -> float:
	var continent := _continent_noise.get_noise_2dv(pos)
	var hills := _hill_noise.get_noise_2dv(pos) * hill_amount

	var range_threshold := lerpf(0.5, -0.5, mountain_amount)
	var range_mask := smoothstep(range_threshold - 0.1, range_threshold + 0.1, _range_noise.get_noise_2dv(pos))
	var ridges := pow(_ridge_noise.get_noise_2dv(pos) * 0.5 + 0.5, mountain_sharpness)

	var height := continent * 0.5 + hills + ridges * range_mask

	if edge_falloff > 0.0:
		var u := float(x) / float(resolution.x - 1)
		var v := float(z) / float(resolution.y - 1)
		var edge_distance := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
		height -= (1.0 - smoothstep(0.0, edge_falloff, edge_distance)) * 1.5
	return height

# Puts sea level at y = 0 so sea_coverage of the map is underwater, scales land and seabed
# to meters, then cuts the river valleys.
func _shape_heights(heights: PackedFloat32Array, rivers: PackedFloat32Array) -> void:
	var sorted := heights.duplicate()
	sorted.sort()
	var count := sorted.size()
	var sea_level := sorted[int(sea_coverage * (count - 1))]
	var highest := maxf(sorted[count - 1] - sea_level, 0.0001)
	var lowest := maxf(sea_level - sorted[0], 0.0001)

	for i in count:
		var height := heights[i] - sea_level
		var river := rivers[i]
		if height >= 0.0:
			var normalized := height / highest
			# Rivers run through the lowlands and fade out in the mountains
			river *= 1.0 - smoothstep(0.15, 0.4, normalized)
			height = pow(normalized, height_curve) * height_scale
		else:
			# Gentle shelf along the coast, flat floor in the deep
			height = -smoothstep(0.0, 1.0, -height / lowest) * sea_depth
		heights[i] = lerpf(height, minf(height, -river_depth), river)

func _build_mesh(heights: PackedFloat32Array) -> ArrayMesh:
	var count := heights.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(count)
	normals.resize(count)
	uvs.resize(count)

	for z in resolution.y:
		for x in resolution.x:
			var i := z * resolution.x + x
			var pos := _grid_position(x, z)
			vertices[i] = Vector3(pos.x, heights[i], pos.y)
			normals[i] = _grid_normal(heights, x, z)
			uvs[i] = Vector2(float(x) / float(resolution.x - 1), float(z) / float(resolution.y - 1))

	# Triangles (clockwise winding)
	var indices := PackedInt32Array()
	indices.resize((resolution.x - 1) * (resolution.y - 1) * 6)
	var n := 0
	for z in resolution.y - 1:
		for x in resolution.x - 1:
			var top_left := z * resolution.x + x
			var top_right := top_left + 1
			var bottom_left := top_left + resolution.x
			var bottom_right := bottom_left + 1
			indices[n] = top_left
			indices[n + 1] = top_right
			indices[n + 2] = bottom_right
			indices[n + 3] = top_left
			indices[n + 4] = bottom_right
			indices[n + 5] = bottom_left
			n += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh

# Central differences between neighboring grid heights (one-sided at the edges)
func _grid_normal(heights: PackedFloat32Array, x: int, z: int) -> Vector3:
	var x0 := maxi(x - 1, 0)
	var x1 := mini(x + 1, resolution.x - 1)
	var z0 := maxi(z - 1, 0)
	var z1 := mini(z + 1, resolution.y - 1)
	var cell := Vector2(terrain_size.x / float(resolution.x - 1), terrain_size.y / float(resolution.y - 1))
	var row := z * resolution.x
	var slope_x := (heights[row + x1] - heights[row + x0]) / (float(x1 - x0) * cell.x)
	var slope_z := (heights[z1 * resolution.x + x] - heights[z0 * resolution.x + x]) / (float(z1 - z0) * cell.y)
	return Vector3(-slope_x, 1.0, -slope_z).normalized()
