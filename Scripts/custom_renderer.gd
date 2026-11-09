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

const LAYOUT = {"flag_width": 24.0, "flag_height": 20.0, "min_text_width": 16.0, "font_size": 16}

const ZOOM_LIMITS = {"min_scale": 0.05, "max_scale": 0.5}
const STACKING_OFFSET_Y := 20.0

const BASE_DOT_RADIUS = 4.0
const BASE_FONT_SIZE = 24
const OFFSET = Vector2(10, BASE_FONT_SIZE * 0.3)


# --- Variables ---
var _font: Font = preload("res://font/arial.TTF")
var map_sprite: Sprite2D
var map_width: float = 0.0
var _current_inv_zoom := 1.0
var _screen_rect: Rect2
var _citiesRID: Array[RID] = []

# Reference to the GPU node
var troop_multimesh: MultiMeshInstance2D

var _last_cam_pos := Vector2.INF
var _last_cam_zoom := Vector2.INF


# --- Lifecycle ---
func _ready() -> void:
	z_index = 20 # Keep renderer high
	_setup_multimesh()

func _process(_delta: float) -> void:
	if !map_sprite:
		return

	var cam := get_viewport().get_camera_2d()
	if !cam:
		return

	if cam.zoom != _last_cam_zoom || cam.global_position != _last_cam_pos:
		_current_inv_zoom = clamp(1.0 / cam.zoom.x, ZOOM_LIMITS.min_scale, ZOOM_LIMITS.max_scale)

		_update_screen_rect()

		_last_cam_zoom = cam.zoom
		_last_cam_pos = cam.global_position

	_update_multimesh_buffer()

	# queue_redraw()


# --- MultiMesh Setup ---
func _setup_multimesh():
	if !troop_multimesh:
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
	if !map_sprite || map_width <= 0 || !troop_multimesh:
		return

	var mm = troop_multimesh.multimesh
	var needed = TroopManager.troops.size() * 3

	if mm.instance_count != needed:
		mm.instance_count = needed

	var player_country = CountryManager.player_country.country_name
	var selected_troops = TroopManager.troop_selection.selected_troops
	var groups = _group_troops_by_visual_position(TroopManager.troops)
	var idx = 0
	var zoom_vec = Vector2(_current_inv_zoom, _current_inv_zoom)
	var scaled_offset := STACKING_OFFSET_Y * _current_inv_zoom

	for base_pos in groups:
		var stack = groups[base_pos]
		var start_y = (stack.size() - 1) * scaled_offset * 0.5

		for i in range(stack.size()):
			var troop = stack[i]
			var pos = base_pos + Vector2(0, start_y - (i * scaled_offset))

			# Logic for colors
			var col = (COLORS.border_selected if selected_troops.has(troop) else COLORS.border_default) if troop.country_name == player_country else COLORS.border_other

			for m in range(-1, 2):
				if idx >= mm.instance_count:
					break

				mm.set_instance_transform_2d(idx, Transform2D(0, zoom_vec, 0, pos + Vector2(map_width * m, 0) + map_sprite.position))
				mm.set_instance_color(idx, col)
				idx += 1


func _draw() -> void:
	if !map_sprite or map_width <= 0:
		return
	if !GameState.in_peace_process:
		_draw_path_preview()
		_draw_active_movements()
		_draw_selection_box()
		_draw_troops()
		
	troop_multimesh.visible = !GameState.in_peace_process
	
	_draw_cities()
	if !GameState.in_peace_process:
		draw_battles()


func _draw_troops() -> void:
	if _current_inv_zoom >= 0.5:
		return # LOD optimization

	# Use the same grouping logic but account for movement
	var groups: Dictionary = _group_troops_by_visual_position(TroopManager.troops)
	var scaled_offset: float = STACKING_OFFSET_Y * _current_inv_zoom

	for base_pos in groups:
		var stack = groups[base_pos]
		var start_y: float = (stack.size() - 1) * scaled_offset * 0.5

		for i in range(stack.size()):
			var troop = stack[i]
			# Calculate position including world-wrapping (m)
			var vertical_stack_pos = base_pos + Vector2(0, start_y - (i * scaled_offset))

			for m in range(-1, 2):
				var d_pos = vertical_stack_pos + Vector2(map_width * m, 0) + map_sprite.position
				if _screen_rect.has_point(d_pos):
					_draw_troop(troop, d_pos)


func _draw_troop(troop: TroopData, pos: Vector2) -> void:
	draw_set_transform_matrix(Transform2D(0, Vector2(_current_inv_zoom, _current_inv_zoom), 0, pos))
	
	var top_left = Vector2(- (LAYOUT.flag_width + LAYOUT.min_text_width) * 0.5, -LAYOUT.flag_height * 0.5)

	# Draw Text (Right side)
	var label = str(troop.divisions_count)
	# Use the base font size; the transform handles the zoom-scaling for us!
	var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, LAYOUT.font_size)

	# Position text relative to the flag's right edge

	TroopManager.get_flag(
		troop.country_name,
		troop.country_obj.ideology_name if troop.country_obj else ""
	).draw_rect(
		get_canvas_item(),
		Rect2(
			top_left,
			Vector2(
				LAYOUT.flag_width,
				LAYOUT.flag_height
			)
		).grow(-1),
		false,
	)

	_font.draw_string(
		get_canvas_item(),
		Vector2(
			top_left.x + LAYOUT.flag_width + (LAYOUT.min_text_width - text_size.x) * 0.5,
			text_size.y * 0.3
		),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		LAYOUT.font_size,
		COLORS.text
	)

	# 3. Reset transform so other things draw correctly
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _group_troops_by_visual_position(troops: Array) -> Dictionary:
	var g = {}
	for t in troops:
		# Get interpolated position if moving, else static position
		var visual_pos = t.position.lerp(t.target_position, t.get_meta("progress", 0.0)) if t.is_moving else t.position

		if !g.has(visual_pos):
			g[visual_pos] = []
		g[visual_pos].append(t)
	return g


func _draw_selection_box() -> void:
	if !TroopManager.troop_selection.dragging:
		return
	var ts = TroopManager.troop_selection
	if ts.drag_start != ts.drag_end:
		var rect = Rect2(ts.drag_start, ts.drag_end - ts.drag_start).abs()
		draw_rect(rect, Color(1, 1, 1, 0.3), true)
		draw_rect(rect, Color(1, 1, 1, 1), false, 1.0)


func _draw_path_preview() -> void:
	if !TroopManager.troop_selection.right_dragging:
		return
	var path = TroopManager.troop_selection.right_path
	var max_len = TroopManager.troop_selection.max_path_length
	
	if path.size() < 2:
		if path.size() == 1:
			draw_circle(path[0]["map_pos"] + map_sprite.position, 2.0, COLORS.path_active if max_len > 0 else COLORS.path_inactive)
		return

	var active_points: PackedVector2Array = []
	var inactive_points: PackedVector2Array = []
	
	for i in range(path.size()):
		var p = path[i]["map_pos"] + map_sprite.position
		if i <= max_len:
			active_points.append(p)
			# The connection point between active and inactive needs to be in both
			if i == max_len && i < path.size() - 1:
				inactive_points.append(p)
		else:
			inactive_points.append(p)

	if active_points.size() >= 2:
		draw_polyline(active_points, COLORS.path_active, 1.5)
	
	if inactive_points.size() >= 2:
		draw_polyline(inactive_points, COLORS.path_inactive, 1.5)


func _draw_active_movements() -> void:
	for troop in TroopManager.troops:
		if !troop.is_moving:
			continue
		var start = troop.position + map_sprite.position
		var end = troop.target_position + map_sprite.position
		if _screen_rect.has_point(start) || _screen_rect.has_point(end):
			draw_line(start, end, Color(1, 0, 0, 0.2), 1.0)
			draw_line(start, start.lerp(end, troop.get_meta("visual_progress", 0.0)), COLORS.movement_active, 1.5)


func _update_screen_rect():
	var canvas_xform := get_canvas_transform()

	_screen_rect = Rect2(
		- canvas_xform.origin / canvas_xform.get_scale(),
		get_viewport_rect().size / canvas_xform.get_scale()
	).grow(200.0)


func _record_cities() -> void:
	for city_data in MapManager.all_cities:
		var pid = city_data["id"]
		var city_name = city_data["city"]
		var base_pos = MapManager.province_centers[pid]
		var color: Color = Color.RED if CountryManager.countries[MapManager.province_objects[pid].country].capital == city_name else Color.WHITE 
		var cityRID = RenderingServer.canvas_item_create()
		_citiesRID.append(cityRID)
		RenderingServer.canvas_item_set_parent(cityRID, get_canvas_item())
		RenderingServer.canvas_item_add_circle(
			cityRID,
			base_pos + map_sprite.position,
			BASE_DOT_RADIUS * _current_inv_zoom,
			color,
		)


func _draw_cities() -> void:
	var hovered_pid = MapManager.current_hovered_pid
	var zoom_vec = Vector2(_current_inv_zoom, _current_inv_zoom)

	var _transform = Transform2D(0, zoom_vec, 0, Vector2(0, 0))
	for cityRID in _citiesRID:
		RenderingServer.canvas_item_set_transform(
			cityRID,
			_transform
		)

	for city_data in MapManager.all_cities:
		var pid = city_data["id"]
		var city_name = city_data["city"]
		var base_pos = MapManager.province_centers[pid]
		var color: Color = Color.RED if CountryManager.countries[MapManager.province_objects[pid].country].capital == city_name else Color.WHITE 

		if base_pos == Vector2.ZERO:
			continue

		RenderingServer.canvas_item_add_circle(
			get_canvas_item(),
			base_pos + map_sprite.position,
			BASE_DOT_RADIUS * _current_inv_zoom,
			color,
		)

		for j in range(-1, 2):
			var world_pos = base_pos + Vector2(map_width * j, 0)
			if !_screen_rect.has_point(world_pos):
				continue

			if pid == hovered_pid:
				_font.draw_string_outline(
					get_canvas_item(),
					OFFSET,
					city_name,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					BASE_FONT_SIZE,
					4,
					Color(0, 0, 0, 1.0),
				)
				_font.draw_string(
					get_canvas_item(),
					OFFSET,
					city_name,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					BASE_FONT_SIZE,
					color,
				)


func draw_battles():
	var player_country = CountryManager.player_country.country_name if !GameState.selectingCountry else ""
	const base_radius = 1.0
	const ring_radius = 1.2
	const line_width = 0.5
	const START_ANGLE = -PI * 0.5 # Top
	var start_angle: float
	var end_angle: float
	var pos: Vector2
	var is_player_involved: bool
	var is_winning: bool
	var display_ratio: float

	for battle in WarManager.active_battles:
		if !battle:
			continue

		pos = battle.position

		# 1. Determine Win/Loss relative to player
		is_player_involved = false
		is_winning = true
		display_ratio = battle.attack_progress

		if battle.attacker_country == player_country:
			is_player_involved = true
			is_winning = display_ratio > 0.5
		elif battle.defender_country == player_country:
			is_player_involved = true
			display_ratio = 1.0 - display_ratio
			is_winning = display_ratio > 0.5

		# 4. Draw Background/Outline (Crucial for tiny icons)
		# We draw a slightly larger black circle first so the icon "pops"
		draw_circle(pos, ring_radius + 0.3, Color(0, 0, 0, 0.8))

		# 5. Draw Progress Arc
		start_angle = START_ANGLE
		end_angle = START_ANGLE
		if is_winning:
			end_angle += display_ratio * TAU
		else:
			start_angle -= display_ratio * TAU
		draw_arc(pos, ring_radius, start_angle, end_angle, 16, (Color(0.0, 1.0, 0.0) if is_winning else Color(1.0, 0.0, 0.0)) if is_player_involved else Color(0.8, 0.5, 0.0), line_width, true)

		# 6. Static Center White Dot (No Pulse)
		draw_circle(pos, base_radius, Color.WHITE)
