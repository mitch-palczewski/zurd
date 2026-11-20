class_name ZurdSightComponent
extends Node

## What a Zurd sees and goes after (Zurd Core Design Doc §4, §12): a vertical cylinder around it, a
## circle on the ground plane covering every height (its radius comes from the Zurd's role). Targets
## come from ObjectTracker's list, so seeing needs no physics queries.

## Radius of the sight cylinder, on the ground plane.
@export var sight_radius: float = 150.0
## Seconds between looks for a new target.
@export var look_interval: float = 0.25


## True when [param point] is in sight from [param from]: within the radius on the ground plane, at
## any height.
func can_see(from: Vector3, point: Vector3) -> bool:
	return Vector2(point.x - from.x, point.z - from.z).length() <= sight_radius


## A Hostile Zurd's target: the loose object in sight nearest [param near] (the Zurd itself when
## not given; a Shadow passes the ship); else the nearest object of the largest sculpture in sight
## with more than [param min_sculpture_size] parts. Only objects [param is_free] accepts count (it
## skips those another Zurd has claimed). Null when there's nothing in sight to go after: each Zurd
## acts on what it sees (Zurd Core Design Doc §12.1).
func find_hostile_target(from: Vector3, min_sculpture_size: int, is_free := Callable(), near := Vector3.INF) -> Node3D:
	var reference := near if near.is_finite() else from
	var loose_in_sight: Node3D = null
	var loose_in_sight_distance := INF
	var large_sculptures: Dictionary[SculptureMass, Array] = {}
	for obj in ObjectTracker.active_objects:
		if not ObjectTracker.is_trackable(obj) or (is_free.is_valid() and not is_free.call(obj)):
			continue
		var piece := obj as MassPiece
		if piece:
			if piece.mass.get_part_count() > min_sculpture_size:
				large_sculptures.get_or_add(piece.mass, []).append(piece)
		elif obj is RigidBody3D and not obj is SculptureMass and can_see(from, obj.global_position):
			var distance := reference.distance_squared_to(obj.global_position)
			if distance < loose_in_sight_distance:
				loose_in_sight = obj
				loose_in_sight_distance = distance
	if loose_in_sight:
		return loose_in_sight

	var largest: SculptureMass = null
	for mass: SculptureMass in large_sculptures:
		var seen := large_sculptures[mass].any(func(p: MassPiece) -> bool: return can_see(from, p.get_center()))
		if seen and (largest == null or mass.get_part_count() > largest.get_part_count()):
			largest = mass
	return _nearest_piece(from, large_sculptures[largest]) if largest else null


## A Hostile Grazer's target (Zurd Core Design Doc §12.2): the nearest loose object in its patch (the
## circle of [param radius] around [param center] on the ground plane); else the nearest object of
## any sculpture in its patch, since a Grazer treats sculptures like loose objects; else the nearest
## stray in sight outside it. Only objects [param is_free] accepts count.
func find_patch_target(from: Vector3, center: Vector3, radius: float, is_free := Callable()) -> Node3D:
	var loose: Node3D = null
	var loose_distance := INF
	var piece_target: Node3D = null
	var piece_distance := INF
	var stray: Node3D = null
	var stray_distance := INF
	for obj in ObjectTracker.active_objects:
		if not ObjectTracker.is_trackable(obj) or (is_free.is_valid() and not is_free.call(obj)):
			continue
		var piece := obj as MassPiece
		if piece == null and (not obj is RigidBody3D or obj is SculptureMass):
			continue
		var position: Vector3 = piece.get_center() if piece else obj.global_position
		var in_patch := Vector2(position.x - center.x, position.z - center.z).length() <= radius
		var distance := from.distance_squared_to(position)
		if piece:
			if in_patch and distance < piece_distance:
				piece_target = piece
				piece_distance = distance
		elif in_patch:
			if distance < loose_distance:
				loose = obj
				loose_distance = distance
		elif can_see(from, position) and distance < stray_distance:
			stray = obj
			stray_distance = distance
	if loose:
		return loose
	return piece_target if piece_target else stray


## The nearest object of [param mass] that [param is_free] accepts: a Hostile Sentinel eating its
## sculpture. Null when there's none.
func find_piece_of(mass: SculptureMass, from: Vector3, is_free := Callable()) -> Node3D:
	if not is_instance_valid(mass):
		return null
	var free_pieces: Array = []
	for piece in mass.pieces:
		if ObjectTracker.is_trackable(piece) and (not is_free.is_valid() or is_free.call(piece)):
			free_pieces.append(piece)
	return _nearest_piece(from, free_pieces)


## The mess this Zurd can see: every loose object in sight, and with [param count_sculptures] every
## sculpture with an object in sight (one entry per sculpture). What it may notice (§12.1).
func get_mess_in_sight(from: Vector3, count_sculptures: bool) -> Array:
	var mess: Array = []
	for obj in ObjectTracker.active_objects:
		if not ObjectTracker.is_trackable(obj):
			continue
		var piece := obj as MassPiece
		if piece:
			if count_sculptures and not mess.has(piece.mass) and can_see(from, piece.get_center()):
				mess.append(piece.mass)
		elif obj is RigidBody3D and not obj is SculptureMass and can_see(from, obj.global_position):
			mess.append(obj)
	return mess


## The nearest loose object in sight that [param is_free] accepts, for a Passive Zurd to eat.
## Sculptures are left alone. Null when there's none.
func find_loose_target(from: Vector3, is_free := Callable()) -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for obj in ObjectTracker.active_objects:
		if not ObjectTracker.is_trackable(obj) or not obj is RigidBody3D or obj is SculptureMass:
			continue
		if not can_see(from, obj.global_position) or (is_free.is_valid() and not is_free.call(obj)):
			continue
		var distance := from.distance_squared_to(obj.global_position)
		if distance < nearest_distance:
			nearest = obj
			nearest_distance = distance
	return nearest


func _nearest_piece(from: Vector3, pieces: Array) -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for piece: MassPiece in pieces:
		var distance := from.distance_squared_to(piece.get_center())
		if distance < nearest_distance:
			nearest = piece
			nearest_distance = distance
	return nearest
