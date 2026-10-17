class_name Zurd 
extends CharacterBody3D

## Base Zurd coordinator linking movement, targeting, and mouth components.

@export var obj_scale_factor: float = .1

@export_group("Components")
@export var target_component: ZurdTargetComponent
@export var movement_componet: ZurdMovementComponent
@export var mouth_componet: ZurdMouthComponent

func _ready() -> void:
    _validate_components()
    if mouth_componet:
        mouth_componet.object_eaten.connect(_on_object_eaten)

func _physics_process(delta: float) -> void:
    if not target_component or not movement_componet or not mouth_componet:
        return 
    
    var target := target_component.get_or_update_target(global_position)
    mouth_componet.set_target(target)
    movement_componet.process_movement(self, target, delta)

    if not target:
        target_component.clear_target()


func _validate_components() -> void:
    if not target_component: target_component = get_node_or_null("TargetComponent")
    if not movement_componet: movement_componet = get_node_or_null("MovementComponent")
    if not mouth_componet: mouth_componet = get_node_or_null("MouthArea")

func _on_object_eaten(_obj: RigidBody3D) -> void:
    _scale_zurd()
    pass

func _scale_zurd():
    var target_scale = scale + Vector3.ONE * obj_scale_factor
    var tween := create_tween()
    tween.tween_property(self, "scale", target_scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
