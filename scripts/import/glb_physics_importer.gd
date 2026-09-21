@tool
extends EditorScenePostImport

const STATIC_DIR = "res://scenes/objects/static/"
const RIGID_DIR = "res://scenes/objects/rigid/"
const COLLIDER_DIR = "res://scenes/objects/colliders/"
const MESH_DIR = "res://scenes/objects/mesh/"

func _post_import(scene: Node) -> Object:
    var mesh_node = _find_mesh_instance(scene)
    if not mesh_node:
        push_warning("Importer: No MeshInstance3D found in " + get_source_file())
        return scene
    
    var item_name: String = get_source_file().get_file().get_basename().validate_filename()

    DirAccess.make_dir_recursive_absolute(STATIC_DIR)
    DirAccess.make_dir_recursive_absolute(RIGID_DIR)
    DirAccess.make_dir_recursive_absolute(COLLIDER_DIR)
    DirAccess.make_dir_recursive_absolute(MESH_DIR)

    var mesh_scene: PackedScene = _make_mesh_scene(item_name, mesh_node)
    var collider_scene: PackedScene = _make_collider_scene(item_name, mesh_node)

    _make_static_body_3d_scene(item_name, mesh_scene, collider_scene)
    _make_rigid_body_3d_scene(item_name, mesh_scene, collider_scene)

    return scene


func _make_mesh_scene(item_name: String, mesh_node: MeshInstance3D) -> PackedScene:
    var mesh_clone = mesh_node.duplicate() as MeshInstance3D
    mesh_clone.name = item_name.capitalize() + "Mesh"

    _enable_vertex_colors(mesh_clone)
    
    return _save_packed_scene(mesh_clone, MESH_DIR + item_name + "_mesh.tscn")


func _make_collider_scene(item_name: String, mesh_node: MeshInstance3D) -> PackedScene:
    var collider_path: String = COLLIDER_DIR + item_name + "_collider.tscn"
    if ResourceLoader.exists(collider_path):
        return load(collider_path)
    return _create_default_box_collider(mesh_node, collider_path)


func _make_static_body_3d_scene(item_name: String, mesh_scene: PackedScene, collider_scene: PackedScene) -> PackedScene:
    var static_root = StaticBody3D.new()
    static_root.name = item_name.capitalize() + "Static"
    add_scene(static_root, mesh_scene)
    add_scene(static_root, collider_scene)
    return _save_packed_scene(static_root, STATIC_DIR + item_name + "_static.tscn")


func _make_rigid_body_3d_scene(item_name: String, mesh_scene: PackedScene, collider_scene: PackedScene) -> PackedScene:
    var rigid_root = RigidBody3D.new()
    rigid_root.name = item_name.capitalize() + "Rigid"
    add_scene(rigid_root, mesh_scene)
    add_scene(rigid_root, collider_scene)
    return _save_packed_scene(rigid_root, RIGID_DIR + item_name + "_rigid.tscn")

func _find_mesh_instance(node: Node) -> MeshInstance3D:
    if node is MeshInstance3D:
        return node
    for child in node.get_children():
        var found = _find_mesh_instance(child)
        if found:
            return found
    return null

func _create_default_box_collider(mesh_node: MeshInstance3D, path: String) -> PackedScene:
    var aabb = mesh_node.mesh.get_aabb()
    
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
    packed.pack(root_node)
    var error = ResourceSaver.save(packed, save_path)
    if error != OK:
        push_error("Failed to save scene to: " + save_path + " (Error code:  " + str(error) + ")")
    return packed
