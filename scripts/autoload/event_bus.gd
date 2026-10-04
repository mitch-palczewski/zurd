extends Node

## Fired when requesting a 3D object to be spawned into the active world.
##
## [b]Contract:[/b]
## - [param spawnable]: An instantiated [Node3D] (e.g., RigidBody3D, item, particle).
## - The caller is responsible for instantiating the node and setting initial properties 
##   (e.g., velocity, scale, angular momentum, damping).
## - The receiving world/level container takes ownership of [param spawnable] via [method Node.add_child].
@warning_ignore("unused_signal")
signal spawn_requested(spawnable: Node3D)
