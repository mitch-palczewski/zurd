class_name MassPiece
extends Node3D

## One object fused into a [SculptureMass] (Sculpture-Mass Design Doc §5). It sits where the loose
## body was and holds that body's visuals. Collision shapes must be direct children of the mass, so
## they live there and point back here through the [constant SHAPE_META] meta.

const SHAPE_META := &"mass_piece"

## The mass this piece belongs to.
var mass: SculptureMass
## This piece's collision shapes (children of [member mass]).
var shapes: Array[CollisionShape3D] = []
## Pieces this one was touching when it fused (Design Doc §4.8). Links always go both ways.
var neighbors: Dictionary[MassPiece, bool] = {}

## How many objects' worth this piece is, and its size (Design Doc §4.10).
var parts: ObjectParts

# What it takes to rebuild the loose body when the piece leaves the mass.
var source_scene_path: String = ""
var body_gravity_scale: float = 0.0
var body_linear_damp_mode: RigidBody3D.DampMode = RigidBody3D.DAMP_MODE_COMBINE
var body_linear_damp: float = 0.0
var body_angular_damp_mode: RigidBody3D.DampMode = RigidBody3D.DAMP_MODE_COMBINE
var body_angular_damp: float = 0.0


## Remembers how [param body] was set up, so [method restore_body] can rebuild it later.
func capture_body(body: RigidBody3D) -> void:
	parts = ObjectParts.of(body)
	source_scene_path = body.scene_file_path
	body_gravity_scale = body.gravity_scale
	body_linear_damp_mode = body.linear_damp_mode
	body_linear_damp = body.linear_damp
	body_angular_damp_mode = body.angular_damp_mode
	body_angular_damp = body.angular_damp


## Applies the settings saved by [method capture_body] to a fresh instance of the object, including
## its parts, size and weight, so a combined object stays combined.
func restore_body(body: RigidBody3D) -> void:
	body.gravity_scale = body_gravity_scale
	body.linear_damp_mode = body_linear_damp_mode
	body.linear_damp = body_linear_damp
	body.angular_damp_mode = body_angular_damp_mode
	body.angular_damp = body_angular_damp
	body.set_meta(ObjectParts.META, parts)
	body.mass = parts.get_mass()
	ObjectParts.resize_children(body, 1.0, parts.get_size())


## Changes the piece from [param old_size] to [param new_size] around its origin: its visuals, and
## its collision shapes, which live on the mass. The piece and its shapes are all children of the
## mass, so this works in the mass's space.
func resize(old_size: float, new_size: float) -> void:
	var ratio := new_size / old_size
	ObjectParts.resize_children(self, old_size, new_size)
	for shape in shapes:
		shape.position = position + (shape.position - position) * ratio
		ObjectParts.set_size(shape, new_size)


func add_shape(shape: CollisionShape3D) -> void:
	shape.set_meta(SHAPE_META, self)
	shapes.append(shape)


func link(other: MassPiece) -> void:
	if other == null or other == self:
		return
	neighbors[other] = true
	other.neighbors[self] = true


func unlink_all() -> void:
	for other in neighbors:
		if is_instance_valid(other):
			other.neighbors.erase(self)
	neighbors.clear()


## Centre of the piece's collision shapes, in global space.
func get_center() -> Vector3:
	if shapes.is_empty():
		return global_position
	var sum := Vector3.ZERO
	for shape in shapes:
		sum += shape.global_position
	return sum / shapes.size()


## Velocity of this piece as part of its mass, including the mass's spin.
func get_velocity() -> Vector3:
	if not is_instance_valid(mass):
		return Vector3.ZERO
	return mass.get_point_velocity(get_center())


## False once the mass is a cloud (Design Doc §4.5: a cloud can no longer be eaten).
func is_edible() -> bool:
	return is_instance_valid(mass) and not mass.is_cloud and not mass.is_queued_for_deletion()


func get_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node in find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	return meshes


## The piece's collision boxes as they would be at [param size], in global space (shapes scale
## around the piece's origin, as in [method resize]). Each box maps the cube from -1 to 1 onto the
## box: its origin is the centre and its basis columns reach to the faces. Objects use box colliders
## (the GLB importer makes them); other shapes are left out.
func get_boxes(size: float) -> Array[Transform3D]:
	var ratio := size / parts.get_size()
	var boxes: Array[Transform3D] = []
	for shape in shapes:
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		var xform := shape.global_transform * Transform3D(Basis.from_scale(box.size * 0.5), Vector3.ZERO)
		xform.origin = global_position + (xform.origin - global_position) * ratio
		xform.basis = xform.basis * ratio
		boxes.append(xform)
	return boxes


## The deepest overlap between any box of [param a] and any box of [param b] (see
## [method get_box_overlap]). Negative when every pair is apart.
static func get_overlap(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var deepest := -INF
	for box_a in a:
		for box_b in b:
			deepest = maxf(deepest, get_box_overlap(box_a, box_b))
	return deepest


## How far two boxes (see [method get_boxes]) push into each other along the axis where they overlap
## least, by the separating axis test: the depth when they overlap, negative when they're apart.
static func get_box_overlap(a: Transform3D, b: Transform3D) -> float:
	var columns: Array[Vector3] = [a.basis.x, a.basis.y, a.basis.z, b.basis.x, b.basis.y, b.basis.z]
	var axes: Array[Vector3] = []
	for column in columns:
		axes.append(column.normalized())
	# Edge-against-edge axes; parallel edges give no new axis.
	for i in 3:
		for j in range(3, 6):
			var cross := columns[i].cross(columns[j])
			if cross.length_squared() > 0.000001 * columns[i].length_squared() * columns[j].length_squared():
				axes.append(cross.normalized())

	var offset := b.origin - a.origin
	var least := INF
	for axis in axes:
		var reach := 0.0
		for column in columns:
			reach += absf(column.dot(axis))
		least = minf(least, reach - absf(offset.dot(axis)))
	return least
