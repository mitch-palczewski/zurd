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

@export_group("Flashes")
@export var merge_flash_color: Color = Color(1.0, 1.0, 1.0)
@export var eaten_flash_color: Color = Color(1.0, 0.0, 0.0)


func _ready() -> void:
	EventBus.object_hit.connect(_on_object_hit)
	EventBus.object_fused.connect(_on_object_fused)
	EventBus.masses_merged.connect(_on_masses_merged)
	EventBus.object_eaten.connect(_on_object_eaten)


func _on_object_hit(obj: RigidBody3D, _other: Node3D) -> void:
	for child in obj.get_children():
		if child is Node3D and not (child is CollisionShape3D):
			_punch(child as Node3D, hit_punch)


func _on_object_fused(_mass: SculptureMass, piece: MassPiece) -> void:
	_punch(piece, fuse_punch)


func _on_masses_merged(mass: SculptureMass, _absorbed_count: int) -> void:
	mass.flash(merge_flash_color)


func _on_object_eaten(_actor: Node3D, _obj: Node3D, mass: SculptureMass) -> void:
	if mass:
		mass.flash(eaten_flash_color)


## Swells [param node]'s visuals by [param amount] and springs them back to their normal scale.
## Never used on collision shapes, so physics is unaffected.
func _punch(node: Node3D, amount: float) -> void:
	if amount <= 0.0:
		return
	if not node.has_meta(BASE_SCALE_META):
		node.set_meta(BASE_SCALE_META, node.scale)
	var base_scale: Vector3 = node.get_meta(BASE_SCALE_META)

	if node.has_meta(PUNCH_TWEEN_META):
		var previous: Tween = node.get_meta(PUNCH_TWEEN_META)
		if previous.is_valid():
			previous.kill()

	node.scale = base_scale * (1.0 + amount)
	var tween := node.create_tween()
	tween.tween_property(node, "scale", base_scale, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	node.set_meta(PUNCH_TWEEN_META, tween)
