extends "res://tests/test_case.gd"

## Project-wide consistency: every scene and resource loads, references point where they say, and
## the input actions the code reads exist, with keyboard bindings and no controller bindings in
## Project Settings (controllers are bound through profiles).

const ROOTS: Array[String] = ["res://scenes/", "res://data/"]
const SHIP_PATH := "res://scenes/characters/player/player_ship.tscn"
const MENU_SCRIPT := "res://scenes/ui/menus/main_menu.gd"
## Matches a reference to another file in a .tscn or .tres: its UID and its path.
const EXT_RESOURCE_PATTERN := "\\[ext_resource[^\\]]*uid=\"(uid://[a-z0-9]+)\"[^\\]]*path=\"([^\"]+)\""


func test_every_scene_and_resource_loads() -> void:
	var files := _find_files()
	check(files.size() > 10, "found the project's scenes and resources")
	for path in files:
		var dependencies := _dependency_paths(path)
		if dependencies.any(func(dependency: String) -> bool: return dependency.ends_with(".cs")):
			continue # C# (lidar) scenes need the .NET build.
		var missing := dependencies.filter(func(dependency: String) -> bool: return not ResourceLoader.exists(dependency))
		check(missing.is_empty(), "%s: every file it uses exists (missing: %s)" % [path, missing])
		check(load(path) != null, "%s loads" % path)


func test_references_point_where_they_say() -> void:
	var regex := RegEx.create_from_string(EXT_RESOURCE_PATTERN)
	var checked := 0
	for path in _find_files():
		for found in regex.search_all(FileAccess.get_file_as_string(path)):
			var id := ResourceUID.text_to_id(found.get_string(1))
			# A UID this machine's cache doesn't know yet falls back to the path; that's fine.
			if not ResourceUID.has_id(id):
				continue
			checked += 1
			var target := ResourceUID.get_id_path(id)
			check(target == found.get_string(2), "%s: %s is %s, but the reference says %s (Godot loads the UID's file)" % [path, found.get_string(1), target, found.get_string(2)])
	check(checked > 0, "references were checked")


func test_input_actions_exist() -> void:
	var needed: Array[StringName] = []
	needed.append_array(ControllerProfile.ACTIONS)
	needed.append(&"ship_swat")
	for line: Array in _control_lines():
		for action: StringName in line.slice(1):
			needed.append(action)
	var ship := (load(SHIP_PATH) as PackedScene).instantiate()
	for node in ship.find_children("*", "", true, false):
		if node is LaunchStation:
			for action: StringName in [node.fire_action, node.prev_action, node.next_action]:
				if action != &"":
					needed.append(action)
		elif node is StationActivity:
			needed.append_array(node.actions)
	ship.free()
	for action in needed:
		check(InputMap.has_action(action), "input action %s exists" % action)


func test_project_settings_bind_keys_not_controllers() -> void:
	for line: Array in _control_lines():
		for action: StringName in line.slice(1):
			var events := _project_events(action)
			check(events.any(func(event: InputEvent) -> bool: return event is InputEventKey or event is InputEventMouseButton),
					"%s has a key or mouse button in Project Settings" % action)
	for action in ControllerProfile.ACTIONS:
		var events := _project_events(action)
		check(not events.any(func(event: InputEvent) -> bool: return event is InputEventJoypadButton or event is InputEventJoypadMotion),
				"%s has no controller binding in Project Settings (profiles bind controllers)" % action)


## Every .tscn and .tres under [constant ROOTS].
func _find_files() -> Array[String]:
	var files: Array[String] = []
	for root_dir in ROOTS:
		_collect(root_dir, files)
	files.sort()
	return files


func _collect(dir: String, files: Array[String]) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in ["tscn", "tres"]:
			files.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), files)


## The files [param path] uses, as paths ("uid://...::Type::res://..." entries give their path).
func _dependency_paths(path: String) -> Array[String]:
	var paths: Array[String] = []
	for dependency in ResourceLoader.get_dependencies(path):
		var dependency_path := dependency.get_slice("::", 2) if dependency.contains("::") else dependency
		paths.append(dependency_path if not dependency_path.is_empty() else dependency.get_slice("::", 0))
	return paths


## The main menu's controls label lines: [description, action, ...].
func _control_lines() -> Array:
	return (load(MENU_SCRIPT) as GDScript).get_script_constant_map()["CONTROL_LINES"]


## [param action]'s events as saved in Project Settings (Controllers removes controller events from
## the live input map at startup, so the input map can't tell).
func _project_events(action: StringName) -> Array:
	var setting: Variant = ProjectSettings.get_setting("input/%s" % action, {})
	return setting.get("events", []) if setting is Dictionary else []
