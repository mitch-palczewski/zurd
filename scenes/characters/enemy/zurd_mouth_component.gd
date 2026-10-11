class_name ZurdMouthComponent
extends Area3D

signal object_eaten(obj: RigidBody3D)

var active_target: RigidBody3D = null 
@export var owner_body: CharacterBody3D

func _ready() -> void:
    body_entered.connect(_on_body_entered)
    if not owner_body:
        owner_body = get_parent() as CharacterBody3D


func set_target(obj: RigidBody3D) -> void:
    if is_instance_valid(active_target) and active_target != obj:
        _set_collision_exception(active_target, false)

    active_target = obj 
    if is_instance_valid(active_target):
        _set_collision_exception(active_target, true)  


func _on_body_entered(body: Node) -> void:
    if body == active_target and body is RigidBody3D:
        _eat_object(body as RigidBody3D)


func _eat_object(obj: RigidBody3D) -> void:
    _set_collision_exception(obj, false)
    object_eaten.emit(obj)
    EventBus.object_eaten.emit(owner_body, obj)
    obj.queue_free()
    active_target = null


func _set_collision_exception(obj: RigidBody3D, ignore: bool) -> void:
    if not is_instance_valid(obj) or not owner_body:
        return
    if ignore:
        owner_body.add_collision_exception_with(obj)
    else: 
        owner_body.remove_collision_exception_with(obj)