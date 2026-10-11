class_name ZurdTargetComponent
extends Node

enum TargetStrategy {CLOSEST, RANDOM}
@export var strategy: TargetStrategy = TargetStrategy.RANDOM

var current_target: RigidBody3D = null

func get_or_update_target(from_position: Vector3) -> RigidBody3D:
    if not is_instance_valid(current_target):
        match strategy:
            TargetStrategy.CLOSEST:
                current_target = ObjectTracker.get_closest_object(from_position)
            TargetStrategy.RANDOM:
                current_target = ObjectTracker.get_random_object()

    return current_target

func clear_target() -> void:
    current_target = null

