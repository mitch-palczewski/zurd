extends "res://tests/test_case.gd"

## The main menu: its controls label follows the live input map, scene entries that point at a
## missing scene are skipped, the Controllers section sets profiles, and a failed load gives the
## buttons back.

const MENU_PATH := "res://scenes/ui/menus/main_menu.tscn"
const NOT_A_SCENE := "res://assets/shaders/sculpture_mass.gdshader"
const PAD := 73

## Input map entries a test changed: action -> its events before.
var _saved_events: Dictionary = {}


func after_each() -> void:
	for action: StringName in _saved_events:
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved_events[action]:
			InputMap.action_add_event(action, event)
	_saved_events.clear()
	if Controllers.get_devices().has(PAD):
		Controllers.disconnect_device(PAD)
	for child in get_children():
		child.free()


func test_controls_label_follows_the_input_map() -> void:
	_replace_events(&"ship_launch", [_key(KEY_P)])
	_replace_events(&"ship_swat", [])
	var menu := await _make_menu()
	var text: String = (menu.get(&"controls_label") as Label).text
	check(text.contains("P - launch random object"), "the label shows the key bound right now")
	check(text.contains("not bound - swat zurd"), "and says when an action has no key or mouse button")


func test_entries_with_a_missing_scene_are_skipped() -> void:
	var entries: Array[SceneEntry] = [_scene_entry("Missing scene", "res://tests/no_such_scene.tscn"), _scene_entry("Real scene", MENU_PATH)]
	var menu := await _make_menu(entries)
	var labels := _button_labels(menu)
	check(labels.has("Real scene"), "an entry whose scene exists gets a button")
	check(not labels.has("Missing scene"), "an entry whose scene is missing is skipped")


func test_controller_list_sets_profiles() -> void:
	var menu := await _make_menu()
	Controllers.connect_device(PAD, "Menu Test Pad", "menu-test-guid")
	await wait_frames(1)
	var option := _find_profile_option(menu, "Menu Test Pad")
	if not check(option != null, "a connected controller gets a row with a profile dropdown"):
		return
	var arcade_name := Controllers.profiles[ControllerProfile.ARCADE_KIT].display_name
	var arcade_index := -1
	for i in option.item_count:
		if option.get_item_text(i) == arcade_name:
			arcade_index = i
	check_equal(option.get_item_text(option.selected), Controllers.profiles[ControllerProfile.STANDARD_GAMEPAD].display_name, "it shows the controller's profile")
	check(arcade_index >= 0, "every profile is offered")
	option.select(arcade_index)
	option.item_selected.emit(arcade_index)
	check_equal(Controllers.get_profile_id(PAD), ControllerProfile.ARCADE_KIT, "picking a profile gives it to the controller")


func test_failed_load_gives_the_buttons_back() -> void:
	var entries: Array[SceneEntry] = [_scene_entry("Not a scene", NOT_A_SCENE)]
	var menu := await _make_menu(entries)
	var button := _find_button(menu, "Not a scene")
	if not check(button != null, "the entry has a button"):
		return
	allow_error("not a valid PackedScene")
	button.pressed.emit()
	check(button.disabled, "the buttons are disabled while a scene loads")
	var enabled := await wait_until(func() -> bool: return not button.disabled, 5.0)
	check(enabled, "after the load fails, the buttons work again")


## A main menu added under this test. [param entries] replaces its scene list when given.
func _make_menu(entries: Array[SceneEntry] = []) -> Control:
	var menu := (load(MENU_PATH) as PackedScene).instantiate() as Control
	if not entries.is_empty():
		menu.set(&"scenes", entries)
	add_child(menu)
	await wait_frames(1)
	return menu


func _replace_events(action: StringName, events: Array) -> void:
	if not _saved_events.has(action):
		_saved_events[action] = InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


func _scene_entry(label: String, path: String) -> SceneEntry:
	var entry := SceneEntry.new()
	entry.label = label
	entry.path = path
	return entry


func _button_labels(menu: Node) -> Array[String]:
	var labels: Array[String] = []
	for node in menu.find_children("*", "Button", true, false):
		labels.append((node as Button).text)
	return labels


func _find_button(menu: Node, label: String) -> Button:
	for node in menu.find_children("*", "Button", true, false):
		if (node as Button).text == label:
			return node as Button
	return null


func _find_profile_option(menu: Node, controller_name: String) -> OptionButton:
	for row in menu.get(&"controller_list").get_children():
		if row.is_queued_for_deletion() or row.get_child_count() < 2:
			continue
		var name_label := row.get_child(0) as Label
		if name_label and name_label.text == controller_name:
			return row.get_child(1) as OptionButton
	return null
