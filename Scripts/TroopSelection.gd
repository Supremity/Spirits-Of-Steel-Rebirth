extends Node2D

# Added group to receive redraw calls from Manager
func _enter_tree():
	add_to_group("TroopRenderer")

var font: Font = preload("res://font/TTT-Regular.otf")
const TROOP_DATA_TYPE = preload("res://Scripts/TroopData.gd")

# --- Constants ---
const FLAG_WIDTH_BASE := 32.0
const FLAG_HEIGHT_BASE := 20.0
const PADDING_BASE := 6.0
const GAP_BASE := 8.0
const FONT_SIZE_BASE := 20

# --- State ---
const CLICK_THRESHOLD := 1.0  # pixels – how far mouse can move and still count as a "click"
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_end: Vector2 = Vector2.ZERO

var right_dragging: bool = false
var right_path: Array = []

@onready var map_sprite: Sprite2D = $"../MapContainer/CultureSprite" 

# --- New State Variable to Cache Max Path Length ---
var max_path_length: int = 0


func _input(event) -> void:
	if not map_sprite: return

	# LEFT CLICK: Selection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_mouse(event)


	# RIGHT CLICK: Path Trace
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_mouse(event)

	if event is InputEventMouseMotion:
		if dragging:
			drag_end = get_global_mouse_position()

			# NEW: Perform live selection if we've moved far enough
			var drag_distance = drag_start.distance_to(drag_end)
			if drag_distance >= CLICK_THRESHOLD:
				_perform_selection()  # This now updates selection LIVE!

			queue_redraw()

		if right_dragging:
			if drag_start.distance_to(get_global_mouse_position()) >= CLICK_THRESHOLD:
				_sample_province_under_mouse()
			queue_redraw()

# ---------------------------
# Left-click Selection
# ---------------------------
func _handle_left_mouse(event: InputEventMouseButton) -> void:
	if event.pressed:
		dragging = true
		drag_start = get_global_mouse_position()
		drag_end = drag_start
		queue_redraw()
	else:
		if not dragging:
			return

		drag_end = get_global_mouse_position()
		var drag_distance = drag_start.distance_to(drag_end)

		# If it WAS a real drag, selection was already updated live in _input()
		# So we just clean up
		dragging = false
		queue_redraw()
	
				# 🎯 PLAY SOUND HERE, ONLY ON MOUSE-UP AFTER DRAG
		if drag_distance >= CLICK_THRESHOLD and SelectionManager.is_a_troop_selected():
			MusicManager.play_sfx(MusicManager.SFX.TROOP_SELECTED)

func _perform_selection() -> void:
	if not map_sprite: return

	var world_rect := Rect2(drag_start, drag_end - drag_start).abs()
	var texture_width := map_sprite.texture.get_width()
	var offset := map_sprite.texture.get_size() * 0.5
	var cam = get_viewport().get_camera_2d()
	var inv_zoom = 1.0 / cam.zoom.x if cam else 1.0

	var selected_list: Array[TroopData] = []
	var flag_size = Vector2(FLAG_WIDTH_BASE, FLAG_HEIGHT_BASE) * inv_zoom
	var pad = PADDING_BASE * inv_zoom

	for t in TroopManager.troops:
		if t.country_name.to_lower() != CurrentPlayer.country_name:
			continue

		var label = str(t.divisions)
		var text_size = font.get_string_size(label, FONT_SIZE_BASE) * inv_zoom
		var w = flag_size.x + (GAP_BASE * inv_zoom) + text_size.x + (pad * 2)
		var h = max(flag_size.y, text_size.y) + (pad * 2)
		var box_size = Vector2(w, h)
		var troop_world_center = t.position - offset
		var troop_rect = Rect2(troop_world_center - box_size * 0.5, box_size)

		if _check_rect_intersection(world_rect, troop_rect, t.position.x, texture_width):
			selected_list.append(t)

	# LIVE UPDATE: Always apply current selection (even mid-drag)
	var additive = Input.is_key_pressed(KEY_SHIFT)

	SelectionManager.select_troops(selected_list, additive)

	# Update max_path_length based on current live selection
	max_path_length = 0
	for troop in selected_list:
		max_path_length += troop.divisions

	#print("Live selection: %d troops, %d divisions" % [selected_list.size(), max_path_length])
	
func _check_rect_intersection(selection_rect: Rect2, troop_rect: Rect2, tx: float, tex_w: float) -> bool:
	# Standard check
	if selection_rect.intersects(troop_rect): return true
	
	# Ghost check (Wrapping)
	var GHOST_MARGIN = 600.0
	if tx < GHOST_MARGIN:
		var wrapped = troop_rect
		wrapped.position.x += tex_w
		if selection_rect.intersects(wrapped): return true
	elif tx > tex_w - GHOST_MARGIN:
		var wrapped = troop_rect
		wrapped.position.x -= tex_w
		if selection_rect.intersects(wrapped): return true
		
	return false

# ---------------------------
# Right-click Path Logic (With Split Support)
# ---------------------------
func _handle_right_mouse(event: InputEventMouseButton) -> void:
	if event.pressed and SelectionManager.is_a_troop_selected():
		right_dragging = true
		drag_start = get_global_mouse_position()  # reuse drag_start for threshold
		right_path.clear()
		_sample_province_under_mouse()  # still sample first point immediately
		queue_redraw()
	else:
		if not right_dragging:
			return
			
		var drag_distance = drag_start.distance_to(get_global_mouse_position())
		
		#if drag_distance < CLICK_THRESHOLD:
		#Plain right-click → do nothing (or open context menu later)
		_perform_path_assignment()
		right_path.clear()
		right_dragging = false
		queue_redraw()

func _sample_province_under_mouse() -> void:
	if not map_sprite: return
	
	# --- LIMIT CHECK: Stop sampling if we've reached max provinces ---
	if right_path.size() >= max_path_length:
		# We have already sampled enough provinces (one per division).
		# Stop sampling new provinces, but allow the user to keep dragging.
		return
	# -----------------------

	var local_pos = map_sprite.to_local(get_global_mouse_position())
	var pid = MapManager.get_province_at_pos(local_pos, map_sprite)
	
	if pid <= 0: return
	if right_path.size() > 0 and right_path[-1]["pid"] == pid: return
	
	var center_tex = MapManager.province_centers.get(pid, Vector2.ZERO)
	if center_tex == Vector2.ZERO: return
	
	var center_local = center_tex - (map_sprite.texture.get_size() * 0.5)
	
	right_path.append({
		"pid": pid,
		"map_pos": center_local, 
		"texture_pos": center_tex
	})
	
	print("Sampled province %d. Path length: %d/%d" % [pid, right_path.size(), max_path_length])

func _perform_path_assignment() -> void:
	if right_path.is_empty(): return
	
	# Extract unique sequential PIDs
	var path_pids = []
	for entry in right_path:
		if path_pids.is_empty() or path_pids[-1] != entry["pid"]:
			path_pids.append(entry["pid"])

	var selected_troops = SelectionManager.get_selected_troops()
	if selected_troops.is_empty(): return
	
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
	var divisions_per_province = max(1, total_divisions / path_pids.size())
	var remainder = total_divisions % path_pids.size()
	
	# Distribute troops to provinces based on their divisions
	var troop_index = 0
	var divisions_remaining_in_current_troop = selected_troops[0].divisions if selected_troops.size() > 0 else 0
	
	for province_idx in range(path_pids.size()):
		var target_pid = path_pids[province_idx]
		var target = target_positions[province_idx]
		
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

	print("Path assignment: %d provinces, %d total divisions across %d troops" % [path_pids.size(), total_divisions, selected_troops.size()])
	
	# Send to Manager
	if TroopManager.has_method("command_move_assigned"):
		TroopManager.command_move_assigned(assignments)
		right_path.clear()
		selected_troops.clear()

# ---------------------------
# Drawing
# ---------------------------
func _draw() -> void:
	if not map_sprite: return
	var tex_offset = map_sprite.texture.get_size() * 0.5
	
	# 1. Draw Selection Box
	if dragging:
		var local_start = map_sprite.to_local(drag_start)
		var local_end = map_sprite.to_local(drag_end)
		var r = Rect2(local_start, local_end - local_start).abs()
		#draw_rect(r, Color(0, 0.5, 1, 0.2), true) (
		draw_rect(r, Color(1.0, 1.0, 1.0, 1.0), false, 2.0)

	# 2. Draw Right-Click Path Preview (with limit indicator)
	if right_path.size() > 0:
		for i in range(right_path.size()):
			var p = right_path[i]["map_pos"]
			# Change color if we've reached the max path length
			var color = Color(1, 0.2, 0.2) if i < max_path_length else Color(0.5, 0.5, 0.5)
			draw_circle(p, 1, color)
			if i < right_path.size() - 1:
				draw_line(p, right_path[i+1]["map_pos"], color, 1.5)

	# 3. Draw Moving Troop Vectors (Arrows & Progress)
	for t in TroopManager.troops:
		if t.is_moving:
			var start_local = t.position - tex_offset
			var end_local = t.target_position - tex_offset
			
			var current_visual_pos = start_local.lerp(end_local, t.get_meta("visual_progress", 0.0))
			draw_line(start_local, current_visual_pos, Color(0, 1, 0, 0.8), 2.0)
			#draw_line(start_local, current_visual_pos, Color(0, 1, 0, 0.8), 2.0)
			draw_line(start_local, end_local, Color(1.0, 0.2, 0.2, 1), 1.0)
			
