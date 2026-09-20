extends Control

@export_file("*.tscn") var world_scene_path: String 
@onready var start_button: Button = $CenterContainer/VBoxContainer/Button

func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)


func _on_start_button_pressed() -> void:
	start_button.disabled = true
	SceneManager.change_scene_async(world_scene_path)
