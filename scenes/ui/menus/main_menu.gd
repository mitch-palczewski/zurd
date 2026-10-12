extends Control

@export_file("*.tscn") var world_scene_path: String 
@export_file("*.tscn") var world2: String 
@onready var start_button: Button = $CenterContainer/VBoxContainer/BaseWorld
@onready var button2: Button = $CenterContainer/VBoxContainer/MapIdeaWorld

func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	button2.pressed.connect(_on_start_button2_pressed)


func _on_start_button_pressed() -> void:
	start_button.disabled = true
	SceneChanger.change_scene_async(world_scene_path)

func _on_start_button2_pressed() -> void:
	start_button.disabled = true
	SceneChanger.change_scene_async(world2)
