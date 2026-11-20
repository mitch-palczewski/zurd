class_name ZurdDirector
extends Node

## Runs the Zurds as a cast (Zurd Core Design Doc §12). It spawns them by role when the world starts:
## Shadows around the ship, Grazers at their patches spread over the map, Sentinels at the landmarks.
## It keeps one Zurd per target, tells Zurds that see the ship launch, tells a Sentinel when its
## sculpture grows, and sends Sentinels to sculptures that have settled (left unchanged for
## [member settle_time]), spawning more Sentinels up to a cap. Each Zurd keeps its own anger and turns
## Hostile by itself. One per world, in GameSystems. Every Zurd in the [constant Zurd.GROUP] group is
## directed, whoever spawned it.

## The group of the hand-placed marker nodes Sentinels watch (one Sentinel per landmark).
const LANDMARK_GROUP := &"zurd_landmarks"
## The sunflower spiral's turn between patches, so they spread evenly over the disc.
const GOLDEN_ANGLE := PI * (3.0 - sqrt(5.0))
## How often (seconds) the Sentinels' homes are checked.
const SENTINEL_CHECK_INTERVAL := 0.5

@export var zurd_scene: PackedScene

@export_group("Cast")
@export var shadow_role: ZurdRole = preload("res://data/zurd_roles/shadow.tres")
@export var grazer_role: ZurdRole = preload("res://data/zurd_roles/grazer.tres")
@export var sentinel_role: ZurdRole = preload("res://data/zurd_roles/sentinel.tres")
@export var shadow_count: int = 3
@export var grazer_count: int = 15
@export var sentinel_count: int = 5
## Most Sentinels at once. When every Sentinel is busy and a settled sculpture has none, a new one
## spawns, up to this.
@export var sentinel_cap: int = 8
## Spawns the cast when the world starts. Tests turn it off and spawn their own Zurds.
@export var spawn_at_start: bool = true

@export_group("Grazing")
## Middle (world X, Z) of the disc the Grazers' patches spread over.
@export var grazing_center: Vector2 = Vector2.ZERO
@export var grazing_radius: float = 1500.0
## Grazers hover about the ship's starting height, give or take this.
@export var grazing_height_spread: float = 30.0

@export_group("Sculptures")
## Parts a sculpture may have before growing it angers the Sentinel watching it, and before a
## Hostile Shadow or Sentinel without one goes after it.
@export var tolerated_sculpture_size: int = 15
## Seconds a sculpture must stay unchanged before a Sentinel comes to watch it.
@export var settle_time: float = 30.0

@export_group("Spawning")
## Least height above the ground (Environment layer) where Zurds start.
@export var spawn_ground_clearance: float = 10.0

@export_group("Testing")
## Shows the testing HUD (the Zurds nearest the ship and their anger) for playtests.
@export var show_testing_hud: bool = true
@export var testing_hud_scene: PackedScene

var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
## Each sculpture's part count when last checked, and the game time it last changed.
var _mass_sizes: Dictionary[SculptureMass, int] = {}
var _mass_changed_at: Dictionary[SculptureMass, float] = {}
## Who is going after what: target (a loose object or a sculpture's piece) -> the Zurd that claimed
## it. Untyped, because a target may have been freed.
var _claims: Dictionary = {}
## The Grazers' patch middles (world), from [method get_patch_centers].
var _patches: Array[Vector3] = []
var _sentinel_timer: float = 0.0


func _ready() -> void:
	_rng.randomize()
	EventBus.object_launched.connect(_on_object_launched)
	if show_testing_hud and testing_hud_scene:
		add_child(testing_hud_scene.instantiate())
	if spawn_at_start:
		# After the world is ready: it picks up spawn requests in its own _ready, which runs after ours.
		_spawn_cast.call_deferred()


func _physics_process(delta: float) -> void:
	_time += delta
	_drop_stale_claims()
	_check_sculptures()
	_sentinel_timer -= delta
	if _sentinel_timer <= 0.0:
		_sentinel_timer = SENTINEL_CHECK_INTERVAL
		update_sentinels()


## [param count] patch middles spread evenly over the disc of [param radius] around [param center]
## (a sunflower spiral), at [param center]'s height.
static func get_patch_centers(center: Vector3, radius: float, count: int) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for i in count:
		var distance := radius * sqrt((i + 0.5) / count)
		var angle := i * GOLDEN_ANGLE
		centers.append(center + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance))
	return centers


## The bearings (radians from the ship's heading) of [param count] Shadows: spread evenly over
## [param arc_degrees] to each side so they stay in the players' view, and shifted a quarter step so
## none sits dead ahead, in the ship's path.
static func get_shadow_bearings(count: int, arc_degrees: float) -> PackedFloat32Array:
	var bearings := PackedFloat32Array()
	if count <= 0:
		return bearings
	var arc := deg_to_rad(arc_degrees)
	var step := 2.0 * arc / count
	for i in count:
		bearings.append(-arc + (i + 0.5) * step + step * 0.25)
	return bearings


## The radius of each Grazer's patch: the disc shared out between them.
func get_patch_radius() -> float:
	return grazing_radius / sqrt(maxf(grazer_count, 1))


## Spawns a Zurd of [param role] (a Grazer when null) at [param at]. A Zurd spawned this way homes
## where it starts: a Grazer's patch around it, a Sentinel at the nearest free landmark, a Shadow at
## the next free spot by the ship.
func spawn_zurd(at: Vector3, role: ZurdRole = null) -> Zurd:
	if zurd_scene == null:
		push_error("ZurdDirector: No zurd_scene assigned.")
		return null
	var zurd := zurd_scene.instantiate() as Zurd
	if zurd == null:
		push_error("ZurdDirector: zurd_scene's root must be a Zurd.")
		return null
	zurd.director = self
	zurd.setup(role if role else grazer_role, _rng)
	EventBus.spawn_requested.emit(zurd)
	if not zurd.is_inside_tree():
		push_warning("ZurdDirector: No world picked up the spawn request.")
		zurd.free()
		return null
	zurd.global_position = at
	zurd.home_point = at
	zurd.patch_center = at
	zurd.patch_radius = get_patch_radius()
	match zurd.role.home:
		ZurdRole.Home.SHIP:
			var ship_distance := zurd.role.ship_distance
			zurd.ship_distance = lerpf(ship_distance.y, ship_distance.x, zurd.temperament.boldness)
			zurd.ship_height = _rng.randf_range(zurd.role.ship_height.x, zurd.role.ship_height.y)
			_assign_shadow_bearings()
		ZurdRole.Home.WATCH:
			zurd.home_landmark = _find_landmark_for(zurd)
	return zurd


func get_zurds() -> Array[Zurd]:
	var zurds: Array[Zurd] = []
	for node in get_tree().get_nodes_in_group(Zurd.GROUP):
		var zurd := node as Zurd
		if zurd and not zurd.is_queued_for_deletion():
			zurds.append(zurd)
	return zurds


## The Zurds of [param role].
func get_zurds_with_role(role: ZurdRole) -> Array[Zurd]:
	var zurds: Array[Zurd] = []
	for zurd in get_zurds():
		if zurd.role == role:
			zurds.append(zurd)
	return zurds


## The landmarks Sentinels watch, placed by hand in the world.
func get_landmarks() -> Array[Node3D]:
	var landmarks: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(LANDMARK_GROUP):
		if node is Node3D:
			landmarks.append(node as Node3D)
	return landmarks


## Loose objects in the world: tracked bodies that aren't sculptures.
func get_loose_objects() -> Array[RigidBody3D]:
	var loose: Array[RigidBody3D] = []
	for obj in ObjectTracker.active_objects:
		if ObjectTracker.is_trackable(obj) and obj is RigidBody3D and not obj is SculptureMass:
			loose.append(obj)
	return loose


## Sculptures that aren't clouds, from the objects fused into them.
func get_sculptures() -> Array[SculptureMass]:
	var masses: Array[SculptureMass] = []
	for obj in ObjectTracker.active_objects:
		var piece := obj as MassPiece
		if piece and ObjectTracker.is_trackable(piece) and not masses.has(piece.mass):
			masses.append(piece.mass)
	return masses


## True once [param mass] has stayed unchanged for [member settle_time].
func is_settled(mass: SculptureMass) -> bool:
	return _mass_changed_at.has(mass) and _time - _mass_changed_at[mass] >= settle_time


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


## Gives the Sentinels their homes (Zurd Core Design Doc §12.2). A Sentinel whose sculpture went (a
## cloud, or eaten away) goes back to a landmark, or becomes a Grazer if it was an extra. Each settled
## sculpture without a Sentinel gets the nearest free one, or a new one up to the cap. Runs every
## half second; tests call it directly.
func update_sentinels() -> void:
	var sentinels := get_zurds_with_role(sentinel_role)
	for sentinel in sentinels:
		if sentinel.home_sculpture != null and not _is_live_sculpture(sentinel.home_sculpture):
			sentinel.home_sculpture = null
			if sentinel.is_extra:
				_make_grazer(sentinel)
			else:
				sentinel.home_landmark = _find_landmark_for(sentinel)
	sentinels = get_zurds_with_role(sentinel_role)
	var watched: Dictionary[SculptureMass, bool] = {}
	for sentinel in sentinels:
		if sentinel.home_sculpture:
			watched[sentinel.home_sculpture] = true
	for mass in get_sculptures():
		if watched.has(mass) or not is_settled(mass):
			continue
		var free := _nearest_free_sentinel(sentinels, mass.get_global_center_of_mass())
		if free == null and sentinels.size() < sentinel_cap:
			free = _spawn_extra_sentinel(mass)
			if free:
				sentinels.append(free)
		if free:
			free.home_sculpture = mass
			free.home_landmark = null
			watched[mass] = true


func _on_object_launched(_obj: RigidBody3D) -> void:
	var ship := _get_ship()
	if ship == null:
		return
	for zurd in get_zurds():
		if zurd.can_see(ship.global_position):
			zurd.on_launch_seen()


## A claim counts while its Zurd is alive and still going after that target.
func _still_holds(holder: Variant, target: Variant) -> bool:
	return (is_instance_valid(holder) and not holder.is_queued_for_deletion()
			and is_instance_valid(target) and holder.get_target() == target)


func _drop_stale_claims() -> void:
	for target in _claims.keys():
		if not _still_holds(_claims[target], target):
			_claims.erase(target)


## Notes when each sculpture last changed (for settling), and tells a Sentinel watching a sculpture
## how much it grew, so a merge and the combine that follows it are counted once.
func _check_sculptures() -> void:
	var sizes: Dictionary[SculptureMass, int] = {}
	var changed: Dictionary[SculptureMass, float] = {}
	var watchers: Dictionary[SculptureMass, Array] = {}
	for zurd in get_zurds():
		if is_instance_valid(zurd.home_sculpture):
			watchers.get_or_add(zurd.home_sculpture, []).append(zurd)
	for mass in get_sculptures():
		var size := mass.get_part_count()
		var before: int = _mass_sizes.get(mass, 0)
		changed[mass] = _time if size != before or not _mass_changed_at.has(mass) else _mass_changed_at[mass]
		if size > before:
			for zurd: Zurd in watchers.get(mass, []):
				zurd.anger.on_sculpture_grew(size - before, size, tolerated_sculpture_size)
		sizes[mass] = size
	_mass_sizes = sizes
	_mass_changed_at = changed


func _is_live_sculpture(mass: SculptureMass) -> bool:
	return is_instance_valid(mass) and not mass.is_queued_for_deletion() and not mass.is_cloud and not mass.pieces.is_empty()


func _nearest_free_sentinel(sentinels: Array[Zurd], to: Vector3) -> Zurd:
	var nearest: Zurd = null
	var nearest_distance := INF
	for sentinel in sentinels:
		if sentinel.home_sculpture or sentinel.is_driven_off():
			continue
		var distance := sentinel.global_position.distance_squared_to(to)
		if distance < nearest_distance:
			nearest = sentinel
			nearest_distance = distance
	return nearest


## A new Sentinel for [param mass], beyond the starting count: it spawns at the landmark nearest the
## sculpture (or well away from it when there are none) and wanders over.
func _spawn_extra_sentinel(mass: SculptureMass) -> Zurd:
	var to := mass.get_global_center_of_mass()
	var at := to + Vector3(300.0, 30.0, 0.0)
	var nearest := INF
	for landmark in get_landmarks():
		var distance := landmark.global_position.distance_squared_to(to)
		if distance < nearest:
			nearest = distance
			at = landmark.global_position
	at.y = maxf(at.y, _get_ground_height(at) + spawn_ground_clearance)
	var sentinel := spawn_zurd(at, sentinel_role)
	if sentinel:
		sentinel.is_extra = true
	return sentinel


## The landmark nearest [param sentinel] that no other Sentinel watches; when every landmark is
## taken, the nearest one anyway (it hangs out near it). Null without landmarks.
func _find_landmark_for(sentinel: Zurd) -> Node3D:
	var taken: Dictionary[Node3D, bool] = {}
	for other in get_zurds_with_role(sentinel_role):
		if other != sentinel and other.home_sculpture == null and is_instance_valid(other.home_landmark):
			taken[other.home_landmark] = true
	var nearest_free: Node3D = null
	var nearest_any: Node3D = null
	var free_distance := INF
	var any_distance := INF
	for landmark in get_landmarks():
		var distance := landmark.global_position.distance_squared_to(sentinel.global_position)
		if distance < any_distance:
			nearest_any = landmark
			any_distance = distance
		if not taken.has(landmark) and distance < free_distance:
			nearest_free = landmark
			free_distance = distance
	return nearest_free if nearest_free else nearest_any


## An extra Sentinel whose sculpture went becomes a Grazer, in the patch with the fewest Grazers.
func _make_grazer(zurd: Zurd) -> void:
	zurd.is_extra = false
	zurd.home_landmark = null
	zurd.set_role(grazer_role)
	if _patches.is_empty():
		zurd.patch_center = zurd.global_position
		zurd.patch_index = -1
		return
	var counts: Array[int] = []
	counts.resize(_patches.size())
	counts.fill(0)
	for other in get_zurds_with_role(grazer_role):
		if other != zurd and other.patch_index >= 0 and other.patch_index < counts.size():
			counts[other.patch_index] += 1
	var emptiest := 0
	for i in counts.size():
		if counts[i] < counts[emptiest]:
			emptiest = i
	zurd.patch_index = emptiest
	zurd.patch_center = _patches[emptiest]


## Spreads the Shadows' spots over the players' view, in a stable order.
func _assign_shadow_bearings() -> void:
	var shadows := get_zurds_with_role(shadow_role)
	if shadows.is_empty():
		return
	shadows.sort_custom(func(a: Zurd, b: Zurd) -> bool: return a.get_instance_id() < b.get_instance_id())
	var bearings := get_shadow_bearings(shadows.size(), shadow_role.view_arc)
	for i in shadows.size():
		shadows[i].ship_bearing = bearings[i]


## The world's starting cast: the Grazers at their patches, the Sentinels at the landmarks, the
## Shadows at their spots by the ship.
func _spawn_cast() -> void:
	var ship := _get_ship()
	var start := ship.global_position if ship else Vector3.ZERO
	_patches = get_patch_centers(Vector3(grazing_center.x, start.y, grazing_center.y), grazing_radius, grazer_count)
	for i in _patches.size():
		var at := _patches[i] + Vector3.UP * _rng.randf_range(-grazing_height_spread, grazing_height_spread)
		at.y = maxf(at.y, _get_ground_height(at) + spawn_ground_clearance)
		_patches[i] = at
		var grazer := spawn_zurd(at, grazer_role)
		if grazer:
			grazer.patch_index = i
	var landmarks := get_landmarks()
	for i in sentinel_count:
		var at := start + Vector3(_rng.randf_range(-200.0, 200.0), 30.0, _rng.randf_range(-200.0, 200.0))
		if not landmarks.is_empty():
			at = landmarks[i % landmarks.size()].global_position + Vector3(_rng.randf_range(-20.0, 20.0), 0.0, _rng.randf_range(-20.0, 20.0))
		at.y = maxf(at.y, _get_ground_height(at) + spawn_ground_clearance)
		spawn_zurd(at, sentinel_role)
	for i in shadow_count:
		spawn_zurd(start, shadow_role)
	# Each starts at its spot, not on the ship (the bearings are known once all of them are in).
	for shadow in get_zurds_with_role(shadow_role):
		var spot := shadow.get_ship_spot()
		spot.y = maxf(spot.y, _get_ground_height(spot) + spawn_ground_clearance)
		shadow.global_position = spot


func _get_ship() -> Node3D:
	return get_tree().get_first_node_in_group(PlayerShip.GROUP) as Node3D


## The height of the ground (the Environment layer) under [param at], or -INF where there's none.
func _get_ground_height(at: Vector3) -> float:
	var world := get_viewport().find_world_3d() if is_inside_tree() else null
	if world == null:
		return -INF
	var from := Vector3(at.x, 2000.0, at.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4000.0, 1)
	var hit := world.direct_space_state.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else -INF
