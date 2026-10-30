extends Node

## A global manager that tracks every object a Zurd can target: loose launched bodies and objects
## fused into a sculpture mass ([MassPiece]s).

## Fired after an object starts being tracked.
signal object_registered(obj: Node3D)

## List of currently active objects.
var active_objects: Array[Node3D] = []


## Registers a new object to be tracked.
## Automatically connects to its [signal Node.tree_exited] signal to clean up references when freed.
## @param obj: The object to track.
func register_object(obj: Node3D) -> void:
    if not active_objects.has(obj):
        active_objects.append(obj)
        if not obj.tree_exited.is_connected(_on_object_tree_exited.bind(obj)):
            obj.tree_exited.connect(_on_object_tree_exited.bind(obj), CONNECT_ONE_SHOT)
        object_registered.emit(obj)


## Stops tracking [param obj] (for example, objects of a mass that became a cloud).
func unregister_object(obj: Node3D) -> void:
    active_objects.erase(obj)


## True while [param obj] can still be targeted: alive, in the tree, not about to be freed, and not
## part of a cloud. Untyped, because the object may already have been freed.
func is_trackable(obj) -> bool:
    if not is_instance_valid(obj) or not (obj is Node3D):
        return false
    if not obj.is_inside_tree() or obj.is_queued_for_deletion():
        return false
    if obj is MassPiece:
        return obj.is_edible()
    return true


## Returns a randomly selected active object from the tracked list.
## Returns [code]null[/code] if no objects are active.
## @return A random object, or [code]null[/code] if empty.
func get_random_object() -> Node3D:
    _purge_invalid()
    if active_objects.is_empty():
        return null
    return active_objects.pick_random()


## Finds and returns the active object closest to the specified [param from_position].
## @param from_position: The 3D world position to measure distance from.
## @return The closest object, or [code]null[/code] if no objects are active.
func get_closest_object(from_position: Vector3) -> Node3D:
    _purge_invalid()
    if active_objects.is_empty():
        return null

    var closest: Node3D = active_objects[0]
    var min_distance := from_position.distance_to(closest.global_position)

    for obj in active_objects:
        var distance := from_position.distance_to(obj.global_position)
        if distance < min_distance:
            min_distance = distance
            closest = obj

    return closest

func _purge_invalid() -> void:
    active_objects = active_objects.filter(is_trackable)

func _on_object_tree_exited(obj: Node3D) -> void:
    active_objects.erase(obj)
