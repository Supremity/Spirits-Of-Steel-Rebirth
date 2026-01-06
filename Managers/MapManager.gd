extends Node

# NOTE(pol): Both are only used to update the UI
signal province_hovered(province_id: int, country_name: String)
signal province_clicked(province_id: int, country_name: String)

signal map_ready()

# Emitted when a click couldn't be processed (so likely sea or border)
signal close_sidemenu
# --- CONSTANTS ---
const GRID_COLOR_THRESHOLD = 0.001 

# The exact colors you provided
const SEA_MAIN   = Color("#7e8e9e")
const SEA_RASTER = Color("#697684") 

# --- DATA ---
var id_map_image: Image
var state_color_image: Image
var state_color_texture: ImageTexture
var max_province_id: int = 0


var color_to_pop_map: Dictionary = {} # Stores {"(0, 10, 255)": 764}

var province_to_country: Dictionary = {}
var country_to_provinces: Dictionary = {}
var province_objects: Dictionary = {} 


var last_hovered_pid: int = -1
var original_hover_color: Color
var province_centers: Dictionary = {} # Stores {ID: Vector2(x, y)}
var adjacency_list: Dictionary = {} # Stores {ID: [Neighbor_ID_1, Neighbor_ID_2, ...]}	

const MAP_DATA_PATH = "res://map_data/MapData.tres"
const CACHE_FOLDER = "res://map_data/"

@export var region_texture: Texture2D
@export var culture_texture: Texture2D
@export var population_texture: Texture2D

func _ready() -> void:
	_load_country_colors()
	_load_population_json()

	var dir = DirAccess.open("res://")
	if dir and not dir.dir_exists(CACHE_FOLDER):
		dir.make_dir_recursive(CACHE_FOLDER)

	if _try_load_cached_data():
		print("MapManager: Loaded cached data with Province Objects.")
		map_ready.emit()
		return

	var region = region_texture if region_texture else preload("res://maps/regions.png")
	var culture = culture_texture if culture_texture else preload("res://maps/cultures.png")
	var population = population_texture if population_texture else preload("res://maps/population_color_map.png")

	_generate_and_save.call_deferred(region, culture, population)

func _generate_and_save(region: Texture2D, culture: Texture2D, population: Texture2D) -> void:
	initialize_map(region, culture, population)

	var map_data := MapData.new()
	map_data.province_centers = province_centers.duplicate()
	map_data.adjacency_list = adjacency_list.duplicate(true)
	map_data.province_to_country = province_to_country.duplicate()
	map_data.country_to_provinces = country_to_provinces.duplicate()
	map_data.max_province_id = max_province_id
	map_data.id_map_image = id_map_image.duplicate()
	map_data.province_objects = province_objects.duplicate()

	ResourceSaver.save(map_data, MAP_DATA_PATH)
	map_ready.emit()

func _try_load_cached_data() -> bool:
	if not ResourceLoader.exists(MAP_DATA_PATH): return false
	var loaded = ResourceLoader.load(MAP_DATA_PATH) as MapData
	if not loaded: return false

	province_centers = loaded.province_centers
	adjacency_list = loaded.adjacency_list
	province_to_country = loaded.province_to_country
	country_to_provinces = loaded.country_to_provinces
	max_province_id = loaded.max_province_id
	id_map_image = loaded.id_map_image
	province_objects = loaded.province_objects

	_build_lookup_texture()
	return true

func initialize_map(region_tex: Texture2D, culture_tex: Texture2D, population_tex: Texture2D) -> void:
	var r_img = region_tex.get_image()
	var c_img = culture_tex.get_image()
	var p_img = population_tex.get_image()
	
	var w = r_img.get_width()
	var h = r_img.get_height()
	
	# Safety check for the crash you saw
	var pw = p_img.get_width()
	var ph = p_img.get_height()

	id_map_image = Image.create(w, h, false, Image.FORMAT_RGB8)
	var unique_regions = {}
	var next_id = 2 

	for y in range(h):
		for x in range(w):
			var c_color = c_img.get_pixel(x, y)
			if _is_sea(c_color):
				_write_id(x, y, 0)
				continue

			var r_color = r_img.get_pixel(x, y)
			if r_color.r < GRID_COLOR_THRESHOLD and r_color.g < GRID_COLOR_THRESHOLD and r_color.b < GRID_COLOR_THRESHOLD:
				_write_id(x, y, 1)
				continue

			var key = r_color.to_html(false)
			if not unique_regions.has(key):
				unique_regions[key] = next_id
				
				var province = Province.new()
				province.id = next_id
				province.country = _identify_country(c_color)
				
				# Use MIN to prevent index errors even if images differ by 1 pixel
				var p_color = p_img.get_pixel(min(x, pw-1), min(y, ph-1))
				province.population = _get_pop_from_color(p_color)
				
				province_objects[next_id] = province
				province_to_country[next_id] = province.country
				next_id += 1

			_write_id(x, y, unique_regions[key])

	max_province_id = next_id - 1
	_calculate_province_centroids() 
	_build_country_to_provinces()
	_build_adjacency_list() 
	_build_lookup_texture()

func draw_province_centroids(image: Image, color: Color = Color(0,1,0,1)) -> void:
	if not image:
		push_warning("No Image provided for drawing centroids!")
		return

	for pid in province_centers.keys():
		var center = province_centers[pid]
		var x = int(round(center.x))
		var y = int(round(center.y))

		# stay inside bounds
		if x >= 0 and x < image.get_width() and y >= 0 and y < image.get_height():
			image.set_pixel(x, y, color)


# --- HELPERS ---

func _build_country_to_provinces():
	var result: Dictionary = {}
	
	for pid in province_to_country.keys():
		var country: String = province_to_country[pid]

		if not result.has(country):
			result[country] = []

		result[country].append(pid)

	country_to_provinces = result
	return


func _write_id(x: int, y: int, pid: int) -> void:
	var r = float(pid % 256) / 255.0
	var g = pid / 256.0 / 255.0
	id_map_image.set_pixel(x, y, Color(r, g, 0.0))


func _build_lookup_texture() -> void:
	state_color_image = Image.create(max_province_id + 2, 1, false, Image.FORMAT_RGBA8)
	for pid in range(2, max_province_id + 1):
		var country = province_to_country.get(pid, "")
		var col = Color.GRAY
		if COUNTRY_COLORS.has(country):
			col = COUNTRY_COLORS[country]
		state_color_image.set_pixel(pid, 0, col)
	state_color_texture = ImageTexture.create_from_image(state_color_image)


func _is_sea(c: Color) -> bool:
	# Check BOTH the Main sea color AND the Raster color
	# If it matches either, it is ID 0 (Untouched)
	return _dist_sq(c, SEA_MAIN) < 0.001 or _dist_sq(c, SEA_RASTER) < 0.001


func _identify_country(c: Color) -> String:
	var best := ""
	var min_dist := 0.05
	for country_name in COUNTRY_COLORS.keys():
		var dist := _dist_sq(c, COUNTRY_COLORS[country_name])
		if dist < min_dist:
			min_dist = dist
			best = country_name
	return best



func _dist_sq(c1: Color, c2: Color) -> float:
	return (c1.r-c2.r)**2 + (c1.g-c2.g)**2 + (c1.b-c2.b)**2


func update_province_color(pid: int, country_name: String) -> void:
	if pid <= 1 or pid > max_province_id:
		return

	var new_color = COUNTRY_COLORS.get(country_name, Color.GRAY)

	_update_lookup(pid, new_color)

	if pid == last_hovered_pid:
		original_hover_color = new_color
		_update_lookup(pid, new_color + Color(0.15, 0.15, 0.15, 0))

func set_country_color(country_name: String, custom_color: Color = Color.TRANSPARENT) -> void:
	var new_color = custom_color
	if new_color == Color.TRANSPARENT:
		new_color = COUNTRY_COLORS.get(country_name, Color.GRAY)

	var provinces = country_to_provinces.get(country_name, [])
	
	if provinces.is_empty():
		print("Warning: No provinces found for country: ", country_name)
		return

	for pid in provinces:
		_update_lookup(pid, new_color)		

		if pid == last_hovered_pid:
			original_hover_color = new_color
			_update_lookup(pid, new_color + Color(0.15, 0.15, 0.15, 0))


func get_province_at_pos(pos: Vector2, map_sprite: Sprite2D = null) -> int:
	if not id_map_image: return 0
	
	var x: int
	var y: int
	var size = id_map_image.get_size()

	# --- INPUT MODE: If map_sprite is provided, we use global coordinates ---
	if map_sprite:
		var local = map_sprite.to_local(pos)
		var sprite_size = map_sprite.texture.get_size()
		
		# If sprite is centered, offset the local position to be top-left based
		if map_sprite.centered: 
			local += sprite_size / 2.0
		
		# --- INFINITE SCROLL MATH ---
		x = int(local.x) % int(sprite_size.x)
		if x < 0: x += int(sprite_size.x)
		y = int(local.y)
	
	# --- INTERNAL MODE: If map_sprite is null, pos is already pixel coordinates ---
	else:
		x = int(pos.x)
		y = int(pos.y)

	# Y is not infinite, so we strictly check bounds
	if y < 0 or y >= size.y or x < 0 or x >= size.x:
		return 0
		
	var c = id_map_image.get_pixel(x, y)
	var r = int(round(c.r * 255.0))
	var g = int(round(c.g * 255.0))
	return r + (g * 256)


func update_hover(global_pos: Vector2, map_sprite: Sprite2D) -> void:

	if _is_mouse_over_ui():         
		if last_hovered_pid > 1:
			_update_lookup(last_hovered_pid, original_hover_color)
			last_hovered_pid = -1
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	
	var pid = get_province_at_pos(global_pos, map_sprite)
	
	if GameState.choosing_deploy_city:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		if pid != last_hovered_pid:

			if last_hovered_pid > 1:
				_update_lookup(last_hovered_pid, original_hover_color)
			
			var player_provinces = country_to_provinces.get(CountryManager.player_country.name, [])
			
			if pid > 1 and pid in player_provinces:
				original_hover_color = state_color_image.get_pixel(pid, 0)
				
				var highlight_color = original_hover_color + Color(0.0, 1, 0.2, 0.8) 
				_update_lookup(pid, highlight_color)
				
				last_hovered_pid = pid
				province_hovered.emit(pid, CountryManager.player_country.name)
			else:
				last_hovered_pid = -1
				province_hovered.emit(-1, "")


func handle_click(global_pos: Vector2, map_sprite: Sprite2D) -> void:
	if _is_mouse_over_ui():
		return

	var pid = get_province_with_radius(global_pos, map_sprite, 5)
	
	if pid <= 1:
		close_sidemenu.emit()
		return

	if GameState.choosing_deploy_city:
		var player_provinces = country_to_provinces.get(CountryManager.player_country.name, [])
		
		if pid in player_provinces:			
			province_clicked.emit(pid, CountryManager.player_country.name)
			
			CountryManager.player_country.deploy_pid = pid
			GameState.choosing_deploy_city = false  # Exit deployment mode
			Input.set_default_cursor_shape(Input.CURSOR_ARROW) # Reset cursor immediately
			
			if last_hovered_pid > 1:
				_update_lookup(last_hovered_pid, original_hover_color)
				last_hovered_pid = -1
		else:
			print("Clicked a province, but it's not yours!")
			return

	else:
		if TroopManager.troop_selection.selected_troops.is_empty():
			province_clicked.emit(pid, province_to_country.get(pid, ""))


# To probe around and still register a click if we hit province/coutnry border
func get_province_with_radius(center: Vector2, map_sprite: Sprite2D, radius: int) -> int:
	var offsets = [
		Vector2(0, 0),
		Vector2(radius, 0),
		Vector2(-radius, 0),
		Vector2(0, radius),
		Vector2(0, -radius),
		Vector2(radius, radius),
		Vector2(radius, -radius),
		Vector2(-radius, radius),
		Vector2(-radius, -radius),
	]

	for off in offsets:
		var pid = get_province_at_pos(center + off, map_sprite)
		if pid > 1:
			return pid

	return -1


func _update_lookup(pid: int, color: Color) -> void:
	state_color_image.set_pixel(pid, 0, color)
	state_color_texture.update(state_color_image)


func _calculate_province_centroids() -> void:
	# Use a dictionary to accumulate data: {ID: [total_x, total_y, pixel_count]}
	var accumulators: Dictionary = {}
	
	# Initialize accumulators for all valid province IDs (IDs > 1)
	for i in range(2, max_province_id + 1):
		accumulators[i] = [0.0, 0.0, 0]

	var w = id_map_image.get_width()
	var h = id_map_image.get_height()
	
	# --- Pass 1: Accumulate Coordinates ---
	for y in range(h):
		for x in range(w):
			var pid = get_province_at_pos(Vector2(x, y), null) # Use direct coordinates, sprite is null
			
			if pid > 1 and accumulators.has(pid):
				accumulators[pid][0] += x
				accumulators[pid][1] += y
				accumulators[pid][2] += 1
	
	# --- Pass 2: Calculate Average (Centroid) ---
	for pid in accumulators:
		var data = accumulators[pid]
		var total_pixels = data[2]
		
		if total_pixels > 0:
			var center_x = data[0] / total_pixels
			var center_y = data[1] / total_pixels
			
			# Store the resulting centroid as a Vector2
			province_centers[pid] = Vector2(center_x, center_y)
			if province_objects.has(pid):
				province_objects[pid].center = Vector2(center_x, center_y)

	print("MapManager: Centroids calculated for %d provinces." % province_centers.size())


func _build_adjacency_list() -> void:
	var w = id_map_image.get_width()
	var h = id_map_image.get_height()

	adjacency_list.clear()

	# Prepare dictionary for unique tracking
	var unique_neighbors := {}

	for y in range(h):
		for x in range(w):
			var pid = _get_pid_fast(x, y)
			if pid <= 1:
				continue

			if not unique_neighbors.has(pid):
				unique_neighbors[pid] = {}

			# 4-directional neighbors
			var dirs = [
				Vector2i(1, 0), Vector2i(-1, 0),
				Vector2i(0, 1), Vector2i(0, -1)
			]

			for d in dirs:
				var nx = x + d.x
				var ny = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue

				var neighbor = _get_pid_fast(nx, ny)

				# Normal adjacency (Land-to-Land)
				if neighbor > 1 and neighbor != pid:
					unique_neighbors[pid][neighbor] = true
					continue

				# Border pixel scan (ID=1)
				if neighbor == 1:
					var across = _scan_across_border(nx, ny, pid)
					if across > 1 and across != pid:
						unique_neighbors[pid][across] = true

	# --- THE FIX: Convert to Typed Arrays and Populate Objects ---
	for pid in unique_neighbors:
		var neighbors_keys = unique_neighbors[pid].keys()
		
		# Create a typed array for the Province resource
		var typed_list: Array[int] = []
		for n_id in neighbors_keys:
			typed_list.append(int(n_id))
		
		# Store in the global dictionary (can remain untyped for pathfinding)
		adjacency_list[pid] = typed_list
		
		# Sync to the Province object
		if province_objects.has(pid):
			province_objects[pid].neighbors = typed_list

	print("MapManager: Adjacency list built and synced to Province objects.")


func _scan_across_border(x: int, y: int, pid: int) -> int:
	var w: int = id_map_image.get_width()
	var h: int = id_map_image.get_height()
	
	# Check right
	if x + 1 < w:
		var n: int = _get_pid_fast(x + 1, y)
		if n > 1 and n != pid:
			return n
	
	# Check down
	if y + 1 < h:
		var n: int = _get_pid_fast(x, y + 1)
		if n > 1 and n != pid:
			return n
	
	return -1


# Faster direct pid fetch
func _get_pid_fast(x: int, y: int) -> int:
	var c = id_map_image.get_pixel(x, y)
	var r = int(c.r * 255.0 + 0.5)
	var g = int(c.g * 255.0 + 0.5)
	return r + g * 256


# --- Pathfinding section kinda. Should be in own file tbh.. ---#

# === CACHED A* PATHFINDING (MODIFIED) ===
var path_cache: Dictionary = {}

# Added 'allowed_countries' parameter. Defaults to empty [] (no restrictions).
func find_path(start_pid: int, end_pid: int, allowed_countries: Array[String] = []) -> Array[int]:
	if start_pid == end_pid:
		return [start_pid]

	if not adjacency_list.has(start_pid) or not adjacency_list.has(end_pid):
		return []

	# --- CACHE LOGIC ---
	# We use Vector2i(start, end) as the key. 
	# This avoids String allocation ("%d_%d") entirely.
	var use_cache = allowed_countries.is_empty()
	var cache_key := Vector2i(start_pid, end_pid)

	if use_cache and path_cache.has(cache_key):
		return path_cache[cache_key].duplicate()

	# --- CALCULATE PATH ---
	var path = _find_path_astar(start_pid, end_pid, allowed_countries)

	# --- STORE IN CACHE ---
	if use_cache and not path.is_empty():
		path_cache[cache_key] = path.duplicate()

	return path

func _find_path_astar(start_pid: int, end_pid: int, allowed_countries: Array[String]) -> Array[int]:
	# 1. Optimize Allowed Check: Convert Array to Dictionary for O(1) lookup
	var allowed_dict = {}
	var restricted_mode = not allowed_countries.is_empty()
	if restricted_mode:
		for c in allowed_countries:
			allowed_dict[c] = true
			
	# 2. Standard A* Setup
	var open_set: Array[int] = [start_pid]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var f_score: Dictionary = {}
	var open_set_hash: Dictionary = {start_pid: true} 

	# 3. "Go as near as you can" tracking
	# We track the node with the lowest distance (heuristic) to the target
	var closest_pid_so_far = start_pid
	var closest_dist_so_far = _heuristic(start_pid, end_pid)

	for pid in adjacency_list.keys():
		g_score[pid] = INF
		f_score[pid] = INF

	g_score[start_pid] = 0
	f_score[start_pid] = closest_dist_so_far

	while open_set.size() > 0:
		# Standard: Find node with lowest f_score
		var current = open_set[0]
		var best_idx = 0
		var best_f = f_score[current]
		
		for i in range(1, open_set.size()):
			var f = f_score[open_set[i]]
			if f < best_f:
				best_f = f
				current = open_set[i]
				best_idx = i

		# Pop current
		open_set[best_idx] = open_set[-1]
		open_set.pop_back()
		open_set_hash.erase(current)

		# Success!
		if current == end_pid:
			return _reconstruct_path(came_from, current)

		# Track closest node (Fallback logic)
		# If we are closer to the target than ever before, record this PID
		var dist_to_target = _heuristic(current, end_pid)
		if dist_to_target < closest_dist_so_far:
			closest_dist_so_far = dist_to_target
			closest_pid_so_far = current

		for neighbor in adjacency_list[current]:
			
			# --- NEW RESTRICTION CHECK ---
			if restricted_mode:
				var n_country = province_to_country.get(neighbor, "")
				# If neighbor belongs to a country NOT in the list, skip it.
				# Note: We allow the neighbor if it IS the target (optional, depends on game rules)
				# But per your request "only go THAT far", we strictly block it.
				if not allowed_dict.has(n_country):
					continue
			# -----------------------------

			var tentative_g = g_score[current] + 1
			
			if tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, end_pid)

				if not open_set_hash.has(neighbor):
					open_set.append(neighbor)
					open_set_hash[neighbor] = true

	# If we get here, the path to end_pid is impossible (blocked by borders).
	# Instead of returning empty [], we return the path to the CLOSEST point we reached.
	if restricted_mode and closest_pid_so_far != start_pid:
		# print("Path blocked! Going to closest valid province: ", closest_pid_so_far)
		return _reconstruct_path(came_from, closest_pid_so_far)

	return []


func _get_cache_key(start_pid: int, end_pid: int) -> String:
	"""Create a unique cache key for this path"""
	return "%d_%d" % [start_pid, end_pid]


func _heuristic(a: int, b: int) -> float:
	var pa = province_centers.get(a, Vector2.ZERO)
	var pb = province_centers.get(b, Vector2.ZERO)
	return pa.distance_to(pb)


func _reconstruct_path(came_from: Dictionary, current: int) -> Array[int]:
	var path: Array[int] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.append(current)
	path.reverse()
	return path


func get_path_length(path: Array[int]) -> int:
	return path.size() - 1 if path.size() > 1 else 0


func is_path_possible(start_pid: int, end_pid: int) -> bool:
	return not find_path(start_pid, end_pid).is_empty()


func print_cache_stats() -> void:
	"""Print cache statistics"""
	print("Path Cache Stats: %d paths cached" % path_cache.size())


func _is_mouse_over_ui() -> bool:
	var hovered = get_viewport().gui_get_hovered_control()
	return hovered != null

func _get_heatmap_color(pop: int, max_pop: float) -> Color:
	# If population is 0, return a neutral "empty" color (dark slate/gray)
	if pop <= 0:
		return Color(0.1, 0.1, 0.15, 1.0)
	
	# Calculate intensity based on the REAL maximum in your current data
	var intensity = clamp(float(pop) / max_pop, 0.0, 1.0)
	
	# We create a multi-stop gradient:
	# Low: Cyan/Green -> Mid: Yellow -> High: Red
	var col: Color
	if intensity < 0.5:
		# Blend from a "Low Density" Teal to Yellow
		col = Color.DARK_CYAN.lerp(Color.YELLOW, intensity * 2.0)
	else:
		# Blend from Yellow to a "High Density" Deep Red
		col = Color.YELLOW.lerp(Color.RED, (intensity - 0.5) * 2.0)
	
	return col

func show_population_map() -> void:
	if province_objects.is_empty():
		return

	var current_max_pop: float = 1.0 
	for province in province_objects.values():
		if province.population > current_max_pop:
			current_max_pop = float(province.population)

	for pid in province_objects.keys():
		var province = province_objects[pid]
		
		if pid <= 1: continue 
			
		var pop_color = _get_heatmap_color(province.population, current_max_pop)
		state_color_image.set_pixel(pid, 0, pop_color)
	
	state_color_texture.update(state_color_image)
	print("MapManager: Population View Updated. Max Pop found: ", current_max_pop)


func show_countries_map() -> void:
	state_color_image.set_pixel(0, 0, SEA_MAIN)   # ID 0: Sea
	state_color_image.set_pixel(1, 0, Color.BLACK) # ID 1: Borders/Grid

	for pid in province_objects.keys():
		if pid <= 1: continue
		
		var province = province_objects[pid]
		var country_name = province.country
		
		var country_color = COUNTRY_COLORS.get(country_name, Color.GRAY)
		
		state_color_image.set_pixel(pid, 0, country_color)
	
	state_color_texture.update(state_color_image)
	print("MapManager: Switched to Political (Country) View")


var COUNTRY_COLORS: Dictionary = {}
func _load_country_colors() -> void:
	
	var file := FileAccess.open("res://assets/countries.json", FileAccess.READ)
	if file == null:
		push_error("Could not open country_colors.json")
		return

	var data = JSON.parse_string(file.get_as_text())
	if data is not Dictionary:
		push_error("Invalid JSON format")
		return

	COUNTRY_COLORS.clear()
	for country_name in data.keys():
		var rgb = data[country_name].get("color")
		if rgb == null or rgb.size() != 3:
			continue
		COUNTRY_COLORS[country_name] = Color8(rgb[0], rgb[1], rgb[2])

func _load_population_json() -> void:
	var path = "res://map_data/population_color_map.json"
	if not FileAccess.file_exists(path):
		push_error("Population JSON missing!")
		return
		
	var file = FileAccess.open(path, FileAccess.READ)
	var json_data = JSON.parse_string(file.get_as_text())
	if json_data is Dictionary:
		color_to_pop_map = json_data

func _get_pop_from_color(c: Color) -> int:
	var r = int(round(c.r * 255.0))
	var g = int(round(c.g * 255.0))
	var b = int(round(c.b * 255.0))
	
	var exact_key = "(%d, %d, %d)" % [r, g, b]
	
	# 1. Try Exact Match
	if color_to_pop_map.has(exact_key):
		return color_to_pop_map[exact_key]
	
	# 2. Try match without spaces (common JSON difference)
	var tight_key = "(%d,%d,%d)" % [r, g, b]
	if color_to_pop_map.has(tight_key):
		return color_to_pop_map[tight_key]

	# 3. Fuzzy Match (Only if exact fails)
	# We look for the color in our map with the smallest RGB distance
	var best_match = 0
	var min_dist = 999999.0
	
	for color_str in color_to_pop_map.keys():
		var target_rgb = _parse_color_string(color_str)
		var dist = (Vector3(r, g, b) - target_rgb).length_squared()
		
		if dist < min_dist:
			min_dist = dist
			best_match = color_to_pop_map[color_str]
			
	# If the closest color is reasonably similar, use it
	if min_dist < 100: # Threshold for "close enough"
		return best_match
		
	return 0

func _parse_color_string(s: String) -> Vector3:
	var cleaned = s.replace("(", "").replace(")", "").replace(" ", "")
	var parts = cleaned.split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
