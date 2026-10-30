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

# What it takes to rebuild the loose body when the piece leaves the mass.
var source_scene_path: String = ""
var spawn_scale: Vector3 = Vector3.ONE
var body_gravity_scale: float = 0.0
var body_linear_damp_mode: RigidBody3D.DampMode = RigidBody3D.DAMP_MODE_COMBINE
var body_linear_damp: float = 0.0
var body_angular_damp_mode: RigidBody3D.DampMode = RigidBody3D.DAMP_MODE_COMBINE
var body_angular_damp: float = 0.0


## Remembers how [param body] was set up, so [method restore_body] can rebuild it later.
func capture_body(body: RigidBody3D) -> void:
	source_scene_path = body.scene_file_path
	body_gravity_scale = body.gravity_scale
	body_linear_damp_mode = body.linear_damp_mode
	body_linear_damp = body.linear_damp
	body_angular_damp_mode = body.angular_damp_mode
	body_angular_damp = body.angular_damp

	# The launcher scales every child by the same amount. Read it off a collision shape, because
	# effects may be tweening the visuals' scale.
	for child in body.get_children():
		if child is CollisionShape3D:
			spawn_scale = (child as CollisionShape3D).scale
			break


## Applies the settings saved by [method capture_body] to a fresh instance of the object.
func restore_body(body: RigidBody3D) -> void:
	body.gravity_scale = body_gravity_scale
	body.linear_damp_mode = body_linear_damp_mode
	body.linear_damp = body_linear_damp
	body.angular_damp_mode = body_angular_damp_mode
	body.angular_damp = body_angular_damp
	for child in body.get_children():
		if child is Node3D:
			(child as Node3D).scale = spawn_scale


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
