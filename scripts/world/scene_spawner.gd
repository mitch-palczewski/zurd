class_name SceneSpawner
extends Node

@export var scene_to_spawn: PackedScene
@export var spawn_location: Node3D
@export var parent_container: Node3D
@export var auto_spawn_on_ready: bool = true

func _ready() -> void:
    if auto_spawn_on_ready:
        spawn()

func spawn() -> Node3D:
    if not scene_to_spawn:
        push_warning("SceneSpawner (%s): No scene_to_spawn assigned." % name)
        return null
    var instance: Node3D = scene_to_spawn.instantiate() as Node3D

    var target_parent: Node = parent_container if parent_container else get_parent()
    target_parent.add_child(instance)
    
    if spawn_location:
        instance.global_transform = spawn_location.global_transform
    
    return instance