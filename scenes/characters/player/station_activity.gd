class_name StationActivity
extends Node

## Tracks whether guests are using a station (Ship-Controls Design Doc §5.5). Using any of its
## actions marks it active; no input for [member idle_timeout] seconds marks it empty. Both changes
## fire [signal EventBus.station_activity_changed]. Stations start empty.

## Names this station in [signal EventBus.station_activity_changed].
@export var station_id: StringName = &"pilot"
## Every input action that belongs to this station.
@export var actions: Array[StringName] = []
@export var idle_timeout: float = 30.0

## True while a guest is using the station.
var is_active: bool = false

var _valid_actions: Array[StringName] = []
var _idle_time: float = 0.0


func _ready() -> void:
	for action in actions:
		if InputMap.has_action(action):
			_valid_actions.append(action)
		else:
			push_error("StationActivity '%s': input action '%s' does not exist." % [station_id, action])


func _process(delta: float) -> void:
	if _is_any_action_used():
		_idle_time = 0.0
		if not is_active:
			_set_active(true)
	elif is_active:
		_idle_time += delta
		if _idle_time >= idle_timeout:
			_set_active(false)


func _is_any_action_used() -> bool:
	# Held inputs count too, so a stick held longer than the timeout keeps the station active.
	for action in _valid_actions:
		if Input.is_action_pressed(action) or Input.is_action_just_pressed(action):
			return true
	return false


func _set_active(active: bool) -> void:
	is_active = active
	EventBus.station_activity_changed.emit(station_id, active)
