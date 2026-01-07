extends Node2D
class_name TroopSelection

var font:  Font = preload("res://font/TTT-Regular.otf")

# --- Constants ---
const FLAG_WIDTH_BASE := 24.0
const FLAG_HEIGHT_BASE := 20.0
const PADDING_BASE := 6.0
const GAP_BASE := 8.0
const CLICK_THRESHOLD := 1.0  # pixels – how far mouse can move and still count as a "click"

# --- State ---
var dragging: bool = false
var drag_start:  Vector2 = Vector2.ZERO
var drag_end: Vector2 = Vector2.ZERO

var right_dragging: bool = false
var right_path: Array = []

@onready var map_sprite:  Sprite2D = $"../MapContainer/CultureSprite"

# --- Path Length Limit ---
var max_path_length: int = 0

var selected_troops: Array[TroopData] = []


func select_troops(new_list: Array[TroopData], append:  bool = false) -> void:
	if not append:
		selected_troops.clear()
	
	for t in new_list:
		if not selected_troops.has(t):
			selected_troops.append(t)
			


func _input(event) -> void:
	if not map_sprite or Console.is_visible(): 
		return

	if event is InputEventMouseButton: 
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_mouse(event)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_mouse(event)

	elif event is InputEventMouseMotion:
		_handle_mouse_motion()


func _handle_mouse_motion() -> void:
	if dragging:
		drag_end = get_global_mouse_position()
		var drag_distance = drag_start.distance_to(drag_end)
		
		if drag_distance >= CLICK_THRESHOLD:
			_perform_selection()
		

	if right_dragging:
		if drag_start.distance_to(get_global_mouse_position()) >= CLICK_THRESHOLD:
			_sample_province_under_mouse()


func _handle_left_mouse(event: InputEventMouseButton) -> void:
	if event.pressed: 
		dragging = true
		drag_start = get_global_mouse_position()
		drag_end = drag_start
	else:
		if not dragging:
			return

		drag_end = get_global_mouse_position()
		var drag_distance = drag_start.distance_to(drag_end)

		dragging = false
	
		if drag_distance >= CLICK_THRESHOLD and not selected_troops.is_empty():
			MusicManager.play_sfx(MusicManager.SFX.TROOP_SELECTED)


func _perform_selection() -> void:
	if not map_sprite:
		return

	var world_rect := Rect2(drag_start, drag_end - drag_start).abs()
	var texture_width := map_sprite.texture.get_width()
	var cam = get_viewport().get_camera_2d()
	var inv_zoom = 1.0 / cam.zoom.x if cam else 1.0

	var selected_list: Array[TroopData] = []
	var flag_size = Vector2(FLAG_WIDTH_BASE, FLAG_HEIGHT_BASE) * inv_zoom
	var pad = PADDING_BASE * inv_zoom

	for t in TroopManager.troops:
		if t.country_name.to_lower() != CountryManager.player_country.country_name: 
			continue

		var label = str(t.divisions)
		var font_size := CustomRenderer.LAYOUT.font_size
		var text_size = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size) * inv_zoom
		
		var w = flag_size.x + (GAP_BASE * inv_zoom) + text_size.x + (pad * 2)
		var h = max(flag_size.y, text_size.y) + (pad * 2)
		var box_size = Vector2(w, h)
		var troop_world_center = t.position + map_sprite.position
		var troop_rect = Rect2(troop_world_center - box_size * 0.5, box_size)

		if _check_rect_intersection(world_rect, troop_rect, t.position.x, texture_width):
			selected_list.append(t)

	# Apply selection
	var additive = Input.is_key_pressed(KEY_SHIFT)
	if not additive:
		selected_troops.clear()
	
	for t in selected_list:
		if not selected_troops.has(t):
			selected_troops.append(t)

	# Update max_path_length based on current live selection
	max_path_length = 0
	for troop in selected_list:
		max_path_length += troop.divisions


func _check_rect_intersection(selection_rect: Rect2, troop_rect: Rect2, tx: float, tex_w: float) -> bool:
	# Standard check
	if selection_rect.intersects(troop_rect):
		return true
	
	# Ghost check (Wrapping)
	var GHOST_MARGIN = 600.0
	if tx < GHOST_MARGIN:
		var wrapped = troop_rect
		wrapped.position.x += tex_w
		if selection_rect.intersects(wrapped):
			return true
	elif tx > tex_w - GHOST_MARGIN:
		var wrapped = troop_rect
		wrapped.position.x -= tex_w
		if selection_rect.intersects(wrapped):
			return true
		
	return false


func _handle_right_mouse(event: InputEventMouseButton) -> void:
	if event.pressed and not selected_troops.is_empty():
		right_dragging = true
		drag_start = get_global_mouse_position()
		right_path.clear()
		_sample_province_under_mouse()
	else:
		if not right_dragging:
			return
		
		_perform_path_assignment()
		right_path.clear()
		right_dragging = false


func _sample_province_under_mouse() -> void:
	if not map_sprite:
		return
	
	# Stop sampling if we've reached max provinces
	if right_path.size() >= max_path_length:
		return

	var local_pos = get_global_mouse_position()
	var pid = MapManager.get_province_at_pos(local_pos, map_sprite)
	
	if pid <= 0:
		return
	
	# Don't add duplicate consecutive provinces
	if right_path.size() > 0 and right_path[-1]["pid"] == pid:
		return
	
	var center_tex = MapManager.province_centers.get(pid)
	if not center_tex:
		return
	
	right_path.append({
		"pid": pid,
		"map_pos": center_tex,
		"texture_pos": center_tex
	})
	
	print("Sampled province %d. Path length: %d/%d" % [pid, right_path.size(), max_path_length])


func _perform_path_assignment() -> void:
	if right_path.is_empty():
		return

	# Extract unique sequential PIDs
	var path_pids = []
	for entry in right_path:
		if path_pids.is_empty() or path_pids[-1] != entry["pid"]:
			path_pids.append(entry["pid"])

	if selected_troops.is_empty():
		return
	
	# Setup target positions for math
	var target_positions = []
	for pid in path_pids:
		var found = false
		for e in right_path:
			if e["pid"] == pid:
				target_positions.append(e["texture_pos"])
				found = true
				break
		if not found:
			target_positions.append(Vector2.ZERO)

	var assignments = []
	
	# Calculate total divisions available
	var total_divisions = 0
	for troop in selected_troops:
		total_divisions += troop.divisions
	
	if path_pids.size() == 0:
		print("No provinces in path!")
		return
	
	# Distribute divisions across provinces
	@warning_ignore("integer_division")
	var divisions_per_province = max(1, total_divisions / path_pids.size())
	var remainder = total_divisions % path_pids.size()
	
	# Distribute troops to provinces based on their divisions
	var troop_index = 0
	var divisions_remaining_in_current_troop = selected_troops[0].divisions if selected_troops.size() > 0 else 0
	
	for province_idx in range(path_pids.size()):
		var target_pid = path_pids[province_idx]
		
		# Determine how many divisions go to this province
		var divs_for_this_province = divisions_per_province
		if province_idx < remainder:
			divs_for_this_province += 1
		
		# Find which troop(s) to assign based on available divisions
		while divs_for_this_province > 0 and troop_index < selected_troops.size():
			var current_troop = selected_troops[troop_index]
			
			if divisions_remaining_in_current_troop > 0:
				# Assign this troop to this province
				assignments.append({ "troop": current_troop, "province_id": target_pid })
				divisions_remaining_in_current_troop -= 1
				divs_for_this_province -= 1
				
				# Move to next troop if current one is exhausted
				if divisions_remaining_in_current_troop <= 0 and troop_index < selected_troops.size() - 1:
					troop_index += 1
					if troop_index < selected_troops.size():
						divisions_remaining_in_current_troop = selected_troops[troop_index].divisions
			else:
				troop_index += 1
				if troop_index < selected_troops.size():
					divisions_remaining_in_current_troop = selected_troops[troop_index].divisions

	print("Path assignment:  %d provinces, %d total divisions across %d troops" % [path_pids.size(), total_divisions, selected_troops.size()])
	
	TroopManager.command_move_assigned(assignments)
	right_path.clear()
	selected_troops.clear()
