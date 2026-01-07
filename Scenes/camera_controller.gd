extends Node

@onready var camera: Camera2D = get_parent().get_node("Camera2D")

@export_group("Movement")
@export var base_speed: float = 600.0

@export_group("Zoom Settings")
@export var zoom_factor: float = 0.1  # 10% per scroll
@export var min_zoom: float = 0.3
@export var max_zoom: float = 9.0


var is_dragging := false
var is_paused := false


func _process(delta: float) -> void:
	if GameState.decision_tree_open: return
	_handle_keyboard_movement(delta)

func _input(event: InputEvent) -> void:
	if GameState.decision_tree_open: return
	
	if event.is_action_pressed("pause_game"):
		is_paused = not is_paused
		MainClock.set_process(is_paused)
		MainClock.pause(is_paused)


	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		is_dragging = event.pressed
		get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and is_dragging:
		camera.position -= event.relative / camera.zoom.x

	if event is InputEventMouseButton and event.is_pressed():
		var zoom_dir = 0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_dir = 1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_dir = -1
		
		if zoom_dir != 0:
			_perform_zoom(zoom_dir)

func _handle_keyboard_movement(delta: float) -> void:
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	camera.position += input_dir * (base_speed / camera.zoom.x) * delta

func _perform_zoom(direction: int) -> void:
	var mouse_pos_before := camera.get_global_mouse_position()

	var zoom_multiplier := 1.0 + zoom_factor * direction
	var new_zoom := camera.zoom.x * zoom_multiplier
	new_zoom = clamp(new_zoom, min_zoom, max_zoom)

	camera.zoom = Vector2.ONE * new_zoom

	var mouse_pos_after := camera.get_global_mouse_position()
	camera.position += mouse_pos_before - mouse_pos_after
