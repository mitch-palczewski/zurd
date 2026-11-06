class_name ControllerProfile
extends RefCounted

## One controller layout: which buttons and axes drive which input actions (Ship-Controls Design Doc
## §6.3). The [code]Controllers[/code] autoload gives each connected controller a profile and binds its
## events to that controller only, so controllers with different layouts can be connected at once.[br]
## A binding is plain data, [code]{"button": index}[/code] or [code]{"axis": index, "value": -1.0 or 1.0}[/code],
## so the built-in profiles are written here and learned ones save as JSON.

## Every action a controller can drive, in the order the Controller Setup screen asks for them.
const ACTIONS: Array[StringName] = [
	&"ship_forward",
	&"ship_reverse",
	&"ship_turn_left",
	&"ship_turn_right",
	&"ship_rise",
	&"ship_sink",
	&"ship_launch",
	&"launch_station_prev",
	&"launch_station_fire",
	&"launch_station_next",
]

const STANDARD_GAMEPAD := &"standard_gamepad"
const ARCADE_KIT := &"arcade_kit"

var id: StringName
var display_name: String
## Controller names ([method Input.get_joy_name]) that get this profile automatically when they connect.
var device_names: PackedStringArray = []
## Each action's bindings.
var bindings: Dictionary[StringName, Array] = {}


func _init(p_id: StringName, p_display_name: String, p_bindings: Dictionary[StringName, Array] = {}) -> void:
	id = p_id
	display_name = p_display_name
	bindings = p_bindings


## The profiles that ship with the game, in menu order. The standard gamepad is the 8BitDo's layout and
## the default for any controller nothing else claims. The arcade kit is empty until it's learned.
static func create_built_in() -> Array[ControllerProfile]:
	var standard_bindings: Dictionary[StringName, Array] = {
		&"ship_forward": [axis(JOY_AXIS_LEFT_Y, -1.0), button(JOY_BUTTON_DPAD_UP)],
		&"ship_reverse": [axis(JOY_AXIS_LEFT_Y, 1.0), button(JOY_BUTTON_DPAD_DOWN)],
		&"ship_turn_left": [axis(JOY_AXIS_LEFT_X, -1.0), button(JOY_BUTTON_DPAD_LEFT)],
		&"ship_turn_right": [axis(JOY_AXIS_LEFT_X, 1.0), button(JOY_BUTTON_DPAD_RIGHT)],
		&"ship_rise": [button(JOY_BUTTON_Y), axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		&"ship_sink": [button(JOY_BUTTON_A), axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		&"ship_launch": [button(JOY_BUTTON_B)],
		&"launch_station_prev": [button(JOY_BUTTON_LEFT_SHOULDER)],
		&"launch_station_fire": [button(JOY_BUTTON_X)],
		&"launch_station_next": [button(JOY_BUTTON_RIGHT_SHOULDER)],
	}
	return [
		ControllerProfile.new(STANDARD_GAMEPAD, "Standard gamepad", standard_bindings),
		ControllerProfile.new(ARCADE_KIT, "Arcade kit"),
	]


static func button(index: int) -> Dictionary:
	return {"button": index}


static func axis(index: int, value: float) -> Dictionary:
	return {"axis": index, "value": signf(value)}


## The binding a pressed button or a pushed axis makes, or an empty Dictionary for any other event.
static func event_to_binding(event: InputEvent) -> Dictionary:
	if event is InputEventJoypadButton:
		return button(event.button_index)
	if event is InputEventJoypadMotion:
		return axis(event.axis, event.axis_value)
	return {}


## An input event for [param binding] that matches only [param device].
static func binding_to_event(binding: Dictionary, device: int) -> InputEvent:
	if binding.has("button"):
		var button_event := InputEventJoypadButton.new()
		button_event.device = device
		button_event.button_index = int(binding["button"]) as JoyButton
		return button_event
	var motion := InputEventJoypadMotion.new()
	motion.device = device
	motion.axis = int(binding["axis"]) as JoyAxis
	motion.axis_value = float(binding["value"])
	return motion


## A short label for [param binding], such as "Button 3" or "Axis 1 −".
static func describe(binding: Dictionary) -> String:
	if binding.has("button"):
		return "Button %d" % binding["button"]
	return "Axis %d %s" % [binding["axis"], "+" if binding["value"] > 0.0 else "−"]


## The profile's learned data, for saving as JSON.
func to_dict() -> Dictionary:
	var saved_bindings := {}
	for action in bindings:
		saved_bindings[String(action)] = bindings[action]
	return {"device_names": Array(device_names), "bindings": saved_bindings}


## Replaces the bindings and device names with saved ones ([method to_dict]). Unknown actions and
## malformed bindings are dropped; JSON numbers come back as whole indices.
func load_dict(data: Dictionary) -> void:
	bindings = {}
	var saved_bindings = data.get("bindings", {})
	if saved_bindings is Dictionary:
		for action in saved_bindings:
			if StringName(action) not in ACTIONS or not saved_bindings[action] is Array:
				continue
			var list: Array = []
			for binding in saved_bindings[action]:
				var clean := _clean(binding)
				if not clean.is_empty():
					list.append(clean)
			bindings[StringName(action)] = list
	var saved_names = data.get("device_names", [])
	device_names = PackedStringArray(saved_names) if saved_names is Array else PackedStringArray()


static func _clean(binding: Variant) -> Dictionary:
	if not binding is Dictionary:
		return {}
	if _is_number(binding.get("button")):
		return button(int(binding["button"]))
	if _is_number(binding.get("axis")) and _is_number(binding.get("value")):
		return axis(int(binding["axis"]), float(binding["value"]))
	return {}


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
