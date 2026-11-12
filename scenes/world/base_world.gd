class_name BaseWorld
extends Node3D

## The template every world builds on (zurd_world.tscn adds the terrain). It holds the
## Environment, the GameSystems, the Input sources and the Actors, and puts everything spawned
## through [signal EventBus.spawn_requested] into its container under Actors.

@onready var _zurds: Node3D = $Actors/Zurds
@onready var _objects: Node3D = $Actors/Objects
@onready var _masses: Node3D = $Actors/Masses
@onready var _projectiles: Node3D = $Actors/Projectiles


func _ready() -> void:
	EventBus.spawn_requested.connect(_on_spawn_requested)


func _on_spawn_requested(spawnable: Node3D) -> void:
	get_container_for(spawnable).add_child(spawnable)


## The Actors container [param node] belongs in: sculpture masses (and clouds), Zurds, swat
## projectiles, or Objects for everything else (launched objects, objects broken off a mass).
func get_container_for(node: Node3D) -> Node3D:
	if node is SculptureMass:
		return _masses
	if node is Zurd:
		return _zurds
	if node is SwatProjectile:
		return _projectiles
	return _objects
