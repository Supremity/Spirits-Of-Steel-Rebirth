extends Node2D
class_name CustomRenderer

# =========================================================
# Constants & Config
# =========================================================
const CITY_COLORS = {
	"text": Color(1, 1, 1, 1),
	"shadow": Color(0, 0, 0, 0.6),
	"dot": Color(1, 1, 1, 0.8)
}
const COLORS = {
	"background":       Color(0, 0, 0, 0.8),
	"text":             Color(1, 1, 1, 1),
	"border_default":   Color(0, 1, 0, 1),   # Green (Yours)
	"border_selected":  Color(0.5, 0.5, 0.5), # Grey (Selected)
	"border_other":     Color(0, 0, 0, 1),    # Black (Others)
	"border_none":      Color(0, 0, 0, 0),
	"path_active":      Color(1, 0.2, 0.2),   # Red (Active path)
	"path_inactive":    Color(0.5, 0.5, 0.5), # Grey (Over limit)
	"movement_active":  Color(0, 1, 0, 0.8),  # Green (Current movement)
	"movement_line":    Color(1, 0.2, 0.2, 1),# Red (Target line)
	"battle_positive":  Color(0, 1, 0, 1),     # Green (Winning)
	"battle_negative":  Color(1, 0, 0, 1)      # Red (Losing)
}

const LAYOUT = {
	"flag_width":        24.0, 
	"flag_height":       20.0,
	"text_padding_x":    8.0,
	"min_text_width":    16.0,
	"border_thickness":  1.0,
	"border_other_px":   1.0,
	"font_size":         18
}

const ZOOM_LIMITS = {
	"min_scale":  0.1, 
	"max_scale":  2.0 
}

const STACKING_OFFSET_Y := 20.0

# =========================================================
# Variables
# =========================================================
var _font: Font = preload("res://font/arial.TTF")
const BATTLE_ICON: Texture2D = preload("res://assets/icons/battle_element_transparent.png")

var map_sprite: Sprite2D
var map_width: float = 0.0
var _current_inv_zoom := 1.0

# =========================================================
# Lifecycle
# =========================================================
func _ready() -> void:
	z_index = 20

func _process(_delta: float) -> void:
	if !map_sprite: return
	
	var cam := get_viewport().get_camera_2d()
	if cam:
		var raw_scale = 1.0 / cam.zoom.x
		_current_inv_zoom = clamp(raw_scale, ZOOM_LIMITS.min_scale, ZOOM_LIMITS.max_scale)
	
	queue_redraw()

# =========================================================
# Draw Master Function
# =========================================================
func _draw() -> void:
	if !map_sprite or map_width <= 0:
		return

	_draw_cities()
	_draw_troops()
	_draw_path_preview()
	_draw_active_movements()
	_draw_battles()
	_draw_selection_box()
	#draw_adjacency_web()	

# For debugging
func draw_adjacency_web() -> void:
	var adj = MapManager.adjacency_list
	var centers = MapManager.province_centers
	
	var line_color = Color(0, 1, 1, 0.4) # Cyan with 40% transparency
	var line_thickness = 1.5
	var circle_radius = 2.0

	for pid in adj.keys():
		if not centers.has(pid): continue
		
		var start_point = centers[pid]
		
		# Optional: Draw a small dot at the province center
		draw_circle(start_point, circle_radius, Color.WHITE)

		for neighbor_id in adj[pid]:
			# neighbor_id < pid prevents drawing the same line twice
			if neighbor_id < pid: continue 
			
			if centers.has(neighbor_id):
				var end_point = centers[neighbor_id]
				draw_line(start_point, end_point, line_color, line_thickness, true)


# Optimized Troop Drawing
# =========================================================
func _draw_troops() -> void:
	var player_country = CountryManager.player_country.country_name
	
	# 1. OPTIMIZATION: O(N) Grouping. Linear scan instead of nested loops.
	var grouped_troops = _group_troops_by_position(TroopManager.troops)

	# 2. OPTIMIZATION: Culling Setup. Don't process what isn't on screen.
	var canvas_transform = get_canvas_transform()
	var viewport_rect = get_viewport_rect()
	var visible_rect = Rect2(-canvas_transform.origin / canvas_transform.get_scale(), 
							 viewport_rect.size / canvas_transform.get_scale())
	
	# Add margin so stacks don't clip at edges
	visible_rect = visible_rect.grow(40.0 * _current_inv_zoom)

	for base_pos in grouped_troops:
		var is_visible = false
		var scroll_offsets_to_draw = []

		# Check 3 positions for infinite scroll wrapping
		for j in [-1, 0, 1]:
			var scroll_offset = Vector2(map_width * j, 0)
			var world_pos = base_pos + map_sprite.position + scroll_offset
			if visible_rect.has_point(world_pos):
				is_visible = true
				scroll_offsets_to_draw.append(scroll_offset)
		
		if not is_visible:
			continue

		var stack: Array = grouped_troops[base_pos]
		var stack_size = stack.size()
		var scaled_offset = STACKING_OFFSET_Y * _current_inv_zoom
		var start_y_offset = (stack_size - 1) * scaled_offset * 0.5

		for i in range(stack_size):
			var t = stack[i]
			var current_y_offset = start_y_offset - (i * scaled_offset)
			var draw_base = base_pos + map_sprite.position + Vector2(0, current_y_offset)

			for s_offset in scroll_offsets_to_draw:
				_draw_single_troop_visual(t, draw_base + s_offset, player_country)

func _group_troops_by_position(troops: Array) -> Dictionary:
	var groups = {}
	# Assuming troops in the same province share the exact same Vector2 position
	for t in troops:
		if not groups.has(t.position):
			groups[t.position] = []
		groups[t.position].append(t)
	return groups

func _draw_single_troop_visual(troop: TroopData, pos: Vector2, player_country: String) -> void:
	# 3. OPTIMIZATION: Level of Detail (LOD)
	# If zoomed very far out, draw a simple dot to save CPU/GPU overhead
	if _current_inv_zoom > 3.0:
		var dot_color = COLORS.border_default if troop.country_name == player_country else COLORS.border_other
		draw_circle(pos, 4.0 * _current_inv_zoom, dot_color)
		return

	var label_text := str(troop.divisions)
	var scale_factor = _current_inv_zoom
	var style = _get_troop_style(troop, player_country)
	var current_border_width = max(0.25, style.width * scale_factor)

	# Measurements
	var flag_size = Vector2(LAYOUT.flag_width, LAYOUT.flag_height) * scale_factor
	var font_size_world = int(LAYOUT.font_size * scale_factor)
	var raw_text_size = _font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18) * scale_factor
	
	var min_text_w_world = LAYOUT.min_text_width * scale_factor
	var padding_world = LAYOUT.text_padding_x * scale_factor
	var final_text_area_width = max(raw_text_size.x + padding_world, min_text_w_world)
	
	var box_size = Vector2(flag_size.x + final_text_area_width, flag_size.y)
	var box_rect = Rect2(pos - box_size * 0.5, box_size)
	
	# Background
	draw_rect(box_rect, COLORS.background, true)
	
	# Flag
	var flag_rect = Rect2(box_rect.position, flag_size)
	if troop.flag_texture: 
		draw_texture_rect(troop.flag_texture, flag_rect, false)
	else:
		draw_rect(flag_rect, Color(0.4, 0.4, 0.4), true)
		
	# Text (Only draw if zoom is close enough to see it)
	if _current_inv_zoom < 2.5:
		var text_start_x = box_rect.position.x + flag_size.x
		var text_center_x = text_start_x + (final_text_area_width * 0.5)
		var draw_pos_x = text_center_x - (raw_text_size.x * 0.5)
		var text_y_center = box_rect.position.y + (box_size.y * 0.5)
		var text_y_baseline = text_y_center + (raw_text_size.y * 0.25)
		
		draw_string(_font, Vector2(draw_pos_x, text_y_baseline), label_text, 
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size_world, COLORS.text)
	
	# Border
	if style.color != COLORS.border_none:
		draw_rect(box_rect, style.color, false, current_border_width)

# =========================================================
# Helper Functions
# =========================================================
func _get_troop_style(troop: TroopData, player_country: String) -> Dictionary:
	var is_owner = troop.country_name.to_lower() == player_country.to_lower()
	var is_selected = TroopManager.troop_selection.selected_troops.has(troop)
	
	if is_owner:
		if is_selected:
			return { "color": COLORS.border_selected, "width": LAYOUT.border_thickness * 2.0 }
		return { "color": COLORS.border_default, "width": LAYOUT.border_thickness }
	return { "color": COLORS.border_other, "width": LAYOUT.border_other_px }

func _draw_selection_box() -> void:
	if not TroopManager.troop_selection.dragging: return
	var ts := TroopManager.troop_selection
	var rect = Rect2(ts.drag_start, ts.drag_end - ts.drag_start).abs()
	if rect.size.length() > 2:
		draw_rect(rect, Color(1, 1, 1, 0.3), true) # Semi-transparent fill
		draw_rect(rect, Color(1, 1, 1, 1), false, 1.0) # Outline

func _draw_path_preview() -> void:
	if not TroopManager.troop_selection.right_dragging: return
	var right_path = TroopManager.troop_selection.right_path
	var max_len = TroopManager.troop_selection.max_path_length
	
	for i in range(right_path.size()):
		var p = right_path[i]["map_pos"] + map_sprite.position
		var color = COLORS.path_inactive if i >= max_len else COLORS.path_active
		draw_circle(p, 1.5 * _current_inv_zoom, color)
		if i < right_path.size() - 1:
			var next_p = right_path[i+1]["map_pos"] + map_sprite.position
			draw_line(p, next_p, color, 1.0 * _current_inv_zoom)

func _draw_active_movements() -> void:
	for troop in TroopManager.troops:
		if not troop.is_moving: continue
		var start = troop.position + map_sprite.position
		var end = troop.target_position + map_sprite.position
		var progress = troop.get_meta("visual_progress", 0.0)
		var current = start.lerp(end, progress)
		draw_line(start, end, Color(1, 0, 0, 0.3), 1.0)
		draw_line(start, current, COLORS.movement_active, 1.5)

func _draw_battles() -> void:
	for battle in WarManager.active_battles:
		var pos = battle.position + map_sprite.position
		var size = BATTLE_ICON.get_size() * 0.05 * _current_inv_zoom
		var draw_pos = pos - size * 0.5
		var p = battle.get_player_relative_progress(CountryManager.player_country.country_name)
		var color = COLORS.battle_positive if p >= 0.0 else COLORS.battle_negative
		draw_circle(pos, 5.0 * _current_inv_zoom, color)
		draw_texture_rect(BATTLE_ICON, Rect2(draw_pos, size), false)
		

func _draw_cities() -> void:
	if not MapManager.id_map_image: return
	
	var dot_radius = 4.0 * _current_inv_zoom
	var hovered_pid = MapManager.current_hovered_pid
	
	for pid in MapManager.province_objects.keys():
		var province = MapManager.province_objects[pid]		
		if province.city == "": continue
			
		var base_pos = MapManager.province_centers.get(pid, Vector2.ZERO)
		if base_pos == Vector2.ZERO: continue

		for j in [-1, 0, 1]:
			var draw_pos = base_pos + map_sprite.position + Vector2(map_width * j, 0)
			
			draw_circle(draw_pos, dot_radius, CITY_COLORS.dot)

			if pid == hovered_pid:
				_draw_city_name_visual(draw_pos, province.city)

func _draw_city_name_visual(pos: Vector2, text: String) -> void:
	if text.is_empty(): return

	var font_size = clampi(int(15 * _current_inv_zoom), 12, 32)
	var outline_size = clampi(int(2 * _current_inv_zoom), 1, 3)

	
	var text_w = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var draw_pos = (pos + map_sprite.position)
	var outline_col = Color(0, 0, 0, 0.8)
	var dirs = [Vector2(1,1), Vector2(-1,1), Vector2(1,-1), Vector2(-1,-1)]
	for dir in dirs:
		draw_string(_font, draw_pos + (dir * outline_size), text, 0, -1, font_size, outline_col)

	draw_string(_font, draw_pos, text, 0, -1, font_size, Color.WHITE)
