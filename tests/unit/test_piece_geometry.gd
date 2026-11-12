extends "res://tests/test_case.gd"

## The geometry growth break-off runs on (Sculpture-Mass Design Doc §4.10): get_shape_bounds turns
## each box or convex hull into a box, get_boxes places those boxes at a size, and get_overlap /
## get_box_overlap measure how far two pieces push into each other.

var _holders: Array[Node] = []


func after_each() -> void:
	for holder in _holders:
		holder.free()
	_holders.clear()


func test_shape_bounds_of_box_hull_and_other_shapes() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 4.0, 6.0)
	var box_bounds := MassPiece.get_shape_bounds(box)
	check_near(box_bounds.get_center(), Vector3.ZERO, 0.0001, "a box is centred on its shape")
	check_near(box_bounds.size, Vector3(2.0, 4.0, 6.0), 0.0001, "and is its own bounds")

	var hull_bounds := MassPiece.get_shape_bounds(_make_hull(Vector3(-1, -1, -1), Vector3(3, 1, 1)))
	check_near(hull_bounds.position, Vector3(-1.0, -1.0, -1.0), 0.0001, "a convex hull's bounds start at its lowest point")
	check_near(hull_bounds.size, Vector3(4.0, 2.0, 2.0), 0.0001, "and span all its points")

	check(not MassPiece.get_shape_bounds(SphereShape3D.new()).has_volume(), "other shapes have no bounds, so they're left out")
	check(not MassPiece.get_shape_bounds(ConvexPolygonShape3D.new()).has_volume(), "nor does an empty hull")


func test_boxes_scale_around_the_piece() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 4.0, 6.0)
	var piece := _make_piece([box], [Vector3(3.0, 0.0, 0.0)])

	var at_size := piece.get_boxes(1.0)
	check_equal(at_size.size(), 1, "one box per shape")
	check_near(at_size[0].origin, Vector3(3.0, 0.0, 0.0), 0.0001, "at the piece's size, a box sits where its shape is")
	check_near(at_size[0].basis.get_scale(), Vector3(1.0, 2.0, 3.0), 0.0001, "its basis reaches to the faces (half the size)")

	var doubled := piece.get_boxes(2.0)
	check_near(doubled[0].origin, Vector3(6.0, 0.0, 0.0), 0.0001, "at twice the size, an off-centre box moves out from the piece's origin")
	check_near(doubled[0].basis.get_scale(), Vector3(2.0, 4.0, 6.0), 0.0001, "and doubles")


func test_boxes_of_hulls_and_shapes_without_volume() -> void:
	var piece := _make_piece([_make_hull(Vector3(-1, -1, -1), Vector3(3, 1, 1)), SphereShape3D.new()], [Vector3.ZERO, Vector3.ZERO])
	var boxes := piece.get_boxes(1.0)
	check_equal(boxes.size(), 1, "the sphere is left out")
	check_near(boxes[0].origin, Vector3(1.0, 0.0, 0.0), 0.0001, "a hull is measured by the box around it")
	check_near(boxes[0].basis.get_scale(), Vector3(2.0, 1.0, 1.0), 0.0001, "and that box's half size")


func test_box_overlap_apart_touching_and_overlapping() -> void:
	var unit := Basis.from_scale(Vector3.ONE)
	var a := Transform3D(unit, Vector3.ZERO)
	check_near(MassPiece.get_box_overlap(a, Transform3D(unit, Vector3(3.0, 0, 0))), -1.0, 0.0001, "boxes 1 m apart: -1")
	check_near(MassPiece.get_box_overlap(a, Transform3D(unit, Vector3(2.0, 0, 0))), 0.0, 0.0001, "touching boxes: 0")
	check_near(MassPiece.get_box_overlap(a, Transform3D(unit, Vector3(1.5, 0, 0))), 0.5, 0.0001, "pushed 0.5 m into each other: 0.5")
	check_near(MassPiece.get_box_overlap(Transform3D(unit, Vector3(1.5, 0, 0)), a), 0.5, 0.0001, "the same either way round")


func test_box_overlap_of_rotated_boxes() -> void:
	var a := Transform3D(Basis.from_scale(Vector3.ONE), Vector3.ZERO)
	var turned := Basis(Vector3.UP, PI / 4.0)
	# A unit box turned 45° reaches √2 along x.
	check_near(MassPiece.get_box_overlap(a, Transform3D(turned, Vector3(2.0, 0, 0))), 1.0 + sqrt(2.0) - 2.0, 0.0001, "a turned box reaches further")
	check(MassPiece.get_box_overlap(a, Transform3D(turned, Vector3(2.5, 0, 0))) < 0.0, "and is apart once its corner clears")
	var parallel := Basis(Vector3.UP, PI / 2.0)
	check_near(MassPiece.get_box_overlap(a, Transform3D(parallel, Vector3(1.0, 0, 0))), 1.0, 0.0001, "boxes turned 90° have parallel edges and still measure")


func test_overlap_takes_the_deepest_pair() -> void:
	var unit := Basis.from_scale(Vector3.ONE)
	var a: Array[Transform3D] = [Transform3D(unit, Vector3.ZERO)]
	var b: Array[Transform3D] = [Transform3D(unit, Vector3(5.0, 0, 0)), Transform3D(unit, Vector3(1.5, 0, 0))]
	check_near(MassPiece.get_overlap(a, b), 0.5, 0.0001, "the deepest of every pair of boxes")
	var none: Array[Transform3D] = []
	check(MassPiece.get_overlap(a, none) < -1000.0, "no boxes: never overlapping")


func _make_hull(from: Vector3, to: Vector3) -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for x in [from.x, to.x]:
		for y in [from.y, to.y]:
			for z in [from.z, to.z]:
				points.append(Vector3(x, y, z))
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	return hull


## A piece of size 1 at the origin with [param shapes] at [param positions], under a plain node that
## stands in for its mass.
func _make_piece(shapes: Array, positions: Array) -> MassPiece:
	var holder := Node3D.new()
	add_child(holder)
	_holders.append(holder)
	var piece := MassPiece.new()
	piece.parts = ObjectParts.new(1.0)
	holder.add_child(piece)
	for i in shapes.size():
		var node := CollisionShape3D.new()
		node.shape = shapes[i]
		node.position = positions[i]
		holder.add_child(node)
		piece.add_shape(node)
	return piece
