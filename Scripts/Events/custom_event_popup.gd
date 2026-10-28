extends Control

@export var content_list: VBoxContainer

signal setup_finished

var data: Dictionary = {}
var manually_positioned = false
var dragging = false
var drag_offset = Vector2.ZERO

func setup(p_data: Dictionary):
	data = p_data
	# Refresh UI
	for child in content_list.get_children():
		child.queue_free()
	
	if data.has("contents") and data["contents"] is Array:
		for element in data["contents"]:
			var count_before = content_list.get_child_count()
			InterpreterManager.get_element(element, content_list, CountryManager.player_country)
			var count_after = content_list.get_child_count()
			
			if count_after > count_before:
				var new_node = content_list.get_child(count_after - 1)
				if new_node is Button:
					new_node.pressed.connect(queue_free)
	
	# Wait one frame for the layout to update, then shrink root to fit
	if not is_inside_tree(): await tree_entered
	await get_tree().process_frame
	size = $PanelContainer.size
	setup_finished.emit()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	$PanelContainer.mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(_on_mouse_entered)


func _on_mouse_entered():
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		queue_free()

func _process(_delta: float) -> void:
	InterpreterManager.refresh_buttons(content_list)

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_offset = get_global_mouse_position() - global_position
				manually_positioned = true
			else:
				dragging = false
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			queue_free()
	
	if event is InputEventMouseMotion and dragging:
		global_position = get_global_mouse_position() - drag_offset
