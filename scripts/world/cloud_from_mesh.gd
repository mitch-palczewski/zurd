@tool
class_name CloudPuffs
extends MultiMeshInstance3D

## Turns a [MeshInstance3D] into a cloud by scattering overlapping spheres ("puffs") over its surface.
## Add this node as a SIBLING of the source MeshInstance3D, assign [member source], then press
## "Rebuild Cloud". The result is saved with the scene, so nothing is recomputed at runtime.

## The mesh to cloud-ify. Keep this node a sibling so the transforms line up.
@export var source: MeshInstance3D
## Hide the original mesh once the cloud is built.
@export var hide_source: bool = true

@export_group("Puffs")
@export_range(1, 500) var puff_count: int = 80
## Puff radius range, as a fraction of the source mesh's longest side.
@export_range(0.01, 0.5, 0.005) var min_radius_ratio: float = 0.07
@export_range(0.01, 0.5, 0.005) var max_radius_ratio: float = 0.15
## How deep puff centres sit under the surface, as a fraction of the puff radius.
## 0 = centres on the surface (cloud bulges outward), 1 = puffs mostly inside the original shape.
@export_range(-0.5, 1.0, 0.05) var inset: float = 0.5
## Minimum centre-to-centre spacing as a fraction of the larger puff radius. Higher = more even coverage.
@export_range(0.0, 1.5, 0.05) var min_spacing: float = 0.5
## Each puff's height is randomly squashed between this value and 1.0 (gives flatter cloud bottoms).
@export_range(0.5, 1.0, 0.05) var min_squash: float = 0.75
@export var random_seed: int = 1

@export_group("Appearance")
@export var cloud_material: Material:
	set(value):
		cloud_material = value
		material_override = value
@export_range(6, 48) var sphere_segments: int = 16

@export_tool_button("Rebuild Cloud", "Reload") var rebuild_button: Callable = rebuild


func _ready() -> void:
	if source and (multimesh == null or multimesh.instance_count == 0):
		rebuild()


## Samples random points over the source mesh's triangles (area-weighted) and places a sphere at each.
func rebuild() -> void:
	if source == null or source.mesh == null:
		push_warning("CloudPuffs: assign a source MeshInstance3D that has a mesh.")
		return

	var faces: PackedVector3Array = source.mesh.get_faces()
	if faces.size() < 3:
		push_warning("CloudPuffs: source mesh has no triangles.")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	var longest_side: float = maxf(source.mesh.get_aabb().get_longest_axis_size(), 0.001)
	var min_radius: float = minf(min_radius_ratio, max_radius_ratio) * longest_side
	var max_radius: float = maxf(min_radius_ratio, max_radius_ratio) * longest_side

	# Cumulative triangle areas so big triangles get proportionally more puffs.
	var tri_count: int = int(faces.size() / 3.0)
	var cumulative := PackedFloat64Array()
	var total_area := 0.0
	for i in tri_count:
		var a: Vector3 = faces[i * 3]
		var b: Vector3 = faces[i * 3 + 1]
		var c: Vector3 = faces[i * 3 + 2]
		total_area += (b - a).cross(c - a).length() * 0.5
		cumulative.append(total_area)

	if total_area <= 0.0:
		push_warning("CloudPuffs: source mesh has zero surface area.")
		return

	var centers: Array[Vector3] = []
	var radii: Array[float] = []
	var attempts := 0
	var max_attempts: int = puff_count * 20

	while centers.size() < puff_count and attempts < max_attempts:
		attempts += 1

		var tri: int = mini(cumulative.bsearch(rng.randf() * total_area), tri_count - 1)
		var a: Vector3 = faces[tri * 3]
		var b: Vector3 = faces[tri * 3 + 1]
		var c: Vector3 = faces[tri * 3 + 2]

		# Uniform random point inside the triangle
		var r1: float = sqrt(rng.randf())
		var r2: float = rng.randf()
		var point: Vector3 = a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)

		# Plane() assumes Godot's clockwise winding, so this matches the mesh's outward normal.
		var normal: Vector3 = Plane(a, b, c).normal
		var radius: float = rng.randf_range(min_radius, max_radius)
		var center: Vector3 = point - normal * radius * inset

		if _is_too_close(center, radius, centers, radii):
			continue

		centers.append(center)
		radii.append(radius)

	if centers.size() < puff_count:
		push_warning("CloudPuffs: only placed %d of %d puffs. Lower min_spacing or the radius range." % [centers.size(), puff_count])

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = sphere_segments
	sphere.rings = maxi(sphere_segments >> 1, 3)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true # per-puff noise seed read by cloud.gdshader via INSTANCE_CUSTOM
	mm.mesh = sphere
	mm.instance_count = centers.size()

	for i in centers.size():
		var squash: float = rng.randf_range(min_squash, 1.0)
		var puff_basis := Basis.from_scale(Vector3(1.0, squash, 1.0) * radii[i])
		mm.set_instance_transform(i, Transform3D(puff_basis, centers[i]))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 0.0))

	multimesh = mm
	material_override = cloud_material
	transform = source.transform
	source.visible = not hide_source


func _is_too_close(center: Vector3, radius: float, centers: Array[Vector3], radii: Array[float]) -> bool:
	for i in centers.size():
		var min_dist: float = maxf(radius, radii[i]) * min_spacing
		if center.distance_squared_to(centers[i]) < min_dist * min_dist:
			return true
	return false