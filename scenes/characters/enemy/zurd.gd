class_name Zurd
extends CharacterBody3D

## Base Zurd class managing movement, target acquisition, and eating mechanics.
## The wonderous gluttony of the evil zurd.

@export_group("Base Movement")
@export var speed: float = 12.0 
@export var turn_speed: float = 4.0
@export var eating_distance: float = 2.5 

@export_group("References")
@export var mouth_area: Area3D 

var target_object: RigidBody3D = null

func _ready() -> void:
    _setup_mouth_area()


func _physics_process(delta: float) -> void:
    _update_target_acquisition()
    _process_movement(delta)

# ==============================================================================
# TARGET ACQUISITION
# ==============================================================================

func _acquire_target() -> RigidBody3D:
    # or ObjectTracker.get_random_object()
    return ObjectTracker.get_closest_object(global_position)


func _update_target_acquisition() -> void:
    if not is_instance_valid(target_object):
        target_object = _acquire_target()
        if target_object:
            _apply_collision_excepetion(target_object, true)

# ==============================================================================
# MOVEMENT
# ==============================================================================

func _process_movement(delta: float) -> void:
    if not is_instance_valid(target_object):
        velocity = velocity.move_toward(Vector3.ZERO, speed * delta)
        move_and_slide()
        return 
    
    var target_pos := target_object.global_position
    var distance := global_position.distance_to(target_pos)
    var dir_to_target := global_position.direction_to(target_pos)

    if not dir_to_target.is_zero_approx():
        var target_basis := Transform3D.IDENTITY.looking_at(dir_to_target, Vector3.UP).basis
        basis = basis.slerp(target_basis, turn_speed * delta)
    
    var current_speed := speed
    if distance < 5.0:
        current_speed = lerpf(2.0, speed, distance / 5.0)

    velocity = -basis.z.normalized() * current_speed
    move_and_slide()

# ==============================================================================
# EATING
# ==============================================================================

func _setup_mouth_area() -> void:
    if not mouth_area:
        mouth_area = get_node_or_null("MouthArea")
    if mouth_area:
        mouth_area.body_entered.connect(_on_mouth_area_body_entered)


func _on_mouth_area_body_entered(body: Node) -> void:
    if body == target_object and body is RigidBody3D:
        _eat_object(body as RigidBody3D)


func _eat_object(obj: RigidBody3D) -> void:
    _apply_collision_excepetion(obj, false)
    _on_object_eaten(obj)
    obj.queue_free()
    target_object = null


func _apply_collision_excepetion(obj: RigidBody3D, ignore: bool) -> void:
    if not is_instance_valid(obj):
        return 
    
    if ignore:
        add_collision_exception_with(obj)
    else: 
        remove_collision_exception_with(obj)


## Virtual hook for subclasses when an object is swallowed 
func _on_object_eaten(_obj:RigidBody3D) -> void:
    pass