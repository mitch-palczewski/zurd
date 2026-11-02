extends Control

## One entry per control scheme in the selector (Ship-Controls Design Doc §3.3).
const SCHEME_NAMES := {
    ControlScheme.Scheme.STICK_DRIVES: "Stick drives: joystick forward / back, buttons up / down",
    ControlScheme.Scheme.STICK_LIFTS: "Stick lifts: joystick up / down, buttons forward / back",
}

@export var scenes: Array[SceneEntry] = []
@onready var button_container: VBoxContainer = $CenterContainer/VBoxContainer
@onready var scheme_option: OptionButton = $CenterContainer/VBoxContainer/SchemeOption
@onready var controls_label: Label = $InfoPanel/ControlsLabel

var _buttons: Array[Button] = []

func _ready() -> void:
    _setup_scheme_option()
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

func _setup_scheme_option() -> void:
    for scheme: int in SCHEME_NAMES:
        scheme_option.add_item(SCHEME_NAMES[scheme], scheme)
    scheme_option.select(scheme_option.get_item_index(ControlScheme.get_current()))
    scheme_option.item_selected.connect(_on_scheme_selected)
    _update_controls_label()

func _on_scheme_selected(index: int) -> void:
    ControlScheme.apply(scheme_option.get_item_id(index) as ControlScheme.Scheme)
    _update_controls_label()

func _update_controls_label() -> void:
    var lifts := ControlScheme.get_current() == ControlScheme.Scheme.STICK_LIFTS
    controls_label.text = "\n".join([
        "--- Controls ---",
        "W / S - rise / sink" if lifts else "W / S - forward / back",
        "A / D - turn left / right",
        "space / shift - forward / back" if lifts else "space / shift - rise / sink",
        "F - launch random object",
        "J / L - choose object (launch station)",
        "K - launch chosen object (launch station)",
        "left click - swat zurd",
    ])
