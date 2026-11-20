class_name Zurd
extends CharacterBody3D

## A Zurd (Zurd Core Design Doc §5, §6, §12). Its role ([ZurdRole]) gives it a home and what angers
## it most; its temperament ([ZurdTemperament]) makes it an individual. It has its own anger
## ([ZurdAnger]), raised by what it perceives itself, and turns Hostile from it.
## Passive, it decides object by object whether to eat the loose objects it sees (more often the
## angrier it is), goes after those at an easy pace and eats them slowly. Otherwise it keeps to its
## home: a Shadow to its spot around the ship in the players' view, a Grazer to its patch, a Sentinel
## circling the landmark or sculpture it watches. Hostile, it hunts by role: a Shadow the loose
## objects nearest the ship, a Grazer its patch (sculptures included), a Sentinel its sculpture. One
## calming down finishes the target it has first.
## A timid Zurd flees and calms after one swat; a bolder one is stunned by the first swats and gets
## angrier with each, until the last drives it away from the ship for a while. A launched object
## flying into it only stuns it, and it eats that object afterwards.

const GROUP := &"zurds"

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

@export_group("Hits")
## Boldness below which a Zurd is timid: one swat drives it off and calms it.
@export_range(0.0, 1.0) var timid_below: float = 0.3
## Swats that drive off a Zurd that isn't timid: from just above timid to the boldest.
@export var bold_swats: Vector2i = Vector2i(2, 4)
@export var stun_time: float = 1.5
## Speed a hit knocks the Zurd back at, easing to a stop over the stun.
@export var knockback_speed: float = 8.0
## Least speed a launched object needs to stun the Zurd by flying into it.
@export var object_hit_speed: float = 8.0
## Least time between two hits that count, so one swat (a spread of projectiles) or one ram (contact
## over several frames) counts once.
@export var hit_cooldown: float = 0.4

@export_group("Driven Off")
## How far from the ship (on the ground plane) a driven-off Zurd flies before it stops.
@export var retreat_distance: float = 300.0
## How long it stays away before it comes back.
@export var away_time: float = 20.0

@export_group("Look")
## Placeholder tint while Hostile.
@export var hostile_color: Color = Color(1.0, 0.1, 0.1, 0.45)

## Set by the [ZurdDirector] that directs this Zurd.
var director: ZurdDirector
## Its role (set by [method setup]); null until then, when it acts like a Grazer without a patch.
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
## Swats that drive it off, from its boldness.
var drive_off_swats: int = 3

## A Grazer's patch: its middle (world) and radius on the ground plane, and its index among the
## director's patches (-1 for a Zurd spawned by hand, whose patch is around where it spawned). The
## director sets these, and the home point, once the Zurd is in place.
var patch_center: Vector3
var patch_radius: float = 200.0
var patch_index: int = -1
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
## The launched object that stunned the Zurd; it eats it after the stun.
var _caught: Node3D = null
var _hostile_material: StandardMaterial3D
var _role_material: StandardMaterial3D
## Seconds until a hit counts again.
var _hit_cooldown_left: float = 0.0
var _reported_anger: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	_hostile_material = _make_tint(hostile_color)
	if hit_area:
		hit_area.body_entered.connect(_on_hit_area_body_entered)
	if role == null:
		_apply_anger_settings()
	_update_look()
	_update_health_bar()


## Gives the Zurd [param new_role] and rolls its temperament with [param rng]: its sight, what angers
## it, its speeds and how many swats drive it off. Called once, by the director, before it spawns.
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

	_look_timer -= delta
	if _look_timer <= 0.0 or not ObjectTracker.is_trackable(_target):
		_look_timer = sight_component.look_interval
		_notice_mess()
		_target = _choose_target()

	var chasing := is_hostile or (_target != null and _target == _caught)
	var passive_eat_speed := mouth_component.eat_duration / maxf(passive_eat_time, 0.01)
	mouth_component.set_target(_target, 1.0 if chasing else passive_eat_speed)
	if _target and mouth_component.is_eating():
		movement_component.process_eating(self, _target, mouth_component.get_mouth_position(), delta)
	elif _target:
		movement_component.process_hunt(self, _target, delta, -1.0 if chasing else movement_component.feeding_speed)
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


## A launched object [param obj] flew into the Zurd: it's stunned and angered (not counted as a
## swat), and eats the object once the stun is over.
func take_object_hit(obj: RigidBody3D) -> void:
	if is_driven_off() or _hit_cooldown_left > 0.0:
		return
	_hit_cooldown_left = hit_cooldown
	_drop_target()
	_caught = obj
	if director:
		director.claim(self, obj, true)
	anger.on_attacked()
	_stun(obj.linear_velocity)
	EventBus.zurd_stunned.emit(self)


func _apply_anger_settings() -> void:
	if role:
		anger.configure(role, temperament)
	anger.hostile_threshold = hostile_threshold
	anger.calm_threshold = calm_threshold
	anger.calm_delay = calm_delay
	anger.decay_rate = decay_rate
	drive_off_swats = temperament.get_drive_off_swats(timid_below, bold_swats)


## Turns Hostile when its anger calls for it, and calms (after the hostile cooldown) when it has
## fallen below the calm threshold.
func _update_hostility() -> void:
	if is_driven_off():
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


## The target to go after now, claimed so no other Zurd goes after it too. A calming Zurd keeps its
## target until it's eaten or gone, then turns Passive.
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
	var home := role.home if role else ZurdRole.Home.PATCH
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
			return sight_component.find_patch_target(global_position, patch_center, patch_radius, is_free)


## With nothing to eat: a Shadow keeps to its spot by the ship, a Grazer wanders its patch, a
## Sentinel circles what it watches.
func _process_home(delta: float) -> void:
	var home := role.home if role else ZurdRole.Home.PATCH
	var travel := role.travel_speed if role else 0.0
	match home:
		ZurdRole.Home.SHIP:
			movement_component.process_wander(self, get_ship_spot(), role.home_radius, delta, travel)
		ZurdRole.Home.WATCH:
			movement_component.process_watch(self, get_watch_center(), delta)
		_:
			movement_component.process_wander(self, patch_center, patch_radius, delta, travel)


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


## Only a fast object counts: food the Zurd flies into is slow, so it doesn't stun itself.
func _on_hit_area_body_entered(body: Node3D) -> void:
	var obj := body as RigidBody3D
	if obj == null or obj is SculptureMass or not ObjectTracker.is_trackable(obj):
		return
	if obj.linear_velocity.length() >= object_hit_speed:
		take_object_hit(obj)
