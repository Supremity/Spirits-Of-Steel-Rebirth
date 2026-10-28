extends Node

var AUTO_MERGE = true

var emptyLatch: bool = false

var to_remove: Array = []
var troops: Array = []
var moving_troops: Array = []
var troops_by_province: Dictionary[int, Array] = {} # { province_id: [TroopData, ...] }
var troops_by_country: Dictionary[String, Array] = {} # { country_name: [TroopData, ...] }

var path_cache: Dictionary = {} # { start_id: { target_id: path_array } }
var flag_cache: Dictionary = {} # { country_name: texture }

var troop_selection: TroopSelection


func clear_all_troops() -> void:
	troops.clear()
	moving_troops.clear()
	troops_by_province.clear()
	troops_by_country.clear()
	path_cache.clear()
	flag_cache.clear()
	#print("TroopManager: All troops and caches cleared.")


func _process(delta: float) -> void:
	for troop in moving_troops:
		_update_moving_troop(troop, delta)


func _update_moving_troop(troop: TroopData, delta: float) -> void:
	if GameState.current_world.clock.paused:
		return

	if troop.country_obj == null:
		troop.country_obj = CountryManager.countries.get(troop.country_name)
	
	var targetPID = troop.path.front()
	var enemies = troops_by_province.get(targetPID, []).filter(
		func(t):
			return WarManager.is_at_war_names(t.country_name, troop.country_name)
	)

	if not enemies.is_empty() and not GameState.current_world.clock.paused:
		WarManager.start_battle(troop.province_id, targetPID)
		pause_troop(troop)
		for enemy in enemies:
			pause_troop(enemy)
		return

	var start = troop.get_meta("start_pos", troop.position)
	var end = troop.target_position
	var total_dist = start.distance_to(end)

	# Safety check for instant arrival
	if total_dist < 0.5:
		troop.position = end
		_arrive_at_leg_end(troop)
		return

	# Unified progress calculation
	var move_progress = troop.get_meta("progress", 0.0)

	var base_speed = 1

	# Increment progress based on real-time and game speed
	move_progress += (base_speed * (troop.country_obj.troop_speed_modifier if troop.country_obj else 1.0) * GameState.current_world.clock.time_scale * delta) / total_dist

	if move_progress >= 1.0:
		troop.position = end
		troop.set_meta("progress", 0.0)
		_arrive_at_leg_end(troop)
	else:
		# Smoothly slide from A to B
		troop.position = start.lerp(end, move_progress)
		troop.set_meta("progress", move_progress)


func _start_next_leg(troop: TroopData) -> void:
	if troop.path.is_empty():
		_stop_troop(troop)
		return

	var next_pid = troop.path[0]

	# Check for Combat (WarManager logic)
	var local_troops = troops_by_province.get(next_pid, [])
	var enemies = local_troops.filter(
		func(t): return WarManager.is_at_war_names(t.country_name, troop.country_name) && t
	)

	if !enemies.is_empty() and not GameState.current_world.clock.paused:
		WarManager.start_battle(troop.province_id, next_pid)
		pause_troop(troop)
		for enemy in enemies:
			pause_troop(enemy)
		return

	# Update targets and start movement
	troop.target_position = MapManager.province_centers.get(int(next_pid), troop.position)
	troop.set_meta("start_pos", troop.position)
	troop.set_meta("progress", 0.0)
	troop.is_moving = true

	if !moving_troops.has(troop):
		moving_troops.append(troop)


func _arrive_at_leg_end(troop: TroopData) -> void:
	if troop.path.is_empty():
		_stop_troop(troop)
		return

	# Logic move: Update which province the troop is 'officially' in
	var arrived_pid = troop.path.pop_front()
	_move_troop_to_province_logically(troop, arrived_pid)

	# Trigger occupation/events
	WarManager.resolve_province_arrival(arrived_pid, troop)

	# Check if we keep going or stop
	if troop.path.is_empty():
		_stop_troop(troop)
		if AUTO_MERGE:
			_auto_merge_in_province(troop.province_id, troop.country_name)
	else:
		_start_next_leg(troop)


func _stop_troop(troop: TroopData) -> void:
	moving_troops.erase(troop)
	troop.is_moving = false
	troop.path.clear()


# Pause a troop along its path
func pause_troop(troop: TroopData) -> void:
	moving_troops.erase(troop)
	troop.target_position = troop.position
	troop.is_moving = false


func command_move_assigned(payload: Array) -> void:
	if payload.is_empty():
		return

	# 1. Group the payload by troop
	# We need this because one source troop might be the "parent" for 5 different moves
	var troop_to_moves = {}
	for entry in payload:
		var t = entry.get("troop")
		if not t:
			continue
		if not troop_to_moves.has(t):
			troop_to_moves[t] = []
		troop_to_moves[t].append(entry)

	# 2. Process each source troop
	for troop in troop_to_moves:
		var moves = troop_to_moves[troop]

		# Sort moves so that the one requiring the MOST divisions happens last
		# This allows us to keep the original troop node for the "main" objective
		moves.sort_custom(func(a, b): return a.get("divisions", 1) < b.get("divisions", 1))

		for i in range(moves.size()):
			var move_data = moves[i]
			var requested_count = int(move_data.get("divisions", 1))

			# If this is the last move in the list OR we are requesting everything left
			if i == moves.size() - 1 or requested_count >= troop.stored_divisions.size():
				# No splitting needed for the final move; just move the original troop
				_apply_movement_path(troop, move_data["province_id"])
				break
			else:
				# Splitting logic:
				var batch: Array[DivisionData] = []
				for j in range(requested_count):
					if not troop.stored_divisions.is_empty():
						batch.append(troop.stored_divisions.pop_back()) # Take from the end

				if batch.is_empty():
					continue

				# Create a new troop node for this small "detachment"
				_apply_movement_path(_create_new_split_troop(troop, batch), move_data["province_id"])


# Helper to keep your code clean
func _apply_movement_path(troop: TroopData, target_pid: int) -> void:
	if troop.province_id == target_pid:
		_return_to_province_center(troop)
		return

	var allowed = troop.country_obj.get_all_allowed_countries()
	var path = _get_cached_path(troop.province_id, target_pid, allowed)

	if not path.is_empty():
		troop.path = path.duplicate()
		if int(troop.path[0]) == int(troop.province_id):
			troop.path.pop_front()

		troop.set_meta("start_pos", troop.position)
		_start_next_leg(troop)
	else:
		_return_to_province_center(troop)


# Stops the troop, but if it was caught mid-leg, walks it back to its province center
# so it doesn't stay stranded between provinces.
func _return_to_province_center(troop: TroopData) -> void:
	var center = MapManager.province_centers.get(troop.province_id, troop.position)
	if troop.position.distance_to(center) < 0.5:
		troop.position = center
		_stop_troop(troop)
		return

	troop.path = [troop.province_id]
	_start_next_leg(troop)


func _get_cached_path(start_id: int, target_id: int, allowed_countries: Array[String]) -> Array:
	if start_id == target_id:
		return []

	# Sort and hash allowed_countries to ensure the cache key is unique per set of permissions.
	var sorted_allowed = allowed_countries.duplicate()
	sorted_allowed.sort()
	var allowed_hash = str(sorted_allowed).hash()
	var key = "%d_%d_%d" % [start_id, target_id, allowed_hash]

	if path_cache.has(key):
		return path_cache[key].duplicate()

	var path = MapManager.find_path(start_id, target_id, allowed_countries)

	if not path.is_empty() and path[0] == start_id:
		path = path.slice(1)
		# path.pop_front()

	if not path.is_empty():
		path_cache[key] = path.duplicate()

	return path


func _split_and_send_troop(troop: TroopData, target_pids: Array, paths: Dictionary) -> void:
	var num_targets = target_pids.size()
	var total_divs = troop.divisions_count

	if num_targets == 0 or total_divs < num_targets:
		return

	# 1. Sort targets by distance to move the "heaviest" part of the stack the shortest distance
	var target_distances: Array = []
	for pid in target_pids:
		var dist = MapManager.heuristic(troop.province_id, pid)
		target_distances.append({"pid": pid, "dist": dist})
	target_distances.sort_custom(func(a, b): return a.dist < b.dist)

	# 2. Calculate distribution
	@warning_ignore("integer_division")
	var base_count: int = total_divs / num_targets
	var remainder: int = total_divs % num_targets

	var original_used = false
	var current_div_index = 0

	# We duplicate the array reference so we can slice it safely
	var all_divisions = troop.stored_divisions.duplicate()

	for i: int in range(num_targets):
		var pid: int = target_distances[i].pid

		# Determine how many divisions go to this specific target
		var count_for_this_leg = base_count
		if i < remainder:
			count_for_this_leg += 1

		# SLICE: Take the specific objects for this batch
		var divisions_for_this_leg: Array[DivisionData] = []
		for d in range(count_for_this_leg):
			if current_div_index < all_divisions.size():
				divisions_for_this_leg.append(all_divisions[current_div_index])
				current_div_index += 1

		var troop_to_move: TroopData

		if !original_used:
			# The original troop instance stays alive and takes the first batch
			troop_to_move = troop
			troop_to_move.stored_divisions = divisions_for_this_leg
			original_used = true
		else:
			# Create a brand new TroopData for the other batches
			# This function must handle country_obj assignment!
			troop_to_move = _create_new_split_troop(troop, divisions_for_this_leg)

		# 3. Assign movement
		if pid == troop_to_move.province_id:
			# This part of the split is staying in the current province
			troop_to_move.path.clear()
			_stop_troop(troop_to_move)
			if AUTO_MERGE:
				_auto_merge_in_province(pid, troop_to_move.country_name)
		else:
			# This part of the split is moving to a new target
			var path = paths.get(pid)
			if path and path.size() > 0:
				var new_path = path.duplicate()
				# If the path starts with current province, remove it
				if new_path[0] == troop_to_move.province_id:
					new_path.pop_front()

				troop_to_move.path = new_path
				_start_next_leg(troop_to_move)
			else:
				_stop_troop(troop_to_move)


func _create_new_split_troop(original: TroopData, specific_divisions: Array) -> TroopData:
	var pos: Vector2 = original.position

	var new_troop: TroopData = TroopData.new(
		original.country_name, original.province_id, 0, pos, TroopManager.get_flag(original.country_name)
	)

	# FIX: Ensure the new split troop knows which country it belongs to
	new_troop.country_obj = original.country_obj

	# Immediately overwrite the empty array with our specific divisions
	new_troop.stored_divisions = specific_divisions

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


func create_troop(country: String, divs: int, prov_id: int) -> TroopData:
	if divs <= 0:
		return null

	var country_data: CountryData = CountryManager.countries.get(country)
	var pos: Vector2 = MapManager.province_centers.get(prov_id, Vector2.ZERO)

	var troop: TroopData = TroopData.new(
		country, prov_id, divs, pos, get_flag(country, country_data.ideology_name if country_data else "")
	)

	# FIX: Assign the country object reference
	troop.country_obj = country_data

	# Initialize runtime metadata
	troop.set_meta("start_pos", pos)
	troop.set_meta("time_left", 0.0)
	troop.set_meta("progress", 0.0)
	troop.is_moving = false
	troop.path = []
	troop.province_id = prov_id

	troops.append(troop)
	_add_troop_to_indexes(troop)

	if AUTO_MERGE:
		_auto_merge_in_province(prov_id, country)

	return troop


func _auto_merge_in_province(province_id: int, country: String) -> void:
	if !AUTO_MERGE:
		return

	var candidates: Array[TroopData] = []

	# 1. Collect Valid Candidates
	for t: TroopData in troops_by_province.get(province_id, []):
		if t.country_name == country && !t.is_moving:
			candidates.append(t)

	if candidates.size() <= 1:
		return

	# 2. Pick the BEST Primary (The one to keep)
	var primary: TroopData = candidates[0]
	var current_selection: TroopData = null

	# Check selection safely
	if troop_selection && "selected_troop" in troop_selection:
		current_selection = troop_selection.selected_troop

	for i: int in range(1, candidates.size()):
		var current: TroopData = candidates[i]

		# Prioritize keeping the selected unit
		if current_selection && current_selection == current:
			primary = current
			break

		# Keep the one with the most divisions
		if current.divisions_count > primary.divisions_count:
			primary = current

	# 3. Merge others into Primary
	for t: TroopData in candidates:
		if t == primary:
			continue

		# MERGE ARRAYS: Transfer divisions from 't' to 'primary'
		primary.stored_divisions.append_array(t.stored_divisions)

		# Clear 't' divisions so they don't get messy during deletion
		t.stored_divisions.clear()

		RemoveTroop(t)

		# Update selection if we just merged the selected unit into another
		if current_selection && current_selection == t:
			if troop_selection.has_method("select_troop"):
				troop_selection.select_troop(primary)
			elif "selected_troop" in troop_selection:
				troop_selection.selected_troop = primary

func RemoveTroop(troop: TroopData) -> void:
	troops.erase(troop)
	moving_troops.erase(troop)

	var pid: int = troop.province_id
	var countryName: String = troop.country_name
	var country: CountryData = CountryManager.countries.get(countryName)

	if troops_by_province.has(pid):
		troops_by_province[pid].erase(troop)
		if troops_by_province[pid].is_empty():
			troops_by_province.erase(pid)

	if troops_by_country.has(countryName):
		troops_by_country[countryName].erase(troop)
	
	if country:
		for div: DivisionData in troop.stored_divisions:
			country.mobilized -= int(div.hp * div.manpowerPerHP)

## Public hook for the WarManager to force a troop to its home province center.
func move_to_garrison(troop: TroopData) -> void:
	var center: Vector2 = MapManager.province_centers.get(troop.province_id, troop.position)
	troop.position = center
	troop.target_position = center
	_stop_troop(troop) # Stops any ongoing movement


## Adds a troop reference to the spatial and country dictionaries.
func _add_troop_to_indexes(troop: TroopData) -> void:
	var pid: int = troop.province_id
	var country: String = troop.country_name

	# Province Index
	if !troops_by_province.has(pid):
		troops_by_province[pid] = [troop]
	else:
		troops_by_province[pid].append(troop)

	# Country Index
	if !troops_by_country.has(country):
		troops_by_country[country] = [troop]
	else:
		troops_by_country[country].append(troop)

## Updates the troop's location in the spatial index (troops_by_province).
func _move_troop_to_province_logically(troop: TroopData, new_pid: int) -> void:
	var old_pid = troop.province_id
	if old_pid == new_pid:
		return

	# Remove from old province list
	if troops_by_province.has(old_pid):
		troops_by_province[old_pid].erase(troop)
		if troops_by_province[old_pid].is_empty():
			troops_by_province.erase(old_pid)

	# Add to new province list and update troop object
	troop.province_id = new_pid
	if !troops_by_province.has(new_pid):
		troops_by_province[new_pid] = [troop]
	else:
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
	if !troops_by_province.has(target_pid):
		troops_by_province[target_pid] = [troop]
	else:
		troops_by_province[target_pid].append(troop)


func get_serialized_troops_for_province(pid: int) -> Array:
	var troop_data: Array = []
	for troop: TroopData in troops_by_province.get(pid, []):
		troop_data.append(troop.ToDict())
	return troop_data


func load_troops_for_province(pid: int, troop_data: Array) -> void:
	# Clear existing troops in this province if any (might not be needed if loading fresh)
	# But generally we should probably clear first
	if troops_by_province.has(pid):
		for t in troops_by_province[pid].duplicate():
			RemoveTroop(t)
	
	for data in troop_data:
		var troop = TroopData.FromDict(data)
		troop.province_id = pid
		troop.position = MapManager.province_centers.get(pid, Vector2.ZERO)
		if troop.is_moving:
			troop.target_position = Vector2(data["target_position"][0], data["target_position"][1])
		else:
			troop.target_position = troop.position
		
		# Ensure country_obj is assigned
		var country_ref = CountryManager.countries.get(troop.country_name)
		if !country_ref:
			push_error("TroopManager: Failed to load troop in province %d - country '%s' not found!" % [pid, troop.country_name])
			continue
		troop.country_obj = country_ref
		
		# Add to managers
		troops.append(troop)
		_add_troop_to_indexes(troop)
		
		if troop.is_moving && !moving_troops.has(troop):
			moving_troops.append(troop)


func get_province_division_count(pid: int) -> int:
	var total: int = 0
	for troop: TroopData in troops_by_province.get(pid, []):
		total += troop.divisions_count
	return total


func have_troops_in_both_provinces(province_id_a: int, province_id_b: int) -> bool:
	return troops_by_province.has(province_id_a) && troops_by_province.has(province_id_b)


func clear_path_cache() -> void:
	path_cache.clear()
	#print("Pathfinding cache cleared")


# Remove leading waypoints that are equal to the troop's current province.
func _sanitize_path_for_troop(path: Array, start_pid: int) -> Array:
	if !path:
		return []
	# Duplicate to avoid mutating caller arrays
	var p: Array = path.duplicate()
	# Pop front while first entry equals start_pid
	while p.size() > 0 and int(p[0]) == int(start_pid):
		p.pop_front()
	return p


# extra helper functions. Not made by AI
func get_troops_for_country(country: String) -> Array:
	return troops_by_country.get(country, [])


func get_troops_in_province(province_id: int) -> Array:
	return troops_by_province.get(province_id, [])


func get_province_strength(pid: int, country: String) -> int:
	var total: int = 0
	for t: TroopData in troops_by_province.get(pid, []):
		if t.country_name == country:
			total += t.divisions_count
	return total

func DeployReady(
	country: String, a_readyTroops: CountryData.ReadyTroop, prov_id: int
) -> TroopData:
	var country_data = CountryManager.countries.get(country)
	var pos = MapManager.province_centers.get(prov_id, Vector2.ZERO)

	# 1. Create the container (TroopData) with 0 divisions initially
	var troop = TroopData.new(
		country, prov_id, 0, pos, get_flag(country, country_data.ideology_name if country_data else "")
	)

	# 2. Inject the specific divisions we trained
	for i: int in range(a_readyTroops.count):
		troop.stored_divisions.append(a_readyTroops.division.duplicate())

	# 3. Setup Runtime Metadata
	troop.set_meta("start_pos", pos)
	troop.set_meta("time_left", 0.0)
	troop.set_meta("progress", 0.0)
	troop.is_moving = false
	troop.path = []
	troop.province_id = prov_id

	# 4. Register
	troops.append(troop)
	_add_troop_to_indexes(troop)

	if AUTO_MERGE:
		_auto_merge_in_province(prov_id, country)

	return troop

func deploy_specific_divisions(
	country: String, divisions_to_deploy: Array, prov_id: int
) -> TroopData:
	if divisions_to_deploy.is_empty():
		return null

	var country_data = CountryManager.countries.get(country)

	var pos = MapManager.province_centers.get(prov_id, Vector2.ZERO)

	# 1. Create the container (TroopData) with 0 divisions initially
	var troop = TroopData.new(
		country, prov_id, 0, pos, get_flag(country, country_data.ideology_name if country_data else "")
	)

	# 2. Inject the specific divisions we trained
	troop.stored_divisions = divisions_to_deploy

	# 3. Setup Runtime Metadata
	troop.set_meta("start_pos", pos)
	troop.set_meta("time_left", 0.0)
	troop.set_meta("progress", 0.0)
	troop.is_moving = false
	troop.path = []
	troop.province_id = prov_id

	# 4. Register
	troops.append(troop)
	_add_troop_to_indexes(troop)

	if AUTO_MERGE:
		_auto_merge_in_province(prov_id, country)

	return troop


# Used by popup for now
var flag_redirects: Dictionary = {}

func _ready() -> void:
	_load_flag_redirects()

func _load_flag_redirects() -> void:
	var path = "res://assets/flags/flag_redirects.json"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		if error == OK:
			flag_redirects = json.data
		else:
			push_error("TroopManager: Failed to parse flag_redirects.json")

var custom_flag_path: String = ""

func set_custom_flag_path(path: String):
	if path != "" and not path.ends_with("/"):
		path += "/"
	custom_flag_path = path
	flag_cache.clear() # Clear cache to force reload from new path


func get_flag(country: String, ideology: String = "") -> Texture2D:
	# Normalize the keys
	country = country.to_lower()
	ideology = ideology.to_lower()
	
	# Cache key needs to include ideology if provided
	var cache_key = country
	if ideology != "":
		cache_key = "%s_%s" % [country, ideology]

	# If already cached → return it
	if flag_cache.has(cache_key):
		return flag_cache[cache_key]

	# 0. Check Redirects
	if flag_redirects.has(country):
		var redirect = flag_redirects[country]
		var target_country = redirect["target"]
		var target_ideology = redirect["ideology"]
		
		if ideology != "":
			return get_flag(target_country, ideology)
		else:
			return get_flag(target_country, target_ideology)

	var path = ""
	
	# Helper to check both custom and default locations
	var find_resource = func(sub_path: String):
		if custom_flag_path != "":
			var full_custom = custom_flag_path + sub_path
			if ResourceLoader.exists(full_custom):
				return full_custom
		var full_default = "res://assets/flags/%s" % [sub_path]
		if ResourceLoader.exists(full_default):
			return full_default
		return ""

	# 1. Try Specific Ideology Flag: {path}/country/ideology_flag.png
	if ideology != "":
		path = find_resource.call("%s/%s_flag.png" % [country, ideology])
		if path != "":
			var tex := load(path)
			flag_cache[cache_key] = tex
			return tex

	# 2. Try Neutral/Default Flag in new structure: {path}/country/neutral_flag.png
	path = find_resource.call("%s/neutral_flag.png" % country)
	if path != "":
		var tex := load(path)
		flag_cache[cache_key] = tex
		return tex

	# 3. Fallback: Suffix Stripping / Semantic Fallback
	var suffixes = {
		"_kingdom": "monarchist",
		"_empire": "monarchist",
		"_republic": "liberal",
		"_commune": "communist",
		"_union": "communist",
		"_socialist": "communist",
		"_fascist": "facist",
		"_national": "facist",
		"_democratic": "liberal"
	}
	
	for suffix in suffixes:
		if country.ends_with(suffix):
			var base_country = country.left(country.length() - suffix.length())
			var fallback_ideology = suffixes[suffix]
			var check_ideology = ideology if ideology != "" else fallback_ideology
			
			var tex = get_flag(base_country, check_ideology)
			if tex:
				flag_cache[cache_key] = tex
				return tex
			
			if ideology != "":
				tex = get_flag(base_country, "")
				if tex:
					flag_cache[cache_key] = tex
					return tex

	# 4. Fallback to old flat structure (just in case): {path}/country_flag.png
	path = find_resource.call("%s_flag.png" % country)
	if path == "":
		path = find_resource.call("fallback_flag.png")
	
	if path != "":
		var tex := load(path)
		flag_cache[cache_key] = tex
		return tex

	return null


func find_troop_owning_division(div_to_find: DivisionData) -> TroopData:
	for t in troops:
		if div_to_find in t.stored_divisions:
			return t
	return null
