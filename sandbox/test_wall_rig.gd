extends Node3D

## Throwaway mock-up of the exhibit's three projected walls (claude/plans/2026-11-17-wall-rig-mockup-plan.md).
## zurd_world02 runs in a background viewport and you fly the ship as usual. Its picture goes onto
## three wall screens in a small room, in one of three ways (Tab cycles them):
## - Three cameras: one per wall, each cut to the wall's exact shape as seen from the sweet spot.
## - One camera, fair: one wide camera, its image projected onto the walls from the sweet spot.
## - One camera, stretched: the same image cut into slices by wall width.
## You're a visitor in the room: 1 sweet spot, 2 left, 3 right, 4 close to the middle wall,
## 5 above. Right mouse drag looks around; H hides the label.
## Room coordinates: the floor under the sweet spot is the origin, guests look along -Z.

const WORLD := "res://scenes/world/zurd_world02.tscn"
const NEAR := 0.05
const FAR := 12000.0
const MODE_NAMES := ["Three cameras", "One camera, fair (projected by angle)", "One camera, stretched (sliced by width)"]
const SPOT_NAMES := ["sweet spot", "off to the left", "off to the right", "close to the middle wall", "above the room"]
const FAIR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;

// One wide camera's image, projected onto the walls from the sweet spot.
uniform sampler2D image : source_color, filter_linear;
uniform vec3 eye;
uniform float tan_half_h;
uniform float t_top;
uniform float t_bottom;
uniform vec4 outside_color : source_color = vec4(0.06, 0.06, 0.08, 1.0);

varying vec3 room_pos;

void vertex() {
	room_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 d = room_pos - eye;
	float depth = -d.z;
	vec3 color = outside_color.rgb;
	if (depth > 0.001) {
		vec2 uv = vec2(0.5 + 0.5 * (d.x / depth) / tan_half_h, (t_top - d.y / depth) / (t_top - t_bottom));
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			color = texture(image, uv).rgb;
		}
	}
	ALBEDO = color;
}
"""

enum Mode { THREE_CAMERAS, ONE_CAMERA_FAIR, ONE_CAMERA_STRETCHED }

@export_group("Room")
@export var middle_width: float = 4.0:
	set(value):
		middle_width = value
		_rebuild_if_ready()
@export var side_width: float = 4.0:
	set(value):
		side_width = value
		_rebuild_if_ready()
@export var wall_height: float = 2.5:
	set(value):
		wall_height = value
		_rebuild_if_ready()
## How far the side walls angle outward from the middle wall's line, in degrees.
@export_range(0.0, 89.0, 1.0) var side_angle: float = 45.0:
	set(value):
		side_angle = value
		_rebuild_if_ready()

@export_group("Sweet spot")
## How far the sweet spot is from the middle wall, in metres.
@export var sweet_spot_distance: float = 3.0:
	set(value):
		sweet_spot_distance = value
		_rebuild_if_ready()
@export var eye_height: float = 1.6:
	set(value):
		eye_height = value
		_rebuild_if_ready()

@export_group("Pictures")
## Pixels per metre of wall. The single camera gets the three walls' pixels combined.
@export var pixels_per_metre: int = 256:
	set(value):
		pixels_per_metre = value
		_rebuild_if_ready()
## How far the single wide camera sees to each side of straight ahead, in degrees. A flat
## camera image can't reach 90°.
@export_range(10.0, 89.0, 1.0) var single_half_angle: float = 80.0:
	set(value):
		single_half_angle = value
		_rebuild_if_ready()

var mode: Mode = Mode.THREE_CAMERAS
var spot: int = 0

var _background: SubViewport
var _ship_camera: Camera3D
var _single_viewport: SubViewport
var _single_camera: Camera3D
var _room: Node3D
## Per wall (left, middle, right): { "node", "viewport", "camera", "basis", "width", "start" }.
var _walls: Array[Dictionary] = []
var _visitor: Camera3D
var _label: Label
var _looking := false


func _ready() -> void:
	_background = SubViewport.new()
	_background.name = "Background"
	_background.own_world_3d = true
	_background.size = Vector2i(64, 64)
	_background.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_background)
	var world: Node = (load(WORLD) as PackedScene).instantiate()
	var director := world.find_child("ZurdDirector", true, false)
	if director:
		director.set(&"spawn_at_start", false)
	_background.add_child(world)
	_ship_camera = world.find_child("PlayerShip", true, false).find_child("Camera3D", true, false)

	_add_room_environment()
	_visitor = Camera3D.new()
	_visitor.fov = 70.0
	add_child(_visitor)
	_visitor.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_label)

	_rebuild()
	go_to_spot(0)


func _process(_delta: float) -> void:
	if _ship_camera == null:
		return
	var ship := _ship_camera.global_transform
	for wall in _walls:
		(wall["camera"] as Camera3D).global_transform = Transform3D(ship.basis * (wall["basis"] as Basis), ship.origin)
	_single_camera.global_transform = ship


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.keycode:
			KEY_TAB:
				set_mode((mode + 1) % 3 as Mode)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				go_to_spot(key.keycode - KEY_1)
			KEY_H:
				_label.visible = not _label.visible
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_RIGHT:
		_looking = button.pressed
	var motion := event as InputEventMouseMotion
	if motion and _looking:
		_visitor.rotation.y -= motion.relative.x * 0.004
		_visitor.rotation.x = clampf(_visitor.rotation.x - motion.relative.y * 0.004, -1.5, 1.5)


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_apply_mode()


## Puts the visitor at spot [param index] (see SPOT_NAMES), looking at the middle wall.
func go_to_spot(index: int) -> void:
	spot = clampi(index, 0, SPOT_NAMES.size() - 1)
	var eye := Vector3(0.0, eye_height, 0.0)
	var middle := Vector3(0.0, wall_height * 0.5, -sweet_spot_distance)
	match spot:
		0:
			_visitor.global_position = eye
			_visitor.look_at(Vector3(0.0, eye_height, -sweet_spot_distance))
		1:
			_visitor.global_position = eye + Vector3(-1.5, 0.0, 0.5)
			_visitor.look_at(middle)
		2:
			_visitor.global_position = eye + Vector3(1.5, 0.0, 0.5)
			_visitor.look_at(middle)
		3:
			_visitor.global_position = Vector3(0.0, eye_height, -sweet_spot_distance + 1.2)
			_visitor.look_at(middle)
		4:
			_visitor.global_position = Vector3(0.0, 14.0, 3.0)
			_visitor.look_at(Vector3(0.0, 0.0, -sweet_spot_distance * 0.6))
	_update_label()


func _rebuild_if_ready() -> void:
	if is_node_ready():
		_rebuild()


## Builds the room, the wall screens, their cameras and the single wide camera from the settings.
func _rebuild() -> void:
	if _room:
		_room.free()
	for wall in _walls:
		(wall["viewport"] as SubViewport).free()
	_walls.clear()
	if _single_viewport:
		_single_viewport.free()
	_room = Node3D.new()
	_room.name = "Room"
	add_child(_room)
	_add_floor()

	var world_3d := _background.find_world_3d()
	var eye := Vector3(0.0, eye_height, 0.0)
	var angle := deg_to_rad(side_angle)
	var a := Vector3(-middle_width * 0.5, 0.0, -sweet_spot_distance)
	var b := Vector3(middle_width * 0.5, 0.0, -sweet_spot_distance)
	var left_end := a + Vector3(-cos(angle), 0.0, sin(angle)) * side_width
	var right_end := b + Vector3(cos(angle), 0.0, sin(angle)) * side_width
	# Each wall from its left end to its right end, as seen from inside the room.
	var segments := [[left_end, a], [a, b], [b, right_end]]
	var start := 0.0
	for segment: Array in segments:
		var p: Vector3 = segment[0]
		var q: Vector3 = segment[1]
		var width := p.distance_to(q)
		var along := (q - p) / width
		var facing := Vector3(-along.z, 0.0, along.x)
		var basis := Basis(along, Vector3.UP, facing)
		var screen := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(width, wall_height)
		screen.mesh = quad
		screen.transform = Transform3D(basis, (p + q) * 0.5 + Vector3(0.0, wall_height * 0.5, 0.0))
		_room.add_child(screen)

		# This wall's camera: faces the wall, its view cut to the wall as the sweet spot sees it.
		var viewport := SubViewport.new()
		viewport.world_3d = world_3d
		viewport.size = Vector2i(maxi(int(width * pixels_per_metre), 8), maxi(int(wall_height * pixels_per_metre), 8))
		add_child(viewport)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_FRUSTUM
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		var to_wall := basis.inverse()
		var local_p := to_wall * (p - eye)
		var local_q := to_wall * (q - eye)
		var depth := -local_p.z
		var bottom := -eye_height
		var top := wall_height - eye_height
		var scale := NEAR / depth
		camera.set_frustum((top - bottom) * scale, Vector2((local_p.x + local_q.x) * 0.5, (top + bottom) * 0.5) * scale, NEAR, FAR)
		viewport.add_child(camera)
		camera.current = true
		_walls.append({"node": screen, "viewport": viewport, "camera": camera, "basis": basis, "width": width, "start": start})
		start += width

	_build_single_camera(eye, [left_end, a, b, right_end], start)
	_apply_mode()


## The one wide camera, facing straight ahead, given the three walls' pixels combined.
func _build_single_camera(eye: Vector3, corners: Array, total_width: float) -> void:
	var tan_h := tan(deg_to_rad(single_half_angle))
	# Its height covers the walls' tops and bottoms as seen from the sweet spot, where they're in front.
	var t_top := 0.0
	var t_bottom := 0.0
	for corner: Vector3 in corners:
		var depth := eye.z - corner.z
		if depth < 0.2:
			continue
		t_top = maxf(t_top, (wall_height - eye_height) / depth)
		t_bottom = minf(t_bottom, -eye_height / depth)
	t_top = minf(t_top, 3.0)
	t_bottom = maxf(t_bottom, -3.0)
	var aspect := 2.0 * tan_h / (t_top - t_bottom)
	var budget := total_width * wall_height * pixels_per_metre * pixels_per_metre
	var height := sqrt(budget / aspect)
	_single_viewport = SubViewport.new()
	_single_viewport.world_3d = _background.find_world_3d()
	_single_viewport.size = Vector2i(mini(int(height * aspect), 16384), maxi(int(height), 8))
	add_child(_single_viewport)
	_single_camera = Camera3D.new()
	_single_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_single_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_single_camera.set_frustum((t_top - t_bottom) * NEAR, Vector2(0.0, (t_top + t_bottom) * 0.5 * NEAR), NEAR, FAR)
	_single_viewport.add_child(_single_camera)
	_single_camera.current = true
	_single_viewport.set_meta(&"projection", [eye, tan_h, t_top, t_bottom])


func _apply_mode() -> void:
	if _walls.is_empty():
		return
	var three := mode == Mode.THREE_CAMERAS
	for wall in _walls:
		(wall["viewport"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if three else SubViewport.UPDATE_DISABLED
	_single_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if three else SubViewport.UPDATE_ALWAYS
	var total: float = _walls[-1]["start"] + _walls[-1]["width"]
	var projection: Array = _single_viewport.get_meta(&"projection")
	for wall in _walls:
		var screen: MeshInstance3D = wall["node"]
		match mode:
			Mode.THREE_CAMERAS:
				screen.material_override = _flat_material((wall["viewport"] as SubViewport).get_texture())
			Mode.ONE_CAMERA_STRETCHED:
				var material := _flat_material(_single_viewport.get_texture())
				material.uv1_scale = Vector3(wall["width"] / total, 1.0, 1.0)
				material.uv1_offset = Vector3(wall["start"] / total, 0.0, 0.0)
				screen.material_override = material
			Mode.ONE_CAMERA_FAIR:
				var shader := Shader.new()
				shader.code = FAIR_SHADER
				var material := ShaderMaterial.new()
				material.shader = shader
				material.set_shader_parameter(&"image", _single_viewport.get_texture())
				material.set_shader_parameter(&"eye", projection[0])
				material.set_shader_parameter(&"tan_half_h", projection[1])
				material.set_shader_parameter(&"t_top", projection[2])
				material.set_shader_parameter(&"t_bottom", projection[3])
				screen.material_override = material
	_update_label()


func _flat_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = texture
	return material


func _update_label() -> void:
	if _label == null:
		return
	var pixels := ""
	if _single_viewport:
		pixels = "  (single camera: %d × %d px)" % [_single_viewport.size.x, _single_viewport.size.y]
	_label.text = "%s%s\nVisitor: %s\nTab: switch   1-5: move   right drag: look   H: hide" % [MODE_NAMES[mode], pixels if mode != Mode.THREE_CAMERAS else "", SPOT_NAMES[spot]]


func _add_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.12, 0.12, 0.14)
	floor_mesh.material_override = floor_material
	floor_mesh.position = Vector3(0.0, -0.01, -2.0)
	_room.add_child(floor_mesh)
	# The sweet spot.
	var marker := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.25
	disc.bottom_radius = 0.25
	disc.height = 0.02
	marker.mesh = disc
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(0.9, 0.2, 0.2)
	marker.material_override = marker_material
	_room.add_child(marker)


func _add_room_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.03)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	light.light_energy = 0.4
	add_child(light)
