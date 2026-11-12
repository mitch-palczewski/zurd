class_name ZurdMovementComponent
extends Node

## Moves a Zurd (Zurd Core Design Doc §5, §6): wandering around its home, hunting a target, holding
## its mouth on what it eats, hovering while it nibbles, the knock-back of a stun, and retreating
## from the ship. It steers around the environment and knocks around the objects it bumps into.

@export_group("Avoidance")
@export var avoidance_distance: float = 5.0
@export var avoidance_strength: float = 2.0
@export_flags_3d_physics var avoid_obstacle_mask: int = 1

@export_group("Hunting Movement")
@export var hunting_speed: float = 30.0
@export var hunting_turn_speed: float = 4.0
## Within this distance of its target a hunting Zurd slows down, so it can turn onto the target
## instead of circling it (at full speed its turning circle is several metres wide).
@export var arrival_radius: float = 20.0
## The slowest a hunting Zurd goes, as a share of its speed: right at its target, or while the
## target is well off to the side.
@export_range(0.0, 1.0) var min_arrival_speed: float = 0.2

@export_group("Wandering Movement")
@export var wander_speed: float = 10.0
@export var wander_turn_speed: float = 2.5
@export var max_wander_distance: float = 30.0
@export var min_wander_distance: float = 5.0
@export var arrival_distance: float = 1.5
@export var wander_timeout: float = 8.0
## How much of a wander leg may go up or down (0 = level only, 1 = any direction).
@export_range(0.0, 1.0) var wander_vertical: float = 0.4

@export_group("Retreat")
## Speed of a Zurd flying away after being driven off.
@export var retreat_speed: float = 40.0

@export_group("Stun")
## How fast the knock-back of a stun eases to a stop.
@export var stun_slowdown: float = 2.0

@export_group("Bobbing")
@export var visual_root: Node3D
@export var bob_height: float = 0.15
@export var bob_frequency: float = 2.0
@export var sway_degrees: float = 3.0
@export_range(0.0, 1.0) var idle_bob_strength: float = 0.4

@export_group("Roll Leveling")
@export var level_speed: float = 6.0

@export_group("Eating")
## How hard the Zurd pulls its mouth back onto the target while eating it.
@export var hold_strength: float = 4.0

@export_group("Pushing")
## How hard the Zurd shoves the objects and sculptures it bumps into.
@export var push_force: float = 6.0


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


## Wanders around [param home]: random legs that stay within [param home_radius] of it, and a leg
## straight back when the Zurd is outside that radius (after hunting, or when it was driven off).
func process_wander(actor: CharacterBody3D, home: Vector3, home_radius: float, delta: float) -> void:
	_wander_timer += delta
	if (not _has_wander_target
			or _wander_timer >= wander_timeout
			or actor.global_position.distance_to(_wander_target) <= arrival_distance):
		_pick_wander_target(actor, home, home_radius)
	var direction := actor.global_position.direction_to(_wander_target)
	_steer_and_move(actor, direction, wander_speed, wander_turn_speed, delta)
	_process_bobbing(actor, delta)


## Flies toward [param target] at [param speed] (the hunting speed when negative), slowing down
## near it and while it's well off to the side, so the Zurd turns onto it instead of circling it.
func process_hunt(actor: CharacterBody3D, target: Node3D, delta: float, speed: float = -1.0) -> void:
	_has_wander_target = false
	var to_target := target.global_position - actor.global_position
	var distance := to_target.length()
	var direction := to_target / maxf(distance, 0.001)
	var factor := clampf(distance / maxf(arrival_radius, 0.001), min_arrival_speed, 1.0)
	if _get_forward_direction(actor).dot(direction) < 0.5:
		factor = min_arrival_speed
	var top_speed := hunting_speed if speed < 0.0 else speed
	_steer_and_move(actor, direction, top_speed * factor, hunting_turn_speed, delta)
	_process_bobbing(actor, delta)


## Holds the mouth on [param target] while the Zurd eats it: match the target's velocity and pull
## the mouth onto it, so the target stays in the mouth for the whole eat duration.
func process_eating(actor: CharacterBody3D, target: Node3D, mouth_position: Vector3, delta: float) -> void:
	_turn_towards(actor, actor.global_position.direction_to(target.global_position), hunting_turn_speed, delta)
	_level_roll(actor, delta)
	var hold_velocity := _get_target_velocity(target) + (target.global_position - mouth_position) * hold_strength
	actor.velocity = actor.velocity.lerp(hold_velocity, _get_exp_decay_weight(10.0, delta))
	_move(actor, delta)
	_process_bobbing(actor, delta)


## Slows to a stop and stays put (a Passive Zurd nibbling: it doesn't follow its food).
func process_hover(actor: CharacterBody3D, delta: float) -> void:
	_level_roll(actor, delta)
	actor.velocity = actor.velocity.lerp(Vector3.ZERO, _get_exp_decay_weight(10.0, delta))
	_move(actor, delta)
	_process_bobbing(actor, delta)


## Drifts with the knock-back of a stun, easing to a stop.
func process_stunned(actor: CharacterBody3D, delta: float) -> void:
	_has_wander_target = false
	actor.velocity = actor.velocity.lerp(Vector3.ZERO, _get_exp_decay_weight(stun_slowdown, delta))
	_move(actor, delta)
	_process_bobbing(actor, delta)


## Flies directly away from [param away_from] on the ground plane, at the retreat speed.
func process_retreat(actor: CharacterBody3D, away_from: Vector3, delta: float) -> void:
	_has_wander_target = false
	var away := actor.global_position - away_from
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -actor.global_basis.z
		away.y = 0.0
	_steer_and_move(actor, away.normalized(), retreat_speed, hunting_turn_speed, delta)
	_process_bobbing(actor, delta)


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


func _pick_wander_target(actor: CharacterBody3D, home: Vector3, home_radius: float) -> void:
	_has_wander_target = true
	_wander_timer = 0.0
	if actor.global_position.distance_to(home) > home_radius:
		# Head back toward home, to a spot near it.
		var near_home := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0) * wander_vertical, randf_range(-1.0, 1.0))
		_wander_target = home + near_home * home_radius * 0.3
		return
	var direction := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0) * wander_vertical, randf_range(-1.0, 1.0))
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	var target := actor.global_position + direction.normalized() * randf_range(min_wander_distance, max_wander_distance)
	_wander_target = home + (target - home).limit_length(home_radius)


func _steer_and_move(actor: CharacterBody3D, desired_dir: Vector3, move_speed: float, turn_rate: float, delta: float) -> void:
	var final_dir := _get_avoidance_direction(actor, desired_dir)
	_turn_towards(actor, final_dir.normalized(), turn_rate, delta)
	_level_roll(actor, delta)
	var target_velocity := _get_forward_direction(actor) * move_speed
	actor.velocity = actor.velocity.lerp(target_velocity, _get_exp_decay_weight(10.0, delta))
	_move(actor, delta)


func _move(actor: CharacterBody3D, delta: float) -> void:
	var speed := actor.velocity.length()
	actor.move_and_slide()
	_push_bodies(actor, speed, delta)


## Zurds knock around the objects and sculptures they run into (Sculpture-Mass Design Doc §4.3,
## Zurd Core Design Doc §5). The object being eaten is excepted from collisions, so it isn't pushed.
func _push_bodies(actor: CharacterBody3D, speed: float, delta: float) -> void:
	var impulse_force := speed * push_force * delta
	for i in actor.get_slide_collision_count():
		var collision := actor.get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if not body:
			continue
		var impact_offset := collision.get_position() - body.global_position
		body.apply_impulse(-collision.get_normal() * impulse_force, impact_offset)


func _get_target_velocity(target: Node3D) -> Vector3:
	if target is MassPiece:
		return (target as MassPiece).get_velocity()
	if target is RigidBody3D:
		return (target as RigidBody3D).linear_velocity
	return Vector3.ZERO


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


func _level_roll(actor: Node3D, delta: float) -> void:
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
	return (desired_dir + collision_normal * avoidance_strength).normalized()


func _get_forward_direction(actor: Node3D) -> Vector3:
	return -actor.global_basis.z.normalized()


func _get_exp_decay_weight(speed: float, delta: float) -> float:
	return 1.0 - exp(-speed * delta)


func _get_rotation_basis(actor: Node3D) -> Basis:
	return actor.global_basis.orthonormalized()


func _set_rotation_keep_scale(actor: Node3D, rotation_basis: Basis) -> void:
	var current_scale := actor.global_basis.get_scale()
	actor.global_basis = rotation_basis.orthonormalized() * Basis.from_scale(current_scale)
