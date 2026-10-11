class_name ZurdMovementComponent
extends Node

@export var speed: float = 12.0
@export var turn_speed: float = 4.0 

func process_movement(actor: CharacterBody3D, target: Node3D, delta: float) -> void:
    if not is_instance_valid(target): 
        _process_without_target(actor, delta)
        return 
    
    var target_pos := target.global_position
    var distance := actor.global_position.distance_to(target_pos)
    var dir_to_target := actor.global_position.direction_to(target_pos)

    if not dir_to_target.is_zero_approx():
        var target_basis := Transform3D.IDENTITY.looking_at(dir_to_target, Vector3.UP).basis
        actor.basis = actor.basis.slerp(target_basis, turn_speed * delta)
    
    var current_speed := speed 
    if distance < 5.0: 
        current_speed = lerpf(2.0, speed, distance / 5.0)
    actor.velocity = -actor.basis.z.normalized() * current_speed
    actor.move_and_slide()


func _process_without_target(actor: CharacterBody3D, delta: float) -> void:
    actor.velocity = actor.velocity.move_toward(Vector3.ZERO, speed * delta)
    actor.move_and_slide()