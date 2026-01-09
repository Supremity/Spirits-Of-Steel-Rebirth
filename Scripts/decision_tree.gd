extends Control
class_name DecisionTree

@export var json_path: String = "res://decisions.json"
@export var button_theme: Theme

@onready var tree_content := $ScrollContainer/TreeContent as Control


func _ready():
	hide()
	load_and_build_tree()


func load_and_build_tree():
	var json_data = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if json_data == null:
		return

	for category in json_data["categories"].keys():
		var nodes = json_data["categories"][category]
		_create_category_label(category, nodes)
		var line = Line2D.new()

		var points = []
		for node_data in nodes:
			var line_point = _create_decision_button(node_data)
			points.append(line_point)
		line.points = points
		tree_content.add_child(line)
		tree_content.move_child(line, 0)


func _create_category_label(category_name: String, nodes: Array):
	if nodes.is_empty():
		return

	var font = load("res://font/Google_Sans/static/GoogleSans-BoldItalic.ttf") as FontFile
	var label := Label.new()
	label.text = category_name.to_upper()
	label.position = Vector2(nodes[0]["pos"][0], nodes[0]["pos"][1] - 40)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_font_override("font", font)

	tree_content.add_child(label)

func _create_decision_button(node_data: Dictionary):
	var btn := Button.new()

	btn.text = node_data["title"]
	btn.position = Vector2(node_data["pos"][0], node_data["pos"][1])
	btn.custom_minimum_size = Vector2(160, 50)

	if button_theme:
		btn.theme = button_theme

	tree_content.add_child(btn)
	
	btn.set_meta("node_data", node_data)

	# if already clicked
	if node_data.get("clicked", false):
		btn.disabled = true
	else:
		btn.pressed.connect(_on_button_pressed.bind(btn))

	return btn.position + btn.custom_minimum_size/2


func _on_button_pressed(btn: Button):
	var node_data: Dictionary = btn.get_meta("node_data")

	if node_data.get("clicked", false):
		return

	if node_data.has("action"):
		_execute_action(node_data["action"])

	node_data["clicked"] = true
	btn.disabled = true


func _execute_action(action: Dictionary):
	match action.get("type", ""):
		"increase_daily_money":
			CountryManager.player_country.daily_money_income += action.get("amount", 0)
			
		"increase_manpower":
			CountryManager.player_country.manpower += action.get("amount", 0)
		
		"increase_daily_pp":
			CountryManager.player_country.daily_pp_gain += action.get("amount", 0)

		"unlock_modifier":
			print(action)
		_:
			push_warning("Unknown action: " + str(action))


func _on_exit_button_button_up() -> void:
	hide()
	GameState.decision_tree_open = false
	
	GameState.current_world.set_process(true)
	GameState.current_world.clock.set_process(true)
	TroopManager.set_process(true)



# Control inside decision tree
@export_group("Zoom Settings")
@export var zoom_step := 0.1
@export var min_zoom := 0.5
@export var max_zoom := 2.5

@export_group("Movement Settings")
@export var pan_speed := 500.0

var is_panning := false

func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)

func _gui_input(event: InputEvent) -> void:

	if event is InputEventMouseButton:
		var is_pan_button = event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]
		if is_pan_button:
			is_panning = event.pressed
		
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			_zoom_at_point(direction, event.position)

	elif event is InputEventMouseMotion and is_panning:
		tree_content.position += event.relative

func _handle_keyboard_pan(delta: float) -> void:
	
	# Project Settings -> Input map
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	

	if input_dir != Vector2.ZERO:
		tree_content.position -= input_dir * pan_speed * delta

func _zoom_at_point(direction: int, mouse_pos: Vector2) -> void:
	var prev_scale := tree_content.scale.x
	var new_scale = clamp(prev_scale + (direction * zoom_step), min_zoom, max_zoom)
	
	if prev_scale == new_scale:
		return

	var pivot = (mouse_pos - tree_content.position) / prev_scale
	tree_content.scale = Vector2.ONE * new_scale
	tree_content.position = mouse_pos - pivot * new_scale
