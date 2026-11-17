class_name SolidScenery
extends Node3D

## Makes a scenery scene solid. Put it on the scene's root: in the game, every mesh under it gets a
## static collider of its exact shape (a trimesh, so hollows and holes stay open) on the
## Environment layer, so the ship, launched objects and Zurds bump into it. Each mesh's shape is
## built once and kept on the mesh (meta [constant SHAPE_META]), so every copy of the scene shares
## it and it goes when the mesh does (a cache that outlived the meshes kept them alive after their
## scene was freed). Meshes in [member exclude] (water surfaces, say) stay non-solid, and a mesh
## that already has a body of its own (such as one with an import-generated collider) is left
## alone.

## Meta on a mesh holding its collider shape.
const SHAPE_META := &"solid_scenery_shape"

## Layers the colliders are on. 1 (Environment) is what the ship, objects and Zurds collide with.
@export_flags_3d_physics var collision_layer: int = 1
## Meshes that stay non-solid.
@export var exclude: Array[MeshInstance3D] = []


func _ready() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance in exclude or _has_body(mesh_instance):
			continue
		var body := StaticBody3D.new()
		body.name = "Collider"
		body.collision_layer = collision_layer
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = shape_for(mesh_instance.mesh)
		body.add_child(shape)
		mesh_instance.add_child(body)


## The collider shape for [param mesh]: its exact surface, built the first time it's asked for.
static func shape_for(mesh: Mesh) -> Shape3D:
	if not mesh.has_meta(SHAPE_META):
		mesh.set_meta(SHAPE_META, mesh.create_trimesh_shape())
	return mesh.get_meta(SHAPE_META)


func _has_body(mesh_instance: MeshInstance3D) -> bool:
	for child in mesh_instance.get_children():
		if child is CollisionObject3D:
			return true
	return false
