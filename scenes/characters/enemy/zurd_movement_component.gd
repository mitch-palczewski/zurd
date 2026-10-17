class_name ZurdMovementComponent
extends Node

@export_group("Avoidance")
@export var avoidance_distance: float = 5.0 
@export var avoidance_strength: float = 2.0 
@export_flags_3d_physics var avoid_obstacle_mask: int = 1

@export_group("Hunting Movement")
@export var hunting_speed: float = 18.0
@export var hunting_turn_speed: float = 4.0 

@export_group("Wandering Movement")
@export var wander_speed: float = 3.5
@export var wander_turn_speed: float = 2.5
@export var max_wander_distance: float = 30.0
@export var min_wander_distance: float = 5.0
@export var arrival_distance: float = 1.5
@export var wander_timeout: float = 8.0

@export_group("Bobbing")
@export var visual_root: Node3D
@export var bob_height: float = 0.15
@export var bob_frequency:float = 2.0
@export var sway_degrees: float = 3.0
@export_range(0.0, 1.0) var idle_bob_strength: float = 0.4


@export_group("Roll Leveling")
@export var level_speed: float = 6.0


var _wander_target: Vector3
var _has_wander_target: bool = false
var _wander_timer: float = 0.0 

var _bob_time: float = 0.0
var _visual_base_position: Vector3
var _visual_base_rotation: Vector3


func _ready() -> void:
    if visual_root:
        _visual_base_position = visual_root.position
        _visual_base_rotation = visual_root.rotation

func process_movement(actor: CharacterBody3D, target: Node3D, delta: float) -> void:
    if not is_instance_valid(target): 
        _process_wandering(actor, delta)
    else:
        _process_hunting(actor, target, delta)
    _process_bobbing(actor, delta)



func _process_hunting(actor: CharacterBody3D, target: Node3D, delta: float) -> void:
    _has_wander_target = false
    _wander_timer = 0.0

    var direction := (target.global_position - actor.global_position).normalized()

    _steer_and_move(actor, direction, hunting_speed, hunting_turn_speed, delta)


func _process_wandering(actor: CharacterBody3D, delta: float) -> void:
    _wander_timer += delta

    if (
        not _has_wander_target 
        or _wander_timer >= wander_timeout 
        or actor.global_position.distance_to(_wander_target) <= arrival_distance 
        ): 
            _pick_wander_target(actor)


    var dir := actor.global_position.direction_to(_wander_target)
    _steer_and_move(actor, dir, wander_speed, wander_turn_speed, delta)


func _process_bobbing(actor: CharacterBody3D, delta: float) -> void:
    if not visual_root:
        return 
    
    var move_ratio := clampf(actor.velocity.length() / maxf(wander_speed, 0.01), 0.0, 1.0)
    var strength := lerpf(idle_bob_strength, 1.0, move_ratio)

    _bob_time += delta * bob_frequency 
    var bob := sin(_bob_time * TAU) * bob_height * strength
    var sway := sin(_bob_time * PI) * deg_to_rad(sway_degrees) * strength

    visual_root.position = _visual_base_position + Vector3(0.0, bob, 0.0)
    visual_root.rotation = _visual_base_rotation + Vector3(0.0, 0.0, sway)


func _pick_wander_target(actor: CharacterBody3D) -> void:
    var y := randf_range(-1.0, 1.0)
    var angle := randf_range(0.0, TAU)
    var ring := sqrt(1.0 - y * y)

    var direction := Vector3( cos(angle) * ring, y, sin(angle) * ring)

    var dist := randf_range(min_wander_distance, max_wander_distance)

    _wander_target = actor.global_position + direction * dist
    _has_wander_target = true
    _wander_timer = 0.0


func _steer_and_move(actor: CharacterBody3D, desired_dir: Vector3, move_speed: float, turn_rate: float, delta: float) -> void:
    var final_dir := _get_avoidance_direction(actor, desired_dir)

    _turn_towards(actor, final_dir.normalized(), turn_rate, delta)
    _level_roll(actor, delta)

    var target_velocity = _get_forward_direction(actor) * move_speed 
    var velocity_weight := _get_exp_decay_weight(10.0, delta)
    actor.velocity = actor.velocity.lerp(target_velocity, velocity_weight)
    actor.move_and_slide()


func _turn_towards(actor: Node3D, desired_dir: Vector3, turn_rate: float, delta: float) -> void:
    if desired_dir.is_zero_approx():
        return

    var forward := _get_forward_direction(actor)
    var angle := acos(clampf(forward.dot(desired_dir), -1.0, 1.0))
    if angle < 0.001:
        return
    
    var axis := forward.cross(desired_dir)
    if axis.length_squared() < 0.0001:
        axis = actor.global_basis.y
    axis = axis.normalized()

    var step := angle * clampf(turn_rate * delta, 0.0, 1.0)
    var rotated := Basis(axis, step) * _get_rotation_basis(actor)
    _set_rotation_keep_scale(actor, rotated)


func _level_roll(actor: Node3D, delta:float) -> void:
    var forward := _get_forward_direction(actor)
    var right := forward.cross(Vector3.UP)
    if right.length_squared() < 0.0001:
        return 
    right = right.normalized() 

    var up := right.cross(forward).normalized()
    var level_basis := Basis(right, up, -forward)
    
    var weight := _get_exp_decay_weight(level_speed, delta)
    var leveled := _get_rotation_basis(actor).slerp(level_basis, weight)
    _set_rotation_keep_scale(actor, leveled)


func _get_avoidance_direction(actor: CharacterBody3D, desired_dir: Vector3) -> Vector3:
    var space_state := actor.get_world_3d().direct_space_state
    var forward := _get_forward_direction(actor)
    var ray_origin := actor.global_position
    var scale_factor := actor.global_basis.get_scale().x
    var ray_end := ray_origin + (forward * avoidance_distance * scale_factor)

    var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, avoid_obstacle_mask)
    query.exclude = [actor.get_rid()]

    var result := space_state.intersect_ray(query)
    if result.is_empty():
        return desired_dir
    
    var collision_normal: Vector3 = result.normal
    var avoided_dir := (desired_dir + collision_normal * avoidance_strength).normalized()

    return avoided_dir


func _get_forward_direction(actor: Node3D) -> Vector3:
    return -actor.global_basis.z.normalized()


func _get_exp_decay_weight(speed: float, delta: float) -> float:
    return 1.0 - exp(-speed * delta)


func _get_rotation_basis(actor: Node3D) -> Basis:
    return actor.global_basis.orthonormalized()

func _set_rotation_keep_scale(actor: Node3D, rotation_basis: Basis) -> void:
    var current_scale := actor.global_basis.get_scale()
    actor.global_basis = rotation_basis.orthonormalized() * Basis.from_scale(current_scale)