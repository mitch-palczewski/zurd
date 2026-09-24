@tool
extends EditorScenePostImport

const STATIC_DIR = "res://scenes/objects/static/"
const RIGID_DIR = "res://scenes/objects/rigid/"
const COLLIDER_DIR = "res://scenes/objects/colliders/"
const MESH_DIR = "res://scenes/objects/mesh/"

func _post_import(scene: Node) -> Object:
    var mesh_nodes: Array[MeshInstance3D] = _find_all_mesh_instances(scene)
    if mesh_nodes.is_empty():
        push_warning("Importer: No MeshInstance3D found in " + get_source_file())
        return scene
    
    var item_name: String = get_source_file().get_file().get_basename().validate_filename()

    DirAccess.make_dir_recursive_absolute(STATIC_DIR)
    DirAccess.make_dir_recursive_absolute(RIGID_DIR)
    DirAccess.make_dir_recursive_absolute(COLLIDER_DIR)
    DirAccess.make_dir_recursive_absolute(MESH_DIR)

    var mesh_scene: PackedScene = _make_mesh_scene(item_name, mesh_nodes, scene)
    var collider_scene: PackedScene = _make_collider_scene(item_name, mesh_nodes, scene)

    _make_static_body_3d_scene(item_name, mesh_scene, collider_scene)
    _make_rigid_body_3d_scene(item_name, mesh_scene, collider_scene)

    return scene


func _make_mesh_scene(item_name: String, mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> PackedScene:
    var root_node = Node3D.new()
    root_node.name = item_name.capitalize() + "Mesh"

    for mesh_node in mesh_nodes:
        var clone = mesh_node.duplicate() as MeshInstance3D
        clone.transform = _get_relative_transform(mesh_node, scene_root)
        _enable_vertex_colors(clone)
        root_node.add_child(clone)
        clone.owner = root_node
    
    return _save_packed_scene(root_node, MESH_DIR + item_name + "_mesh.tscn")


func _make_collider_scene(item_name: String, mesh_nodes: Array[MeshInstance3D], scene_root: Node) -> PackedScene:
    var collider_path: String = COLLIDER_DIR + item_name + "_collider.tscn"
    if ResourceLoader.exists(collider_path):
        return load(collider_path)
    return _create_default_box_collider(mesh_nodes, collider_path, scene_root)


func _make_static_body_3d_scene(item_name: String, mesh_scene: PackedScene, collider_scene: PackedScene) -> PackedScene:
    var static_root = StaticBody3D.new()
    static_root.name = item_name.capitalize() + "Static"
    static_root.collision_layer = 1
    static_root.collision_mask = 0
    add_scene(static_root, mesh_scene)
    add_scene(static_root, collider_scene)
    return _save_packed_scene(static_root, STATIC_DIR + item_name + "_static.tscn")


func _make_rigid_body_3d_scene(item_name: String, mesh_scene: PackedScene, collider_scene: PackedScene) -> PackedScene:
    var rigid_root = RigidBody3D.new()
    rigid_root.name = item_name.capitalize() + "Rigid"
    rigid_root.collision_layer = 0
    rigid_root.collision_mask = 0
    rigid_root.set_collision_layer_value(3, true)
    rigid_root.set_collision_mask_value(1, true)
    rigid_root.set_collision_mask_value(2, true)
    rigid_root.set_collision_mask_value(3, true)
    rigid_root.set_collision_mask_value(4, true)
    add_scene(rigid_root, mesh_scene)
    add_scene(rigid_root, collider_scene)
    return _save_packed_scene(rigid_root, RIGID_DIR + item_name + "_rigid.tscn")


func _find_all_mesh_instances(node: Node, result: Array[MeshInstance3D]=[]) -> Array[MeshInstance3D]:
    if node is MeshInstance3D:
        result.append(node)
    for child in node.get_children():
        _find_all_mesh_instances(child, result)
    return result

func _create_default_box_collider(mesh_nodes: Array[MeshInstance3D], path: String, scene_root: Node) -> PackedScene:
    var aabb: AABB = _calculate_combined_aabb(mesh_nodes, scene_root)
    
    var col_root = Node3D.new()
    col_root.name = "Colliders"

    var shape_node = CollisionShape3D.new()
    shape_node.name = "CollisionBox"

    var box = BoxShape3D.new()
    box.size = aabb.size
    shape_node.shape = box
    shape_node.position = aabb.get_center()

    col_root.add_child(shape_node)
    shape_node.owner = col_root

    return _save_packed_scene(col_root, path)


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


func _get_relative_transform(node:Node3D, root: Node) -> Transform3D:
    var trans = Transform3D.IDENTITY
    var current: Node = node
    while current and current != root and current is Node3D:
        trans = (current as Node3D).transform * trans
        current = current.get_parent()
    return trans


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


func add_scene(parent_node: Node, scene: PackedScene) -> void:
    var scene_instance = scene.instantiate()
    parent_node.add_child(scene_instance)
    scene_instance.owner = parent_node
    return


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
