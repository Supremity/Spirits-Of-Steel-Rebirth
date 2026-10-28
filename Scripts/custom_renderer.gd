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

# Cities live on their own canvas item so they only get redrawn when something about them changes,
# instead of every frame with the troops.
const CITY_REFRESH_FRAMES := 30 # Fallback refresh to pick up capital changes
var _city_layer: Node2D
var _city_dirty := true
var _city_last_hovered := -1
var _city_frames_since_redraw := 0

# Battles get their own layer too. They're drawn in map space with no zoom scaling,
# so camera movement never needs a redraw; only battle progress does.
var _battle_layer: Node2D
var _battle_last_count := -1
var _battle_frames_since_redraw := 0


# --- Lifecycle ---
func _ready() -> void:
	z_index = 20 # Keep renderer high
	_setup_multimesh()

	_city_layer = Node2D.new()
	_city_layer.name = "CityLayer"
	add_child(_city_layer)
	_city_layer.draw.connect(_draw_cities)

	# Added after the city layer so battles draw on top of cities
	_battle_layer = Node2D.new()
	_battle_layer.name = "BattleLayer"
	add_child(_battle_layer)
	_battle_layer.draw.connect(draw_battles)
	MapManager.province_ownership_changed.connect(_on_province_ownership_changed)


func _on_province_ownership_changed(_pid: int, _old_owner: String, _new_owner: String) -> void:
	_city_dirty = true


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
		_city_dirty = true

	_update_multimesh_buffer()

	queue_redraw()

	_city_frames_since_redraw += 1
	if (_city_dirty
		|| MapManager.current_hovered_pid != _city_last_hovered
		|| _city_frames_since_redraw >= CITY_REFRESH_FRAMES):
		_city_dirty = false
		_city_last_hovered = MapManager.current_hovered_pid
		_city_frames_since_redraw = 0
		_city_layer.queue_redraw()

	_battle_layer.visible = !GameState.in_peace_process
	var battle_count: int = WarManager.active_battles.size()
	var clock_running: bool = GameState.current_world && !GameState.current_world.clock.paused
	_battle_frames_since_redraw += 1
	if (battle_count != _battle_last_count
		|| (battle_count > 0 && clock_running)
		|| _battle_frames_since_redraw >= CITY_REFRESH_FRAMES):
		_battle_last_count = battle_count
		_battle_frames_since_redraw = 0
		_battle_layer.queue_redraw()


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

	var player_country = CountryManager.player_country.country_name if CountryManager.player_country else ""
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


func _draw_troops() -> void:
	if _current_inv_zoom > 1.5:
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

	draw_texture_rect(
		TroopManager.get_flag(
			troop.country_name,
			troop.country_obj.ideology_name if troop.country_obj else ""
		),
		Rect2(
			top_left,
			Vector2(
				LAYOUT.flag_width,
				LAYOUT.flag_height
			)
		).grow(-1.0),
		false
	)

	draw_string(
		_font,
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


# Drawn onto _city_layer (connected to its draw signal), not onto the renderer itself.
func _draw_cities() -> void:
	if !MapManager.id_map_image or !map_sprite or map_width <= 0:
		return

	var hovered_pid = MapManager.current_hovered_pid
	const base_dot_radius = 4.0
	const base_font_size = 24
	const offset = Vector2(10, base_font_size * 0.3)

	var dot_radius := base_dot_radius * _current_inv_zoom
	var sprite_pos := map_sprite.position
	var wrap_offsets := [Vector2(-map_width, 0), Vector2.ZERO, Vector2(map_width, 0)]

	for city_data in MapManager.all_cities:
		var pid = city_data["id"]
		var base_pos: Vector2 = MapManager.province_centers.get(pid, Vector2.ZERO)
		if base_pos == Vector2.ZERO:
			continue
		base_pos += sprite_pos

		for wrap in wrap_offsets:
			var world_pos: Vector2 = base_pos + wrap
			# Cull before doing any lookups
			if !_screen_rect.has_point(world_pos):
				continue

			var city_name: String = city_data["city"]
			# Owner may have been removed from countries (dead/annexed) while the province still points at it
			var province = MapManager.province_objects.get(pid)
			var city_owner: CountryData = CountryManager.countries.get(province.country) if province else null
			var color: Color = Color.RED if city_owner and city_owner.capital == city_name else Color.WHITE

			_city_layer.draw_circle(world_pos, dot_radius, color)

			if pid == hovered_pid:
				_city_layer.draw_set_transform_matrix(Transform2D(0, Vector2(_current_inv_zoom, _current_inv_zoom), 0, world_pos))
				_city_layer.draw_string_outline(
					_font,
					offset,
					city_name,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					base_font_size,
					4,
					Color(0, 0, 0, 0.8)
				)
				_city_layer.draw_string(
					_font,
					offset,
					city_name,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					base_font_size,
					color
				)
				_city_layer.draw_set_transform_matrix(Transform2D.IDENTITY)


# Drawn onto _battle_layer (connected to its draw signal), not onto the renderer itself.
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
		_battle_layer.draw_circle(pos, ring_radius + 0.3, Color(0, 0, 0, 0.8))

		# 5. Draw Progress Arc
		start_angle = START_ANGLE
		end_angle = START_ANGLE
		if is_winning:
			end_angle += display_ratio * TAU
		else:
			start_angle -= display_ratio * TAU
		_battle_layer.draw_arc(pos, ring_radius, start_angle, end_angle, 16, (Color(0.0, 1.0, 0.0) if is_winning else Color(1.0, 0.0, 0.0)) if is_player_involved else Color(0.8, 0.5, 0.0), line_width, true)

		# 6. Static Center White Dot (No Pulse)
		_battle_layer.draw_circle(pos, base_radius, Color.WHITE)
