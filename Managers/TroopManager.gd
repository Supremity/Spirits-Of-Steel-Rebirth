extends Node

# --- CONFIGURATION ---
var AUTO_MERGE = true             # Auto-merge adjacent troops

# --- DATA STRUCTURES ---
var troops: Array = []                     # Master list of all troops
var moving_troops: Array = []              # Subset for _process updates
var troops_by_province: Dictionary = {}    # { province_id: [TroopData, ...] }
var troops_by_country: Dictionary = {}     # { country_name: [TroopData, ...] }

var path_cache: Dictionary = {}            # { start_id: { target_id: path_array } }
var flag_cache: Dictionary = {}            # { country_name: texture }

var troop_selection: TroopSelection


func _ready() -> void:
	set_process(false)


func change_merge() -> void:
	AUTO_MERGE = !AUTO_MERGE
	if AUTO_MERGE:
		if CountryManager and MapManager:
			var current_country = CountryManager.player_country.country_name
			var provinces = MapManager.country_to_provinces.get(current_country, [])
			for prov in provinces:
				_auto_merge_in_province(prov, current_country)


func _process(delta: float) -> void:
	if moving_troops.is_empty():
		set_process(false)
		return

	var snapshot := moving_troops.duplicate() # Shallow copy for safe iteration

	for troop in snapshot:
		if not troops.has(troop):
			continue # Troop was removed (e.g., by combat)

		_update_smooth(troop, delta)


func _update_smooth(troop: TroopData, delta: float) -> void:
	var start = troop.get_meta("start_pos", troop.position)
	var end = troop.target_position
	var total_dist = start.distance_to(end)
	if total_dist < 0.001:
		_arrive_at_leg_end(troop)
		return

	# --- Stage 1: Visual indicator ---
	var visual_progress = troop.get_meta("visual_progress", 0.0)
	visual_progress += GameState.current_world.clock.time_scale * delta / total_dist
	if visual_progress > 1.0:
		visual_progress = 1.0  # cap at 1
	troop.set_meta("visual_progress", visual_progress)

	# --- Stage 2: Actual troop movement ---
	var move_progress = troop.get_meta("progress", 0.0)
	if visual_progress >= 1.0:
		move_progress += GameState.current_world.clock.time_scale * delta / total_dist
		if move_progress >= 1.0:
			troop.position = end
			troop.set_meta("progress", 0.0)
			troop.set_meta("visual_progress", 0.0)
			_arrive_at_leg_end(troop)
		else:
			troop.position = start.lerp(end, move_progress)
			troop.set_meta("progress", move_progress)



"""
This happens right before a Troop starts moving into the next province
"""
func _start_next_leg(troop: TroopData) -> void:
	if troop.path.is_empty():
		return
	
	var next_pid = troop.path[0]
	
	# Check for hostile troops in the next province
	var troopsExist: Array = troops_by_province.get(next_pid, [])
	
	var enemy_troops = troopsExist.filter(func(t): 
		return WarManager.is_at_war_names(t.country_name, troop.country_name))

	if not enemy_troops.is_empty():
		WarManager.start_battle(troop.province_id, next_pid)
		pause_troop(troop) 
		for enemy in enemy_troops:
			pause_troop(enemy)
		return
	
	
	# Set the target position to the center of the next province
	troop.target_position = MapManager.province_centers.get(int(next_pid), troop.position)
	troop.set_meta("start_pos", troop.position)
	
	troop.set_meta("progress", 0.0)
	
	# Enable processing
	troop.is_moving = true
	if not moving_troops.has(troop):
		moving_troops.append(troop)
	if not is_processing():
		set_process(true)

"""
When a Troop has entered the province
"""
func _arrive_at_leg_end(troop: TroopData) -> void:
	if troop.path.is_empty():
		_stop_troop(troop)
		return

	var next_pid = troop.path.pop_front()

	_move_troop_to_province_logically(troop, next_pid)
	WarManager.resolve_province_arrival(next_pid, troop) 
	
	if not troops.has(troop): return
	
	if troop.is_moving:
		if troop.path.is_empty():
			_stop_troop(troop)
			if AUTO_MERGE and troops.has(troop):
				_auto_merge_in_province(troop.province_id, troop.country_name)
		else:
			_start_next_leg(troop)



## Deletes Troop Path and stops it moving
func _stop_troop(troop: TroopData) -> void:
	moving_troops.erase(troop)
	troop.is_moving = false
	troop.path.clear()
	if moving_troops.is_empty():
		set_process(false)

# Pause a troop along its path
func pause_troop(troop: TroopData) -> void:
	if moving_troops.has(troop):
		moving_troops.erase(troop)
	
	# Prevents troop from trying to move into invalid positions or (0,0) after resume. (Happens in very rare cases)
	troop.target_position = troop.position 

	troop.is_moving = false
	if moving_troops.is_empty():
		set_process(false)
		
func resume_troop(troop: TroopData) -> void:
	if troop.path.is_empty():
		print("Cannot resume troop. No path set")
		return

	# FIX: If the target is basically where we are standing, it means
	# _start_next_leg aborted early (due to battle). We must restart the leg logic.
	if troop.position.distance_squared_to(troop.target_position) < 1.0:
		_start_next_leg(troop)
		return

	if not moving_troops.has(troop):
		moving_troops.append(troop)

	troop.is_moving = true
	
	if not is_processing():
		set_process(true)


# =============================================================
# COMMAND & PATHFINDING
# =============================================================
## Public entry point for a single troop move order.
func order_move_troop(troop: TroopData, target_pid: int) -> void:
	command_move_assigned([ { "troop": troop, "province_id": target_pid } ])


func command_move_assigned(payload: Array) -> void:
	if payload.is_empty(): return

	# 1. Setup Allowed Countries
	var country = payload[0].get('troop').country_name
	var allowedCountries: Array[String] = CountryManager.get_country(country).allowedCountries


	# 2. Data containers
	# maps: troop -> { "targets": [id, id], "paths": { target_id: path_array } }
	var troop_to_targets: Dictionary = {} 
	
	# Track unique paths to calculate only once per batch
	# Key: Vector2i(start, end), Value: path_array (or null initially)
	var unique_paths_needed: Dictionary = {} 

	var sfx_played = false

	# --- PHASE 1: Grouping & Identification ---
	for entry in payload:
		var troop = entry.get("troop")
		var target_pid = entry.get("province_id")
		
		if not troop or target_pid <= 0: continue

		# Play SFX only once
		if not sfx_played and troop.country_name == CountryManager.player_country.country_name:
			if MusicManager: MusicManager.play_sfx(MusicManager.SFX.TROOP_MOVE)
			sfx_played = true

		var start_id = troop.province_id
		
		# STOP CONDITION: Don't move if already there
		if start_id == target_pid: continue

		# Initialize troop data if new
		if not troop_to_targets.has(troop):
			troop_to_targets[troop] = { "targets": [], "paths": {} }
		
		var data = troop_to_targets[troop]
		
		# Add target if unique for this troop
		if not data["targets"].has(target_pid):
			data["targets"].append(target_pid)
			
		# Mark this path as "needed"
		# OPTIMIZATION: Vector2i Key
		var path_key = Vector2i(start_id, target_pid)
		unique_paths_needed[path_key] = null 

	# --- PHASE 2: Batch Pathfinding ---
	# We calculate each unique path exactly once
	for key in unique_paths_needed.keys():
		var start = key.x
		var end = key.y
		# Call our optimized cache getter
		unique_paths_needed[key] = _get_cached_path(start, end, allowedCountries)

	# --- PHASE 3: Assignment & Execution ---
	for troop in troop_to_targets:
		var data = troop_to_targets[troop]
		var targets = data["targets"]
		
		# Collect the calculated paths for this troop
		var valid_paths = {}
		var valid_targets = []
		
		for t_pid in targets:
			var key = Vector2i(troop.province_id, t_pid)
			var path = unique_paths_needed.get(key)
			
			if path and not path.is_empty():
				valid_paths[t_pid] = path
				valid_targets.append(t_pid)

		# Execute Split or Move
		if valid_targets.size() > 1:
			_split_and_send_troop(troop, valid_targets, valid_paths)
		elif valid_targets.size() == 1:
			var target = valid_targets[0]
			var final_path = valid_paths[target]
			
			# Apply path to troop
			troop.path = final_path.duplicate()
			# IMPORTANT: Pop the first node (current location) immediately
			if not troop.path.is_empty() and troop.path[0] == troop.province_id:
				troop.path.pop_front()
				
			_start_next_leg(troop)


func _get_cached_path(start_id: int, target_id: int, allowed_countries: Array[String]) -> Array:
	if start_id == target_id: return []

	var key = Vector2i(start_id, target_id)
	if path_cache.has(key):
		return path_cache[key].duplicate()
	
	var path = MapManager.find_path(start_id, target_id, allowed_countries)

	if not path.is_empty() and path[0] == start_id:
		path.pop_front()

	if not path.is_empty():
		path_cache[key] = path.duplicate()
		
	return path


# =============================================================
# SPLIT & MANEUVER
# =============================================================
func _split_and_send_troop(original_troop: TroopData, target_pids: Array, paths: Dictionary) -> void:
	var total_divs = original_troop.divisions
	var num_targets = target_pids.size()
	
	if num_targets == 0: return
	# Prevent splitting if we don't have enough troops for 1 per target
	if total_divs < num_targets: return 

	@warning_ignore("integer_division")
	var base_divs = total_divs / num_targets
	var remainder = total_divs % num_targets
	
	# We use this flag to ensure we reuse the 'original_troop' exactly once
	var original_reused = false

	for i in range(num_targets):
		var target_pid = target_pids[i]
		
		# 1. Calculate Division Count
		var divs = base_divs
		if i < remainder: divs += 1
		
		# 2. Assign Troop Object
		# We try to reuse the original object for the first chunk (i=0) to save memory/processing
		var troop_to_move: TroopData
		
		if not original_reused:
			troop_to_move = original_troop
			troop_to_move.divisions = divs
			original_reused = true
		else:
			troop_to_move = _create_new_split_troop(original_troop, divs)
		
		# 3. Handle Movement
		if target_pid == original_troop.province_id:
			# Case: Troop stays here
			troop_to_move.path.clear()
			_stop_troop(troop_to_move)
			# Force auto-merge check since we might have just created a new stack here
			if AUTO_MERGE:
				_auto_merge_in_province(target_pid, troop_to_move.country_name)
		else:
			# Case: Troop moves away
			var path = paths.get(target_pid)
			
			# Only move if we actually have a valid path
			if path and path.size() > 0:
				troop_to_move.path = path.duplicate()
				
				# Sanitize: If path[0] is where we are, remove it
				if not troop_to_move.path.is_empty() and troop_to_move.path[0] == troop_to_move.province_id:
					troop_to_move.path.pop_front()
				
				_start_next_leg(troop_to_move)
			else:
				# Fallback: Path failed, just stay put (don't lose the troops!)
				_stop_troop(troop_to_move)

	print("Split %s (%d divs) into %d armies" % [original_troop.country_name, total_divs, num_targets])


## Creates and registers a new troop object resulting from a split.
func _create_new_split_troop(original: TroopData, divisions: int) -> TroopData:
	var pos = original.position
	# Use the existing create_troop function's core logic
	var new_troop = load("res://Scripts/TroopData.gd").new(
		original.country_name,
		original.province_id,
		divisions,
		pos,
		original.flag_texture
	)

	# Copy runtime metadata for new troop
	new_troop.is_moving = false
	new_troop.path = []
	new_troop.set_meta("start_pos", pos)
	new_troop.set_meta("time_left", 0.0)
	new_troop.set_meta("progress", 0.0)

	# Register the new troop in all indexes
	troops.append(new_troop)
	_add_troop_to_indexes(new_troop)

	return new_troop


# =============================================================
# TROOP MANAGEMENT & CREATION
# =============================================================
## Creates a new troop and registers it in all indexes.
func create_troop(country: String, divs: int, prov_id: int) -> TroopData:
	if divs <= 0: return null

	# 1. Flag caching
	if not flag_cache.has(country):
		var path = "res://assets/flags/%s_flag.png" % country.to_lower()
		flag_cache[country] = load(path) if ResourceLoader.exists(path) else null

	var pos = MapManager.province_centers.get(prov_id, Vector2.ZERO)
	var troop = load("res://Scripts/TroopData.gd").new(
		country,
		prov_id,
		divs,
		pos,
		flag_cache.get(country)
	)

	# 2. Critical: initialize runtime metadata
	troop.set_meta("start_pos", pos)
	troop.set_meta("time_left", 0.0)
	troop.set_meta("progress", 0.0)
	troop.is_moving = false
	troop.path = []
	troop.province_id = prov_id

	# 3. Add to master list and indexes
	troops.append(troop)
	_add_troop_to_indexes(troop)

	# 4. Auto-merge if enabled
	if AUTO_MERGE:
		_auto_merge_in_province(prov_id, country)

	return troop


func _auto_merge_in_province(province_id: int, country: String) -> void:
	if not AUTO_MERGE:
		return

	var local_troops = troops_by_province.get(province_id, [])
	var same_country: Array = []

	# Collect unmoving troops
	for t in local_troops:
		if t.country_name == country and not t.is_moving:
			same_country.append(t)

	if same_country.size() <= 1:
		return

	var primary = same_country[0]
	var to_remove = []

	# Merge the rest
	for i in range(1, same_country.size()):
		var secondary = same_country[i]
		primary.divisions += secondary.divisions
		to_remove.append(secondary)

	# Remove AFTER merging to avoid breaking the list while iterating
	for troop in to_remove:
		_remove_troop(troop)


# =============================================================
# WAR MANAGER INTERFACE (Hooks for Combat & Strategy)
# =============================================================
## Public hook for the WarManager to remove a troop that has lost a battle.
func remove_troop_by_war(troop: TroopData) -> void:
	_remove_troop(troop)


## Public hook for the WarManager to force a troop to its home province center.
func move_to_garrison(troop: TroopData) -> void:
	var center = MapManager.province_centers.get(troop.province_id, troop.position)
	troop.position = center
	troop.target_position = center
	_stop_troop(troop) # Stops any ongoing movement


# =============================================================
# INDEXING HELPERS (Internal Maintenance)
# =============================================================
## Adds a troop reference to the spatial and country dictionaries.
func _add_troop_to_indexes(troop: TroopData) -> void:
	var pid = troop.province_id
	var country = troop.country_name
	
	# Province Index
	if not troops_by_province.has(pid):
		troops_by_province[pid] = []
	troops_by_province[pid].append(troop)

	# Country Index
	if not troops_by_country.has(country):
		troops_by_country[country] = []
	troops_by_country[country].append(troop)


## Removes a troop reference from all data structures (master, moving, indexes).
func _remove_troop(troop: TroopData) -> void:
	# 1. Master lists
	troops.erase(troop)
	moving_troops.erase(troop)
	
	var pid = troop.province_id
	var country = troop.country_name
	
	# 2. Province Index
	if troops_by_province.has(pid):
		troops_by_province[pid].erase(troop)
		if troops_by_province[pid].is_empty():
			troops_by_province.erase(pid)
			
	# 3. Country Index
	if troops_by_country.has(country):
		troops_by_country[country].erase(troop)


## Updates the troop's location in the spatial index (troops_by_province).
func _move_troop_to_province_logically(troop: TroopData, new_pid: int) -> void:
	var old_pid = troop.province_id
	if old_pid == new_pid: return
	
	# Remove from old province list
	if troops_by_province.has(old_pid):
		troops_by_province[old_pid].erase(troop)
		if troops_by_province[old_pid].is_empty():
			troops_by_province.erase(old_pid)
			
	# Add to new province list and update troop object
	troop.province_id = new_pid
	if not troops_by_province.has(new_pid):
		troops_by_province[new_pid] = []
	troops_by_province[new_pid].append(troop)

# Careful using this
func teleport_troop_to_province(troop: TroopData, target_pid: int) -> void:
	# Remove from old province index
	var old_pid = troop.province_id
	if troops_by_province.has(old_pid):
		troops_by_province[old_pid].erase(troop)
		if troops_by_province[old_pid].is_empty():
			troops_by_province.erase(old_pid)

	# Update troop province
	troop.province_id = target_pid
	
	# Update troop position immediately to center of target province
	troop.position = MapManager.province_centers.get(target_pid, Vector2.ZERO)
	troop.target_position = troop.position
	troop.path.clear()
	troop.set_meta("start_pos", troop.position)
	troop.set_meta("progress", 0.0)
	troop.is_moving = false

	# Add to new province index
	if not troops_by_province.has(target_pid):
		troops_by_province[target_pid] = []
	troops_by_province[target_pid].append(troop)


func get_province_division_count(pid: int) -> int:
	var total = 0
	var list = troops_by_province.get(pid, [])
	for troop in list:
		total += troop.divisions
	return total
	

func have_troops_in_both_provinces(province_id_a: int, province_id_b: int) -> bool:
	var has_troops_in_a: bool = troops_by_province.has(province_id_a)
	var has_troops_in_b: bool = troops_by_province.has(province_id_b)
	return has_troops_in_a and has_troops_in_b

func clear_path_cache() -> void:
	path_cache.clear()
	print ("Pathfinding cache cleared")


# Remove leading waypoints that are equal to the troop's current province.
func _sanitize_path_for_troop(path: Array, start_pid: int) -> Array:
	if not path:
		return []
	# Duplicate to avoid mutating caller arrays
	var p = path.duplicate()
	# Pop front while first entry equals start_pid
	while p.size() > 0 and int(p[0]) == int(start_pid):
		p.pop_front()
	return p


# extra helper functions. Not made by AI
func get_troops_for_country(country):
	return troops_by_country.get(country, [])


func get_troops_in_province(province_id):
	return troops_by_province.get(province_id, [])


func get_province_strength(pid: int, country: String) -> int:
	var total = 0
	var list = troops_by_province.get(pid, [])
	for t in list:
		if t.country_name == country:
			total += t.divisions
	return total

func destroy_force_in_province(pid: int, country: String) -> void:
	var list = troops_by_province.get(pid, []).duplicate()
	for t in list:
		if t.country_name == country:
			_remove_troop(t)


# Used by popup for now
func get_flag(country: String) -> Texture2D:
	# Normalize the key
	country = country.to_lower()

	# If already cached → return it
	if flag_cache.has(country):
		return flag_cache[country]

	# Build the file path
	var path = "res://assets/flags/%s_flag.png" % country

	# Load if exists
	if ResourceLoader.exists(path):
		var tex := load(path)
		flag_cache[country] = tex
		return tex

	# Fallback texture (optional)
	print("Flag not found for country:", country)
	return null
