extends "res://tests/test_case.gd"

## SceneChanger's async loading: a load that fails closes the loading screen and says so
## (load_failed), and a real load switches scene.

const MENU_PATH := "res://scenes/ui/menus/main_menu.tscn"
## A file that exists but isn't a scene.
const NOT_A_SCENE := "res://assets/shaders/sculpture_mass.gdshader"
const MISSING := "res://tests/no_such_scene.tscn"


func after_each() -> void:
	if get_tree().current_scene:
		get_tree().unload_current_scene()


func test_missing_scene_fails_without_a_loading_screen() -> void:
	var failures := watch(SceneChanger.load_failed)
	allow_error("does not exist")
	SceneChanger.change_scene_async(MISSING)
	check_equal(failures.size(), 1, "load_failed fires")
	check_equal(failures[0][0], MISSING, "with the path that failed")
	await wait_frames(2)
	check(_loading_screens().is_empty(), "no loading screen is left on screen")


func test_file_that_isnt_a_scene_fails_and_closes_the_loading_screen() -> void:
	var failures := watch(SceneChanger.load_failed)
	var shown: Array[bool] = []
	listen(get_tree().root.child_entered_tree, func(node: Node) -> void:
		if node is LoadingScreen:
			shown.append(true))
	allow_error("not a valid PackedScene")
	SceneChanger.change_scene_async(NOT_A_SCENE)
	check(await wait_until(func() -> bool: return not failures.is_empty(), 5.0), "load_failed fires")
	check(not shown.is_empty(), "the loading screen showed while loading")
	await wait_frames(2)
	check(_loading_screens().is_empty(), "the loading screen closes")
	check(get_tree().current_scene == null, "no scene was switched to")


func test_scene_loads_and_switches() -> void:
	var completed := watch(SceneChanger.load_completed)
	SceneChanger.change_scene_async(MENU_PATH)
	var switched := await wait_until(func() -> bool: return get_tree().current_scene != null, 10.0)
	if not check(switched, "the scene loads and becomes the current scene"):
		return
	check_equal(get_tree().current_scene.scene_file_path, MENU_PATH, "it's the requested scene")
	check_equal(completed.size(), 1, "load_completed fires once")
	await wait_seconds(LoadingScreen.MIN_SHOW_TIME + 0.2)
	check(_loading_screens().is_empty(), "the loading screen closes after its minimum time")


func _loading_screens() -> Array[Node]:
	var screens: Array[Node] = []
	for node in get_tree().root.get_children():
		if node is LoadingScreen and not node.is_queued_for_deletion():
			screens.append(node)
	return screens
