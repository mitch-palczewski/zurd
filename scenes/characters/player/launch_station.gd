class_name LaunchStation
extends Node

## One launch button or launch station (Ship-Controls Design Doc §5.3, Launch-Station Design Doc §3).
## It fires through the ship's shared [LaunchObjectComponent] from its own side and keeps its own
## cooldown. With previous / next actions it also keeps a selected object: the first press shows it
## on the station's [LaunchPreview], later presses step, and Launch fires it until the preview times
## out. Otherwise, and without those actions, it launches random objects.

## Names this station in [signal EventBus.launch_selection_changed].
@export var station_id: StringName = &"pilot"
@export var launcher: LaunchObjectComponent
## Sideways offset of this station's launch point and pedestal from the middle of the ship, matching
## the side the station stands on in the room. Positive is right.
@export var side_offset: float = 0.0
## Shows the selected object. Optional: a station without one still selects, it just shows nothing.
@export var preview: LaunchPreview

@export_group("Input")
@export var fire_action: StringName = &"ship_launch"
## Leave both selection actions empty for a button that launches random objects.
@export var prev_action: StringName = &""
@export var next_action: StringName = &""

@export_group("Timing")
@export var cooldown_time: float = 0.5
## Time after the last select or launch press before the preview hides and the station goes back to
## random objects.
@export var preview_hide_delay: float = 5.0

## Index of the selected object in the launcher's [member LaunchObjectComponent.projectile_scenes].
var selected_index: int = 0
## True while the selected object is shown, so a launch fires it.
var is_showing: bool = false

var _cooldown_timer: float = 0.0
var _hide_timer: float = 0.0


func _ready() -> void:
	if not launcher:
		push_error("LaunchStation '%s': no launcher assigned." % station_id)
	for action: StringName in [fire_action, prev_action, next_action]:
		if action != &"" and not InputMap.has_action(action):
			push_error("LaunchStation '%s': input action '%s' does not exist." % [station_id, action])
	if preview:
		preview.position.x = side_offset


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if not launcher:
		return

	# Presses come before the hide timer, so a press in its last frame keeps the preview.
	if has_selection():
		var prev_pressed := _is_just_pressed(prev_action)
		var next_pressed := _is_just_pressed(next_action)
		if prev_pressed or next_pressed:
			_select(int(next_pressed) - int(prev_pressed))

	if _is_just_pressed(fire_action):
		if is_showing:
			_hide_timer = preview_hide_delay
		if _cooldown_timer <= 0.0:
			launcher.launch_object(get_launch_scene(), side_offset)
			_cooldown_timer = cooldown_time

	if is_showing:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_hide()


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


## The object a launch fires: the shown object, or null (random) while nothing is shown.
func get_launch_scene() -> PackedScene:
	return get_selected_scene() if is_showing else null


## Shows the selected object without stepping when it's hidden, so a guest never skips an object they
## didn't see. When it's already showing, steps by [param step].
func _select(step: int) -> void:
	var count := launcher.get_projectile_count()
	if count == 0:
		return
	if is_showing:
		selected_index = wrapi(selected_index + step, 0, count)
	is_showing = true
	_hide_timer = preview_hide_delay
	var scene := get_selected_scene()
	if preview:
		preview.show_object(scene)
	EventBus.launch_selection_changed.emit(station_id, scene)


func _hide() -> void:
	is_showing = false
	if preview:
		preview.hide_preview()
	EventBus.launch_selection_changed.emit(station_id, null)


func _is_just_pressed(action: StringName) -> bool:
	return action != &"" and InputMap.has_action(action) and Input.is_action_just_pressed(action)
