class_name ZurdTargetComponent
extends Node

enum TargetStrategy {CLOSEST, RANDOM}
@export var strategy: TargetStrategy = TargetStrategy.RANDOM

## A loose object or one object of a sculpture mass.
var current_target: Node3D = null

func get_or_update_target(from_position: Vector3) -> Node3D:
    if not ObjectTracker.is_trackable(current_target):
        match strategy:
            TargetStrategy.CLOSEST:
                current_target = ObjectTracker.get_closest_object(from_position)
            TargetStrategy.RANDOM:
                current_target = ObjectTracker.get_random_object()

    return current_target

func clear_target() -> void:
    current_target = null

