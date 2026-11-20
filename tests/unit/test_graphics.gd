extends "res://tests/test_case.gd"

## The Graphics autoload (performance settings plan): presets, Custom, saving and loading, the
## defaults, and the settings that reach the screen and the frame-rate counter. Each test works on a
## config file of its own in the run's temporary folder; the real one is never touched.

var _config := ""
var _run_config := ""


func before_each() -> void:
	_run_config = Graphics.config_path
	_config = temp_path("graphics_test.json")
	DirAccess.remove_absolute(_config)
	Graphics.set_config_path(_config)


func after_each() -> void:
	Graphics.set_config_path(_run_config)
	DirAccess.remove_absolute(_config)


func test_each_preset_sets_every_setting() -> void:
	for preset: StringName in Graphics.PRESETS:
		Graphics.set_preset(preset)
		check_equal(Graphics.get_preset(), preset, "after choosing %s, the preset is %s" % [preset, preset])
		for setting: StringName in Graphics.SETTINGS:
			check_equal(Graphics.get_setting(setting), Graphics.PRESET_VALUES[preset][setting], "%s sets %s" % [preset, setting])
			check(Graphics.find_choice(setting, Graphics.PRESET_VALUES[preset][setting]) != null, "%s's %s is one of the setting's choices" % [preset, setting])


func test_changing_one_setting_makes_it_custom() -> void:
	Graphics.set_preset(Graphics.HIGH)
	var changes := watch(Graphics.settings_changed)
	var own: Variant = Graphics.get_setting(Graphics.RESOLUTION)
	var other: Variant = _other_choice(Graphics.RESOLUTION, own)
	Graphics.set_setting(Graphics.RESOLUTION, other)
	check_equal(Graphics.get_setting(Graphics.RESOLUTION), other, "the setting changed")
	check_equal(Graphics.get_preset(), Graphics.CUSTOM, "a setting that differs from every preset makes it Custom")
	check_equal(changes.size(), 1, "the change is announced")
	Graphics.set_setting(Graphics.RESOLUTION, own)
	check_equal(Graphics.get_preset(), Graphics.HIGH, "setting it back matches the preset again")


func test_a_value_that_isnt_a_choice_is_refused() -> void:
	Graphics.set_preset(Graphics.HIGH)
	Graphics.set_setting(Graphics.SHADOWS, &"ultra")
	check(was_logged("isn't a choice"), "it says so")
	check_equal(Graphics.get_setting(Graphics.SHADOWS), Graphics.PRESET_VALUES[Graphics.HIGH][Graphics.SHADOWS], "the setting keeps its value")
	Graphics.set_preset(&"extreme")
	check(was_logged("no preset"), "an unknown preset is refused too")
	check_equal(Graphics.get_preset(), Graphics.HIGH, "and nothing changes")


func test_settings_are_saved_and_loaded() -> void:
	Graphics.set_preset(Graphics.LOW)
	var shadows: Variant = _other_choice(Graphics.SHADOWS, Graphics.get_setting(Graphics.SHADOWS))
	Graphics.set_setting(Graphics.SHADOWS, shadows)
	Graphics.set_show_fps(true)
	var expected := {}
	for setting: StringName in Graphics.SETTINGS:
		expected[setting] = Graphics.get_setting(setting)
	check(FileAccess.file_exists(_config), "the settings are saved")

	Graphics.set_config_path(_config)
	for setting: StringName in Graphics.SETTINGS:
		check_equal(Graphics.get_setting(setting), expected[setting], "%s loads back" % setting)
	check(Graphics.show_fps, "Show FPS loads back")
	Graphics.set_show_fps(false)


func test_without_a_config_the_default_preset_applies() -> void:
	check_equal(Graphics.get_preset(), Graphics.get_default_preset(), "with no saved file, the settings are this computer's default preset")
	check(not FileAccess.file_exists(_config), "nothing is saved until a setting changes")
	check(not Graphics.show_fps, "the frame-rate counter is off")


func test_a_broken_file_falls_back_to_the_default() -> void:
	_write_config("this isn't JSON")
	Graphics.set_config_path(_config)
	check(was_logged("isn't valid"), "it says the file is broken")
	check_equal(Graphics.get_preset(), Graphics.get_default_preset(), "and uses the default preset")


func test_a_bad_value_in_the_file_is_skipped_alone() -> void:
	var default_preset := Graphics.get_default_preset()
	var resolution: Variant = _other_choice(Graphics.RESOLUTION, Graphics.PRESET_VALUES[default_preset][Graphics.RESOLUTION])
	# JSON keeps numbers as floats; a resolution must still match its choice.
	_write_config(JSON.stringify({"settings": {"resolution": float(resolution), "shadows": "ultra", "no_such_setting": 1}}))
	Graphics.set_config_path(_config)
	check(was_logged("isn't a choice"), "it warns about the value that isn't a choice")
	check_equal(Graphics.get_setting(Graphics.RESOLUTION), resolution, "the good value loads")
	check_equal(Graphics.get_setting(Graphics.SHADOWS), Graphics.PRESET_VALUES[default_preset][Graphics.SHADOWS], "the bad one keeps the default")


func test_integrated_gpus_start_without_reflections() -> void:
	var integrated := Graphics.default_preset_for(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU)
	check_equal(Graphics.PRESET_VALUES[integrated][Graphics.REFLECTIONS], &"off", "an integrated GPU's default preset has no reflections")
	check_equal(Graphics.default_preset_for(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU), Graphics.HIGH, "any other GPU starts on High")


func test_settings_reach_the_screen() -> void:
	var root := get_tree().root
	Graphics.set_preset(Graphics.HIGH)
	Graphics.set_setting(Graphics.RESOLUTION, 50)
	check_near(root.scaling_3d_scale, 0.5, 0.001, "3D renders at half the screen's resolution")
	check_equal(root.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR, "and is upscaled with FSR")
	Graphics.set_setting(Graphics.RESOLUTION, 100)
	check_near(root.scaling_3d_scale, 1.0, 0.001, "100% renders at full resolution")

	Graphics.set_setting(Graphics.ANTI_ALIASING, &"fxaa")
	check_equal(root.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA, "FXAA is on")
	check_equal(root.msaa_3d, Viewport.MSAA_DISABLED, "MSAA is off with FXAA")
	Graphics.set_setting(Graphics.ANTI_ALIASING, &"msaa_2x")
	check_equal(root.msaa_3d, Viewport.MSAA_2X, "MSAA 2x is on")
	check_equal(root.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED, "FXAA is off with MSAA")
	Graphics.set_setting(Graphics.ANTI_ALIASING, &"off")
	check_equal(root.msaa_3d, Viewport.MSAA_DISABLED, "Off turns MSAA off")
	check_equal(root.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED, "and FXAA")

	Graphics.set_setting(Graphics.FRAME_LIMIT, &"fps_30")
	check_equal(Engine.max_fps, 30, "a 30 fps limit caps the frame rate")
	Graphics.set_setting(Graphics.FRAME_LIMIT, &"vsync")
	check_equal(Engine.max_fps, 0, "VSync has no cap of its own")


func test_f3_toggles_the_frame_rate_counter() -> void:
	var counter := Graphics.get_node(^"FpsCounter") as CanvasLayer
	check(not counter.visible, "the counter starts hidden")
	await tap(Graphics.TOGGLE_FPS_ACTION)
	await wait_frames(1)
	check(Graphics.show_fps, "the action turns it on")
	check(counter.visible, "and it shows")
	await wait_frames(30)
	check((counter.get_node(^"Label") as Label).text.contains("fps"), "it shows the frame rate")
	await tap(Graphics.TOGGLE_FPS_ACTION)
	await wait_frames(1)
	check(not Graphics.show_fps, "pressing it again turns it off")
	check(not counter.visible, "and hides it")


## A choice of [param setting] other than [param value].
func _other_choice(setting: StringName, value: Variant) -> Variant:
	for choice: Array in Graphics.SETTINGS[setting]["choices"]:
		if choice[0] != value:
			return choice[0]
	return null


func _write_config(text: String) -> void:
	var file := FileAccess.open(_config, FileAccess.WRITE)
	file.store_string(text)
	file.close()
