extends Node

## Graphics settings for performance (claude/plans/2026-11-20-performance-settings-plan.md): a
## preset plus individual settings, saved per computer in [member config_path], and a frame-rate
## counter toggled with the input action [constant TOGGLE_FPS_ACTION] (F3).[br]
## Settings for the whole screen go on the root viewport, the RenderingServer and the window.
## Settings for particular nodes reach every node of that kind as it enters the tree, so worlds and
## scenery need nothing of their own: each [DirectionalLight3D] for shadows, each
## [PlanarReflection] for reflections, each [SkyCanopy] for the canopy. A node's own values from
## its scene are kept as meta the first time it's seen, and High gives them back, so tuning a scene
## in the editor still counts.[br]
## Until a setting is changed (and so saved), the default preset applies: [constant MEDIUM] on an
## integrated GPU (no reflections), else [constant HIGH].

## Fired after the settings or Show FPS changed and were applied.
signal settings_changed

const CONFIG_PATH := "user://graphics_config.json"
const TOGGLE_FPS_ACTION := &"toggle_fps"

const LOW := &"low"
const MEDIUM := &"medium"
const HIGH := &"high"
## What [method get_preset] returns when the settings match no preset.
const CUSTOM := &"custom"

const RESOLUTION := &"resolution"
const SHADOWS := &"shadows"
const REFLECTIONS := &"reflections"
const SKY_CANOPY := &"sky_canopy"
const ANTI_ALIASING := &"anti_aliasing"
const FRAME_LIMIT := &"frame_limit"

## The presets in menu order, with their names.
const PRESETS := {LOW: "Low", MEDIUM: "Medium", HIGH: "High"}

## Every setting in menu order: its name and its choices as [value, name] pairs. 3D resolution is
## a percentage of the screen's.
const SETTINGS := {
	RESOLUTION: {"name": "3D resolution", "choices": [[50, "50%"], [67, "67%"], [75, "75%"], [85, "85%"], [100, "100%"]]},
	SHADOWS: {"name": "Shadows", "choices": [[&"off", "Off"], [&"low", "Low"], [&"high", "High"]]},
	REFLECTIONS: {"name": "Reflections", "choices": [[&"off", "Off"], [&"low", "Low"], [&"high", "High"]]},
	SKY_CANOPY: {"name": "Sky canopy", "choices": [[&"simple", "Simple"], [&"full", "Full"]]},
	ANTI_ALIASING: {"name": "Anti-aliasing", "choices": [[&"off", "Off"], [&"fxaa", "FXAA"], [&"msaa_2x", "MSAA 2x"]]},
	FRAME_LIMIT: {"name": "Frame limit", "choices": [[&"vsync", "VSync"], [&"fps_30", "30 fps"], [&"fps_60", "60 fps"], [&"unlimited", "Unlimited"]]},
}

## What each preset sets.
const PRESET_VALUES := {
	LOW: {RESOLUTION: 67, SHADOWS: &"low", REFLECTIONS: &"off", SKY_CANOPY: &"simple", ANTI_ALIASING: &"off", FRAME_LIMIT: &"vsync"},
	MEDIUM: {RESOLUTION: 100, SHADOWS: &"high", REFLECTIONS: &"off", SKY_CANOPY: &"full", ANTI_ALIASING: &"fxaa", FRAME_LIMIT: &"vsync"},
	HIGH: {RESOLUTION: 100, SHADOWS: &"high", REFLECTIONS: &"high", SKY_CANOPY: &"full", ANTI_ALIASING: &"fxaa", FRAME_LIMIT: &"vsync"},
}

## Low shadows: the sun's shadow map is this many pixels across, with at most two splits and hard
## edges.
const LOW_SHADOW_ATLAS := 2048
## Low reflections render at this share of a reflection's own resolution.
const LOW_REFLECTION_SCALE := 0.66
## A Simple sky canopy has at most this many shells.
const SIMPLE_CANOPY_LAYERS := 2
## Meta holding a node's own values, from its scene, of the properties these settings change.
const ORIGINAL_META := &"_graphics_original"
## Seconds between updates of the frame-rate counter's text, so it can be read.
const FPS_TEXT_INTERVAL := 0.25

## Where the settings are saved: [constant CONFIG_PATH]. The test runner points it at a temporary
## file before this node is ready, so a test run never reads or writes the real one.
var config_path: String = CONFIG_PATH
## Whether the frame-rate counter shows. Change it with [method set_show_fps].
var show_fps := false

## Setting id → its value (one of the setting's choices).
var _values: Dictionary = {}
var _fps_layer: CanvasLayer
var _fps_label: Label
var _fps_text_left := 0.0
var _frame_ms := 0.0
var _last_frame_usec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_frame_usec = Time.get_ticks_usec()
	_make_fps_counter()
	_load_config()
	get_tree().node_added.connect(_apply_to)
	_apply()


func _process(_delta: float) -> void:
	if InputMap.has_action(TOGGLE_FPS_ACTION) and Input.is_action_just_pressed(TOGGLE_FPS_ACTION):
		set_show_fps(not show_fps)
	# Real time between frames, smoothed over about ten frames.
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_frame_usec) / 1000.0
	_last_frame_usec = now
	_frame_ms = lerpf(_frame_ms, frame_ms, 0.1)
	if not show_fps:
		return
	_fps_text_left -= frame_ms / 1000.0
	if _fps_text_left <= 0.0:
		_fps_text_left = FPS_TEXT_INTERVAL
		_fps_label.text = "%d fps  %.1f ms" % [Engine.get_frames_per_second(), _frame_ms]


## The default preset for a GPU of [param adapter_type] (a [enum RenderingDevice.DeviceType]):
## an integrated GPU starts without reflections.
static func default_preset_for(adapter_type: int) -> StringName:
	return MEDIUM if adapter_type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU else HIGH


## The choice of [param setting] equal to [param value], or null when it has none. Numbers compare
## as numbers and names as text, so a value read back from JSON matches.
static func find_choice(setting: StringName, value: Variant) -> Variant:
	if not SETTINGS.has(setting):
		return null
	for choice: Array in SETTINGS[setting]["choices"]:
		var candidate: Variant = choice[0]
		if typeof(candidate) == TYPE_INT and typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			if is_equal_approx(float(candidate), float(value)):
				return candidate
		elif typeof(candidate) == TYPE_STRING_NAME and typeof(value) in [TYPE_STRING, TYPE_STRING_NAME]:
			if candidate == StringName(value):
				return candidate
	return null


## This computer's default preset (see [method default_preset_for]).
func get_default_preset() -> StringName:
	return default_preset_for(RenderingServer.get_video_adapter_type())


## The preset the settings match, or [constant CUSTOM].
func get_preset() -> StringName:
	for preset: StringName in PRESETS:
		if _matches(PRESET_VALUES[preset]):
			return preset
	return CUSTOM


## Sets every setting to [param preset]'s, applies and saves them.
func set_preset(preset: StringName) -> void:
	if not PRESET_VALUES.has(preset):
		push_warning("Graphics: there's no preset '%s'." % preset)
		return
	_values = PRESET_VALUES[preset].duplicate()
	_changed()


func get_setting(setting: StringName) -> Variant:
	return _values.get(setting)


## Sets [param setting] to [param value] (one of its choices), applies and saves it.
func set_setting(setting: StringName, value: Variant) -> void:
	var choice: Variant = find_choice(setting, value)
	if choice == null:
		push_warning("Graphics: '%s' isn't a choice for the setting '%s'." % [value, setting])
		return
	_values[setting] = choice
	_changed()


func set_show_fps(on: bool) -> void:
	show_fps = on
	_fps_layer.visible = on
	_fps_text_left = 0.0
	_save_config()
	settings_changed.emit()


## Saves to and loads from [param path] from now on: the settings are what [param path] holds
## (the default preset's where it holds none) and are applied at once. Tests use it to work on a
## file of their own.
func set_config_path(path: String) -> void:
	config_path = path
	_load_config()
	_apply()
	settings_changed.emit()


func _changed() -> void:
	_apply()
	_save_config()
	settings_changed.emit()


func _matches(values: Dictionary) -> bool:
	for setting: StringName in SETTINGS:
		if _values.get(setting) != values[setting]:
			return false
	return true


# ==============================================================================
# APPLYING
# ==============================================================================

func _apply() -> void:
	_apply_screen()
	for node in get_tree().root.find_children("*", "", true, false):
		# Applying can free nodes further along the list (a canopy rebuilds its shells).
		if is_instance_valid(node):
			_apply_to(node)
	_fps_layer.visible = show_fps


## The settings for the whole screen: 3D resolution, anti-aliasing, the shadow map, the frame limit.
func _apply_screen() -> void:
	var root := get_tree().root
	var scale := float(_values[RESOLUTION]) / 100.0
	# FSR 1 upscales with sharpening; the menus and HUD always draw at full resolution.
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = scale
	var aa: StringName = _values[ANTI_ALIASING]
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == &"fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	root.msaa_3d = Viewport.MSAA_2X if aa == &"msaa_2x" else Viewport.MSAA_DISABLED

	var sixteen_bits: bool = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits", true)
	if _values[SHADOWS] == &"low":
		RenderingServer.directional_shadow_atlas_set_size(LOW_SHADOW_ATLAS, sixteen_bits)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	else:
		RenderingServer.directional_shadow_atlas_set_size(
				ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096), sixteen_bits)
		RenderingServer.directional_soft_shadow_filter_set_quality(
				ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", RenderingServer.SHADOW_QUALITY_SOFT_LOW))

	# A cap keeps VSync on, so the picture doesn't tear; Unlimited turns both off.
	var vsync := DisplayServer.VSYNC_ENABLED
	match _values[FRAME_LIMIT]:
		&"fps_30":
			Engine.max_fps = 30
		&"fps_60":
			Engine.max_fps = 60
		&"unlimited":
			Engine.max_fps = 0
			vsync = DisplayServer.VSYNC_DISABLED
		_:
			Engine.max_fps = 0
	if DisplayServer.window_get_vsync_mode() != vsync:
		DisplayServer.window_set_vsync_mode(vsync)


## Applies the settings to [param node] if they concern it. Runs for every node entering the tree.
func _apply_to(node: Node) -> void:
	if node is DirectionalLight3D:
		_apply_light(node)
	elif node is PlanarReflection:
		_apply_reflection(node)
	elif node is SkyCanopy:
		_apply_canopy(node)


func _apply_light(light: DirectionalLight3D) -> void:
	var own := _original(light, ["shadow_enabled", "directional_shadow_mode"])
	light.shadow_enabled = own["shadow_enabled"] and _values[SHADOWS] != &"off"
	var mode: int = own["directional_shadow_mode"]
	if _values[SHADOWS] == &"low":
		mode = mini(mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	light.directional_shadow_mode = mode


func _apply_reflection(reflection: PlanarReflection) -> void:
	var own := _original(reflection, ["enabled", "resolution_scale"])
	reflection.enabled = own["enabled"] and _values[REFLECTIONS] != &"off"
	var scale: float = own["resolution_scale"]
	reflection.resolution_scale = scale * LOW_REFLECTION_SCALE if _values[REFLECTIONS] == &"low" else scale


func _apply_canopy(canopy: SkyCanopy) -> void:
	var own := _original(canopy, ["layer_count"])
	var layers: int = own["layer_count"]
	if _values[SKY_CANOPY] == &"simple":
		layers = mini(layers, SIMPLE_CANOPY_LAYERS)
	# Setting it rebuilds the canopy, so only when it changes.
	if canopy.layer_count != layers:
		canopy.layer_count = layers


## [param node]'s own values of [param properties], as they were the first time it was seen here.
func _original(node: Node, properties: Array) -> Dictionary:
	if not node.has_meta(ORIGINAL_META):
		var values := {}
		for property: String in properties:
			values[property] = node.get(property)
		node.set_meta(ORIGINAL_META, values)
	return node.get_meta(ORIGINAL_META)


# ==============================================================================
# FRAME-RATE COUNTER
# ==============================================================================

## A label in the top right corner, over everything.
func _make_fps_counter() -> void:
	_fps_layer = CanvasLayer.new()
	_fps_layer.name = "FpsCounter"
	_fps_layer.layer = 128
	_fps_layer.visible = false
	add_child(_fps_layer)
	_fps_label = Label.new()
	_fps_label.name = "Label"
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_font_size_override(&"font_size", 20)
	_fps_label.add_theme_constant_override(&"outline_size", 6)
	_fps_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_fps_layer.add_child(_fps_label)
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_label.offset_left = -260.0
	_fps_label.offset_right = -16.0
	_fps_label.offset_top = 10.0


# ==============================================================================
# SAVING
# ==============================================================================

## Starts from the default preset, then takes every valid value the config file holds. A value
## the file holds that isn't a choice is skipped (with a warning); the rest still load.
func _load_config() -> void:
	_values = PRESET_VALUES[get_default_preset()].duplicate()
	show_fps = false
	if not FileAccess.file_exists(config_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(config_path)) != OK or not json.data is Dictionary:
		push_warning("Graphics: %s isn't valid (%s); using the default settings." % [config_path, json.get_error_message()])
		return
	var data: Dictionary = json.data
	var saved = data.get("settings", {})
	if saved is Dictionary:
		for key in saved:
			var setting := StringName(str(key))
			var choice: Variant = find_choice(setting, saved[key])
			if choice == null:
				push_warning("Graphics: %s has '%s' for the setting '%s', which isn't a choice; using the default." % [config_path, saved[key], key])
				continue
			_values[setting] = choice
	show_fps = data.get("show_fps", false) == true


func _save_config() -> void:
	var settings := {}
	for setting: StringName in _values:
		var value: Variant = _values[setting]
		settings[String(setting)] = String(value) if value is StringName else value
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		push_error("Graphics: can't write %s (%s)." % [config_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({"settings": settings, "show_fps": show_fps}, "\t"))
