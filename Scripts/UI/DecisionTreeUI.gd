extends CanvasLayer

# --- CONFIGURATION ---
const MOVE_SPEED = 800.0
const GRID_SIZE = 50.0
const LINE_WIDTH = 4.0
const NODE_SIZE = Vector2(220, 90)
const ZOOM_STEP = 0.1
const MIN_ZOOM = 0.2
const MAX_ZOOM = 3.0

# Colors (No transparency)
const COL_BG = Color(0.05, 0.05, 0.05, 1.0) # Solid Black-Grey
const COL_GRID = Color(0.2, 0.2, 0.2, 1.0) # Visible Grey Grid
const COL_LINE_INACTIVE = Color(0.3, 0.3, 0.3)
const COL_LINE_ACTIVE = Color(0.2, 0.8, 0.2)
const COL_LINE_EXCLUSIVE = Color(0.8, 0.2, 0.2)
const DAMAGED_MAT = preload("res://Materials/damaged.tres")

# --- NODES ---
@onready var tree_canvas: Node2D = $CanvasAnchor/TreeCanvas
@onready var tabs_container: TabBar = $StaticUI/Header/TabsContainer
@export var info_text: RichTextLabel
@export var info_tab: TabContainer
@export var edit_label: TextEdit
@export var edit_desc: TextEdit
@export var edit_days: SpinBox
@export var edit_ppcost: SpinBox
# @onready var tooltip_panel := $StaticUI/TooltipPanel/TooltipLabel
@export var close_button: Button
@export var edit_button: Button
@export var editing_buttons: HBoxContainer
@export var edit_function: CheckBox
@export var save_button: Button
@export var add_decision: Button
@export var add_req: Button
@export var add_finished: Button
@export var editor_tab: TabContainer
@export var reqs_block: VBoxContainer
@export var finished_block: VBoxContainer
@onready var expression_scene = load("res://Scenes/Expression.tscn")


var current_category: String = "Economy"
var node_buttons: Dictionary = {}
var connection_lines: Array = []
var current_zoom: float = 1.0
var edit_mode: bool = false
var dragging_node: Button = null
var connecting_id: String = ""
var drag_offset: Vector2 = Vector2.ZERO
var selected_decision: Dictionary = {}
var selected_node_btn: Button = null
var _is_loading_expr: bool = false


func _ready():
	DecisionManager.ui_overlay = self
	edit_button.visible = DecisionManager.debug
	_on_edit_mode_toggled(false)
	tabs_container.tab_changed.connect(_on_tab_changed)


func _process(delta: float) -> void:
	if visible:
		var input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input != Vector2.ZERO:
			tree_canvas.position -= input * MOVE_SPEED * delta / current_zoom
			tree_canvas.queue_redraw()

	# print(edit_mode)
	# print(dragging_node)	
	if edit_mode and dragging_node:
		var mouse_pos = tree_canvas.get_local_mouse_position()
		dragging_node.position = mouse_pos - drag_offset
		# Snap is only visually for the data, but maybe snap it here too? 
		# Let's keep it smooth while dragging and snap on release for simplicity.
		
		var player = CountryManager.player_country
		var country_cats = DecisionManager.get_country_categories(player.country_name)
		var nodes = country_cats.get(current_category, [])
		var idx = dragging_node.get_meta("idx")
		nodes[idx]["pos"] = [dragging_node.position.x, dragging_node.position.y]
		
		_update_connections()
		tree_canvas.queue_redraw()
		

func _input(event: InputEvent) -> void:
	if not visible:
		return
		
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			tree_canvas.position += event.relative
			tree_canvas.queue_redraw()
	
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at_mouse(1.0 + ZOOM_STEP)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at_mouse(1.0 - ZOOM_STEP)


func _zoom_at_mouse(factor: float):
	var old_zoom = current_zoom
	current_zoom = clamp(current_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var final_factor = current_zoom / old_zoom
	
	var mouse_pos = tree_canvas.get_local_mouse_position()
	
	tree_canvas.scale = Vector2(current_zoom, current_zoom)
	# Adjust position to zoom towards the mouse cursor
	tree_canvas.position -= mouse_pos * (final_factor - 1.0) * old_zoom
	tree_canvas.queue_redraw()


# --- LOGIC ---
func open_menu():
	show()
	_rebuild_tabs()
	_load_category(current_category)
	GameState.decision_menu_open = true
	# Editing is only available in debug mode
	edit_button.visible = DecisionManager.debug
	if not DecisionManager.debug:
		edit_button.set_pressed_no_signal(false)
	_on_edit_mode_toggled(edit_button.button_pressed)
	_toggle_pause(true)


func close_menu():
	hide()
	GameState.decision_menu_open = false
	_toggle_pause(false)


func _toggle_pause(pause: bool):
	var world = GameState.current_world
	if world:
		world.set_process(!pause)
		world.clock.set_process(!pause)
		var cam = world.find_child("CameraController", true, false)
		if cam:
			cam.set_process(!pause)
	TroopManager.set_process(!pause)


func _rebuild_tabs():
	while tabs_container.tab_count > 0:
		tabs_container.remove_tab(0)
	
	var player_country = CountryManager.player_country
	var all_decisions = DecisionManager.get_country_categories(player_country.country_name)
	var categories = all_decisions.keys()
	
	for i in range(categories.size()):
		var cat = categories[i]
		tabs_container.add_tab(cat.to_upper())
		if cat == current_category:
			tabs_container.current_tab = i


func _on_tab_changed(tab_idx: int):
	var player_country = CountryManager.player_country
	var all_decisions = DecisionManager.get_country_categories(player_country.country_name)
	var categories = all_decisions.keys()
	
	if tab_idx < categories.size():
		current_category = categories[tab_idx]
		_load_category(current_category)


func _load_category(cat_name: String):
	for c in tree_canvas.get_children():
		c.queue_free()
	node_buttons.clear()
	connection_lines.clear()
	# tree_canvas.position = Vector2.ZERO

	var player = CountryManager.player_country
	var nodes = DecisionManager.get_country_categories(player.country_name).get(cat_name, [])

	for i in range(nodes.size()):
		_create_node(nodes[i], i, player)

	for node in nodes:
		if node.has("prereq"):
			var prereqs = node["prereq"]
			if not prereqs is Array:
				prereqs = [prereqs]
			for req_id in prereqs:
				var start = _get_node_center(nodes, req_id)
				if start != Vector2.ZERO:
					connection_lines.append(
						{
							"type": "prereq",
							"from": start,
							"to": Vector2(node["pos"][0], node["pos"][1]) \
								+ (NODE_SIZE * 0.5),
							"active": player.has_meta("finished_" + req_id)
						}
					)
				
		if node.has("exclusive"):
			var exclusives = node["exclusive"]
			if not exclusives is Array:
				exclusives = [exclusives]
			for ex_id in exclusives:
				var start = _get_node_center(nodes, ex_id)
				if start != Vector2.ZERO:
					# Only draw one line between mutually exclusive nodes
					if node["id"] > ex_id:
						connection_lines.append(
							{
								"type": "exclusive",
								"from": start,
								"to": Vector2(node["pos"][0], node["pos"][1]) \
									+ (NODE_SIZE * 0.5),
								"active": false
							}
						)
	tree_canvas.queue_redraw()


func _update_connections():
	connection_lines.clear()
	var player = CountryManager.player_country
	var categories = DecisionManager.get_country_categories(player.country_name)
	var nodes = categories.get(current_category, [])

	for node in nodes:
		if node.has("prereq"):
			var prereqs = node["prereq"]
			if not prereqs is Array:
				prereqs = [prereqs]
			for req_id in prereqs:
				var start = _get_node_center(nodes, req_id)
				if start != Vector2.ZERO:
					connection_lines.append(
						{
							"type": "prereq",
							"from": start,
							"to": Vector2(node["pos"][0], node["pos"][1]) \
								+ (NODE_SIZE * 0.5),
							"active": player.has_meta("finished_" + req_id)
						}
					)
				
		if node.has("exclusive"):
			var exclusives = node["exclusive"]
			if not exclusives is Array:
				exclusives = [exclusives]
			for ex_id in exclusives:
				var start = _get_node_center(nodes, ex_id)
				if start != Vector2.ZERO:
					if node["id"] > ex_id:
						connection_lines.append(
							{
								"type": "exclusive",
								"from": start,
								"to": Vector2(node["pos"][0], node["pos"][1]) \
									+ (NODE_SIZE * 0.5),
								"active": false
							}
						)


func _create_node(data: Dictionary, idx: int, player: CountryData):
	var btn = Button.new()
	btn.position = Vector2(data["pos"][0], data["pos"][1])
	btn.custom_minimum_size = NODE_SIZE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP # Ensures hover works
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	btn.mouse_entered.connect(func(): _show_info(data))
	btn.mouse_exited.connect(func(): _reset_info())
	btn.pressed.connect(
		func():
			if not edit_mode:
				DecisionManager.start_decision(player, current_category, idx)
	)
	btn.gui_input.connect(func(event): _on_node_gui_input(event, btn, data))
	
	var tt = data["title"]
	if data.has("desc") and data["desc"] != "":
		tt += "\n" + data["desc"]
	
	var reqs_text = str(data.get("reqs", []))
	if reqs_text != "":
		tt += "\n\n[ Requirements ]\n" + reqs_text

	var action_text = str(data.get("action", []))
	if action_text != "":
		tt += "\n\n[ On Finished ]\n" + action_text
	
	btn.tooltip_text = tt

	_apply_node_style(btn, data, player)
	btn.set_meta("id", data["id"])
	btn.set_meta("idx", idx)

	node_buttons[data["id"]] = btn
	tree_canvas.add_child(btn)
	btn.material = DAMAGED_MAT
	return btn


func _show_info(data: Dictionary):
	info_text.text = "[b][font_size=26][color=yellow]%s[/color][/font_size][/b]\n" % data["title"]
	info_text.text += "[font_size=18][i]%s[/i][/font_size]\n\n" % data.get("desc", "")
	info_text.text += (
		"[color=orange]Time: %d Days | Cost: %d Political Power[/color]"
		% [data["days"], data["cost_pp"]]
	)

	if data.has("reqs"):
		var reqs = data["reqs"]
		if not reqs is Array:
			reqs = [reqs]
		
		var final_req_texts = []
		for req in reqs:
			if not req is Dictionary: continue
			
			var args = req.get("args", [])
			var req_line = req.get("func", "Unknown").capitalize()
			if args.size() > 0:
				var arg_strs = []
				for a in args:
					arg_strs.append(str(a).capitalize())
				req_line += ": " + ", ".join(arg_strs)
			final_req_texts.append(req_line)
			
		if not final_req_texts.is_empty():
			var full_text = "\n".join(final_req_texts)
			info_text.text += "\n[color=red]Requirement: %s[/color]" % full_text


func _reset_info():
	info_text.text = "[center][color=gray]Hover over a node to see info[/color][/center]"


func _apply_node_style(btn: Button, data: Dictionary, player: CountryData):
	var id = data["id"]
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_bottom = 4

	if player.has_meta("finished_" + id):
		btn.text = data["title"] + "\n[DONE]"
		style.bg_color = Color(0.1, 0.4, 0.1)
		btn.disabled = true
	elif DecisionManager.is_in_progress(player, id):
		btn.text = data["title"] + "\n⌛ %d Days" % DecisionManager.get_days_left(player, id)
		style.bg_color = Color(0.1, 0.2, 0.5) # Dark Blue
		btn.disabled = true
	else:
		var is_mutually_locked = false
		if data.has("exclusive"):
			var exclusives = data["exclusive"]
			if not exclusives is Array:
				exclusives = [exclusives]
			for ex_id in exclusives:
				if player.has_meta("finished_" + ex_id) or \
					DecisionManager.is_in_progress(player, ex_id):
					is_mutually_locked = true
					break
		
		var is_prereq_locked = false
		if data.has("prereq"):
			var prereqs = data["prereq"]
			if not prereqs is Array:
				prereqs = [prereqs]
			for req_id in prereqs:
				if not player.has_meta("finished_" + req_id):
					is_prereq_locked = true
					break
		
		if is_mutually_locked:
			btn.text = data["title"] + "\n[LOCKED]"
			style.bg_color = Color(0.4, 0.1, 0.1)
			btn.disabled = true
		elif is_prereq_locked:
			btn.text = data["title"]
			style.bg_color = Color(0.241, 0.102, 0.101, 1.0)
			btn.disabled = true
		else:
			btn.text = data["title"] + "\n%d PP" % data["cost_pp"]
			style.bg_color = Color(0.2, 0.2, 0.2)
			# Also check if another decision is already running
			btn.disabled = (
				player.political_power < data["cost_pp"] or DecisionManager.is_country_busy(player)
			)

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.add_theme_stylebox_override("hover", style)


func _on_draw_canvas():
	var vp_size = get_viewport().size
	# Viewport rect in local canvas space
	var rel_origin = - tree_canvas.position / current_zoom
	var view_size = vp_size / current_zoom

	# Find the first grid line to the left/top of the current view
	var start_x = floor(rel_origin.x / GRID_SIZE) * GRID_SIZE
	var start_y = floor(rel_origin.y / GRID_SIZE) * GRID_SIZE

	# Draw enough lines to fill the screen
	var end_x = start_x + view_size.x + GRID_SIZE
	var end_y = start_y + view_size.y + GRID_SIZE

	# Grid logic
	var x = start_x
	while x <= end_x:
		tree_canvas.draw_line(Vector2(x, start_y), Vector2(x, end_y), COL_GRID, 1.0)
		x += GRID_SIZE

	var y = start_y
	while y <= end_y:
		tree_canvas.draw_line(Vector2(start_x, y), Vector2(end_x, y), COL_GRID, 1.0)
		y += GRID_SIZE

	# Connections
	for line in connection_lines:
		if line.get("type", "prereq") == "exclusive":
			_draw_dashed_line(
				tree_canvas, line["from"], line["to"], COL_LINE_EXCLUSIVE, LINE_WIDTH, 15.0
			)
		else:
			var color = COL_LINE_ACTIVE if line["active"] else COL_LINE_INACTIVE
			tree_canvas.draw_line(line["from"], line["to"], color, LINE_WIDTH, true)

func _draw_dashed_line(
	canvas: Node2D,
	from: Vector2,
	to: Vector2,
	color: Color,
	width: float,
	dash_length: float = 10.0
):
	var length = (to - from).length()
	var normal = (to - from).normalized()
	var current_pos = from
	var drawn_length = 0.0

	while drawn_length < length:
		var step_end = current_pos + normal * dash_length
		if drawn_length + dash_length > length:
			step_end = to
		
		# Draw dash
		canvas.draw_line(current_pos, step_end, color, width, true)
		
		# Move past dash and gap
		current_pos = step_end + normal * dash_length
		drawn_length += dash_length * 2.0


func _get_node_center(nodes: Array, id: String) -> Vector2:
	for n in nodes:
		if n["id"] == id:
			return Vector2(n["pos"][0], n["pos"][1]) + (NODE_SIZE * 0.5)
	return Vector2.ZERO


func refresh_status_only():
	if not visible:
		return
	var player = CountryManager.player_country
	var country_categories = DecisionManager.get_country_categories(player.country_name)
	var nodes = country_categories.get(current_category, [])
	for btn in node_buttons.values():
		if is_instance_valid(btn):
			_apply_node_style(btn, nodes[btn.get_meta("idx")], player)
	_update_connections()
	tree_canvas.queue_redraw()


func _on_reload_decisions_pressed():
	var rel_path = "res://starts/" + GameState.current_start + "/decisions/"
	DecisionManager.load_decisions_from_path(rel_path)
	_load_category(current_category)


func _on_edit_mode_toggled(toggled_on: bool):
	edit_mode = toggled_on and DecisionManager.debug
	editing_buttons.visible = edit_mode

	if info_tab:
		info_tab.current_tab = 1 if edit_mode else 0

	if not edit_mode:
		dragging_node = null
		if edit_function.button_pressed:
			edit_function.button_pressed = false # Hides the expression editor
		selected_decision = {}
		selected_node_btn = null
		edit_label.text = ""
		edit_desc.text = ""
		edit_days.value = 0
		edit_ppcost.value = 0


func _on_save_decisions_pressed():
	if not selected_decision.is_empty() and selected_node_btn:
		selected_decision["reqs"] = reqs_block.get_children().filter(func(x): return !x.is_queued_for_deletion()).map(func(x): return x.ToDict())
		selected_decision["action"] = finished_block.get_children().filter(func(x): return !x.is_queued_for_deletion()).map(func(x): return x.ToDict())
		_update_node_visuals(selected_node_btn, selected_decision)
	DecisionManager.save_country_decisions(CountryManager.player_country.country_name)


func _on_node_gui_input(event: InputEvent, btn: Button, data: Dictionary):
	if not edit_mode:
		return
		
	# print(data)

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					dragging_node = btn
					drag_offset = btn.get_local_mouse_position()
					btn.z_index = 10 # Keep dragged node on top
					
					if selected_decision != data:
						# Select for editing
						selected_decision = data
						selected_node_btn = btn
						edit_label.text = data.get("title", "")
						edit_desc.text = data.get("desc", "")
						edit_days.value = data.get("days", 0)
						edit_ppcost.value = data.get("cost_pp", 0)
						if edit_function.button_pressed:
							_load_expression_blocks(data)
						else:
							_load_expression_blocks({})
				else:
					if dragging_node == btn:
						dragging_node = null
						btn.z_index = 0
						# Snap to grid
						btn.position = (btn.position / GRID_SIZE).round() * GRID_SIZE
						data["pos"] = [btn.position.x, btn.position.y]
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					if connecting_id != "":
						var prereqs = data.get("prereq", [])
						if not prereqs is Array: prereqs = [prereqs]
						var exclusives = data.get("exclusive", [])
						if not exclusives is Array: exclusives = [exclusives]
						
						if connecting_id not in prereqs and connecting_id not in exclusives:
							if connecting_id != data.get("id", ""):
								if Input.is_key_pressed(KEY_SHIFT):
									exclusives.append(connecting_id)
									data["exclusive"] = exclusives
								else:
									prereqs.append(connecting_id)
									data["prereq"] = prereqs
						else:
							if Input.is_key_pressed(KEY_SHIFT):
								exclusives.erase(connecting_id)
								if exclusives.is_empty():
									data.erase("exclusive")
								else:
									data["exclusive"] = exclusives
							else:
								prereqs.erase(connecting_id)
								if prereqs.is_empty():
									data.erase("prereq")
								else:
									data["prereq"] = prereqs

						connecting_id = ""
						add_decision.text = "Add Button"
					else:
						connecting_id = data["id"]
						add_decision.text = "[connecting]: %s" % connecting_id
			MOUSE_BUTTON_MIDDLE:
				if Input.is_key_pressed(KEY_SHIFT):
					var player = CountryManager.player_country
					var country_cats = DecisionManager.get_country_categories(player.country_name)
					var nodes: Array = country_cats.get(current_category, [])
					var idx: int = nodes.find(data)
					print(data)
					nodes.remove_at(idx)
					data.clear()
					print(data)
					btn.queue_free()

		_update_connections()
		tree_canvas.queue_redraw()

func _on_add_decision_pressed() -> void:
	var player: CountryData = CountryManager.player_country
	var country_cats: Dictionary = DecisionManager.get_country_categories_editable(player.country_name)
	
	if not country_cats.has(current_category):
		country_cats[current_category] = []
		
	var nodes = country_cats[current_category]
	var id: String = "%s_%d#%d" % [current_category, nodes.size(), randi_range(0, 100)]
	var new_decision = {
		"id": id,
		"title": id,
		"pos": [
			100.0,
			150.0
		],
		"days": 20.0,
		"cost_pp": 25.0,
		"reqs": [],
		"action": [],
		"desc": ""
	}
	nodes.append(new_decision)
	var btn = _create_node(new_decision, nodes.size() - 1, player)

	# Automatically select the new decision
	selected_decision = new_decision
	selected_node_btn = btn
	edit_label.text = new_decision.get("title", "")
	edit_desc.text = new_decision.get("desc", "")
	edit_days.value = new_decision.get("days", 0)
	edit_ppcost.value = new_decision.get("cost_pp", 0)
	_load_expression_blocks(new_decision)
	
	_update_connections()
	tree_canvas.queue_redraw()
	_on_save_decisions_pressed()


func _load_expression_blocks(data: Dictionary):
	_is_loading_expr = true
	for c in reqs_block.get_children():
		reqs_block.remove_child(c)
		c.queue_free()
	for c in finished_block.get_children():
		finished_block.remove_child(c)
		c.queue_free()
	
	for req in data.get("reqs", []):
		var expr = ExpressionBox.FromDict(req, true)
		reqs_block.add_child(expr)
		expr.changed.connect(_sync_expressions)
		
	for act in data.get("action", []):
		var expr = ExpressionBox.FromDict(act, true)
		finished_block.add_child(expr)
		expr.changed.connect(_sync_expressions)
	_is_loading_expr = false


func _on_add_req_pressed():
	_add_expr_to_block(reqs_block)


func _on_add_finished_pressed():
	_add_expr_to_block(finished_block)


func _add_expr_to_block(block: Control):
	if selected_decision.is_empty(): return
	var expr = expression_scene.instantiate()
	expr.is_child = true
	block.add_child(expr)
	expr.changed.connect(_sync_expressions)
	_sync_expressions()


func _sync_expressions():
	if _is_loading_expr or selected_decision.is_empty() or not selected_node_btn: return
	selected_decision["reqs"] = reqs_block.get_children().filter(func(x): return !x.is_queued_for_deletion()).map(func(x): return x.ToDict())
	selected_decision["action"] = finished_block.get_children().filter(func(x): return !x.is_queued_for_deletion()).map(func(x): return x.ToDict())
	_update_node_visuals(selected_node_btn, selected_decision)
	DecisionManager.save_country_decisions(CountryManager.player_country.country_name)


func _on_edit_label_text_changed() -> void:
	if selected_decision.is_empty() or not selected_node_btn:
		return
	
	selected_decision["title"] = edit_label.text
	_update_node_visuals(selected_node_btn, selected_decision)


func _on_edit_desc_text_changed() -> void:
	if selected_decision.is_empty() or not selected_node_btn:
		return
	
	selected_decision["desc"] = edit_desc.text
	_update_node_visuals(selected_node_btn, selected_decision)


func _on_edit_days_value_changed(value: float) -> void:
	if selected_decision.is_empty() or not selected_node_btn:
		return
	
	selected_decision["days"] = int(value)
	_update_node_visuals(selected_node_btn, selected_decision)


func _on_edit_ppcost_value_changed(value: float) -> void:
	if selected_decision.is_empty() or not selected_node_btn:
		return
	
	selected_decision["cost_pp"] = int(value)
	_update_node_visuals(selected_node_btn, selected_decision)


func _update_node_visuals(btn: Button, data: Dictionary):
	var player = CountryManager.player_country
	_apply_node_style(btn, data, player)
	
	# Update tooltip
	var tt = data["title"]
	if data.get("desc", "") != "":
		tt += "\n" + data["desc"]
	
	var reqs_text = str(data.get("reqs", []))
	if reqs_text != "" and reqs_text != "[]":
		tt += "\n\n[ Requirements ]\n" + reqs_text

	var action_text = str(data.get("action", []))
	if action_text != "" and action_text != "[]":
		tt += "\n\n[ On Finished ]\n" + action_text
	
	btn.tooltip_text = tt



func _on_edit_func_toggled(toggled_on: bool) -> void:
	add_req.visible = toggled_on
	add_finished.visible = toggled_on
	editor_tab.visible = toggled_on
	if toggled_on and not selected_decision.is_empty():
		_load_expression_blocks(selected_decision)
	elif not toggled_on:
		_load_expression_blocks({})
