##Toroidal variant of BaseWorld. Wraps object positions across world boundaries.
class_name ToroidalWorld
extends BaseWorld

## Half-extents for X and Z axes. 
## Vector2(100, 100) = 200x200 total play region centered at (0,0).
@export var bounds_xz: Vector2 = Vector2(100.0, 100.0)

func _physics_process(_delta: float) -> void:
    _wrap_dynamic_objects()

func _wrap_dynamic_objects() -> void:
    if not object_container:
        return 
    
    for child in object_container.get_children():
        if child is RigidBody3D or child is CharacterBody3D:
            _process_node_wrapping(child)


func _process_node_wrapping(node: Node3D) -> void:
    if not ToroidalUtils.is_out_of_bounds_xz(node.global_position, bounds_xz):
        return
    var new_position: Vector3 = ToroidalUtils.wrap_position_xz(node.global_position, bounds_xz)

    if node is RigidBody3D: 
        var node_transform: Transform3D = node.global_transform
        node_transform.origin = new_position
        node.global_transform = node_transform
    else: 
        node.global_position = new_position
