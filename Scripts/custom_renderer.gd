extends Node2D
class_name CustomRenderer

# --- Constants & Config ---
const COLORS = {
	"background": Color(0, 0, 0, 0.8),
	"text": Color(1, 1, 1, 1),
	"border_default": Color(0, 1, 0, 1),
	"border_selected": Color(0.8, 0.8, 0.8),
	"border_other": Color(0, 0, 0, 1),
	"movement_active": Color(0, 1, 0, 0.8),
	"path_active": Color(1, 0.2, 0.2),
	"path_inactive": Color(0.5, 0.5, 0.5)
}

const LAYOUT = {
	"flag_width": 24.0,
	"flag_height": 20.0,
	"min_text_width": 16.0,
	"font_size": 16
}

const ZOOM_LIMITS = {"min_scale": 0.1, "max_scale": 2.0}
const STACKING_OFFSET_Y := 20.0

# --- Variables ---
var _font: Font = preload("res://font/arial.TTF")
var map_sprite: Sprite2D
var map_width: float = 0.0
var _current_inv_zoom := 1.0
var _screen_rect: Rect2

# Reference to the GPU node
var troop_multimesh: MultiMeshInstance2D 

var _last_cam_pos := Vector2.INF
var _last_cam_zoom := Vector2.INF

# --- Lifecycle ---
func _ready() -> void:
	z_index = 20 # Keep renderer high
	_setup_multimesh()

func _process(_delta: float) -> void:
	if !map_sprite: return

	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	
	var zoom_changed := cam.zoom != _last_cam_zoom
	var pos_changed := cam.global_position != _last_cam_pos

	if zoom_changed or pos_changed:
		var raw_scale := 1.0 / cam.zoom.x
		_current_inv_zoom = clamp(raw_scale, ZOOM_LIMITS.min_scale, ZOOM_LIMITS.max_scale)

		_update_screen_rect()

		_last_cam_zoom = cam.zoom
		_last_cam_pos = cam.global_position

	_update_multimesh_buffer()
	
	queue_redraw()

# --- MultiMesh Setup ---
func _setup_multimesh():
	if not troop_multimesh:
		troop_multimesh = MultiMeshInstance2D.new()
		troop_multimesh.name = "TroopMultiMesh"
#		troop_multimesh.mouse_filter = Control.MOUSE_FILTER_IGNORE 
		# Crucial: Move the boxes behind the labels
		troop_multimesh.z_index = -1 
		add_child(troop_multimesh)
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = false # Simplified to avoid data corruption
	
	var q_mesh = QuadMesh.new()
	q_mesh.size = Vector2(LAYOUT.flag_width + LAYOUT.min_text_width, LAYOUT.flag_height)
	mm.mesh = q_mesh
	
	# SHADER: Using modern Godot 4.5 canvas_item logic
	var mat = ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
	shader_type canvas_item;
	void fragment() {
		float zoom = max(0.4, COLOR.a); // we’ll encode zoom in alpha
		float tx = 0.05 * zoom;
		float ty = 0.1 * zoom;

		bool is_border = UV.x < tx || UV.x > (1.0 - tx) || UV.y < ty || UV.y > (1.0 - ty);
		// COLOR here is the Instance Color we set in GDScript
		if (is_border) {
			COLOR = COLOR; 
		} else {
			COLOR = vec4(0.0, 0.0, 0.0, 0.8); 
		}
	}
	"""
	# Apply material to the Instance, not the Mesh (more reliable for updates)
	troop_multimesh.material = mat
	troop_multimesh.multimesh = mm

func _update_multimesh_buffer():
	if not map_sprite or map_width <= 0 or not troop_multimesh: return
		
	var troops = TroopManager.troops
	var mm = troop_multimesh.multimesh
	var needed = troops.size() * 3
	
	if mm.instance_count != needed:
		mm.instance_count = needed
	
	var player_country = CountryManager.player_country.country_name
	var selected_troops = TroopManager.troop_selection.selected_troops
	var groups = _group_troops_by_visual_position(troops)
	var idx = 0
	
	for base_pos in groups:
		var stack = groups[base_pos]
		var scaled_offset := STACKING_OFFSET_Y * _current_inv_zoom
		var start_y = (stack.size() - 1) * scaled_offset * 0.5

		
		for i in range(stack.size()):
			var troop = stack[i]
			var pos = base_pos + Vector2(0, start_y - (i * scaled_offset))
			
			# Logic for colors
			var col = COLORS.border_other
			if troop.country_name == player_country:
				col = COLORS.border_selected if selected_troops.has(troop) else COLORS.border_default
			
			for m in [-1, 0, 1]:
				if idx >= mm.instance_count: break
				var f_pos = pos + Vector2(map_width * m, 0) + map_sprite.position
				var scale := Vector2(_current_inv_zoom, _current_inv_zoom)

				mm.set_instance_transform_2d(
					idx,
					Transform2D(0, scale, 0, f_pos)
				)
				mm.set_instance_color(idx, col)
				idx += 1

# --- Drawing ---
func _draw() -> void:
	if !map_sprite or map_width <= 0: return
	_draw_path_preview()
	_draw_active_movements()
	_draw_selection_box()
	_draw_troop_details_culled()
	_draw_cities()
# --- Drawing ---
func _draw_troop_details_culled() -> void:
	if _current_inv_zoom > 1.5: return # LOD optimization

	# Use the same grouping logic but account for movement
	var troops = TroopManager.troops
	var groups = _group_troops_by_visual_position(troops)
	
	for base_pos in groups:
		var stack = groups[base_pos]
		# Use scaled offset so text stays aligned with the MultiMesh boxes
		var scaled_offset := STACKING_OFFSET_Y * _current_inv_zoom
		var start_y = (stack.size() - 1) * scaled_offset * 0.5
		
		for i in range(stack.size()):
			var troop = stack[i]
			# Calculate position including world-wrapping (m)
			var vertical_stack_pos = base_pos + Vector2(0, start_y - (i * scaled_offset))
			
			for m in [-1, 0, 1]:
				var d_pos = vertical_stack_pos + Vector2(map_width * m, 0) + map_sprite.position
				if _screen_rect.has_point(d_pos):
					_draw_single_troop_detail(troop, d_pos)

func _draw_single_troop_detail(troop: TroopData, pos: Vector2) -> void:
	# 1. Save the current drawing state
	var base_transform = get_canvas_transform()
	
	# 2. Apply a local transform for this specific troop
	# We move to the troop position and scale everything by _current_inv_zoom
	var t := Transform2D(0, Vector2(_current_inv_zoom, _current_inv_zoom), 0, pos)
	draw_set_transform_matrix(t)

	# --- Everything below is now drawn relative to (0,0) at scale 1.0 ---
	
	var total_w = LAYOUT.flag_width + LAYOUT.min_text_width
	var total_h = LAYOUT.flag_height
	var top_left = Vector2(-total_w / 2.0, -total_h / 2.0)

	# Draw Flag (Left side)
	if troop.flag_texture:
		# Shrink by 1px to stay inside the border
		var flag_rect = Rect2(top_left, Vector2(LAYOUT.flag_width, total_h)).grow(-1.0)
		draw_texture_rect(troop.flag_texture, flag_rect, false)

	# Draw Text (Right side)
	var label = str(troop.divisions)
	# Use the base font size; the transform handles the zoom-scaling for us!
	var font_size = LAYOUT.font_size 
	var text_size = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	
	# Position text relative to the flag's right edge
	var text_area_x = top_left.x + LAYOUT.flag_width
	var tx = text_area_x + (LAYOUT.min_text_width - text_size.x) * 0.5
	var ty = (text_size.y * 0.3) # Vertical center relative to (0,0)

	draw_string(_font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLORS.text)

	# 3. Reset transform so other things draw correctly
	draw_set_transform_matrix(Transform2D())

# --- Updated Helper for Movement ---
func _group_troops_by_visual_position(troops: Array) -> Dictionary:
	var g = {}
	for t in troops:
		# Get interpolated position if moving, else static position
		var visual_pos = t.position
		if t.is_moving:
			var progress = t.get_meta("progress", 0.0)
			visual_pos = t.position.lerp(t.target_position, progress)
		
		if not g.has(visual_pos): g[visual_pos] = []
		g[visual_pos].append(t)
	return g

func _draw_selection_box() -> void:
	if not TroopManager.troop_selection.dragging: return
	var ts = TroopManager.troop_selection
	var rect = Rect2(ts.drag_start, ts.drag_end - ts.drag_start).abs()
	draw_rect(rect, Color(1, 1, 1, 0.3), true)
	draw_rect(rect, Color(1, 1, 1, 1), false, 1.0)

func _draw_path_preview() -> void:
	if not TroopManager.troop_selection.right_dragging: return
	var path = TroopManager.troop_selection.right_path
	for i in range(path.size()):
		var p = path[i]["map_pos"] + map_sprite.position
		var col = COLORS.path_active if i < TroopManager.troop_selection.max_path_length else COLORS.path_inactive
		draw_circle(p, 1.0, col)

func _draw_active_movements() -> void:
	for troop in TroopManager.troops:
		if !troop.is_moving: continue
		var start = troop.position + map_sprite.position
		var end = troop.target_position + map_sprite.position
		if _screen_rect.has_point(start) or _screen_rect.has_point(end):
			var current = start.lerp(end, troop.get_meta("visual_progress", 0.0))
			draw_line(start, end, Color(1, 0, 0, 0.2), 1.0)
			draw_line(start, current, COLORS.movement_active, 1.5)
			
func _update_screen_rect():
	var canvas_xform := get_canvas_transform()
	var viewport_rect := get_viewport_rect()

	_screen_rect = Rect2(
		-canvas_xform.origin / canvas_xform.get_scale(),
		viewport_rect.size / canvas_xform.get_scale()
	)

	_screen_rect = _screen_rect.grow(200.0)



func _draw_cities() -> void:
	if not MapManager.id_map_image: return

	var hovered_pid = MapManager.current_hovered_pid
	var base_dot_radius = 4.0
	var base_font_size = 24 

	for pid in MapManager.province_objects.keys():
		var province = MapManager.province_objects[pid]
		if province.city == "": continue

		var base_pos = MapManager.province_centers.get(pid, Vector2.ZERO)
		if base_pos == Vector2.ZERO: continue
		for j in [-1, 0, 1]:
			var world_pos = base_pos + map_sprite.position + Vector2(map_width * j, 0)
			if not _screen_rect.has_point(world_pos): continue

			var t := Transform2D(0, Vector2(_current_inv_zoom, _current_inv_zoom), 0, world_pos)
			draw_set_transform_matrix(t)

			draw_circle(Vector2.ZERO, base_dot_radius, Color.WHITE)

			if pid == hovered_pid:
				var offset = Vector2(10, base_font_size * 0.3) 
				draw_string_outline(_font, offset, province.city, HORIZONTAL_ALIGNMENT_LEFT, -1, base_font_size, 4, Color(0,0,0,0.8))
				draw_string(_font, offset, province.city, HORIZONTAL_ALIGNMENT_LEFT, -1, base_font_size, Color.WHITE)

		# Reset once per province instead of once per wrap-iteration
		draw_set_transform_matrix(Transform2D())
