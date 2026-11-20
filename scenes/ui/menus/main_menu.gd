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
	["show frame rate", &"toggle_fps"],
]

const CONTROLLER_SETUP_PATH := "uid://cof4wo1dnpuiy" # controller_setup.tscn
## Width of the Performance panel on the right, and its distance from the screen's top and right.
const PERFORMANCE_PANEL_WIDTH := 330.0
const PERFORMANCE_PANEL_MARGIN := Vector2(27.0, 48.0)

@export var scenes: Array[SceneEntry] = []
@onready var button_container: VBoxContainer = $CenterContainer/VBoxContainer
@onready var controller_list: VBoxContainer = $CenterContainer/VBoxContainer/ControllerList
@onready var controller_setup_button: Button = $CenterContainer/VBoxContainer/ControllerSetupButton
@onready var controls_label: Label = $InfoPanel/ControlsLabel
## The Performance section, made in code by [method _setup_performance]. Its dropdowns are named
## after what they set: "preset", or a setting's id.
var performance_panel: VBoxContainer

var _buttons: Array[Button] = []
var _preset_ids: Array[StringName] = []
var _show_fps_box: CheckBox

func _ready() -> void:
	_update_controls_label()
	_setup_controllers()
	_setup_performance()
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

## The Performance section (performance settings plan), on the right of the screen: the preset,
## each setting and Show FPS. Changes apply at once; Graphics saves them for this computer.
func _setup_performance() -> void:
	performance_panel = VBoxContainer.new()
	performance_panel.name = "PerformancePanel"
	add_child(performance_panel)
	performance_panel.anchor_left = 1.0
	performance_panel.anchor_right = 1.0
	performance_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	performance_panel.offset_left = -PERFORMANCE_PANEL_MARGIN.x - PERFORMANCE_PANEL_WIDTH
	performance_panel.offset_right = -PERFORMANCE_PANEL_MARGIN.x
	performance_panel.offset_top = PERFORMANCE_PANEL_MARGIN.y

	var title := Label.new()
	title.text = "Performance"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	performance_panel.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	performance_panel.add_child(grid)

	var preset_option := _add_setting_row(grid, "preset", "Preset")
	for preset: StringName in Graphics.PRESETS:
		preset_option.add_item(Graphics.PRESETS[preset])
		_preset_ids.append(preset)
	# Shown when the settings match no preset; it can't be picked.
	preset_option.add_item("Custom")
	preset_option.set_item_disabled(_preset_ids.size(), true)
	_preset_ids.append(Graphics.CUSTOM)
	preset_option.item_selected.connect(func(index: int) -> void: Graphics.set_preset(_preset_ids[index]))

	for setting: StringName in Graphics.SETTINGS:
		var choices: Array = Graphics.SETTINGS[setting]["choices"]
		var option := _add_setting_row(grid, setting, Graphics.SETTINGS[setting]["name"])
		for choice: Array in choices:
			option.add_item(choice[1])
		option.item_selected.connect(func(index: int) -> void: Graphics.set_setting(setting, choices[index][0]))

	_show_fps_box = CheckBox.new()
	_show_fps_box.name = "ShowFps"
	var key := _get_input_name(Graphics.TOGGLE_FPS_ACTION)
	_show_fps_box.text = "Show FPS" if key.is_empty() else "Show FPS (%s)" % key
	_show_fps_box.toggled.connect(Graphics.set_show_fps)
	performance_panel.add_child(_show_fps_box)

	Graphics.settings_changed.connect(_update_performance)
	_update_performance()

## A row of the Performance grid: [param label], and a dropdown named [param id], which it returns.
func _add_setting_row(grid: GridContainer, id: String, label: String) -> OptionButton:
	var name_label := Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(name_label)
	var option := OptionButton.new()
	option.name = id
	option.custom_minimum_size.x = 130.0
	grid.add_child(option)
	return option

## Shows the current settings (selecting doesn't emit item_selected, so nothing is set again).
func _update_performance() -> void:
	var preset_option := performance_panel.find_child("preset", true, false) as OptionButton
	preset_option.select(_preset_ids.find(Graphics.get_preset()))
	for setting: StringName in Graphics.SETTINGS:
		var option := performance_panel.find_child(setting, true, false) as OptionButton
		var values: Array = Graphics.SETTINGS[setting]["choices"].map(func(choice: Array) -> Variant: return choice[0])
		option.select(values.find(Graphics.get_setting(setting)))
	_show_fps_box.set_pressed_no_signal(Graphics.show_fps)

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
