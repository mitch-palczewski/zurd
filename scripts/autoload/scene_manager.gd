extends Node


## Emitted throughout the loading process to update progress UI
signal load_progress_updated(progress: float)
## Emitted when the requested scene finished loading on the background thread
signal load_completed

var _target_scene_path: String = ""
var _is_loading: bool = false 
var _progress_array: Array = []


func _process(_delta: float) -> void:
	if not _is_loading:
		return 
	
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(_target_scene_path, _progress_array)
	
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var progress: float = _progress_array[0] if _progress_array.size() > 0 else 0.0
			load_progress_updated.emit(progress)
		ResourceLoader.THREAD_LOAD_LOADED:
			_is_loading = false
			load_progress_updated.emit(1.0)
			load_completed.emit()
			_switch_to_loaded_scene()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_is_loading = false
			push_error("SceneManager: Failed to load scene asynchronously at path: " + _target_scene_path)


func _switch_to_loaded_scene() -> void:
	var new_packed_scene: PackedScene = ResourceLoader.load_threaded_get(_target_scene_path) as PackedScene
	
	if new_packed_scene:
		get_tree().change_scene_to_packed.call_deferred(new_packed_scene)
	else:
		push_error("SceneManager: Loaded resource at " + _target_scene_path + " is not a valid PackedScene.")


## Changes the active scene using threads. [br] [br]
## If [member use_sub_threads] is [code]true[/code], multiple threads will be used to load the resource, which makes loading faster, 
## but may affect the main thread (and thus cause game slowdowns).
func change_scene_async(target_path: String, use_sub_threads: bool = false) -> void:
	if _is_loading:
		push_warning("SceneManager: Already loading a scene. Request Ignored.")
		return
	
	if not ResourceLoader.exists(target_path):
		push_error("SceneManager: Target scene path does not exist: " + target_path)
		return 
	
	_target_scene_path = target_path
	_is_loading = true
	_progress_array.clear()
	
	if LoadingScreen: 
		LoadingScreen.show_screen()
	
	var error: Error = ResourceLoader.load_threaded_request(target_path, "", use_sub_threads)
	if error != OK:
		_is_loading = false
		push_error("SceneManager: ResourceLoader failed to initialize background thread.")


## Change the active scene syncronously. Ideal for changing to lightweight scenes. For heavier scenes use [method change_scene_async]
func change_scene(target_path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(target_path)
