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


## Fired when an actor (such as a Zurd enemy) finishes eating an object, or one part of a combined object.[br]
## [br]
## [br][b]Contract:[/b][br]
## - [param actor]: The node (e.g., Zurd) that performed the eating action.[br]
## - [param obj]: The eaten object: a loose [RigidBody3D] or a [MassPiece] of a mass. It is freed right after,
##   unless it was a combined object that lost one part and is now smaller.[br]
## - [param mass]: The [SculptureMass] the object was eaten off, or [code]null[/code] for a loose object.[br]
## - Useful for global score tracking, spawning reward particles, audio triggers, and HUD updates.[br]
@warning_ignore("unused_signal")
signal object_eaten(actor: Node3D, obj: Node3D, mass: SculptureMass)


## Fired when a Zurd finishes eating its target, so the world's [MassManager] takes the bite: one part of a
## combined object, or the whole object. It then fires [signal object_eaten].[br]
## [param obj]: a loose [RigidBody3D] or a [MassPiece] of a mass.
@warning_ignore("unused_signal")
signal eat_requested(actor: Node3D, obj: Node3D)


## Fired when a swat input (mouse click, LIDAR detection) happens.
## [br]
## [param screen_uv]: normalized viewport position, (0,0) top-left to (1,1) bottom-right.
@warning_ignore("unused_signal")
signal swat_requested(screen_uv: Vector2)


## Fired as the pointer moves, so the cursor visual can follow it
## [br]
## [param screen_uv]: normalized viewport position, (0,0) top-left to (1,1) bottom-right.
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
## [param mass]: the mass that remains. [param absorbed_count]: how many objects (parts) it took over.
@warning_ignore("unused_signal")
signal masses_merged(mass: SculptureMass, absorbed_count: int)


## Fired when the ship, or a fused object that grew, breaks objects off a mass.[br]
## [param objects]: the new loose bodies: the objects that were hit or grown into, plus any that fell off
## because of it.
@warning_ignore("unused_signal")
signal objects_broken_off(mass: SculptureMass, objects: Array[RigidBody3D])


## Fired when two matching objects combine into one bigger object (Design Doc §4.10).[br]
## [param obj]: the combined object, a loose [RigidBody3D] or a [MassPiece]. [param absorbed_parts]: how
## many parts it took in.
@warning_ignore("unused_signal")
signal objects_combined(obj: Node3D, absorbed_parts: int)


## Fired when an object changes size: it grew from combining or shrank from a Zurd's bite. Its collision
## shapes and visuals are already at [param new_size]; effects can animate the visuals from [param old_size].
@warning_ignore("unused_signal")
signal object_resized(obj: Node3D, old_size: float, new_size: float)


## Fired when a mass's cloud progress (object count / cloud threshold, 0 to 1) changes.
@warning_ignore("unused_signal")
signal cloud_progress_changed(mass: SculptureMass, progress: float)


## Fired when a mass reaches the cloud threshold and becomes a cloud.
@warning_ignore("unused_signal")
signal cloud_formed(mass: SculptureMass)


# Ship controls (see claude/plans/Ship-Controls Design Doc.md, §7).

## Fired when a launch station selects a different object, and once at startup.[br]
## [param station]: the station's id. [param scene]: the selected object's scene.
@warning_ignore("unused_signal")
signal launch_selection_changed(station: StringName, scene: PackedScene)


## Fired when a station becomes active (a guest used it) or empty (no input for its idle timeout).
@warning_ignore("unused_signal")
signal station_activity_changed(station: StringName, active: bool)
