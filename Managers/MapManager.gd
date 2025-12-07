extends Node

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
var province_to_country: Dictionary = {}
var country_to_provinces: Dictionary = {}
var last_hovered_pid: int = -1
var original_hover_color: Color
var province_centers: Dictionary = {} # Stores {ID: Vector2(x, y)}
var adjacency_list: Dictionary = {} # Stores {ID: [Neighbor_ID_1, Neighbor_ID_2, ...]}	

# MapManager.gd
const MAP_DATA_PATH = "res://map_data/MapData.tres"
const CACHE_FOLDER = "res://map_data/"

@export var region_texture: Texture2D
@export var culture_texture: Texture2D

var map_data: MapData


func _ready() -> void:

	var dir = DirAccess.open("res://")
	if dir:
		if not dir.dir_exists(CACHE_FOLDER):
			var err = dir.make_dir_recursive(CACHE_FOLDER)
			if err != OK:
				push_error("Failed to create cache folder: %s" % err)
			else:
				print("MapManager: Created cache folder at %s" % CACHE_FOLDER)
	else:
		push_error("MapManager: Cannot access res:// filesystem!")

	# --- Try to load cached data ---
	if _try_load_cached_data():
		print("MapManager: Loaded precomputed map data instantly!")
		map_ready.emit()
		return

	# --- First time: generate and cache ---
	var region = region_texture if region_texture else preload("res://maps/regions.png")
	var culture = culture_texture if culture_texture else preload("res://maps/cultures.png")

	if not region or not culture:
		push_error("MapManager: Missing region or culture texture!")
		return

	print("MapManager: First-time setup — parsing map (this may take 5–15 seconds)...")
	call_deferred("_generate_and_save", region, culture)


func _generate_and_save(region: Texture2D, culture: Texture2D) -> void:
	initialize_map(region, culture)  # Your existing heavy parsing code

	# Save everything
	var map_data := MapData.new()
	map_data.province_centers = province_centers.duplicate()
	map_data.adjacency_list = adjacency_list.duplicate(true)
	map_data.province_to_country = province_to_country.duplicate()
	map_data.country_to_provinces = country_to_provinces.duplicate()
	map_data.max_province_id = max_province_id
	map_data.id_map_image = id_map_image.duplicate()

	var err = ResourceSaver.save(map_data, MAP_DATA_PATH)
	if err == OK:
		print("MapManager: Precomputed map data saved → future loads will be instant!")
	else:
		push_error("Failed to save MapData.tres: %s" % err)

	map_ready.emit()


func _try_load_cached_data() -> bool:
	if not ResourceLoader.exists(MAP_DATA_PATH):
		return false

	var loaded = ResourceLoader.load(MAP_DATA_PATH) as MapData
	if not loaded:
		return false

	province_centers = loaded.province_centers.duplicate()
	adjacency_list = loaded.adjacency_list.duplicate(true)
	province_to_country = loaded.province_to_country.duplicate()
	country_to_provinces = loaded.country_to_provinces.duplicate()
	max_province_id = loaded.max_province_id
	id_map_image = loaded.id_map_image.duplicate()

	_build_lookup_texture()
	MapDebugOverlay.set_centers(province_centers)

	return true

func initialize_map(region_tex: Texture2D, culture_tex: Texture2D) -> void:
	var r_img = region_tex.get_image()
	var c_img = culture_tex.get_image()
	
	var w = r_img.get_width()
	var h = r_img.get_height()

	id_map_image = Image.create(w, h, false, Image.FORMAT_RGB8)
	
	var unique_regions = {}
	var next_id = 2 # ID 0=Sea, ID 1=Land Grid
	
	print("MapManager: Parsing map with Priority Sea Detection...")

	for y in range(h):
		for x in range(w):
			var r_color = r_img.get_pixel(x, y)
			var c_color = c_img.get_pixel(x, y)

			# --- SEA DETECTION ---
			# Sea color becomes ID 0 to distinguish it from country borders 
			# 
			if _is_sea(c_color):
				_write_id(x, y, 0) 
				continue

			# --- GRID LINE ---
			# Now we check if it's a black line in regions.png
			if r_color.r < GRID_COLOR_THRESHOLD and r_color.g < GRID_COLOR_THRESHOLD and r_color.b < GRID_COLOR_THRESHOLD:
				_write_id(x, y, 1) 
				continue

			# --- LAND PROVINCE ---
			var key = r_color.to_html(false)
			if not unique_regions.has(key):
				unique_regions[key] = next_id
				var country = _identify_country(c_color)
				if country != "":
					province_to_country[next_id] = country
				next_id += 1

			var pid = unique_regions[key]
			_write_id(x, y, pid)

	max_province_id = next_id - 1
	_build_lookup_texture()
	_calculate_province_centroids()
	_build_country_to_provinces()
	_build_adjacency_list()
	
	MapDebugOverlay.set_centers(province_centers)
	map_ready.emit()
	print("MapManager: Done.")

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
	var g = float(pid / 256) / 255.0
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
	var best = ""
	var min_dist = 0.05
	for name in COUNTRY_COLORS:
		var dist = _dist_sq(c, COUNTRY_COLORS[name])
		if dist < min_dist:
			min_dist = dist
			best = name
	return best

func _dist_sq(c1: Color, c2: Color) -> float:
	return (c1.r-c2.r)**2 + (c1.g-c2.g)**2 + (c1.b-c2.b)**2

# MapManager.gd

func update_province_color(pid: int, country_name: String) -> void:
	if pid <= 1 or pid > max_province_id:
		return

	var new_color = COUNTRY_COLORS.get(country_name, Color.GRAY)

	# 1. Update the province's color in the lookup image
	_update_lookup(pid, new_color)

	# 2. Handle hover state change (if the player is hovering over the newly conquered province)
	if pid == last_hovered_pid:
		# Set the new permanent color as the base color for the hover state
		original_hover_color = new_color

		# Re-apply the hover highlight on the new color
		_update_lookup(pid, new_color + Color(0.15, 0.15, 0.15, 0))

	# The actual map data change (province_to_country and country_to_provinces)
	# is handled by the WarManager for centralized logic, but the visual update
	# is handled here.
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
		return
	
	var pid = get_province_at_pos(global_pos, map_sprite)
	if pid != last_hovered_pid:
		if last_hovered_pid > 1:
			_update_lookup(last_hovered_pid, original_hover_color)
		last_hovered_pid = pid
		if pid > 1:
			var col = state_color_image.get_pixel(pid, 0)
			original_hover_color = col
			_update_lookup(pid, col + Color(0.15, 0.15, 0.15, 0))
		province_hovered.emit(pid, province_to_country.get(pid, ""))



func handle_click(global_pos: Vector2, map_sprite: Sprite2D) -> void:
	if _is_mouse_over_ui():
		return

	var pid = get_province_with_radius(global_pos, map_sprite, 5)
	if pid > 1:
		if len(SelectionManager.selected_troops) > 0:
			return
		province_clicked.emit(pid, province_to_country.get(pid, ""))
	else:
		emit_signal("close_sidemenu")
		
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

# MapManager.gd

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

	print("MapManager: Centroids calculated for %d provinces." % province_centers.size())


# === FIXED ADJACENCY + PATHFINDING ===

func _build_adjacency_list() -> void:
	var w = id_map_image.get_width()
	var h = id_map_image.get_height()

	adjacency_list.clear()

	# Prepare dictionary
	for pid in range(2, max_province_id + 1):
		adjacency_list[pid] = []

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

				# Normal adjacency
				if neighbor > 1 and neighbor != pid:
					unique_neighbors[pid][neighbor] = true
					continue

				# Border pixel? (ID=1)
				if neighbor == 1:
					var across = _scan_across_border(nx, ny, pid)
					if across > 1 and across != pid:
						unique_neighbors[pid][across] = true

	# Convert sets to arrays
	for pid in unique_neighbors:
		adjacency_list[pid] = unique_neighbors[pid].keys()

	print("MapManager: Adjacency list built (with border scan).")


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


const INF = 999999.0


func get_path_length(path: Array[int]) -> int:
	return path.size() - 1 if path.size() > 1 else 0

func is_path_possible(start_pid: int, end_pid: int) -> bool:
	return not find_path(start_pid, end_pid).is_empty()

func get_distance(start_pid: int, end_pid: int) -> int:
	var path = find_path(start_pid, end_pid)
	return get_path_length(path) if path.size() > 0 else -1


# === FUTURE PORTS READY ===
func find_path_with_ports(start_pid: int, end_pid: int, ports: Dictionary = {}) -> Array[int]:
	"""FUTURE-PROOF: Same A* but allows sea travel between ports.
	ports = {port_pid: [connected_sea_pids]}"""
	# For now, just calls land-only pathfinder
	return find_path(start_pid, end_pid)

# --- CACHE MANAGEMENT ---
func clear_path_cache() -> void:
	"""Clear the path cache if needed (e.g., when map changes)"""
	path_cache.clear()
	print("Path cache cleared!")

func get_cache_size() -> int:
	"""Get number of cached paths"""
	return path_cache.size()

func print_cache_stats() -> void:
	"""Print cache statistics"""
	print("Path Cache Stats: %d paths cached" % path_cache.size())

func _is_mouse_over_ui() -> bool:
	var hovered = get_viewport().gui_get_hovered_control()
	return hovered != null

# Your color → country definition
const COUNTRY_COLORS := {
	"canada": Color8(195, 92, 109),
	"denmark": Color8(153, 116, 93),
	"russia": Color8(56, 96, 56),
	"norway": Color8(111, 71, 71),
	"united_states": Color8(20, 133, 237),
	"finland": Color8(194, 198, 215),
	"sweden": Color8(36, 132, 247),
	"iceland": Color8(68, 81, 113),
	"estonia": Color8(50, 135, 175),
	"united_kingdom": Color8(200, 56, 93),
	"latvia": Color8(75, 77, 186),
	"belarus": Color8(199, 213, 224),
	"lithuania": Color8(219, 219, 119),
	"ireland": Color8(80, 159, 90),
	"kazakhstan": Color8(88, 161, 193),
	"germany": Color8(73, 72, 77),
	"poland": Color8(197, 92, 106),
	"mongolia": Color8(163, 142, 75),
	"netherlands": Color8(199, 135, 73),
	"china": Color8(167, 87, 90),
	"ukraine": Color8(52, 88, 138),
	"belgium": Color8(193, 171, 8),
	"france": Color8(61, 117, 232),
	"czechia": Color8(54, 167, 156),
	"luxembourg": Color8(85, 228, 233),
	"slovakia": Color8(121, 92, 159),
	"austria": Color8(168, 174, 198),
	"hungary": Color8(78, 125, 115),
	"moldova": Color8(134, 110, 82),
	"romania": Color8(215, 196, 72),
	"transnistria": Color8(42, 22, 24),
	"switzerland": Color8(224, 5, 5),
	"liechtenstein": Color8(87, 90, 127),
	"italy": Color8(67, 127, 63),
	"slovenia": Color8(79, 111, 150),
	"croatia": Color8(42, 45, 96),
	"serbia": Color8(154, 104, 103),
	"bosnia_and_herzegovina": Color8(223, 192, 135),
	"uzbekistan": Color8(202, 206, 253),
	"japan": Color8(255, 201, 178),
	"bulgaria": Color8(51, 155, 0),
	"spain": Color8(242, 205, 94),
	"san_marino": Color8(98, 176, 198),
	"monaco": Color8(237, 162, 186),
	"abkhazia": Color8(63, 31, 45),
	"montenegro": Color8(252, 114, 121),
	"kosovo": Color8(118, 142, 186),
	"georgia": Color8(239, 228, 232),
	"andorra": Color8(201, 0, 1),
	"kyrgyzstan": Color8(244, 61, 111),
	"south_ossetia": Color8(194, 150, 87),
	"north_korea": Color8(245, 12, 55),
	"albania": Color8(149, 45, 102),
	"north_macedonia": Color8(202, 149, 118),
	"azerbaijan": Color8(114, 140, 217),
	"portugal": Color8(39, 116, 70),
	"turkmenistan": Color8(189, 140, 110),
	"turkey": Color8(166, 52, 67),
	"vatican_city": Color8(196, 181, 130),
	"greece": Color8(93, 181, 227),
	"armenia": Color8(246, 162, 134),
	"tajikistan": Color8(109, 148, 130),
	"iran": Color8(90, 143, 123),
	"afghanistan": Color8(113, 107, 121),
	"south_korea": Color8(94, 118, 190),
	"tunisia": Color8(185, 86, 106),
	"iraq": Color8(178, 114, 99),
	"syria": Color8(55, 78, 92),
	"pakistan": Color8(0, 41, 23),
	"algeria": Color8(10, 43, 36),
	"morocco": Color8(155, 74, 89),
	"malta": Color8(217, 217, 217),
	"turkish_cyprus": Color8(92, 77, 50),
	"india": Color8(208, 163, 108),
	"cyprus": Color8(222, 181, 27),
	"lebanon": Color8(84, 156, 139),
	"libya": Color8(42, 112, 84),
	"israel": Color8(69, 105, 217),
	"jordan": Color8(227, 152, 156),
	"mexico": Color8(104, 151, 82),
	"saudi_arabia": Color8(171, 190, 152),
	"palestine": Color8(86, 72, 87),
	"egypt": Color8(175, 163, 88),
	"nepal": Color8(0, 56, 147),
	"kuwait": Color8(90, 64, 42),
	"bhutan": Color8(121, 100, 95),
	"myanmar": Color8(59, 113, 79),
	"western_sahara": Color8(197, 174, 120),
	"mauritania": Color8(42, 111, 83),
	"bahrain": Color8(58, 65, 75),
	"bangladesh": Color8(0, 42, 48),
	"qatar": Color8(111, 35, 115),
	"united_arab_emirates": Color8(39, 150, 120),
	"taiwan": Color8(91, 77, 92),
	"mali": Color8(158, 138, 87),
	"oman": Color8(129, 84, 88),
	"niger": Color8(38, 88, 77),
	"cuba": Color8(151, 68, 176),
	"chad": Color8(187, 170, 126),
	"sudan": Color8(12, 56, 39),
	"vietnam": Color8(198, 190, 117),
	"laos": Color8(89, 77, 63),
	"haiti": Color8(165, 116, 111),
	"dominican_republic": Color8(114, 136, 119),
	"thailand": Color8(20, 45, 76),
	"belize": Color8(130, 50, 20),
	"yemen": Color8(78, 50, 53),
	"jamaica": Color8(139, 220, 10),
	"philippines": Color8(114, 85, 166),
	"guatemala": Color8(72, 48, 109),
	"eritrea": Color8(206, 140, 162),
	"cabo_verde": Color8(206, 32, 39),
	"st_kitts_and_nevis": Color8(59, 56, 0),
	"senegal": Color8(184, 117, 124),
	"honduras": Color8(153, 176, 74),
	"burkina_faso": Color8(202, 110, 123),
	"el_salvador": Color8(159, 136, 198),
	"nicaragua": Color8(145, 178, 190),
	"ethiopia": Color8(48, 71, 123),
	"cambodia": Color8(226, 180, 144),
	"dominica": Color8(118, 112, 178),
	"nigeria": Color8(194, 122, 107),
	"gambia": Color8(68, 53, 92),
	"barbados": Color8(252, 209, 22),
	"st_lucia": Color8(93, 183, 230),
	"guinea_bissau": Color8(218, 189, 129),
	"guinea": Color8(32, 90, 78),
	"venezuela": Color8(200, 100, 150),
	"grenada": Color8(0, 123, 95),
	"benin": Color8(219, 196, 120),
	"djibouti": Color8(215, 20, 26),
	"cameroon": Color8(24, 94, 97),
	"south_sudan": Color8(212, 191, 110),
	"somalia": Color8(102, 131, 171),
	"somaliland": Color8(85, 171, 112),
	"costa_rica": Color8(167, 140, 42),
	"colombia": Color8(222, 187, 91),
	"togo": Color8(21, 51, 35),
	"maldives": Color8(146, 155, 162),
	"ghana": Color8(162, 74, 88),
	"central_african_republic": Color8(166, 77, 99),
	"trinidad_and_tobago": Color8(240, 90, 39),
	"ivory_coast": Color8(209, 153, 106),
	"sierra_leone": Color8(114, 159, 190),
	"panama": Color8(60, 53, 88),
	"sri_lanka": Color8(86, 75, 57),
	"liberia": Color8(81, 61, 118),
	"guyana": Color8(180, 150, 120),
	"palau": Color8(255, 201, 14),
	"nauru": Color8(41, 47, 133),
	"malaysia": Color8(197, 96, 100),
	"suriname": Color8(128, 55, 84),
	"indonesia": Color8(221, 190, 196),
	"brazil": Color8(76, 145, 63),
	"dr_congo": Color8(65, 104, 147),
	"kenya": Color8(131, 54, 64),
	"brunei": Color8(60, 110, 85),
	"uganda": Color8(146, 130, 79),
	"equatorial_guinea": Color8(80, 144, 171),
	"congo": Color8(209, 108, 120),
	"gabon": Color8(220, 191, 123),
	"singapore": Color8(77, 73, 134),
	"ecuador": Color8(249, 146, 98),
	"sao_tome_and_principe": Color8(18, 173, 43),
	"peru": Color8(196, 189, 204),
	"rwanda": Color8(29, 56, 65),
	"tanzania": Color8(103, 135, 146),
	"burundi": Color8(154, 75, 160),
	"papua_new_guinea": Color8(43, 56, 90),
	"angola": Color8(44, 24, 35),
	"seychelles": Color8(161, 30, 36),
	"solomon_islands": Color8(226, 12, 12),
	"zambia": Color8(34, 86, 47),
	"east_timor": Color8(40, 170, 76),
	"tuvalu": Color8(237, 28, 36),
	"malawi": Color8(161, 84, 104),
	"bolivia": Color8(204, 166, 108),
	"mozambique": Color8(14, 54, 62),
	"australia": Color8(57, 143, 97),
	"madagascar": Color8(44, 140, 4),
	"vanuatu": Color8(237, 167, 32),
	"zimbabwe": Color8(173, 88, 93),
	"fiji": Color8(143, 73, 82),
	"namibia": Color8(193, 217, 167),
	"niue": Color8(185, 122, 87),
	"chile": Color8(155, 101, 107),
	"botswana": Color8(136, 157, 188),
	"paraguay": Color8(57, 113, 228),
	"mauritius": Color8(179, 149, 0),
	"tonga": Color8(255, 117, 120),
	"argentina": Color8(145, 157, 236),
	"south_africa": Color8(210, 165, 108),
	"eswatini": Color8(87, 95, 134),
	"lesotho": Color8(0, 190, 240),
	"uruguay": Color8(174, 192, 156),
	"new_zealand": Color8(218, 209, 233),
	"american_union": Color8(37, 48, 65),
	"socialist_states": Color8(178, 34, 53),
	"american_commonwealth": Color8(90, 80, 198),
	"vichy_france": Color8(109, 187, 209),
	"french_commune": Color8(10, 54, 176),
	"french_empire": Color8(5, 91, 142),
	"free_france": Color8(21, 37, 81),
	"saar_protectorate": Color8(117, 207, 133),
	"german_reich": Color8(102, 96, 87),
	"german_empire": Color8(102, 102, 102),
	"german_republic": Color8(51, 34, 42),
	"great_britain": Color8(204, 110, 117),
	"oceania": Color8(149, 47, 47),
	"british_union": Color8(207, 12, 39),
	"chinese_republic": Color8(218, 230, 92),
	"beiyang_china": Color8(224, 139, 13),
	"reorganized_china": Color8(96, 140, 194),
	"great_qing": Color8(214, 180, 144),
	"provincial_league": Color8(130, 139, 171),
	"russian_sfsr": Color8(156, 91, 113),
	"white_russia": Color8(74, 99, 41),
	"russian_republic": Color8(0, 127, 13),
	"soviet_union": Color8(125, 13, 24),
	"transamur": Color8(235, 247, 247),
	"imperial_japan": Color8(211, 184, 180),
	"japanese_empire": Color8(201, 191, 183),
	"occupied_japan": Color8(180, 186, 224),
	"japanese_republic": Color8(255, 166, 146),
	"republican_spain": Color8(255, 212, 2),
	"francoist_spain": Color8(179, 123, 105),
	"spanish_republic": Color8(232, 106, 118),
	"carlist_spain": Color8(232, 143, 72),
	"italian_empire": Color8(72, 140, 84),
	"italian_kingdom": Color8(86, 165, 82),
	"italian_republic": Color8(31, 122, 92),
	"salo_republic": Color8(35, 69, 41),
	"serbian_republic": Color8(89, 80, 110),
	"serbian_kingdom": Color8(13, 70, 130),
	"yugoslavia": Color8(72, 73, 126),
	"sfr_yugoslavia": Color8(99, 106, 143),
	"apartheid_south_africa": Color8(152, 130, 191),
	"british_south_africa": Color8(102, 30, 52),
	"south_african_republic": Color8(251, 131, 128),
	"national_south_africa": Color8(185, 103, 74),
	"zulu_kingdom": Color8(40, 128, 255),
	"saudi_republic": Color8(130, 141, 124),
	"unitary_saudi": Color8(77, 120, 90),
	"reformed_saudi": Color8(157, 160, 159),
	"abyssinia": Color8(190, 176, 215),
	"pdr_ethiopia": Color8(196, 173, 199),
	"reformed_ethiopia": Color8(162, 144, 161),
	"italian_east_africa": Color8(69, 95, 77),
	"danish_republic": Color8(156, 128, 125),
	"norwegian_republic": Color8(0, 40, 101),
	"british_raj": Color8(170, 10, 10),
	"bharatiya": Color8(120, 38, 38),
	"princely_federation": Color8(226, 135, 40),
	"unitary_india": Color8(95, 174, 95),
	"indian_empire": Color8(184, 92, 1),
	"dominion_of_canada": Color8(119, 48, 39),
	"unitary_canada": Color8(129, 138, 163),
	"popular_canada": Color8(245, 140, 151),
	"royal_canada": Color8(140, 104, 115),
	"mexican_empire": Color8(178, 212, 191),
	"reformed_mexico": Color8(86, 102, 85),
	"unitary_mexico": Color8(76, 82, 98),
	"mexican_republic": Color8(75, 105, 91),
	"pr_mongolia": Color8(108, 140, 42),
	"nigerian_republic": Color8(173, 47, 50),
	"unitary_nigeria": Color8(11, 54, 24),
	"nigerian_kingdom": Color8(148, 133, 58),
	"reformed_nigeria": Color8(3, 129, 5),
	"swedish_republic": Color8(102, 142, 201),
	"unitary_sweden": Color8(45, 87, 147),
	"swedish_kingdom": Color8(97, 185, 223),
	"argentinian_republic": Color8(60, 76, 156),
	"unitary_argentina": Color8(22, 49, 82),
	"argentinian_kingdom": Color8(231, 204, 118),
	"reformed_argentina": Color8(152, 149, 187),
	"arab_islamic_republic": Color8(68, 150, 86),
	"siam": Color8(140, 166, 115),
	"reformed_thailand": Color8(3, 113, 174),
	"thai_republic": Color8(165, 26, 49),
	"national_siam": Color8(116, 43, 89),
	"venezuelan_republic": Color8(186, 201, 171),
	"dutch_east_indies": Color8(40, 50, 120),
	"indonesian_republic": Color8(100, 9, 10),
	"reformed_indonesia": Color8(3, 15, 72),
	"majapahit_empire": Color8(130, 53, 51),
	"occupied_indonesia": Color8(138, 95, 94),
	"rosa_luxembourg": Color8(116, 161, 173),
	"dutch_republic": Color8(102, 78, 55),
	"niederlande": Color8(96, 93, 99),
	"orange_netherlands": Color8(229, 195, 134),
	"british_malaya": Color8(255, 117, 152),
	"afghan_kingdom": Color8(64, 160, 167),
	"afghan_republic": Color8(255, 159, 132),
	"kingdom_of_greece": Color8(124, 166, 212),
	"greek_republic": Color8(176, 187, 249),
	"brazilian_republic": Color8(109, 63, 76),
	"brazilian_empire": Color8(34, 112, 138),
	"unitary_brazil": Color8(41, 94, 87),
	"reformed_brazil": Color8(53, 132, 52),
	"bohemia": Color8(100, 153, 104),
	"czechoslovakia": Color8(63, 196, 183),
	"czech_republic": Color8(62, 196, 159),
	"bohemian_protectorate": Color8(70, 82, 157),
	"persia": Color8(47, 100, 74),
	"reformed_iran": Color8(143, 117, 96),
	"iranian_republic": Color8(89, 110, 106),
	"iraqi_kingdom": Color8(101, 135, 121),
	"reformed_iraq": Color8(182, 166, 101),
	"iraqi_republic": Color8(191, 30, 36),
	"egyptian_kingdom": Color8(222, 184, 110),
	"united_arab_republic": Color8(199, 187, 164),
	"reformed_egypt": Color8(168, 151, 111),
	"egyptian_republic": Color8(201, 193, 134),
	"omani_sultanate": Color8(176, 121, 118),
	"yemeni_kingdom": Color8(102, 77, 70),
	"yemeni_republic": Color8(217, 140, 104),
	"kingdom_of_albania": Color8(173, 83, 114),
	"psr_albania": Color8(163, 74, 119),
	"kingdom_of_hungary": Color8(249, 126, 98),
	"hungarian_republic": Color8(255, 147, 139),
	"greater_hungary": Color8(196, 129, 119),
	"austrian_empire": Color8(220, 220, 220),
	"austrian_state": Color8(181, 175, 194),
	"austria_hungary": Color8(233, 234, 227),
	"bulgarian_empire": Color8(58, 115, 97),
	"bulgarian_kingdom": Color8(66, 113, 69),
	"bulgarian_republic": Color8(74, 143, 74),
	"irish_republic": Color8(115, 158, 134),
	"irish_kingdom": Color8(185, 204, 172),
	"unitary_ireland": Color8(31, 62, 79),
	"ukrainian_state": Color8(107, 43, 1),
	"ukrainian_ssr": Color8(107, 78, 77),
	"national_ukraine": Color8(107, 124, 142),
	"reformed_ukraine": Color8(1, 125, 207),
	"slovak_republic": Color8(161, 168, 191),
	"kampuchea": Color8(122, 94, 116),
	"independent_croatia": Color8(191, 119, 173),
	"illyria": Color8(233, 175, 221),
	"legionary_romania": Color8(209, 205, 153),
	"romanian_kingdom": Color8(255, 255, 119),
	"romanian_republic": Color8(229, 185, 92),
	"chosen": Color8(54, 66, 107),
	"joseon": Color8(156, 169, 202),
	"finnish_ssr": Color8(181, 164, 164),
	"greater_finland": Color8(230, 217, 226),
	"finnish_kingdom": Color8(197, 206, 230),
	"pakistani_republic": Color8(75, 80, 102),
	"reformed_pakistan": Color8(3, 125, 37),
	"sikh_empire": Color8(255, 127, 39),
	"unitary_pakistan": Color8(62, 69, 65),
	"ottoman_empire": Color8(162, 20, 0),
	"turkish_republic": Color8(135, 148, 141),
	"national_turkey": Color8(102, 74, 58),
	"kemalist_turkey": Color8(194, 207, 189),
	"montenegrin_kingdom": Color8(77, 89, 105),
	"portugese_kingdom": Color8(0, 102, 122),
	"portugese_republic": Color8(179, 15, 6),
	"burma": Color8(166, 106, 147),
	"syrian_republic": Color8(149, 150, 171),
	"polish_republic": Color8(230, 127, 148),
	"polish_kingdom": Color8(191, 136, 162),
	"unitary_poland": Color8(187, 156, 201),
	"vietnamese_republic": Color8(0, 69, 154),
	"reformed_vietnam": Color8(151, 130, 73),
	"vietnamese_empire": Color8(77, 64, 5),
	"vietnamese_kingdom": Color8(218, 206, 175),
	"communist_chile": Color8(1, 89, 132),
	"flanders": Color8(251, 224, 67),
	"belgian_republic": Color8(181, 150, 75),
	"burgundy": Color8(85, 1, 0),
	"baltic_duchy": Color8(142, 142, 129),
	"angolan_republic": Color8(154, 168, 127),
	"lithuanian_kingdom": Color8(153, 69, 116),
	"alash_autonomy": Color8(0, 122, 167),
	"pr_congo": Color8(157, 25, 48),
	"white_ruthenia": Color8(239, 238, 215),
	"byelorussian_ssr": Color8(178, 190, 191),
	"reformed_belarus": Color8(229, 232, 238),
	"pr_benin": Color8(29, 75, 212),
	"emu_empire": Color8(129, 76, 158),
	"australian_republic": Color8(199, 164, 153),
	"new_caledonia": Color8(122, 188, 208),
	"greenland": Color8(196, 197, 215),
	"aussa": Color8(130, 72, 96),
	"tannu_tuva": Color8(151, 130, 190),
	"manchukuo": Color8(255, 120, 71),
	"mengjiang": Color8(185, 255, 152),
	"sinkiang": Color8(71, 190, 152),
	"tibet": Color8(80, 115, 45),
	"ma_clique": Color8(105, 90, 132),
	"shanxi_clique": Color8(82, 2, 15),
	"yunnan_clique": Color8(114, 148, 80),
	"guangxi_clique": Color8(71, 113, 97),
	"jabal_shammar": Color8(222, 84, 10),
	"danzig": Color8(163, 183, 214),
	"cyrenaica": Color8(107, 107, 107),
	"patagonia": Color8(150, 71, 70),
	"west_indies": Color8(51, 13, 178),
	"california": Color8(242, 205, 95),
	"new_england": Color8(0, 107, 51),
	"mittelafrika": Color8(135, 104, 60),
	"lodomeria": Color8(161, 161, 161),
	"sicily": Color8(204, 204, 0),
	"sardinia": Color8(95, 206, 247),
	"german_east_asia": Color8(70, 94, 150),
	"bukhara": Color8(146, 106, 160),
	"khiva": Color8(203, 154, 104),
	"turkestan": Color8(0, 76, 152),
	"sichuan_clique": Color8(75, 47, 52),
	"hunan_clique": Color8(143, 20, 20),
	"shandong_clique": Color8(42, 96, 59),
	"legation_cities": Color8(0, 148, 255),
	"kumul_khanate": Color8(160, 82, 45),
	"borneo": Color8(185, 226, 255),
	"west_africa": Color8(105, 50, 0),
	"alaska": Color8(15, 32, 75),
	"pr_america": Color8(158, 26, 54),
	"lincoln": Color8(0, 212, 166),
	"montana": Color8(117, 57, 25),
	"utah": Color8(42, 69, 145),
	"nevada": Color8(206, 92, 23),
	"illinois": Color8(22, 0, 85),
	"texas": Color8(10, 40, 70),
	"midwest": Color8(255, 240, 60),
	"great_lakes": Color8(124, 201, 241),
	"hawaii": Color8(203, 84, 32),
	"central_america": Color8(172, 214, 236),
	"kurdistan": Color8(204, 172, 120),
	"north_ireland": Color8(230, 144, 68),
	"quebec": Color8(62, 219, 234),
	"alberta": Color8(74, 65, 184),
	"french_guiana": Color8(161, 200, 220),
	"scotland": Color8(202, 208, 115),
	"wales": Color8(219, 72, 78),
	"england": Color8(171, 106, 130),
	"anarchist_state": Color8(150, 60, 67),
	"guadeloupe": Color8(36, 69, 138),
	"hong_kong": Color8(248, 225, 231),
	"macau": Color8(214, 204, 97),
	"xinjiang": Color8(238, 218, 218),
	"communist_china": Color8(245, 12, 56),
	"canary_islands": Color8(249, 242, 228),
	"montserrat": Color8(156, 44, 72),
	"french_polynesia": Color8(0, 103, 170),
	"french_antarctica": Color8(0, 38, 84),
	"mayotte": Color8(212, 46, 18),
	"reunion": Color8(1, 112, 193),
	"indian_ocean": Color8(162, 67, 0),
	"bavaria": Color8(49, 58, 176),
	"wurttemberg": Color8(255, 110, 0),
	"baden": Color8(44, 84, 83),
	"brittany": Color8(99, 96, 141),
	"catalonia": Color8(249, 110, 91),
	"basque_country": Color8(156, 189, 140),
	"cornwall": Color8(115, 102, 66),
	"ryukyuan": Color8(54, 54, 54),
	"siberia": Color8(46, 74, 101),
	"chechnya": Color8(103, 132, 128),
	"jewish_oblast": Color8(224, 222, 246),
	"punjab": Color8(185, 250, 230),
}
