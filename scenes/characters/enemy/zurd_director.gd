class_name ZurdDirector
extends Node

## Runs the Zurds as a group (Zurd Core Design Doc): the shared anger ([ZurdAnger]), which Zurds are
## Hostile, who is going after what (one Zurd per target), and the Zurds the world starts with. One
## per world, in GameSystems. Every Zurd in the [constant Zurd.GROUP] group is directed, whoever
## spawned it.

@export var zurd_scene: PackedScene

@export_group("Starting Zurds")
## Zurds spawned when the world starts: alone or in pairs, around the ship.
@export var starting_zurds: int = 3
## How far from the ship they start, on the ground plane.
@export var spawn_distance: Vector2 = Vector2(80.0, 150.0)
## Their height relative to the ship's.
@export var spawn_height: Vector2 = Vector2(-5.0, 15.0)
## How far apart the two Zurds of a pair start.
@export var pair_spacing: float = 8.0
## Least height above the ground (Environment layer) where they start.
@export var spawn_ground_clearance: float = 10.0

@export_group("Anger")
## Mess (loose objects plus sculptures, each sculpture counting one) before launches add anger.
@export var tolerated_mess: int = 15
## Added per launch while the loose objects are over the limit.
@export var mess_anger: float = 0.05
## Parts a sculpture may have before growing it adds anger (a hard cut-off).
@export var tolerated_sculpture_size: int = 15
## Added per part a sculpture gains beyond the limit.
@export var sculpture_anger: float = 0.03
## Added per swat, ram or launched-object hit on a Zurd.
@export var attack_anger: float = 0.1
## Seconds without a launch or a provocation before anger starts to fall.
@export var calm_delay: float = 3.0
## How fast anger falls, per second.
@export var decay_rate: float = 0.05

@export_group("Hostility")
## Least time a Zurd stays Hostile before it can calm down.
@export var hostile_cooldown: float = 10.0

@export_group("Appetite")
## The chance a Passive Zurd decides to eat a loose object it sees, when the Zurds are calm. It
## rises to 1 at full anger (see [method get_appetite]).
@export_range(0.0, 1.0) var calm_appetite: float = 0.5

@export_group("Testing")
## Shows the testing HUD (anger, Zurds, mess) for playtests.
@export var show_testing_hud: bool = true
@export var testing_hud_scene: PackedScene

## The shared anger. Its settings come from the exports above when the world starts.
var anger := ZurdAnger.new()

## Each sculpture's part count when last seen, so growth is counted once.
var _mass_sizes: Dictionary[SculptureMass, int] = {}
## Who is going after what: target (a loose object or a sculpture's piece) -> the Zurd that claimed
## it. Untyped, because a target may have been freed.
var _claims: Dictionary = {}
var _reported_anger: float = 0.0


func _ready() -> void:
	_apply_settings()
	EventBus.object_launched.connect(_on_object_launched)
	EventBus.zurd_stunned.connect(_on_zurd_attacked)
	EventBus.zurd_driven_off.connect(_on_zurd_attacked)
	if show_testing_hud and testing_hud_scene:
		add_child(testing_hud_scene.instantiate())
	# After the world is ready: it picks up spawn requests in its own _ready, which runs after ours.
	_spawn_starting_zurds.call_deferred()


func _physics_process(delta: float) -> void:
	anger.update(delta)
	_drop_stale_claims()
	_check_sculpture_growth()
	_update_hostility()
	if absf(anger.value - _reported_anger) >= 0.01 or (anger.value == 0.0 and _reported_anger != 0.0):
		_reported_anger = anger.value
		EventBus.zurd_anger_changed.emit(anger.value)


## Spawns a Zurd at [param at].
func spawn_zurd(at: Vector3) -> Zurd:
	if zurd_scene == null:
		push_error("ZurdDirector: No zurd_scene assigned.")
		return null
	var zurd := zurd_scene.instantiate() as Zurd
	if zurd == null:
		push_error("ZurdDirector: zurd_scene's root must be a Zurd.")
		return null
	zurd.director = self
	EventBus.spawn_requested.emit(zurd)
	if not zurd.is_inside_tree():
		push_warning("ZurdDirector: No world picked up the spawn request.")
		zurd.free()
		return null
	zurd.global_position = at
	return zurd


func get_zurds() -> Array[Zurd]:
	var zurds: Array[Zurd] = []
	for node in get_tree().get_nodes_in_group(Zurd.GROUP):
		var zurd := node as Zurd
		if zurd and not zurd.is_queued_for_deletion():
			zurds.append(zurd)
	return zurds


## Loose objects in the world: tracked bodies that aren't sculptures.
func get_loose_objects() -> Array[RigidBody3D]:
	var loose: Array[RigidBody3D] = []
	for obj in ObjectTracker.active_objects:
		if ObjectTracker.is_trackable(obj) and obj is RigidBody3D and not obj is SculptureMass:
			loose.append(obj)
	return loose


## The chance a Passive Zurd decides to eat a loose object it sees: [member calm_appetite] when the
## Zurds are calm, rising to 1 with the anger.
func get_appetite() -> float:
	return lerpf(calm_appetite, 1.0, anger.value)


## The mess the Zurds care about: loose objects plus sculptures, each sculpture counting one.
func get_mess_count() -> int:
	return get_loose_objects().size() + get_sculptures().size()


## Claims [param target] for [param zurd], so other Zurds leave it alone, and drops its other
## claims. Returns false when another Zurd already has it, unless [param take_over].
func claim(zurd: Zurd, target: Node3D, take_over := false) -> bool:
	if not take_over and is_claimed_by_other(target, zurd):
		return false
	release(zurd)
	_claims[target] = zurd
	return true


## Drops every claim of [param zurd].
func release(zurd: Zurd) -> void:
	for target in _claims.keys():
		if _claims[target] == zurd:
			_claims.erase(target)


## True when a Zurd other than [param zurd] is going after [param target].
func is_claimed_by_other(target: Node3D, zurd: Zurd) -> bool:
	var holder: Variant = _claims.get(target)
	return holder != null and holder != zurd and _still_holds(holder, target)


## Sculptures that aren't clouds, from the objects fused into them.
func get_sculptures() -> Array[SculptureMass]:
	var masses: Array[SculptureMass] = []
	for obj in ObjectTracker.active_objects:
		var piece := obj as MassPiece
		if piece and ObjectTracker.is_trackable(piece) and not masses.has(piece.mass):
			masses.append(piece.mass)
	return masses


func _apply_settings() -> void:
	anger.tolerated_mess = tolerated_mess
	anger.mess_anger = mess_anger
	anger.tolerated_sculpture_size = tolerated_sculpture_size
	anger.sculpture_anger = sculpture_anger
	anger.attack_anger = attack_anger
	anger.calm_delay = calm_delay
	anger.decay_rate = decay_rate


func _on_object_launched(_obj: RigidBody3D) -> void:
	anger.on_launch(get_mess_count())


## A claim counts while its Zurd is alive and still going after that target.
func _still_holds(holder: Variant, target: Variant) -> bool:
	return (is_instance_valid(holder) and not holder.is_queued_for_deletion()
			and is_instance_valid(target) and holder.get_target() == target)


func _drop_stale_claims() -> void:
	for target in _claims.keys():
		if not _still_holds(_claims[target], target):
			_claims.erase(target)


func _on_zurd_attacked(_zurd: Node3D) -> void:
	anger.on_zurd_attacked()


## Adds anger for sculptures that grew past the size limit since the last check, by comparing part
## counts, so a merge and the combine that follows it are counted once.
func _check_sculpture_growth() -> void:
	var seen: Dictionary[SculptureMass, int] = {}
	for mass in get_sculptures():
		var size := mass.get_part_count()
		var before: int = _mass_sizes.get(mass, 0)
		if size > before:
			anger.on_sculpture_grew(size - before, size)
		seen[mass] = size
	_mass_sizes = seen


## Makes as many Zurds Hostile as the anger calls for: the nearest to the mess first. Hostile Zurds
## calm down (the furthest first) only after the hostile cooldown.
func _update_hostility() -> void:
	var available: Array[Zurd] = []
	for zurd in get_zurds():
		zurd.director = self
		if not zurd.is_driven_off():
			available.append(zurd)
	var wanted := anger.get_hostile_count(available.size())
	# A Zurd finishing its target before calming down counts as calmed already.
	var hostile := available.filter(func(zurd: Zurd) -> bool: return zurd.is_hostile and not zurd.is_calming)
	if hostile.size() == wanted:
		return
	var mess := _get_mess_positions()
	var by_distance := func(a: Zurd, b: Zurd) -> bool: return _distance_to_mess(a, mess) < _distance_to_mess(b, mess)
	if hostile.size() < wanted:
		var calm := available.filter(func(zurd: Zurd) -> bool: return not zurd.is_hostile or zurd.is_calming)
		calm.sort_custom(by_distance)
		for i in mini(wanted - hostile.size(), calm.size()):
			calm[i].set_hostile(true)
	else:
		hostile.sort_custom(by_distance)
		hostile.reverse()
		var to_calm := hostile.size() - wanted
		for zurd: Zurd in hostile:
			if to_calm == 0:
				break
			if zurd.hostile_time >= hostile_cooldown:
				zurd.set_hostile(false)
				to_calm -= 1


## Where the mess is: every loose object, and every object of a sculpture over the size limit. With
## no mess (anger from attacks only), the ship.
func _get_mess_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for body in get_loose_objects():
		positions.append(body.global_position)
	for mass in get_sculptures():
		if mass.get_part_count() > anger.tolerated_sculpture_size:
			for piece in mass.pieces:
				positions.append(piece.get_center())
	if positions.is_empty():
		var ship := get_tree().get_first_node_in_group(PlayerShip.GROUP) as Node3D
		if ship:
			positions.append(ship.global_position)
	return positions


func _distance_to_mess(zurd: Zurd, mess: Array[Vector3]) -> float:
	var nearest := INF
	for point in mess:
		nearest = minf(nearest, zurd.global_position.distance_squared_to(point))
	return nearest


## Places the starting Zurds around the ship: one on its own, then pairs, and so on.
func _spawn_starting_zurds() -> void:
	var ship := get_tree().get_first_node_in_group(PlayerShip.GROUP) as Node3D
	var center := ship.global_position if ship else Vector3.ZERO
	var previous := Vector3.ZERO
	for i in starting_zurds:
		var at: Vector3
		if i % 2 == 1:
			# The second of a pair starts next to the first.
			var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			at = previous + side * pair_spacing
		else:
			var angle := randf() * TAU
			var distance := randf_range(spawn_distance.x, spawn_distance.y)
			at = center + Vector3(cos(angle), 0.0, sin(angle)) * distance
			at.y = center.y + randf_range(spawn_height.x, spawn_height.y)
		at.y = maxf(at.y, _get_ground_height(at, ship) + spawn_ground_clearance)
		previous = at
		spawn_zurd(at)


func _get_ground_height(at: Vector3, ship: Node3D) -> float:
	if ship == null:
		return -INF
	var from := Vector3(at.x, 2000.0, at.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4000.0, 1)
	var hit := ship.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else -INF
