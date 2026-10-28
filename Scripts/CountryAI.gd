class_name CountryAI

# --- TUNING ---
const TICK_RATE_PEACE := 12  # Slower thinking in peace time
const TICK_RATE_WAR := 2  # Think fast during war
const SATURATION_IDEAL := 1.0  # Target: At least 1 division equivalent per province
const SATURATION_MAX := 4.0  # Avoid overstacking; redistribute if exceeding
const DISTANCE_PENALTY := 0.1  # Reduce score per unit distance to discourage far moves
# NOTE(soi): why tf was this 1?!?!??
const MIN_DIVISIONS_PER_SPLIT := 10  # Smallest split size
const MIN_TOTAL_POWER_FOR_WAR := 5000 # Minimum power/divisions to even think about war
const MAX_SPLITS_PER_TROOP := 5  # Limit splits to prevent micro-management overhead

# --- AI DIPLOMACY/WAR LOGIC---
const DECLARE_WAR_COOLDOWN_FRAMES := 600
const MAX_PARALLEL_WARS := 2
const WAR_SCORE_THRESHOLD := 0.6
const MAX_WAR_DECLARATIONS_PER_TICK := 1
const AI_CHAOS := 0.9
const MAX_COMBINED_WAR_MEMBERS := 8 # Prevent world-war scale escalations
const EMERGENCY_DEPLOYMENT_THRESHOLD := 5 # If at war and fewer than this, panic deploy


var country: CountryData
var personality: Dictionary[String, Variant]= {
	"economy": {
		"trade": 1.0,
		"industry_amount_factor": 0.08,
		"industry": 0.75,
		"surplus": 1.0
	},
	"military": {
		"training_factor": 1.0,
		"max_economic_ratio": 0.7,
	},
	"war": {
		"probability": {
			"base": 0.1,
			"tension_factor": 2.0,
		},
		"score": {
			"strength": 2.0,
			"money_factor": 0.00002,
			"max_cities": 3,
			"cities": 0.5
		},
		"combat": {
			"attack_weight": 2.0,
			"defense_weight": 1.5,
			"city_bonus": 50.0,
		},
		"min_strength_ratio": 1.1,
		"min_economy": 15000,
	},
	"aggression": 1.0,
}
var _last_declare_frame: int = -999999
var _neighbor_cache: Array = []
var _neighbors_dirty: bool = true


func _init(_country: CountryData) -> void:
	country = _country
	personality = {
		"economy": {
			"trade": randf(),
			"industry_amount_factor": 0.2 * randf(),
			"industry": randf(),
			"surplus": randf()
		},
		"military": {
			"training_factor": randf(),
			"max_economic_ratio": 0.7,
		},
		"war": {
			"probability": {
				"base": randf(),
				"tension_factor": 10 * randf(),
			},
			"score": {
				"strength": 2 * randf(),
				"money_factor": 0.0001 * randf(),
				"max_cities": 3 * randf(),
				"cities": randf()
			},
			"combat": {
				"attack_weight": 5 * randf(),
				"defense_weight": 5 * randf(),
				"city_bonus": 100 * randf(),
			},
			"min_strength_ratio": 1.1 + randf(),
			"min_economy": 10000 * randf(),
		},
	}
	
	var extremism: float = _get_extremism()
	personality["aggression"] = (extremism * 2.0) + (AI_CHAOS * randf())
	
	# Adjust war probability based on extremism
	personality["war"]["probability"]["base"] *= (1.0 + extremism)
	personality["war"]["probability"]["tension_factor"] = (2.0 + extremism * 5.0) * randf()
	
	if MapManager.is_inside_tree():
		MapManager.province_ownership_changed.connect(_on_province_ownership_changed)

func _on_province_ownership_changed(_pid: int, _old_owner: String, _new_owner: String) -> void:
	_neighbors_dirty = true


func think_hour() -> void:
	if Engine.get_frames_drawn() % (TICK_RATE_WAR if !WarManager.has_enemies_of(country.country_name) else TICK_RATE_PEACE) != 0:
		return
	
	_execute_best([
		{"score": _score_frontline(), "action": _execute_frontline}
	])


func think_day() -> void:
	_optimize_economy()
	_execute_best([
		{"score": _score_factory(), "action": _execute_factory},
		{"score": _score_train(), "action": _execute_train},
		{"score": _score_war(), "action": _execute_war},
		{"score": _score_call_to_arms(), "action": _execute_call_to_arms}
	])


func _execute_best(actions: Array) -> void:
	if actions.size() == 0:
		return
	
	actions.sort_custom(func(a, b): return a.score > b.score)
	
	#if country == GameState.game_ui.selected_country:
	#	print(country.country_name + ": ")
	#	for entry in actions:
	#		print("%s - %f" % [str(entry.action), entry.score])
	
	for action: Dictionary in actions:
		if action.score < 0 || action.action.call():
			break


func _score_factory() -> float:
	return 0 if country.money < 1000 else max(0.1, 1.0 - (float(country.factories_amount) * personality["economy"]["industry_amount_factor"])) * personality["economy"]["industry"]


func _score_train() -> float:
	return 0 if country.money < 500 || country.manpower < 10000 else personality["military"]["training_factor"]


func _score_war() -> float:
	return 0 if country.is_puppet else MapManager.world_tension * personality["aggression"]


func _score_frontline() -> float:
	if not WarManager.has_enemies_of(country.country_name):
		var deployed_count = 0
		for troop in TroopManager.get_troops_for_country(country.country_name):
			deployed_count += troop.divisions_count
		if deployed_count < EMERGENCY_DEPLOYMENT_THRESHOLD:
			return 10.0
	return 1.0 # Always high priority to manage frontline


func _execute_factory() -> bool:
	if !MapManager.country_to_owned_provinces.has(country.country_name): return false
	var provincesToDo: Array = MapManager.country_to_owned_provinces[country.country_name].filter(func (pid: int): return MapManager.province_objects[pid].buildings.size() < 4 && ! pid in EconomyManager.construction_queue)
	if provincesToDo.is_empty():
		return false
	MapManager._province_build_industry(provincesToDo.pick_random(), country.country_name, GameState.IndustryType.FACTORY)
	return true


func _execute_train() -> bool:
	var trained_any = false
	for type in DivisionData.TEMPLATES.keys():
		var template: Dictionary = DivisionData.TEMPLATES[type]
		var max_affordable: int = mini(int(country.money / template["cost"]), int(country.manpower / template["manpower"]))
		
		var res_req = template.get("required_resource", "")
		var res_amount = template.get("required_resource_amount", 1)
		if res_req != "":
			var max_by_equip: int = int(country.stockpile.get(res_req, 0) / res_amount)
			max_affordable = mini(max_affordable, max_by_equip)
			
		if max_affordable < 1:
			continue
			
		var limit = 20 if !WarManager.has_enemies_of(country.country_name) else 10
		var train_count = clampi(max_affordable, 1, limit)
		if country.train_troops(train_count, type):
			trained_any = true
			break
			
	return trained_any


func _execute_war() -> bool:
	# 1. THE STOCHASTIC GATE (Randomness + World Tension)
	# Extreme countries care less about tension
	if MapManager.world_tension < (0.15 - _get_extremism() * 0.1) && personality["aggression"] < 2.5:
		return false

	# Only proceed if we pass the probability check
	if randf() > (personality["war"]["probability"]["base"] + MapManager.world_tension * personality["war"]["probability"]["tension_factor"]):
		return false

	# 2. COOLDOWNS & OVEREXTENSION (Existing)
	var frame_now: int = Engine.get_frames_drawn()
	if frame_now - _last_declare_frame < DECLARE_WAR_COOLDOWN_FRAMES || WarManager.get_enemies_of(country.country_name).size() >= MAX_PARALLEL_WARS || country.money < personality["war"]["min_economy"]:
		#if country == GameState.game_ui.selected_country:
		#	print("%s didn't go to war due to cooldown, too many enemies, or a weak economy" % country.country_name)
		return false

	# Pre-calculate our faction set for O(1) intersection checks in filter
	var our_factions := {}
	for f in country.factions:
		our_factions[f] = true

	var candidates: Array = _get_neighbor_countries().filter(
		func(enemy: String):
			var enemy_data: CountryData = CountryManager.countries.get(enemy)
			if not enemy_data: return false
			
			# Cheapest check first: Relation/Aggression
			if not (country.get_relation_with(enemy) < 20 or personality["aggression"] > 2.0):
				return false
				
			# Faction check: Use pre-calculated set for speed
			for f in enemy_data.factions:
				if our_factions.has(f):
					return false
				
			return true
	)

	# Safety: Don't declare war if we have very FEW troops
	if _estimate_country_strength(country.country_name, true) < MIN_TOTAL_POWER_FOR_WAR:
		return false
	#print(candidates)
	if candidates.is_empty():
		#if country == GameState.game_ui.selected_country:
		#	print("%s had no candidates to go to war with" % country.country_name)
		return false

	var best_score: float = -INF
	var best_target: String = ""
	
	var puppeter: PackedStringArray = []
	puppeter.append_array(country.puppets)
	
	if country.is_puppet:
		puppeter.append(country.owner)
		puppeter.append_array(CountryManager.countries[country.owner].puppets)

	for target_name: String in candidates:
		var target_data: CountryData = CountryManager.countries[target_name]
		if FactionManager.in_faction(country, target_data) || WarManager.is_at_war_names(country.country_name, target_name) || puppeter.has(target_name):
			continue

		# 3. SCALE ANALYSIS (Prevent massive world wars)
		var own_members = _get_side_members(country.country_name)
		var target_members = _get_side_members(target_name)
		
		# If the conflict would involve too many countries, skip (unless aggressive)
		if own_members.size() + target_members.size() > MAX_COMBINED_WAR_MEMBERS && personality["aggression"] < 2.5:
			continue

		# 4. STRENGTH & DISTANCE ANALYSIS
		# Collective Security: Calculate strength of the entire "side" (factions + puppets)
		var own_side_strength = _estimate_side_strength(country.country_name)
		var target_side_strength = _estimate_side_strength(target_name)
		
		var ratio: float = own_side_strength / max(1.0, target_side_strength)

		if ratio < personality["war"]["min_strength_ratio"]:
			continue

		# 5. DYNAMIC SCORING
		# Strength advantage
		# Prefer rich targets
		# Target Cities (Existing) More cities = more score, capped at 3 for balance
		# 6. FINAL THRESHOLD
		# We add a bit of randomness to the score so it's not always the same neighbor
		var score: float = (ratio - 1.0) * personality["war"]["score"]["strength"] \
			+ target_data.money * personality["war"]["score"]["money_factor"] \
			+ min(MapManager.get_cities_province_country(target_name).size(), personality["war"]["score"]["max_cities"]) * personality["war"]["score"]["cities"] \
			+ randf_range(-0.5, 0.5)

		if score > best_score && score > WAR_SCORE_THRESHOLD:
			best_score = score
			best_target = target_name

	# 7. EXECUTION
	if best_target:
		#if country == GameState.game_ui.selected_country:
		#print("%s is declaring war on %s" % [country.country_name, best_target])
		WarManager.declare_war(country, CountryManager.countries[best_target])
		
		# Aggressive/Extreme countries cause more tension
		MapManager.increase_world_tension(0.02 + _get_extremism() * 0.03 + personality["aggression"] * 0.01)

		_last_declare_frame = frame_now
	
	#if country == GameState.game_ui.selected_country:
	#	print("%s executed war" % country.country_name)
	return true


#func _execute_war_declaration(target_name: String, frame: int):
#	WarManager.declare_war(country, CountryManager.countries[target_name])
#	# Increasing tension on every war slows down/speeds up the global state
#	MapManager.increase_world_tension(0.02)
#
#	_last_declare_frame = frame


func _execute_frontline():
	if !country.ready_troops.is_empty():
		# Get every city the country owns
		var cities = MapManager.country_to_cities.get(country.country_name, [])
		if !cities.is_empty():
			# We duplicate to safely erase during iteration
			for troop_data: CountryData.ReadyTroop in country.ready_troops.duplicate():
				# Pick a random city from the full list to ensure spreading
				TroopManager.DeployReady(
					country.country_name, 
					troop_data, 
					cities.pick_random()
				)
				
				country.ready_troops.erase(troop_data)
	
	var idle_troops: Array = TroopManager.get_troops_for_country(country.country_name).filter(func(t): return not t.is_moving)
	if idle_troops.is_empty():
		#if country == GameState.game_ui.selected_country:
		#	print("%s had no idle troops" % country.country_name)
		return

	var enemies: Array[String] = WarManager.get_enemies_of(country.country_name)
	var move_payload: Array = []
	if enemies.is_empty():
		#if country == GameState.game_ui.selected_country:
		#	print("%s had no enemies" % country.country_name)
		var hubs = MapManager.country_to_cities.get(country.country_name, [])
		for troop in idle_troops:
			if !hubs.has(troop.province_id):
				# Choose closest hub to avoid unnecessary long moves
				var troop_pos: Vector2 = MapManager.province_graph.get_point_position(troop.province_id)
				hubs.sort_custom(
					func(a, b):
						return troop_pos.distance_squared_to(MapManager.province_graph.get_point_position(a)) < troop_pos.distance_squared_to(MapManager.province_graph.get_point_position(b))
				)
				move_payload.append({"troop": troop, "province_id": hubs[0]})
		if !move_payload.is_empty():
			TroopManager.command_move_assigned(move_payload)
		return

	# Get weighted targets (Cities, Troops, and Empty Gaps)
	var targets: Array[Dictionary] = []
	var seen: Dictionary = {}
	
	var enemy_dict: Dictionary = {}
	for e in enemies:
		enemy_dict[e] = true
		
	var city_dict: Dictionary = {}
	for city in MapManager.all_cities:
		city_dict[city.id] = true

	for my_pid in MapManager.get_provinces_bordering_enemies(country.country_name, enemies):
		#if country == GameState.game_ui.selected_country:
		#	print("Border Province: %d" % my_pid)
		for n_id in MapManager.province_graph.get_point_connections(my_pid):
			#if country == GameState.game_ui.selected_country:
			#	print("Neighbor Province: %d" % my_pid)
			if !MapManager.province_objects.has(n_id):
				continue
			#if country == GameState.game_ui.selected_country:
			#	print("Braveror Province: %d" % my_pid)
			# Check if it's enemy territory
			var enemy_name: String = MapManager.province_objects[n_id].GetFunctionalOwner()
			if enemy_dict.has(enemy_name) && !seen.has(n_id):
				#if country == GameState.game_ui.selected_country:
				#	print("Seenhbor Province: %d" % my_pid)
				seen[n_id] = true
				var e_str: int = TroopManager.get_province_strength(n_id, enemy_name)
				var score: float = 10.0

				if city_dict.has(n_id):
					score += personality["war"]["combat"]["city_bonus"]

				if e_str > 0:
					score += (e_str * personality["war"]["combat"]["attack_weight"])
				else:
					score += 15.0  # High priority to flip "free" land fast

				targets.append(
					{
						"id": n_id,
						"virtual_strength": 0.0,
						"enemy_strength": e_str,
						"score": score
					}
				)

				# --- BLITZKRIEG LOGIC ---
				# Look at the neighbor's neighbors (2 tiles deep)
				# If an enemy city is just behind the front line and empty, go for it!
				for dn_id in MapManager.province_graph.get_point_connections(n_id):
					if (MapManager.province_objects.has(dn_id)
						&& MapManager.province_objects[dn_id].GetFunctionalOwner() == enemy_name 
						&& !seen.has(dn_id) 
						&& city_dict.has(dn_id)
						):
						targets.append(
							{
								"id": dn_id,
								"virtual_strength": 0.0,
								"enemy_strength":
								TroopManager.get_province_strength(dn_id, enemy_name),
								"score": personality["war"]["combat"]["city_bonus"] * 0.8
							}
						)
	if targets.is_empty():
		#if country == GameState.game_ui.selected_country:
		#	print("%s had no targets" % country.country_name)
		return

	for troop in idle_troops:
		# Sort targets by a mix of Score and Distance
		# Math: score / (distance + 1)
		var troop_pos: Vector2 = MapManager.province_centers[troop.province_id]
		targets.sort_custom(
			func(a, b):
				return (a.score / (troop_pos.distance_to(MapManager.province_centers[a.id]) * 0.01 + 1.0)) > (b.score / (troop_pos.distance_to(MapManager.province_centers[b.id]) * 0.01 + 1.0))
		)

		var divisions_left: int = troop.divisions_count

		for target in targets:
			if divisions_left <= 0:
				break
			if target.virtual_strength >= SATURATION_MAX:
				continue

			# DETERMINISTIC SPLITTING:
			# If target is empty, only send 1-2 divisions to "capture" it.
			# If target has enemies, send enough to beat them (or everything left).
			var amount_to_send: int = clamp(target.enemy_strength * 1.2 if target.enemy_strength > 0 else SATURATION_IDEAL, 1, divisions_left)

			# Ensure the split-off part is also substantial
			if amount_to_send < divisions_left:
				amount_to_send = clampi(max(amount_to_send, MIN_DIVISIONS_PER_SPLIT), 1, divisions_left)

			# Only split if it's worth the micro-overhead
			if (
				amount_to_send < divisions_left
				&& (divisions_left - amount_to_send) < MIN_DIVISIONS_PER_SPLIT
			):
				amount_to_send = divisions_left

			move_payload.append(
				{"troop": troop, "province_id": target.id, "divisions": amount_to_send}  # Pass this to your Command Move
			)

			target.virtual_strength += amount_to_send
			divisions_left -= amount_to_send

	if !move_payload.is_empty():
		TroopManager.command_move_assigned(move_payload)
	#if country == GameState.game_ui.selected_country:
	#	print("%s executed their frontline" % country.country_name)


func _score_call_to_arms() -> float:
	if WarManager.has_enemies_of(country.country_name):
		return 0.0
	if country.factions.is_empty():
		return 0.0
	
	return 1.5


func _execute_call_to_arms() -> bool:
	var called_any = false
	var enemies = WarManager.get_enemies_of(country.country_name)

	for faction_name in country.factions:
		var faction_data = FactionManager.factions.get(faction_name)
		if not faction_data:
			continue
		
		# CIVIL WAR CHECK: Don't call allies if the enemy is in the same faction
		var is_internal_conflict = false
		for member in faction_data.members:
			if member.polity in enemies:
				is_internal_conflict = true
				break
		
		if is_internal_conflict:
			continue
		
		for member in faction_data.members:
			if member.polity == country.country_name:
				continue
			
			var member_country = CountryManager.countries.get(member.polity)
			if member_country:
				WarManager.call_to_arms(country, member_country)
				called_any = true
	
	return called_any


# --- UTILITIES ---

func _get_peace_hubs() -> Array:
	# Check if we have a valid list of all cities
	var cities: Array = MapManager.get_cities_province_country(country.country_name)
	
	return MapManager.country_to_provinces.get(country.country_name, []) if cities.is_empty() else cities


func _get_neighbor_countries() -> Array:
	if not _neighbors_dirty:
		return _neighbor_cache

	var neighbors: Dictionary = {}
	for pid in MapManager.country_to_provinces.get(country.country_name, []):
		for nid in MapManager.province_graph.get_point_connections(pid):
			var province = MapManager.province_objects.get(nid)
			if not province: 
				continue
			
			var owner: String = province.occupier if province.occupier != "" else province.country
			if owner != "" and owner != "Sea" and owner != country.country_name:
				neighbors[owner] = true

	_neighbor_cache = neighbors.keys()
	_neighbors_dirty = false
	return _neighbor_cache


func _estimate_country_strength(country_name: String, only_deployed: bool = false) -> float:
	var total: float = 0.0
	var c: CountryData = CountryManager.countries.get(country_name)
	
	if !c:
		#print("Country %s doesn't exist." % country_name)
		return 0.1
	
	if !only_deployed:
		total += float(c.manpower) * 0.05   # Manpower pool is potential, not active
		total += float(c.money) * 0.01      # Money is even less direct
		
	total += c.mobilized
			
	return max(0.1, total)


func _estimate_side_strength(country_name: String) -> float:
	var total_strength = 0.0
	var all_potential = _get_side_members(country_name)
	
	# Sum Strengths
	for p_name in all_potential:
		total_strength += _estimate_country_strength(p_name)
	
	return total_strength


func _get_side_members(country_name: String) -> Array[String]:
	var side_members: Array[String] = [country_name]
	
	var c_data = CountryManager.countries.get(country_name)
	if not c_data:
		return side_members
	
	# 1. Add Faction Members
	for faction_name in c_data.factions:
		var faction_data = FactionManager.factions.get(faction_name)
		if faction_data:
			for member in faction_data.members:
				if not member.polity in side_members:
					side_members.append(member.polity)
	
	# 2. Add Puppets for all side members
	var all_potential: Array[String] = []
	all_potential.append_array(side_members)
	
	for member in side_members:
		var m_data = CountryManager.countries.get(member)
		if m_data:
			for puppet in m_data.puppets:
				if not puppet in all_potential:
					all_potential.append(puppet)
					
	return all_potential


func _get_extremism() -> float:
	# Ideology map is roughly -100 to 100 on both axes.
	# Higher distance from center (0,0) = more extreme.
	# Return value 0.0 (neutral) to 1.0 (extreme)
	return clamp(country.ideology.length() * 0.00707113562, 0.0, 1.0) # 141.42 is approx dist to corner


func _optimize_economy() -> void:
	if MapManager.recipes.is_empty():
		return
	_optimize_factory_allocation()
	_optimize_trading()


func _optimize_factory_allocation() -> void:
	if country.factories_amount <= 0:
		country.factory_allocation.clear()
		return

	# Target weights for military production
	var W_inf := 4.0
	var W_tank := 2.0 if country.factories_amount >= 4 else 0.0
	var W_art := 1.5 if country.factories_amount >= 2 else 0.0
	var W_total := W_inf + W_tank + W_art
	if W_total <= 0.0:
		W_total = 1.0

	var target_production := {
		"Infantry_equipment": 24.0 * country.factories_amount * (W_inf / W_total),
		"Tank_equipment": 24.0 * country.factories_amount * (W_tank / W_total),
		"Artillery_equipment": 24.0 * country.factories_amount * (W_art / W_total),
		"Steel_ingot": 0.0,
		"Battery_pack": 0.0,
		"Basic_circuitry": 0.0
	}

	var current_daily_production := {}
	for res in target_production:
		current_daily_production[res] = 0.0

	var temp_allocations := {}
	for recipe_name in MapManager.recipes:
		temp_allocations[recipe_name] = 0

	for i in range(country.factories_amount):
		# Re-evaluate intermediate targets based on current allocations
		target_production["Steel_ingot"] = 24.0 * (temp_allocations.get("Infantry_equipment", 0) + temp_allocations.get("Tank_equipment", 0) + temp_allocations.get("Artillery_equipment", 0))
		target_production["Battery_pack"] = 24.0 * temp_allocations.get("Tank_equipment", 0)
		target_production["Basic_circuitry"] = 24.0 * temp_allocations.get("Battery_pack", 0)

		var best_recipe := ""
		var max_deficit := -INF

		for recipe_name in MapManager.recipes:
			var deficit: float = target_production.get(recipe_name, 0.0) - current_daily_production.get(recipe_name, 0.0)
			if deficit > max_deficit:
				max_deficit = deficit
				best_recipe = recipe_name

		if best_recipe != "":
			temp_allocations[best_recipe] = temp_allocations.get(best_recipe, 0) + 1
			current_daily_production[best_recipe] = current_daily_production.get(best_recipe, 0.0) + 24.0
			var recipe = MapManager.recipes.get(best_recipe)
			if recipe:
				for req in recipe.resources_required:
					if req in current_daily_production:
						current_daily_production[req] = current_daily_production[req] - 24.0

	# Apply new allocations
	country.factory_allocation.clear()
	for recipe_name in temp_allocations:
		if temp_allocations[recipe_name] > 0:
			country.factory_allocation[recipe_name] = temp_allocations[recipe_name]


func _optimize_trading() -> void:
	# Calculate net daily resource change before trade
	var net_before_trade := {}

	# 1. Province yields
	var provinces = MapManager.country_to_owned_provinces.get(country.country_name, [])
	for pid in provinces:
		var province: Province = MapManager.province_objects.get(pid)
		if province:
			for resource in province.resources:
				net_before_trade[resource.type] = net_before_trade.get(resource.type, 0.0) + resource.amount

	# 2. Factory production and consumption
	for resource_name in country.factory_allocation:
		var allocation = country.factory_allocation[resource_name]
		if allocation <= 0:
			continue

		var recipe = MapManager.recipes.get(resource_name)
		if not recipe:
			continue

		var daily_vol: float = allocation * 24.0
		net_before_trade[resource_name] = net_before_trade.get(resource_name, 0.0) + daily_vol
		for req in recipe.resources_required:
			net_before_trade[req] = net_before_trade.get(req, 0.0) - daily_vol

	var new_trade_settings := {}

	for res_name in MapManager.resources:
		var net: float = net_before_trade.get(res_name, 0.0)
		var stock: int = country.stockpile.get(res_name, 0)
		
		# Define target reserves for military equipment
		var target_reserve = 0
		if res_name == "Infantry_equipment":
			target_reserve = 500
		elif res_name == "Tank_equipment":
			target_reserve = 200
		elif res_name == "Artillery_equipment":
			target_reserve = 150

		if target_reserve > 0 and stock < target_reserve:
			# Even if net is positive/neutral, we want to import to reach target reserve!
			if country.money > 1000:
				var needed = target_reserve - stock
				var import_qty := clampi(int(ceil(needed / 24.0)), 1, 5)
				new_trade_settings[res_name] = import_qty
		else:
			# Non-military or stockpile above target reserve
			if net < 0:
				# Deficit -> import if stockpile is low
				if stock < 200 and country.money > 500:
					var import_qty := int(ceil(abs(net) / 24.0))
					new_trade_settings[res_name] = min(import_qty, 5) # Cap imports at 5 units/hour
			elif net > 0:
				# Surplus -> export if stockpile is healthy (safety buffer for military equipment)
				var healthy_threshold = 50 if target_reserve == 0 else target_reserve + 100
				if stock > healthy_threshold:
					var export_qty := int(floor(net / 24.0))
					if export_qty > 0:
						# Negative trade settings represent exports
						new_trade_settings[res_name] = -export_qty

	# Apply new trade settings and update global world stockpile
	for res in MapManager.resources:
		var old_val: int = country.trade_settings.get(res, 0)
		var new_val: int = new_trade_settings.get(res, 0)
		if old_val != new_val:
			country.trade_settings[res] = new_val
			if not EconomyManager.world_stockpile.has(res):
				EconomyManager.world_stockpile[res] = 0
			EconomyManager.world_stockpile[res] += new_val - old_val

	country.recalculate_stockpile_change()
