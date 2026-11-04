extends Control

## One entry per control scheme in the selector (Ship-Controls Design Doc §3.3).
const SCHEME_NAMES := {
	ControlScheme.Scheme.STICK_DRIVES: "Stick drives: joystick forward / back, buttons up / down",
	ControlScheme.Scheme.STICK_LIFTS: "Stick lifts: joystick up / down, buttons forward / back",
}

## Each line of the controls label: what it does, then its input actions. The keys are read from the
## live input map, so the label follows the chosen scheme and any change to the bindings.
const CONTROL_LINES := [
	["forward / back", &"ship_forward", &"ship_reverse"],
	["turn left / right", &"ship_turn_left", &"ship_turn_right"],
	["rise / sink", &"ship_rise", &"ship_sink"],
	["launch random object", &"ship_launch"],
	["choose object (launch station)", &"launch_station_prev", &"launch_station_next"],
	["launch chosen object (launch station)", &"launch_station_fire"],
	["swat zurd", &"ship_swat"],
]

@export var scenes: Array[SceneEntry] = []
@onready var button_container: VBoxContainer = $CenterContainer/VBoxContainer
@onready var scheme_option: OptionButton = $CenterContainer/VBoxContainer/SchemeOption
@onready var controls_label: Label = $InfoPanel/ControlsLabel

var _buttons: Array[Button] = []

func _ready() -> void:
	_setup_scheme_option()
	for entry in scenes:
		# Sandbox scenes are left out of exported builds, so their entries are skipped there.
		if not ResourceLoader.exists(entry.path):
			if OS.has_feature("editor"):
				push_warning("MainMenu: '%s' points at a missing scene: %s" % [entry.label, entry.path])
			continue
		var button := Button.new()
		button.text = entry.label
		button.pressed.connect(_on_scene_button_pressed.bind(entry.path))
		button_container.add_child(button)
		_buttons.append(button)
	SceneChanger.load_failed.connect(_on_load_failed)

func _on_scene_button_pressed(path: String) -> void:
	_set_buttons_disabled(true)
	SceneChanger.change_scene_async(path)

## The menu stays up after a failed load, so its buttons work again.
func _on_load_failed(_target_path: String) -> void:
	_set_buttons_disabled(false)

func _set_buttons_disabled(disabled: bool) -> void:
	for b in _buttons:
		b.disabled = disabled

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
	var lines: PackedStringArray = ["--- Controls ---"]
	for line: Array in CONTROL_LINES:
		var keys: PackedStringArray = []
		for action: StringName in line.slice(1):
			var input_name := _get_input_name(action)
			if not input_name.is_empty():
				keys.append(input_name)
		var shown := " / ".join(keys) if not keys.is_empty() else "not bound"
		lines.append("%s - %s" % [shown, line[0]])
	controls_label.text = "\n".join(lines)

## The first keyboard key or mouse button bound to [param action], or "" when it has none.
func _get_input_name(action: StringName) -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key:
			return OS.get_keycode_string(key.physical_keycode if key.physical_keycode else key.keycode)
		if event is InputEventMouseButton:
			return event.as_text().to_lower()
	return ""
