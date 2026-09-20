class_name LoadingScreen
extends Control

@onready var progress_bar = $MarginContainer/ProgressBar

const MIN_SHOW_TIME: float = 0.5
const SCENE_PATH: String = "uid://e2w44cj8g4pv"
var _start_time: float = 0.0

func _ready() -> void:
	_start_time = Time.get_ticks_msec() / 1000.0
	SceneManager.load_progress_updated.connect(_on_load_progress_updated)
	SceneManager.load_completed.connect(_on_load_completed)


func _on_load_progress_updated(progress: float) -> void:
	progress_bar.value =progress * 100.0


func _on_load_completed() -> void:
	var elapsed = (Time.get_ticks_msec() / 1000.0) - _start_time
	if elapsed < MIN_SHOW_TIME:
		await  get_tree().create_timer(MIN_SHOW_TIME - elapsed).timeout
	queue_free()


## Factory Function: loading and instancing the [LoadingScreen] scene. 
static func show_screen() -> LoadingScreen:
	var packed_scene: PackedScene = load(SCENE_PATH)
	if not packed_scene:
		push_error("LoadingScreen: Could not load scene at UID:" + SCENE_PATH)
		return null
	
	var instance = packed_scene.instantiate() as LoadingScreen
	var main_tree = Engine.get_main_loop() as SceneTree
	
	main_tree.root.add_child.call_deferred(instance)
	return instance
