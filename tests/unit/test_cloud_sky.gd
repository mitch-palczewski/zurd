extends "res://tests/test_case.gd"

## The cloud sky (Cloud-Formation Design Doc §4): how a cloud rises, circles in the gyre, keeps its
## distance and lives, stepped by hand on bare cloud states without a world; and the puffs and
## wisps that dress a cloud. How it all looks is checked by eye.

const SkyScript := preload("res://scenes/sculpture/cloud_sky.gd")
const Puffs := preload("res://scenes/sculpture/cloud_puffs.gd")
const Wisps := preload("res://scenes/sculpture/cloud_wisps.gd")
## Seconds per step when running the sky by hand.
const STEP := 0.5


## Steps [param sky] on by [param seconds].
func _run(sky: Node, seconds: float, step := STEP) -> void:
	var done := 0.0
	while done < seconds - 0.000001:
		var delta := minf(step, seconds - done)
		sky.step(delta)
		done += delta


func _ring_of(sky: Node, point: Vector3) -> float:
	return Vector2(point.x, point.z).distance_to(sky.gyre_center)


func _in_zone(sky: Node, point: Vector3) -> bool:
	var ring := _ring_of(sky, point)
	return ring >= sky.gyre_radius_range.x - 0.01 and ring <= sky.gyre_radius_range.y + 0.01 \
			and point.y >= sky.zone_heights.x - sky.bob_height - 0.01 and point.y <= sky.zone_heights.y + sky.bob_height + 0.01


func test_inner_rings_turn_faster() -> void:
	var sky: Node = SkyScript.new()
	var inner: float = sky.gyre_radius_range.x
	var outer: float = sky.gyre_radius_range.y
	check_near(sky.get_angular_speed((inner + outer) * 0.5), TAU / sky.gyre_lap_time, 0.000001, "the middle ring laps in gyre_lap_time")
	sky.gyre_shear = 1.0
	check(sky.get_angular_speed(inner) > sky.get_angular_speed(outer), "inner rings turn faster than outer ones, so clouds pass one another")
	check_near(sky.get_angular_speed(inner) * inner, sky.get_angular_speed(outer) * outer, 0.0001, "with a shear of 1, every ring moves at the same metres per second")
	sky.gyre_shear = 0.0
	check_near(sky.get_angular_speed(inner), sky.get_angular_speed(outer), 0.000001, "with no shear the whole sky turns like a wheel")
	sky.free()


func test_a_new_cloud_holds_then_rises_out_and_up_while_growing() -> void:
	var sky: Node = SkyScript.new()
	var start := Vector3(100.0, 40.0, 50.0)
	var cloud: Variant = sky.add_cloud(start, 10.0)
	_run(sky, sky.rise_delay * 0.9)
	check(cloud.center.is_equal_approx(start), "it holds still for rise_delay")
	check_near(cloud.size, 1.0, 0.000001, "at its own size")

	_run(sky, sky.rise_delay * 0.1 + sky.rise_time * 0.5)
	var home: Vector3 = sky.get_orbit_point(cloud)
	var out := Vector2(cloud.center.x - start.x, cloud.center.z - start.z).length() / Vector2(home.x - start.x, home.z - start.z).length()
	var up: float = (cloud.center.y - start.y) / (home.y - start.y)
	check(out > up, "halfway, it has glided further out than it has climbed: an arc, not straight up")
	check(_ring_of(sky, cloud.center) > _ring_of(sky, start), "it moves outward, away from the gyre centre")
	check(cloud.growth > 1.0 and cloud.growth < sky.scale_multiplier, "it grows while it rises")

	_run(sky, sky.rise_time * 0.5)
	check(_in_zone(sky, cloud.center), "it arrives on its ring, in the cloud zone")
	check_near(cloud.growth, sky.scale_multiplier, 0.0001, "grown to scale_multiplier times its size")
	check(absf(cloud.size / cloud.growth - 1.0) <= sky.breath + 0.000001, "breathing by at most breath")
	sky.free()


func test_clouds_stay_on_the_gyre_and_in_the_zone() -> void:
	var sky: Node = SkyScript.new()
	for i in 12:
		sky.add_cloud(Vector3(randf_range(-600.0, 600.0), 20.0, randf_range(-600.0, 600.0)), randf_range(5.0, 40.0))
	_run(sky, sky.rise_delay + sky.rise_time)
	var left := false
	# Two laps of the middle ring, in big steps.
	for i in ceili(sky.gyre_lap_time * 2.0 / 5.0):
		sky.step(5.0)
		for cloud: Variant in sky.clouds:
			left = left or not _in_zone(sky, cloud.center)
	check(not left, "no cloud ever leaves its gyre ring or the cloud zone")
	sky.free()


func test_overlapping_clouds_part_and_stay_apart() -> void:
	var sky: Node = SkyScript.new()
	# Same angular speed for every ring: without the push they'd stay overlapped for good.
	sky.gyre_shear = 0.0
	var a: Variant = sky.add_cloud(Vector3(500.0, 0.0, 0.0), 30.0)
	var b: Variant = sky.add_cloud(Vector3(500.0, 0.0, 0.0), 30.0)
	for cloud: Variant in [a, b]:
		cloud.ring = 2000.0
		cloud.height = 1200.0
		cloud.angle = 0.0
	b.angle = 0.001
	_run(sky, sky.rise_delay + sky.rise_time)
	var reach: float = a.radius * a.size + b.radius * b.size
	if not check(a.center.distance_to(b.center) < reach, "set-up: both arrive in the same spot"):
		sky.free()
		return
	# Parting at its slowest, each moves at MIN_PUSH × push_speed.
	var limit: float = reach / (2.0 * sky.push_speed * SkyScript.MIN_PUSH) + 10.0
	var waited := 0.0
	while waited < limit and a.center.distance_to(b.center) < a.radius * a.size + b.radius * b.size:
		sky.step(STEP)
		waited += STEP
	check(waited < limit, "they part")
	# Their bobs and breathing may bring them back into one another for a moment; it never lasts.
	var longest := 0.0
	var overlapping_for := 0.0
	for i in ceili(600.0 / STEP):
		sky.step(STEP)
		var overlapping: bool = a.center.distance_to(b.center) < a.radius * a.size + b.radius * b.size
		overlapping_for = overlapping_for + STEP if overlapping else 0.0
		longest = maxf(longest, overlapping_for)
	check(longest < 60.0, "and they don't stay overlapped afterwards")
	sky.free()


func test_the_tumble_is_a_slow_pure_rotation() -> void:
	var sky: Node = SkyScript.new()
	var cloud: Variant = sky.add_cloud(Vector3.ZERO, 10.0)
	_run(sky, sky.rise_delay + sky.rise_time + sky.tumble_period * 0.25)
	check(cloud.tumble.is_normalized(), "the tumble stays a pure rotation")
	check(not cloud.tumble.is_equal_approx(Quaternion.IDENTITY), "and keeps turning")
	sky.free()


func test_puffs_sit_on_their_object() -> void:
	var piece := Node3D.new()
	add_child(piece)
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(4.0, 2.0, 6.0)
	box.mesh = box_mesh
	box.position = Vector3(1.0, 2.0, 3.0)
	piece.add_child(box)
	var puffs: Node = Puffs.new()
	piece.add_child(puffs)
	var meshes: Array[MeshInstance3D] = [box]
	puffs.build(meshes, 20, Vector2(0.1, 0.2), SphereMesh.new(), StandardMaterial3D.new(), RandomNumberGenerator.new())
	if not check_equal(puffs.multimesh.instance_count, 20, "the asked-for number of puffs") or puffs.placements.size() != 20:
		piece.queue_free()
		return
	var bounds := AABB(box.position - box_mesh.size * 0.5, box_mesh.size)
	var placed := true
	for i in 20:
		var puff: Transform3D = puffs.placements[i]
		var radius := puff.basis.x.length()
		var inside := puff.origin - bounds.position
		var to_surface := minf(minf(minf(inside.x, inside.y), inside.z), minf(minf(bounds.size.x - inside.x, bounds.size.y - inside.y), bounds.size.z - inside.z))
		placed = placed and to_surface >= -0.001 and to_surface <= radius * Puffs.INSET + 0.001
	check(placed, "every puff is half sunk into the object's surface, on the outside of it")
	piece.queue_free()


func test_wisps_come_and_go() -> void:
	var wisps: Node = Wisps.new()
	add_child(wisps)
	wisps.setup(5, 20.0, SphereMesh.new(), StandardMaterial3D.new(), RandomNumberGenerator.new())
	check_equal(wisps.multimesh.instance_count, 5 * Wisps.PUFFS_PER_WISP, "a few puffs per wisp")
	check_equal(wisps.get_visible_count(), 0, "none show at first: they trickle in")
	var appeared := {}
	var went := {}
	var most := 0
	for i in 600:
		wisps.advance(1.0)
		most = maxi(most, wisps.get_visible_count())
		for slot in 5:
			if wisps.get_visibility(slot) > 0.0:
				appeared[slot] = true
			elif appeared.has(slot):
				went[slot] = true
	check(most <= 5, "never more than its count show at once")
	check(appeared.size() == 5 and went.size() == 5, "every wisp appears and melts away again")
	wisps.queue_free()
