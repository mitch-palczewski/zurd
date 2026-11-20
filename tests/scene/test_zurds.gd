extends "res://tests/test_case.gd"

## The Zurds in the game world (Zurd Core Design Doc §5, §6, §12): the starting cast, feeding and
## appetite, each Zurd's own anger and Hostility, the roles' homes and hunting, Sentinels finding
## settled sculptures, swats by boldness, ramming and object hits. The world has no terrain unless a
## test needs it. The ship hovers at the origin's height of 100 m; Zurds are placed beside it. Many
## Zurds here are held still (wander speed 0), so they stay where a test puts them.

const AREA := Vector3(150.0, 100.0, 0.0)
const SLAB := "res://scenes/objects/rigid/GEO_Stock_07_rigid.tscn"
const OTHER := "res://scenes/objects/rigid/GEO_Stock_06_rigid.tscn"
const THIRD := "res://scenes/objects/rigid/GEO_Stock_05_rigid.tscn"
## A small object to feed Zurds with: the slab at this size is 1.4 × 0.9 × 0.2 m.
const SMALL := 0.3

var world: Node3D
var director: ZurdDirector
var ship: PlayerShip


# ==============================================================================
# THE CAST
# ==============================================================================

func test_world_starts_with_its_cast() -> void:
	await _setup(true)
	await wait_frames(2)
	var shadows := director.get_zurds_with_role(director.shadow_role)
	var grazers := director.get_zurds_with_role(director.grazer_role)
	var sentinels := director.get_zurds_with_role(director.sentinel_role)
	check(shadows.size() == director.shadow_count and grazers.size() == director.grazer_count and sentinels.size() == director.sentinel_count,
			"the world starts with its cast: %d Shadows, %d Grazers, %d Sentinels" % [shadows.size(), grazers.size(), sentinels.size()])
	var placed := true
	var calm := true
	for zurd in director.get_zurds():
		placed = placed and zurd.get_parent() == world.get_node(^"Actors/Zurds") and zurd.global_basis.get_scale().is_equal_approx(Vector3.ONE)
		calm = calm and not zurd.is_hostile and zurd.anger.value == 0.0
	check(placed, "each is in Actors/Zurds, its body unscaled (Godot advises against scaling physics bodies)")
	check(calm, "each starts Passive, its anger at 0")
	var in_patch := true
	var patches: Dictionary[int, bool] = {}
	for grazer in grazers:
		in_patch = in_patch and _ground_distance_to(grazer, grazer.patch_center) <= grazer.patch_radius
		patches[grazer.patch_index] = true
	check(in_patch, "each Grazer starts in its patch")
	check_equal(patches.size(), director.grazer_count, "each has a patch of its own")
	var watching := true
	for sentinel in sentinels:
		watching = watching and sentinel.home_landmark != null and sentinel.global_position.distance_to(sentinel.home_landmark.global_position) <= 60.0
	check(watching, "each Sentinel starts at a landmark")
	var in_view := true
	for shadow in shadows:
		in_view = in_view and _bearing_from_ship(shadow) <= director.shadow_role.view_arc + 5.0
		var distance := _ground_distance(shadow, ship)
		in_view = in_view and distance >= director.shadow_role.ship_distance.x - 30.0 and distance <= director.shadow_role.ship_distance.y + 30.0
	check(in_view, "each Shadow starts at its spot, in the players' view at its distance from the ship")


func test_grazer_keeps_to_its_patch() -> void:
	await _setup()
	var grazer := director.spawn_zurd(AREA + Vector3(400.0, 0.0, 0.0))
	grazer.patch_center = AREA
	grazer.patch_radius = 100.0
	var came_back := await wait_until(func() -> bool: return _ground_distance_to(grazer, AREA) <= grazer.patch_radius, 60.0)
	check(came_back, "a Grazer away from its patch heads back to it")
	var furthest := 0.0
	for frame in 30 * Engine.physics_ticks_per_second:
		await get_tree().physics_frame
		furthest = maxf(furthest, _ground_distance_to(grazer, AREA))
	check(furthest <= grazer.patch_radius * 1.25, "and stays in it (%.0f m out at most, patch radius %.0f m)" % [furthest, grazer.patch_radius])


func test_shadow_keeps_its_spot_in_view() -> void:
	await _setup()
	var shadow := director.spawn_zurd(ship.global_position + Vector3(0.0, 0.0, 250.0), director.shadow_role)
	var arc := director.shadow_role.view_arc
	var at_spot := func() -> bool: return shadow.global_position.distance_to(shadow.get_ship_spot()) <= shadow.role.home_radius * 1.5
	var arrived: bool = await wait_until(at_spot, 30.0)
	check(arrived, "a Shadow behind the ship comes round to its spot")
	check(_bearing_from_ship(shadow) <= arc + 10.0, "in the players' view (%.0f° off the heading, arc %.0f°)" % [_bearing_from_ship(shadow), arc])
	# Arrived means within 1.5 roaming radii of its spot, so that's the margin on its distance too.
	var margin := shadow.role.home_radius * 1.5
	check(_ground_distance(shadow, ship) >= shadow.role.ship_distance.x - margin, "at its distance, not on the ship's tail")
	hold(&"ship_forward")
	await wait_seconds(3.0)
	release(&"ship_forward")
	var kept_up: bool = await wait_until(at_spot, 30.0)
	check(kept_up, "when the ship flies on, it catches up to its spot again")


# ==============================================================================
# FEEDING AND APPETITE
# ==============================================================================

func test_passive_zurd_feeds_on_loose_objects_it_sees() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	zurd.temperament.greed = 1.0
	var food := spawn_object(OTHER, AREA + Vector3(30.0, 0.0, 0.0))
	var out_of_sight := spawn_object(OTHER, AREA + Vector3(0.0, 0.0, zurd.sight_component.sight_radius + 50.0))
	var food_ref: WeakRef = weakref(food)
	var fastest := 0.0
	var time := 0.0
	var eating_from := -1.0
	while food_ref.get_ref() != null and time < 30.0:
		await get_tree().physics_frame
		time += 1.0 / Engine.physics_ticks_per_second
		if eating_from < 0.0 and zurd.mouth_component.is_eating():
			eating_from = time
		# The approach: holding the bite in its mouth can pull it along a little faster.
		if eating_from < 0.0:
			fastest = maxf(fastest, zurd.velocity.length())
	check(food_ref.get_ref() == null, "a Passive Zurd goes after a loose object it sees and eats it")
	check(not zurd.is_hostile, "while staying Passive")
	check(fastest <= zurd.movement_component.feeding_speed + 0.5, "it goes to it no faster than its feeding_speed (%.1f m/s, feeding speed %.1f)" % [fastest, zurd.movement_component.feeding_speed])
	check_near(time - eating_from, zurd.passive_eat_time, 1.0, "it eats a bite in passive_eat_time")
	check(is_instance_valid(out_of_sight), "it leaves an object out of sight alone")


func test_appetite_rises_with_its_anger() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	# Decisions last appetite_recheck; 0 makes each one due again on the next frame.
	zurd.appetite_recheck = 0.0
	zurd.anger.decay_rate = 0.0
	var objects: Array[Node3D] = []
	for i in 400:
		objects.append(Node3D.new())
	var greed := zurd.temperament.greed
	var share := float(objects.filter(func(obj: Node3D) -> bool: return zurd.wants_to_eat(obj)).size()) / objects.size()
	check(share >= greed - 0.1 and share <= greed + 0.1, "calm, a Zurd eats about its greed's share of what it sees (%.0f%%, greed %.0f%%)" % [share * 100.0, greed * 100.0])
	await wait_physics(1)
	zurd.anger.value = 1.0
	check(objects.all(func(obj: Node3D) -> bool: return zurd.wants_to_eat(obj)), "at full anger it wants to eat them all")
	for obj in objects:
		obj.free()


func test_declined_objects_wait_for_a_second_look() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	zurd.temperament.greed = 0.0
	zurd.appetite_recheck = 3.0
	var food := spawn_object(OTHER, AREA + Vector3(30.0, 0.0, 0.0))
	await wait_seconds(1.0)
	check(zurd.get_target() == null and is_instance_valid(food), "a Passive Zurd that decided against an object leaves it alone")
	zurd.temperament.greed = 1.0
	var reconsidered := await wait_until(func() -> bool: return zurd.get_target() == food, zurd.appetite_recheck + 1.0)
	check(reconsidered, "after appetite_recheck it decides again (and now wants it)")


func test_hostile_zurds_eat_what_they_declined() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	zurd.temperament.greed = 0.0
	zurd.appetite_recheck = 1000.0
	zurd.anger.decay_rate = 0.0
	var spurned := spawn_object(OTHER, AREA + Vector3(30.0, 0.0, 0.0))
	await wait_seconds(1.0)
	check(zurd.get_target() == null, "set-up: the Passive Zurd decided against the object")
	zurd.anger.value = 1.0
	var hunted := await wait_until(func() -> bool: return zurd.is_hostile and zurd.get_target() == spurned, 2.0)
	check(hunted, "once Hostile, it goes after the object anyway")


# ==============================================================================
# EACH ZURD'S OWN ANGER
# ==============================================================================

func test_mess_angers_the_zurd_that_sees_it() -> void:
	await _setup()
	var near := _spawn_still_zurd(AREA)
	var far := _spawn_still_zurd(AREA + Vector3(0.0, 0.0, 400.0))
	near.anger.temper = 1.0
	near.anger.mess_anger = 0.3
	near.anger.decay_rate = 0.0
	var states := watch(EventBus.zurd_state_changed)
	var eaten := watch(EventBus.object_eaten)
	# Past what it tolerates in view, near the first Zurd and out of the second one's sight.
	for i in near.anger.tolerated_in_view + 3:
		spawn_object(OTHER, AREA + Vector3(-40.0 - (i % 3) * 12.0, 0.0, -30.0 + floorf(i / 3.0) * 12.0))
	await wait_seconds(0.5)
	check(near.anger.value > 0.0, "a Zurd that sees more mess than it tolerates gets angry")
	check_equal(far.anger.value, 0.0, "one that can't see it doesn't")
	check(near.is_hostile and not far.is_hostile, "past its hostile threshold, the first turns Hostile on its own")
	check(states.any(func(state: Array) -> bool: return state[0] == near and state[1] == true), "zurd_state_changed says so")
	var ate := await wait_until(func() -> bool: return eaten.any(func(event: Array) -> bool: return event[0] == near), 10.0)
	check(ate, "the Hostile Zurd goes after the loose objects and eats one")


func test_launches_hold_the_anger_of_zurds_that_see_them() -> void:
	await _setup()
	var watcher := _spawn_still_zurd(ship.global_position + Vector3(60.0, 0.0, 0.0))
	var elsewhere := _spawn_still_zurd(ship.global_position + Vector3(0.0, 0.0, 600.0))
	for zurd in [watcher, elsewhere]:
		zurd.anger.value = 0.5
	var dummy := RigidBody3D.new()
	# Launch for longer than the calm delay; the launched objects themselves don't matter here.
	for i in ceili(watcher.anger.calm_delay * 2.0 / 0.5):
		EventBus.object_launched.emit(dummy)
		await wait_seconds(0.5)
	dummy.free()
	check_near(watcher.anger.value, 0.5, 0.001, "a Zurd that sees the ship launch holds its anger, under its tolerance")
	check(elsewhere.anger.value < 0.5, "one out of sight of the ship calms as usual")


func test_hostile_zurds_calm_down_after_the_cooldown() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	zurd.hostile_cooldown = 2.0
	zurd.anger.decay_rate = 0.0
	zurd.anger.value = 1.0
	await wait_physics(2)
	check(zurd.is_hostile, "past its hostile threshold, the Zurd turns Hostile")
	zurd.anger.value = (zurd.anger.calm_threshold + zurd.anger.hostile_threshold) * 0.5
	await wait_seconds(zurd.hostile_cooldown + 0.5)
	check(zurd.is_hostile, "between the thresholds it stays Hostile")
	zurd.anger.value = 0.0
	await wait_physics(2)
	check(not zurd.is_hostile, "below the calm threshold, after the hostile cooldown, it turns Passive")


func test_calming_zurd_finishes_its_target_first() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	zurd.hostile_cooldown = 0.0
	zurd.anger.decay_rate = 0.0
	var food := spawn_object(OTHER, AREA + Vector3(40.0, 0.0, 0.0))
	zurd.anger.value = 1.0
	await wait_physics(3)
	check(zurd.is_hostile and zurd.get_target() == food, "set-up: a Hostile Zurd going after an object")
	zurd.anger.value = 0.0
	await wait_physics(3)
	check(zurd.is_hostile and zurd.is_calming, "calming down, it stays Hostile while it finishes its target")
	check(zurd.get_target() == food, "and keeps going after it")
	var ate := await wait_until_freed(food, 10.0)
	check(ate, "it eats its target")
	await wait_physics(30)
	check(not zurd.is_hostile and not zurd.is_calming, "then turns Passive")


# ==============================================================================
# HUNTING BY ROLE
# ==============================================================================

func test_hostile_shadow_goes_after_loose_objects_nearest_the_ship_then_large_sculptures() -> void:
	await _setup()
	director.tolerated_sculpture_size = 2
	var sculpture := await _make_sculpture(AREA + Vector3(0.0, 0.0, -40.0), 3)
	var shadow := _spawn_still_zurd(AREA, director.shadow_role)
	var near_shadow := spawn_object(OTHER, AREA + Vector3(20.0, 0.0, 0.0))
	var near_ship := spawn_object(OTHER, AREA + Vector3(-60.0, 0.0, 0.0))
	shadow.anger.decay_rate = 0.0
	shadow.anger.value = 1.0
	await wait_physics(3)
	check(shadow.is_hostile, "set-up: the Shadow is Hostile")
	check(shadow.get_target() == near_ship, "a Hostile Shadow goes after the loose object nearest the ship, not nearest itself")
	near_ship.queue_free()
	near_shadow.queue_free()
	await wait_physics(3)
	var target := shadow.get_target() as MassPiece
	check(target != null and target.mass == sculpture, "with no loose objects left, it goes after the sculpture over the size limit")
	director.tolerated_sculpture_size = 15
	await wait_physics(30)
	check(shadow.get_target() == null, "a sculpture under the size limit it leaves alone")


func test_hostile_grazer_clears_its_patch_sculptures_included() -> void:
	await _setup()
	var sculpture := await _make_sculpture(AREA + Vector3(0.0, 0.0, -40.0), 2)
	var grazer := _spawn_still_zurd(AREA)
	var loose := spawn_object(OTHER, AREA + Vector3(30.0, 0.0, 0.0))
	await wait_seconds(1.0)
	check(not (grazer.get_target() is MassPiece), "a Passive Grazer leaves sculptures alone")
	grazer.anger.decay_rate = 0.0
	grazer.anger.value = 1.0
	await wait_physics(3)
	check(grazer.get_target() == loose, "a Hostile Grazer goes after the loose objects in its patch first")
	loose.queue_free()
	await wait_physics(3)
	var target := grazer.get_target() as MassPiece
	check(target != null and target.mass == sculpture, "then a sculpture in its patch, of any size: it treats it like a loose object")


func test_hostile_zurd_reaches_food_right_beside_it() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	# Off to the side and close: at full speed its turning circle is wider than the gap.
	var food := spawn_object(OTHER, AREA + Vector3(8.0, 0.0, 0.0))
	zurd.anger.decay_rate = 0.0
	zurd.anger.value = 1.0
	var ate := await wait_until_freed(food, 8.0)
	check(ate, "a Hostile Zurd turns onto food right beside it and eats it, instead of circling it")


func test_one_zurd_per_target() -> void:
	await _setup()
	var first := _spawn_still_zurd(AREA)
	var second := _spawn_still_zurd(AREA + Vector3(40.0, 0.0, 0.0))
	var food := spawn_object(OTHER, AREA + Vector3(10.0, 0.0, 0.0))
	for zurd in [first, second]:
		zurd.anger.decay_rate = 0.0
		zurd.anger.value = 1.0
	await wait_physics(3)
	check(first.get_target() == food, "the nearer Zurd goes after the object")
	check(second.get_target() != food, "the other leaves it alone (it's claimed)")
	first.take_swat(Vector3.RIGHT * 10.0)
	var taken_over := await wait_until(func() -> bool: return second.get_target() == food, 1.0)
	check(taken_over, "when the first Zurd is swatted off it, the other may take it")


func test_zurds_share_a_sculpture_by_pieces() -> void:
	await _setup()
	var sculpture := await _make_sculpture(AREA + Vector3(0.0, 0.0, -40.0), 3)
	var first := _spawn_still_zurd(AREA)
	var second := _spawn_still_zurd(AREA + Vector3(20.0, 0.0, 0.0))
	for zurd in [first, second]:
		zurd.anger.decay_rate = 0.0
		zurd.anger.value = 1.0
	await wait_physics(3)
	var a := first.get_target() as MassPiece
	var b := second.get_target() as MassPiece
	check(a != null and b != null and a.mass == sculpture and b.mass == sculpture, "both Zurds go after the sculpture")
	check(a != b, "but after different pieces of it")


# ==============================================================================
# SENTINELS
# ==============================================================================

func test_only_sentinels_watch_sculptures() -> void:
	await _setup()
	var sculpture := await _make_sculpture(AREA + Vector3(0.0, 0.0, -60.0), 2)
	var parts := sculpture.get_part_count()
	var sentinel := director.spawn_zurd(AREA, director.sentinel_role)
	sentinel.home_sculpture = sculpture
	var grazer := director.spawn_zurd(AREA + Vector3(0.0, 0.0, -40.0))
	var watch_distance := sentinel.movement_component.watch_distance
	var closest := INF
	var ever_targeted := false
	for frame in 15 * Engine.physics_ticks_per_second:
		await get_tree().physics_frame
		closest = minf(closest, sentinel.global_position.distance_to(sculpture.get_global_center_of_mass()))
		ever_targeted = ever_targeted or sentinel.get_target() is MassPiece or grazer.get_target() is MassPiece
	check(closest <= watch_distance * 1.6, "a Sentinel comes to watch its sculpture (%.0f m away at closest)" % closest)
	check(not ever_targeted, "neither it nor a Passive Grazer nearby goes after the sculpture")
	check_equal(sculpture.get_part_count(), parts, "and none of it is eaten")


func test_a_sentinels_sculpture_growing_past_the_limit_angers_it() -> void:
	await _setup()
	director.tolerated_sculpture_size = 2
	var sculpture := await _make_sculpture(AREA, 2)
	var sentinel := _spawn_still_zurd(AREA + Vector3(0.0, 0.0, 40.0), director.sentinel_role)
	sentinel.home_sculpture = sculpture
	var grazer := _spawn_still_zurd(AREA + Vector3(0.0, 0.0, -40.0))
	await wait_physics(2)
	check_equal(sentinel.anger.value, 0.0, "a sculpture up to the size limit doesn't anger its Sentinel")
	await _add_to_sculpture(sculpture, THIRD)
	await wait_physics(2)
	check_near(sentinel.anger.value, sentinel.anger.sculpture_anger * sentinel.anger.temper, 0.0001, "each part past the limit does")
	check_equal(grazer.anger.value, 0.0, "a Grazer nearby isn't angered by one sculpture (one item of mess)")


func test_a_settled_sculpture_gets_one_sentinel() -> void:
	await _setup()
	director.settle_time = 1.0
	var near := director.spawn_zurd(AREA + Vector3(0.0, 0.0, 60.0), director.sentinel_role)
	var far := director.spawn_zurd(AREA + Vector3(0.0, 0.0, 300.0), director.sentinel_role)
	var sculpture := await _make_sculpture(AREA, 2)
	await wait_seconds(director.settle_time * 0.5)
	await _add_to_sculpture(sculpture, THIRD)
	await wait_seconds(director.settle_time * 0.7)
	director.update_sentinels()
	check(near.home_sculpture == null and far.home_sculpture == null, "a sculpture still being added to isn't settled: no Sentinel yet")
	await wait_seconds(director.settle_time * 0.5)
	director.update_sentinels()
	check(near.home_sculpture == sculpture, "once left alone for settle_time, the nearest free Sentinel takes it")
	check(far.home_sculpture == null, "and only that one")
	var arrived := await wait_until(func() -> bool: return near.global_position.distance_to(sculpture.get_global_center_of_mass()) <= near.movement_component.watch_distance * 1.6, 30.0)
	check(arrived, "it wanders over to watch it")


func test_a_new_sentinel_comes_when_all_are_busy_up_to_the_cap() -> void:
	await _setup()
	director.settle_time = 0.0
	director.sentinel_cap = 2
	var first := director.spawn_zurd(AREA, director.sentinel_role)
	var one := await _make_sculpture(AREA + Vector3(0.0, 0.0, -40.0), 2)
	var two := await _make_sculpture(AREA + Vector3(0.0, 0.0, 200.0), 2)
	var three := await _make_sculpture(AREA + Vector3(0.0, 0.0, 400.0), 2)
	await wait_physics(2)
	director.update_sentinels()
	var sentinels := director.get_zurds_with_role(director.sentinel_role)
	check_equal(sentinels.size(), director.sentinel_cap, "with every Sentinel busy, new ones come, up to the cap")
	var watched := sentinels.map(func(sentinel: Zurd) -> SculptureMass: return sentinel.home_sculpture)
	check(first.home_sculpture != null and watched.count(one) + watched.count(two) + watched.count(three) == director.sentinel_cap,
			"each watches a different settled sculpture; the one left over waits")
	check(sentinels.filter(func(sentinel: Zurd) -> bool: return sentinel.is_extra).size() == 1, "the newcomer is an extra")


func test_sentinels_leave_a_sculpture_that_becomes_a_cloud() -> void:
	await _setup()
	director.settle_time = 0.0
	var manager := get_mass_manager(world)
	manager.cloud_threshold_count = 3
	var sentinel := director.spawn_zurd(AREA + Vector3(0.0, 0.0, 60.0), director.sentinel_role)
	var extra := director.spawn_zurd(AREA + Vector3(0.0, 0.0, -60.0), director.sentinel_role)
	extra.is_extra = true
	var first := await _make_sculpture(AREA, 2)
	var second := await _make_sculpture(AREA + Vector3(0.0, 0.0, -100.0), 2)
	await wait_physics(2)
	sentinel.home_sculpture = first
	extra.home_sculpture = second
	await _add_to_sculpture(first, THIRD)
	await _add_to_sculpture(second, THIRD)
	check(first.is_cloud and second.is_cloud, "set-up: both sculptures became clouds")
	director.update_sentinels()
	check(sentinel.home_sculpture == null and sentinel.home_landmark != null, "a Sentinel whose sculpture became a cloud goes back to a landmark")
	check(extra.role == director.grazer_role and not extra.is_extra, "an extra Sentinel becomes a Grazer instead")


# ==============================================================================
# SWATS AND HITS
# ==============================================================================

func test_a_timid_zurd_flees_and_calms_after_one_swat() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	_set_boldness(zurd, 0.0)
	zurd.anger.value = 0.5
	var driven_off := watch(EventBus.zurd_driven_off)
	zurd.take_swat(Vector3.RIGHT * 10.0)
	check(zurd.is_driven_off(), "one swat drives a timid Zurd off")
	check_equal(driven_off.size(), 1, "zurd_driven_off fires")
	check_equal(zurd.anger.value, 0.0, "and it calms")
	var away := await wait_until(func() -> bool: return _ground_distance(zurd, ship) >= zurd.retreat_distance, 20.0)
	check(away, "it flies away from the ship, to retreat_distance")


func test_a_bold_zurd_takes_more_swats_and_gets_angrier() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	_set_boldness(zurd, 1.0)
	zurd.temperament.greed = 1.0
	zurd.away_time = 2.0
	check_equal(zurd.drive_off_swats, zurd.bold_swats.y, "the boldest Zurd takes the most swats")
	var stunned := watch(EventBus.zurd_stunned)
	var driven_off := watch(EventBus.zurd_driven_off)
	var food := spawn_object(SLAB, _in_mouth(zurd), SMALL)
	await wait_seconds(0.5)
	check(zurd.mouth_component.is_eating(), "set-up: the Zurd is nibbling")
	var angrier := true
	for swat in zurd.drive_off_swats - 1:
		var before := zurd.anger.value
		zurd.take_swat(Vector3.RIGHT * 10.0)
		angrier = angrier and zurd.anger.value > before
		check(zurd.is_stunned() and not zurd.is_driven_off(), "swat %d stuns the Zurd" % (swat + 1))
		check(not zurd.mouth_component.is_eating(), "and stops its bite")
		await wait_seconds(zurd.stun_time + 0.2)
	check(angrier, "each swat makes it angrier")
	check(is_instance_valid(food), "a bite cut short leaves the object whole")
	check_equal(stunned.size(), zurd.drive_off_swats - 1, "zurd_stunned fires for each stun")
	zurd.take_swat(Vector3.RIGHT * 10.0)
	check(zurd.is_driven_off(), "the last swat drives it off")
	check_equal(driven_off.size(), 1, "zurd_driven_off fires")
	check(not zurd.is_hostile and zurd.anger.value == 0.0, "it's Passive and calm while away")
	zurd.take_swat(Vector3.RIGHT * 10.0)
	check_equal(zurd.swats, zurd.drive_off_swats, "swats don't count while it's away")
	var back := await wait_until(func() -> bool: return not zurd.is_driven_off(), 20.0 + zurd.away_time)
	check(back, "after away_time it comes back")
	check_equal(zurd.swats, 0, "with its swats reset")


func test_one_swat_counts_once() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	_set_boldness(zurd, 1.0)
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


func test_launched_object_stuns_angers_then_gets_eaten() -> void:
	await _setup()
	var zurd := _spawn_still_zurd(AREA)
	var stunned := watch(EventBus.zurd_stunned)
	var eaten := watch(EventBus.object_eaten)
	var thrown := spawn_object(SLAB, AREA + Vector3(30.0, 0.0, 0.0), 0.5, Vector3(-30.0, 0.0, 0.0))
	var hit := await wait_until(func() -> bool: return not stunned.is_empty(), 3.0)
	check(hit, "a launched object flying into a Zurd stuns it")
	check_equal(zurd.swats, 0, "without counting as a swat")
	check(zurd.anger.value > 0.0, "it angers the Zurd it hit")
	var ate := await wait_until_freed(thrown, zurd.stun_time + 10.0)
	check(ate and eaten.any(func(event: Array) -> bool: return event[0] == zurd), "after the stun, the Zurd eats that object")


# ==============================================================================
# GETTING AROUND
# ==============================================================================

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


# ==============================================================================
# HELPERS
# ==============================================================================

## Loads the world, with its starting cast when [param with_zurds], and keeps the ship hovering where
## the Zurds are placed relative to it.
func _setup(with_zurds := false) -> void:
	world = await load_world(false, with_zurds)
	director = get_zurd_director(world)
	ship = get_ship(world)
	if not with_zurds:
		ship.global_position = Vector3(0.0, 100.0, 0.0)


## A Zurd of [param role] (a Grazer when null) at [param at] that doesn't wander (it still hunts, eats
## and retreats).
func _spawn_still_zurd(at: Vector3, role: ZurdRole = null) -> Zurd:
	var zurd := director.spawn_zurd(at, role)
	zurd.movement_component.wander_speed = 0.0
	return zurd


func _set_boldness(zurd: Zurd, boldness: float) -> void:
	zurd.temperament.boldness = boldness
	zurd.drive_off_swats = zurd.temperament.get_drive_off_swats(zurd.timid_below, zurd.bold_swats)


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
	return _ground_distance_to(a, b.global_position)


func _ground_distance_to(a: Node3D, point: Vector3) -> float:
	var offset := a.global_position - point
	return Vector2(offset.x, offset.z).length()


## How far (degrees) [param zurd] is off the ship's heading, seen from above.
func _bearing_from_ship(zurd: Node3D) -> float:
	var forward := -ship.global_basis.z
	var offset := zurd.global_position - ship.global_position
	return absf(rad_to_deg(Vector2(forward.x, forward.z).angle_to(Vector2(offset.x, offset.z))))
