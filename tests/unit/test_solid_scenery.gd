extends "res://tests/test_case.gd"

## SolidScenery: a scenery scene's meshes get static colliders on the Environment layer, shared
## between copies, except the meshes it excludes and the ones that already have a body.

const Solid := preload("res://scenes/scenery/solid_scenery.gd")
const FLUTE_SECTION := "res://scenes/scenery/flute_section.tscn"


## A scenery root with three meshes: a plain one, one in exclude, and one with its own body.
func _make_scenery(mesh: Mesh) -> Node3D:
	var scenery := Node3D.new()
	scenery.set_script(Solid)
	for mesh_name in ["Plain", "Excluded", "HasBody"]:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = mesh_name
		mesh_instance.mesh = mesh
		scenery.add_child(mesh_instance)
	var own_body := StaticBody3D.new()
	scenery.get_node(^"HasBody").add_child(own_body)
	scenery.set(&"exclude", [scenery.get_node(^"Excluded")] as Array[MeshInstance3D])
	return scenery


func _bodies_under(node: Node) -> Array[StaticBody3D]:
	var bodies: Array[StaticBody3D] = []
	for child in node.get_children():
		if child is StaticBody3D:
			bodies.append(child)
	return bodies


func _shape_of(body: StaticBody3D) -> Shape3D:
	var shapes := body.find_children("*", "CollisionShape3D", false, false)
	return (shapes[0] as CollisionShape3D).shape if shapes.size() == 1 else null


func test_meshes_get_static_colliders_on_the_environment_layer() -> void:
	var scenery := _make_scenery(BoxMesh.new())
	add_child(scenery)
	var bodies := _bodies_under(scenery.get_node(^"Plain"))
	if not check_equal(bodies.size(), 1, "a plain mesh gets one static body"):
		return
	check_equal(bodies[0].collision_layer, 1, "on the Environment layer")
	check_equal(bodies[0].collision_mask, 0, "looking for nothing itself")
	check(_shape_of(bodies[0]) is ConcavePolygonShape3D, "shaped exactly like the mesh (a trimesh)")
	check(_bodies_under(scenery.get_node(^"Excluded")).is_empty(), "an excluded mesh stays non-solid")
	check_equal(_bodies_under(scenery.get_node(^"HasBody")).size(), 1, "a mesh with its own body gets no second one")
	scenery.queue_free()


func test_copies_share_one_shape_per_mesh() -> void:
	var mesh := BoxMesh.new()
	var first := _make_scenery(mesh)
	var second := _make_scenery(mesh)
	add_child(first)
	add_child(second)
	var first_shape := _shape_of(_bodies_under(first.get_node(^"Plain"))[0])
	var second_shape := _shape_of(_bodies_under(second.get_node(^"Plain"))[0])
	check(first_shape != null and first_shape == second_shape, "two copies of the same mesh share one shape")
	var other := _make_scenery(SphereMesh.new())
	add_child(other)
	check(_shape_of(_bodies_under(other.get_node(^"Plain"))[0]) != first_shape, "a different mesh gets its own shape")
	for scenery in [first, second, other]:
		scenery.queue_free()


func test_flute_section_is_solid_but_its_water_is_not() -> void:
	var flute := (load(FLUTE_SECTION) as PackedScene).instantiate()
	add_child(flute)
	check_equal(_bodies_under(flute.get_node(^"section")).size(), 1, "the flute section's basin is solid")
	check(_bodies_under(flute.get_node(^"section_waters")).is_empty(), "its water isn't, like the reflecting pool's")
	flute.queue_free()
