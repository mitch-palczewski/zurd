@tool
extends EditorScenePostImport
 
const STATIC_MATERIAL_PATH = "res://assets/materials/golf_terrain.tres"
const MATERIAL_DIR = "res://assets/materials/objects/"
const MESH_DIR = "res://assets/meshes/"
 
const STATIC_DIR = "res://scenes/objects/static/"
const RIGID_DIR = "res://scenes/objects/rigid/"
 
 
func _post_import(scene: Node) -> Object:
    var mesh_nodes: Array[MeshInstance3D] = _find_all_mesh_instances(scene)
    if mesh_nodes.is_empty():
        push_warning("Importer: No MeshInstance3D found in " + get_source_file())
        return scene
 
    var item_name: String = get_source_file().get_file().get_basename().validate_filename()
 
    DirAccess.make_dir_recursive_absolute(STATIC_DIR)
    DirAccess.make_dir_recursive_absolute(RIGID_DIR)
    DirAccess.make_dir_recursive_absolute(MATERIAL_DIR)
    DirAccess.make_dir_recursive_absolute(MESH_DIR)
 
    var shared_meshes: Dictionary = _export_shared_meshes(item_name, mesh_nodes)
 
    _make_static_body_3d_scene(item_name, mesh_nodes, scene, shared_meshes)
    _make_rigid_body_3d_scene(item_name, mesh_nodes, scene, shared_meshes)
 
    return scene
 
 
# ==============================================================================
# SCENE GENERATION
# ==============================================================================
func _make_static_body_3d_scene(item_name: String, mesh_nodes: Array[MeshInstance3D], scene_root: Node, shared_meshes: Dictionary) -> void:
    var static_root := StaticBody3D.new()
    static_root.name = item_name.to_pascal_case() + "Static"
 
    static_root.collision_layer = 1
    static_root.collision_mask = 0
 
    _add_visuals(item_name, static_root, mesh_nodes, scene_root, shared_meshes)
    _apply_material_to_instance(static_root, STATIC_MATERIAL_PATH)
    _attach_convex_colliders(static_root, mesh_nodes, scene_root)
 
    _save_packed_scene(static_root, STATIC_DIR + item_name + "_static.tscn")
 
 
func _make_rigid_body_3d_scene(item_name: String, mesh_nodes: Array[MeshInstance3D], scene_root: Node, shared_meshes: Dictionary) -> void:
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
    _setup_vertex_color_materials(rigid_root, item_name)
    _attach_primitive_box_collider(rigid_root, mesh_nodes, scene_root)
 
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
 
func _apply_material_to_instance(parent_node: Node3D, mat_path: String) -> void:
    if not ResourceLoader.exists(mat_path):
        push_warning("Importer: Terrain material not found at '" + mat_path + "'")
        return
 
    var mat := load(mat_path) as Material
    if not mat:
        push_error("Importer: Failed to load material resource at '" + mat_path + "'")
        return
 
    for mesh_instance in _find_all_mesh_instances(parent_node):
        if mesh_instance.mesh:
            for i in mesh_instance.mesh.get_surface_count():
                mesh_instance.set_surface_override_material(i, mat)
 
 
func _setup_vertex_color_materials(parent_node: Node3D, item_name: String) -> void:
    var saved_materials := {} 
    var mesh_instances := _find_all_mesh_instances(parent_node)
    for mesh_instance in mesh_instances:
        var mesh := mesh_instance.mesh
        if mesh == null:
            continue

        var surface_count = mesh.get_surface_count()

        for i in surface_count:
            if not _surface_has_colors(mesh, i):
                continue
 
            var source := mesh_instance.get_active_material(i)
            if not saved_materials.has(source):
                var path =  ""
                if mesh_instances.size() == 1 and surface_count == 1:
                    path = "%s%s_mat.res" % [MATERIAL_DIR, item_name]
                else:
                    path = "%s%s_mat_%d.res" % [MATERIAL_DIR, item_name, saved_materials.size()]
                saved_materials[source] = _save_vertex_color_material(source, path)

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
 
func _attach_primitive_box_collider(parent_node: Node3D, mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> void:
    var aabb: AABB = _calculate_combined_aabb(mesh_nodes, scene_root)
 
    var shape_node := CollisionShape3D.new()
    shape_node.name = "CollisionBox"
 
    var box := BoxShape3D.new()
    box.size = aabb.size
    shape_node.shape = box
    shape_node.position = aabb.get_center()
 
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
 
 
func _calculate_combined_aabb(mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> AABB:
    var combined := AABB()
    var has_aabb := false
    for mesh_node in mesh_nodes:
        if not mesh_node.mesh:
            continue
        var local_aabb := mesh_node.mesh.get_aabb()
        var rel_transform := _get_relative_transform(mesh_node, scene_root)
        var xformed_aabb := rel_transform * local_aabb
 
        if not has_aabb:
            combined = xformed_aabb
            has_aabb = true
        else:
            combined = combined.merge(xformed_aabb)
    return combined
 
 
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
 
