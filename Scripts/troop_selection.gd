extends Node2D
class_name TroopSelection

var font: Font = preload("res://font/TTT-Regular.otf")

# --- Constants ---
const FLAG_WIDTH_BASE := 24.0
const FLAG_HEIGHT_BASE := 20.0
const PADDING_BASE := 6.0
const GAP_BASE := 8.0
const CLICK_THRESHOLD := 2.0 # pixels – how far mouse can move and still count as a "click"

# --- State ---
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_end: Vector2 = Vector2.ZERO

var right_dragging: bool = false
var right_path: Array = []

@onready var map_sprite: Sprite2D = $"../../../MapContainer/CultureSprite"

# --- Path Length Limit ---
var max_path_length: int = 0

var selected_troops: Array[TroopData] = []

func _input(event) -> void:
	if !map_sprite || Console.is_visible():
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_mouse(event)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_mouse(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion()


func deselect_all() -> void:
	selected_troops.clear()
	GameState.game_ui.close_troop_container()


func _handle_mouse_motion() -> void:
	if dragging:
		drag_end = get_global_mouse_position()
		if drag_start.distance_to(drag_end) >= CLICK_THRESHOLD:
			_perform_selection()

	if right_dragging && drag_start.distance_to(get_global_mouse_position()) >= CLICK_THRESHOLD:
			_sample_province_under_mouse()


func _handle_left_mouse(event: InputEventMouseButton) -> void:
	if GameState.selectingCountry || !dragging && MapManager._is_mouse_over_ui():
		return
	
	if event.pressed:
		dragging = true
		drag_start = get_global_mouse_position()
		drag_end = drag_start
	elif dragging:
		drag_end = get_global_mouse_position()
		dragging = false

		if selected_troops.size() > 0:
			MusicManager.play_sfx(MusicManager.SFX.TROOP_SELECTED)
			# Call your new function
			GameState.game_ui.make_troop_container(selected_troops)
		else:
			# If we clicked empty ground, hide the container
			GameState.game_ui.close_troop_container()


func _handle_right_mouse(event: InputEventMouseButton) -> void:
	if event.pressed and not selected_troops.is_empty():
		right_dragging = true
		drag_start = get_global_mouse_position()
		right_path.clear()
		_sample_province_under_mouse()
	elif right_dragging:
		_perform_path_assignment()
		right_path.clear()
		right_dragging = false


func _perform_selection() -> void:
	if !map_sprite:
		return

	var world_rect := Rect2(drag_start, drag_end - drag_start).abs()
	var texture_width := map_sprite.texture.get_width()
	var cam = get_viewport().get_camera_2d()
	var inv_zoom = 1.0 / cam.zoom.x if cam else 1.0

	var selected_list: Array[TroopData] = []
	var flag_size = Vector2(FLAG_WIDTH_BASE, FLAG_HEIGHT_BASE) * inv_zoom
	var pad = PADDING_BASE * inv_zoom * 2
	var baseBoxSize = Vector2(flag_size.x + (GAP_BASE * inv_zoom) + pad, pad)

	for t in TroopManager.troops:
		if t.country_name != CountryManager.player_country.country_name:
			continue

		var text_size = (
			font.get_string_size(str(t.divisions_count), HORIZONTAL_ALIGNMENT_CENTER, -1, CustomRenderer.LAYOUT.font_size) * inv_zoom
		)

		var box_size = baseBoxSize + Vector2(text_size.x, max(flag_size.y, text_size.y))
		if _check_rect_intersection(world_rect, Rect2(t.position + map_sprite.position - box_size * 0.5, box_size), t.position.x, texture_width):
			selected_list.append(t)

	# Apply selection
	if !Input.is_key_pressed(KEY_SHIFT):
		selected_troops.clear()

	for t in selected_list:
		if !selected_troops.has(t):
			selected_troops.append(t)

	# Update max_path_length based on current live selection
	max_path_length = 0
	for troop in selected_list:
		max_path_length += troop.divisions_count


func _check_rect_intersection(
	selection_rect: Rect2, troop_rect: Rect2, tx: float, tex_w: float
) -> bool:
	# Standard check
	if selection_rect.intersects(troop_rect):
		return true

	# Ghost check (Wrapping)
	const GHOST_MARGIN = 600.0
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


func _sample_province_under_mouse() -> void:
	if !map_sprite:
		return

	# Stop sampling if we've reached max provinces
	if right_path.size() >= max_path_length:
		return

	var pid = MapManager.getProvinceAtPos(get_global_mouse_position(), map_sprite)

	# if pid <= 0 || MapManager.province_objects[pid].type == Province.SEA:
	# 	return

	# Check for military access
	var prov = MapManager.province_objects[pid]
	if !prov || !CountryManager.player_country.get_all_allowed_countries().has(prov.GetFunctionalOwner()):
		return

	# Don't add duplicate consecutive provinces
	if right_path.size() > 0 && right_path[-1]["pid"] == pid:
		return

	# Force the next province to be a neighbor of the previous one (no "jumping")
	if right_path.size() > 0:
		var last_pid = right_path[-1]["pid"]
		if !MapManager.province_graph.are_points_connected(last_pid, pid):
			return

	var center_tex = MapManager.province_centers[pid]
	if !center_tex:
		return

	right_path.append({"pid": pid, "map_pos": center_tex, "texture_pos": center_tex})

	print("Sampled province %d. Path length: %d/%d" % [pid, right_path.size(), max_path_length])


func _perform_path_assignment() -> void:
	if right_path.is_empty() or selected_troops.is_empty():
		return

	var path_pids = []
	for entry in right_path:
		if path_pids.is_empty() || path_pids[-1] != entry["pid"]:
			path_pids.append(entry["pid"])

	if path_pids.is_empty():
		return

	# 1. Cast the moving pool correctly
	var ui_selected = GameState.game_ui.selected_division_objects
	var moving_pool: Array[DivisionData] = []

	if !ui_selected.is_empty():
		moving_pool = ui_selected.duplicate()
	else:
		for t in selected_troops:
			moving_pool.append_array(t.stored_divisions)

	# 2. Ensure the Dictionary values are typed arrays
	var pool_by_origin = {}

	for div in moving_pool:
		var owningPolity = TroopManager.find_troop_owning_division(div)
		if owningPolity:
			var origin_id = owningPolity.province_id
			if !pool_by_origin.has(origin_id):
				# Initialize as a typed arrays
				pool_by_origin[origin_id] = [] as Array[DivisionData]
			pool_by_origin[origin_id].append(div)

	var all_assignments = []

	for origin_id in pool_by_origin:
		# 3. Cast the origin batch when retrieving it
		var origin_batch = pool_by_origin[origin_id] as Array[DivisionData]

		var template = null
		for t in selected_troops:
			if t.province_id == origin_id:
				template = t
				break

		if !template:
			var troops_at_origin = TroopManager.get_troops_in_province(origin_id)
			if !troops_at_origin.is_empty():
				template = troops_at_origin[0]
			else:
				continue

		@warning_ignore("integer_division")
		var divs_per_target: int = max(1, origin_batch.size() / path_pids.size())
		var remainder: int = origin_batch.size() % path_pids.size()
		var current_batch_idx: int = 0

		for province_idx in range(path_pids.size()):
			# 4. Initialize the specific batch as a typed array
			var final_divs: Array[DivisionData] = []
			for i in range(divs_per_target + (1 if province_idx < remainder else 0)):
				if current_batch_idx < origin_batch.size():
					var div = origin_batch[current_batch_idx]
					_remove_division_from_current_owner(div)
					final_divs.append(div)
					current_batch_idx += 1

			if final_divs.is_empty():
				continue

			# This will now succeed because final_divs is Array[DivisionData]
			var new_troop = TroopManager._create_new_split_troop(template, final_divs)
			all_assignments.append({"troop": new_troop, "province_id": path_pids[province_idx]})

	TroopManager.command_move_assigned(all_assignments)
	_cleanup_empty_troops()

	GameState.game_ui.selected_division_objects.clear()
	GameState.game_ui.close_troop_container()
	selected_troops.clear()
	right_path.clear()


# --- Helper functions for the logic above ---


func _remove_division_from_current_owner(div: DivisionData):
	# Search all our selected troops and remove the div from their stored_divisions
	for t in selected_troops:
		if t.stored_divisions.has(div):
			t.stored_divisions.erase(div)
			return


func _cleanup_empty_troops():
	# If a troop gave away all its divisions, delete it from the world
	for t in selected_troops:
		if t.stored_divisions.is_empty():
			TroopManager.RemoveTroop(t)


# --- Helpers to keep logic clean ---


func _find_template_troop_for_divs(batch: Array[DivisionData]) -> TroopData:
	# Find which troop currently owns the first division in this batch
	# to use as a template (country name, flag, etc)
	for t in selected_troops:
		if batch[0] in t.stored_divisions:
			return t
	return selected_troops[0]


# --- MODE A: Move only the units clicked in the UI ---
func _handle_selective_ui_move(div_objects: Array[DivisionData], path: Array) -> void:
	# Group the divisions by their current "parent" troop so we can split them
	var split_map = {} # { TroopData: Array[DivisionData] }
	for div in div_objects:
		var owningPoltiy: TroopData = TroopManager.find_troop_owning_division(div)
		if owningPoltiy:
			if !split_map.has(owningPoltiy):
				split_map[owningPoltiy] = []
			split_map[owningPoltiy].append(div)

	for original_troop in split_map:
		var divs_to_move = split_map[original_troop]

		# Remove these objects from the original stack
		for d in divs_to_move:
			original_troop.stored_divisions.erase(d)

		# Create the new troop instance for the split-off units
		var new_troop = TroopManager._create_new_split_troop(original_troop, divs_to_move)
		new_troop.path = path.duplicate()
		TroopManager._start_next_leg(new_troop)

		# If the original troop is now empty, delete it from the map
		if original_troop.stored_divisions.is_empty():
			TroopManager.RemoveTroop(original_troop)


# --- MODE B: Spread the whole selected army across the path ---
func _handle_frontline_spread(path: Array) -> void:
	# Collect ALL division objects from all selected troops
	var all_divs: Array[DivisionData] = []
	for t in selected_troops:
		all_divs.append_array(t.stored_divisions)
		# We will effectively "re-distribute" all these, so clear the originals
		t.stored_divisions.clear()

	@warning_ignore("integer_division")
	var divs_per_prov: int = max(1, all_divs.size() / path.size())
	var remainder: int = all_divs.size() % path.size()

	var div_index: int = 0
	for i in range(path.size()):
		# var target_pid = path[i]
		var batch: Array[DivisionData] = []
		for j in range(divs_per_prov + (1 if i < remainder else 0)):
			if div_index < all_divs.size():
				batch.append(all_divs[div_index])
				div_index += 1

		if batch.is_empty():
			continue

		var new_troop: TroopData = TroopManager._create_new_split_troop(selected_troops[0], batch)
		new_troop.path = path.slice(0, i + 1)
		TroopManager._start_next_leg(new_troop)

	# Clean up the now-empty original troops
	for t in selected_troops:
		if t.stored_divisions.is_empty():
			TroopManager.RemoveTroop(t)


func _print_troop_details(troop: TroopData) -> void:
	print("--- Selected Troop (Prov: %d) ---" % troop.province_id)
	for div in troop.stored_divisions:
		var exp_level = "Green"
		if div.experience > 0.7:
			exp_level = "Veteran"
		elif div.experience > 0.3:
			exp_level = "Trained"

		print(
			(
				" > %s [%s] - HP: %d%% - Exp: %s"
				% [div.name, div.type.to_upper(), div.hp, exp_level]
			)
		)
