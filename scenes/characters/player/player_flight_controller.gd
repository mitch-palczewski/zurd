class_name PlayerFlightController
extends Node

## Flies the ship like a fish in water (Ship-Controls Design Doc §5.2): the joystick drives and
## turns, two buttons rise and sink, and with no input the ship slows to a hover and drifts.
## The ship only ever turns around global Y, so the projected view never pitches or rolls.

## [param collider_shape]: the shape the ship hit (a [CollisionShape3D]), so a sculpture mass knows
## which of its objects to break off.
signal impact_occurred(collider: Object, force: float, collider_shape: Object)

## How far below the ship the ground ray reaches. Past this the ship counts as having no ground.
const GROUND_PROBE_LENGTH: float = 1000.0

@export_group("Speed")
@export var max_forward_speed: float = 18.0
@export var max_reverse_speed: float = 6.0
## How fast the ship speeds up toward its target speed, in m/s².
@export var acceleration: float = 10.0
## Time to slow from top speed to a hover once the stick is released.
@export var coast_to_hover_time: float = 1.5

@export_group("Handling")
## Time for an on/off input to ease to full strength, so a digital arcade stick feels analog and
## turns never start or stop with a jerk.
@export var input_ramp_time: float = 0.3
## Turn speed at full input, in degrees per second.
@export_range(0.0, 180.0, 0.1, "degrees") var max_turn_rate_degrees: float = 45.0
@export var rise_speed: float = 5.0

@export_group("Altitude")
## Closest the ship may sink toward the ground (Environment layer) below it.
@export var ground_clearance: float = 4.0
## Floor used where there is no ground under the ship.
@export var lowest_altitude: float = -50.0
## Highest the ship may rise. Keep it below the cloud band ([member MassManager.atmosphere_y_range]).
@export var altitude_ceiling: float = 120.0
@export_flags_3d_physics var ground_mask: int = 1

@export_group("Hover")
## Top speed of the gentle drift while hovering. Keep it below [member min_impact_speed] so a
## resting ship never breaks objects off a mass.
@export var idle_drift_speed: float = 0.5
## Seconds for one slow drift loop around the hover spot.
@export var drift_period: float = 40.0
## Time for the drift and bob to fade in once the ship is idle, and out again on input.
@export var hover_blend_time: float = 1.0
@export var hover_bob_height: float = 0.2
## Bobs per second.
@export var hover_bob_frequency: float = 0.15

@export_group("View")
## Fixed downward tilt of the camera. It never changes during play.
@export_range(-30.0, 30.0, 0.1, "degrees") var camera_tilt_degrees: float = 0.0

@export_group("Collision Interaction")
@export var push_force: float = 12.0
@export var min_impact_speed: float = 2.0

var ship: CharacterBody3D
var cockpit: Node3D
var camera: Camera3D

## Speed along the ship's facing; negative in reverse.
var forward_speed: float = 0.0
var vertical_speed: float = 0.0
## 0 while the pilot flies, 1 once the ship hovers. Scales the drift and the bob.
var hover_amount: float = 0.0

var _thrust: float = 0.0
var _turn: float = 0.0
var _lift: float = 0.0
var _hover_time: float = 0.0
var _base_cockpit_position: Vector3 = Vector3.ZERO


func setup(player_ship: CharacterBody3D, player_cockpit: Node3D, player_camera: Camera3D) -> void:
	ship = player_ship
	cockpit = player_cockpit
	camera = player_camera

	# The view never pitches or rolls, even if the ship was placed tilted.
	ship.global_basis = Basis(Vector3.UP, ship.global_rotation.y)
	if cockpit:
		cockpit.rotation = Vector3.ZERO
		_base_cockpit_position = cockpit.position
	if camera:
		camera.rotation = Vector3(-deg_to_rad(camera_tilt_degrees), 0.0, 0.0)


func _physics_process(delta: float) -> void:
	if not ship or not cockpit:
		return
	_process_flight(delta)


func _process_flight(delta: float) -> void:
	var thrust_input := Input.get_axis(&"ship_reverse", &"ship_forward")
	var turn_input := Input.get_axis(&"ship_turn_right", &"ship_turn_left")
	var lift_input := Input.get_axis(&"ship_sink", &"ship_rise")
	var has_input := thrust_input != 0.0 or turn_input != 0.0 or lift_input != 0.0

	_ease_inputs(thrust_input, turn_input, lift_input, delta)
	_apply_thrust(delta)
	_apply_turn(delta)
	_update_hover(has_input, delta)

	vertical_speed = _limit_vertical_speed(_lift * rise_speed, delta)
	ship.velocity = -ship.global_basis.z * forward_speed + Vector3.UP * vertical_speed + _get_drift_velocity()
	var pre_slide_velocity := ship.velocity
	ship.move_and_slide()

	_update_bob()
	_handle_collisions(pre_slide_velocity, delta)


func _ease_inputs(thrust_input: float, turn_input: float, lift_input: float, delta: float) -> void:
	var step := delta / maxf(input_ramp_time, 0.001)
	_thrust = move_toward(_thrust, thrust_input, step)
	_turn = move_toward(_turn, turn_input, step)
	_lift = move_toward(_lift, lift_input, step)


func _apply_thrust(delta: float) -> void:
	var top_speed := max_forward_speed if _thrust >= 0.0 else max_reverse_speed
	var target_speed := _thrust * top_speed
	var speeding_up := absf(target_speed) > absf(forward_speed) and target_speed * forward_speed >= 0.0
	var rate := acceleration if speeding_up else max_forward_speed / maxf(coast_to_hover_time, 0.01)
	forward_speed = move_toward(forward_speed, target_speed, rate * delta)


func _apply_turn(delta: float) -> void:
	# Positive turns left. Left always turns the view left, also in reverse.
	ship.global_rotate(Vector3.UP, deg_to_rad(max_turn_rate_degrees) * _turn * delta)


func _update_hover(has_input: bool, delta: float) -> void:
	_hover_time += delta
	var is_idle := not has_input and absf(forward_speed) <= idle_drift_speed
	hover_amount = move_toward(hover_amount, 1.0 if is_idle else 0.0, delta / maxf(hover_blend_time, 0.01))


func _get_drift_velocity() -> Vector3:
	# Two slow waves at different rates trace a loose loop, so the ship drifts like a moored boat
	# and stays near its hover spot. Position only: the view never turns by itself.
	var phase := TAU * _hover_time / maxf(drift_period, 0.01)
	var drift := Vector3(sin(phase), 0.0, sin(phase * 0.7 + 1.3))
	return drift.limit_length(1.0) * idle_drift_speed * hover_amount


func _limit_vertical_speed(wanted_speed: float, delta: float) -> float:
	var height := ship.global_position.y
	var floor_height := _get_floor_height()
	var next_height := height + wanted_speed * delta
	if next_height < floor_height:
		# Climb back no faster than the ship can rise, so it rides up over hills without snapping.
		return minf((floor_height - height) / delta, rise_speed)
	if next_height > altitude_ceiling:
		return maxf((altitude_ceiling - height) / delta, -rise_speed)
	return wanted_speed


func _get_floor_height() -> float:
	var origin := ship.global_position
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * GROUND_PROBE_LENGTH, ground_mask)
	var hit := ship.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return lowest_altitude
	var ground: Vector3 = hit["position"]
	return ground.y + ground_clearance


func _update_bob() -> void:
	# The whole cockpit (camera and visible floor) bobs together, so the floor stays fixed in the view.
	var bob := sin(TAU * hover_bob_frequency * _hover_time) * hover_bob_height * hover_amount
	cockpit.position = _base_cockpit_position + Vector3(0.0, bob, 0.0)


func _handle_collisions(pre_slide_velocity: Vector3, delta: float) -> void:
	var impulse_force := pre_slide_velocity.length() * push_force * delta

	for i in ship.get_slide_collision_count():
		var collision := ship.get_slide_collision(i)
		var collider := collision.get_collider()

		if not collider:
			continue

		if collider is RigidBody3D:
			var body := collider as RigidBody3D
			var push_dir := -collision.get_normal()
			var impact_offset := collision.get_position() - body.global_position
			body.apply_impulse(push_dir * impulse_force, impact_offset)

		var incoming_speed := -pre_slide_velocity.dot(collision.get_normal())

		if incoming_speed >= min_impact_speed:
			impact_occurred.emit(collider, impulse_force, collision.get_collider_shape())
