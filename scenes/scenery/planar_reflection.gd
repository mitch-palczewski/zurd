class_name PlanarReflection
extends Node

## Mirror reflection for a flat water surface. A second camera, the active camera mirrored in the
## water plane, renders the scene into a texture that the water's shader
## (assets/shaders/reflecting_pool_water.gdshader) shows. It renders only while the water is on
## screen, at [member resolution_scale] of the screen's size. Its camera leaves out
## [constant NO_REFLECTION_LAYER], where anything below the water goes (a basin seen from below
## would hide the reflection: a camera can't clip at the water). Runs in the game only.

## Render layer the reflection camera leaves out.
const NO_REFLECTION_LAYER := 20

## The water surface. Its mesh is flat and faces up; the plane is its height.
@export var water_mesh: MeshInstance3D
## Size of the reflection picture as a share of the screen's.
@export_range(0.1, 1.0, 0.05) var resolution_scale: float = 0.5
@export_flags_3d_render var cull_mask: int = 0xFFFFF & ~(1 << (NO_REFLECTION_LAYER - 1))
@export var enabled: bool = true

var _viewport: SubViewport
var _camera: Camera3D
var _material: ShaderMaterial
var _active := false


## [param camera] mirrored in [param plane]: the same distance on the other side, looking along the
## mirrored direction. A true mirror flips handedness, so the X axis is turned back to keep a valid
## camera; its picture comes out flipped left to right (the water shader flips it back).
static func mirror_transform(camera: Transform3D, plane: Plane) -> Transform3D:
	var n := plane.normal
	var origin := camera.origin - 2.0 * plane.distance_to(camera.origin) * n
	# bounce() mirrors in the plane (reflect() mirrors through the normal's line).
	var x := -camera.basis.x.bounce(n)
	var y := camera.basis.y.bounce(n)
	var z := camera.basis.z.bounce(n)
	return Transform3D(Basis(x, y, z), origin)


## Whether any of [param box] lies inside the frustum [param planes] (from
## [method Camera3D.get_frustum], normals pointing out).
static func is_box_in_frustum(box: AABB, planes: Array[Plane]) -> bool:
	for plane in planes:
		var outside := true
		for i in 8:
			if not plane.is_point_over(box.get_endpoint(i)):
				outside = false
				break
		if outside:
			return false
	return true


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if water_mesh == null:
		push_warning("PlanarReflection: no water_mesh set on " + str(get_path()))
		return
	var source := water_mesh.get_active_material(0) as ShaderMaterial
	if source == null:
		push_warning("PlanarReflection: the water mesh needs the reflecting pool water ShaderMaterial")
		return
	# Each pool shows its own reflection.
	_material = source.duplicate() as ShaderMaterial
	water_mesh.set_surface_override_material(0, _material)
	water_mesh.layers = 1 << (NO_REFLECTION_LAYER - 1)

	_viewport = SubViewport.new()
	_viewport.name = "ReflectionViewport"
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.gui_disable_input = true
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "ReflectionCamera"
	_camera.cull_mask = cull_mask
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_camera)
	_camera.current = true

	_material.set_shader_parameter("reflection_texture", _viewport.get_texture())
	# After the cameras have moved this frame.
	process_priority = 1000


func _process(_delta: float) -> void:
	if _viewport == null:
		return
	var main_camera := get_viewport().get_camera_3d()
	if not enabled or main_camera == null or not water_mesh.is_visible_in_tree():
		_set_active(false)
		return
	var water_box := water_mesh.global_transform * water_mesh.get_aabb()
	if not is_box_in_frustum(water_box, main_camera.get_frustum()):
		_set_active(false)
		return

	_set_active(true)
	var screen_size := get_viewport().get_visible_rect().size
	_viewport.size = Vector2i((screen_size * resolution_scale).max(Vector2.ONE))
	_camera.cull_mask = cull_mask
	_camera.keep_aspect = main_camera.keep_aspect
	_camera.fov = main_camera.fov
	_camera.near = main_camera.near
	_camera.far = main_camera.far
	_camera.global_transform = mirror_transform(main_camera.get_global_transform_interpolated(), get_water_plane())


## The water surface as a plane facing up.
func get_water_plane() -> Plane:
	return Plane(Vector3.UP, water_mesh.global_transform * water_mesh.get_aabb().get_center())


func _set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	_material.set_shader_parameter("reflection_active", active)
