class_name LaunchObjectComponent
extends Node3D

## The ship's one launcher, at the middle of the ship. Every launch flies straight ahead. Launch
## buttons ([LaunchStation]) call [method launch_object]; this node owns the object list and the
## launch physics.

@export_group("Launch Settings")
@export var projectile_scenes: Array[PackedScene] = []
@export var launch_speed: float = 45.0
@export var target_stop_distance: float = 70.0
@export var clearance_distance: float = 21.0
## Share of the ship's velocity added to a launched object. Below 1, an object lands at a similar
## distance whether the ship is moving or hovering.
@export_range(0.0, 1.0, 0.05) var ship_velocity_carry_over: float = 0.5

@export_group("Object Settings")
@export var angular_damp: float = 0.1

@export_group("Randomization")
@export var min_scale: float = 1.0
@export var max_scale: float = 7.0
@export var min_spin_speed: float = 1.0
@export var max_spin_speed: float = 3.0
@export_range(0.0, 45.0, 0.1, "degrees") var spread_degrees: float = 5.0


@export_group("References")
@export var player_ship: CharacterBody3D


## Launches [param scene], or a random object from [member projectile_scenes] when it is null.
func launch_object(scene: PackedScene = null) -> void:
	var projectile := _instantiate_projectile(scene)
	if projectile == null:
		return

	_setup_transform_and_scale(projectile)
	_setup_physics(projectile)

	if player_ship:
		projectile.add_collision_exception_with(player_ship)

	EventBus.spawn_requested.emit(projectile)
	ObjectTracker.register_object(projectile)

	if player_ship:
		_re_enable_player_collision_when_clear(projectile)


func get_projectile_count() -> int:
	return projectile_scenes.size()


func _re_enable_player_collision_when_clear(projectile: RigidBody3D) -> void:
	while is_instance_valid(projectile) and is_instance_valid(player_ship):
		var distance := projectile.global_position.distance_to(player_ship.global_position)
		if distance >= clearance_distance:
			break
		await get_tree().process_frame

	if is_instance_valid(projectile) and is_instance_valid(player_ship):
		projectile.remove_collision_exception_with(player_ship)


func _instantiate_projectile(scene: PackedScene) -> RigidBody3D:
	var selected_scene := scene
	if selected_scene == null:
		if projectile_scenes.is_empty():
			push_warning("LaunchObjectComponent: No scenes assigned to projectile_scenes array!")
			return null
		selected_scene = projectile_scenes.pick_random()

	if not selected_scene:
		push_warning("LaunchObjectComponent: Selected projectile scene slot is empty/null!")
		return null

	var instance := selected_scene.instantiate()
	if not (instance is RigidBody3D):
		push_error("LaunchObjectComponent: Projectile scene root must be a RigidBody3D!")
		instance.queue_free()
		return null

	return instance as RigidBody3D


func _setup_transform_and_scale(projectile: RigidBody3D) -> void:
	projectile.global_transform = global_transform.orthonormalized()
	var scale_factor := randf_range(min_scale, max_scale)
	for child in projectile.get_children():
		if child is Node3D:
			# Scale the position too, so an off-centre collision box stays lined up with the mesh.
			child.position *= scale_factor
			child.scale = Vector3.ONE * scale_factor


func _setup_physics(projectile: RigidBody3D) -> void:
	projectile.gravity_scale = 0.0
	projectile.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	projectile.linear_damp = launch_speed / maxf(target_stop_distance, 0.1)
	projectile.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	projectile.angular_damp = angular_damp
	projectile.linear_velocity = _calculate_launch_velocity()
	projectile.angular_velocity = _generate_random_spin()


func _calculate_launch_velocity() -> Vector3:
	var forward_dir = - global_transform.basis.z.normalized()

	if spread_degrees > 0.0:
		var spread_rad := deg_to_rad(spread_degrees)
		var pitch_offset := randf_range(-spread_rad, spread_rad)
		var yaw_offset := randf_range(-spread_rad, spread_rad)

		var local_x := global_transform.basis.x.normalized()
		var local_y := global_transform.basis.y.normalized()

		forward_dir = forward_dir.rotated(local_x, pitch_offset)
		forward_dir = forward_dir.rotated(local_y, yaw_offset)

	var launch_velocity = forward_dir * launch_speed

	if player_ship:
		launch_velocity += player_ship.velocity * ship_velocity_carry_over

	return launch_velocity


func _generate_random_spin() -> Vector3:
	var random_axis := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
	var spin_speed := randf_range(min_spin_speed, max_spin_speed)
	return random_axis * spin_speed
