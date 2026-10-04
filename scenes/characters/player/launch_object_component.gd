class_name LaunchObjectComponent
extends Node3D

@export_group("Launch Settings")
@export var projectile_scene: PackedScene
@export var launch_speed: float = 20.0
@export var target_stop_distance: float = 40.0
@export var cooldown_time: float = 0.5
@export var input_action: StringName = &"ship_launch"

@export_group("References")
@export var player_ship: CharacterBody3D  #OPTIONAL 

var cooldown_timer: float = 0.0

func _process(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta

	if Input.is_action_just_pressed(input_action) and cooldown_timer <= 0.0:
		launch_object()
	

func launch_object() -> void:
	if not projectile_scene:
		push_warning("LaunchObjectComponent: No projectile_scene assigned in Inspector!")
		return 
	
	var instance := projectile_scene.instantiate()
	if not (instance is RigidBody3D):
		push_error("LaunchObjectComponent: Projectile scene root must be a RigidBody3D!")
		instance.queue_free()
		return
	
	var projectile := instance as RigidBody3D

	get_tree().current_scene.add_child(projectile)
	projectile.global_transform = global_transform

	projectile.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	projectile.linear_damp = launch_speed / maxf(target_stop_distance, 0.1)

	var forward_dir = -global_transform.basis.z.normalized()
	var launch_velocity = forward_dir * launch_speed

	if player_ship:
		launch_velocity += player_ship.velocity
	
	projectile.linear_velocity = launch_velocity    

	cooldown_timer = cooldown_time
