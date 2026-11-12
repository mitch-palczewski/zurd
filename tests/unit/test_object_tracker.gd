extends "res://tests/test_case.gd"

## ObjectTracker: the list of everything a Zurd may target. Each test starts from an empty list and
## puts the old one back after.

var _saved: Array[Node3D] = []


func before_each() -> void:
	_saved.assign(ObjectTracker.active_objects)
	ObjectTracker.active_objects.clear()


func after_each() -> void:
	ObjectTracker.active_objects.assign(_saved)


func test_register_once_and_unregister() -> void:
	var registered := watch(ObjectTracker.object_registered)
	var obj := _add(Vector3.ZERO)
	ObjectTracker.register_object(obj)
	ObjectTracker.register_object(obj)
	check_equal(ObjectTracker.active_objects.count(obj), 1, "an object is tracked once, however often it registers")
	check_equal(registered.size(), 1, "object_registered fires once")
	ObjectTracker.unregister_object(obj)
	check(not ObjectTracker.active_objects.has(obj), "unregister stops tracking it")


func test_objects_leaving_the_tree_drop_out() -> void:
	var obj := _add(Vector3.ZERO)
	ObjectTracker.register_object(obj)
	obj.free()
	check(ObjectTracker.active_objects.is_empty(), "a freed object is dropped at once")


func test_trackable() -> void:
	var obj := _add(Vector3.ZERO)
	check(ObjectTracker.is_trackable(obj), "an object in the tree is trackable")
	check(not ObjectTracker.is_trackable(null), "null isn't")
	var outside := Node3D.new()
	check(not ObjectTracker.is_trackable(outside), "an object outside the tree isn't")
	outside.free()
	check(not ObjectTracker.is_trackable(outside), "a freed object isn't")
	var leaving := _add(Vector3.ZERO)
	leaving.queue_free()
	check(not ObjectTracker.is_trackable(leaving), "an object about to be freed isn't")

	var mass := SculptureMass.new()
	var piece := MassPiece.new()
	piece.mass = mass
	add_child(piece)
	check(ObjectTracker.is_trackable(piece), "a fused object is trackable")
	mass.is_cloud = true
	check(not ObjectTracker.is_trackable(piece), "a fused object of a cloud isn't (Design Doc §4.5)")
	piece.free()
	mass.free()


func test_closest_and_random() -> void:
	check(ObjectTracker.get_closest_object(Vector3.ZERO) == null, "nothing tracked: no closest object")
	check(ObjectTracker.get_random_object() == null, "nothing tracked: no random object")
	var far := _add(Vector3(10, 0, 0))
	var near := _add(Vector3(2, 0, 0))
	var behind := _add(Vector3(-5, 0, 0))
	for obj in [far, near, behind]:
		ObjectTracker.register_object(obj)
	check(ObjectTracker.get_closest_object(Vector3.ZERO) == near, "the closest object to the origin")
	check(ObjectTracker.get_closest_object(Vector3(-4, 0, 0)) == behind, "the closest object to another point")
	near.queue_free()
	far.queue_free()
	var only_behind := true
	for i in 20:
		only_behind = only_behind and ObjectTracker.get_random_object() == behind
	check(only_behind, "random picks skip objects that can't be targeted any more")


func _add(at: Vector3) -> Node3D:
	var obj := Node3D.new()
	add_child(obj)
	obj.global_position = at
	return obj
