extends Node

@export var camera: Camera2D = get_parent()
@export var base_speed: float = 600.0

var is_dragging := false
var top_bar_height = 26


func _process(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() == null && !GameState.decision_menu_open:
		camera.position += Input.get_vector("move_left", "move_right", "move_up", "move_down") * (base_speed / camera.zoom.x) * delta
	_clamp_vertical()


# Keeps the map filling the window vertically (x wraps around in World.gd instead)
func _clamp_vertical() -> void:
	if MapManager.MAP_HEIGHT <= 0:
		return
	var view_height: float = camera.get_viewport_rect().size.y / camera.zoom.y
	var min_y: float = -top_bar_height / camera.zoom.y
	var max_y: float = MapManager.MAP_HEIGHT - view_height
	if max_y < min_y:
		# Window is taller than the map at this zoom, so just center it
		camera.position.y = (MapManager.MAP_HEIGHT - view_height) * 0.5
	else:
		camera.position.y = clampf(camera.position.y, min_y, max_y)


func _is_mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton && event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			if !Console.is_visible() && !_is_mouse_over_ui():
				is_dragging = true
				get_viewport().set_input_as_handled()
		else:
			is_dragging = false

	if event is InputEventMouseMotion && is_dragging:
		camera.position -= event.relative / camera.zoom.x
		return

	if Console.is_visible() || _is_mouse_over_ui():
		return

	if event is InputEventMouseButton && event.is_pressed():
		var zoom_dir = 0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_dir = 1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_dir = -1

		if zoom_dir != 0:
			_perform_zoom(zoom_dir)


func _perform_zoom(direction: int) -> void:
	var mouse_pos_before := camera.get_global_mouse_position()

	camera.zoom = (camera.zoom + Vector2.ONE * direction).clamp(
		Vector2.ONE,
		Vector2.ONE * 12 
	)

	camera.position += mouse_pos_before - camera.get_global_mouse_position()
