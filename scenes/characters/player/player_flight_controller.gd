class_name PlayerFlightController
extends Node

signal impact_occured(collider: Object, force: float)

@export_group("Speed")
@export var base_speed: float = 5.0
@export var boost_speed: float = 20.0
@export var acceleration: float = 10.0
@export var deceleration: float = 10.0

@export_group("Agility")
@export var pitch_speed: float = 0.5
@export var boost_pitch_speed: float = 0.8
@export var yaw_speed: float = 0.5
@export var boost_yaw_speed: float = 0.8

@export_group("Pitch Thresholds & Return")
@export var hard_max_pitch: float = deg_to_rad(80.0)
@export var comfort_max_pitch: float = deg_to_rad(20.0)
@export var pitch_return_speed: float = 0.6

@export_group("Collision Interaction")
@export var push_force: float = 12.0
@export var min_impact_speed: float = 2.0

@export_group("Visual Cockpit Feedback")
@export var max_roll_bank: float = deg_to_rad(10.0)
@export var max_pitch_lean: float = deg_to_rad(7.0)
@export var lean_smoothing: float = 5.0 

@export_group("Camera FOV Boost")
@export var base_fov: float = 75.0
@export var boost_fov: float = 92.0
@export var fov_smoothing: float = 6

@export_group("G-Force Visual Feedback")
@export var max_g_offset_y:float = 0.02 
@export var g_force_smoothing: float = 3.0

var ship: CharacterBody3D
var cockpit: Node3D
var camera: Camera3D

var current_speed: float = 0.0
var speed_ratio: float = 0.0
var current_bank: float = 0.0
var current_pitch: float = 0.0
var current_visual_pitch: float = 0.0
var base_camera_pos: Vector3 = Vector3.ZERO


func setup(player_ship: CharacterBody3D, player_cockpit: Node3D, player_camera: Camera3D) -> void:
    ship = player_ship
    cockpit = player_cockpit
    camera = player_camera
    current_speed = base_speed

    if camera:
        camera.fov = base_fov
        base_camera_pos = camera.position


func _physics_process(delta:float) -> void:
    if not ship or not cockpit:
        return 
    _process_flight(delta)


func _process_flight(delta:float) -> void:
    var pitch_input := Input.get_axis(&"ship_pitch_down", &"ship_pitch_up")
    var yaw_input := Input.get_axis(&"ship_yaw_right", &"ship_yaw_left")
    var is_boosting := Input.is_action_pressed(&"ship_boost")

    _apply_thrust(is_boosting, delta)
    _apply_pitch(pitch_input,  delta)
    _apply_yaw(yaw_input, delta)

    ship.velocity = -ship.transform.basis.z * current_speed
    var pre_slide_velocity = ship.velocity
    ship.move_and_slide()

    _update_cockpit_visuals(pitch_input, yaw_input, delta)

    _handle_collisions(pre_slide_velocity, delta)


func _apply_thrust(is_boosting: bool, delta: float):
    var target_speed := boost_speed if is_boosting else base_speed
    var rate := acceleration if target_speed > current_speed else deceleration
    current_speed = move_toward(current_speed, target_speed, rate * delta)
    speed_ratio = clampf((current_speed - base_speed) / (boost_speed - base_speed), 0.0, 1.0)


func _apply_pitch(pitch_input: float, delta:float) -> void:
    var active_pitch_speed = lerp(pitch_speed, boost_pitch_speed, speed_ratio)
    var new_pitch: float = current_pitch 
    if pitch_input != 0.0:
        var target_pitch_delta = pitch_input * active_pitch_speed * delta
        new_pitch = clamp(current_pitch + target_pitch_delta, -hard_max_pitch, hard_max_pitch)
    else:
        if current_pitch > comfort_max_pitch:
            new_pitch = lerp(current_pitch, comfort_max_pitch, pitch_return_speed * delta)
        elif current_pitch < - comfort_max_pitch:
            new_pitch = lerp(current_pitch, -comfort_max_pitch, pitch_return_speed * delta)
    var actual_pitch_delta = new_pitch - current_pitch
    current_pitch = new_pitch
    ship.rotate_object_local(Vector3.RIGHT, actual_pitch_delta) 


func _apply_yaw(yaw_input: float, delta: float) -> void:
    var active_yaw_speed = lerp(yaw_speed, boost_yaw_speed, speed_ratio)
    ship.rotate_object_local(Vector3.UP, yaw_input * active_yaw_speed * delta)


func _update_cockpit_visuals(pitch_input:float, yaw_input: float, delta: float) -> void:
    var target_lean_x = current_pitch * (max_pitch_lean / hard_max_pitch)
    current_visual_pitch = lerp_angle(current_visual_pitch, target_lean_x, lean_smoothing * delta)
    cockpit.rotation.x = current_visual_pitch

    var target_bank_z = yaw_input * max_roll_bank
    current_bank = lerp_angle(current_bank, target_bank_z, lean_smoothing * delta)
    cockpit.rotation.z = current_bank

    if camera:
        var target_fov = lerp(base_fov, boost_fov, speed_ratio)
        camera.fov = lerp(camera.fov, target_fov, fov_smoothing * delta)

        var g_multiplier = lerp(1.0, 1.5, speed_ratio)
        var target_y_offset = -pitch_input * max_g_offset_y * g_multiplier
        var target_cam_pos = base_camera_pos + Vector3(0.0 , target_y_offset, 0.0)

       
        var smoothed_pos = camera.position.lerp(target_cam_pos, g_force_smoothing * delta) 

        camera.position = smoothed_pos 


func _handle_collisions(pre_slide_velocity: Vector3 ,delta: float) -> void:
    var collision_count = ship.get_slide_collision_count()

    var impulse_force = current_speed * push_force * delta

    for i in collision_count:
        var collision = ship.get_slide_collision(i)
        var collider = collision.get_collider()

        if not collider:
            continue

        if collider is RigidBody3D:
            var push_dir = -collision.get_normal()
            var impact_offset = collision.get_position() - collider.global_position
            var impulse = push_dir * impulse_force
            collider.apply_impulse(impulse, impact_offset)

        var incoming_speed := -pre_slide_velocity.dot(collision.get_normal())

        if incoming_speed >= min_impact_speed:
            impact_occured.emit(collider, impulse_force)


