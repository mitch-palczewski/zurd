class_name EdgeLines
extends RefCounted

## Lines along a model's edges, drawn a fixed number of pixels wide by a shader that includes
## assets/shaders/edge_outline.gdshaderinc: the reflecting pool's outline and the clouds' ridges.
## [method find_feature_edges] picks the edges, [method build_outline_mesh] turns them into the
## line mesh. For a big model that takes a noticeable moment, so the work also comes in pieces that
## can run on another thread: [method get_surfaces] (main thread), then
## [method find_feature_edges_in] and [method build_outline_arrays] (any thread), then
## [method mesh_from_arrays] (main thread).


## The model's feature edges, as pairs of points (start, end, start, end, ...): edges that only one
## face uses, and edges where two faces meet at more than [param min_angle_degrees]. Points closer
## than a tenth of a millimetre count as one, so flat-shaded meshes (split vertices) work too.
static func find_feature_edges(mesh: Mesh, min_angle_degrees: float) -> PackedVector3Array:
	return find_feature_edges_in(get_surfaces(mesh), min_angle_degrees)


## [param mesh]'s surfaces as [vertices, indices] pairs, copied out so another thread can work on
## them. Surfaces without indices get them, one per vertex.
static func get_surfaces(mesh: Mesh) -> Array:
	var surfaces := []
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			indices.resize(vertices.size())
			for i in vertices.size():
				indices[i] = i
		surfaces.append([vertices, indices])
	return surfaces


## [method find_feature_edges] on surfaces from [method get_surfaces]. Safe on any thread.
static func find_feature_edges_in(surfaces: Array, min_angle_degrees: float) -> PackedVector3Array:
	var points: Array[Vector3] = []
	var point_ids := {}
	# { Vector2i(lower id, higher id): Array of face normals }
	var edge_faces := {}
	for surface: Array in surfaces:
		var vertices: PackedVector3Array = surface[0]
		var indices: PackedInt32Array = surface[1]
		for t in range(0, indices.size() - 2, 3):
			var corners: Array[int] = []
			for k in 3:
				var vertex := vertices[indices[t + k]]
				var key := Vector3i((vertex * 10000.0).round())
				if not point_ids.has(key):
					point_ids[key] = points.size()
					points.append(vertex)
				corners.append(point_ids[key])
			var normal := (points[corners[1]] - points[corners[0]]).cross(points[corners[2]] - points[corners[0]])
			if normal.length_squared() < 1e-12:
				continue
			normal = normal.normalized()
			for k in 3:
				var a: int = corners[k]
				var b: int = corners[(k + 1) % 3]
				var edge := Vector2i(mini(a, b), maxi(a, b))
				if not edge_faces.has(edge):
					edge_faces[edge] = []
				edge_faces[edge].append(normal)

	var min_cos := cos(deg_to_rad(min_angle_degrees))
	var result := PackedVector3Array()
	for edge: Vector2i in edge_faces:
		var normals: Array = edge_faces[edge]
		var is_feature := normals.size() != 2 or (normals[0] as Vector3).dot(normals[1]) < min_cos
		if is_feature:
			result.append(points[edge.x])
			result.append(points[edge.y])
	return result


## A mesh for assets/shaders/edge_outline.gdshader: one quad per edge in [param edges] (pairs of
## points). Each corner keeps its own end as the vertex, the other end in UV and UV2.x, and its
## side of the line (-1 or 1) in UV2.y; the shader widens the quad on screen.
static func build_outline_mesh(edges: PackedVector3Array) -> ArrayMesh:
	return mesh_from_arrays(build_outline_arrays(edges))


## The surface arrays of [method build_outline_mesh]'s mesh; empty without edges. Safe on any
## thread.
static func build_outline_arrays(edges: PackedVector3Array) -> Array:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	for e in range(0, edges.size() - 1, 2):
		var a := edges[e]
		var b := edges[e + 1]
		var base := vertices.size()
		# The corners at the A end point to B, and the other way round. Seen from B the line runs
		# the other way, so B's side -1 lies next to A's side 1: the corners go round the quad.
		for corner: Array in [[a, b, -1.0], [a, b, 1.0], [b, a, -1.0], [b, a, 1.0]]:
			var own: Vector3 = corner[0]
			var other: Vector3 = corner[1]
			vertices.append(own)
			uvs.append(Vector2(other.x, other.y))
			uv2s.append(Vector2(other.z, corner[2]))
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	if vertices.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## The line mesh from [method build_outline_arrays]'s arrays (an empty mesh for none).
static func mesh_from_arrays(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not arrays.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
