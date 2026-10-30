class_name PlayerShip
extends CharacterBody3D

@onready var flight_controller: PlayerFlightController = $FlightController
@onready var cockpit: Node3D = $Cockpit
@onready var camera: Camera3D = $Cockpit/Camera3D


func _ready() -> void:
    flight_controller.setup(self, cockpit, camera)
    flight_controller.impact_occured.connect(_on_flight_impact)


func set_flight_enabled(enabled: bool) -> void:
    flight_controller.set_physics_process(enabled)

func _on_flight_impact(collider: Object, force: float, collider_shape: Object) -> void:
    print("PlayerShip: Ship collided with: ", collider.name, " Force: ", force)
    # Only the objects the ship actually hits break off (Sculpture-Mass Design Doc §4.6).
    if collider is SculptureMass:
        (collider as SculptureMass).request_break_off(collider_shape)
