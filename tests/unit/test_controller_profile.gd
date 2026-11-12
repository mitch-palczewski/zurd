extends "res://tests/test_case.gd"

## ControllerProfile: controller layouts as plain data (Ship-Controls Design Doc §6.3).


func test_built_in_profiles() -> void:
	var profiles := ControllerProfile.create_built_in()
	var ids: Array[StringName] = []
	for profile in profiles:
		ids.append(profile.id)
	check_equal(ids, [ControllerProfile.STANDARD_GAMEPAD, ControllerProfile.ARCADE_KIT], "the standard gamepad comes first, then the arcade kit")
	var standard := profiles[0]
	for action in ControllerProfile.ACTIONS:
		check(not standard.bindings.get(action, []).is_empty(), "the standard gamepad binds %s" % action)
	check(profiles[1].bindings.is_empty(), "the arcade kit starts empty, until it's learned")


func test_saved_profile_loads_back_the_same() -> void:
	var bindings: Dictionary[StringName, Array] = {
		&"ship_forward": [ControllerProfile.axis(JOY_AXIS_LEFT_Y, -1.0), ControllerProfile.button(JOY_BUTTON_DPAD_UP)],
		&"ship_launch": [ControllerProfile.button(JOY_BUTTON_B)],
	}
	var saved := ControllerProfile.new(&"test", "Test", bindings)
	saved.device_names = PackedStringArray(["Pad A"])
	# Through JSON, as on disk: numbers come back as floats.
	var data: Dictionary = JSON.parse_string(JSON.stringify(saved.to_dict()))
	var loaded := ControllerProfile.new(&"test", "Test")
	loaded.load_dict(data)
	check_equal(loaded.bindings.size(), 2, "every action comes back")
	check_equal(loaded.bindings[&"ship_launch"], [{"button": JOY_BUTTON_B}], "a button binding comes back as a whole index")
	check_equal(loaded.bindings[&"ship_forward"], bindings[&"ship_forward"], "axis bindings come back with their direction")
	check(loaded.bindings[&"ship_launch"][0]["button"] is int, "button indices are ints again after JSON")
	check_equal(Array(loaded.device_names), ["Pad A"], "device names come back")


func test_load_drops_unknown_actions_and_malformed_bindings() -> void:
	var profile := ControllerProfile.new(&"test", "Test")
	profile.load_dict({
		"bindings": {
			"not_an_action": [{"button": 1}],
			"ship_launch": [{"button": "x"}, {"axis": 2}, "junk", {"button": 5.0}],
		},
		"device_names": "not a list",
	})
	check(not profile.bindings.has(&"not_an_action"), "unknown actions are dropped")
	check_equal(profile.bindings[&"ship_launch"], [{"button": 5}], "malformed bindings are dropped, good ones kept")
	check(profile.device_names.is_empty(), "malformed device names are dropped")


func test_bindings_become_events_for_one_device() -> void:
	var button := ControllerProfile.binding_to_event(ControllerProfile.button(JOY_BUTTON_B), 3) as InputEventJoypadButton
	check(button != null and button.device == 3 and button.button_index == JOY_BUTTON_B, "a button binding becomes a button event for that device only")
	var motion := ControllerProfile.binding_to_event(ControllerProfile.axis(JOY_AXIS_LEFT_X, -0.4), 5) as InputEventJoypadMotion
	check(motion != null and motion.device == 5 and motion.axis == JOY_AXIS_LEFT_X, "an axis binding becomes a motion event for that device only")
	check_equal(motion.axis_value, -1.0, "an axis binding keeps only its direction")
	check_equal(ControllerProfile.event_to_binding(button), {"button": JOY_BUTTON_B}, "and an event becomes a binding again")
	check(ControllerProfile.event_to_binding(InputEventKey.new()).is_empty(), "a key isn't a controller binding")
