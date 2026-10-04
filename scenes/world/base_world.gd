class_name BaseWorld
extends Node3D

@onready var object_container = $ObjectContainer

func _ready() -> void:
    EventBus.spawn_requested.connect(_on_spawn_requested)

func _on_spawn_requested(spawnable: Node3D) -> void:
    var intended_transform := spawnable.global_transform
    object_container.add_child(spawnable)
    spawnable.global_transform = intended_transform