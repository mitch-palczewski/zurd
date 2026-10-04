class_name LaunchObjectComponent
extends Node3D

@export_group("Launch Settings")
@export var projectile_scene: PackedScene
@export var launch_speed: float = 20.0
@export var target_stop_distance: float = 40.0
@export var cooldown_time: float = 0.5
@export var input_action: StringName = &"ship_launch"

@export_group("Randomization")
@export var min_scale: float = 0.7 
@export var max_scale: float = 1.4
@export var min_spin_speed: float = 0.2
@export var max_spin_speed: float = 1.0
@export_range(0.0, 45.0 , 0.1, "degrees") var spread_degrees: float = 2.0

@export_group("References")
@export var player_ship: CharacterBody3D  

var cooldown_timer: float = 0.0

func _process(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta

	if Input.is_action_just_pressed(input_action) and cooldown_timer <= 0.0:
		launch_object()
	

func launch_object() -> void:
	var projectile := _instantiate_projectile()

	_setup_transform_and_scale(projectile)
	_setup_physics(projectile)

	EventBus.spawn_requested.emit(projectile)

	cooldown_timer = cooldown_time


func _instantiate_projectile() -> RigidBody3D:
	if not projectile_scene:
		push_warning("LaunchObjectComponent: No projectile_scene assigned in Inspector!")
		return null
	
	var instance := projectile_scene.instantiate()
	if not (instance is RigidBody3D):
		push_error("LaunchObjectComponent: Projectile scene root must be a RigidBody3D!")
		instance.queue_free()
		return null

	return instance as RigidBody3D


func _setup_transform_and_scale(projectile: RigidBody3D) -> void:
	projectile.global_transform = global_transform
	var scale_factor := randf_range(min_scale, max_scale)
	projectile.scale = Vector3.ONE * scale_factor


func _setup_physics(projectile: RigidBody3D) -> void:
	projectile.gravity_scale = 0.0 
	projectile.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	projectile.linear_damp = launch_speed / maxf(target_stop_distance, 0.1)
	projectile.linear_velocity = _calculate_launch_velocity()
	projectile.angular_velocity = _generate_random_spin()


func _calculate_launch_velocity() -> Vector3:
	var forward_dir = -global_transform.basis.z.normalized()

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
		launch_velocity += player_ship.velocity

	return launch_velocity 


func _generate_random_spin() -> Vector3:
	var random_axis := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
	var spin_speed := randf_range(min_spin_speed, max_spin_speed)
	return random_axis * spin_speed

	
