@tool
extends EditorScenePostImport

## Turns each model under assets/models/ into shared mesh and material files, plus the scenes its
## folder opts it into:
## - assets/models/objects/: a rigid scene in scenes/objects/rigid/, for objects the ship launches.
## - assets/models/scenery/: a static scene in scenes/objects/static/, for fixed scenery.
## - any other folder under assets/models/ (such as characters/): only the mesh and material files.
## Models straight in assets/models/ get a warning and no scenes. Files outside assets/models/ are
## left alone. This script is the project's default for scene imports (Project Settings → Import
## Defaults → Scene), so a new model needs no setup.

const MODELS_DIR = "res://assets/models/"
const OBJECT_MODELS_DIR = MODELS_DIR + "objects/"
const SCENERY_MODELS_DIR = MODELS_DIR + "scenery/"

const MATERIAL_DIR = "res://assets/materials/objects/"
const MESH_DIR = "res://assets/meshes/"

const STATIC_DIR = "res://scenes/objects/static/"
const RIGID_DIR = "res://scenes/objects/rigid/"


func _post_import(scene: Node) -> Object:
	var source := get_source_file()
	if not source.begins_with(MODELS_DIR):
		return scene

	var mesh_nodes: Array[MeshInstance3D] = _find_all_mesh_instances(scene)
	if mesh_nodes.is_empty():
		push_warning("Importer: No MeshInstance3D found in " + source)
		return scene

	if source.get_base_dir() + "/" == MODELS_DIR:
		push_warning("Importer: %s makes no scenes. Move it into objects/ (launched objects) or scenery/ (fixed scenery), or into another folder such as characters/ for the mesh and material only." % source)

	var item_name: String = source.get_file().get_basename().validate_filename()

	DirAccess.make_dir_recursive_absolute(MATERIAL_DIR)
	DirAccess.make_dir_recursive_absolute(MESH_DIR)

	var shared_meshes: Dictionary = _export_shared_meshes(item_name, mesh_nodes)
	var shared_materials: Dictionary = _export_vertex_color_materials(item_name, mesh_nodes, shared_meshes)

	if source.begins_with(SCENERY_MODELS_DIR):
		DirAccess.make_dir_recursive_absolute(STATIC_DIR)
		_make_static_body_3d_scene(item_name, mesh_nodes, scene, shared_meshes, shared_materials)
	if source.begins_with(OBJECT_MODELS_DIR):
		DirAccess.make_dir_recursive_absolute(RIGID_DIR)
		_make_rigid_body_3d_scene(item_name, mesh_nodes, scene, shared_meshes, shared_materials)

	return scene


# ==============================================================================
# SCENE GENERATION
# ==============================================================================
func _make_static_body_3d_scene(item_name: String, mesh_nodes: Array[MeshInstance3D], scene_root: Node, shared_meshes: Dictionary, shared_materials: Dictionary) -> void:
	var static_root := StaticBody3D.new()
	static_root.name = item_name.to_pascal_case() + "Static"

	static_root.collision_layer = 1
	static_root.collision_mask = 0

	_add_visuals(item_name, static_root, mesh_nodes, scene_root, shared_meshes)
	_apply_vertex_color_materials(static_root, shared_materials)
	_attach_convex_colliders(static_root, mesh_nodes, scene_root)

	_save_packed_scene(static_root, STATIC_DIR + item_name + "_static.tscn")


func _make_rigid_body_3d_scene(item_name: String, mesh_nodes: Array[MeshInstance3D], scene_root: Node, shared_meshes: Dictionary, shared_materials: Dictionary) -> void:
	var rigid_root := RigidBody3D.new()
	rigid_root.name = item_name.to_pascal_case() + "Rigid"

	rigid_root.collision_layer = 0
	rigid_root.collision_mask = 0
	rigid_root.set_collision_layer_value(3, true)
	rigid_root.set_collision_mask_value(1, true)
	rigid_root.set_collision_mask_value(2, true)
	rigid_root.set_collision_mask_value(3, true)
	rigid_root.set_collision_mask_value(4, true)

	_add_visuals(item_name, rigid_root, mesh_nodes, scene_root, shared_meshes)
	_apply_vertex_color_materials(rigid_root, shared_materials)
	_attach_convex_hull_collider(rigid_root, mesh_nodes, scene_root)

	_save_packed_scene(rigid_root, RIGID_DIR + item_name + "_rigid.tscn")


# ==============================================================================
# MESH EXPORT & VISUALS
# ==============================================================================

## Saves every unique mesh as <item>_<n>.res and returns { source Mesh: external Mesh }.
func _export_shared_meshes(item_name: String, mesh_nodes: Array[MeshInstance3D]) -> Dictionary:
	var exported := {}
	var index := 0

	var mesh_count = mesh_nodes.size()
	var mesh_dir = MESH_DIR

	if mesh_count > 1:
		mesh_dir = MESH_DIR + item_name + "/"
		DirAccess.make_dir_recursive_absolute(mesh_dir)

	for mesh_node in mesh_nodes:
		var source := mesh_node.mesh
		if source == null or exported.has(source):
			continue

		var path: String = ""
		if mesh_nodes.size() == 1:
			path = "%s%s.res" % [mesh_dir, item_name]
		else:
			path = "%s%s_%d.res" % [mesh_dir, item_name, index]
		index += 1

		var err := ResourceSaver.save(source, path)
		if err != OK:
			push_error("Importer: Failed to save mesh '%s' (error %d)" % [path, err])
			continue

		exported[source] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as Mesh

	return exported


func _add_visuals(item_name: String, parent_node: Node3D, mesh_nodes: Array[MeshInstance3D], scene_root: Node, shared_meshes: Dictionary) -> void:
	var visuals := Node3D.new()
	visuals.name = item_name
	parent_node.add_child(visuals)
	visuals.owner = parent_node

	for mesh_node in mesh_nodes:
		var shared_mesh: Mesh = shared_meshes.get(mesh_node.mesh)
		if shared_mesh == null:
			continue

		var instance := MeshInstance3D.new()
		instance.name = mesh_node.name
		instance.mesh = shared_mesh
		instance.transform = _get_relative_transform(mesh_node, scene_root)

		visuals.add_child(instance, true)
		instance.owner = parent_node


# ==============================================================================
# MATERIAL HELPERS
# ==============================================================================

## Saves a vertex-colour copy of the material of every coloured surface, once per model, and returns
## { source Material: saved Material }. Both scene versions use them, so a model looks the same
## launched or placed as scenery.
func _export_vertex_color_materials(item_name: String, mesh_nodes: Array[MeshInstance3D], shared_meshes: Dictionary) -> Dictionary:
	var used_nodes: Array[MeshInstance3D] = []
	for mesh_node in mesh_nodes:
		if shared_meshes.has(mesh_node.mesh):
			used_nodes.append(mesh_node)

	var saved_materials := {}
	for mesh_node in used_nodes:
		var mesh: Mesh = shared_meshes[mesh_node.mesh]
		var surface_count := mesh.get_surface_count()

		for i in surface_count:
			if not _surface_has_colors(mesh, i):
				continue

			var source := mesh.surface_get_material(i)
			if saved_materials.has(source):
				continue
			var path := ""
			if used_nodes.size() == 1 and surface_count == 1:
				path = "%s%s_mat.res" % [MATERIAL_DIR, item_name]
			else:
				path = "%s%s_mat_%d.res" % [MATERIAL_DIR, item_name, saved_materials.size()]
			saved_materials[source] = _save_vertex_color_material(source, path)

	return saved_materials


## Puts the saved vertex-colour materials on the coloured surfaces of [param parent_node]'s meshes.
func _apply_vertex_color_materials(parent_node: Node3D, saved_materials: Dictionary) -> void:
	for mesh_instance in _find_all_mesh_instances(parent_node):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue

		for i in mesh.get_surface_count():
			var source := mesh.surface_get_material(i)
			if _surface_has_colors(mesh, i) and saved_materials.has(source):
				mesh_instance.set_surface_override_material(i, saved_materials[source])


func _surface_has_colors(mesh: Mesh, surface: int) -> bool:
	if mesh is ArrayMesh:
		var format: int = (mesh as ArrayMesh).surface_get_format(surface)
		return (format & Mesh.ARRAY_FORMAT_COLOR) != 0

	var arrays: Array = mesh.surface_get_arrays(surface)
	return arrays.size() > Mesh.ARRAY_COLOR and arrays[Mesh.ARRAY_COLOR] != null


func _save_vertex_color_material(source: Material, path: String) -> Material:
	var mat: BaseMaterial3D
	if source is BaseMaterial3D:
		mat = source.duplicate() as BaseMaterial3D
	else:
		mat = StandardMaterial3D.new()

	mat.vertex_color_use_as_albedo = true
	mat.take_over_path(path)

	var err := ResourceSaver.save(mat, path)
	if err != OK:
		push_error("Importer: Failed to save material '%s' (error %d)" % [path, err])

	return mat


# ==============================================================================
# COLLIDER ATTACHMENT HELPERS
# ==============================================================================

## One convex hull around the whole model: the exact hull of every vertex, not simplified, so it
## hugs the mesh (simplifying made thin objects up to 45% thicker; Jolt reduces a hull with more
## than 256 points itself). The mesh transforms are baked into the points, and the node sits at the
## middle of the hull at scale 1, where the old box sat. The sculpture-mass code relies on that
## layout: [method ObjectParts.of] reads an object's size from its first collision shape's scale,
## the launcher rescales that node, [method MassPiece.get_center] averages shape positions, and
## growth break-off measures the hull by its bounding box ([method MassPiece.get_boxes]).
func _attach_convex_hull_collider(parent_node: Node3D, mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> void:
	var vertices := PackedVector3Array()
	for mesh_node in mesh_nodes:
		if mesh_node.mesh:
			vertices.append_array(_get_relative_transform(mesh_node, scene_root) * mesh_node.mesh.get_faces())
	if vertices.is_empty():
		push_warning("Importer: No vertices for a collision hull in " + get_source_file())
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var combined := ArrayMesh.new()
	combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var hull := combined.create_convex_shape(true, false)

	var bounds := AABB(hull.points[0], Vector3.ZERO)
	for point in hull.points:
		bounds = bounds.expand(point)
	var center := bounds.get_center()
	var centered := PackedVector3Array()
	for point in hull.points:
		centered.append(point - center)
	hull.points = centered

	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionConvex"
	shape_node.shape = hull
	shape_node.position = center

	parent_node.add_child(shape_node)
	shape_node.owner = parent_node


func _attach_convex_colliders(parent_node: Node3D, mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> void:
	for i in mesh_nodes.size():
		var mesh_node := mesh_nodes[i]
		if not mesh_node.mesh:
			continue

		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionConvex" if mesh_nodes.size() == 1 else "CollisionConvex_" + str(i + 1)

		shape_node.shape = mesh_node.mesh.create_convex_shape(true, true)
		shape_node.transform = _get_relative_transform(mesh_node, scene_root)

		parent_node.add_child(shape_node)
		shape_node.owner = parent_node


# ==============================================================================
# UTILITY & MATH HELPERS
# ==============================================================================

func _find_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_mesh_instances(node, result)
	return result


func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, result)


func _get_relative_transform(node: Node3D, root: Node) -> Transform3D:
	var trans := Transform3D.IDENTITY
	var current: Node = node
	while current and current != root and current is Node3D:
		trans = (current as Node3D).transform * trans
		current = current.get_parent()
	return trans


func _save_packed_scene(root_node: Node, save_path: String) -> Error:
	var packed := PackedScene.new()
	var err := packed.pack(root_node)
	if err == OK:
		err = ResourceSaver.save(packed, save_path)
	if err != OK:
		push_error("Importer: Failed to save scene '%s' (error %d)" % [save_path, err])

	root_node.free()
	return err
