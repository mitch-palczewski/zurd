class_name Zurd 
extends CharacterBody3D

## Base Zurd coordinator linking movement, targeting, and mouth components.

@export var obj_scale_factor: float = .1

@export_group("Components")
@export var target_component: ZurdTargetComponent
@export var movement_component: ZurdMovementComponent
@export var mouth_component: ZurdMouthComponent

func _ready() -> void:
	_validate_components()
	if mouth_component:
		mouth_component.bite_taken.connect(_on_bite_taken)

func _physics_process(delta: float) -> void:
	if not target_component or not movement_component or not mouth_component:
		return 

	var target := target_component.get_or_update_target(global_position)
	mouth_component.set_target(target)
	if target and mouth_component.is_eating():
		movement_component.process_eating(self, target, mouth_component.get_mouth_position(), delta)
	else:
		movement_component.process_movement(self, target, delta)

	if not target:
		target_component.clear_target()


func _validate_components() -> void:
	if not target_component: target_component = get_node_or_null("TargetComponent")
	if not movement_component: movement_component = get_node_or_null("MovementComponent")
	if not mouth_component: mouth_component = get_node_or_null("MouthArea")


func _on_bite_taken(_obj: Node3D) -> void:
	_scale_zurd(obj_scale_factor)


func take_swat(_swat_velocity: Vector3) -> void:
	_scale_zurd(-obj_scale_factor)
	target_component.clear_target()
	mouth_component.cancel_eating()


func _scale_zurd(scale_increase_factor: float):
	var target_scale = scale + Vector3.ONE * scale_increase_factor
	var tween := create_tween()
	tween.tween_property(self, "scale", target_scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)