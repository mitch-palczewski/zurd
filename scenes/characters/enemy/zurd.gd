class_name Zurd
extends CharacterBody3D

## A Zurd (Zurd Core Design Doc §5, §6). Passive, it wanders around its home and only nibbles a loose
## object it drifts into. Hostile, it hunts loose objects, then large sculptures. The [ZurdDirector]
## decides which Zurds are Hostile. Its first swats stun it; the last drives it away from the ship
## for a while. A launched object flying into it only stuns it, and it eats that object afterwards.

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
## Gets the placeholder Hostile tint.
@export var body_mesh: MeshInstance3D

@export_group("Wandering")
## How far from its home a Passive Zurd wanders. Loose: hunting can take it far away.
@export var home_radius: float = 100.0
## How close a loose object must be to the mouth for a Passive Zurd to nibble it.
@export var nibble_distance: float = 3.0
## Passive eating speed, compared with Hostile eating.
@export var nibble_speed: float = 0.33

@export_group("Hits")
## The swat that drives the Zurd off; the swats before it stun it.
@export var drive_off_swats: int = 3
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
## How long it stays away before heading home.
@export var away_time: float = 20.0

@export_group("Look")
## Placeholder tint while Hostile.
@export var hostile_color: Color = Color(1.0, 0.1, 0.1, 0.45)

## Where the Zurd wanders while Passive. Whoever spawns it sets it; otherwise where it starts.
var home: Vector3
## Set by the [ZurdDirector] that directs this Zurd.
var director: ZurdDirector
var is_hostile: bool = false
## Seconds since the Zurd turned Hostile.
var hostile_time: float = 0.0
## Swats since it last came back from being driven off.
var swats: int = 0

var _home_set: bool = false
var _target: Node3D = null
var _look_timer: float = 0.0
var _stun_left: float = 0.0
var _retreating: bool = false
var _away_left: float = 0.0
var _away_spot: Vector3
## The launched object that stunned the Zurd; it eats it after the stun.
var _caught: Node3D = null
var _hostile_material: StandardMaterial3D
## Seconds until a hit counts again.
var _hit_cooldown_left: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	if not _home_set:
		home = global_position
	_hostile_material = StandardMaterial3D.new()
	_hostile_material.albedo_color = hostile_color
	_hostile_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hostile_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if hit_area:
		hit_area.body_entered.connect(_on_hit_area_body_entered)
	_update_health_bar()


func _physics_process(delta: float) -> void:
	if not sight_component or not movement_component or not mouth_component:
		return
	if is_hostile:
		hostile_time += delta
	_hit_cooldown_left -= delta

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
		movement_component.process_wander(self, _away_spot, home_radius, delta)
		return

	_look_timer -= delta
	if _look_timer <= 0.0 or not ObjectTracker.is_trackable(_target):
		_look_timer = sight_component.look_interval
		_target = _choose_target()

	var chasing := is_hostile or (_target != null and _target == _caught)
	mouth_component.set_target(_target, 1.0 if chasing else nibble_speed)
	if _target and mouth_component.is_eating():
		if chasing:
			movement_component.process_eating(self, _target, mouth_component.get_mouth_position(), delta)
		else:
			movement_component.process_hover(self, delta)
	elif _target:
		movement_component.process_hunt(self, _target, delta, -1.0 if chasing else movement_component.wander_speed)
	else:
		movement_component.process_wander(self, home, home_radius, delta)


## Sets where the Zurd wanders while Passive.
func set_home(at: Vector3) -> void:
	home = at
	_home_set = true


## Called by the [ZurdDirector]. A driven-off Zurd can't turn Hostile until it's back.
func set_hostile(hostile: bool) -> void:
	if hostile == is_hostile or (hostile and is_driven_off()):
		return
	is_hostile = hostile
	hostile_time = 0.0
	_look_timer = 0.0
	if body_mesh:
		body_mesh.material_overlay = _hostile_material if hostile else null
	EventBus.zurd_state_changed.emit(self, hostile)


func is_stunned() -> bool:
	return _stun_left > 0.0


## True from the drive-off swat until the Zurd has stayed away for its away time.
func is_driven_off() -> bool:
	return _retreating or _away_left > 0.0


## The object the Zurd is going after, or null.
func get_target() -> Node3D:
	return _target


## A swat, or the ship ramming the Zurd ([param swat_velocity]: the hit's direction and speed). The
## first swats stun it; the last drives it off. A Zurd that's been driven off ignores swats, and a
## hit within the hit cooldown of the last one doesn't count.
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
		_stun(swat_velocity)
		EventBus.zurd_stunned.emit(self)
	_update_health_bar()


## A launched object [param obj] flew into the Zurd: it's stunned (not counted as a swat), and eats
## the object once the stun is over.
func take_object_hit(obj: RigidBody3D) -> void:
	if is_driven_off() or _hit_cooldown_left > 0.0:
		return
	_hit_cooldown_left = hit_cooldown
	_drop_target()
	_caught = obj
	_stun(obj.linear_velocity)
	EventBus.zurd_stunned.emit(self)


func _choose_target() -> Node3D:
	if ObjectTracker.is_trackable(_caught):
		return _caught
	_caught = null
	if is_hostile:
		var tolerated: int = director.anger.tolerated_sculpture_size if director else 15
		return sight_component.find_hostile_target(global_position, tolerated)
	return sight_component.find_nibble_target(mouth_component.get_mouth_position(), nibble_distance)


func _stun(push: Vector3) -> void:
	_stun_left = stun_time
	if not push.is_zero_approx():
		velocity = push.normalized() * knockback_speed


func _drop_target() -> void:
	_target = null
	_look_timer = 0.0
	mouth_component.cancel_eating()
	mouth_component.set_target(null)


func _drive_off() -> void:
	set_hostile(false)
	_stun_left = 0.0
	_caught = null
	_retreating = true


func _process_retreat(delta: float) -> void:
	var ship := get_tree().get_first_node_in_group(PlayerShip.GROUP) as Node3D
	var away_from := ship.global_position if ship else home
	var offset := global_position - away_from
	if Vector2(offset.x, offset.z).length() >= retreat_distance:
		_retreating = false
		_away_left = away_time
		_away_spot = global_position
		return
	movement_component.process_retreat(self, away_from, delta)


func _come_back() -> void:
	swats = 0
	_update_health_bar()


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
