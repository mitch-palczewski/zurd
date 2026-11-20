class_name ZurdDirector
extends Node

## Runs the Zurds as a cast (Zurd Core Design Doc §12). It spawns them by role when the world starts:
## Shadows around the ship, Grazers in packs spread over the map, Sentinels at the landmarks. It moves
## the packs: each pack's middle roams the grazing disc, heads for loose objects it smells and keeps
## away from the other packs, and its Grazers wander around it, eating what they find. It keeps one
## Zurd per target, tells Zurds that see the ship launch, tells a Sentinel when its sculpture grows,
## sends Sentinels to sculptures that have settled (left unchanged for [member settle_time]),
## spawning more Sentinels up to a cap, and sets the Zurds that see a new cloud chasing it. Each Zurd
## keeps its own anger and turns Hostile by itself. One per world, in GameSystems. Every Zurd in the
## [constant Zurd.GROUP] group is directed, whoever spawned it.

## The group of the hand-placed marker nodes Sentinels watch (one Sentinel per landmark).
const LANDMARK_GROUP := &"zurd_landmarks"
## The sunflower spiral's turn between points, so they spread evenly over the disc.
const GOLDEN_ANGLE := PI * (3.0 - sqrt(5.0))
## How often (seconds) the Sentinels' homes are checked.
const SENTINEL_CHECK_INTERVAL := 0.5
## How often (seconds) the packs sniff for loose objects and check the ground under them.
const PACK_SNIFF_INTERVAL := 0.5
## Seconds a roaming pack heads for one spot before it picks another.
const PACK_ROAM_TIME := 90.0


## A pack of Grazers (Zurd Core Design Doc §12.7). Its middle roams; its members wander around it.
class GrazerPack:
	## Its middle (world), kept above the ground.
	var center: Vector3
	## The height it roams at; it rises or sinks to food it smells.
	var height: float
	## Where it's heading: the loose object it smells, else a spot it roams to.
	var goal: Vector3
	var has_goal: bool = false
	var smells_food: bool = false
	## Seconds before a roaming pack picks a new spot.
	var roam_left: float = 0.0


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
## Middle (world X, Z) of the disc the Grazer packs roam.
@export var grazing_center: Vector2 = Vector2.ZERO
@export var grazing_radius: float = 1500.0
## Packs hover about the ship's starting height, give or take this.
@export var grazing_height_spread: float = 30.0
## Packs the Grazers are shared out between. Fixed: packs don't merge or split.
@export var pack_count: int = 3
## How far around its pack's middle a Grazer wanders.
@export var pack_radius: float = 60.0
## How far around its pack's middle a Hostile Grazer hunts: loose objects first, then sculptures.
@export var pack_hunt_radius: float = 250.0
## A pack smells loose objects this far from its middle and heads for the nearest. With none, it roams
## to a spot within this distance.
@export var pack_scent: float = 600.0
## Speed a pack's middle moves at.
@export var pack_speed: float = 8.0
## Packs keep about this far apart, so the map stays covered.
@export var pack_spacing: float = 400.0

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
## Shows the testing HUD (the Zurds nearest the ship and their anger) and an anger bar over each Zurd,
## for playtests.
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
var _packs: Array[GrazerPack] = []
var _sentinel_timer: float = 0.0
var _sniff_timer: float = 0.0


func _ready() -> void:
	_rng.randomize()
	EventBus.object_launched.connect(_on_object_launched)
	EventBus.cloud_formed.connect(_on_cloud_formed)
	if show_testing_hud and testing_hud_scene:
		add_child(testing_hud_scene.instantiate())
	if spawn_at_start:
		# After the world is ready: it picks up spawn requests in its own _ready, which runs after ours.
		_spawn_cast.call_deferred()


func _physics_process(delta: float) -> void:
	_time += delta
	_drop_stale_claims()
	_check_sculptures()
	_update_packs(delta)
	_sentinel_timer -= delta
	if _sentinel_timer <= 0.0:
		_sentinel_timer = SENTINEL_CHECK_INTERVAL
		update_sentinels()


## [param count] points spread evenly over the disc of [param radius] around [param center] (a
## sunflower spiral), at [param center]'s height: where the packs start.
static func spread_over_disc(center: Vector3, radius: float, count: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in count:
		var distance := radius * sqrt((i + 0.5) / count)
		var angle := i * GOLDEN_ANGLE
		points.append(center + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance))
	return points


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


## Spawns a Zurd of [param role] (a Grazer when null) at [param at]. A Zurd spawned this way homes
## where it starts: a Grazer around that spot until it joins a pack ([method join_pack]), a Sentinel
## at the nearest free landmark, a Shadow at the next free spot by the ship.
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
	zurd.pack_center = at
	zurd.pack_radius = pack_radius
	zurd.hunt_radius = pack_hunt_radius
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


## Starts a pack of Grazers whose middle is at [param center]; it keeps that height. Returns the
## pack's index.
func add_pack(center: Vector3) -> int:
	var pack := GrazerPack.new()
	pack.center = center
	pack.height = center.y
	_packs.append(pack)
	return _packs.size() - 1


## Makes [param zurd] a member of pack [param index]: it wanders around the pack's middle and, when
## Hostile, hunts around it.
func join_pack(zurd: Zurd, index: int) -> void:
	zurd.pack_index = index
	zurd.pack_center = _packs[index].center
	zurd.pack_radius = pack_radius
	zurd.hunt_radius = pack_hunt_radius


func get_pack_count() -> int:
	return _packs.size()


## The middle (world) of pack [param index].
func get_pack_center(index: int) -> Vector3:
	return _packs[index].center


## Where pack [param index] is heading: the loose object it smells, else a spot it roams to.
func get_pack_goal(index: int) -> Vector3:
	return _packs[index].goal


## True while pack [param index] heads for a loose object it smells.
func is_pack_smelling_food(index: int) -> bool:
	return _packs[index].smells_food


## The Grazers in pack [param index].
func get_pack_members(index: int) -> Array[Zurd]:
	var members: Array[Zurd] = []
	for zurd in get_zurds_with_role(grazer_role):
		if zurd.pack_index == index:
			members.append(zurd)
	return members


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


## A new cloud (Zurd Core Design Doc §12.5): every Zurd that can see it gives chase, except those
## driven off.
func _on_cloud_formed(mass: SculptureMass) -> void:
	var body := mass.get_cloud_body()
	if body == null:
		return
	var radius := CloudSky.get_cloud_radius(body)
	for zurd in get_zurds():
		if not zurd.is_driven_off() and zurd.can_see(body.global_position):
			zurd.start_cloud_chase(mass, radius)


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


## Moves each pack's middle (Zurd Core Design Doc §12.7): toward the loose object it smells (rising
## or sinking to it), else to a spot it roams to at its own height; away from packs closer than the
## spacing; and back onto the grazing disc. Its members follow it.
func _update_packs(delta: float) -> void:
	if _packs.is_empty():
		return
	_sniff_timer -= delta
	if _sniff_timer <= 0.0:
		_sniff_timer = PACK_SNIFF_INTERVAL
		var loose := get_loose_objects()
		for pack in _packs:
			_sniff(pack, loose)
			pack.center.y = maxf(pack.center.y, _get_ground_height(pack.center) + spawn_ground_clearance)
	for pack in _packs:
		pack.roam_left -= delta
		var to_goal := pack.goal - pack.center
		var move := Vector3.ZERO
		if to_goal.length() > maxf(pack_speed * delta, 1.0):
			move = to_goal.normalized()
		elif not pack.smells_food:
			# Reached the spot it roamed to: it picks another at the next sniff.
			pack.has_goal = false
		for other in _packs:
			if other == pack:
				continue
			var offset := Vector3(pack.center.x - other.center.x, 0.0, pack.center.z - other.center.z)
			var distance := offset.length()
			if distance < pack_spacing:
				var away := offset / distance if distance > 0.01 else Vector3.RIGHT.rotated(Vector3.UP, _rng.randf() * TAU)
				move += away * (1.0 - distance / pack_spacing) * 4.0
		pack.center = _onto_disc(pack.center + move.limit_length(1.0) * pack_speed * delta)
	for zurd in get_zurds_with_role(grazer_role):
		if zurd.pack_index >= 0 and zurd.pack_index < _packs.size():
			zurd.pack_center = _packs[zurd.pack_index].center


## Picks where [param pack] heads: the nearest of the [param loose] objects within its scent that no
## other pack is nearer to; else, once it has reached its last spot, smelled food there or roamed too
## long, a new spot within its scent.
func _sniff(pack: GrazerPack, loose: Array[RigidBody3D]) -> void:
	var food: RigidBody3D = null
	var food_distance := pack_scent
	for obj in loose:
		var distance := _flat_distance(pack.center, obj.global_position)
		if distance > food_distance or _is_nearer_another_pack(pack, obj.global_position, distance):
			continue
		food = obj
		food_distance = distance
	if food:
		pack.goal = food.global_position
		pack.has_goal = true
		pack.smells_food = true
		return
	if pack.smells_food or not pack.has_goal or pack.roam_left <= 0.0:
		pack.smells_food = false
		pack.has_goal = true
		pack.roam_left = PACK_ROAM_TIME
		pack.goal = _pick_roam_spot(pack)


func _is_nearer_another_pack(pack: GrazerPack, point: Vector3, distance: float) -> bool:
	for other in _packs:
		if other != pack and _flat_distance(other.center, point) < distance:
			return true
	return false


## A spot within [member pack_scent] of [param pack]'s middle, on the disc and at the pack's own
## height, at least the spacing away from the other packs when one can be found (else the roomiest of
## a few tries).
func _pick_roam_spot(pack: GrazerPack) -> Vector3:
	var level := Vector3(pack.center.x, pack.height, pack.center.z)
	var best := level
	var best_room := -INF
	for attempt in 6:
		var angle := _rng.randf() * TAU
		var spot := _onto_disc(level + Vector3(cos(angle), 0.0, sin(angle)) * pack_scent * sqrt(_rng.randf()))
		var room := INF
		for other in _packs:
			if other != pack:
				room = minf(room, _flat_distance(other.center, spot))
		if room >= pack_spacing:
			return spot
		if room > best_room:
			best_room = room
			best = spot
	return best


## [param point] moved onto the grazing disc, if it's off it.
func _onto_disc(point: Vector3) -> Vector3:
	var flat := Vector2(point.x - grazing_center.x, point.z - grazing_center.y)
	if flat.length() <= grazing_radius:
		return point
	flat = flat.normalized() * grazing_radius
	return Vector3(grazing_center.x + flat.x, point.y, grazing_center.y + flat.y)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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


## An extra Sentinel whose sculpture went becomes a Grazer, in the pack with the fewest Grazers (or
## around where it is, without packs).
func _make_grazer(zurd: Zurd) -> void:
	zurd.is_extra = false
	zurd.home_landmark = null
	zurd.pack_index = -1
	zurd.set_role(grazer_role)
	if _packs.is_empty():
		zurd.pack_center = zurd.global_position
		return
	var smallest := 0
	var smallest_size := get_pack_members(0).size()
	for i in range(1, _packs.size()):
		var members := get_pack_members(i).size()
		if members < smallest_size:
			smallest = i
			smallest_size = members
	join_pack(zurd, smallest)


## Spreads the Shadows' spots over the players' view, in a stable order.
func _assign_shadow_bearings() -> void:
	var shadows := get_zurds_with_role(shadow_role)
	if shadows.is_empty():
		return
	shadows.sort_custom(func(a: Zurd, b: Zurd) -> bool: return a.get_instance_id() < b.get_instance_id())
	var bearings := get_shadow_bearings(shadows.size(), shadow_role.view_arc)
	for i in shadows.size():
		shadows[i].ship_bearing = bearings[i]


## The world's starting cast: the Grazer packs spread over the disc, the Sentinels at the landmarks,
## the Shadows at their spots by the ship.
func _spawn_cast() -> void:
	var ship := _get_ship()
	var start := ship.global_position if ship else Vector3.ZERO
	if grazer_count > 0:
		for center in spread_over_disc(Vector3(grazing_center.x, start.y, grazing_center.y), grazing_radius, maxi(pack_count, 1)):
			center.y += _rng.randf_range(-grazing_height_spread, grazing_height_spread)
			center.y = maxf(center.y, _get_ground_height(center) + spawn_ground_clearance)
			add_pack(center)
	for i in grazer_count:
		var index := i % _packs.size()
		var angle := _rng.randf() * TAU
		var at := _packs[index].center + Vector3(cos(angle), 0.0, sin(angle)) * pack_radius * sqrt(_rng.randf())
		at.y = maxf(at.y, _get_ground_height(at) + spawn_ground_clearance)
		var grazer := spawn_zurd(at, grazer_role)
		if grazer:
			join_pack(grazer, index)
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
