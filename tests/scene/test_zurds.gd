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
		check(not zurd.is_hostile, "each starts Passive")
		var distance := _ground_distance(zurd, ship)
		check(distance >= director.spawn_distance.x - director.pair_spacing and distance <= director.spawn_distance.y + director.pair_spacing,
				"each starts spawn_distance from the ship (%.0f m)" % distance)


func test_passive_zurd_nibbles_only_what_it_drifts_into() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	var far := spawn_object(SLAB, zurd.mouth_component.get_mouth_position() + Vector3(0.0, 0.0, -20.0), SMALL)
	await wait_seconds(2.0)
	check(is_instance_valid(far) and zurd.get_target() == null, "a Passive Zurd leaves an object out of reach alone")

	var near := spawn_object(SLAB, _in_mouth(zurd), SMALL)
	var eat_time := zurd.mouth_component.eat_duration
	await wait_seconds(eat_time + 0.3)
	check(is_instance_valid(near), "it nibbles slower than a Hostile Zurd eats")
	var nibbled := await wait_until_freed(near, eat_time / zurd.nibble_speed + 2.0)
	check(nibbled, "but it eats an object in its mouth")
	check(is_instance_valid(far), "and still leaves the far one alone")


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
	director.anger.value = 0.5
	# Launch for longer than the calm delay, as fast as the button allows.
	for i in ceili(director.anger.calm_delay * 2.0 / pilot.cooldown_time):
		await tap(pilot.fire_action)
		await wait_seconds(pilot.cooldown_time)
	check(director.get_loose_objects().size() <= director.anger.tolerated_mess, "set-up: still under the mess limit")
	check_near(director.anger.value, 0.5, 0.001, "launching under the limit neither raises nor lowers the anger")
	await wait_seconds(director.anger.calm_delay + 1.0)
	check(director.anger.value < 0.5, "once the launches stop, it falls")


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


func _ground_distance(a: Node3D, b: Node3D) -> float:
	var offset := a.global_position - b.global_position
	return Vector2(offset.x, offset.z).length()
