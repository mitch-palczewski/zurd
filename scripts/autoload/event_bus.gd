extends Node

## Fired when requesting a 3D object to be spawned into the active world.[br]
## [br]
## [br][b]Contract:[/b][br]
## - [param spawnable]: An instantiated [Node3D] (e.g., RigidBody3D, item, particle).[br]
## - The caller is responsible for instantiating the node and setting initial properties
##   (e.g., velocity, scale, angular momentum, damping).[br]
## - The receiving world/level container takes ownership of [param spawnable] via [method Node.add_child].[br]
@warning_ignore("unused_signal")
signal spawn_requested(spawnable: Node3D)


## Fired when an actor (such as a Zurd enemy) consumes or eats a tracked projectile object.[br]
## [br]
## [br][b]Contract:[/b][br]  
## - [param actor]: The [CharacterBody3D] (e.g., Zurd) that performed the eating action.[br]
## - [param obj]: The [RigidBody3D] projectile object that was consumed and is about to be freed.[br]
## - Useful for global score tracking, spawning reward particles, audio triggers, and HUD updates.[br]
@warning_ignore("unused_signal")
signal object_eaten(actor: CharacterBody3D, obj: RigidBody3D)


## Firedwhen a swat input (mouse click, LIDAR detection) happens.
## [br]
## [param screen_uv]: normalized viewport position, (0,0) top-left to (1,1) botom-right.
@warning_ignore("unused_signal")
signal swat_requested(screen_uv: Vector2)


## Fired as the pointer moves, so the cursor visual can follow it
## [br]
## [param screen_uv]: normalized viewport position, (0,0) top-left to (1,1) botom-right.
@warning_ignore("unused_signal")
signal pointer_moved(screen_uv: Vector2)