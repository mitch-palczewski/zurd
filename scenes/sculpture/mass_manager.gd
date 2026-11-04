class_name MassManager
extends Node

## Runs the sculpture masses (Sculpture-Mass Design Doc). It counts hits on loose objects and does
## all fusing, combining, merging, eating and breaking off. Collision shapes can't change inside a
## physics callback, so contact callbacks only queue requests. The queue runs in
## [method _physics_process], which comes after the engine has reported this frame's contacts and
## before the next step. Every object registered with [code]ObjectTracker[/code] is watched, so the
## generated object scenes need no script.

const HITS_META := &"mass_hits"
const TOUCHED_META := &"mass_touched_piece"
const FUSE_BLOCKED_UNTIL_META := &"mass_fuse_blocked_until"
const LOOSE_CONTACTS_REPORTED := 4

@export_group("Mass")
## Objects a mass needs to turn into a cloud. A combined object counts as all its parts.
@export_range(2, 500) var cloud_threshold_count: int = 60
## Counted collisions before a loose object fuses to what it hit, or combines with it if it's the
## same kind of object. Only hits from other objects or masses count, at any speed.
@export_range(1, 20) var hits_to_fuse: int = 2
## Physics mass of one object (one part). Every part weighs the same, whatever its size.
@export var object_mass: float = 1.0
@export var mass_linear_damp: float = 0.3
@export var mass_angular_damp: float = 0.5
## How hard a fusing object pushes the mass. 1 = plain momentum (Design Doc §5), where the object
## weighs the same as each fused object. Higher counts it as that many objects, so masses get
## knocked around more.
@export_range(0.0, 10.0, 0.05, "or_greater") var fuse_push: float = 1.0
## How much an off-centre fuse spins the mass. 0 = no spin (the Design Doc's simplification),
## 1 = roughly physical.
@export_range(0.0, 10.0, 0.05, "or_greater") var fuse_spin: float = 0.0
@export var mass_scene: PackedScene

@export_group("Combining")
## How a combined object's size is worked out from its parts (Design Doc §4.10). Changing it only
## affects later combines; bites always step back to the earlier sizes.
@export var combine_size_mode: ObjectParts.SizeMode = ObjectParts.SizeMode.ADD_VOLUMES

@export_group("Breaking Off")
## Seconds after leaving a mass before an object's hits count again, so it drifts clear instead of
## fusing straight back. 0 = no delay.
@export var refuse_delay: float = 1.0
## Extra speed pushing an object that leaves a mass away from the mass's centre. 0 = only the mass's
## own velocity at that point.
@export var detach_speed: float = 1.0
## How close a fusing object must be to a fused object to count as touching it (structure links).
@export var neighbor_margin: float = 0.25
## How far a fused object that grows must push into a neighbour before the neighbour breaks off.
## Neighbours it already pushed into this far before growing stay.
@export var growth_break_depth: float = 0.1

@export_group("Cloud")
## Band of heights where finished clouds hover.
@export var atmosphere_y_range: Vector2 = Vector2(150.0, 200.0)
@export var rise_speed: float = 6.0
@export var drift_speed: float = 1.5
## Length of the switch to the cloud look when a mass becomes a cloud.
@export var cloud_transition_time: float = 2.0

@export_group("Debug")
## Shows each mass's object count above it.
@export var debug_labels: bool = false

var _requests: Array[Callable] = []
## What objects became earlier in the batch being processed: a loose body -> the piece it fused or
## combined into, or the loose body that absorbed it; a fused piece -> the piece that absorbed it.
var _became_this_batch: Dictionary = {}


func _ready() -> void:
	ObjectTracker.object_registered.connect(_on_object_registered)
	EventBus.eat_requested.connect(_on_eat_requested)


func _physics_process(_delta: float) -> void:
	if _requests.is_empty():
		return
	var batch := _requests
	_requests = []
	for request in batch:
		request.call()
	_became_this_batch.clear()


func request_break_off(piece: MassPiece) -> void:
	_requests.append(_process_break_off.bind(piece))


# ==============================================================================
# CONTACTS (physics callbacks: only record and queue)
# ==============================================================================

func _on_object_registered(obj: Node3D) -> void:
	var body := obj as RigidBody3D
	if body == null or body is SculptureMass or body.has_meta(HITS_META):
		return
	body.set_meta(HITS_META, 0)
	body.contact_monitor = true
	body.max_contacts_reported = maxi(body.max_contacts_reported, LOOSE_CONTACTS_REPORTED)
	body.body_entered.connect(_on_loose_body_entered.bind(body))
	body.body_shape_entered.connect(_on_loose_body_shape_entered.bind(body))


func _on_loose_body_shape_entered(_body_rid: RID, other: Node, other_shape_index: int, _local_shape_index: int, body: RigidBody3D) -> void:
	# Remember which fused object was hit, so the object links to it when it fuses.
	var other_mass := other as SculptureMass
	if other_mass:
		var piece := other_mass.get_piece_for_shape_index(other_shape_index)
		if piece:
			body.set_meta(TOUCHED_META, piece)


func _on_loose_body_entered(other: Node, body: RigidBody3D) -> void:
	if not _is_fuse_partner(other):
		return
	if Time.get_ticks_msec() < int(body.get_meta(FUSE_BLOCKED_UNTIL_META, 0)):
		return
	var hits := int(body.get_meta(HITS_META, 0)) + 1
	body.set_meta(HITS_META, hits)
	EventBus.object_hit.emit(body, other)
	if hits >= hits_to_fuse:
		_requests.append(_process_fuse.bind(body, other))


func _on_mass_body_shape_entered(_body_rid: RID, other: Node, other_shape_index: int, local_shape_index: int, mass: SculptureMass) -> void:
	# Loose objects report their own hits; masses only look for other masses.
	var other_mass := other as SculptureMass
	if other_mass == null:
		return
	var mine := mass.get_piece_for_shape_index(local_shape_index)
	var theirs := other_mass.get_piece_for_shape_index(other_shape_index)
	if mine and theirs:
		_requests.append(_process_merge.bind(mine, theirs))


func _on_eat_requested(actor: Node3D, obj: Node3D) -> void:
	_requests.append(_process_eat.bind(obj, actor))


## Only other objects and masses count as hits (not the ship, Zurds or the environment).
func _is_fuse_partner(other: Node) -> bool:
	if other is SculptureMass:
		return not (other as SculptureMass).is_cloud
	return other is RigidBody3D and other.has_meta(HITS_META)


# ==============================================================================
# REQUESTS (run outside physics callbacks)
# Arguments are untyped because a node may have been freed since the request was queued.
# ==============================================================================

func _process_fuse(body: Variant, other: Variant) -> void:
	if not _is_loose(body):
		return
	var loose: RigidBody3D = body
	# Follow what it hit if that fused or combined earlier in this batch.
	var target: Variant = _follow(other)
	if target == null or target == loose:
		return

	if target is MassPiece:
		if _is_live_piece(target):
			_join_mass(loose, target.mass, target)
	elif target is SculptureMass:
		var touched := _get_touched_piece(loose)
		if _is_live_mass(target):
			_join_mass(loose, target, touched if touched and touched.mass == target else null)
		elif touched:
			# The mass it hit merged into another one earlier in this batch.
			_join_mass(loose, touched.mass, touched)
	elif _is_loose(target):
		if _matches(loose, target):
			_combine_loose(loose, target)
		else:
			# Two loose objects: whichever reached the hit count pulls the other into a new mass.
			_start_mass(loose, target)


func _process_merge(piece_a: Variant, piece_b: Variant) -> void:
	var followed_a: Variant = _follow(piece_a)
	var followed_b: Variant = _follow(piece_b)
	if not _is_live_piece(followed_a) or not _is_live_piece(followed_b):
		return
	var a: MassPiece = followed_a
	var b: MassPiece = followed_b
	if a.mass == b.mass:
		return
	if a.mass.get_part_count() >= b.mass.get_part_count():
		_merge(a.mass, b.mass, a, b)
	else:
		_merge(b.mass, a.mass, b, a)


func _process_eat(obj: Variant, actor: Variant) -> void:
	var target: Variant = _follow(obj)
	var eater: Node3D = actor if is_instance_valid(actor) else null
	if _is_live_piece(target):
		_bite_piece(target, eater)
	elif _is_loose(target):
		_bite_loose(target, eater)


func _process_break_off(piece: Variant) -> void:
	var target: Variant = _follow(piece)
	if not _is_live_piece(target):
		return
	var hit: MassPiece = target
	var mass := hit.mass
	var broken: Array[RigidBody3D] = []
	var body := _detach(hit)
	if body:
		broken.append(body)
	broken.append_array(_settle(mass))
	EventBus.objects_broken_off.emit(mass, broken)


# ==============================================================================
# MASS OPERATIONS
# ==============================================================================

func _start_mass(a: RigidBody3D, b: RigidBody3D) -> void:
	var mass := _create_mass((a.global_position + b.global_position) * 0.5)
	if mass == null:
		return
	var first := _fuse(a, mass, null)
	_fuse(b, mass, first)


func _create_mass(at: Vector3) -> SculptureMass:
	if mass_scene == null:
		push_error("MassManager: No mass_scene assigned.")
		return null
	var instance := mass_scene.instantiate()
	var mass := instance as SculptureMass
	if mass == null:
		push_error("MassManager: mass_scene root must be a SculptureMass.")
		instance.free()
		return null

	mass.manager = self
	mass.linear_damp = mass_linear_damp
	mass.angular_damp = mass_angular_damp
	EventBus.spawn_requested.emit(mass)
	if not mass.is_inside_tree():
		push_warning("MassManager: No world picked up the spawn request.")
		mass.free()
		return null

	mass.global_position = at
	mass.body_shape_entered.connect(_on_mass_body_shape_entered.bind(mass))
	return mass


## [param body] reached its hit count against [param mass] (Design Doc §4.1, §4.10). It combines
## with a matching fused object it's touching, preferring [param touched] (the one it hit), or else
## fuses.
func _join_mass(body: RigidBody3D, mass: SculptureMass, touched: MassPiece) -> void:
	var matching := _find_matching_piece(body, mass, touched)
	if matching:
		_combine_into_piece(body, matching)
	else:
		_fuse(body, mass, touched)


func _find_matching_piece(body: RigidBody3D, mass: SculptureMass, touched: MassPiece) -> MassPiece:
	if touched and _matches(body, touched):
		return touched
	if not mass.pieces.any(_matches.bind(body)):
		return null
	for piece in _find_touching_pieces(body, mass):
		if _matches(body, piece):
			return piece
	return null


## Fuses [param body] into [param mass] and frees the body (Design Doc §4.1). [param touched] is the
## fused object it hit, if known.
func _fuse(body: RigidBody3D, mass: SculptureMass, touched: MassPiece) -> MassPiece:
	var neighbors := _find_touching_pieces(body, mass)
	if touched and touched.mass == mass and not neighbors.has(touched):
		neighbors.append(touched)
	if neighbors.is_empty() and not mass.pieces.is_empty():
		# Always link to something, so the structure stays connected.
		neighbors.append(mass.get_closest_piece(body.global_position))

	var old_center := mass.get_global_center_of_mass()
	var hit_velocity := body.linear_velocity - mass.linear_velocity
	var reduced_weight := _take_momentum(mass, body)

	var piece := mass.add_piece(body)
	for neighbor in neighbors:
		piece.link(neighbor)
	_became_this_batch[body] = piece
	body.queue_free()

	ObjectTracker.register_object(piece)
	EventBus.object_fused.emit(mass, piece)
	mass.refresh()
	_spin_from_hit(mass, piece.get_center() - old_center, hit_velocity, reduced_weight)
	return piece


## Changes [param mass]'s velocity for [param body] joining it: the weighted average of the two
## (Design Doc §4.1, §5), with the body's weight (its parts) scaled by [member fuse_push]. Returns
## the pair's reduced weight, for [method _spin_from_hit].
func _take_momentum(mass: SculptureMass, body: RigidBody3D) -> float:
	if mass.pieces.is_empty():
		mass.linear_velocity = body.linear_velocity
		return 0.0
	var mass_weight := mass.get_part_count() * object_mass
	# A mass with one object is two loose objects meeting, so neither pushes harder.
	var push := fuse_push if mass.pieces.size() > 1 else 1.0
	var incoming := ObjectParts.of(body).count() * object_mass * push
	mass.linear_velocity += (body.linear_velocity - mass.linear_velocity) * incoming / (mass_weight + incoming)
	return mass_weight * incoming / (mass_weight + incoming)


## Spins [param mass] for an object that joined it [param offset] from its old centre of mass, moving
## at [param hit_velocity] relative to it. For two bodies that stick together, the spin about the new
## centre is offset × hit_velocity × [param reduced_weight] (the two-body reduced mass).
func _spin_from_hit(mass: SculptureMass, offset: Vector3, hit_velocity: Vector3, reduced_weight: float) -> void:
	if fuse_spin <= 0.0 or reduced_weight <= 0.0 or mass.is_cloud:
		return
	var inertia := mass.get_inertia_estimate()
	if inertia <= 0.0:
		return
	mass.angular_velocity += offset.cross(hit_velocity) * reduced_weight * fuse_spin / inertia


## Moves every piece of [param absorb] into [param keep] (Design Doc §4.2). [param a] and [param b]
## are the pieces that touched; they become linked, and combine if they're the same kind of object.
func _merge(keep: SculptureMass, absorb: SculptureMass, a: MassPiece, b: MassPiece) -> void:
	var keep_weight := keep.get_part_count() * object_mass
	var absorb_weight := absorb.get_part_count() * object_mass
	keep.linear_velocity = (keep.linear_velocity * keep_weight + absorb.linear_velocity * absorb_weight) / (keep_weight + absorb_weight)

	var absorbed_count := absorb.get_part_count()
	for piece in absorb.pieces.duplicate():
		keep.adopt_piece(piece)
		# Reparenting takes the piece out of the tree, which drops it from the tracker.
		ObjectTracker.register_object(piece)
	a.link(b)
	absorb.queue_free()

	EventBus.masses_merged.emit(keep, absorbed_count)
	keep.refresh()
	if _matches(a, b) and _is_live_mass(keep):
		_combine_pieces(a, b)


# ==============================================================================
# COMBINING (Design Doc §4.10)
# ==============================================================================

## Combines two matching loose objects: the bigger one stays where it is, takes the other's parts
## and grows, and the other is freed.
func _combine_loose(a: RigidBody3D, b: RigidBody3D) -> void:
	var keep := a
	var absorb := b
	if ObjectParts.of(b).is_bigger_than(ObjectParts.of(a)):
		keep = b
		absorb = a
	var keep_parts := ObjectParts.of(keep)
	var absorb_parts := ObjectParts.of(absorb)

	# Momentum: the weighted average of the two, as in fusing (Design Doc §4.1).
	var keep_weight := keep_parts.get_mass()
	var absorb_weight := absorb_parts.get_mass()
	var total := keep_weight + absorb_weight
	keep.linear_velocity = (keep.linear_velocity * keep_weight + absorb.linear_velocity * absorb_weight) / total
	keep.angular_velocity = (keep.angular_velocity * keep_weight + absorb.angular_velocity * absorb_weight) / total

	var old_size := keep_parts.get_size()
	keep_parts.absorb(absorb_parts, combine_size_mode)
	keep.set_meta(HITS_META, 0)
	keep.remove_meta(TOUCHED_META)
	_became_this_batch[absorb] = keep
	absorb.queue_free()

	_apply_size(keep, old_size)
	EventBus.objects_combined.emit(keep, absorb_parts.count())


## Combines loose [param body] into the matching fused [param piece]: the piece takes the body's
## parts and grows in place, and the fused objects it grows into break off.
func _combine_into_piece(body: RigidBody3D, piece: MassPiece) -> void:
	var mass := piece.mass
	var body_parts := ObjectParts.of(body)
	var old_center := mass.get_global_center_of_mass()
	var hit_velocity := body.linear_velocity - mass.linear_velocity
	var reduced_weight := _take_momentum(mass, body)

	var old_size := piece.parts.get_size()
	piece.parts.absorb(body_parts, combine_size_mode)
	_became_this_batch[body] = piece
	body.queue_free()

	_apply_size(piece, old_size)
	EventBus.objects_combined.emit(piece, body_parts.count())
	_break_overlapped(piece, old_size)
	if _is_live_piece(piece):
		_spin_from_hit(mass, piece.get_center() - old_center, hit_velocity, reduced_weight)


## Combines matching fused objects [param a] and [param b] of one mass (after a merge): the bigger
## one takes the other's parts and links and grows in place, and the other is removed.
func _combine_pieces(a: MassPiece, b: MassPiece) -> void:
	var keep := a
	var absorb := b
	if b.parts.is_bigger_than(a.parts):
		keep = b
		absorb = a
	var old_size := keep.parts.get_size()
	var absorbed_parts := absorb.parts.count()
	keep.parts.absorb(absorb.parts, combine_size_mode)
	for neighbor in absorb.neighbors:
		keep.link(neighbor)
	_became_this_batch[absorb] = keep
	keep.mass.remove_piece(absorb)

	_apply_size(keep, old_size)
	EventBus.objects_combined.emit(keep, absorbed_parts)
	_break_overlapped(keep, old_size)


## Puts [param obj] (a loose body or a fused piece) at its parts' size after it was [param old_size].
## Collision shapes and visuals change at once; SculptureFx animates the visuals.
func _apply_size(obj: Node3D, old_size: float) -> void:
	var new_size: float
	var piece := obj as MassPiece
	if piece:
		new_size = piece.parts.get_size()
		piece.resize(old_size, new_size)
	else:
		var body := obj as RigidBody3D
		var parts := ObjectParts.of(body)
		new_size = parts.get_size()
		ObjectParts.resize_children(body, old_size, new_size)
		body.mass = parts.get_mass()
	EventBus.object_resized.emit(obj, old_size, new_size)


## Breaks off the fused objects that [param piece] pushes into after growing from [param old_size],
## pushed away from it, then settles the mass (Design Doc §4.8).
func _break_overlapped(piece: MassPiece, old_size: float) -> void:
	var mass := piece.mass
	var center := piece.get_center()
	var broken: Array[RigidBody3D] = []
	for other in _find_grown_into(piece, old_size):
		var body := _detach(other, center)
		if body:
			broken.append(body)
	broken.append_array(_settle(mass))
	if not broken.is_empty():
		EventBus.objects_broken_off.emit(mass, broken)


## Fused objects of [param piece]'s mass that it now pushes into by more than
## [member growth_break_depth], but didn't at [param old_size].
func _find_grown_into(piece: MassPiece, old_size: float) -> Array[MassPiece]:
	var old_boxes := piece.get_boxes(old_size)
	var new_boxes := piece.get_boxes(piece.parts.get_size())
	var found: Array[MassPiece] = []
	for other in piece.mass.pieces:
		if other == piece:
			continue
		var other_boxes := other.get_boxes(other.parts.get_size())
		if (MassPiece.get_overlap(new_boxes, other_boxes) > growth_break_depth
				and MassPiece.get_overlap(old_boxes, other_boxes) <= growth_break_depth):
			found.append(other)
	return found


## True when [param a] and [param b] are the same kind of object: the same model, at any size. Each
## is a loose body or a fused piece.
func _matches(a: Node, b: Node) -> bool:
	var path := _get_scene_path(a)
	return not path.is_empty() and path == _get_scene_path(b)


func _get_scene_path(obj: Node) -> String:
	var piece := obj as MassPiece
	return piece.source_scene_path if piece else obj.scene_file_path


# ==============================================================================
# EATING (Design Doc §4.5)
# ==============================================================================

## A Zurd's bite out of fused [param piece]: one part of a combined object, which shrinks back a
## step and keeps its links, or the whole object, which may drop its dependents.
func _bite_piece(piece: MassPiece, eater: Node3D) -> void:
	var mass := piece.mass
	EventBus.object_eaten.emit(eater, piece, mass)
	if piece.parts.count() > 1:
		var old_size := piece.parts.get_size()
		piece.parts.remove_last()
		_apply_size(piece, old_size)
		mass.refresh()
	else:
		mass.remove_piece(piece)
		_settle(mass)


## A Zurd's bite out of loose [param body]: one part of a combined object, which shrinks back a
## step, or the whole object.
func _bite_loose(body: RigidBody3D, eater: Node3D) -> void:
	EventBus.object_eaten.emit(eater, body, null)
	var parts := ObjectParts.of(body)
	if parts.count() > 1:
		var old_size := parts.get_size()
		parts.remove_last()
		_apply_size(body, old_size)
	else:
		body.queue_free()


# ==============================================================================
# BREAKING OFF
# ==============================================================================

## Takes [param piece] out of its mass and puts a loose copy of the object in its place, moving with
## the mass's velocity at that point plus [member detach_speed] away from [param push_from], or from
## the mass's centre when that's null (Design Doc §4.6, §5).
func _detach(piece: MassPiece, push_from: Variant = null) -> RigidBody3D:
	var mass := piece.mass
	var center := piece.get_center()
	var velocity := mass.get_point_velocity(center)
	var origin: Vector3 = mass.get_global_center_of_mass() if push_from == null else push_from
	var away := center - origin
	if away.length_squared() > 0.0001:
		velocity += away.normalized() * detach_speed
	var spin := mass.angular_velocity
	var xform := piece.global_transform.orthonormalized()

	mass.remove_piece(piece)
	return _spawn_loose(piece, xform, velocity, spin)


func _spawn_loose(piece: MassPiece, xform: Transform3D, velocity: Vector3, spin: Vector3) -> RigidBody3D:
	if piece.source_scene_path.is_empty():
		push_warning("MassManager: Can't rebuild '%s' as a loose object; it has no scene file." % piece.name)
		return null
	var scene := load(piece.source_scene_path) as PackedScene
	if scene == null:
		push_error("MassManager: Failed to load '%s'." % piece.source_scene_path)
		return null
	var instance := scene.instantiate()
	var body := instance as RigidBody3D
	if body == null:
		push_error("MassManager: '%s' root must be a RigidBody3D." % piece.source_scene_path)
		instance.free()
		return null

	piece.restore_body(body)
	EventBus.spawn_requested.emit(body)
	if not body.is_inside_tree():
		push_warning("MassManager: No world picked up the spawn request.")
		body.free()
		return null

	body.global_transform = xform
	body.linear_velocity = velocity
	body.angular_velocity = spin
	if refuse_delay > 0.0:
		body.set_meta(FUSE_BLOCKED_UNTIL_META, Time.get_ticks_msec() + int(refuse_delay * 1000.0))
	ObjectTracker.register_object(body)
	return body


## Cleans up [param mass] after pieces left it (Design Doc §4.8). Chunks that are no longer connected
## to the largest one fall off, a one-object remnant becomes loose, and an empty mass is freed.
## Returns the objects that became loose.
func _settle(mass: SculptureMass) -> Array[RigidBody3D]:
	var loose: Array[RigidBody3D] = []
	var chunks := mass.get_chunks()
	for i in range(1, chunks.size()):
		for piece in chunks[i]:
			var body := _detach(piece)
			if body:
				loose.append(body)

	if mass.pieces.size() == 1:
		var body := _detach(mass.pieces[0])
		if body:
			loose.append(body)

	if mass.pieces.is_empty():
		mass.queue_free()
	else:
		mass.refresh()
	return loose


# ==============================================================================
# HELPERS
# ==============================================================================

## Fused objects of [param mass] that [param body] is touching (Design Doc §4.8: each fused object
## remembers what it was touching when it fused).
func _find_touching_pieces(body: RigidBody3D, mass: SculptureMass) -> Array[MassPiece]:
	var found: Array[MassPiece] = []
	var space := body.get_world_3d().direct_space_state
	for child in body.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null or shape_node.disabled:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = shape_node.global_transform
		query.margin = neighbor_margin
		query.collision_mask = mass.collision_layer
		query.exclude = [body.get_rid()]
		for result in space.intersect_shape(query, 32):
			if result.collider != mass:
				continue
			var piece := mass.get_piece_for_shape_index(result.shape)
			if piece and not found.has(piece):
				found.append(piece)
	return found


func _get_touched_piece(body: RigidBody3D) -> MassPiece:
	if not body.has_meta(TOUCHED_META):
		return null
	var piece: Variant = body.get_meta(TOUCHED_META)
	if _is_live_piece(piece):
		return piece
	return null


## What [param obj] became if it fused or combined earlier in this batch, or [param obj] itself;
## null if it was freed.
func _follow(obj: Variant) -> Variant:
	if not is_instance_valid(obj):
		return null
	while _became_this_batch.has(obj):
		obj = _became_this_batch[obj]
	return obj


func _is_loose(body: Variant) -> bool:
	return (is_instance_valid(body) and body is RigidBody3D and body.has_meta(HITS_META)
			and body.is_inside_tree() and not body.is_queued_for_deletion()
			and not _became_this_batch.has(body))


func _is_live_mass(mass: Variant) -> bool:
	return (is_instance_valid(mass) and mass is SculptureMass and mass.is_inside_tree()
			and not mass.is_queued_for_deletion() and not mass.is_cloud)


func _is_live_piece(piece: Variant) -> bool:
	return (is_instance_valid(piece) and piece is MassPiece and piece.is_inside_tree()
			and not piece.is_queued_for_deletion() and _is_live_mass(piece.mass))
