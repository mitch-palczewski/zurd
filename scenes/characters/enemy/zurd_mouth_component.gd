class_name ZurdMouthComponent
extends Area3D

## Eats the Zurd's target: a loose object, or one object of a sculpture mass. The target has to stay
## in the mouth for [member eat_duration]. If it leaves the mouth or stops being a valid target, or
## [method cancel_eating] is called, the object is unharmed and the timer starts over.

signal object_eaten(obj: Node3D)

## Seconds a target must stay in the mouth to be eaten (Sculpture-Mass Design Doc "Eat duration").
@export var eat_duration: float = 1.5
@export var owner_body: CharacterBody3D

var active_target: Node3D = null
var _excepted_body: PhysicsBody3D = null
var _is_eating: bool = false
var _eat_time: float = 0.0

func _ready() -> void:
    if not owner_body:
        owner_body = get_parent() as CharacterBody3D


func _physics_process(delta: float) -> void:
    if not _is_target_in_mouth():
        cancel_eating()
        return

    _is_eating = true
    _eat_time += delta
    if _eat_time >= eat_duration:
        _eat_target()


func set_target(obj: Node3D) -> void:
    if obj != active_target:
        cancel_eating()
        active_target = obj
    _update_collision_exception()


## True while the target is in the mouth and being eaten.
func is_eating() -> bool:
    return _is_eating


## Interrupts eating; the target is unharmed.
func cancel_eating() -> void:
    _is_eating = false
    _eat_time = 0.0


func get_mouth_position() -> Vector3:
    var mouth_shape := _get_mouth_shape()
    return mouth_shape.global_position if mouth_shape else global_position


func _eat_target() -> void:
    var target := active_target
    cancel_eating()
    # Keep the collision exception until the next set_target(), so the Zurd isn't suddenly inside
    # a solid mass.
    active_target = null
    object_eaten.emit(target)

    if target is MassPiece:
        # The mass removes the object, emits EventBus.object_eaten and drops any dependents.
        var piece := target as MassPiece
        piece.mass.request_eat(piece, owner_body)
    else:
        EventBus.object_eaten.emit(owner_body, target, null)
        target.queue_free()


func _is_target_in_mouth() -> bool:
    if not ObjectTracker.is_trackable(active_target):
        return false
    if active_target is MassPiece:
        return _overlaps_piece(active_target as MassPiece)
    if active_target is PhysicsBody3D:
        return overlaps_body(active_target)
    return false


## True if this specific object of the mass is in the mouth, not just any part of the mass.
func _overlaps_piece(piece: MassPiece) -> bool:
    if not overlaps_body(piece.mass):
        return false
    var mouth_shape := _get_mouth_shape()
    if not mouth_shape or not mouth_shape.shape:
        return false

    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = mouth_shape.shape
    query.transform = mouth_shape.global_transform
    query.collision_mask = collision_mask
    for result in get_world_3d().direct_space_state.intersect_shape(query, 32):
        if result.collider == piece.mass and piece.mass.get_piece_for_shape_index(result.shape) == piece:
            return true
    return false


func _get_mouth_shape() -> CollisionShape3D:
    for child in get_children():
        if child is CollisionShape3D:
            return child as CollisionShape3D
    return null


## Lets the Zurd fly into its target: excepts the target's body (the whole mass for a fused object)
## from the Zurd's collisions, and moves the exception when the target or its mass changes.
func _update_collision_exception() -> void:
    var body := _get_target_body()
    if is_instance_valid(_excepted_body) and _excepted_body == body:
        return
    if is_instance_valid(_excepted_body):
        _set_collision_exception(_excepted_body, false)
    _excepted_body = body
    if body:
        _set_collision_exception(body, true)


func _get_target_body() -> PhysicsBody3D:
    if not ObjectTracker.is_trackable(active_target):
        return null
    if active_target is MassPiece:
        return (active_target as MassPiece).mass
    return active_target as PhysicsBody3D


func _set_collision_exception(obj: PhysicsBody3D, ignore: bool) -> void:
    if not is_instance_valid(obj) or not owner_body:
        return
    if ignore:
        owner_body.add_collision_exception_with(obj)
    else:
        owner_body.remove_collision_exception_with(obj)
