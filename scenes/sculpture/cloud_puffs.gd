class_name CloudPuffs
extends MultiMeshInstance3D

## Soft puffs scattered over one of a cloud's objects (Cloud-Formation Design Doc §4.2), so the
## cloud reads as a cloud while the object stays recognisable. It sits under the object's piece, so
## it puffs up, swells, turns and grows with the object. Built once by [method build]; visual only.
## Adapted from the old editor-only CloudPuffs (commit a22d649).

## How deep a puff's centre sits under the surface, as a share of its radius: 0 puts centres on
## the surface, 1 hides puffs mostly inside the object.
const INSET := 0.5
## Each puff's height is squashed to between this and its width (flatter, cloud-like puffs).
const MIN_SQUASH := 0.75

## Each puff's transform in this node's space, as placed by [method build] (the MultiMesh holds
## the same; a headless run's renderer doesn't keep them).
var placements: Array[Transform3D] = []


## Scatters [param count] puffs over [param meshes] (one object's meshes), more where there's more
## surface, each [param size] (min, max) times the object's longest side. [param sphere] is a unit
## sphere. Works in this node's space, so add it under the object first.
func build(meshes: Array[MeshInstance3D], count: int, size: Vector2, sphere: Mesh, puff_material: Material, rng: RandomNumberGenerator) -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = puff_material

	var to_here := global_transform.affine_inverse()
	var triangles := PackedVector3Array()
	var bounds := AABB()
	var has_bounds := false
	for mesh_instance in meshes:
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var xform := to_here * mesh_instance.global_transform
		# A mirrored transform flips the winding, and with it the faces' outward side.
		var mirrored := xform.basis.determinant() < 0.0
		var faces := mesh_instance.mesh.get_faces()
		for i in range(0, faces.size() - 2, 3):
			triangles.append(xform * faces[i])
			triangles.append(xform * faces[i + 2 if mirrored else i + 1])
			triangles.append(xform * faces[i + 1 if mirrored else i + 2])
		var box := xform * mesh_instance.get_aabb()
		bounds = bounds.merge(box) if has_bounds else box
		has_bounds = true

	var cumulative := PackedFloat64Array()
	var total_area := 0.0
	for i in range(0, triangles.size(), 3):
		total_area += (triangles[i + 1] - triangles[i]).cross(triangles[i + 2] - triangles[i]).length() * 0.5
		cumulative.append(total_area)

	placements.clear()
	if total_area > 0.0:
		var longest := bounds.get_longest_axis_size()
		var last := cumulative.size() - 1
		for n in count:
			var t := mini(cumulative.bsearch(rng.randf() * total_area), last) * 3
			var a := triangles[t]
			var b := triangles[t + 1]
			var c := triangles[t + 2]
			# A uniform random point on the triangle.
			var r1 := sqrt(rng.randf())
			var r2 := rng.randf()
			var point := a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)
			# Plane() takes Godot's clockwise front faces, so this is the outward normal.
			var normal := Plane(a, b, c).normal
			var radius := rng.randf_range(size.x, size.y) * longest
			var squash := rng.randf_range(MIN_SQUASH, 1.0)
			placements.append(Transform3D(Basis.from_scale(Vector3(1.0, squash, 1.0) * radius), point - normal * radius * INSET))

	var puffs := MultiMesh.new()
	puffs.transform_format = MultiMesh.TRANSFORM_3D
	# Per-puff noise seed (xyz) and fade (w), read by cloud_puff.gdshader.
	puffs.use_custom_data = true
	puffs.mesh = sphere
	puffs.instance_count = placements.size()
	for i in placements.size():
		puffs.set_instance_transform(i, placements[i])
		puffs.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 0.0))
	multimesh = puffs
