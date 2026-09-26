extends Node
class_name YawBankController4

@export_group("Speed & Agility")
@export var forward_speed: float = 5.0
@export var pitch_speed: float = .5
@export var yaw_speed: float = .5

@export_group("Pitch Thresholds & Return")
@export var hard_max_pitch: float = deg_to_rad(80.0)
@export var comfort_max_pitch: float = deg_to_rad(30.0)
@export var pitch_return_speed: float = .2

@export_group("Collision Interaction")
@export var push_force: float = 12.0

@export_group("Visual Cockpit Feedback") # <--- NEW SECTION
@export var max_roll_bank: float = deg_to_rad(10.0)
@export var max_pitch_lean: float = deg_to_rad(7.0) # <--- NEW: max magnitude of visual tilt (X-axis)
@export var lean_smoothing: float = 5.0             # <--- Renamed 'bank_smoothing' for clarity

var current_bank: float = 0.0
var current_pitch: float = 0.0
var current_visual_pitch: float = 0.0 # <--- NEW: tracks smoothed visual tilt

func process_flight(ship: CharacterBody3D, cockpit: Node3D, delta: float) -> void:
	var pitch_input = Input.get_axis("move_down", "move_up")
	var yaw_input = Input.get_axis("move_right", "move_left")

	# 1. ACTUAL Pitch Logic (Calculates ship orientation)
	var new_pitch: float = current_pitch

	if pitch_input != 0.0:
		var target_pitch_delta = pitch_input * pitch_speed * delta
		new_pitch = clamp(current_pitch + target_pitch_delta, -hard_max_pitch, hard_max_pitch)
	else:
		if current_pitch > comfort_max_pitch:
			new_pitch = move_toward(current_pitch, comfort_max_pitch, pitch_return_speed * delta)
		elif current_pitch < -comfort_max_pitch:
			new_pitch = move_toward(current_pitch, -comfort_max_pitch, pitch_return_speed * delta)

	var actual_pitch_delta = new_pitch - current_pitch
	current_pitch = new_pitch
	ship.rotate_object_local(Vector3.RIGHT, actual_pitch_delta)

	# 2. ACTUAL Yaw Logic
	ship.global_rotate(Vector3.UP, yaw_input * yaw_speed * delta)

	# -------------------------------------------------------------------------
	# 3. VISUAL Cockpit Feedback Logic (Applies smoothed offsets to cockpit node)

	# --- Visual Pitch Lean (X-Axis) ---
	# NEW: Map the actual ship pitch ratio to the visual lean range.
	# Example: If hard_max_pitch is 80 and max_pitch_lean is 7.
	# When current_pitch is 40, target_lean is 3.5.
	var target_lean_x = current_pitch * (max_pitch_lean / hard_max_pitch)

	# NEW: Smoothly interpolate toward the target
	current_visual_pitch = lerp_angle(current_visual_pitch, target_lean_x, lean_smoothing * delta)

	# UPDATED: Apply visual pitch
	cockpit.rotation.x = current_visual_pitch

	# --- Visual Banking (Z-Axis, previously roll) ---
	var target_bank_z = yaw_input * max_roll_bank
	# UPDATED: Reused lean_smoothing for consistency
	current_bank = lerp_angle(current_bank, target_bank_z, lean_smoothing * delta)

	# Apply visual roll
	cockpit.rotation.z = current_bank
	# -------------------------------------------------------------------------

	# 4. Movement
	ship.velocity = -ship.transform.basis.z * forward_speed
	ship.move_and_slide()
	
	for i in ship.get_slide_collision_count():
		var collision = ship.get_slide_collision(i)
		var collider = collision.get_collider()

		if collider is RigidBody3D:
			# Direction pointing away from ship into the hit object
			var push_dir = -collision.get_normal()
			
			# Vector from the object's center of mass to the collision point
			var impact_offset = collision.get_position() - collider.global_position
			
			# Calculate impulse (scaled by ship speed and push force)
			var impulse = push_dir * forward_speed * push_force * delta
			
			# apply_impulse induces both movement and rotational spin from off-center hits
			collider.apply_impulse(impulse, impact_offset)
