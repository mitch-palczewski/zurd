extends "res://tests/test_case.gd"

## The Controllers autoload: a profile per controller, bound to that controller only (Ship-Controls
## Design Doc §6.3), and the saved choices. Each test works on a config file of its own in the
## run's temporary folder; the real one is never touched. The controllers are made up.

const PAD_A := 70
const PAD_B := 71
const PAD_C := 72
const STANDARD := ControllerProfile.STANDARD_GAMEPAD
const ARCADE := ControllerProfile.ARCADE_KIT

var _config := ""
var _run_config := ""


func before_each() -> void:
	_run_config = Controllers.config_path
	_config = temp_path("controllers_test.json")
	DirAccess.remove_absolute(_config)
	Controllers.set_config_path(_config)


func after_each() -> void:
	for device in [PAD_A, PAD_B, PAD_C]:
		if Controllers.get_devices().has(device):
			Controllers.disconnect_device(device)
	Controllers.set_config_path(_run_config)
	DirAccess.remove_absolute(_config)


func test_each_controller_is_bound_to_itself_only() -> void:
	Controllers.connect_device(PAD_A, "Test Pad A", "test-guid-a")
	Controllers.connect_device(PAD_B, "Test Pad B", "test-guid-b")
	check_equal(Controllers.get_profile_id(PAD_A), STANDARD, "a new controller gets the standard gamepad")
	check_equal(Controllers.get_profile_id(PAD_B), STANDARD, "so does a second one")
	var standard := Controllers.profiles[STANDARD]
	for action in ControllerProfile.ACTIONS:
		var count: int = standard.bindings.get(action, []).size()
		check_equal(_events(PAD_A, action).size(), count, "pad A has every standard binding for %s" % action)
		check_equal(_events(PAD_B, action).size(), count, "pad B has its own copy for %s" % action)
		check(_events(-1, action).is_empty(), "no binding for %s matches every controller" % action)
	check(InputMap.event_is_action(_button(PAD_A, JOY_BUTTON_B), &"ship_launch"), "pad A's B button launches")
	check(not InputMap.event_is_action(_button(PAD_C, JOY_BUTTON_B), &"ship_launch"), "a controller that isn't connected does nothing")

	Controllers.set_profile(PAD_B, ARCADE)
	check(not InputMap.event_is_action(_button(PAD_B, JOY_BUTTON_B), &"ship_launch"), "pad B on the (empty) arcade kit no longer launches with B")
	check(InputMap.event_is_action(_button(PAD_A, JOY_BUTTON_B), &"ship_launch"), "pad A is unaffected")


func test_off_unbinds_a_controller() -> void:
	Controllers.connect_device(PAD_A, "Test Pad A", "test-guid-a")
	Controllers.set_profile(PAD_A, Controllers.OFF)
	check_equal(Controllers.get_profile_id(PAD_A), Controllers.OFF, "the controller is off")
	for action in ControllerProfile.ACTIONS:
		check(_events(PAD_A, action).is_empty(), "an ignored controller has no binding for %s" % action)


func test_profile_choice_is_remembered() -> void:
	Controllers.connect_device(PAD_B, "Test Pad B", "test-guid-b")
	Controllers.set_profile(PAD_B, ARCADE)
	check(FileAccess.file_exists(_config), "the choice is saved")
	Controllers.set_config_path(_config)
	check_equal(Controllers.get_profile_id(PAD_B), ARCADE, "after loading the saved file, the controller keeps its profile")
	Controllers.disconnect_device(PAD_B)
	Controllers.connect_device(PAD_B, "Test Pad B", "test-guid-b")
	check_equal(Controllers.get_profile_id(PAD_B), ARCADE, "a controller that reconnects gets its remembered profile (by GUID)")
	Controllers.connect_device(PAD_C, "Test Pad B", "test-guid-c")
	check_equal(Controllers.get_profile_id(PAD_C), STANDARD, "another controller of the same name isn't affected by that choice")


func test_learned_layout_is_saved_and_recognised() -> void:
	Controllers.connect_device(PAD_B, "Test Pad B", "test-guid-b")
	var learned: Dictionary[StringName, Array] = {&"ship_launch": [ControllerProfile.button(7)]}
	Controllers.save_learned_profile(ARCADE, learned, PAD_B)
	check_equal(Controllers.get_profile_id(PAD_B), ARCADE, "the controller that taught the layout uses it")
	check(InputMap.event_is_action(_button(PAD_B, 7), &"ship_launch"), "its learned button launches")

	Controllers.set_config_path(_config)
	check_equal(Controllers.profiles[ARCADE].bindings.get(&"ship_launch"), [{"button": 7}], "the learned layout loads back")
	check(Controllers.profiles[ARCADE].device_names.has("Test Pad B"), "with the controller's name")
	Controllers.connect_device(PAD_C, "Test Pad B", "test-guid-c")
	check_equal(Controllers.get_profile_id(PAD_C), ARCADE, "a new controller with that name gets the learned profile")


func test_reset_restores_the_built_in_layout() -> void:
	Controllers.connect_device(PAD_B, "Test Pad B", "test-guid-b")
	var learned: Dictionary[StringName, Array] = {&"ship_launch": [ControllerProfile.button(7)]}
	Controllers.save_learned_profile(ARCADE, learned, PAD_B)
	Controllers.reset_profile(ARCADE)
	check(Controllers.profiles[ARCADE].bindings.is_empty(), "the arcade kit is back to its built-in (empty) layout")
	check_equal(Controllers.get_profile_id(PAD_B), ARCADE, "the controller keeps its profile choice")
	Controllers.set_config_path(_config)
	check(Controllers.profiles[ARCADE].bindings.is_empty(), "the reset is saved too")


func test_broken_config_falls_back_to_built_in_profiles() -> void:
	var file := FileAccess.open(_config, FileAccess.WRITE)
	file.store_string("{ this isn't JSON")
	file.close()
	Controllers.set_config_path(_config)
	check(was_logged("isn't valid"), "a broken config file is reported")
	check_equal(Controllers.profiles[STANDARD].bindings.size(), ControllerProfile.ACTIONS.size(), "the standard gamepad keeps its built-in layout")
	Controllers.connect_device(PAD_A, "Test Pad A", "test-guid-a")
	check_equal(Controllers.get_profile_id(PAD_A), STANDARD, "and controllers still work")


func test_controller_events_in_project_settings_are_dropped() -> void:
	var planted := InputEventJoypadButton.new()
	planted.device = -1
	planted.button_index = JOY_BUTTON_START
	InputMap.action_add_event(&"ship_launch", planted)
	# A fresh copy of the autoload, so its startup runs again.
	var fresh: Node = (load("res://scripts/autoload/controllers.gd") as GDScript).new()
	fresh.set(&"config_path", _config)
	add_child(fresh)
	check(not InputMap.event_is_action(_button(PAD_C, JOY_BUTTON_START), &"ship_launch"), "a controller binding from Project Settings is dropped at startup")
	check(was_logged("has a controller binding in Project Settings"), "with a warning")
	fresh.free()


## The controller events bound to [param action] for [param device] (-1: every controller).
func _events(device: int, action: StringName) -> Array[InputEvent]:
	var found: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device == device:
			found.append(event)
	return found


func _button(device: int, index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index as JoyButton
	event.pressed = true
	return event
