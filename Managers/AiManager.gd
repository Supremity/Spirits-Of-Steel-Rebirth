extends Node

# --- Constants for AI Tuning ---
const MIN_MONEY_RESERVE := 25000.0
const RECRUIT_MANPOWER_THRESHOLD := 15000


# --- Strategic Layer ---
func process_hour(country: CountryData) -> void:
	_ai_handle_deployment(country)
	_ai_consider_recruitment(country)
	#_ai_consider_tech_upgrade(country)


# --- Tactical Layer ---
func process_day(country: CountryData) -> void:
	_evaluate_frontline_moves(country)


func _ai_handle_deployment(country: CountryData) -> void:
	if country.ready_troops.is_empty():
		return

	# Attempt to deploy to a border province first if one is set/preferred
	# Otherwise, use the new MapManager border logic to find a tactical spot
	var borders = MapManager.get_border_provinces(country.country_name)

	for troop in country.ready_troops.duplicate():
		if country.deploy_pid != -1:
			country.deploy_ready_troop_to_pid(troop)
		elif not borders.is_empty():
			# Deploy directly to the front lines!
			var target_id = borders.pick_random()
			TroopManager.create_troop(country.country_name, troop.divisions, target_id)
			country.ready_troops.erase(troop)
		else:
			country.deploy_ready_troop_to_random(troop)


func _ai_consider_recruitment(country: CountryData) -> void:
	var army_base_cost := 100
	var army_cost := 0.0

	for troop in TroopManager.get_troops_for_country(country.country_name):
		army_cost += troop.divisions * (army_base_cost)

	var upkeep_buffer := army_cost * 24

	if country.money < (MIN_MONEY_RESERVE + upkeep_buffer):
		return
	if country.manpower < RECRUIT_MANPOWER_THRESHOLD:
		return

	country.train_troops(2, 10, army_base_cost)


func _evaluate_frontline_moves(country: CountryData):
	var ai_troops = TroopManager.get_troops_for_country(country.country_name)
	var idle_troops = ai_troops.filter(func(t): return not t.is_moving)
	
	if idle_troops.is_empty():
		return

	var enemies = WarManager.get_enemies_of(country.country_name)
	var move_payload = []

	# --- PEACE TIME: Uniform Distribution ---
	if enemies.is_empty():
		var owned_cities = MapManager.get_cities_province_country(country.country_name)
		if owned_cities.is_empty(): return
		
		for i in range(idle_troops.size()):
			var troop = idle_troops[i]
			# Round-robin: troop 1 -> city A, troop 2 -> city B...
			var target_pid = owned_cities[i % owned_cities.size()]
			
			# Optimization: Only move if not already at that city
			if troop.province_id != target_pid:
				move_payload.append({"troop": troop, "province_id": target_pid})

	# --- WAR TIME: Strategic Fanning (Full Version) ---
	else:
		var army_targets = []
		var city_targets = []

		for enemy_name in enemies:
			# 1. Gather Army Targets (Where the enemy actually is)
			var enemy_provinces = MapManager.country_to_provinces.get(enemy_name, [])
			for p_id in enemy_provinces:
				if not TroopManager.get_troops_in_province(p_id).is_empty():
					army_targets.append(p_id)

			# 2. Gather City Targets
			city_targets.append_array(MapManager.get_cities_province_country(enemy_name))

		army_targets.shuffle()
		city_targets.shuffle()

		for troop in idle_troops:
			var targets_for_this_troop = []
			var split_count = 1

			# Split logic for large stacks
			if troop.divisions >= 10: split_count = 3
			elif troop.divisions >= 5: split_count = 2

			for j in range(split_count):
				var target_pid = -1
				var roll = randf()
				
				if roll < 0.6 and not army_targets.is_empty():
					target_pid = army_targets.pick_random()
				elif roll < 0.9 and not city_targets.is_empty():
					target_pid = city_targets.pick_random()
				else:
					var borders = MapManager.get_border_provinces(country.country_name)
					if not borders.is_empty():
						target_pid = borders.pick_random()

				if target_pid != -1 and not targets_for_this_troop.has(target_pid):
					targets_for_this_troop.append(target_pid)

			for pid in targets_for_this_troop:
				move_payload.append({"troop": troop, "province_id": pid})

	# Execute all moves in one batch call
	if not move_payload.is_empty():
		TroopManager.command_move_assigned(move_payload)


## Helper to keep the main function clean
func _handle_peace_garrison(country, idle_troops, move_payload):
	var home_cities = MapManager.get_cities_province_country(country.country_name)
	if home_cities.is_empty():
		return

	var rally_point = home_cities[0]
	for troop in idle_troops:
		if troop.province_id != rally_point:
			move_payload.append({"troop": troop, "province_id": rally_point})


func _find_tactical_targets(ai_country_name: String) -> Array:
	var targets: Array = []
	var enemies = WarManager.get_enemies_of(ai_country_name)

	if not enemies.is_empty():
		for enemy in enemies:
			# 1. Find our provinces that touch the enemy
			var our_frontline = MapManager.get_provinces_bordering_enemy(ai_country_name, enemy)

			# 2. For every frontline province we own, find the enemy neighbor to attack
			for our_pid in our_frontline:
				var province_data = MapManager.province_objects.get(our_pid)
				for neighbor_id in province_data.neighbors:
					# Is this neighbor owned by the enemy?
					if MapManager.province_to_country.get(neighbor_id) == enemy:
						if not targets.has(neighbor_id):
							targets.append(neighbor_id)

	# Fallback to defense if no enemy targets found
	if targets.is_empty():
		targets = MapManager.get_border_provinces(ai_country_name)

	return targets
