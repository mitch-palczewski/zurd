class_name MassManager
extends Node

## Runs the sculpture masses (Sculpture-Mass Design Doc). It counts hits on loose objects and does
## all fusing, merging, eating and breaking off. Collision shapes can't change inside a physics
## callback, so contact callbacks only queue requests. The queue runs in [method _physics_process],
## which comes after the engine has reported this frame's contacts and before the next step.
## Every object registered with [code]ObjectTracker[/code] is watched, so the generated object scenes
## need no script.

const HITS_META := &"mass_hits"
const TOUCHED_META := &"mass_touched_piece"
const FUSE_BLOCKED_UNTIL_META := &"mass_fuse_blocked_until"
const LOOSE_CONTACTS_REPORTED := 4

@export_group("Mass")
## Objects a mass needs to turn into a cloud.
@export_range(2, 500) var cloud_threshold_count: int = 60
## Counted collisions before a loose object fuses to what it hit. Only hits from other objects or
## masses count, at any speed.
@export_range(1, 20) var hits_to_fuse: int = 2
## Physics mass of one object. Every object weighs the same, whatever its size.
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

@export_group("Breaking Off")
## Seconds after leaving a mass before an object's hits count again, so it drifts clear instead of
## fusing straight back. 0 = no delay.
@export var refuse_delay: float = 1.0
## Extra speed pushing an object that leaves a mass away from the mass's centre. 0 = only the mass's
## own velocity at that point.
@export var detach_speed: float = 1.0
## How close a fusing object must be to a fused object to count as touching it (structure links).
@export var neighbor_margin: float = 0.25

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
## Loose body -> the piece it became, for the batch being processed.
var _fused_this_batch: Dictionary = {}


func _ready() -> void:
	ObjectTracker.object_registered.connect(_on_object_registered)


func _physics_process(_delta: float) -> void:
	if _requests.is_empty():
		return
	var batch := _requests
	_requests = []
	for request in batch:
		request.call()
	_fused_this_batch.clear()


func request_eat(piece: MassPiece, actor: Node3D) -> void:
	_requests.append(_process_eat.bind(piece, actor))


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
	if not _is_loose(body) or not is_instance_valid(other):
		return
	var loose: RigidBody3D = body

	if _fused_this_batch.has(other):
		# What it hit was fused earlier in this batch: follow it to its mass.
		var other_piece: MassPiece = _fused_this_batch[other]
		if _is_live_mass(other_piece.mass):
			_fuse(loose, other_piece.mass, other_piece)
	elif other is SculptureMass:
		var touched := _get_touched_piece(loose)
		if _is_live_mass(other):
			_fuse(loose, other, touched if touched and touched.mass == other else null)
		elif touched and _is_live_mass(touched.mass):
			# The mass it hit merged into another one earlier in this batch.
			_fuse(loose, touched.mass, touched)
	elif _is_loose(other):
		# Two loose objects: whichever reached the hit count pulls the other into a new mass.
		_start_mass(loose, other)


func _process_merge(piece_a: Variant, piece_b: Variant) -> void:
	if not _is_live_piece(piece_a) or not _is_live_piece(piece_b):
		return
	var a: MassPiece = piece_a
	var b: MassPiece = piece_b
	if a.mass == b.mass:
		return
	if a.mass.pieces.size() >= b.mass.pieces.size():
		_merge(a.mass, b.mass, a, b)
	else:
		_merge(b.mass, a.mass, b, a)


func _process_eat(piece: Variant, actor: Variant) -> void:
	if not _is_live_piece(piece):
		return
	var eaten: MassPiece = piece
	var mass := eaten.mass
	EventBus.object_eaten.emit(actor if is_instance_valid(actor) else null, eaten, mass)
	mass.remove_piece(eaten)
	_settle(mass)


func _process_break_off(piece: Variant) -> void:
	if not _is_live_piece(piece):
		return
	var hit: MassPiece = piece
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


## Fuses [param body] into [param mass] and frees the body (Design Doc §4.1). [param touched] is the
## fused object it hit, if known.
func _fuse(body: RigidBody3D, mass: SculptureMass, touched: MassPiece) -> MassPiece:
	var neighbors := _find_touching_pieces(body, mass)
	if touched and touched.mass == mass and not neighbors.has(touched):
		neighbors.append(touched)
	if neighbors.is_empty() and not mass.pieces.is_empty():
		# Always link to something, so the structure stays connected.
		neighbors.append(mass.get_closest_piece(body.global_position))

	# Momentum: the mass-weighted average of the mass and the incoming object (Design Doc §5), with
	# the object's weight scaled by fuse_push. A mass with one object is two loose objects meeting,
	# so neither pushes harder.
	var mass_weight := mass.pieces.size() * object_mass
	var incoming := object_mass * (fuse_push if mass.pieces.size() > 1 else 1.0)
	var hit_velocity := body.linear_velocity - mass.linear_velocity
	var old_center := mass.get_global_center_of_mass()
	if mass.pieces.is_empty():
		mass.linear_velocity = body.linear_velocity
	else:
		mass.linear_velocity += hit_velocity * incoming / (mass_weight + incoming)

	var piece := mass.add_piece(body)
	for neighbor in neighbors:
		piece.link(neighbor)
	_fused_this_batch[body] = piece
	body.queue_free()

	ObjectTracker.register_object(piece)
	EventBus.object_fused.emit(mass, piece)
	mass.refresh()

	if fuse_spin > 0.0 and mass_weight > 0.0 and not mass.is_cloud:
		var reduced_weight := mass_weight * incoming / (mass_weight + incoming)
		_spin_from_hit(mass, piece.get_center() - old_center, hit_velocity, reduced_weight)
	return piece


## Spins [param mass] for an object that fused [param offset] from its old centre of mass, moving at
## [param hit_velocity] relative to it. For two bodies that stick together, the spin about the new
## centre is offset × hit_velocity × [param reduced_weight] (the two-body reduced mass).
func _spin_from_hit(mass: SculptureMass, offset: Vector3, hit_velocity: Vector3, reduced_weight: float) -> void:
	var inertia := mass.get_inertia_estimate()
	if inertia <= 0.0:
		return
	mass.angular_velocity += offset.cross(hit_velocity) * reduced_weight * fuse_spin / inertia


## Moves every piece of [param absorb] into [param keep] (Design Doc §4.2). [param a] and [param b]
## are the pieces that touched; they become linked.
func _merge(keep: SculptureMass, absorb: SculptureMass, a: MassPiece, b: MassPiece) -> void:
	var keep_weight := keep.pieces.size() * object_mass
	var absorb_weight := absorb.pieces.size() * object_mass
	keep.linear_velocity = (keep.linear_velocity * keep_weight + absorb.linear_velocity * absorb_weight) / (keep_weight + absorb_weight)

	var absorbed_count := absorb.pieces.size()
	for piece in absorb.pieces.duplicate():
		keep.adopt_piece(piece)
		# Reparenting takes the piece out of the tree, which drops it from the tracker.
		ObjectTracker.register_object(piece)
	a.link(b)
	absorb.queue_free()

	EventBus.masses_merged.emit(keep, absorbed_count)
	keep.refresh()


## Takes [param piece] out of its mass and puts a loose copy of the object in its place, moving with
## the mass's velocity at that point (Design Doc §4.6, §5).
func _detach(piece: MassPiece) -> RigidBody3D:
	var mass := piece.mass
	var center := piece.get_center()
	var velocity := mass.get_point_velocity(center)
	var away := center - mass.get_global_center_of_mass()
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


func _is_loose(body: Variant) -> bool:
	return (is_instance_valid(body) and body is RigidBody3D and body.has_meta(HITS_META)
			and body.is_inside_tree() and not body.is_queued_for_deletion()
			and not _fused_this_batch.has(body))


func _is_live_mass(mass: Variant) -> bool:
	return (is_instance_valid(mass) and mass is SculptureMass and mass.is_inside_tree()
			and not mass.is_queued_for_deletion() and not mass.is_cloud)


func _is_live_piece(piece: Variant) -> bool:
	return (is_instance_valid(piece) and piece is MassPiece and piece.is_inside_tree()
			and not piece.is_queued_for_deletion() and _is_live_mass(piece.mass))
