# MapDebugOverlay.gd (Autoload)
extends Node2D

@export var enabled: bool = false : set = set_enabled
@export var show_centroids: bool = true
@export var show_labels: bool = true

@export var dot_size: float = 1.0          # Size in WORLD units (perfect at any zoom)
@export var dot_color: Color = Color(0, 1, 0, 0.8)
@export var hovered_color: Color = Color(1, 0.8, 0, 1)
@export var selected_color: Color = Color(1, 1, 0, 1)

var map_sprite: Sprite2D
var province_centers: Dictionary = {}
var selected_pid: int = -1
var hovered_pid: int = -1

var camera: Camera2D

var path_to_highlight: Array[int] = []


func highlight_path(path: Array[int]) -> void:
	path_to_highlight = path.duplicate()
	queue_redraw()


func _ready() -> void:
	z_index = 999
	set_process_input(true)
	camera = get_viewport().get_camera_2d()


func _enter_tree() -> void:
	# Auto-find the map sprite (adjust path if needed)
	if get_tree().current_scene:
		map_sprite = get_tree().current_scene.get_node("MapContainer/CultureSprite")
	
	# Make sure this overlay follows the camera perfectly
	if get_viewport().get_camera_2d():
		get_viewport().get_camera_2d().call_deferred("make_current")


func _process(_delta) -> void:
	# Force this Node2D to be a child of the camera's canvas
	# This makes all drawing world-space and zoom-perfect
	if get_parent() != get_viewport():
		get_viewport().add_child(self)
		global_position = Vector2.ZERO


func _draw() -> void:
	if not enabled or not map_sprite or province_centers.is_empty():
		return

	for pid in province_centers:
		var pixel_pos = Vector2(province_centers[pid].x, province_centers[pid].y)
		var world_pos = pixel_pos + map_sprite.position

		draw_circle(world_pos, dot_size * 0.5, Color.GREEN)

	if not path_to_highlight.is_empty():
		for i in range(path_to_highlight.size() - 1):
			var pid1 = path_to_highlight[i]
			var pid2 = path_to_highlight[i + 1]
			var pos1 = Vector2(province_centers.get(pid1, Vector2.ZERO).x, province_centers.get(pid1, Vector2.ZERO).y) + map_sprite.offset # - offset
			var pos2 = Vector2(province_centers.get(pid2, Vector2.ZERO).x, province_centers.get(pid2, Vector2.ZERO).y) + map_sprite.offset # offset
			draw_line(pos1, pos2, Color.RED, 3.0)


func set_centers(centers: Dictionary) -> void:
	province_centers = centers.duplicate()
	queue_redraw()


func select_province(pid: int) -> void:
	selected_pid = pid
	queue_redraw()


func hover_province(pid: int) -> void:
	hovered_pid = pid
	queue_redraw()


func set_enabled(v: bool) -> void:
	enabled = v
	visible = v
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F3:
			enabled = !enabled
			print("MapDebugOverlay: ", "ON" if enabled else "OFF")
		if event.keycode == KEY_F4:
			show_labels = !show_labels
