extends Control

## Records a controller layout (Ship-Controls Design Doc §6.3). Pick a profile, press Learn, press any
## button on the controller to set up, then press each control when asked. Saving replaces the
## profile's bindings, adds the controller's name to it and gives the controller that profile. Outside
## learning, the list lights up each control while it's pressed, to test the layout. Opened from the
## main menu; not part of the game flow.

const MENU_PATH := "uid://68dobhnbf23d" # main_menu.tscn
## How far an axis must move to count as a press, and how far back before it can count again.
const AXIS_PRESS := 0.6
const AXIS_RELEASE := 0.3

## Each control to learn: its action, its name in the list, and the
## prompt that asks for it.
const STEPS := [
	[&"ship_forward", "Joystick forward", "Push the pilot joystick FORWARD."],
	[&"ship_reverse", "Joystick back", "Pull the pilot joystick BACK."],
	[&"ship_turn_left", "Joystick left", "Push the pilot joystick LEFT."],
	[&"ship_turn_right", "Joystick right", "Push the pilot joystick RIGHT."],
	[&"ship_rise", "Up button", "Press the pilot's UP button."],
	[&"ship_sink", "Down button", "Press the pilot's DOWN button."],
	[&"ship_launch", "Pilot launch", "Press the pilot's LAUNCH button."],
	[&"launch_station_prev", "Station previous", "Press the launch station's PREVIOUS button (small, left)."],
	[&"launch_station_fire", "Station launch", "Press the launch station's big LAUNCH button."],
	[&"launch_station_next", "Station next", "Press the launch station's NEXT button (small, right)."],
]

enum State {
	## Showing the profile; pressed controls light up.
	TEST,
	## Waiting for a press that picks the controller to set up.
	PICK_DEVICE,
	## Asking for the control of [member _step].
	LEARN,
	## Every control asked for; waiting for Save.
	DONE,
}

var _state := State.TEST
var _profile_id: StringName
## The controller being set up.
var _device := -1
## Index into [constant STEPS] while learning.
var _step := 0
## Bindings being learned. Starts as the profile's own, so a skipped control keeps what it had.
var _learned: Dictionary[StringName, Array] = {}
## Axes pushed past [constant AXIS_PRESS] that haven't come back below [constant AXIS_RELEASE], by
## Vector2i(device, axis).
var _held_axes: Dictionary[Vector2i, bool] = {}

var _profile_option: OptionButton
var _prompt: Label
## Each action's row: [marker, binding] labels.
var _rows: Dictionary[StringName, Array] = {}
var _learn_button: Button
var _skip_button: Button
var _back_button: Button
var _save_button: Button
var _reset_button: Button


func _ready() -> void:
	_build_ui()
	for profile: ControllerProfile in Controllers.profiles.values():
		_profile_option.add_item(profile.display_name)
		_profile_option.set_item_metadata(_profile_option.item_count - 1, profile.id)
		if profile.id == ControllerProfile.ARCADE_KIT:
			_profile_option.select(_profile_option.item_count - 1)
	_profile_option.item_selected.connect(_on_profile_selected)
	Controllers.devices_changed.connect(_on_devices_changed)
	_on_profile_selected(_profile_option.selected)


func _process(_delta: float) -> void:
	for i in STEPS.size():
		var action: StringName = STEPS[i][0]
		var marker: Label = _rows[action][0]
		if _state == State.TEST:
			marker.text = "●" if Input.is_action_pressed(action) else ""
		else:
			marker.text = "▶" if _state == State.LEARN and i == _step else ""


func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	# Controllers never drive this screen's buttons, so a press can't click one by accident.
	get_viewport().set_input_as_handled()
	if not _is_press(event):
		return
	if _state == State.PICK_DEVICE:
		_device = event.device
		_hold_resting_axes()
		_step = 0
		_set_state(State.LEARN)
	elif _state == State.LEARN and event.device == _device:
		_learn(ControllerProfile.event_to_binding(event))


## True for a button going down, or an axis pushed past [constant AXIS_PRESS]. An axis must come back
## below [constant AXIS_RELEASE] before it counts again, so holding the stick doesn't fill the next
## control too.
func _is_press(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.pressed
	var key := Vector2i(event.device, event.axis)
	if absf(event.axis_value) < AXIS_RELEASE:
		_held_axes.erase(key)
		return false
	if absf(event.axis_value) < AXIS_PRESS or _held_axes.has(key):
		return false
	_held_axes[key] = true
	return true


## Axes that rest away from the middle (an odd trigger, a stick held during the pick) don't count until
## they come back, so they can't fill a control by themselves.
func _hold_resting_axes() -> void:
	for axis in JOY_AXIS_MAX:
		if absf(Input.get_joy_axis(_device, axis)) >= AXIS_RELEASE:
			_held_axes[Vector2i(_device, axis)] = true


func _learn(binding: Dictionary) -> void:
	for i in _step:
		if binding in _learned.get(STEPS[i][0], []):
			_prompt.text = "That's already %s. %s" % [STEPS[i][1].to_lower(), STEPS[_step][2]]
			return
	_learned[STEPS[_step][0]] = [binding]
	_advance()


func _advance() -> void:
	_step += 1
	if _step >= STEPS.size():
		_set_state(State.DONE)
	else:
		_set_state(State.LEARN)


func _set_state(state: State) -> void:
	_state = state
	match state:
		State.TEST:
			_learned = Controllers.profiles[_profile_id].bindings.duplicate(true)
			_prompt.text = "Press Learn to record this profile from a controller. Pressed controls light up below."
		State.PICK_DEVICE:
			_prompt.text = "Press any button on the controller you want to set up."
		State.LEARN:
			var progress := "(%s, control %d of %d)" % [Controllers.get_device_name(_device), _step + 1, STEPS.size()]
			_prompt.text = "%s\n%s" % [STEPS[_step][2], progress]
		State.DONE:
			_prompt.text = "All controls done on %s. Save to keep this layout." % Controllers.get_device_name(_device)
	_learn_button.text = "Learn" if state == State.TEST else "Cancel"
	_skip_button.disabled = state != State.LEARN
	_back_button.disabled = not (state == State.DONE or (state == State.LEARN and _step > 0))
	_save_button.disabled = state != State.DONE
	_reset_button.disabled = state != State.TEST
	_profile_option.disabled = state != State.TEST
	for step in STEPS:
		var described: PackedStringArray = []
		for binding: Dictionary in _learned.get(step[0], []):
			described.append(ControllerProfile.describe(binding))
		_rows[step[0]][1].text = ", ".join(described) if not described.is_empty() else "—"


func _on_profile_selected(index: int) -> void:
	_profile_id = _profile_option.get_item_metadata(index)
	_set_state(State.TEST)


func _on_learn_pressed() -> void:
	_set_state(State.PICK_DEVICE if _state == State.TEST else State.TEST)


func _on_back_pressed() -> void:
	_step = mini(_step, STEPS.size()) - 1
	_set_state(State.LEARN)


func _on_save_pressed() -> void:
	Controllers.save_learned_profile(_profile_id, _learned, _device)
	_set_state(State.TEST)
	_prompt.text = "Saved, and %s now uses it. Pressed controls light up below." % Controllers.get_device_name(_device)


func _on_reset_pressed() -> void:
	Controllers.reset_profile(_profile_id)
	_set_state(State.TEST)


func _on_devices_changed() -> void:
	if _state in [State.LEARN, State.DONE] and _device not in Controllers.get_devices():
		_set_state(State.TEST)
		_prompt.text = "The controller disconnected, so nothing was saved."


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Controller Setup"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)

	var profile_row := HBoxContainer.new()
	var profile_label := Label.new()
	profile_label.text = "Profile"
	profile_row.add_child(profile_label)
	_profile_option = OptionButton.new()
	profile_row.add_child(_profile_option)
	column.add_child(profile_row)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_prompt)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	for step in STEPS:
		var marker := Label.new()
		marker.custom_minimum_size.x = 16
		var step_name := Label.new()
		step_name.text = step[1]
		var binding := Label.new()
		grid.add_child(marker)
		grid.add_child(step_name)
		grid.add_child(binding)
		_rows[step[0]] = [marker, binding]
	column.add_child(grid)

	var buttons := HBoxContainer.new()
	_learn_button = _add_button(buttons, "Learn", _on_learn_pressed)
	_skip_button = _add_button(buttons, "Skip", _advance)
	_back_button = _add_button(buttons, "Back", _on_back_pressed)
	_save_button = _add_button(buttons, "Save", _on_save_pressed)
	_reset_button = _add_button(buttons, "Reset to default", _on_reset_pressed)
	_add_button(buttons, "Back to menu", SceneChanger.change_scene.bind(MENU_PATH))
	column.add_child(buttons)

	var hint := Label.new()
	hint.text = ("Skip keeps a control's current binding. Layouts and choices are saved on this computer "
			+ "(%s). Keyboard and mouse always work." % Controllers.CONFIG_PATH)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)


func _add_button(parent: Container, text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	return button
