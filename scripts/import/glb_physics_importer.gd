@tool
extends EditorScenePostImport

const STATIC_MATERIAL_PATH = "res://assets/materials/golf_terrain.tres"

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

    _make_static_body_3d_scene(item_name, mesh_nodes, scene)
    _make_rigid_body_3d_scene(item_name, mesh_nodes, scene)

    return scene


# ==============================================================================
# SCENE GENERATION
# ==============================================================================
func _make_static_body_3d_scene(item_name: String, mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> PackedScene:
    var static_root = StaticBody3D.new()
    static_root.name = item_name.capitalize() + "Static"

    static_root.collision_layer = 1
    static_root.collision_mask = 0

    _attach_static_mesh_clones(static_root, mesh_nodes, scene_root)
    _attach_convex_colliders(static_root, mesh_nodes, scene_root)

    return _save_packed_scene(static_root, STATIC_DIR + item_name + "_static.tscn")


func _make_rigid_body_3d_scene(item_name: String, mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> PackedScene:
    var rigid_root = RigidBody3D.new()
    rigid_root.name = item_name.capitalize() + "Rigid"

    rigid_root.collision_layer = 0
    rigid_root.collision_mask = 0
    rigid_root.set_collision_layer_value(3, true)
    rigid_root.set_collision_mask_value(1, true)
    rigid_root.set_collision_mask_value(2, true)
    rigid_root.set_collision_mask_value(3, true)
    rigid_root.set_collision_mask_value(4, true)

    _attach_mesh_clones(rigid_root, mesh_nodes, scene_root)
    _attach_primitive_box_collider(rigid_root, mesh_nodes, scene_root)

    return _save_packed_scene(rigid_root, RIGID_DIR + item_name + "_rigid.tscn")


# ==============================================================================
# MESH & COLLIDER ATTACHMENT HELPERS
# ==============================================================================
func _attach_mesh_clones(parent_node: Node3D, mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> void:
    for mesh_node in mesh_nodes:
        var clone = mesh_node.duplicate() as MeshInstance3D
        clone.transform = _get_relative_transform(mesh_node, scene_root)
        _enable_vertex_colors(clone)

        parent_node.add_child(clone)
        clone.owner = parent_node


func _attach_static_mesh_clones(parent_node: Node3D, mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> void:
    for mesh_node in mesh_nodes:
        var clone = mesh_node.duplicate() as MeshInstance3D
        clone.transform = _get_relative_transform(mesh_node, scene_root)
        _apply_custom_material(clone, STATIC_MATERIAL_PATH)

        parent_node.add_child(clone)
        clone.owner = parent_node


func _attach_primitive_box_collider(parent_node: Node3D, mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> void:
    var aabb: AABB = _calculate_combined_aabb(mesh_nodes, scene_root)

    var shape_node = CollisionShape3D.new()
    shape_node.name = "CollisionBox"

    var box = BoxShape3D.new()
    box.size = aabb.size
    shape_node.shape = box
    shape_node.position = aabb.get_center()

    parent_node.add_child(shape_node)
    shape_node.owner = parent_node


func _attach_convex_colliders(parent_node: Node3D, mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> void:
    for i in mesh_nodes.size():
        var mesh_node = mesh_nodes[i]
        if not mesh_node.mesh:
            continue
        
        var shape_node = CollisionShape3D.new()
        shape_node.name = "CollisionConvex" if mesh_nodes.size() == 1 else "CollisionConvex_" + str(i + 1)

        var convex_shape = mesh_node.mesh.create_convex_shape(true, true)
        shape_node.shape = convex_shape
        shape_node.transform = _get_relative_transform(mesh_node, scene_root)

        parent_node.add_child(shape_node)
        shape_node.owner = parent_node


# ==============================================================================
# UTILITY & MATH HELPERS
# ==============================================================================
func _apply_custom_material(mesh_node: MeshInstance3D, mat_path: String) -> void:
    if not mesh_node or not mesh_node.mesh:
        return
    
    if not ResourceLoader.exists(mat_path):
        push_warning("Importer: Custom material not found at '" + mat_path + "'. Falling back tto vertex color material. ")
        _enable_vertex_colors(mesh_node)
        return 
    
    var custom_mat = load(mat_path) as Material
    if not custom_mat:
        push_error("Importer: Failed to load material at '" + mat_path + "'")
        return 
    
    for i in mesh_node.mesh.get_surface_count():
        mesh_node.set_surface_override_material(i, custom_mat)


func _enable_vertex_colors(mesh_node: MeshInstance3D) -> void:
    if not mesh_node or not mesh_node.mesh:
        return
    for i in mesh_node.mesh.get_surface_count():
        var active_mat = mesh_node.get_active_material(i)

        if active_mat is BaseMaterial3D:
            var mat = active_mat.duplicate() as BaseMaterial3D
            mat.vertex_color_use_as_albedo = true
            mesh_node.set_surface_override_material(i, mat)
        else:
            var mat = StandardMaterial3D.new()
            mat.vertex_color_use_as_albedo = true
            mesh_node.set_surface_override_material(i, mat)


func _find_all_mesh_instances(node: Node, result: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
    if node is MeshInstance3D:
        result.append(node)
    for child in node.get_children():
        _find_all_mesh_instances(child, result)
    return result


func _calculate_combined_aabb(mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> AABB:
    var combined = AABB()
    var has_aabb = false
    for mesh_node in mesh_nodes:
        if not mesh_node.mesh:
            continue
        var local_aabb = mesh_node.mesh.get_aabb()
        var rel_transform = _get_relative_transform(mesh_node, scene_root)
        var xformed_aabb = rel_transform * local_aabb

        if not has_aabb:
            combined = xformed_aabb
            has_aabb = true
        else:
            combined = combined.merge(xformed_aabb)
    return combined


func _get_relative_transform(node: Node3D, root: Node) -> Transform3D:
    var trans = Transform3D.IDENTITY
    var current: Node = node
    while current and current != root and current is Node3D:
        trans = (current as Node3D).transform * trans
        current = current.get_parent()
    return trans


func _save_packed_scene(root_node: Node, save_path: String) -> PackedScene:
    var packed = PackedScene.new()
    var packed_err = packed.pack(root_node)
    if packed_err != OK:
        push_error("Failed to pack scene for: " + save_path + " (Error code: " + str(packed_err) + ")")
        root_node.free()
        return null
    
    var save_err = ResourceSaver.save(packed, save_path)
    if save_err != OK:
        push_error("Failed to save scene to: " + save_path + " (Error code:  " + str(save_err) + ")")
        root_node.free()
        return null
    
    root_node.free()

    return load(save_path) as PackedScene
