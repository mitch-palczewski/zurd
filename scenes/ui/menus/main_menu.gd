extends Control

## Each line of the controls label: what it does, then its input actions. The keys are read from the
## live input map, so the label follows any change to the bindings.
const CONTROL_LINES := [
	["forward / back", &"ship_forward", &"ship_reverse"],
	["turn left / right", &"ship_turn_left", &"ship_turn_right"],
	["rise / sink", &"ship_rise", &"ship_sink"],
	["launch random object", &"ship_launch"],
	["choose object (launch station)", &"launch_station_prev", &"launch_station_next"],
	["launch chosen or random object (launch station)", &"launch_station_fire"],
	["swat zurd", &"ship_swat"],
]

const CONTROLLER_SETUP_PATH := "uid://cof4wo1dnpuiy" # controller_setup.tscn

@export var scenes: Array[SceneEntry] = []
@onready var button_container: VBoxContainer = $CenterContainer/VBoxContainer
@onready var controller_list: VBoxContainer = $CenterContainer/VBoxContainer/ControllerList
@onready var controller_setup_button: Button = $CenterContainer/VBoxContainer/ControllerSetupButton
@onready var controls_label: Label = $InfoPanel/ControlsLabel

var _buttons: Array[Button] = []

func _ready() -> void:
	_update_controls_label()
	_setup_controllers()
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

## The Controllers section (Ship-Controls Design Doc §6.3): a profile dropdown for each connected
## controller, and the way to the Controller Setup screen.
func _setup_controllers() -> void:
	controller_setup_button.pressed.connect(_on_scene_button_pressed.bind(CONTROLLER_SETUP_PATH))
	_buttons.append(controller_setup_button)
	Controllers.devices_changed.connect(_update_controller_list)
	_update_controller_list()

func _update_controller_list() -> void:
	for row in controller_list.get_children():
		row.queue_free()
	var devices := Controllers.get_devices()
	if devices.is_empty():
		var none := Label.new()
		none.text = "None connected (keyboard and mouse always work)"
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		controller_list.add_child(none)
		return
	for device in devices:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		var joy_name := Controllers.get_device_name(device)
		name_label.text = joy_name if not joy_name.is_empty() else "Controller %d" % device
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(_make_profile_option(device))
		controller_list.add_child(row)

func _make_profile_option(device: int) -> OptionButton:
	var option := OptionButton.new()
	var ids: Array[StringName] = []
	for profile: ControllerProfile in Controllers.profiles.values():
		option.add_item(profile.display_name)
		ids.append(profile.id)
	option.add_item("Off")
	ids.append(Controllers.OFF)
	option.select(ids.find(Controllers.get_profile_id(device)))
	option.item_selected.connect(func(index: int) -> void: Controllers.set_profile(device, ids[index]))
	return option

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
