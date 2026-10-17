class_name SwatProjectile
extends Area3D

var _velocity: Vector3 = Vector3.ZERO
var _time_left: float = 0.0


func _ready() -> void:
    set_physics_process(false)
    body_entered.connect(_on_body_entered)


func launch(start: Vector3, direction: Vector3, up_hint: Vector3, speed: float, max_range: float) -> void:
    global_transform = Transform3D(Basis.looking_at(direction, up_hint), start)
    _velocity = direction * speed
    _time_left = max_range / maxf(speed, 0.001)
    set_physics_process(true)

func _physics_process(delta: float) -> void:
    global_position += _velocity * delta 
    _time_left -= delta
    if _time_left <= 0.0:
        queue_free()

func _on_body_entered(body: Node3D) -> void:
    if is_queued_for_deletion():
        return 
    if body.has_method(&"take_swat"):
        body.call(&"take_swat", _velocity)
    queue_free()