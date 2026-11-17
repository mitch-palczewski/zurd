class_name CloudPuffs
extends MultiMeshInstance3D

## Soft puffs scattered over one of a cloud's object meshes (Cloud-Formation Design Doc §4.2), so
## the cloud reads as a cloud while the object stays recognisable. It hangs under the mesh, so it
## puffs up, swells, turns and grows with it, and works in the mesh's own space. [method build]
## places the puffs from the model's surface table ([method make_surface_table], worked out once
## per model, off the main thread, by [CloudSky]). Visual only.
## Adapted from the old editor-only CloudPuffs (commit a22d649).

## How deep a puff's centre sits under the surface, as a share of its radius: 0 puts centres on
## the surface, 1 hides puffs mostly inside the object.
const INSET := 0.5
## Each puff's height is squashed to between this and its width (flatter, cloud-like puffs).
const MIN_SQUASH := 0.75

## Each puff's transform in this node's space, as placed by [method build] (the MultiMesh holds
## the same; a headless run's renderer doesn't keep them).
var placements: Array[Transform3D] = []


## A model's triangles and their running total area, for picking points on its surface by area.
## [param surfaces] comes from [method EdgeLines.get_surfaces]. Safe on any thread.
static func make_surface_table(surfaces: Array) -> Dictionary:
	var triangles := PackedVector3Array()
	var cumulative := PackedFloat64Array()
	var total := 0.0
	var low := Vector3.INF
	var high := -Vector3.INF
	for surface: Array in surfaces:
		var vertices: PackedVector3Array = surface[0]
		var indices: PackedInt32Array = surface[1]
		for t in range(0, indices.size() - 2, 3):
			var a := vertices[indices[t]]
			var b := vertices[indices[t + 1]]
			var c := vertices[indices[t + 2]]
			triangles.append(a)
			triangles.append(b)
			triangles.append(c)
			total += (b - a).cross(c - a).length() * 0.5
			cumulative.append(total)
			low = low.min(a).min(b).min(c)
			high = high.max(a).max(b).max(c)
	var longest := (high - low).abs()
	return {"triangles": triangles, "cumulative": cumulative, "total": total,
			"longest": maxf(longest.x, maxf(longest.y, longest.z)) if total > 0.0 else 0.0}


## Scatters [param count] puffs over the model in [param table] ([method make_surface_table]), more
## where there's more surface, each [param size] (min, max) times the model's longest side.
## [param sphere] is a unit sphere.
func build(table: Dictionary, count: int, size: Vector2, sphere: Mesh, puff_material: Material, rng: RandomNumberGenerator) -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = puff_material
	placements.clear()
	var total: float = table.get("total", 0.0)
	if total > 0.0:
		var triangles: PackedVector3Array = table["triangles"]
		var cumulative: PackedFloat64Array = table["cumulative"]
		var longest: float = table["longest"]
		var last := cumulative.size() - 1
		for n in count:
			var t := mini(cumulative.bsearch(rng.randf() * total), last) * 3
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
