class_name LaunchPreview
extends Node3D

## A launch station's selection preview (Launch-Station Design Doc §4): a pedestal that rises out of
## the cockpit floor with a small copy of the selected object turning on top. It only displays; its
## [LaunchStation] calls [method show_object] and [method hide_preview]. Each call retargets from
## wherever the preview is, so transitions never queue.

## Scale of a shrunk object. Not 0: a zero scale gives a basis that can't be inverted.
const MIN_SCALE := 0.01

@export_group("Object")
## Largest dimension of a fitted object copy.
@export var box_size: float = 0.12
## Gap between the disc and the bottom of the object's bounds.
@export var hover_height: float = 0.02
@export_range(0.0, 360.0, 0.1, "degrees") var turn_speed_degrees: float = 60.0

@export_group("Timing")
## Time for the pedestal to rise out of the floor or sink back into it.
@export var rise_time: float = 0.25
## Time for an object to grow from nothing, with a slight overshoot.
@export var pop_time: float = 0.2
## Time for an object to shrink away, on a hide and at the start of a step.
@export var shrink_time: float = 0.12

@export_group("Pedestal")
## How far below its shown position the hidden pedestal sits: its height plus a margin, so it hides
## fully under the floor.
@export var sink_depth: float = 0.14

@onready var pedestal: Node3D = $Pedestal
@onready var turntable: Node3D = $Pedestal/Turntable

## The scene the preview ends on; null while it is hidden or hiding.
var _target_scene: PackedScene
## The scene whose copy is on the turntable; null when none is.
var _shown_scene: PackedScene
## One copy per scene shown so far, kept hidden on the turntable when not shown. Null for a scene
## without meshes.
var _copies: Dictionary[PackedScene, Node3D] = {}
var _tween: Tween


func _ready() -> void:
	# The scene shows the pedestal up, for tuning in the editor; it starts hidden in the floor.
	pedestal.position.y = -sink_depth
	pedestal.visible = false
	turntable.scale = Vector3.ONE * MIN_SCALE


func _process(delta: float) -> void:
	if pedestal.visible:
		turntable.rotation.y = wrapf(turntable.rotation.y + deg_to_rad(turn_speed_degrees) * delta, -PI, PI)


## Shows [param scene] on the pedestal, raising the pedestal first if it is down. Null hides the
## preview, like [method hide_preview].
func show_object(scene: PackedScene) -> void:
	if scene == _target_scene:
		return
	_target_scene = scene
	_retarget()


## Shrinks the object away, then sinks the pedestal into the floor.
func hide_preview() -> void:
	show_object(null)


func _retarget() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	# Each step starts where the one before it ends, and its duration is scaled by how far it has to go.
	var object_scale := turntable.scale.x
	var height := pedestal.position.y

	if _shown_scene != _target_scene:
		if object_scale > MIN_SCALE:
			var shrink := _tween.tween_property(turntable, "scale", Vector3.ONE * MIN_SCALE, shrink_time * object_scale)
			shrink.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			object_scale = MIN_SCALE
		_tween.tween_callback(_swap_copy.bind(_target_scene))

	if _target_scene:
		_tween.tween_callback(pedestal.show)
		if height < 0.0:
			var rise := _tween.tween_property(pedestal, "position:y", 0.0, rise_time * -height / sink_depth)
			rise.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if not is_equal_approx(object_scale, 1.0):
			var pop := _tween.tween_property(turntable, "scale", Vector3.ONE, pop_time * absf(1.0 - object_scale))
			pop.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		var sink_duration := rise_time * (height + sink_depth) / sink_depth
		var sink := _tween.tween_property(pedestal, "position:y", -sink_depth, sink_duration)
		sink.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_tween.tween_callback(pedestal.hide)


func _swap_copy(scene: PackedScene) -> void:
	if _shown_scene and _copies[_shown_scene]:
		_copies[_shown_scene].visible = false
	_shown_scene = scene
	if scene == null:
		return
	if not _copies.has(scene):
		_copies[scene] = _build_copy(scene)
	if _copies[scene]:
		_copies[scene].visible = true
	# Rotation 0 shows the model's front (+Z, glTF forward) to the camera.
	turntable.rotation.y = 0.0


## A visual-only copy of [param scene], fitted to [member box_size] and standing [member hover_height]
## above the disc, on the turning axis. Null when the scene has no meshes.
func _build_copy(scene: PackedScene) -> Node3D:
	var instance := scene.instantiate()
	var copy := Node3D.new()
	copy.name = "%sPreview" % instance.name
	_copy_meshes(instance, Transform3D.IDENTITY, copy)
	# The instance never entered the tree, so nothing ran its _ready or registered it.
	instance.free()

	var bounds := _get_bounds(copy)
	var longest := bounds.get_longest_axis_size()
	if longest <= 0.0:
		push_warning("LaunchPreview: '%s' has no meshes to show." % scene.resource_path)
		copy.free()
		return null

	var fit := box_size / longest
	copy.scale = Vector3.ONE * fit
	var bottom_center := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	copy.position = Vector3(0.0, hover_height, 0.0) - bottom_center * fit
	copy.visible = false
	turntable.add_child(copy)
	return copy


## Adds a new [MeshInstance3D] to [param copy] for each mesh under [param node], placed by its
## transform relative to the scene root. Only meshes are copied: no bodies, shapes or scripts.
func _copy_meshes(node: Node, to_root: Transform3D, copy: Node3D) -> void:
	for child in node.get_children():
		var child_3d := child as Node3D
		if child_3d == null:
			continue
		var child_to_root := to_root * child_3d.transform
		var source := child_3d as MeshInstance3D
		if source and source.mesh:
			var mesh_copy := MeshInstance3D.new()
			mesh_copy.mesh = source.mesh
			mesh_copy.transform = child_to_root
			mesh_copy.material_override = source.material_override
			for surface in source.get_surface_override_material_count():
				mesh_copy.set_surface_override_material(surface, source.get_surface_override_material(surface))
			copy.add_child(mesh_copy)
		_copy_meshes(child_3d, child_to_root, copy)


func _get_bounds(copy: Node3D) -> AABB:
	var bounds := AABB()
	for i in copy.get_child_count():
		var mesh_copy := copy.get_child(i) as MeshInstance3D
		var box := mesh_copy.transform * mesh_copy.mesh.get_aabb()
		bounds = box if i == 0 else bounds.merge(box)
	return bounds
