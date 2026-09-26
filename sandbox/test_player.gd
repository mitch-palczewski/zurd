extends CharacterBody3D

@onready var cockpit: Node3D = $Cockpit
@onready var controllers_container: Node = $Controllers

var active_controller

func _ready() -> void:
	# Default to first controller child
	if controllers_container.get_child_count() > 0:
		set_controller(0)

func _unhandled_input(event: InputEvent) -> void:
	# Quick-switch control schemes during playtesting using number keys 1-3
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: set_controller(0)
			KEY_2: set_controller(1)
			KEY_3: set_controller(2)
			KEY_4: set_controller(3)

func set_controller(index: int) -> void:
	if index < controllers_container.get_child_count():
		active_controller = controllers_container.get_child(index) 

func _physics_process(delta: float) -> void:
	if active_controller:
		active_controller.process_flight(self, cockpit, delta)
