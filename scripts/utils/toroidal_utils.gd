## Static helper functions for 3D toroidal space calculations. 
## Allows for the world to wrap so if you fly straight you will see the same objects repeat.
class_name ToroidalUtils
extends RefCounted


## Wraps a position vector across X and Z axes using half-extents (Vector2).
## bounds_xz.x = half-width (X), bounds_xz.y = half-depth (Z).
static func wrap_position_xz(position: Vector3, bounds_xz: Vector2) -> Vector3:
    var wrapped: Vector3 = position
    wrapped.x = wrapf(position.x, -bounds_xz.x, bounds_xz.x)
    wrapped.z = wrapf(position.z, -bounds_xz.y, bounds_xz.y)
    return wrapped


## Returns true if a position is outside the defined boundary box
static func is_out_of_bounds_xz(position: Vector3, bounds_xz: Vector2) -> bool:
    return abs(position.x) > bounds_xz.x or abs(position.z) > bounds_xz.y 