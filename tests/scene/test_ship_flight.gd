extends "res://tests/test_case.gd"

## The ship's flight in the game world (Ship-Controls Design Doc §5.2): top speed, coasting to a
## hover, turning, the hover drift, the ceiling, the ground clearance and the lowest altitude, and
## breaking objects off a mass by ramming it. Expected values come from the flight controller.

const SLAB := "res://scenes/objects/rigid/GEO_Stock_07_rigid.tscn"
const OTHER := "res://scenes/objects/rigid/GEO_Stock_06_rigid.tscn"

var world: Node3D
var ship: PlayerShip
var flight: PlayerFlightController


func before_each() -> void:
	world = await load_world()
	ship = get_ship(world)
	flight = ship.flight_controller
	ship.global_position = Vector3(0.0, flight.altitude_ceiling - 20.0, 0.0)
	await wait_physics(1)


func test_reaches_top_speed_gradually() -> void:
	hold(&"ship_forward")
	var speeding_up := flight.max_forward_speed / flight.acceleration
	await wait_seconds(speeding_up * 0.5)
	check(flight.forward_speed < flight.max_forward_speed * 0.9, "the ship speeds up gradually (acceleration), not at once")
	var fastest := 0.0
	for i in ceili((speeding_up * 0.5 + flight.input_ramp_time + 0.5) * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		fastest = maxf(fastest, flight.forward_speed)
	check_near(flight.forward_speed, flight.max_forward_speed, 0.01, "it reaches max_forward_speed")
	check(fastest <= flight.max_forward_speed + 0.001, "and never goes faster")
	var horizontal := Vector3(ship.velocity.x, 0.0, ship.velocity.z)
	check_near(horizontal.length(), flight.max_forward_speed, 0.05, "the ship moves at that speed")
	check_near(horizontal.normalized(), -ship.global_basis.z, 0.01, "straight ahead")


func test_coasts_to_a_hover() -> void:
	hold(&"ship_forward")
	await wait_until(func() -> bool: return is_equal_approx(flight.forward_speed, flight.max_forward_speed), 10.0)
	release(&"ship_forward")
	await wait_seconds(flight.coast_to_hover_time * 0.5)
	check(flight.forward_speed > 0.0, "released, the ship doesn't stop at once")
	await wait_seconds(flight.coast_to_hover_time * 0.5 + flight.input_ramp_time + 0.1)
	check_near(flight.forward_speed, 0.0, 0.001, "it slows to a stop in coast_to_hover_time")
	await wait_seconds(flight.hover_blend_time + 0.1)
	check_near(flight.hover_amount, 1.0, 0.001, "then it hovers")
	var horizontal := Vector2(ship.velocity.x, ship.velocity.z)
	check(horizontal.length() <= flight.idle_drift_speed + 0.001, "drifting no faster than idle_drift_speed")


func test_turns_at_its_turn_rate_without_tilting() -> void:
	hold(&"ship_turn_left")
	await wait_seconds(flight.input_ramp_time + 0.1)
	# Both readings at the start of a physics frame, so exactly one second of steps lies between.
	await wait_physics(1)
	var start := ship.global_rotation.y
	await wait_physics(Engine.physics_ticks_per_second)
	var turned := rad_to_deg(angle_difference(start, ship.global_rotation.y))
	check_near(turned, flight.max_turn_rate_degrees, 0.5, "holding left turns max_turn_rate_degrees a second, to the left")
	check_near(ship.global_basis.y, Vector3.UP, 0.0001, "the ship never pitches or rolls")


func test_hover_drift_stays_near_the_spot() -> void:
	check(flight.idle_drift_speed < flight.min_impact_speed, "a hovering ship drifts slower than an impact, so resting against a mass breaks nothing")
	await wait_seconds(flight.hover_blend_time + 0.1)
	var spot := ship.global_position
	var furthest := 0.0
	var fastest := 0.0
	for i in ceili(flight.drift_period * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		var offset := ship.global_position - spot
		furthest = maxf(furthest, Vector2(offset.x, offset.z).length())
		fastest = maxf(fastest, Vector2(ship.velocity.x, ship.velocity.z).length())
	check(furthest > 0.0, "an idle ship drifts")
	check(fastest <= flight.idle_drift_speed + 0.001, "no faster than idle_drift_speed")
	var bound := flight.idle_drift_speed * flight.drift_period * 0.5
	check(furthest <= bound, "it stays near its hover spot over a drift period (%.1f m, within %.1f m)" % [furthest, bound])
	check_near(ship.global_position.y, spot.y, 0.001, "without changing height (only the cockpit bobs)")


func test_rising_stops_at_the_ceiling() -> void:
	ship.global_position.y = flight.altitude_ceiling - 3.0
	hold(&"ship_rise")
	var highest := 0.0
	for i in ceili((flight.input_ramp_time + 3.0 / flight.rise_speed + 1.0) * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		highest = maxf(highest, ship.global_position.y)
	check_near(ship.global_position.y, flight.altitude_ceiling, 0.01, "rising stops at altitude_ceiling")
	check(highest <= flight.altitude_ceiling + 0.001, "and never passes it")


func test_sinking_stops_at_ground_clearance() -> void:
	var ground := _ground_height(ship.global_position)
	if not check(not is_nan(ground), "set-up: there's ground under the ship"):
		return
	ship.global_position.y = ground + flight.ground_clearance + 10.0
	hold(&"ship_sink")
	await wait_seconds(flight.input_ramp_time + 10.0 / flight.rise_speed + 1.0)
	ground = _ground_height(ship.global_position)
	check_near(ship.global_position.y, ground + flight.ground_clearance, 0.05, "sinking stops ground_clearance above the ground")


func test_without_ground_sinking_stops_at_the_lowest_altitude() -> void:
	ship.global_position = Vector3(5000.0, flight.lowest_altitude + 3.0, 5000.0)
	if not check(is_nan(_ground_height(ship.global_position)), "set-up: no ground out here"):
		return
	hold(&"ship_sink")
	await wait_seconds(flight.input_ramp_time + 3.0 / flight.rise_speed + 1.0)
	check_near(ship.global_position.y, flight.lowest_altitude, 0.01, "sinking stops at lowest_altitude")


func test_ramming_a_mass_breaks_off_what_it_hits() -> void:
	var manager := get_mass_manager(world)
	var slab := spawn_object(SLAB, ship.global_position - ship.global_basis.z * 30.0)
	var other := spawn_beside(OTHER, slab, Vector3.UP)
	for i in manager.hits_to_fuse:
		slab.body_entered.emit(other)
	await wait_physics(2)
	if not check(not is_instance_valid(slab), "set-up: a mass right ahead"):
		return
	var broken_off := watch(EventBus.objects_broken_off)
	hold(&"ship_forward")
	var broke := await wait_until(func() -> bool: return not broken_off.is_empty(), 5.0)
	check(broke, "flying into the mass breaks objects off it")
	if broke:
		var bodies: Array = broken_off[0][1]
		check(bodies.any(func(body: RigidBody3D) -> bool: return body.scene_file_path == SLAB), "including the object the ship hit")


## The height of the ground (the flight controller's ground layers) under [param point], or NAN.
func _ground_height(point: Vector3) -> float:
	var from := Vector3(point.x, 1000.0, point.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2000.0, flight.ground_mask)
	var hit := ship.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else NAN
