class_name LaunchStation
extends Node

## One launch button or launch station (Ship-Controls Design Doc §5.3). It fires through the ship's
## shared [LaunchObjectComponent] and keeps its own cooldown. With previous / next actions it also
## keeps a selected object; without them it launches random objects.

## Names this station in [signal EventBus.launch_selection_changed].
@export var station_id: StringName = &"pilot"
@export var launcher: LaunchObjectComponent

@export_group("Input")
@export var fire_action: StringName = &"ship_launch"
## Leave both selection actions empty for a button that launches random objects.
@export var prev_action: StringName = &""
@export var next_action: StringName = &""

@export_group("Timing")
@export var cooldown_time: float = 0.5

## Index of the selected object in the launcher's [member LaunchObjectComponent.projectile_scenes].
var selected_index: int = 0

var _cooldown_timer: float = 0.0


func _ready() -> void:
	if not launcher:
		push_error("LaunchStation '%s': no launcher assigned." % station_id)
	for action: StringName in [fire_action, prev_action, next_action]:
		if action != &"" and not InputMap.has_action(action):
			push_error("LaunchStation '%s': input action '%s' does not exist." % [station_id, action])
	if has_selection():
		_emit_selection.call_deferred()


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if not launcher:
		return

	if has_selection():
		if _is_just_pressed(prev_action):
			_step_selection(-1)
		if _is_just_pressed(next_action):
			_step_selection(1)

	if _is_just_pressed(fire_action) and _cooldown_timer <= 0.0:
		launcher.launch_object(get_selected_scene())
		_cooldown_timer = cooldown_time


## True when this station chooses its object, false when it launches random objects.
func has_selection() -> bool:
	return prev_action != &"" or next_action != &""


## The selected object's scene, or null when this station launches random objects.
func get_selected_scene() -> PackedScene:
	if not has_selection() or not launcher:
		return null
	var count := launcher.get_projectile_count()
	if count == 0:
		return null
	selected_index = wrapi(selected_index, 0, count)
	return launcher.projectile_scenes[selected_index]


func _step_selection(step: int) -> void:
	var count := launcher.get_projectile_count()
	if count == 0:
		return
	selected_index = wrapi(selected_index + step, 0, count)
	_emit_selection()


func _emit_selection() -> void:
	EventBus.launch_selection_changed.emit(station_id, get_selected_scene())


func _is_just_pressed(action: StringName) -> bool:
	return action != &"" and InputMap.has_action(action) and Input.is_action_just_pressed(action)
