class_name SculptureFx
extends Node

## Placeholder effects for the sculpture-mass events (Sculpture-Mass Design Doc §6). It only listens
## to the EventBus, so effects can change without touching the mass code. Visuals only for now;
## sound will hook onto the same signals once there are audio files.

const BASE_SCALE_META := &"fx_base_scale"
const PUNCH_TWEEN_META := &"fx_punch_tween"

@export_group("Hit")
## How much a loose object's visual swells when a counted hit lands on it (the clatter before fusing).
@export var hit_punch: float = 0.12

@export_group("Fuse")
## How much an object swells as it fuses into a mass.
@export var fuse_punch: float = 0.3

@export_group("Combine")
## Length of the grow animation when matching objects combine, and of the shrink animation when a
## Zurd bites a part off. Placeholder until the real animation is designed.
@export var resize_time: float = 0.25
## Flash on the combined object only (Design Doc §4.10).
@export var combine_flash_color: Color = Color(1.0, 0.85, 0.0)
@export var combine_flash_time: float = 0.4

@export_group("Flashes")
@export var merge_flash_color: Color = Color(1.0, 1.0, 1.0)
@export var eaten_flash_color: Color = Color(1.0, 0.0, 0.0)


func _ready() -> void:
	EventBus.object_hit.connect(_on_object_hit)
	EventBus.object_fused.connect(_on_object_fused)
	EventBus.masses_merged.connect(_on_masses_merged)
	EventBus.object_eaten.connect(_on_object_eaten)
	EventBus.objects_combined.connect(_on_objects_combined)
	EventBus.object_resized.connect(_on_object_resized)


func _on_object_hit(obj: RigidBody3D, _other: Node3D) -> void:
	for visual in _get_visuals(obj):
		_punch(visual, hit_punch)


func _on_object_fused(_mass: SculptureMass, piece: MassPiece) -> void:
	_punch(piece, fuse_punch)


func _on_masses_merged(mass: SculptureMass, _absorbed_count: int) -> void:
	mass.flash(merge_flash_color)


func _on_object_eaten(_actor: Node3D, _obj: Node3D, mass: SculptureMass) -> void:
	if mass:
		mass.flash(eaten_flash_color)


func _on_objects_combined(obj: Node3D, _absorbed_parts: int) -> void:
	_flash_overlay(obj, combine_flash_color, combine_flash_time)


## The manager has already put the visuals at [param new_size]; they snap from [param old_size] to
## it with a little overshoot.
func _on_object_resized(obj: Node3D, old_size: float, new_size: float) -> void:
	if new_size <= 0.0:
		return
	for visual in _get_visuals(obj):
		var final_scale := visual.scale
		# Hit punches spring back to the new size from now on.
		visual.set_meta(BASE_SCALE_META, final_scale)
		_kill_tween(visual)
		visual.scale = final_scale * (old_size / new_size)
		var tween := visual.create_tween()
		tween.tween_property(visual, "scale", final_scale, resize_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		visual.set_meta(PUNCH_TWEEN_META, tween)


## Swells [param node]'s visuals by [param amount] and springs them back to their normal scale.
## Never used on collision shapes, so physics is unaffected.
func _punch(node: Node3D, amount: float) -> void:
	if amount <= 0.0:
		return
	if not node.has_meta(BASE_SCALE_META):
		node.set_meta(BASE_SCALE_META, node.scale)
	var base_scale: Vector3 = node.get_meta(BASE_SCALE_META)

	_kill_tween(node)
	node.scale = base_scale * (1.0 + amount)
	var tween := node.create_tween()
	tween.tween_property(node, "scale", base_scale, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	node.set_meta(PUNCH_TWEEN_META, tween)


func _kill_tween(node: Node3D) -> void:
	if node.has_meta(PUNCH_TWEEN_META):
		var previous: Tween = node.get_meta(PUNCH_TWEEN_META)
		if previous.is_valid():
			previous.kill()


## Lights up only [param obj]'s meshes in [param color] for [param duration], on top of whatever
## material they use, so it works on loose objects and on fused ones (whose material the whole
## mass shares).
func _flash_overlay(obj: Node3D, color: Color, duration: float) -> void:
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	overlay.albedo_color = color
	var meshes: Array = obj.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = overlay

	# Runs on this node, not the object, so the flash still clears if the object fuses mid-flash.
	var tween := create_tween()
	tween.tween_property(overlay, "albedo_color:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tween.finished.connect(_clear_overlay.bind(meshes, overlay))


## Untyped, because meshes may have been freed since the flash started.
func _clear_overlay(meshes: Array, overlay: Material) -> void:
	for mesh in meshes:
		# A newer flash may have replaced this one.
		if is_instance_valid(mesh) and mesh.material_overlay == overlay:
			mesh.material_overlay = null


## The nodes that show [param obj]: a loose body's children apart from its collision shapes, or all
## of a fused piece's children.
func _get_visuals(obj: Node3D) -> Array[Node3D]:
	var visuals: Array[Node3D] = []
	for child in obj.get_children():
		if child is Node3D and not (child is CollisionShape3D):
			visuals.append(child as Node3D)
	return visuals
