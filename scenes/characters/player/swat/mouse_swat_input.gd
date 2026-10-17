class_name MouseSwatInput 
extends Node

func _unhandled_input(event: InputEvent) -> void:
    var viewport: Viewport = get_viewport()
    var uv: Vector2 = viewport.get_mouse_position() / viewport.get_visible_rect().size
    if event is InputEventMouseMotion:
        EventBus.pointer_moved.emit(uv)
    elif event.is_action_pressed(&"ship_swat"):
        EventBus.swat_requested.emit(uv)