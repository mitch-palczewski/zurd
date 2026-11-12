extends "res://tests/test_case.gd"

## ObjectParts: how many objects' worth a combined object holds, and its size (Sculpture-Mass
## Design Doc §4.10).

const VOLUMES := ObjectParts.SizeMode.ADD_VOLUMES
const SCALES := ObjectParts.SizeMode.ADD_SCALES


func test_combined_size_follows_the_mode() -> void:
	var by_volume := ObjectParts.new(3.0)
	by_volume.absorb(ObjectParts.new(4.0), VOLUMES)
	check_near(by_volume.get_size(), pow(3.0 ** 3 + 4.0 ** 3, 1.0 / 3.0), 0.001, "adding volumes: sizes 3 and 4 make ∛91 ≈ 4.5")
	var by_scale := ObjectParts.new(3.0)
	by_scale.absorb(ObjectParts.new(4.0), SCALES)
	check_near(by_scale.get_size(), 7.0, 0.001, "adding scales: sizes 3 and 4 make 7")


func test_absorb_adds_parts_oldest_first() -> void:
	var keeper := ObjectParts.new(2.0, 1.5)
	var other := ObjectParts.new(3.0, 1.5)
	other.absorb(ObjectParts.new(1.0, 1.5), SCALES)
	keeper.absorb(other, SCALES)
	check_equal(keeper.count(), 3, "a combined object counts every part it took in")
	check_equal(Array(keeper.scales), [2.0, 3.0, 1.0], "parts are kept oldest first")
	check_near(keeper.get_size(), 6.0, 0.001, "the size grows with each part in turn")
	check_near(keeper.get_mass(), 4.5, 0.001, "weight is one part's weight per part, whatever the sizes")


func test_remove_last_returns_to_the_earlier_size() -> void:
	var parts := ObjectParts.new(2.5)
	parts.absorb(ObjectParts.new(1.7), VOLUMES)
	var after_one := parts.get_size()
	# The mode may change between combines; a bite still steps back exactly.
	parts.absorb(ObjectParts.new(3.1), SCALES)
	parts.remove_last()
	check_equal(parts.get_size(), after_one, "a bite restores the exact size from before the last part joined")
	parts.remove_last()
	check_equal(parts.get_size(), 2.5, "and again, back to the first part's size")
	parts.remove_last()
	check_equal(parts.count(), 1, "the last part can't be removed (the object itself goes instead)")


func test_bigger_object_has_more_parts_then_larger_size() -> void:
	var small_pair := ObjectParts.new(1.0)
	small_pair.absorb(ObjectParts.new(1.0), VOLUMES)
	var big_single := ObjectParts.new(5.0)
	check(small_pair.is_bigger_than(big_single), "more parts wins over a larger size")
	check(not big_single.is_bigger_than(small_pair), "and not the other way round")
	check(ObjectParts.new(3.0).is_bigger_than(ObjectParts.new(2.0)), "with equal parts, the larger size wins")
	check(not ObjectParts.new(2.0).is_bigger_than(ObjectParts.new(2.0)), "equal objects: neither is bigger")


func test_of_builds_a_record_from_the_shape_scale() -> void:
	var body := RigidBody3D.new()
	body.mass = 2.0
	var shape := CollisionShape3D.new()
	shape.scale = Vector3.ONE * 3.0
	body.add_child(shape)
	var parts := ObjectParts.of(body)
	check_near(parts.get_size(), 3.0, 0.0001, "a body's size is its collision shape's scale")
	check_near(parts.part_mass, 2.0, 0.0001, "one part weighs what the body weighs")
	check_equal(parts.count(), 1, "a plain body is one part")
	check(body.get_meta(ObjectParts.META) == parts, "the record is kept on the body")
	check(ObjectParts.of(body) == parts, "asking again returns the same record")
	body.free()


func test_resize_children_scales_positions_too() -> void:
	var body := Node3D.new()
	var child := Node3D.new()
	child.position = Vector3(1.0, 0.0, 0.0)
	child.basis = Basis(Vector3.UP, 0.5) * 2.0
	body.add_child(child)
	ObjectParts.resize_children(body, 2.0, 4.0)
	check_near(child.position, Vector3(2.0, 0.0, 0.0), 0.0001, "an off-centre child moves out with the size")
	check_near(child.basis.get_scale().x, 4.0, 0.0001, "and takes the new size")
	check_near(child.basis.get_euler().y, 0.5, 0.0001, "keeping its rotation")
	body.free()
