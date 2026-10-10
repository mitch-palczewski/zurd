extends Node 

## A global manager that tracks all active launched objects in the world.

## List of currently active, spawned rigid body objects.
var active_objects: Array[RigidBody3D] = []


## Registers a new [RigidBody3D] object to be tracked.
## Automatically connects to its [signal Node.tree_exited] signal to clean up references when freed.
## @param obj: The rigid body object to track.
func register_object(obj: RigidBody3D) -> void:
    if not active_objects.has(obj):
        active_objects.append(obj)
        if not obj.tree_exited.is_connected(_on_object_tree_exited.bind(obj)):
            obj.tree_exited.connect(_on_object_tree_exited.bind(obj), CONNECT_ONE_SHOT)


## Returns a randomly selected active object from the tracked list.
## Returns [code]null[/code] if no objects are active.
## @return A random [RigidBody3D], or [code]null[/code] if empty.
func get_random_object() -> RigidBody3D:
    _purge_invalid()
    if active_objects.is_empty():
        return null
    return active_objects.pick_random()


## Finds and returns the active object closest to the specified [param from_position].
## @param from_position: The 3D world position to measure distance from.
## @return The closest [RigidBody3D], or [code]null[/code] if no objects are active.
func get_closest_object(from_position: Vector3) -> RigidBody3D:
    _purge_invalid()
    if active_objects.is_empty():
        return null
    
    var closest: RigidBody3D = active_objects[0]
    var min_distance := from_position.distance_to(closest.global_position)

    for obj in active_objects:
        var distance := from_position.distance_to(obj.global_position)
        if distance < min_distance:
            min_distance = distance
            closest = obj

    return closest

func _purge_invalid() -> void:
    active_objects = active_objects.filter(is_instance_valid)

func _on_object_tree_exited(obj: RigidBody3D) -> void:
    active_objects.erase(obj)