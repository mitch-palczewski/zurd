class_name ObjectParts
extends RefCounted

## How many launched objects' worth of matter one object holds (Sculpture-Mass Design Doc §4.10). A
## plain object is one part. Matching objects that combine add up their parts, and a Zurd bites them
## off one at a time, most recent first. A loose body keeps its record in the [constant META] meta,
## because the generated object scenes have no script; a fused object keeps it on its [MassPiece].

const META := &"object_parts"

## How a combined object's size is worked out from its parts' sizes.
enum SizeMode {
	## Keeps the total volume: sizes 3 and 4 make ∛(3³ + 4³) ≈ 4.5.
	ADD_VOLUMES,
	## Adds the sizes: 3 + 4 = 7.
	ADD_SCALES,
}

## Each part's own size (its launch scale), oldest first.
var scales := PackedFloat32Array()
## The object's size after each part joined, oldest first; the last one is its current size. A bite
## steps back one entry, so the object returns to exactly the size it had before that part joined,
## whatever the size mode is now.
var sizes := PackedFloat32Array()
## Physics weight of one part (the object scene's own mass).
var part_mass: float = 1.0


## A single part of [param size] weighing [param mass_per_part].
func _init(size: float = 1.0, mass_per_part: float = 1.0) -> void:
	scales.append(size)
	sizes.append(size)
	part_mass = mass_per_part


## The parts record of loose [param body]. A body without one is a single part at its current size
## (the launcher scales every child by the same amount), and gets a record now.
static func of(body: RigidBody3D) -> ObjectParts:
	if body.has_meta(META):
		return body.get_meta(META)
	var parts := ObjectParts.new(_get_child_size(body), body.mass)
	body.set_meta(META, parts)
	return parts


## Changes [param node]'s 3D children from [param old_size] to [param new_size]. Their positions
## scale too, so off-centre children (like collision boxes) stay lined up with the rest.
static func resize_children(node: Node, old_size: float, new_size: float) -> void:
	var ratio := new_size / old_size
	for child in node.get_children():
		var child_3d := child as Node3D
		if child_3d:
			child_3d.position *= ratio
			set_size(child_3d, new_size)


## Gives [param node] a uniform [param size], keeping its rotation.
static func set_size(node: Node3D, size: float) -> void:
	node.basis = node.basis.orthonormalized() * size


static func _get_child_size(body: Node) -> float:
	for child in body.get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).scale.x
	return 1.0


func count() -> int:
	return scales.size()


func get_size() -> float:
	return sizes[sizes.size() - 1]


func get_mass() -> float:
	return part_mass * count()


## True when this is the bigger object: more parts, then the larger size.
func is_bigger_than(other: ObjectParts) -> bool:
	if count() != other.count():
		return count() > other.count()
	return get_size() > other.get_size()


## Adds [param other]'s parts after this object's own, oldest first, growing the size by
## [param mode] with each one.
func absorb(other: ObjectParts, mode: SizeMode) -> void:
	for part_scale in other.scales:
		sizes.append(_combine_sizes(get_size(), part_scale, mode))
		scales.append(part_scale)


## Removes the most recently added part; the size goes back to what it was before that part joined.
## The last part can't be removed: the object itself goes instead.
func remove_last() -> void:
	if count() <= 1:
		return
	scales.remove_at(scales.size() - 1)
	sizes.remove_at(sizes.size() - 1)


static func _combine_sizes(a: float, b: float, mode: SizeMode) -> float:
	if mode == SizeMode.ADD_SCALES:
		return a + b
	return pow(a * a * a + b * b * b, 1.0 / 3.0)
