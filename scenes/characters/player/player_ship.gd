class_name PlayerShip
extends CharacterBody3D

## The group the ship is in, so Zurds and their director can find it.
const GROUP := &"player_ship"

@onready var flight_controller: PlayerFlightController = $FlightController
@onready var cockpit: Node3D = $Cockpit
@onready var camera: Camera3D = $Cockpit/Camera3D


func _ready() -> void:
	add_to_group(GROUP)
	flight_controller.setup(self, cockpit, camera)
	flight_controller.impact_occurred.connect(_on_flight_impact)


func _on_flight_impact(collider: Object, _force: float, collider_shape: Object) -> void:
	# Only the objects the ship actually hits break off (Sculpture-Mass Design Doc §4.6).
	if collider is SculptureMass:
		(collider as SculptureMass).request_break_off(collider_shape)
	# Ramming a Zurd counts as a swat (Zurd Core Design Doc §6).
	elif collider is Node3D and collider.has_method(&"take_swat"):
		var hit_direction := global_position.direction_to((collider as Node3D).global_position)
		collider.call(&"take_swat", hit_direction * maxf(velocity.length(), 1.0))
