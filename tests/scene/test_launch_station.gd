extends "res://tests/test_case.gd"

## Launching (Ship-Controls Design Doc §5.3, §5.5, Launch-Station Design Doc): launch points, launch
## speed and stop distance, what launched objects carry, the launch station's selection and preview
## timing, cooldowns, and station activity. The world has no terrain and the ship hovers high, so
## launched objects fly free.

var world: Node3D
var ship: PlayerShip
var launcher: LaunchObjectComponent
var pilot: LaunchStation
var station: LaunchStation
## Every launch_selection_changed emission: [station id, scene].
var selections: Array
## Every launched object: [body, position in launcher space, velocity], at launch.
var launched: Array


func before_each() -> void:
	selections = watch(EventBus.launch_selection_changed)
	world = await load_world(false)
	ship = get_ship(world)
	ship.global_position = Vector3(0.0, 100.0, 0.0)
	launcher = ship.get_node(^"LaunchMuzzle")
	pilot = ship.get_node(^"Stations/PilotLaunch")
	station = ship.get_node(^"Stations/StationLaunch")
	launched = []
	listen(EventBus.spawn_requested, func(node: Node3D) -> void:
		var body := node as RigidBody3D
		if body and not body is SculptureMass:
			launched.append([body, launcher.global_transform.affine_inverse() * body.global_position, body.linear_velocity]))
	await wait_physics(1)


func test_starts_hidden_and_quiet() -> void:
	await wait_frames(5)
	check(selections.is_empty(), "no launch_selection_changed at startup")
	check(not station.is_showing, "the launch station shows nothing at startup")
	check(not station.preview.pedestal.visible, "its pedestal is down")


func test_each_button_launches_from_its_side() -> void:
	await tap(pilot.fire_action)
	await tap(station.fire_action)
	if not check_equal(launched.size(), 2, "one object per press"):
		return
	check_near(launched[0][1].x, pilot.side_offset, 0.001, "the pilot's button launches from the middle")
	check_near(launched[1][1].x, station.side_offset, 0.001, "the launch station launches from its own side")


func test_launch_speed_and_stop_distance() -> void:
	await tap(pilot.fire_action)
	if not check_equal(launched.size(), 1, "one object launched"):
		return
	var body: RigidBody3D = launched[0][0]
	var velocity: Vector3 = launched[0][2]
	var carried := ship.velocity.length() * launcher.ship_velocity_carry_over
	check_near(velocity.length(), launcher.launch_speed, carried + 0.01, "it leaves at launch_speed")
	var off_axis := rad_to_deg(velocity.angle_to(-launcher.global_basis.z))
	check(off_axis <= launcher.spread_degrees * sqrt(2.0) + 0.5, "straight ahead, within spread_degrees (%.1f°)" % off_axis)
	var start := launcher.global_transform * (launched[0][1] as Vector3)
	# Five time constants of the braking: all but 1% of the way.
	await wait_seconds(5.0 * launcher.target_stop_distance / launcher.launch_speed)
	var travelled := body.global_position.distance_to(start)
	check_near(travelled, launcher.target_stop_distance, launcher.target_stop_distance * 0.1, "it stops about target_stop_distance away")


func test_launched_objects_are_tracked_grouped_and_clear_the_ship() -> void:
	await tap(pilot.fire_action)
	if not check_equal(launched.size(), 1, "one object launched"):
		return
	var body: RigidBody3D = launched[0][0]
	check(ObjectTracker.active_objects.has(body), "a launched object is a Zurd target")
	var entry := launcher.catalog.find_entry(load(body.scene_file_path) as PackedScene)
	check(entry != null, "it's an object from the catalog")
	if entry:
		check_equal(ObjectCatalog.group_of(body), entry.group, "it carries its catalog group")
	check(body.get_collision_exceptions().has(ship), "at first it passes through the ship")
	var cleared := await wait_until(func() -> bool: return not body.get_collision_exceptions().has(ship), 3.0)
	check(cleared, "then it collides with the ship again")
	check(body.global_position.distance_to(ship.global_position) >= launcher.clearance_distance, "once it's clearance_distance away")


func test_station_shows_steps_and_wraps() -> void:
	var count := launcher.get_object_count()
	await tap(station.next_action)
	check(station.is_showing, "the first press shows the selection")
	check_equal(station.selected_index, 0, "without stepping (object 0)")
	_check_last_selection(launcher.get_object_scene(0), "the signal carries the shown object's scene")
	await tap(station.next_action)
	check_equal(station.selected_index, 1, "next steps to object 1")
	_check_last_selection(launcher.get_object_scene(1), "the signal carries the new scene")
	await tap(station.prev_action)
	await tap(station.prev_action)
	check_equal(station.selected_index, count - 1, "previous from object 0 wraps to the last object")
	_check_last_selection(launcher.get_object_scene(count - 1), "the signal carries the last object's scene")


func test_launch_fires_the_shown_object() -> void:
	await tap(station.next_action)
	await tap(station.next_action)
	await tap(station.fire_action)
	if not check_equal(launched.size(), 1, "one object launched"):
		return
	check_equal(launched[0][0].scene_file_path, launcher.get_object_scene(1).resource_path, "it's the shown object")
	check(station.is_showing, "the preview stays up after a launch")


func test_preview_hides_after_the_delay_and_remembers() -> void:
	await tap(station.next_action)
	await tap(station.next_action)
	var shown := station.selected_index
	await wait_seconds(station.preview_hide_delay - 0.5)
	check(station.is_showing, "the preview stays up before preview_hide_delay")
	await wait_seconds(1.0)
	check(not station.is_showing, "it hides preview_hide_delay after the last press")
	_check_last_selection(null, "launch_selection_changed sends null when it hides")
	check(station.get_launch_scene() == null, "the station launches random objects again")
	await tap(station.fire_action)
	check_equal(launched.size(), 1, "and still launches")
	await tap(station.next_action)
	check_equal(station.selected_index, shown, "the next press shows the remembered object, without stepping")


func test_launching_keeps_the_preview_up() -> void:
	await tap(station.next_action)
	await tap(station.fire_action)
	await wait_seconds(station.preview_hide_delay - 1.0)
	await tap(station.fire_action)
	await wait_seconds(station.preview_hide_delay - 1.0)
	check(station.is_showing, "each launch restarts the hide timer")
	await wait_seconds(1.5)
	check(not station.is_showing, "it hides preview_hide_delay after the last press")


func test_cooldowns() -> void:
	await tap(station.fire_action)
	await tap(station.fire_action)
	check_equal(launched.size(), 1, "a second press within cooldown_time launches nothing")
	await tap(pilot.fire_action)
	check_equal(launched.size(), 2, "the pilot's button has its own cooldown")
	await tap(station.next_action)
	check(station.is_showing, "selecting works right after a launch")
	await wait_seconds(station.cooldown_time)
	await tap(station.fire_action)
	check_equal(launched.size(), 3, "after cooldown_time it launches again")


func test_stations_go_active_and_empty() -> void:
	var activity := watch(EventBus.station_activity_changed)
	var pilot_activity: StationActivity = ship.get_node(^"Stations/PilotActivity")
	var station_activity: StationActivity = ship.get_node(^"Stations/LaunchStationActivity")
	await tap(&"ship_forward")
	await tap(station.next_action)
	check(_has_activity(activity, pilot_activity.station_id, true), "flying makes the pilot's station active")
	check(_has_activity(activity, station_activity.station_id, true), "selecting makes the launch station active")
	await wait_seconds(pilot_activity.idle_timeout - 1.0)
	check(pilot_activity.is_active and station_activity.is_active, "they stay active until idle_timeout")
	await wait_seconds(2.0)
	check(not pilot_activity.is_active and not station_activity.is_active, "with no input for idle_timeout, they're empty")
	check(_has_activity(activity, pilot_activity.station_id, false), "station_activity_changed says so")


func _check_last_selection(scene: PackedScene, what: String) -> void:
	if selections.is_empty():
		check(false, what + " (it never fired)")
		return
	var last: Array = selections.back()
	check(last[0] == station.station_id and last[1] == scene, what)


func _has_activity(events: Array, station_id: StringName, active: bool) -> bool:
	return events.any(func(event: Array) -> bool: return event[0] == station_id and event[1] == active)
