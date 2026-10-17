class_name ZurdSpawner
extends Node3D


@export_group("Spawn Settings")
@export var zurd_scene: PackedScene 
@export var spawn_radius: float = 100.0
@export var check_interval: float = 3.0


var _active_zurds: Array[Node3D] = []
var _zurd_spawn_check_timer: Timer


func _ready() -> void:
    if not zurd_scene:
        push_warning("ZurdSpawner: No Scene assigned")
        return 
    
    _setup_timer()


func _setup_timer() -> void: 
    _zurd_spawn_check_timer = Timer.new()
    _zurd_spawn_check_timer.wait_time = check_interval
    _zurd_spawn_check_timer.one_shot = false
    _zurd_spawn_check_timer.autostart = true
    _zurd_spawn_check_timer.timeout.connect(_check_spawn_condition)
    add_child(_zurd_spawn_check_timer)


func _check_spawn_condition() -> void:
    _active_zurds = _active_zurds.filter(is_instance_valid)

    if _active_zurds.size() <= 0:
        _spawn_zurd()
        return 
    
    var active_objects_count = ObjectTracker.active_objects.size()
    var obj_zurd_ratio: float = float(active_objects_count) / float(_active_zurds.size())

    if obj_zurd_ratio > 10.0:
        _spawn_zurd()
    

func _spawn_zurd() -> void:
    var zurd := zurd_scene.instantiate() as Node3D
    if not zurd:
        push_error("ZurdSpawner: Failed to intantiate Zurd scene.")
        return
    
    var random_offset := Vector3(
        randf_range(-spawn_radius, spawn_radius),
        randf_range(0.0, spawn_radius * 0.5),
        randf_range(-spawn_radius, spawn_radius)
    )

    EventBus.spawn_requested.emit(zurd)
    zurd.global_position = global_position + random_offset
    _active_zurds.append(zurd)
