extends Control
@export_file("*.tscn") var initial_scene_path: String = "res://scenes/ui/menus/main_menu/main_menu.tscn"

func _ready() -> void:
	# TODO game boot initialization logic here. 
	# Could be team logo or intro video. 
	
	if initial_scene_path.is_empty():
		push_error("Boot: No initial_scene_path specified in Inspector")
		return
	
	SceneManager.change_scene(initial_scene_path)
