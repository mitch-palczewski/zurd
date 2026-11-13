@tool
class_name ReflectingPool
extends Node3D

## A reflecting pool: mirror water (see PlanarReflection) in a checkerboard basin with an outline
## along its edges. Builds the outline from the basin's mesh when it loads (in the editor too), and
## in the game gives the basin a collider that follows its shape exactly (a trimesh, so the
## hollow stays hollow; a convex hull would fill it up to the rim). Both are rebuilt from the mesh,
## so a re-export from Blender needs no changes here.

const OUTLINE_SHADER := preload("res://assets/shaders/edge_outline.gdshader")

## The basin's mesh: gets the outline and the collider.
@export var basin_mesh: MeshInstance3D
## Edges where the faces meet at a sharper angle than this (in degrees) get the outline. Open
## edges always do.
@export_range(1.0, 90.0, 1.0) var outline_angle: float = 20.0
@export var outline_color: Color = Color(0.55, 0.18, 0.85):
	set(value):
		outline_color = value
		if _outline_material:
			_outline_material.set_shader_parameter("outline_color", value)
## Outline width in pixels.
@export_range(0.5, 20.0, 0.5) var outline_width: float = 3.0:
	set(value):
		outline_width = value
		if _outline_material:
			_outline_material.set_shader_parameter("width", value)

var _outline_material: ShaderMaterial


## The model's feature edges, as pairs of points (start, end, start, end, ...): edges that only one
## face uses, and edges where two faces meet at more than [param min_angle_degrees]. Points closer
## than a tenth of a millimetre count as one, so flat-shaded meshes (split vertices) work too.
static func find_feature_edges(mesh: Mesh, min_angle_degrees: float) -> PackedVector3Array:
	var points: Array[Vector3] = []
	var point_ids := {}
	# { Vector2i(lower id, higher id): Array of face normals }
	var edge_faces := {}
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			indices.resize(vertices.size())
			for i in vertices.size():
				indices[i] = i
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

	var mesh := ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _ready() -> void:
	if basin_mesh == null or basin_mesh.mesh == null:
		push_warning("ReflectingPool: no basin_mesh set on " + str(get_path()))
		return
	_add_outline()
	if not Engine.is_editor_hint():
		_add_collider()


func _add_outline() -> void:
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_parameter("outline_color", outline_color)
	_outline_material.set_shader_parameter("width", outline_width)

	var outline := MeshInstance3D.new()
	outline.name = "Outline"
	outline.mesh = build_outline_mesh(find_feature_edges(basin_mesh.mesh, outline_angle))
	outline.material_override = _outline_material
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The lines are widened on screen, past the edges' own box.
	outline.extra_cull_margin = 1.0
	outline.layers = basin_mesh.layers
	# Not owned: built on load, never saved into the scene.
	basin_mesh.add_child(outline)


func _add_collider() -> void:
	var body := StaticBody3D.new()
	body.name = "BasinBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = basin_mesh.mesh.create_trimesh_shape()
	body.add_child(shape)
	basin_mesh.add_child(body)
