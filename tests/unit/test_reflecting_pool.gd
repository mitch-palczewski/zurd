extends "res://tests/test_case.gd"

## The reflecting pool's geometry: the mirror camera, the frustum test that pauses the reflection,
## and the outline's edges. How it looks is checked by eye, not here.

const Reflection := preload("res://scenes/scenery/planar_reflection.gd")
const Edges := preload("res://scripts/utils/edge_lines.gd")


func _camera_poses() -> Array[Transform3D]:
	return [
		Transform3D.IDENTITY.translated(Vector3(0, 10, 0)),
		Transform3D(Basis.from_euler(Vector3(-0.4, 0.7, 0.0)), Vector3(3, 25, -8)),
		Transform3D(Basis.from_euler(Vector3(-1.2, -2.1, 0.0)), Vector3(-40, 4, 12)),
	]


func test_mirror_camera_sits_opposite_the_water() -> void:
	var plane := Plane(Vector3.UP, Vector3(0, 2, 0))
	for pose in _camera_poses():
		var mirrored := Reflection.mirror_transform(pose, plane)
		check_near(plane.distance_to(mirrored.origin), -plane.distance_to(pose.origin), 0.001, "the mirror camera is as far below the water as the camera is above it")
		check_near(Vector2(mirrored.origin.x, mirrored.origin.z), Vector2(pose.origin.x, pose.origin.z), 0.001, "straight below the camera")


func test_mirror_camera_looks_along_the_mirrored_view() -> void:
	var plane := Plane(Vector3.UP, Vector3(0, -5, 0))
	for pose in _camera_poses():
		var mirrored := Reflection.mirror_transform(pose, plane)
		var view := -pose.basis.z
		var mirrored_view := Vector3(view.x, -view.y, view.z)
		check_near(-mirrored.basis.z, mirrored_view, 0.001, "it looks along the view direction mirrored in the water")
		check_near(mirrored.basis.determinant(), 1.0, 0.001, "its basis stays right-handed (a valid camera)")
		check(mirrored.basis.is_conformal(), "and orthonormal")
		var back := Reflection.mirror_transform(mirrored, plane)
		check(back.is_equal_approx(pose), "mirroring twice gives the camera back")


func test_frustum_test_finds_boxes_on_screen() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_transform = Transform3D.IDENTITY
	var planes := camera.get_frustum()
	check(Reflection.is_box_in_frustum(AABB(Vector3(-1, -1, -11), Vector3(2, 2, 2)), planes), "a box straight ahead is on screen")
	check(Reflection.is_box_in_frustum(AABB(Vector3(-100, -1, -20), Vector3(200, 2, 2)), planes), "a box wider than the view is on screen")
	check(not Reflection.is_box_in_frustum(AABB(Vector3(-1, -1, 9), Vector3(2, 2, 2)), planes), "a box behind the camera is not")
	camera.queue_free()


func test_outline_follows_a_box_edges() -> void:
	var edges := Edges.find_feature_edges(BoxMesh.new(), 20.0)
	check_equal(edges.size(), 24, "a box has 12 edges; the diagonals across its faces are left out")
	for i in range(0, edges.size(), 2):
		var along := (edges[i + 1] - edges[i]).abs()
		check_near(along.length(), 1.0, 0.001, "each edge runs the whole side of the unit box")


func test_outline_keeps_open_edges() -> void:
	var edges := Edges.find_feature_edges(PlaneMesh.new(), 20.0)
	check_equal(edges.size(), 8, "a flat plane has only its 4 open edges")
	var mesh := Edges.build_outline_mesh(edges)
	check_equal(mesh.surface_get_array_len(0), 16, "the outline mesh has one quad (4 corners) per edge")
