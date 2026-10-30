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


## Fired when an actor (such as a Zurd enemy) finishes eating an object.[br]
## [br]
## [br][b]Contract:[/b][br]
## - [param actor]: The node (e.g., Zurd) that performed the eating action.[br]
## - [param obj]: The eaten object: a loose [RigidBody3D] or a [MassPiece] of a mass. It is freed right after.[br]
## - [param mass]: The [SculptureMass] the object was eaten off, or [code]null[/code] for a loose object.[br]
## - Useful for global score tracking, spawning reward particles, audio triggers, and HUD updates.[br]
@warning_ignore("unused_signal")
signal object_eaten(actor: Node3D, obj: Node3D, mass: SculptureMass)


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


# Sculpture masses (see claude/plans/Sculpture-Mass Design Doc.md, §6).

## Fired when a counted hit lands on a loose object (it hit another object or a mass).[br]
## [param other]: the loose [RigidBody3D] or [SculptureMass] it hit.
@warning_ignore("unused_signal")
signal object_hit(obj: RigidBody3D, other: Node3D)


## Fired when an object fuses into a mass, including the two objects that start a new mass.
@warning_ignore("unused_signal")
signal object_fused(mass: SculptureMass, piece: MassPiece)


## Fired when two masses combine.[br]
## [param mass]: the mass that remains. [param absorbed_count]: how many objects it took over.
@warning_ignore("unused_signal")
signal masses_merged(mass: SculptureMass, absorbed_count: int)


## Fired when the ship breaks objects off a mass.[br]
## [param objects]: the new loose bodies: the objects the ship hit, plus any that fell off because of it.
@warning_ignore("unused_signal")
signal objects_broken_off(mass: SculptureMass, objects: Array[RigidBody3D])


## Fired when a mass's cloud progress (object count / cloud threshold, 0 to 1) changes.
@warning_ignore("unused_signal")
signal cloud_progress_changed(mass: SculptureMass, progress: float)


## Fired when a mass reaches the cloud threshold and becomes a cloud.
@warning_ignore("unused_signal")
signal cloud_formed(mass: SculptureMass)
