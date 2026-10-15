extends Control

@export var scenes: Array[SceneEntry] = []
@onready var button_container: VBoxContainer = $CenterContainer/VBoxContainer

var _buttons: Array[Button] = []

func _ready() -> void:
    for entry in scenes:
        var button := Button.new()
        button.text = entry.label
        button.pressed.connect(_on_scene_button_pressed.bind(entry.path))
        button_container.add_child(button)
        _buttons.append(button)

func _on_scene_button_pressed(path: String) -> void:
    for b in _buttons:
        b.disabled = true
    SceneChanger.change_scene_async(path)