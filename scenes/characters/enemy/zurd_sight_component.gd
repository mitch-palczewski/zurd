class_name ZurdSightComponent
extends Node

## What a Zurd sees and goes after (Zurd Core Design Doc §4): a vertical cylinder around it, a circle
## on the ground plane covering every height. Targets come from ObjectTracker's list, so seeing needs
## no physics queries.

## Radius of the sight cylinder, on the ground plane.
@export var sight_radius: float = 150.0
## Seconds between looks for a new target.
@export var look_interval: float = 0.25


## True when [param point] is in sight from [param from]: within the radius on the ground plane, at
## any height.
func can_see(from: Vector3, point: Vector3) -> bool:
	return Vector2(point.x - from.x, point.z - from.z).length() <= sight_radius


## A Hostile Zurd's target: the nearest loose object in sight; else the nearest object of the
## largest sculpture in sight with more than [param min_sculpture_size] parts; else the nearest of
## those anywhere, because all Zurds know the world. Only objects [param is_free] accepts count (it
## skips those another Zurd has claimed). Null when there's nothing to go after.
func find_hostile_target(from: Vector3, min_sculpture_size: int, is_free := Callable()) -> Node3D:
	var loose_in_sight: Node3D = null
	var loose_in_sight_distance := INF
	var loose_anywhere: Node3D = null
	var loose_anywhere_distance := INF
	var large_sculptures: Dictionary[SculptureMass, Array] = {}
	for obj in ObjectTracker.active_objects:
		if not ObjectTracker.is_trackable(obj) or (is_free.is_valid() and not is_free.call(obj)):
			continue
		var piece := obj as MassPiece
		if piece:
			if piece.mass.get_part_count() > min_sculpture_size:
				large_sculptures.get_or_add(piece.mass, []).append(piece)
		elif obj is RigidBody3D and not obj is SculptureMass:
			var distance := from.distance_squared_to(obj.global_position)
			if distance < loose_anywhere_distance:
				loose_anywhere = obj
				loose_anywhere_distance = distance
			if distance < loose_in_sight_distance and can_see(from, obj.global_position):
				loose_in_sight = obj
				loose_in_sight_distance = distance
	if loose_in_sight:
		return loose_in_sight

	var largest: SculptureMass = null
	for mass: SculptureMass in large_sculptures:
		var seen := large_sculptures[mass].any(func(p: MassPiece) -> bool: return can_see(from, p.get_center()))
		if seen and (largest == null or mass.get_part_count() > largest.get_part_count()):
			largest = mass
	if largest:
		return _nearest_piece(from, large_sculptures[largest])
	if loose_anywhere:
		return loose_anywhere
	var all_pieces: Array = []
	for mass: SculptureMass in large_sculptures:
		all_pieces.append_array(large_sculptures[mass])
	return _nearest_piece(from, all_pieces)


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


## The nearest sculpture (not a cloud) in sight, for a Passive Zurd to watch. Null when there's none.
func find_sculpture_to_watch(from: Vector3) -> SculptureMass:
	var nearest: SculptureMass = null
	var nearest_distance := INF
	for obj in ObjectTracker.active_objects:
		var piece := obj as MassPiece
		if piece == null or not ObjectTracker.is_trackable(piece) or not can_see(from, piece.get_center()):
			continue
		var distance := from.distance_squared_to(piece.get_center())
		if distance < nearest_distance:
			nearest = piece.mass
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
