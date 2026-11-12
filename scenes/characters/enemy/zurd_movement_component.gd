class_name ZurdMovementComponent
extends Node

## Moves a Zurd (Zurd Core Design Doc §5, §6): wandering around its home, hunting a target, holding
## its mouth on what it eats, hovering while it nibbles, the knock-back of a stun, and retreating
## from the ship. Between targets it keeps clear of the terrain (a height field, so climbing is
## enough) and of other Zurds, and it knocks around the objects it bumps into.

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

@export_group("Feeding and Watching")
## Speed a Passive Zurd goes to food at.
@export var feeding_speed: float = 10.0
## How far from a sculpture a Passive Zurd watches it from.
@export var watch_distance: float = 25.0
## How long it stops to look at the sculpture before moving to another spot around it.
@export var watch_pause: float = 3.0

@export_group("Terrain")
## Least height a Zurd keeps above the ground (the avoidance layers) while flying between targets;
## its wander destinations are kept at least this high too. Off in the last approach to a target,
## so it can still reach food lying on a hill.
@export var ground_clearance: float = 8.0
## How far ahead a Zurd looks for obstacles, in seconds at its speed (at least avoidance_distance).
## When what's ahead is ground, it steers up over it.
@export var look_ahead_time: float = 1.0
## Seconds between checks of the ground under the Zurd.
@export var ground_check_interval: float = 0.1

@export_group("Personal Space")
## Other Zurds closer than this push the Zurd away, more strongly the closer they are.
@export var personal_space: float = 8.0
## Speed of that push when another Zurd is right on top of it.
@export var separation_speed: float = 6.0

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

var _ground_check_timer: float = 0.0
var _ground_height: float = -INF

var _watch_spot: Vector3
var _has_watch_spot: bool = false
var _watch_timer: float = 0.0
var _watch_pause_left: float = 0.0


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


## Watches the sculpture at [param center]: flies to a spot [member watch_distance] from it, stops
## there facing it for [member watch_pause], then moves to another spot around it.
func process_watch(actor: CharacterBody3D, center: Vector3, delta: float) -> void:
	_has_wander_target = false
	if _watch_pause_left > 0.0:
		_watch_pause_left -= delta
		_turn_towards(actor, actor.global_position.direction_to(center), wander_turn_speed, delta)
		_level_roll(actor, delta)
		actor.velocity = actor.velocity.lerp(_get_separation(actor), _get_exp_decay_weight(10.0, delta))
		_move(actor, delta)
		_process_bobbing(actor, delta)
		if _watch_pause_left <= 0.0:
			_has_watch_spot = false
		return
	_watch_timer += delta
	if not _has_watch_spot or _watch_spot.distance_to(center) > watch_distance * 1.5:
		var angle := randf() * TAU
		_watch_spot = center + Vector3(cos(angle), randf_range(-0.3, 0.3), sin(angle)) * watch_distance
		_watch_spot.y = maxf(_watch_spot.y, _get_ground_height(actor, _watch_spot) + ground_clearance)
		_has_watch_spot = true
		_watch_timer = 0.0
	if actor.global_position.distance_to(_watch_spot) <= maxf(arrival_distance, watch_distance * 0.2) or _watch_timer >= wander_timeout:
		_watch_pause_left = watch_pause
		return
	_steer_and_move(actor, actor.global_position.direction_to(_watch_spot), wander_speed, wander_turn_speed, delta)
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
	# Within the arrival radius it may come down to the target, even on a hillside.
	_steer_and_move(actor, direction, top_speed * factor, hunting_turn_speed, delta, distance > arrival_radius)
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
	else:
		var direction := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0) * wander_vertical, randf_range(-1.0, 1.0))
		if direction.is_zero_approx():
			direction = Vector3.FORWARD
		var target := actor.global_position + direction.normalized() * randf_range(min_wander_distance, max_wander_distance)
		_wander_target = home + (target - home).limit_length(home_radius)
	# Never into the ground: lift the destination clear of the terrain under it.
	_wander_target.y = maxf(_wander_target.y, _get_ground_height(actor, _wander_target) + ground_clearance)


## Turns toward [param desired_dir] and moves forward at [param move_speed]. With
## [param keep_clear] it also climbs to keep its ground clearance and steers around what's ahead.
## Other Zurds nearby always push it away.
func _steer_and_move(actor: CharacterBody3D, desired_dir: Vector3, move_speed: float, turn_rate: float, delta: float, keep_clear: bool = true) -> void:
	var direction := desired_dir
	if keep_clear:
		direction = _get_avoidance_direction(actor, _keep_ground_clearance(actor, direction, delta))
	_turn_towards(actor, direction.normalized(), turn_rate, delta)
	_level_roll(actor, delta)
	var target_velocity := _get_forward_direction(actor) * move_speed + _get_separation(actor)
	actor.velocity = actor.velocity.lerp(target_velocity, _get_exp_decay_weight(10.0, delta))
	_move(actor, delta)


## [param direction], tipped upward when the Zurd is below its ground clearance: the lower it is, the
## steeper it climbs.
func _keep_ground_clearance(actor: CharacterBody3D, direction: Vector3, delta: float) -> Vector3:
	_ground_check_timer -= delta
	if _ground_check_timer <= 0.0:
		_ground_check_timer = ground_check_interval
		_ground_height = _get_ground_height(actor, actor.global_position)
	var height := actor.global_position.y - _ground_height
	if height >= ground_clearance:
		return direction
	var climbing := direction
	climbing.y = maxf(climbing.y, clampf(1.0 - height / ground_clearance, 0.0, 1.0))
	return climbing.normalized()


## The height of the ground (the avoidance layers) under [param point], or -INF where there's none.
func _get_ground_height(actor: CharacterBody3D, point: Vector3) -> float:
	var from := Vector3(point.x, point.y + 1000.0, point.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3000.0, avoid_obstacle_mask)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else -INF


## A push away from other Zurds inside the personal space: up to [member separation_speed], stronger
## the closer they are.
func _get_separation(actor: CharacterBody3D) -> Vector3:
	if personal_space <= 0.0:
		return Vector3.ZERO
	var push := Vector3.ZERO
	for node in actor.get_tree().get_nodes_in_group(Zurd.GROUP):
		var other := node as Node3D
		if other == null or other == actor:
			continue
		var offset := actor.global_position - other.global_position
		var distance := offset.length()
		if distance >= personal_space:
			continue
		var away := offset / distance if distance > 0.01 else Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		push += away * (1.0 - distance / personal_space)
	return push.limit_length(1.0) * separation_speed


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


## [param desired_dir], turned away from an obstacle ahead: the ray reaches [member look_ahead_time]
## ahead at the current speed. Ground-like obstacles (facing up) are climbed over.
func _get_avoidance_direction(actor: CharacterBody3D, desired_dir: Vector3) -> Vector3:
	var space_state := actor.get_world_3d().direct_space_state
	var forward := _get_forward_direction(actor)
	var ray_origin := actor.global_position
	var scale_factor := actor.global_basis.get_scale().x
	var reach := maxf(avoidance_distance * scale_factor, actor.velocity.length() * look_ahead_time)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + forward * reach, avoid_obstacle_mask)
	query.exclude = [actor.get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return desired_dir
	var collision_normal: Vector3 = result.normal
	var avoided := desired_dir + collision_normal * avoidance_strength
	if collision_normal.y > 0.3:
		avoided += Vector3.UP * avoidance_strength
	return avoided.normalized()


func _get_forward_direction(actor: Node3D) -> Vector3:
	return -actor.global_basis.z.normalized()


func _get_exp_decay_weight(speed: float, delta: float) -> float:
	return 1.0 - exp(-speed * delta)


func _get_rotation_basis(actor: Node3D) -> Basis:
	return actor.global_basis.orthonormalized()


func _set_rotation_keep_scale(actor: Node3D, rotation_basis: Basis) -> void:
	var current_scale := actor.global_basis.get_scale()
	actor.global_basis = rotation_basis.orthonormalized() * Basis.from_scale(current_scale)
