class_name Zurd
extends CharacterBody3D

## A Zurd (Zurd Core Design Doc §5, §6, §12). Its role ([ZurdRole]) gives it a home and what angers
## it most; its temperament ([ZurdTemperament]) makes it an individual. It has its own anger
## ([ZurdAnger]), raised by what it perceives itself, and turns Hostile from it.
## Passive, it decides object by object whether to eat the loose objects it sees (more often the
## angrier it is), goes after those at an easy pace and eats them slowly. Otherwise it keeps to its
## home: a Shadow to its spot around the ship in the players' view (swooping back when it has been
## out of view), a Grazer to its pack, a Sentinel circling the landmark or sculpture it watches.
## Hostile, it hunts by role: a Shadow the loose objects nearest the ship, a Grazer around its pack
## (sculptures included), a Sentinel its sculpture. One calming down finishes the target it has
## first. It keeps out of the space around the ship, except to fetch food there.
## A timid Zurd flees and calms after one swat; a bolder one is stunned by the first swats and gets
## angrier with each, until the last drives it away from the ship for a while. A launched object
## flying into it is food: it snatches it, eats it quickly and calms a little (§12.7).
## It grows with every part it eats, up to a cap, and stays big: bigger is slower and takes more
## swats (§12.4). A new cloud it sees sets it chasing the cloud, bouncing off it, until it gives up
## (§12.5).

const GROUP := &"zurds"
## Testing anger bar: seconds between redraws, how many redraws back its rising or falling arrow
## compares with, and its length.
const ANGER_BAR_INTERVAL := 0.25
const ANGER_BAR_TREND_STEPS := 3
const ANGER_BAR_CELLS := 8

@export_group("Components")
@export var sight_component: ZurdSightComponent
@export var movement_component: ZurdMovementComponent
@export var mouth_component: ZurdMouthComponent
## Catches launched objects flying into the Zurd (objects layer). Larger than the body, so an object
## is caught before it bounces off.
@export var hit_area: Area3D
## The placeholder health bar: swats taken so far.
@export var health_label: Label3D
## Gets the placeholder role and Hostile tints.
@export var body_mesh: MeshInstance3D

@export_group("Anger")
## Anger at which it turns Hostile.
@export_range(0.0, 1.0) var hostile_threshold: float = 0.6
## A Hostile Zurd calms only once its anger is below this.
@export_range(0.0, 1.0) var calm_threshold: float = 0.3
## Seconds without anything holding or raising its anger before it starts to fall.
@export var calm_delay: float = 3.0
## How fast its anger falls, per second (times its patience).
@export var decay_rate: float = 0.05
## Least time it stays Hostile before it can calm down.
@export var hostile_cooldown: float = 10.0

@export_group("Passive")
## Seconds a Passive Zurd takes to eat a bite (a Hostile one takes the mouth's eat_duration).
@export var passive_eat_time: float = 4.0
## How long a Passive Zurd keeps its decision to eat an object or leave it, before deciding again.
@export var appetite_recheck: float = 20.0

@export_group("Feeding")
## Least speed a launched object needs, flying into the Zurd, to count as thrown to it. Food the Zurd
## flies into itself is slow.
@export var object_hit_speed: float = 8.0
## How much faster than a Hostile bite it eats an object thrown to it.
@export var catch_eat_speed: float = 4.0

@export_group("Hits")
## Boldness below which a Zurd is timid: one swat drives it off and calms it.
@export_range(0.0, 1.0) var timid_below: float = 0.3
## Swats that drive off a Zurd that isn't timid: from just above timid to the boldest, before growth
## adds more.
@export var bold_swats: Vector2i = Vector2i(2, 4)
@export var stun_time: float = 1.5
## Speed a hit knocks the Zurd back at, easing to a stop over the stun.
@export var knockback_speed: float = 8.0
## Least time between two hits that count, so one swat (a spread of projectiles) or one ram (contact
## over several frames) counts once.
@export var hit_cooldown: float = 0.4

@export_group("Driven Off")
## How far from the ship (on the ground plane) a driven-off Zurd flies before it stops.
@export var retreat_distance: float = 300.0
## How long it stays away before it comes back.
@export var away_time: float = 20.0

@export_group("Growth")
## Size it gains per part it eats (1 is the Zurd as built). It stays big.
@export var growth_per_bite: float = 0.1
## The largest it grows.
@export var max_size: float = 4.5
## Bigger is slower: its speeds are multiplied by its size to the power of minus this (at 0.3, a
## 4.5× Zurd moves at about 64%).
@export var size_slowdown: float = 0.3
## Growth that adds one swat to drive it off. A timid Zurd still flees at the first.
@export var growth_per_swat: float = 1.0

@export_group("Shadow")
## Seconds a Shadow may be out of the camera's view before it swoops back to its spot.
@export var view_lost_time: float = 1.5
## Speed it swoops back at (the ship flies at up to 55 m/s).
@export var swoop_speed: float = 90.0

@export_group("Cloud Chase")
## Seconds it chases a new cloud before it gives up and goes home.
@export var chase_time: float = 15.0
## Speed it chases the cloud at.
@export var chase_speed: float = 50.0
## Seconds a bounce off the cloud lasts.
@export var bounce_time: float = 0.8
## Speed it bounces off at, easing to a stop over the bounce.
@export var bounce_speed: float = 25.0
## How fast it spins while it bounces off (radians per second).
@export var bounce_spin: float = 12.0

@export_group("Look")
## Placeholder tint while Hostile.
@export var hostile_color: Color = Color(1.0, 0.1, 0.1, 0.45)

## Set by the [ZurdDirector] that directs this Zurd.
var director: ZurdDirector
## Its role (set by [method setup]); null until then, when it acts like a Grazer without a pack.
var role: ZurdRole
var temperament := ZurdTemperament.new()
var anger := ZurdAnger.new()
var is_hostile: bool = false
## True while a Hostile Zurd calming down finishes the target it has; then it turns Passive.
var is_calming: bool = false
## Seconds since the Zurd turned Hostile.
var hostile_time: float = 0.0
## Swats since it last came back from being driven off.
var swats: int = 0
## Swats that drive it off, from its boldness and growth.
var drive_off_swats: int = 3
## Its size: 1 is the Zurd as built. It starts at its temperament's body size and grows as it eats
## (see [method set_size]).
var size: float = 1.0
## How often it has bounced off a cloud.
var cloud_bounces: int = 0

## A Grazer's pack: its middle (world; the director moves it as the pack roams), the radius the
## members wander in, the radius a Hostile member hunts in, and the pack's index among the director's
## packs (-1 for a Zurd spawned by hand, whose pack stays where it spawned).
var pack_center: Vector3
var pack_radius: float = 60.0
var hunt_radius: float = 250.0
var pack_index: int = -1
## A Shadow's spot: its bearing from the ship's heading (radians), distance and height from the ship.
var ship_bearing: float = 0.0
var ship_distance: float = 200.0
var ship_height: float = 0.0
## A Sentinel's home: the landmark it watches, or the sculpture it took on (that comes first). With
## neither, it watches [member home_point].
var home_landmark: Node3D
var home_sculpture: SculptureMass
var home_point: Vector3
## A Sentinel spawned beyond the director's starting count: it becomes a Grazer when its sculpture
## goes.
var is_extra: bool = false

var _target: Node3D = null
## Game time, for appetite decisions.
var _time: float = 0.0
## A Passive Zurd's decisions about objects it has seen: object -> [eat it?, decided until]. Untyped
## keys, because an object may have been freed.
var _appetite: Dictionary = {}
## Mess it has noticed (loose objects and sculptures), so each angers it once. Untyped keys.
var _noticed: Dictionary = {}
## Mess in view at its last look.
var _mess_in_view: int = 0
var _look_timer: float = 0.0
var _stun_left: float = 0.0
var _retreating: bool = false
var _away_left: float = 0.0
var _away_spot: Vector3
## Where the Zurd was driven off, for retreating when there's no ship to flee from.
var _retreat_origin: Vector3
## A launched object thrown to it, which it eats before anything else.
var _caught: Node3D = null
var _hostile_material: StandardMaterial3D
var _role_material: StandardMaterial3D
## Seconds until a hit counts again.
var _hit_cooldown_left: float = 0.0
var _reported_anger: float = 0.0
## Seconds a Shadow has been out of the camera's view, and whether it's swooping back.
var _out_of_view_time: float = 0.0
var _swooping: bool = false
## The cloud it's chasing, the cloud's radius in its body's space, the chase time left and the time
## left of a bounce off it.
var _chased_cloud: SculptureMass
var _cloud_radius: float = 1.0
var _chase_left: float = 0.0
var _bounce_left: float = 0.0
## Its parts at size 1: shape radii (the shapes are its own copies) and node positions.
var _base_radii: Dictionary[CollisionShape3D, float] = {}
var _base_positions: Dictionary[Node3D, Vector3] = {}
var _base_mesh_scale: Vector3 = Vector3.ONE
var _body_shape: CollisionShape3D
## Testing: the anger bar over it, its redraw timer and its anger at the last redraws.
var _anger_bar: Label3D
var _anger_bar_timer: float = 0.0
var _anger_history: Array[float] = []


func _ready() -> void:
	add_to_group(GROUP)
	_hostile_material = _make_tint(hostile_color)
	_capture_parts()
	_make_anger_bar()
	if hit_area:
		hit_area.body_entered.connect(_on_hit_area_body_entered)
	EventBus.object_eaten.connect(_on_object_eaten)
	if role == null:
		_apply_anger_settings()
	set_size(temperament.body)
	_update_look()
	_update_health_bar()


## Gives the Zurd [param new_role] and rolls its temperament with [param rng]: its sight, what angers
## it, its speeds, its size and how many swats drive it off. Called once, by the director, before it
## spawns.
func setup(new_role: ZurdRole, rng: RandomNumberGenerator) -> void:
	temperament = ZurdTemperament.roll(new_role, rng)
	if movement_component:
		movement_component.wander_speed *= temperament.pace
		movement_component.hunting_speed *= temperament.pace
		movement_component.feeding_speed *= temperament.pace
		movement_component.watch_pause *= temperament.curiosity
	set_role(new_role)


## Switches the Zurd to [param new_role], keeping its temperament and its anger (an extra Sentinel
## becoming a Grazer).
func set_role(new_role: ZurdRole) -> void:
	role = new_role
	if sight_component:
		sight_component.sight_radius = role.sight_radius
	_apply_anger_settings()
	_look_timer = 0.0
	if is_inside_tree():
		_update_look()


func get_role_name() -> String:
	return role.role_name if role else "Zurd"


## How much it wants food: its greed when calm, rising to 1 at full anger.
func get_appetite() -> float:
	return lerpf(temperament.greed, 1.0, anger.value)


## True when [param point] is in its sight.
func can_see(point: Vector3) -> bool:
	return sight_component != null and sight_component.can_see(global_position, point)


## The director saw the ship launch while the ship was in this Zurd's sight.
func on_launch_seen() -> void:
	anger.on_launch_seen(_mess_in_view)


## Where a Shadow's spot is now: its bearing from the ship's heading, at its distance and height.
func get_ship_spot() -> Vector3:
	var ship := _get_ship()
	if ship == null:
		return global_position
	var forward := -ship.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized().rotated(Vector3.UP, ship_bearing)
	return ship.global_position + forward * ship_distance + Vector3.UP * ship_height


## What a Sentinel watches now: its sculpture's middle, else its landmark, else its home point.
func get_watch_center() -> Vector3:
	if is_instance_valid(home_sculpture) and not home_sculpture.pieces.is_empty():
		return home_sculpture.get_global_center_of_mass()
	if is_instance_valid(home_landmark):
		return home_landmark.global_position
	return home_point


## Its body's radius (metres), which grows with it.
func get_body_radius() -> float:
	if _body_shape and _body_shape.shape is SphereShape3D:
		return (_body_shape.shape as SphereShape3D).radius
	return 3.0 * size


## What its size does to its speeds: 1 at size 1, less when bigger.
func get_speed_factor() -> float:
	return pow(size, -size_slowdown)


## Makes it [param new_size] (1 is the Zurd as built), at most [member max_size] (Zurd Core Design Doc
## §12.4). Its mesh, body, mouth, hit area and labels scale together, its speeds fall with size and
## the swats that drive it off rise. The body node itself stays unscaled: Godot advises against
## scaling physics bodies.
func set_size(new_size: float) -> void:
	var old := size
	size = clampf(new_size, 0.1, maxf(max_size, 0.1))
	if not is_equal_approx(size, old):
		_apply_size(old)


func _physics_process(delta: float) -> void:
	if not sight_component or not movement_component or not mouth_component:
		return
	_time += delta
	if is_hostile:
		hostile_time += delta
	_hit_cooldown_left -= delta
	anger.update(delta)
	_update_hostility()
	_report_anger()
	_update_anger_bar(delta)
	_update_view(delta)

	if _stun_left > 0.0:
		_stun_left -= delta
		movement_component.process_stunned(self, delta)
		return
	if _retreating:
		_process_retreat(delta)
		return
	if _away_left > 0.0:
		_away_left -= delta
		if _away_left <= 0.0:
			_come_back()
		# It stays around where it retreated to until it comes back.
		movement_component.process_wander(self, _away_spot, retreat_distance * 0.2, delta)
		return
	if _chase_left > 0.0:
		_process_cloud_chase(delta)
		return

	_look_timer -= delta
	if _look_timer <= 0.0 or not ObjectTracker.is_trackable(_target):
		_look_timer = sight_component.look_interval
		_notice_mess()
		_target = _choose_target()

	var caught := _target != null and _target == _caught
	var eat_speed := mouth_component.eat_duration / maxf(passive_eat_time, 0.01)
	if caught:
		eat_speed = catch_eat_speed
	elif is_hostile:
		eat_speed = 1.0
	mouth_component.set_target(_target, eat_speed)
	if _target and mouth_component.is_eating():
		movement_component.process_eating(self, _target, mouth_component.get_mouth_position(), delta)
	elif _target:
		movement_component.process_hunt(self, _target, delta, -1.0 if is_hostile or caught else movement_component.feeding_speed)
	else:
		_process_home(delta)


## Whether this Zurd, while Passive, wants to eat [param obj]: decided with its appetite the first
## time it considers the object, and again once the decision is [member appetite_recheck] old.
func wants_to_eat(obj: Node3D) -> bool:
	var decision: Array = _appetite.get(obj, [])
	if decision.is_empty() or _time >= decision[1]:
		decision = [randf() < get_appetite(), _time + appetite_recheck]
		_appetite[obj] = decision
		if _appetite.size() > 64:
			_forget_freed(_appetite)
	return decision[0]


## Turns the Zurd Hostile or calms it. A driven-off Zurd can't turn Hostile until it's back. A Hostile
## Zurd calming down while it has a target finishes it first ([member is_calming]).
func set_hostile(hostile: bool) -> void:
	if hostile:
		is_calming = false
		if not is_hostile and not is_driven_off():
			_set_state(true)
	elif is_hostile:
		if ObjectTracker.is_trackable(_target):
			is_calming = true
		else:
			_set_state(false)


func is_stunned() -> bool:
	return _stun_left > 0.0


## True from the drive-off swat until the Zurd has stayed away for its away time.
func is_driven_off() -> bool:
	return _retreating or _away_left > 0.0


## True while it chases a new cloud.
func is_chasing_cloud() -> bool:
	return _chase_left > 0.0


## True while a Shadow swoops back into the players' view.
func is_swooping() -> bool:
	return _swooping


## The object the Zurd is going after, or null.
func get_target() -> Node3D:
	return _target


## A swat, or the ship ramming the Zurd ([param swat_velocity]: the hit's direction and speed). The
## last of its [member drive_off_swats] drives it off (a timid Zurd's first); the ones before stun it
## and anger it. A Zurd that's been driven off ignores swats, and a hit within the hit cooldown of the
## last one doesn't count.
func take_swat(swat_velocity: Vector3) -> void:
	if is_driven_off() or _hit_cooldown_left > 0.0:
		return
	_hit_cooldown_left = hit_cooldown
	swats += 1
	_drop_target()
	if swats >= drive_off_swats:
		_drive_off()
		EventBus.zurd_driven_off.emit(self)
	else:
		anger.on_attacked()
		_stun(swat_velocity)
		EventBus.zurd_stunned.emit(self)
	_update_health_bar()


## A launched object [param obj] flew into the Zurd: food thrown to it (Zurd Core Design Doc §12.7).
## It snatches it out of the air, turns onto it and eats it quickly, then carries on; each part of it
## calms the Zurd a little. No stun, and not a swat. A driven-off Zurd, one chasing a cloud and one
## still eating a thrown object ignore it.
func catch_object(obj: RigidBody3D) -> void:
	if is_driven_off() or is_chasing_cloud() or ObjectTracker.is_trackable(_caught):
		return
	_drop_target()
	_caught = obj
	_target = obj
	# Snatched: it stops flying on past the Zurd.
	obj.linear_velocity = velocity
	if director:
		director.claim(self, obj, true)


## A cloud formed where it can see it (Zurd Core Design Doc §12.5): it drops its target and its
## hostility (its anger falls to the calm threshold) and chases the cloud for [member chase_time],
## bouncing off it, then gives up and goes home. [param body_radius] is the cloud's radius in its
## cloud body's space, before it grows. A driven-off Zurd ignores it.
func start_cloud_chase(cloud: SculptureMass, body_radius: float) -> void:
	if is_driven_off():
		return
	_drop_target()
	_caught = null
	_set_state(false)
	anger.value = minf(anger.value, anger.calm_threshold)
	_chased_cloud = cloud
	_cloud_radius = body_radius
	_chase_left = chase_time
	_bounce_left = 0.0


func _apply_anger_settings() -> void:
	if role:
		anger.configure(role, temperament)
	anger.hostile_threshold = hostile_threshold
	anger.calm_threshold = calm_threshold
	anger.calm_delay = calm_delay
	anger.decay_rate = decay_rate
	_update_drive_off_swats()


## Swats that drive it off: by boldness, plus one per [member growth_per_swat] it has grown since it
## spawned. A timid Zurd still flees at the first.
func _update_drive_off_swats() -> void:
	drive_off_swats = temperament.get_drive_off_swats(timid_below, bold_swats)
	if growth_per_swat > 0.0 and not temperament.is_timid(timid_below):
		drive_off_swats += floori(maxf(size - temperament.body, 0.0) / growth_per_swat + 0.0001)


## Turns Hostile when its anger calls for it, and calms (after the hostile cooldown) when it has
## fallen below the calm threshold. Not while it's away or chasing a cloud.
func _update_hostility() -> void:
	if is_driven_off() or is_chasing_cloud():
		return
	var calm := not is_hostile or is_calming
	var wants := anger.should_be_hostile(not calm)
	if wants and calm:
		set_hostile(true)
	elif not wants and not calm and hostile_time >= hostile_cooldown:
		set_hostile(false)


## Notices the mess in sight it hadn't seen before; what's beyond its tolerance angers it.
func _notice_mess() -> void:
	var mess := sight_component.get_mess_in_sight(global_position, role != null and role.sculptures_count_as_mess)
	_mess_in_view = mess.size()
	var new_items := 0
	for item in mess:
		if not _noticed.has(item):
			_noticed[item] = true
			new_items += 1
	if new_items > 0:
		anger.on_noticed(new_items, _mess_in_view)
	if _noticed.size() > 128:
		_forget_freed(_noticed)


## The target to go after now, claimed so no other Zurd goes after it too. An object thrown to it
## comes first. A calming Zurd keeps its target until it's eaten or gone, then turns Passive.
func _choose_target() -> Node3D:
	if ObjectTracker.is_trackable(_caught):
		return _caught
	_caught = null
	if is_calming:
		if ObjectTracker.is_trackable(_target):
			return _target
		_set_state(false)
	var is_free := func(obj: Node3D) -> bool: return director == null or not director.is_claimed_by_other(obj, self)
	var target: Node3D
	if is_hostile:
		target = _find_hostile_target(is_free)
	else:
		var appealing := func(obj: Node3D) -> bool: return is_free.call(obj) and wants_to_eat(obj)
		target = sight_component.find_loose_target(global_position, appealing)
	if director:
		if target:
			director.claim(self, target)
		else:
			director.release(self)
	return target


## What a Hostile Zurd goes after, by role (Zurd Core Design Doc §12.2).
func _find_hostile_target(is_free: Callable) -> Node3D:
	var tolerated: int = director.tolerated_sculpture_size if director else 15
	var home := role.home if role else ZurdRole.Home.PACK
	match home:
		ZurdRole.Home.SHIP:
			var ship := _get_ship()
			var near := ship.global_position if ship else global_position
			return sight_component.find_hostile_target(global_position, tolerated, is_free, near)
		ZurdRole.Home.WATCH:
			if is_instance_valid(home_sculpture):
				var piece := sight_component.find_piece_of(home_sculpture, global_position, is_free)
				if piece:
					return piece
			return sight_component.find_hostile_target(global_position, tolerated, is_free)
		_:
			return sight_component.find_area_target(global_position, pack_center, maxf(hunt_radius, pack_radius), is_free)


## With nothing to eat: a Shadow keeps to its spot by the ship (moving along with the ship, and
## swooping back when it has been out of view), a Grazer wanders around its pack's middle, a Sentinel
## circles what it watches.
func _process_home(delta: float) -> void:
	var home := role.home if role else ZurdRole.Home.PACK
	var travel := (role.travel_speed if role else 0.0) * get_speed_factor()
	match home:
		ZurdRole.Home.SHIP:
			var spot := get_ship_spot()
			var ship := _get_ship() as CharacterBody3D
			var carry := ship.velocity if ship else Vector3.ZERO
			if _swooping and global_position.distance_to(spot) > role.home_radius:
				movement_component.process_fly_to(self, spot, swoop_speed * get_speed_factor(), delta, carry)
				return
			if _swooping:
				# At its spot but still out of view: it waits another while before swooping again.
				_swooping = false
				_out_of_view_time = 0.0
			movement_component.process_wander(self, spot, role.home_radius, delta, travel, carry)
		ZurdRole.Home.WATCH:
			movement_component.process_watch(self, get_watch_center(), delta)
		_:
			movement_component.process_wander(self, pack_center, pack_radius, delta, travel)


## A Shadow counts how long it has been out of the camera's view; past [member view_lost_time] it
## swoops back to its spot (Zurd Core Design Doc §12.7), until it's in view again.
func _update_view(delta: float) -> void:
	if role == null or role.home != ZurdRole.Home.SHIP:
		return
	if _is_in_view():
		_out_of_view_time = 0.0
		_swooping = false
		return
	_out_of_view_time += delta
	if _out_of_view_time >= view_lost_time:
		_swooping = true


## True when the players can see it: inside the current camera's view. Without a camera it counts as
## seen. (With the three-wall rig, any wall's camera will count.)
func _is_in_view() -> bool:
	var camera := get_viewport().get_camera_3d()
	return camera == null or camera.is_position_in_frustum(global_position)


## Chases the cloud: flies at its middle and bounces off with a spin whenever it reaches it, until
## the chase time is up. It can't eat the cloud.
func _process_cloud_chase(delta: float) -> void:
	_chase_left -= delta
	var body: Node3D = _chased_cloud.get_cloud_body() if is_instance_valid(_chased_cloud) else null
	if _chase_left <= 0.0 or body == null:
		_end_cloud_chase()
		return
	if _bounce_left > 0.0:
		_bounce_left -= delta
		rotate_object_local(Vector3.UP, bounce_spin * delta)
		movement_component.process_stunned(self, delta)
		return
	var center := body.global_position
	var reach := _cloud_radius * body.global_basis.get_scale().x + get_body_radius()
	if global_position.distance_to(center) <= reach:
		_bounce_off(center)
		return
	movement_component.process_fly_to(self, center, chase_speed * get_speed_factor(), delta)


## Boing: knocked away from the cloud's middle and up a little.
func _bounce_off(center: Vector3) -> void:
	var away := global_position - center
	if away.length_squared() < 0.0001:
		away = Vector3.UP
	velocity = (away.normalized() + Vector3.UP * 0.5).normalized() * bounce_speed
	_bounce_left = bounce_time
	cloud_bounces += 1


func _end_cloud_chase() -> void:
	_chase_left = 0.0
	_bounce_left = 0.0
	_chased_cloud = null
	_look_timer = 0.0


func _stun(push: Vector3) -> void:
	_stun_left = stun_time
	if not push.is_zero_approx():
		velocity = push.normalized() * knockback_speed


func _drop_target() -> void:
	_target = null
	_look_timer = 0.0
	if director:
		director.release(self)
	mouth_component.cancel_eating()
	mouth_component.set_target(null)


func _set_state(hostile: bool) -> void:
	is_calming = false
	if hostile == is_hostile:
		return
	is_hostile = hostile
	hostile_time = 0.0
	_look_timer = 0.0
	_update_look()
	EventBus.zurd_state_changed.emit(self, hostile)


## A timid Zurd is calmed by being driven off at once; every driven-off Zurd comes back calm.
func _drive_off() -> void:
	_set_state(false)
	anger.calm_down()
	_retreat_origin = global_position
	_stun_left = 0.0
	_caught = null
	_end_cloud_chase()
	_retreating = true


func _process_retreat(delta: float) -> void:
	var ship := _get_ship()
	var away_from := ship.global_position if ship else _retreat_origin
	var offset := global_position - away_from
	if Vector2(offset.x, offset.z).length() >= retreat_distance:
		_retreating = false
		_away_left = away_time
		_away_spot = global_position
		return
	movement_component.process_retreat(self, away_from, delta)


func _forget_freed(memory: Dictionary) -> void:
	for obj in memory.keys():
		if not is_instance_valid(obj):
			memory.erase(obj)


func _come_back() -> void:
	swats = 0
	_update_health_bar()


func _get_ship() -> Node3D:
	return get_tree().get_first_node_in_group(PlayerShip.GROUP) as Node3D


func _report_anger() -> void:
	if absf(anger.value - _reported_anger) >= 0.01 or (anger.value == 0.0 and _reported_anger != 0.0):
		_reported_anger = anger.value
		EventBus.zurd_anger_changed.emit(self, anger.value)


## Every bite it takes grows it; a bite of an object thrown to it also calms it a little.
func _on_object_eaten(actor: Node3D, obj: Node3D, _mass: SculptureMass) -> void:
	if actor != self:
		return
	if obj == _caught:
		anger.on_fed()
	set_size(size + growth_per_bite)


# ==============================================================================
# SIZE
# ==============================================================================

## Notes its parts at size 1, and gives it its own copies of their shapes: the scene shares them
## between all Zurds, and each grows on its own.
func _capture_parts() -> void:
	_body_shape = _first_shape(self)
	for shape_node: CollisionShape3D in [_body_shape, _first_shape(mouth_component), _first_shape(hit_area)]:
		if shape_node == null or not shape_node.shape is SphereShape3D:
			continue
		shape_node.shape = shape_node.shape.duplicate()
		_base_radii[shape_node] = (shape_node.shape as SphereShape3D).radius
		_base_positions[shape_node] = shape_node.position
	if health_label:
		_base_positions[health_label] = health_label.position
	if body_mesh:
		_base_mesh_scale = body_mesh.scale


## Scales its parts from size [param old] to [member size], and its speeds and the distances it keeps
## with them.
func _apply_size(old: float) -> void:
	var ratio := size / old
	var speed_ratio := pow(ratio, -size_slowdown)
	for shape_node in _base_radii:
		(shape_node.shape as SphereShape3D).radius = _base_radii[shape_node] * size
	for node in _base_positions:
		node.position = _base_positions[node] * size
	if body_mesh:
		body_mesh.scale = _base_mesh_scale * size
	if movement_component:
		movement_component.wander_speed *= speed_ratio
		movement_component.hunting_speed *= speed_ratio
		movement_component.feeding_speed *= speed_ratio
		movement_component.retreat_speed *= speed_ratio
		movement_component.ground_clearance *= ratio
		movement_component.avoidance_distance *= ratio
		movement_component.watch_distance *= ratio
		movement_component.bob_height *= ratio
	_update_drive_off_swats()
	_update_health_bar()


static func _first_shape(parent: Node) -> CollisionShape3D:
	if parent == null:
		return null
	for child in parent.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


# ==============================================================================
# LOOK (placeholders)
# ==============================================================================

## The placeholder tints: red while Hostile, else its role's faint colour.
func _update_look() -> void:
	if body_mesh == null:
		return
	if is_hostile:
		body_mesh.material_overlay = _hostile_material
		return
	if role and role.tint.a > 0.0:
		if _role_material == null or _role_material.albedo_color != role.tint:
			_role_material = _make_tint(role.tint)
		body_mesh.material_overlay = _role_material
	else:
		body_mesh.material_overlay = null


func _make_tint(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _update_health_bar() -> void:
	if health_label:
		health_label.text = "■".repeat(swats) + "□".repeat(maxi(drive_off_swats - swats, 0))


## Testing: a bar over the Zurd showing its anger, so playtesters see which Zurds are heating up
## (Zurd Core Design Doc §12.7). Only while the director's testing HUD is on. It keeps its size on
## screen at any distance, and hides far away.
func _make_anger_bar() -> void:
	if director == null or not director.show_testing_hud:
		return
	_anger_bar = Label3D.new()
	_anger_bar.name = "AngerBar"
	_anger_bar.position = Vector3(0.0, 8.0, 0.0)
	_anger_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_anger_bar.fixed_size = true
	_anger_bar.pixel_size = 0.0008
	_anger_bar.font_size = 32
	_anger_bar.outline_size = 8
	_anger_bar.outline_modulate = Color(0.0, 0.0, 0.0, 0.6)
	_anger_bar.visibility_range_end = 800.0
	_anger_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_anger_bar)
	_base_positions[_anger_bar] = _anger_bar.position


## Redraws the anger bar: filled to its anger, green through yellow to red at the hostile threshold
## (red while Hostile), with arrows while it's rising or falling.
func _update_anger_bar(delta: float) -> void:
	if _anger_bar == null:
		return
	_anger_bar_timer -= delta
	if _anger_bar_timer > 0.0:
		return
	_anger_bar_timer = ANGER_BAR_INTERVAL
	_anger_history.append(anger.value)
	if _anger_history.size() > ANGER_BAR_TREND_STEPS + 1:
		_anger_history.pop_front()
	var change := anger.value - _anger_history[0]
	var filled := clampi(roundi(anger.value * ANGER_BAR_CELLS), 0, ANGER_BAR_CELLS)
	var bar := "█".repeat(filled) + "░".repeat(ANGER_BAR_CELLS - filled)
	# An arrow on each side keeps the bar centred over the Zurd.
	if change > 0.005:
		bar = "▲ %s ▲" % bar
	elif change < -0.005:
		bar = "▼ %s ▼" % bar
	_anger_bar.text = bar
	_anger_bar.modulate = _get_anger_color()


func _get_anger_color() -> Color:
	var hot := Color(1.0, 0.2, 0.15)
	if is_hostile:
		return hot
	var calm := Color(0.35, 1.0, 0.35)
	var warm := Color(1.0, 0.9, 0.25)
	var heat := clampf(anger.value / maxf(anger.hostile_threshold, 0.01), 0.0, 1.0)
	return calm.lerp(warm, heat * 2.0) if heat < 0.5 else warm.lerp(hot, heat * 2.0 - 1.0)


## Only a fast object counts as thrown to it: food the Zurd flies into is slow.
func _on_hit_area_body_entered(body: Node3D) -> void:
	var obj := body as RigidBody3D
	if obj == null or obj is SculptureMass or not ObjectTracker.is_trackable(obj):
		return
	if obj.linear_velocity.length() >= object_hit_speed:
		catch_object(obj)
