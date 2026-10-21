class_name SwatEmitter
extends Node3D

@export_group("Projectile")
@export var projectile_scene: PackedScene 
@export var projectile_speed: float = 120.0
@export var max_range: float = 70.0
@export var muzzle_offset: float = 3.0

@export_group("Formation")
@export var row_counts: Array[int] = [4,3,4]
@export var slot_spacing: float = 1.6
@export var row_spacing: float = 0.8
@export_range(0.0, 30.0, 0.1, "degrees") var spread_degrees: float = 4.0
@export_range(0.0, 10.0, 0.1, "degrees") var jitter_degrees: float = 0.5


func _ready() -> void:
    EventBus.swat_requested.connect(_on_swat_requested)

func _on_swat_requested(screen_uv: Vector2) -> void: 
    if not projectile_scene:
        push_warning("SwatEmitter: No projectile_scene assigned")
        return 

    var viewport: Viewport = get_viewport()
    var camera: Camera3D = viewport.get_camera_3d()
    if camera == null:
        return 
    
    var screen_pos: Vector2 = screen_uv * viewport.get_visible_rect().size
    var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
    var aim: Vector3 = camera.project_ray_normal(screen_pos)

    var right: Vector3 = aim.cross(camera.global_basis.y).normalized()
    var up: Vector3 = right.cross(aim).normalized()

    var slots: Array[Vector2] = _build_slots()
    var tan_per_unit: float = tan(deg_to_rad(spread_degrees)) / maxf(_get_max_extent(slots), 0.001)
    var jitter_tan: float  = tan(deg_to_rad(jitter_degrees))
    var formation_center: Vector3 = ray_origin + aim * muzzle_offset

    for slot in slots:
        var jitter: Vector2 = Vector2.from_angle(randf() *TAU) * sqrt(randf()) * jitter_tan
        var tilt: Vector2 = slot * tan_per_unit + jitter
        var direction: Vector3 = (aim + right * tilt.x + up * tilt.y).normalized()
        var start: Vector3 = formation_center + right * slot.x + up * slot.y
        _fire(start, direction, up)


func _fire(start: Vector3, direction: Vector3, up_hint: Vector3) -> void:
    var instance = projectile_scene.instantiate()
    var projectile = instance as SwatProjectile
    if not projectile:
        push_error("SwatEmitter: projectile_scene root must be a SwatProjectile.")
        instance.queue_free()
        return 
    
    EventBus.spawn_requested.emit(projectile)
    if not projectile.is_inside_tree():
        push_warning("SwatEmitter: No world picked up the spawn request.")
        projectile.queue_free()
        return 
    
    projectile.launch(start, direction, up_hint, projectile_speed, max_range)

func _build_slots() -> Array[Vector2]:
    var slots: Array[Vector2] = []
    var row_count = row_counts.size()
    for row in row_count:
        var row_item_count = row_counts[row]
        var y = ((row_count - 1) * 0.5 - row) * slot_spacing
        for col in row_item_count:
            var x = (col - (row_item_count -1)* 0.5) * slot_spacing
            slots.append(Vector2(x,y))
    return slots


func _get_max_extent(slots: Array[Vector2]) -> float:
    var extent = 0.0
    for slot in slots:
        extent = maxf(extent, slot.length())
    return extent
