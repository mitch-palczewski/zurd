extends Node

## Gives each connected controller a [ControllerProfile] and binds that profile's buttons and axes to
## that controller only (Ship-Controls Design Doc §6.3), so the 8BitDo and the arcade kit can be
## connected at once with different layouts. Keyboard and mouse bindings stay in Project Settings.[br]
## A controller gets the profile last chosen for it (remembered by its GUID), else a profile that lists
## its name, else the standard gamepad. Choices and learned profiles are saved in [member config_path].

## Fired when a controller connects or disconnects, or a controller's profile or bindings change.
signal devices_changed

const CONFIG_PATH := "user://controller_config.json"
## The profile choice for a controller the game ignores.
const OFF := &"off"

## Where choices and learned profiles are saved: [constant CONFIG_PATH]. The test runner points it at a
## temporary file before this node is ready, so a test run never reads or writes the real one.
var config_path: String = CONFIG_PATH

## Every profile by id, in menu order.
var profiles: Dictionary[StringName, ControllerProfile] = {}

## Connected controllers: device id → {"name": String, "guid": String, "profile": StringName}.
var _devices: Dictionary[int, Dictionary] = {}
## Remembered choices: controller key ([method _key_for]) → profile id or [constant OFF].
var _assignments: Dictionary[String, StringName] = {}
## Profiles whose bindings were learned on this machine, so they're saved over the built-in ones.
var _learned: Dictionary[StringName, bool] = {}


func _ready() -> void:
	_reset_profiles()
	_load_config()
	_remove_project_joypad_events()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for device in Input.get_connected_joypads():
		connect_device(device, Input.get_joy_name(device), Input.get_joy_guid(device))


## The connected controllers' device ids, in the order they connected.
func get_devices() -> Array[int]:
	var devices: Array[int] = []
	devices.assign(_devices.keys())
	return devices


func get_device_name(device: int) -> String:
	return _devices[device]["name"] if _devices.has(device) else ""


## The profile id [param device] uses, or [constant OFF].
func get_profile_id(device: int) -> StringName:
	return _devices[device]["profile"] if _devices.has(device) else OFF


## Gives [param device] the profile [param profile_id] (or [constant OFF]), remembers the choice for
## that controller, and binds it.
func set_profile(device: int, profile_id: StringName) -> void:
	if not _devices.has(device) or not (profile_id == OFF or profiles.has(profile_id)):
		push_warning("Controllers: can't give device %d the profile '%s'." % [device, profile_id])
		return
	_devices[device]["profile"] = profile_id
	_assignments[_key_for(_devices[device])] = profile_id
	_save_config()
	_bind(device)
	devices_changed.emit()


## Replaces the bindings of [param profile_id] with learned ones, adds [param device]'s controller name
## to the profile so that controller is recognised, and gives the controller the profile.
func save_learned_profile(profile_id: StringName, bindings: Dictionary[StringName, Array], device: int) -> void:
	var profile: ControllerProfile = profiles.get(profile_id)
	if profile == null:
		push_warning("Controllers: no profile '%s' to save." % profile_id)
		return
	profile.bindings = bindings.duplicate(true)
	_learned[profile_id] = true
	if _devices.has(device):
		var joy_name: String = _devices[device]["name"]
		if not joy_name.is_empty() and joy_name not in profile.device_names:
			profile.device_names.append(joy_name)
		_devices[device]["profile"] = profile_id
		_assignments[_key_for(_devices[device])] = profile_id
	_save_config()
	_bind_all()
	devices_changed.emit()


## Puts [param profile_id] back to its built-in bindings. Controllers keep their profile choices.
func reset_profile(profile_id: StringName) -> void:
	for profile in ControllerProfile.create_built_in():
		if profile.id == profile_id:
			profiles[profile_id] = profile
	_learned.erase(profile_id)
	_save_config()
	_bind_all()
	devices_changed.emit()


## Starts handling [param device], a controller called [param joy_name] with [param guid]. Called when a
## controller connects; tests call it with made-up controllers.
func connect_device(device: int, joy_name: String, guid: String) -> void:
	var info := {"name": joy_name, "guid": guid}
	info["profile"] = _choose_profile(info)
	_devices[device] = info
	_bind(device)
	devices_changed.emit()


func disconnect_device(device: int) -> void:
	_unbind(device)
	_devices.erase(device)
	devices_changed.emit()


## Saves to and loads from [param path] from now on. Starts over from the built-in profiles and what
## [param path] holds, and gives the connected controllers their remembered (or default) profiles.
## Tests use it to work on a file of their own.
func set_config_path(path: String) -> void:
	config_path = path
	_assignments.clear()
	_learned.clear()
	_reset_profiles()
	_load_config()
	for device in _devices:
		_devices[device]["profile"] = _choose_profile(_devices[device])
	_bind_all()
	devices_changed.emit()


func _reset_profiles() -> void:
	profiles.clear()
	for profile in ControllerProfile.create_built_in():
		profiles[profile.id] = profile


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		connect_device(device, Input.get_joy_name(device), Input.get_joy_guid(device))
	elif _devices.has(device):
		disconnect_device(device)


func _choose_profile(info: Dictionary) -> StringName:
	var remembered: StringName = _assignments.get(_key_for(info), &"")
	if remembered == OFF or profiles.has(remembered):
		return remembered
	for profile in profiles.values():
		if info["name"] in profile.device_names:
			return profile.id
	return ControllerProfile.STANDARD_GAMEPAD


## Choices are remembered per controller model (GUID), or per name for a controller without a GUID.
func _key_for(info: Dictionary) -> String:
	return info["guid"] if not String(info["guid"]).is_empty() else "name:%s" % info["name"]


func _bind_all() -> void:
	for device in _devices:
		_bind(device)


## Replaces [param device]'s events with its profile's.
func _bind(device: int) -> void:
	_unbind(device)
	var profile: ControllerProfile = profiles.get(_devices[device]["profile"])
	if profile == null:
		return
	for action in profile.bindings:
		for binding: Dictionary in profile.bindings[action]:
			InputMap.action_add_event(action,ControllerProfile.binding_to_event(binding, device))


func _unbind(device: int) -> void:
	for action in ControllerProfile.ACTIONS:
		for event in InputMap.action_get_events(action):
			if _is_joypad(event) and event.device == device:
				InputMap.action_erase_event(action, event)
				Input.action_release(action)


## Controller events in Project Settings would bypass the profiles: they match every controller, or
## whichever one gets a given device number. Profiles own all controller bindings, so any found there
## at startup are dropped.
func _remove_project_joypad_events() -> void:
	for action in ControllerProfile.ACTIONS:
		if not InputMap.has_action(action):
			push_error("Controllers: input action '%s' does not exist." % action)
			continue
		for event in InputMap.action_get_events(action):
			if _is_joypad(event):
				InputMap.action_erase_event(action, event)
				push_warning(("Controllers: '%s' has a controller binding in Project Settings. It's ignored; "
						+ "controllers are bound through their profiles (main menu → Controller setup).") % action)


func _is_joypad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func _load_config() -> void:
	if not FileAccess.file_exists(config_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(config_path)) != OK or not json.data is Dictionary:
		push_warning("Controllers: %s isn't valid (%s); using the built-in profiles." % [config_path, json.get_error_message()])
		return
	var data: Dictionary = json.data
	var assignments = data.get("assignments", {})
	if assignments is Dictionary:
		for key in assignments:
			_assignments[String(key)] = StringName(str(assignments[key]))
	var learned = data.get("profiles", {})
	if learned is Dictionary:
		for profile_id in learned:
			var profile: ControllerProfile = profiles.get(StringName(profile_id))
			if profile == null or not learned[profile_id] is Dictionary:
				push_warning("Controllers: %s has an unknown profile '%s'; it's ignored." % [config_path, profile_id])
				continue
			profile.load_dict(learned[profile_id])
			_learned[profile.id] = true


func _save_config() -> void:
	var assignments := {}
	for key in _assignments:
		assignments[key] = String(_assignments[key])
	var learned := {}
	for profile_id in _learned:
		learned[String(profile_id)] = profiles[profile_id].to_dict()
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		push_error("Controllers: can't write %s (%s)." % [config_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({"assignments": assignments, "profiles": learned}, "\t"))
