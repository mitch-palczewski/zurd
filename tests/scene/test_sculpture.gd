extends "res://tests/test_case.gd"

## Sculpture masses in the game world (Sculpture-Mass Design Doc): fusing, combining, merging,
## growth break-off, bites, breaking off and clouds. Contacts are made by emitting the bodies'
## contact signals, as the physics engine does, so every case is exact; one test uses real
## collisions. Objects sit high above the ship, in a world without terrain.

const AREA := Vector3(0.0, 100.0, 300.0)
## A box-shaped slab, 4.8 × 3 × 0.7 m.
const SLAB := "res://scenes/objects/rigid/GEO_Stock_07_rigid.tscn"
const OTHER := "res://scenes/objects/rigid/GEO_Stock_06_rigid.tscn"
const THIRD := "res://scenes/objects/rigid/GEO_Stock_05_rigid.tscn"
## Far enough apart that a fused slab can grow without reaching its neighbour.
const CLEAR_GAP := 6.0

var world: Node3D
var manager: MassManager
## Every object_fused emission: [mass, piece].
var fused: Array


func before_each() -> void:
	world = await load_world(false)
	manager = get_mass_manager(world)
	fused = watch(EventBus.object_fused)


func test_hits_fuse_two_objects_into_a_mass() -> void:
	var a := spawn_object(SLAB, AREA)
	var b := spawn_beside(OTHER, a, Vector3.RIGHT)
	var hits := watch(EventBus.object_hit)
	a.body_entered.emit(get_ship(world))
	await wait_physics(2)
	check(hits.is_empty(), "bumping the ship doesn't count as a hit")
	_hit(a, b, manager.hits_to_fuse - 1)
	await wait_physics(2)
	check(is_instance_valid(a) and fused.is_empty(), "below the hit count (%d), nothing fuses" % manager.hits_to_fuse)
	_hit(a, b, 1)
	await wait_physics(2)
	check(not is_instance_valid(a) and not is_instance_valid(b), "at the hit count, both loose bodies are replaced")
	check_equal(hits.size(), manager.hits_to_fuse, "every counted hit fires object_hit")
	check_equal(fused.size(), 2, "both objects fuse")
	var mass: SculptureMass = fused[0][0]
	check_equal(mass.pieces.size(), 2, "into one new mass")
	check_near(mass.mass, 2 * manager.object_mass, 0.001, "a mass weighs object_mass per object")
	check(mass.pieces[0].neighbors.has(mass.pieces[1]), "the two fused objects are linked")
	for piece in mass.pieces:
		check(ObjectTracker.active_objects.has(piece), "fused objects stay Zurd targets")


func test_object_hitting_a_mass_fuses_into_it() -> void:
	var mass := await _make_mass(AREA, SLAB, OTHER)
	var third := spawn_beside(THIRD, mass, Vector3.UP)
	_touch(third, mass, _piece_of(mass, SLAB))
	_hit(third, mass)
	await wait_physics(2)
	check(not is_instance_valid(third), "the object left its loose body")
	check_equal(mass.pieces.size(), 3, "and joined the mass it hit")
	check(_piece_of(mass, THIRD).neighbors.has(_piece_of(mass, SLAB)), "linked to the object it hit")


func test_matching_loose_objects_combine() -> void:
	var small := spawn_object(SLAB, AREA, 2.0)
	var big := spawn_beside(SLAB, small, Vector3.RIGHT, 0.1, 3.0)
	var combined := watch(EventBus.objects_combined)
	var resized := watch(EventBus.object_resized)
	_hit(small, big)
	await wait_physics(2)
	check(fused.is_empty(), "matching objects don't start a mass")
	check(not is_instance_valid(small) and is_instance_valid(big), "the bigger object stays and takes the other in")
	var expected := ObjectParts.new(3.0)
	expected.absorb(ObjectParts.new(2.0), manager.combine_size_mode)
	var parts := ObjectParts.of(big)
	check_equal(parts.count(), 2, "it holds both parts")
	check_near(parts.get_size(), expected.get_size(), 0.0001, "it grows by the manager's size mode")
	check_near(_shape_scale(big), expected.get_size(), 0.0001, "its collider grows at once")
	check_near(big.mass, parts.get_mass(), 0.0001, "it weighs both parts")
	check(combined.size() == 1 and combined[0][0] == big and combined[0][1] == 1, "objects_combined names it and the one part it took in")
	check(resized.size() == 1 and is_equal_approx(resized[0][1], 3.0) and is_equal_approx(resized[0][2], expected.get_size()), "object_resized gives the old and new size")


func test_matching_object_combines_into_a_fused_object() -> void:
	var mass := await _make_mass(AREA, SLAB, OTHER)
	var slab := _piece_of(mass, SLAB)
	await _combine_into(slab)
	check_equal(mass.pieces.size(), 2, "the matching object doesn't fuse as a new piece")
	check_equal(slab.parts.count(), 2, "the fused object it hit takes it in")
	check_equal(mass.get_part_count(), 3, "the mass counts every part")
	check_near(mass.mass, 3 * manager.object_mass, 0.001, "and weighs every part")


func test_masses_merge_and_matching_objects_combine() -> void:
	var first := await _make_mass(AREA, SLAB, OTHER)
	var second := await _make_mass(AREA + Vector3(0.0, 0.0, 20.0), SLAB, THIRD)
	var first_slab := _piece_of(first, SLAB)
	var second_slab := _piece_of(second, SLAB)
	var merged := watch(EventBus.masses_merged)
	var combined := watch(EventBus.objects_combined)
	first.body_shape_entered.emit(second.get_rid(), second, _shape_index(second, second_slab), _shape_index(first, first_slab))
	await wait_physics(2)
	check(not is_instance_valid(second), "the absorbed mass is gone")
	check(merged.size() == 1 and merged[0][0] == first and merged[0][1] == 2, "masses_merged names the mass that stays and the 2 objects it took over")
	check_equal(first.get_part_count(), 4, "it holds every object")
	check_equal(combined.size(), 1, "the two slabs that touched combine")
	check_equal(first.pieces.size(), 3, "so there's one slab piece")
	check_equal(first_slab.parts.count(), 2, "holding both slabs")
	check(first_slab.neighbors.has(_piece_of(first, THIRD)), "it takes over the absorbed slab's links")


func test_growth_breaks_off_only_newly_overlapped_neighbours() -> void:
	manager.combine_size_mode = ObjectParts.SizeMode.ADD_SCALES
	# The slab will double in size.
	var slab := spawn_object(SLAB, AREA)
	var stays := spawn_beside(OTHER, slab, Vector3.DOWN, 2.0)
	_hit(slab, stays)
	await wait_physics(2)
	var mass: SculptureMass = fused[0][0]
	var slab_piece := _piece_of(mass, SLAB)
	var breaks := spawn_beside_box(THIRD, _piece_box(slab_piece), Vector3.RIGHT)
	_touch(breaks, mass, slab_piece)
	_hit(breaks, mass)
	await wait_physics(2)
	check_equal(mass.pieces.size(), 3, "set-up: three fused objects")

	var broken_off := watch(EventBus.objects_broken_off)
	await _combine_into(slab_piece)
	check_equal(slab_piece.parts.count(), 2, "the slab grew")
	check(broken_off.size() == 1 and broken_off[0][0] == mass, "objects_broken_off names the mass")
	var bodies: Array = broken_off[0][1] if not broken_off.is_empty() else []
	check(bodies.size() == 1 and bodies[0].scene_file_path == THIRD, "the neighbour it grew into breaks off, and only that one")
	check(_piece_of(mass, THIRD) == null, "it left the mass")
	check(_piece_of(mass, OTHER) != null, "the neighbour it didn't reach stays")
	if bodies.size() == 1 and manager.detach_speed > 0.0:
		check(bodies[0].linear_velocity.x > 0.0, "the broken-off object is pushed away from the slab")


func test_bites_on_loose_objects() -> void:
	var eater := Node3D.new()
	add_child(eater)
	var eaten := watch(EventBus.object_eaten)
	var single := spawn_object(OTHER, AREA + Vector3(0.0, 0.0, -20.0))
	EventBus.eat_requested.emit(eater, single)
	await wait_physics(2)
	check(not is_instance_valid(single), "a one-part loose object is eaten whole")
	check(eaten.size() == 1 and eaten[0][0] == eater and eaten[0][2] == null, "object_eaten names the eater, and no mass")

	var small := spawn_object(SLAB, AREA, 2.0)
	var big := spawn_beside(SLAB, small, Vector3.RIGHT, 0.1, 3.0)
	_hit(small, big)
	await wait_physics(2)
	var parts := ObjectParts.of(big)
	EventBus.eat_requested.emit(eater, big)
	await wait_physics(2)
	check(is_instance_valid(big), "a combined object loses one part and stays")
	check_equal(parts.count(), 1, "one part is left")
	check_near(parts.get_size(), 3.0, 0.0001, "it's back to its size before the last part joined")
	check_near(_shape_scale(big), 3.0, 0.0001, "and so is its collider")
	check_near(big.mass, parts.get_mass(), 0.0001, "and its weight")
	EventBus.eat_requested.emit(eater, big)
	await wait_physics(2)
	check(not is_instance_valid(big), "the last bite takes the object")
	eater.free()


func test_bites_on_a_fused_object() -> void:
	var eater := Node3D.new()
	add_child(eater)
	var mass := await _make_mass(AREA, SLAB, OTHER)
	var slab := _piece_of(mass, SLAB)
	await _combine_into(slab)
	await _combine_into(slab)
	check_equal(slab.parts.count(), 3, "set-up: a fused object of 3 parts")
	var links := slab.neighbors.keys()
	var eaten := watch(EventBus.object_eaten)

	for left in [2, 1]:
		EventBus.eat_requested.emit(eater, slab)
		await wait_physics(2)
		check_equal(slab.parts.count(), left, "a bite takes one part (%d left)" % left)
		check_equal(mass.get_part_count(), left + 1, "the mass count drops with it")
		check_equal(slab.neighbors.keys(), links, "the fused object keeps its links")
	check(eaten.size() == 2 and eaten[0][1] == slab and eaten[0][2] == mass, "object_eaten names the fused object and its mass")

	EventBus.eat_requested.emit(eater, slab)
	await wait_physics(2)
	check(not is_instance_valid(slab), "the last bite takes the whole object")
	check(not is_instance_valid(mass), "the one object left can't be a mass, so the mass ends")
	check(_tracked_bodies(OTHER).size() == 1, "and the object left becomes loose again")
	eater.free()


func test_breaking_off_keeps_parts_and_group() -> void:
	var a := spawn_object(SLAB, AREA)
	a.set_meta(ObjectCatalog.GROUP_META, &"Geometry")
	var b := spawn_beside(OTHER, a, Vector3.DOWN, CLEAR_GAP)
	_hit(a, b)
	await wait_physics(2)
	var mass: SculptureMass = fused[0][0]
	var slab := _piece_of(mass, SLAB)
	check_equal(ObjectCatalog.group_of(slab), &"Geometry", "a fused object keeps its catalog group")
	await _combine_into(slab)
	var size := slab.parts.get_size()

	var broken_off := watch(EventBus.objects_broken_off)
	mass.request_break_off(slab.shapes[0])
	await wait_physics(3)
	var loose: RigidBody3D = null
	for body in (broken_off[0][1] if not broken_off.is_empty() else []):
		if body.scene_file_path == SLAB:
			loose = body
	if not check(loose != null, "the hit object breaks off as a loose object"):
		return
	var parts := ObjectParts.of(loose)
	check_equal(parts.count(), 2, "it keeps both parts")
	check_near(parts.get_size(), size, 0.0001, "and its size")
	check_near(_shape_scale(loose), size, 0.0001, "its collider is that size")
	check_near(loose.mass, parts.get_mass(), 0.0001, "it weighs both parts")
	check_equal(ObjectCatalog.group_of(loose), &"Geometry", "it keeps its catalog group")
	check(ObjectTracker.active_objects.has(loose), "it's a Zurd target again")
	if manager.refuse_delay > 0.0:
		var hits := watch(EventBus.object_hit)
		var other := _tracked_bodies(OTHER)
		if check(other.size() == 1, "the one object left became loose too"):
			loose.body_entered.emit(other[0])
			check(hits.is_empty(), "right after breaking off, its hits don't count (refuse delay)")


func test_cloud_counts_parts() -> void:
	manager.cloud_threshold_count = 4
	var formed := watch(EventBus.cloud_formed)
	var mass := await _make_mass(AREA, SLAB, OTHER)
	await _combine_into(_piece_of(mass, SLAB))
	check(not mass.is_cloud, "3 parts of 4: not a cloud yet")
	check_near(mass.cloud_progress, 0.75, 0.0001, "cloud progress counts parts, not fused objects")
	var third := spawn_beside(THIRD, mass, Vector3.UP, CLEAR_GAP)
	_hit(third, mass)
	await wait_physics(2)
	check(mass.is_cloud, "at the threshold (by parts, with only 3 fused objects) the mass becomes a cloud")
	check_equal(formed.size(), 1, "cloud_formed fires")
	check_equal(mass.collision_layer, 0, "a cloud stops colliding")
	for piece in mass.pieces:
		check(not ObjectTracker.is_trackable(piece), "a cloud's objects are no longer Zurd targets")
	var late := spawn_beside(OTHER, mass, Vector3.UP, CLEAR_GAP * 3.0)
	_hit(late, mass)
	await wait_physics(2)
	check(is_instance_valid(late) and mass.pieces.size() == 3, "a cloud takes no new objects")


func test_hits_in_the_same_frame_follow_what_objects_became() -> void:
	var middle := spawn_object(SLAB, AREA)
	var left := spawn_beside(OTHER, middle, Vector3.LEFT)
	var right := spawn_beside(THIRD, middle, Vector3.RIGHT)
	# Both reach the hit count in the same frame: the second fuse finds the middle object already fused.
	_hit(left, middle)
	_hit(right, middle)
	await wait_physics(2)
	check(not is_instance_valid(left) and not is_instance_valid(middle) and not is_instance_valid(right), "all three objects fused")
	var masses := {}
	for event in fused:
		masses[event[0]] = true
	check_equal(masses.size(), 1, "into one mass")
	check_equal(fused.size(), 3, "three fuses")


func test_real_collisions_fuse_objects() -> void:
	manager.hits_to_fuse = 1
	spawn_object(SLAB, AREA + Vector3(-5.0, 0.0, 0.0), 1.0, Vector3(4.0, 0.0, 0.0))
	spawn_object(OTHER, AREA + Vector3(5.0, 0.0, 0.0), 1.0, Vector3(-4.0, 0.0, 0.0))
	var met := await wait_until(func() -> bool: return fused.size() >= 2, 5.0)
	check(met, "two objects flown into each other fuse on contact")


## Emits [param body]'s contact signal [param times] times (default: the hit count), as physics does
## when it touches [param other].
func _hit(body: RigidBody3D, other: Node, times := -1) -> void:
	for i in (manager.hits_to_fuse if times < 0 else times):
		body.body_entered.emit(other)


## Emits the shape contact physics reports when [param body] touches [param piece] of [param mass].
func _touch(body: RigidBody3D, mass: SculptureMass, piece: MassPiece) -> void:
	body.body_shape_entered.emit(mass.get_rid(), mass, _shape_index(mass, piece), 0)


## A mass of two objects, [param first] at [param at] with [param second] below it, apart enough
## for the first to grow.
func _make_mass(at: Vector3, first: String, second: String) -> SculptureMass:
	var a := spawn_object(first, at)
	var b := spawn_beside(second, a, Vector3.DOWN, CLEAR_GAP)
	_hit(a, b)
	await wait_physics(2)
	return fused[-1][0] as SculptureMass


## Fires a loose copy of [param piece]'s object into it, so it combines.
func _combine_into(piece: MassPiece) -> void:
	var mass := piece.mass
	var loose := spawn_object(piece.source_scene_path, mass.global_position + Vector3(0.0, 0.0, 30.0))
	_touch(loose, mass, piece)
	_hit(loose, mass)
	await wait_physics(2)


func _shape_index(mass: SculptureMass, piece: MassPiece) -> int:
	for i in PhysicsServer3D.body_get_shape_count(mass.get_rid()):
		if mass.get_piece_for_shape_index(i) == piece:
			return i
	return -1


func _piece_of(mass: SculptureMass, path: String) -> MassPiece:
	for piece in mass.pieces:
		if piece.source_scene_path == path:
			return piece
	return null


## The box around [param piece]'s collision shapes, in global space.
func _piece_box(piece: MassPiece) -> AABB:
	var box := AABB()
	for i in piece.shapes.size():
		var shape := piece.shapes[i]
		var shape_box := shape.global_transform * MassPiece.get_shape_bounds(shape.shape)
		box = shape_box if i == 0 else box.merge(shape_box)
	return box


func _shape_scale(body: RigidBody3D) -> float:
	for child in body.get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).scale.x
	return 0.0


## Loose bodies of the model [param path] that a Zurd could target.
func _tracked_bodies(path: String) -> Array[RigidBody3D]:
	var bodies: Array[RigidBody3D] = []
	for obj in ObjectTracker.active_objects:
		if obj is RigidBody3D and is_instance_valid(obj) and obj.scene_file_path == path:
			bodies.append(obj)
	return bodies
