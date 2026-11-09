extends Node2D
class_name CustomRenderer

# Retained-mode map renderer built on RenderingServer.
#
# Nothing here uses _draw(). Every visual is a RenderingServer canvas item whose
# draw commands are recorded once and kept by the server. Per frame we only move
# items (canvas_item_set_transform) or rewrite a MultiMesh buffer. Commands are
# re-recorded only when what they show changes (division count, selection,
# battle progress, hovered city, ...).
#
# Item tree (all children of this node's canvas item, drawn in this order):
#   _city_roots[0..2]  one per world-wrap copy, each holds the shared city MultiMesh
#   _city_label        hovered city name
#   _troop_root        one child item per troop (+ a detail child for flag/text)
#   _battle_root       one child item per battle
#   _overlay           selection box, path preview, movement lines

# --- Constants & Config ---
const COLORS = {
	"background": Color(0, 0, 0, 0.8),
	"text": Color(1, 1, 1, 1),
	"border_default": Color(0, 1, 0, 1),
	"border_selected": Color(0.8, 0.8, 0.8),
	"border_other": Color(0, 0, 0, 1),
	"movement_active": Color(0, 1, 0, 0.8),
	"path_active": Color(1, 0.2, 0.2),
	"path_inactive": Color(0.5, 0.5, 0.5),
	"city": Color.WHITE,
	"capital": Color.RED,
}

const LAYOUT = {"flag_width": 24.0, "flag_height": 20.0, "min_text_width": 16.0, "font_size": 16}

const ZOOM_LIMITS = {"min_scale": 0.05, "max_scale": 0.5}
const STACKING_OFFSET_Y := 20.0
const TROOP_BORDER := 2.0

# Troops (box, background, flag and text) are hidden while the raw Camera2D zoom
# is below this value. Compare against the raw zoom, not
# _current_inv_zoom: that value is clamped, so it stops changing at zoom <= 2.
const TROOP_DETAIL_MIN_ZOOM := 4.0

const BASE_DOT_RADIUS = 4.0
const DOT_SEGMENTS = 12
const BASE_FONT_SIZE = 24
const OFFSET = Vector2(10, BASE_FONT_SIZE * 0.3)

const BATTLE = {"base_radius": 1.0, "ring_radius": 1.2, "line_width": 0.5, "segments": 16}

# 2D MultiMesh buffer layout: 8 floats transform + 4 floats color.
const MM_STRIDE := 12

# --- Variables ---
var _font: Font = preload("res://font/arial.TTF")
var map_sprite: Sprite2D
var map_width: float = 0.0:
	set(value):
		map_width = value
		_rebuild_cities()

var _current_inv_zoom := 1.0
var _cam_x := 0.0
var _cam_zoom := 1.0 # raw Camera2D zoom, not clamped

var _last_cam_pos := Vector2.INF
var _last_cam_zoom := Vector2.INF

# Cities
var _city_mesh: ArrayMesh
var _city_mm: RID
var _city_roots: Array[RID] = []
var _city_items: Array[RID] = []
var _city_positions: PackedVector2Array = []
var _city_pids: PackedInt32Array = []
var _city_names: PackedStringArray = []
var _city_index_by_pid := {} # pid -> index of its first city
var _city_colors: PackedColorArray = []
var _city_buffer: PackedFloat32Array = []
var _city_colors_dirty := false
var _city_label: RID
var _label_index := -2 # index into _city_* arrays, -1 = none, -2 = force refresh

# Troops: TroopData -> {"item": RID, "detail": RID, "sig": Array}
var _troop_root: RID
var _troop_items := {}

# Battles: battle -> {"item": RID, "sig": Array}
var _battle_root: RID
var _battle_items := {}

# Overlay
var _overlay: RID
var _overlay_had_content := false

var _signals_connected := false


# --- Lifecycle ---
func _ready() -> void:
	z_index = 20 # Keep renderer high
	_create_roots()


# SceneSwitcher caches the world scene and re-adds it to the tree, so RIDs are
# freed only when the node itself is deleted, never in _exit_tree.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_all()


func _process(_delta: float) -> void:
	if !map_sprite or map_width <= 0:
		return

	var cam := get_viewport().get_camera_2d()
	if !cam:
		return

	_connect_signals()
	_cam_x = cam.global_position.x
	_cam_zoom = cam.zoom.x

	var zoom_changed := cam.zoom != _last_cam_zoom
	if zoom_changed or cam.global_position != _last_cam_pos:
		_current_inv_zoom = clamp(1.0 / cam.zoom.x, ZOOM_LIMITS.min_scale, ZOOM_LIMITS.max_scale)
		_last_cam_zoom = cam.zoom
		_last_cam_pos = cam.global_position

	if zoom_changed:
		_write_city_buffer()

	if _city_colors_dirty:
		_refresh_city_colors()

	var peace := GameState.in_peace_process
	# Far zoom hides the whole troop layer: box, background, flag and text together.
	var show_troops := !peace and _cam_zoom >= TROOP_DETAIL_MIN_ZOOM
	RenderingServer.canvas_item_set_visible(_troop_root, show_troops)
	RenderingServer.canvas_item_set_visible(_battle_root, !peace)

	_update_city_label()
	if show_troops:
		_update_troops()
	if !peace:
		_update_battles()
	_update_overlay(peace)


# --- Setup / teardown ---
func _create_roots() -> void:
	var parent := get_canvas_item()
	var draw_index := 0

	for m in range(-1, 2):
		var root := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(root, parent)
		RenderingServer.canvas_item_set_draw_index(root, draw_index)
		_city_roots.append(root)
		draw_index += 1

	_city_label = _make_child(parent, draw_index); draw_index += 1
	_troop_root = _make_child(parent, draw_index); draw_index += 1
	_battle_root = _make_child(parent, draw_index); draw_index += 1
	_overlay = _make_child(parent, draw_index)

	_city_mm = RenderingServer.multimesh_create()
	_city_mesh = _build_dot_mesh(BASE_DOT_RADIUS, DOT_SEGMENTS)
	RenderingServer.multimesh_set_mesh(_city_mm, _city_mesh.get_rid())


func _make_child(parent: RID, draw_index: int) -> RID:
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, parent)
	RenderingServer.canvas_item_set_draw_index(item, draw_index)
	return item


func _free_all() -> void:
	for entry in _troop_items.values():
		_free_troop_entry(entry)
	_troop_items.clear()
	for entry in _battle_items.values():
		RenderingServer.free_rid(entry.item)
	_battle_items.clear()
	for item in _city_items:
		RenderingServer.free_rid(item)
	_city_items.clear()
	for rid in _city_roots + [_city_label, _troop_root, _battle_root, _overlay, _city_mm]:
		if rid.is_valid():
			RenderingServer.free_rid(rid)
	_city_roots.clear()


func _connect_signals() -> void:
	if _signals_connected:
		return
	_signals_connected = true
	MapManager.province_ownership_changed.connect(_on_province_ownership_changed)
	CountryManager.player_country_changed.connect(_on_player_country_changed)
	if GameState.current_world and GameState.current_world.clock:
		GameState.current_world.clock.day_passed.connect(_on_day_passed)


func _on_province_ownership_changed(_pid: int, _old_owner: String, _new_owner: String) -> void:
	_city_colors_dirty = true


func _on_day_passed() -> void:
	# Capitals can move through decisions/events; recheck once per day.
	_city_colors_dirty = true


func _on_player_country_changed() -> void:
	# Border colors depend on the player country; force every troop to re-record.
	for entry in _troop_items.values():
		entry.sig = []
	for entry in _battle_items.values():
		entry.sig = []


# --- Cities ---
func _build_dot_mesh(radius: float, segments: int) -> ArrayMesh:
	var verts := PackedVector2Array()
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		verts.append(Vector2.ZERO)
		verts.append(Vector2.from_angle(a0) * radius)
		verts.append(Vector2.from_angle(a1) * radius)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Collects city data and (re)allocates the city MultiMesh.
## Runs whenever World sets map_width, i.e. on every map load.
func _rebuild_cities() -> void:
	if !_city_mm.is_valid() or !map_sprite or map_width <= 0:
		return

	_city_positions.clear()
	_city_pids.clear()
	_city_names.clear()
	_city_index_by_pid.clear()
	for city_data in MapManager.all_cities:
		var pid: int = city_data["id"]
		var pos: Vector2 = MapManager.province_centers.get(pid, Vector2.ZERO)
		if pos == Vector2.ZERO:
			continue
		if !_city_index_by_pid.has(pid):
			_city_index_by_pid[pid] = _city_positions.size()
		_city_positions.append(pos)
		_city_pids.append(pid)
		_city_names.append(city_data["city"])

	var count := _city_positions.size()
	RenderingServer.multimesh_allocate_data(_city_mm, count, RenderingServer.MULTIMESH_TRANSFORM_2D, true)
	_city_buffer.resize(count * MM_STRIDE)
	_city_colors.resize(count)

	# One item per wrap copy, all drawing the same MultiMesh.
	for item in _city_items:
		RenderingServer.free_rid(item)
	_city_items.clear()
	for m in range(-1, 2):
		var root := _city_roots[m + 1]
		RenderingServer.canvas_item_set_transform(root, Transform2D(0, map_sprite.position + Vector2(map_width * m, 0)))
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, root)
		RenderingServer.canvas_item_add_multimesh(item, _city_mm)
		_city_items.append(item)

	_compute_city_colors()
	_write_city_buffer()
	_label_index = -2


func _compute_city_colors() -> void:
	for i in _city_pids.size():
		var province = MapManager.province_objects.get(_city_pids[i])
		var country = CountryManager.countries.get(province.country) if province else null
		var is_capital: bool = country != null and country.capital == _city_names[i]
		_city_colors[i] = COLORS.capital if is_capital else COLORS.city


func _refresh_city_colors() -> void:
	_city_colors_dirty = false
	_compute_city_colors()
	_write_city_buffer()
	_label_index = -2


## Writes transforms (scaled by inverse zoom) and colors in one call.
func _write_city_buffer() -> void:
	var count := _city_positions.size()
	if count == 0:
		return
	var s := _current_inv_zoom
	var b := _city_buffer
	for i in count:
		var o := i * MM_STRIDE
		var p := _city_positions[i]
		var c := _city_colors[i]
		b[o] = s;    b[o + 1] = 0.0; b[o + 2] = 0.0; b[o + 3] = p.x
		b[o + 4] = 0.0; b[o + 5] = s; b[o + 6] = 0.0; b[o + 7] = p.y
		b[o + 8] = c.r; b[o + 9] = c.g; b[o + 10] = c.b; b[o + 11] = c.a
	RenderingServer.multimesh_set_buffer(_city_mm, b)


func _update_city_label() -> void:
	var hovered := MapManager.current_hovered_pid
	var index: int = _city_index_by_pid.get(hovered, -1)

	if index != _label_index:
		_label_index = index
		RenderingServer.canvas_item_clear(_city_label)
		if index >= 0:
			var city_name := _city_names[index]
			_font.draw_string_outline(_city_label, OFFSET, city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, BASE_FONT_SIZE, 4, Color(0, 0, 0, 1.0))
			_font.draw_string(_city_label, OFFSET, city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, BASE_FONT_SIZE, _city_colors[index])

	if _label_index >= 0:
		var pos := _wrap_nearest(_city_positions[_label_index] + map_sprite.position)
		RenderingServer.canvas_item_set_transform(_city_label, Transform2D(0, Vector2(_current_inv_zoom, _current_inv_zoom), 0, pos))


# --- Troops ---
func _update_troops() -> void:
	var player_country := _player_country_name()
	var selected: Array = TroopManager.troop_selection.selected_troops if TroopManager.troop_selection else []

	# Create items for new troops, free items of removed troops.
	var alive := {}
	for troop in TroopManager.troops:
		alive[troop] = true
		if !_troop_items.has(troop):
			var item := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(item, _troop_root)
			var detail := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(detail, item)
			_troop_items[troop] = {"item": item, "detail": detail, "sig": []}
	for troop in _troop_items.keys():
		if !alive.has(troop):
			_free_troop_entry(_troop_items[troop])
			_troop_items.erase(troop)

	var zoom_vec := Vector2(_current_inv_zoom, _current_inv_zoom)
	var scaled_offset := STACKING_OFFSET_Y * _current_inv_zoom
	var groups := _group_troops_by_visual_position(TroopManager.troops)

	for base_pos in groups:
		var stack: Array = groups[base_pos]
		var start_y := (stack.size() - 1) * scaled_offset * 0.5
		for i in stack.size():
			var troop: TroopData = stack[i]
			var entry: Dictionary = _troop_items[troop]

			var border: Color = COLORS.border_other
			if troop.country_name == player_country:
				border = COLORS.border_selected if selected.has(troop) else COLORS.border_default
			var ideology: String = troop.country_obj.ideology_name if troop.country_obj else ""
			var sig := [troop.divisions_count, border, troop.country_name, ideology]
			if sig != entry.sig:
				entry.sig = sig
				_record_troop(entry, troop, border, ideology)

			var pos: Vector2 = base_pos + map_sprite.position + Vector2(0, start_y - i * scaled_offset)
			RenderingServer.canvas_item_set_transform(entry.item, Transform2D(0, zoom_vec, 0, _wrap_nearest(pos)))


func _record_troop(entry: Dictionary, troop: TroopData, border: Color, ideology: String) -> void:
	var item: RID = entry.item
	var detail: RID = entry.detail
	var w: float = LAYOUT.flag_width + LAYOUT.min_text_width
	var h: float = LAYOUT.flag_height
	var rect := Rect2(-w * 0.5, -h * 0.5, w, h)

	# Box: border strips.
	RenderingServer.canvas_item_clear(item)
	var b := TROOP_BORDER
	RenderingServer.canvas_item_add_rect(item, Rect2(rect.position, Vector2(w, b)), border)
	RenderingServer.canvas_item_add_rect(item, Rect2(rect.position + Vector2(0, h - b), Vector2(w, b)), border)
	RenderingServer.canvas_item_add_rect(item, Rect2(rect.position + Vector2(0, b), Vector2(b, h - 2 * b)), border)
	RenderingServer.canvas_item_add_rect(item, Rect2(rect.position + Vector2(w - b, b), Vector2(b, h - 2 * b)), border)

	# Detail: translucent inner fill + flag + division count.
	RenderingServer.canvas_item_clear(detail)
	RenderingServer.canvas_item_add_rect(detail, rect.grow(-b), COLORS.background)
	var flag := TroopManager.get_flag(troop.country_name, ideology)
	if flag:
		flag.draw_rect(detail, Rect2(rect.position, Vector2(LAYOUT.flag_width, h)).grow(-1.0), false)

	var label := str(troop.divisions_count)
	var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LAYOUT.font_size)
	_font.draw_string(
		detail,
		Vector2(rect.position.x + LAYOUT.flag_width + (LAYOUT.min_text_width - text_size.x) * 0.5, text_size.y * 0.3),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		LAYOUT.font_size,
		COLORS.text
	)


func _free_troop_entry(entry: Dictionary) -> void:
	RenderingServer.free_rid(entry.detail)
	RenderingServer.free_rid(entry.item)


func _group_troops_by_visual_position(troops: Array) -> Dictionary:
	var g = {}
	for t in troops:
		# Get interpolated position if moving, else static position
		var visual_pos = t.position.lerp(t.target_position, t.get_meta("progress", 0.0)) if t.is_moving else t.position

		if !g.has(visual_pos):
			g[visual_pos] = []
		g[visual_pos].append(t)
	return g


# --- Battles ---
func _update_battles() -> void:
	var player_country := _player_country_name() if !GameState.selectingCountry else ""

	var alive := {}
	for battle in WarManager.active_battles:
		if !battle:
			continue
		alive[battle] = true
		var entry: Dictionary = _battle_items.get(battle, {})
		if entry.is_empty():
			var item := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(item, _battle_root)
			entry = {"item": item, "sig": []}
			_battle_items[battle] = entry

		var sig := [battle.attack_progress, battle.attacker_country, battle.defender_country, player_country]
		if sig != entry.sig:
			entry.sig = sig
			_record_battle(entry.item, battle, player_country)

		RenderingServer.canvas_item_set_transform(entry.item, Transform2D(0, _wrap_nearest(battle.position)))

	for battle in _battle_items.keys():
		if !alive.has(battle):
			RenderingServer.free_rid(_battle_items[battle].item)
			_battle_items.erase(battle)


func _record_battle(item: RID, battle, player_country: String) -> void:
	var is_player_involved := false
	var is_winning := true
	var display_ratio: float = battle.attack_progress

	if battle.attacker_country == player_country:
		is_player_involved = true
		is_winning = display_ratio > 0.5
	elif battle.defender_country == player_country:
		is_player_involved = true
		display_ratio = 1.0 - display_ratio
		is_winning = display_ratio > 0.5

	var color := Color(0.8, 0.5, 0.0)
	if is_player_involved:
		color = Color(0.0, 1.0, 0.0) if is_winning else Color(1.0, 0.0, 0.0)

	var start_angle := -PI * 0.5 # Top
	var end_angle := start_angle
	if is_winning:
		end_angle += display_ratio * TAU
	else:
		start_angle -= display_ratio * TAU

	RenderingServer.canvas_item_clear(item)
	# Dark backing circle so the tiny icon stands out.
	RenderingServer.canvas_item_add_circle(item, Vector2.ZERO, BATTLE.ring_radius + 0.3, Color(0, 0, 0, 0.8))
	# Progress arc (RenderingServer has no arc primitive, so build a polyline).
	if !is_equal_approx(start_angle, end_angle):
		var points := PackedVector2Array()
		for i in BATTLE.segments + 1:
			points.append(Vector2.from_angle(lerpf(start_angle, end_angle, float(i) / BATTLE.segments)) * BATTLE.ring_radius)
		RenderingServer.canvas_item_add_polyline(item, points, PackedColorArray([color]), BATTLE.line_width, true)
	RenderingServer.canvas_item_add_circle(item, Vector2.ZERO, BATTLE.base_radius, Color.WHITE)


# --- Overlay (selection box, path preview, movement lines) ---
func _update_overlay(peace: bool) -> void:
	var ts = TroopManager.troop_selection
	var any_moving := false
	if !peace:
		for troop in TroopManager.troops:
			if troop.is_moving:
				any_moving = true
				break

	var has_content: bool = !peace and ts != null and (ts.dragging or ts.right_dragging or any_moving)
	if !has_content and !_overlay_had_content:
		return # Nothing drawn last frame and nothing to draw now.
	_overlay_had_content = has_content

	RenderingServer.canvas_item_clear(_overlay)
	if !has_content:
		return

	_record_path_preview(ts)
	if any_moving:
		_record_active_movements()
	_record_selection_box(ts)


func _record_selection_box(ts) -> void:
	if !ts.dragging or ts.drag_start == ts.drag_end:
		return
	var rect := Rect2(ts.drag_start, ts.drag_end - ts.drag_start).abs()
	RenderingServer.canvas_item_add_rect(_overlay, rect, Color(1, 1, 1, 0.3))
	var outline := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position])
	RenderingServer.canvas_item_add_polyline(_overlay, outline, PackedColorArray([Color.WHITE]), 1.0)


func _record_path_preview(ts) -> void:
	if !ts.right_dragging:
		return
	var path = ts.right_path
	var max_len = ts.max_path_length

	if path.size() < 2:
		if path.size() == 1:
			RenderingServer.canvas_item_add_circle(_overlay, path[0]["map_pos"] + map_sprite.position, 2.0, COLORS.path_active if max_len > 0 else COLORS.path_inactive)
		return

	var active_points := PackedVector2Array()
	var inactive_points := PackedVector2Array()

	for i in path.size():
		var p: Vector2 = path[i]["map_pos"] + map_sprite.position
		if i <= max_len:
			active_points.append(p)
			# The connection point between active and inactive needs to be in both
			if i == max_len and i < path.size() - 1:
				inactive_points.append(p)
		else:
			inactive_points.append(p)

	if active_points.size() >= 2:
		RenderingServer.canvas_item_add_polyline(_overlay, active_points, PackedColorArray([COLORS.path_active]), 1.5)
	if inactive_points.size() >= 2:
		RenderingServer.canvas_item_add_polyline(_overlay, inactive_points, PackedColorArray([COLORS.path_inactive]), 1.5)


func _record_active_movements() -> void:
	for troop in TroopManager.troops:
		if !troop.is_moving:
			continue
		var start: Vector2 = _wrap_nearest(troop.position + map_sprite.position)
		var end: Vector2 = start + (troop.target_position - troop.position)
		RenderingServer.canvas_item_add_line(_overlay, start, end, Color(1, 0, 0, 0.2), 1.0)
		RenderingServer.canvas_item_add_line(_overlay, start, start.lerp(end, troop.get_meta("visual_progress", 0.0)), COLORS.movement_active, 1.5)


# --- Helpers ---
## Picks the world-wrap copy of a position closest to the camera.
## Correct while the visible area is narrower than one map width.
func _wrap_nearest(p: Vector2) -> Vector2:
	p.x += round((_cam_x - p.x) / map_width) * map_width
	return p


func _player_country_name() -> String:
	return CountryManager.player_country.country_name if CountryManager.player_country else ""
