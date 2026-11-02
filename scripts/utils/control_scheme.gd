## Switches the pilot between the two control schemes under test (Ship-Controls Design Doc §3.3).
## Both schemes use the same input actions. A scheme only decides which controls drive them, by
## swapping the input events of the thrust actions with those of the altitude actions.
class_name ControlScheme
extends RefCounted

enum Scheme {
	## Joystick forward / back moves the ship; the two buttons rise and sink. The project default.
	STICK_DRIVES,
	## Joystick up / down raises and lowers the ship; the two buttons move it forward and back.
	STICK_LIFTS,
}

## Each thrust or altitude action, and the action whose controls it takes in [constant Scheme.STICK_LIFTS].
const _SWAPS := {
	&"ship_forward": &"ship_rise",
	&"ship_reverse": &"ship_sink",
	&"ship_rise": &"ship_forward",
	&"ship_sink": &"ship_reverse",
}


## Rebinds the thrust and altitude actions for [param scheme]. The input map is global, so the
## choice holds across scene changes until it is changed again or the game restarts.
static func apply(scheme: Scheme) -> void:
	for action: StringName in _SWAPS:
		var source: StringName = action if scheme == Scheme.STICK_DRIVES else _SWAPS[action]
		InputMap.action_erase_events(action)
		for event: InputEvent in _project_events(source):
			InputMap.action_add_event(action, event)
		Input.action_release(action)


## The scheme the input map is set to now.
static func get_current() -> Scheme:
	for event: InputEvent in _project_events(&"ship_rise"):
		if InputMap.action_has_event(&"ship_forward", event):
			return Scheme.STICK_LIFTS
	return Scheme.STICK_DRIVES


## The events [param action] has in the project settings (Project Settings → Input Map), which
## always hold the default scheme.
static func _project_events(action: StringName) -> Array:
	var setting: Dictionary = ProjectSettings.get_setting("input/%s" % action, {})
	return setting.get("events", [])
