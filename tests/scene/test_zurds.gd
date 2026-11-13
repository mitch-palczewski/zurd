extends "res://tests/test_case.gd"

## The core Zurds in the game world (Zurd Core Design Doc): starting Zurds, nibbling, the anger and
## who turns Hostile, what Hostile Zurds go after, calming down, swats, ramming and object hits.
## The world has no terrain. The ship hovers at the origin's height of 100 m; Zurds are placed
## beside it. Most Zurds here are held still (wander speed 0), so they stay where a test puts them.

const AREA := Vector3(150.0, 100.0, 0.0)
const SLAB := "res://scenes/objects/rigid/GEO_Stock_07_rigid.tscn"
const OTHER := "res://scenes/objects/rigid/GEO_Stock_06_rigid.tscn"
const THIRD := "res://scenes/objects/rigid/GEO_Stock_05_rigid.tscn"
## A small object to feed Zurds with: the slab at this size is 1.4 × 0.9 × 0.2 m.
const SMALL := 0.3

var world: Node3D
var director: ZurdDirector
var ship: PlayerShip


func test_starting_zurds_spawn_around_the_ship() -> void:
	await _setup(true)
	await wait_frames(2)
	var zurds := director.get_zurds()
	check_equal(zurds.size(), director.starting_zurds, "the world starts with starting_zurds Zurds")
	for zurd in zurds:
		check(zurd.get_parent() == world.get_node(^"Actors/Zurds"), "each is in Actors/Zurds")
		check(zurd.global_basis.get_scale().is_equal_approx(Vector3.ONE), "its body isn't scaled (Godot advises against scaling physics bodies)")
		check(not zurd.is_hostile, "each starts Passive")
		var distance := _ground_distance(zurd, ship)
		# A pair's second Zurd starts up to pair_spacing off, and they've moved a little since.
		var margin := director.pair_spacing + 5.0
		check(distance >= director.spawn_distance.x - margin and distance <= director.spawn_distance.y + margin,
				"each starts spawn_distance from the ship (%.0f m)" % distance)


func test_passive_zurd_feeds_on_loose_objects_it_sees() -> void:
	await _setup()
	director.calm_appetite = 1.0
	var zurd := _spawn_still_zurd(AREA)
	var food := spawn_object(OTHER, AREA + Vector3(30.0, 0.0, 0.0))
	var out_of_sight := spawn_object(OTHER, AREA + Vector3(0.0, 0.0, zurd.sight_component.sight_radius + 50.0))
	var food_ref: WeakRef = weakref(food)
	var fastest := 0.0
	var time := 0.0
	var eating_from := -1.0
	while food_ref.get_ref() != null and time < 30.0:
		await get_tree().physics_frame
		time += 1.0 / Engine.physics_ticks_per_second
		fastest = maxf(fastest, zurd.velocity.length())
		if eating_from < 0.0 and zurd.mouth_component.is_eating():
			eating_from = time
	check(food_ref.get_ref() == null, "a Passive Zurd goes after a loose object it sees and eats it")
	check(not zurd.is_hostile, "while staying Passive")
	check(fastest <= zurd.movement_component.feeding_speed + 0.5, "no faster than feeding_speed (%.1f m/s)" % fastest)
	check_near(time - eating_from, zurd.passive_eat_time, 1.0, "it eats a bite in passive_eat_time")
	check(is_instance_valid(out_of_sight), "it leaves an object out of sight alone")


func test_appetite_rises_with_anger() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	# Decisions last appetite_recheck; 0 makes each one due again on the next frame.
	zurd.appetite_recheck = 0.0
	director.anger.decay_rate = 0.0
	var objects: Array[Node3D] = []
	for i in 400:
		objects.append(Node3D.new())
	var eaten := objects.filter(func(obj: Node3D) -> bool: return zurd.wants_to_eat(obj)).size()
	var share := float(eaten) / objects.size()
	check(share >= director.calm_appetite - 0.1 and share <= director.calm_appetite + 0.1,
			"calm, a Zurd decides to eat about calm_appetite of the objects it sees (%.0f%%)" % (share * 100.0))
	await wait_physics(1)
	director.anger.value = 1.0
	check(objects.all(func(obj: Node3D) -> bool: return zurd.wants_to_eat(obj)), "at full anger it wants to eat them all")
	for obj in objects:
		obj.free()


func test_declined_objects_wait_for_a_second_look() -> void:
	await _setup()
	director.calm_appetite = 0.0
	director.anger.decay_rate = 0.0
	var zurd := _spawn_still_zurd(AREA)
	zurd.appetite_recheck = 3.0
	var food := spawn_object(OTHER, AREA + Vector3(30.0, 0.0, 0.0))
	await wait_seconds(1.0)
	check(zurd.get_target() == null and is_instance_valid(food), "a Passive Zurd that decided against an object leaves it alone")
	director.calm_appetite = 1.0
	var reconsidered := await wait_until(func() -> bool: return zurd.get_target() == food, zurd.appetite_recheck + 1.0)
	check(reconsidered, "after appetite_recheck it decides again (and now wants it)")


func test_hostile_zurds_eat_what_they_declined() -> void:
	await _setup()
	director.calm_appetite = 0.0
	director.anger.decay_rate = 0.0
	var zurd := _spawn_still_zurd(AREA)
	zurd.appetite_recheck = 1000.0
	var spurned := spawn_object(OTHER, AREA + Vector3(30.0, 0.0, 0.0))
	await wait_seconds(1.0)
	check(zurd.get_target() == null, "set-up: the Passive Zurd decided against the object")
	director.anger.value = 1.0
	var hunted := await wait_until(func() -> bool: return zurd.is_hostile and zurd.get_target() == spurned, 2.0)
	check(hunted, "once Hostile, it goes after the object anyway")


func test_idle_passive_zurds_roam_near_the_ship() -> void:
	await _setup()
	var zurd := director.spawn_zurd(ship.global_position + Vector3(350.0, 0.0, 0.0))
	var radius := zurd.roam_radius
	var came_back := await wait_until(func() -> bool: return _ground_distance(zurd, ship) <= radius, 60.0)
	check(came_back, "a Passive Zurd far from the ship roams back near it")
	var furthest := 0.0
	for frame in 30 * Engine.physics_ticks_per_second:
		await get_tree().physics_frame
		furthest = maxf(furthest, _ground_distance(zurd, ship))
	check(furthest <= radius * 1.25, "and stays near it (%.0f m at most, roam_radius %.0f m)" % [furthest, radius])


func test_passive_zurd_watches_sculptures_without_eating_them() -> void:
	await _setup()
	var sculpture := await _make_sculpture(AREA + Vector3(0.0, 0.0, -60.0), 2)
	var parts := sculpture.get_part_count()
	var zurd := director.spawn_zurd(AREA)
	var watch_distance := zurd.movement_component.watch_distance
	var closest := INF
	var ever_targeted := false
	for frame in 15 * Engine.physics_ticks_per_second:
		await get_tree().physics_frame
		closest = minf(closest, zurd.global_position.distance_to(sculpture.get_global_center_of_mass()))
		ever_targeted = ever_targeted or zurd.get_target() != null
	check(closest <= watch_distance * 1.6, "a Passive Zurd that sees a sculpture comes to watch it (%.0f m away at closest)" % closest)
	check(not ever_targeted, "it never goes after the sculpture")
	check_equal(sculpture.get_part_count(), parts, "and eats none of it")


func test_calming_zurd_finishes_its_target_first() -> void:
	await _setup()
	director.hostile_cooldown = 0.0
	var zurd := _spawn_still_zurd(AREA)
	var food := spawn_object(OTHER, AREA + Vector3(40.0, 0.0, 0.0))
	director.anger.decay_rate = 0.0
	director.anger.value = 1.0
	await wait_physics(3)
	check(zurd.is_hostile and zurd.get_target() == food, "set-up: a Hostile Zurd going after an object")
	director.anger.value = 0.0
	await wait_physics(3)
	check(zurd.is_hostile and zurd.is_calming, "told to calm down, it stays Hostile while it finishes its target")
	check(zurd.get_target() == food, "and keeps going after it")
	var ate := await wait_until_freed(food, 10.0)
	check(ate, "it eats its target")
	await wait_physics(30)
	check(not zurd.is_hostile and not zurd.is_calming, "then turns Passive")


func test_mess_turns_the_nearest_zurd_hostile() -> void:
	await _setup()
	director.anger.mess_anger = 0.3
	var near := _spawn_still_zurd(AREA)
	var far := _spawn_still_zurd(AREA + Vector3(0.0, 0.0, 250.0))
	var states := watch(EventBus.zurd_state_changed)
	var eaten := watch(EventBus.object_eaten)
	# Launches past the mess limit, scattered near the first Zurd.
	for i in director.anger.tolerated_mess + 1:
		var spot := AREA + Vector3(-40.0 - (i % 4) * 12.0, 0.0, -30.0 + floorf(i / 4.0) * 12.0)
		EventBus.object_launched.emit(spawn_object(OTHER, spot))
	await wait_physics(2)
	check(director.anger.value > 0.0, "launching past the mess limit angers the Zurds")
	check(near.is_hostile, "the Zurd nearest the mess turns Hostile first")
	check(not far.is_hostile, "while the anger (%.2f) calls for only one" % director.anger.value)
	check(states.any(func(state: Array) -> bool: return state[0] == near and state[1] == true), "zurd_state_changed says so")
	var ate := await wait_until(func() -> bool: return eaten.any(func(event: Array) -> bool: return event[0] == near), 10.0)
	check(ate, "the Hostile Zurd goes after the loose objects and eats one")


func test_hostile_zurd_goes_after_loose_objects_then_large_sculptures() -> void:
	await _setup()
	director.anger.tolerated_sculpture_size = 2
	var sculpture := await _make_sculpture(AREA + Vector3(0.0, 0.0, -40.0), 3)
	var loose := spawn_object(OTHER, AREA + Vector3(30.0, 0.0, 0.0))
	var zurd := _spawn_still_zurd(AREA)
	director.anger.decay_rate = 0.0
	director.anger.value = 1.0
	await wait_physics(3)
	check(zurd.is_hostile, "set-up: the Zurd is Hostile")
	check(zurd.get_target() == loose, "a Hostile Zurd goes after a loose object before a large sculpture")

	loose.queue_free()
	await wait_physics(3)
	var target := zurd.get_target() as MassPiece
	check(target != null and target.mass == sculpture, "with no loose objects left, it goes after the large sculpture")

	director.anger.tolerated_sculpture_size = 15
	await wait_physics(30)
	check(zurd.get_target() == null, "a sculpture under the size limit is left alone")


func test_hostile_zurd_reaches_food_right_beside_it() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	# Off to the side and close: at full speed its turning circle is wider than the gap.
	var food := spawn_object(OTHER, AREA + Vector3(8.0, 0.0, 0.0))
	director.anger.decay_rate = 0.0
	director.anger.value = 1.0
	var ate := await wait_until_freed(food, 8.0)
	check(ate, "a Hostile Zurd turns onto food right beside it and eats it, instead of circling it")


func test_large_sculptures_anger_the_zurds() -> void:
	await _setup()
	director.anger.tolerated_sculpture_size = 2
	var sculpture := await _make_sculpture(AREA, 2)
	check_equal(director.anger.value, 0.0, "a sculpture up to the size limit doesn't anger the Zurds")
	await _add_to_sculpture(sculpture, THIRD)
	check_near(director.anger.value, director.anger.sculpture_anger, 0.0001, "each object added past the limit does")


func test_hostile_zurds_calm_down_after_the_cooldown() -> void:
	await _setup()
	director.hostile_cooldown = 2.0
	var zurd := _spawn_still_zurd(AREA)
	director.anger.value = 1.0
	await wait_physics(2)
	check(zurd.is_hostile, "anger 1: the Zurd turns Hostile")
	director.anger.value = 0.0
	await wait_seconds(director.hostile_cooldown * 0.5)
	check(zurd.is_hostile, "it stays Hostile for the hostile cooldown, though the anger fell")
	await wait_seconds(director.hostile_cooldown * 0.5 + 0.2)
	check(not zurd.is_hostile, "then turns Passive")


func test_swats_stun_then_drive_off() -> void:
	await _setup()
	director.calm_appetite = 1.0
	var zurd := _spawn_still_zurd(AREA)
	zurd.away_time = 2.0
	var stunned := watch(EventBus.zurd_stunned)
	var driven_off := watch(EventBus.zurd_driven_off)

	var food := spawn_object(SLAB, _in_mouth(zurd), SMALL)
	await wait_seconds(0.5)
	check(zurd.mouth_component.is_eating(), "set-up: the Zurd is nibbling")
	for swat in zurd.drive_off_swats - 1:
		zurd.take_swat(Vector3.RIGHT * 10.0)
		check(zurd.is_stunned() and not zurd.is_driven_off(), "swat %d stuns the Zurd" % (swat + 1))
		check(not zurd.mouth_component.is_eating(), "and stops its bite")
		await wait_seconds(zurd.stun_time + 0.2)
		check(not zurd.is_stunned(), "the stun wears off after stun_time")
	check(is_instance_valid(food), "a bite cut short leaves the object whole")
	check_equal(stunned.size(), zurd.drive_off_swats - 1, "zurd_stunned fires for each stun")
	check(director.anger.value > 0.0, "swatting Zurds angers them")

	zurd.take_swat(Vector3.RIGHT * 10.0)
	check(zurd.is_driven_off(), "the last swat drives the Zurd off")
	check_equal(driven_off.size(), 1, "zurd_driven_off fires")
	var away := await wait_until(func() -> bool: return _ground_distance(zurd, ship) >= zurd.retreat_distance, 20.0)
	check(away, "it flies away from the ship, to retreat_distance")
	check(not zurd.is_hostile, "it's Passive while away")
	zurd.take_swat(Vector3.RIGHT * 10.0)
	check_equal(zurd.swats, zurd.drive_off_swats, "swats don't count while it's away")
	var back := await wait_until(func() -> bool: return not zurd.is_driven_off(), zurd.away_time + 2.0)
	check(back, "after away_time it comes back")
	check_equal(zurd.swats, 0, "with its swats reset")


func test_one_swat_counts_once() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	# A swat is a spread of projectiles, several of which can hit the same Zurd at once.
	for projectile in 5:
		zurd.take_swat(Vector3.RIGHT * 10.0)
	check_equal(zurd.swats, 1, "hits within the hit cooldown count once")
	await wait_seconds(zurd.hit_cooldown + 0.1)
	zurd.take_swat(Vector3.RIGHT * 10.0)
	check_equal(zurd.swats, 2, "after it, the next swat counts")


func test_ramming_a_zurd_counts_as_a_swat() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(ship.global_position - ship.global_basis.z * 25.0)
	hold(&"ship_forward")
	var hit := await wait_until(func() -> bool: return zurd.swats >= 1, 5.0)
	release(&"ship_forward")
	check(hit, "flying the ship into a Zurd counts as a swat")


func test_launched_object_stuns_then_gets_eaten() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	var stunned := watch(EventBus.zurd_stunned)
	var eaten := watch(EventBus.object_eaten)
	var thrown := spawn_object(SLAB, AREA + Vector3(30.0, 0.0, 0.0), 0.5, Vector3(-30.0, 0.0, 0.0))
	var hit := await wait_until(func() -> bool: return not stunned.is_empty(), 3.0)
	check(hit, "a launched object flying into a Zurd stuns it")
	check_equal(zurd.swats, 0, "without counting as a swat")
	var ate := await wait_until_freed(thrown, zurd.stun_time + 10.0)
	check(ate and eaten.any(func(event: Array) -> bool: return event[0] == zurd), "after the stun, the Zurd eats that object")


func test_launching_under_the_limit_holds_the_anger() -> void:
	await _setup()
	var pilot: LaunchStation = ship.get_node(^"Stations/PilotLaunch")
	# Only launching under the limits is tested here. The launched objects stop at the same spot and
	# may pile into one sculpture, whose growth past the size limit would rightly add anger; keep
	# both limits out of reach so the pile can't.
	director.anger.tolerated_mess = 1000
	director.anger.tolerated_sculpture_size = 1000
	director.anger.value = 0.5
	# Launch for longer than the calm delay, as fast as the button allows.
	for i in ceili(director.anger.calm_delay * 2.0 / pilot.cooldown_time):
		await tap(pilot.fire_action)
		await wait_seconds(pilot.cooldown_time)
	check(director.get_mess_count() <= director.anger.tolerated_mess, "set-up: still under the mess limit")
	check_near(director.anger.value, 0.5, 0.001, "launching under the limit neither raises nor lowers the anger")
	await wait_seconds(director.anger.calm_delay + 1.0)
	check(director.anger.value < 0.5, "once the launches stop, it falls")


func test_sculptures_count_as_mess() -> void:
	await _setup()
	director.anger.tolerated_mess = 1
	director.anger.mess_anger = 0.3
	var first := spawn_object(OTHER, AREA + Vector3(0.0, 0.0, 60.0))
	EventBus.object_launched.emit(first)
	check_equal(director.anger.value, 0.0, "set-up: one loose object is within a mess limit of 1")
	first.queue_free()
	await wait_physics(2)
	await _make_sculpture(AREA, 2)
	await _make_sculpture(AREA + Vector3(0.0, 0.0, -40.0), 2)
	EventBus.object_launched.emit(spawn_object(OTHER, AREA + Vector3(0.0, 0.0, 60.0)))
	check_near(director.anger.value, 0.3, 0.0001, "one loose object plus two sculptures is over the limit: each sculpture counts as mess")


func test_one_zurd_per_target() -> void:
	await _setup()
	var first := _spawn_still_zurd(AREA)
	var second := _spawn_still_zurd(AREA + Vector3(40.0, 0.0, 0.0))
	var food := spawn_object(OTHER, AREA + Vector3(10.0, 0.0, 0.0))
	director.anger.decay_rate = 0.0
	director.anger.value = 1.0
	await wait_physics(3)
	check(first.get_target() == food, "the nearer Zurd goes after the object")
	check(second.get_target() != food, "the other leaves it alone (it's claimed)")
	first.take_swat(Vector3.RIGHT * 10.0)
	var taken_over := await wait_until(func() -> bool: return second.get_target() == food, 1.0)
	check(taken_over, "when the first Zurd is swatted off it, the other may take it")


func test_zurds_share_a_sculpture_by_pieces() -> void:
	await _setup()
	director.anger.tolerated_sculpture_size = 2
	var sculpture := await _make_sculpture(AREA + Vector3(0.0, 0.0, -40.0), 3)
	var first := _spawn_still_zurd(AREA)
	var second := _spawn_still_zurd(AREA + Vector3(20.0, 0.0, 0.0))
	director.anger.decay_rate = 0.0
	director.anger.value = 1.0
	await wait_physics(3)
	var a := first.get_target() as MassPiece
	var b := second.get_target() as MassPiece
	check(a != null and b != null and a.mass == sculpture and b.mass == sculpture, "both Zurds go after the large sculpture")
	check(a != b, "but after different pieces of it")


func test_zurds_keep_their_personal_space() -> void:
	await _setup()
	var first := _spawn_still_zurd(AREA)
	var second := _spawn_still_zurd(AREA + Vector3(1.0, 0.0, 0.0))
	var space := first.movement_component.personal_space
	var apart := await wait_until(func() -> bool: return first.global_position.distance_to(second.global_position) >= space * 0.75, 3.0)
	check(apart, "two Zurds on top of each other drift apart to most of their personal space")


func test_wandering_zurds_keep_clear_of_the_terrain() -> void:
	world = await load_world(true)
	director = get_zurd_director(world)
	ship = get_ship(world)
	var zurds: Array[Zurd] = []
	for i in 8:
		var angle := TAU * i / 8.0
		var at := Vector3(cos(angle), 0.0, sin(angle)) * 120.0
		at.y = _ground_height(at) + 8.0
		zurds.append(director.spawn_zurd(at))
	var clearance := zurds[0].movement_component.ground_clearance
	var samples := 0
	var scraping := 0
	for frame in 60 * Engine.physics_ticks_per_second:
		await get_tree().physics_frame
		if frame % 10 != 0:
			continue
		for zurd in zurds:
			samples += 1
			if zurd.global_position.y - _ground_height(zurd.global_position) < 2.0:
				scraping += 1
	var share := float(scraping) / samples
	check(share < 0.05, "wandering Zurds stay clear of the terrain: within 2 m of the ground %.1f%% of the time (ground clearance %.0f m)" % [share * 100.0, clearance])


## Loads the world, with its starting Zurds when [param with_zurds], and keeps the ship hovering
## where the Zurds are placed relative to it.
func _setup(with_zurds := false) -> void:
	world = await load_world(false, with_zurds)
	director = get_zurd_director(world)
	ship = get_ship(world)
	if not with_zurds:
		ship.global_position = Vector3(0.0, 100.0, 0.0)


## A Zurd at [param at] that doesn't wander (it still hunts, eats and retreats).
func _spawn_still_zurd(at: Vector3) -> Zurd:
	var zurd := director.spawn_zurd(at)
	zurd.movement_component.wander_speed = 0.0
	return zurd


## Where a small object sits in [param zurd]'s mouth, clear of its body.
func _in_mouth(zurd: Zurd) -> Vector3:
	var radius := 1.0
	for child in zurd.mouth_component.get_children():
		var shape := child as CollisionShape3D
		if shape and shape.shape is SphereShape3D:
			radius = (shape.shape as SphereShape3D).radius
	return zurd.mouth_component.get_mouth_position() - zurd.global_basis.z.normalized() * radius * 0.7


## A sculpture of [param parts] different objects at [param at], fused by contact signals.
func _make_sculpture(at: Vector3, parts: int) -> SculptureMass:
	var fused := watch(EventBus.object_fused)
	var first := spawn_object(SLAB, at)
	var second := spawn_beside(OTHER, first, Vector3.DOWN)
	_hit(first, second)
	await wait_physics(2)
	var mass: SculptureMass = fused[-1][0]
	var models := [THIRD, SLAB, OTHER]
	for i in range(2, parts):
		await _add_to_sculpture(mass, models[(i - 2) % models.size()])
	return mass


func _add_to_sculpture(mass: SculptureMass, path: String) -> void:
	var extra := spawn_beside(path, mass, Vector3.UP)
	_hit(extra, mass)
	await wait_physics(2)


func _hit(body: RigidBody3D, other: Node) -> void:
	for i in get_mass_manager(world).hits_to_fuse:
		body.body_entered.emit(other)


func _ground_height(at: Vector3) -> float:
	var from := Vector3(at.x, 2000.0, at.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4000.0, 1)
	var hit := ship.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else -1000.0


func _ground_distance(a: Node3D, b: Node3D) -> float:
	var offset := a.global_position - b.global_position
	return Vector2(offset.x, offset.z).length()
