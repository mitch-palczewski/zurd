class_name ZurdMovementComponent
extends Node

@export var speed: float = 12.0
@export var turn_speed: float = 4.0 
@export var avoidance_distance: float = 5.0 

func process_movement(actor: CharacterBody3D, target: Node3D, delta: float) -> void:
    if not is_instance_valid(target): 
        _process_without_target(actor, delta)
        return 
    
    var target_pos := target.global_position
    var distance := actor.global_position.distance_to(target_pos)
    var dir_to_target := actor.global_position.direction_to(target_pos)

    var final_dir := _get_avoidance_direction(actor, dir_to_target)

    if not dir_to_target.is_zero_approx():
        var target_basis := Transform3D.IDENTITY.looking_at(final_dir, Vector3.UP).basis
        actor.basis = actor.basis.slerp(target_basis, turn_speed * delta)
    
    var current_speed := speed 
    if distance < 5.0: 
        current_speed = lerpf(2.0, speed, distance / 5.0)
        
    actor.velocity = -actor.basis.z.normalized() * current_speed
    actor.move_and_slide()


func _process_without_target(actor: CharacterBody3D, delta: float) -> void:
    actor.velocity = actor.velocity.move_toward(Vector3.ZERO, speed * delta)
    actor.move_and_slide()


func _get_avoidance_direction(actor: CharacterBody3D, desired_dir: Vector3) -> Vector3:
    var space_state := actor.get_world_3d().direct_space_state
    var forward := -actor.global_basis.z
    var ray_origin := actor.global_position
    var ray_end := ray_origin + (forward * avoidance_distance)

    var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
    query.collision_mask = 1
    query.exclude = [actor.get_rid()]

    var result := space_state.intersect_ray(query)
    if result.is_empty():
        return desired_dir
    
    var collision_normal: Vector3 = result.normal
    var avoided_dir := (desired_dir + collision_normal * 2.0).normalized()

    return avoided_dir