extends Node

# --- Strategic Layer (Called every game hour) ---
func process_hour(country: CountryData) -> void:
	_ai_handle_deployment(country)
	_ai_consider_recruitment(country)

# --- Tactical Layer (Called every game day) ---
func process_day(country: CountryData) -> void:
	# Decisions that don't need to happen every hour (like moving armies)
	if WarManager.wars.has(country):
		_evaluate_frontline_moves(country)

func _ai_handle_deployment(country: CountryData) -> void:
	if country.ready_troops.is_empty():
		return
		
	var troops_to_deploy = country.ready_troops.duplicate()
	for troop in troops_to_deploy:
		# AI logic: just get them on the map
		country.deploy_ready_troop_to_random(troop)

func _ai_consider_recruitment(country: CountryData) -> void:
	var safety_buffer = country.hourly_money_income * 10.0
	if country.money < safety_buffer or country.manpower < 5000:
		return 
		
	country.train_troops(5, 10, 50.0)

# --- Internal Tactical Logic ---

func _evaluate_frontline_moves(country: CountryData):
	var ai_troops = TroopManager.get_troops_for_country(country.country_name)
	var idle_troops = ai_troops.filter(func(t): return not t.is_moving)
	
	if idle_troops.is_empty(): 
		return

	# Find where we need to go
	var targets = _find_tactical_targets(country.country_name)
	if targets.is_empty():
		return

	# Distribution logic
	var num_targets = targets.size()
	var base_count = idle_troops.size() / num_targets
	var remainder = idle_troops.size() % num_targets
	var troop_idx = 0
	
	for target_pid in targets:
		var count_for_this_target = base_count + (1 if remainder > 0 else 0)
		remainder -= 1
			
		for i in range(count_for_this_target):
			if troop_idx >= idle_troops.size(): break
			TroopManager.order_move_troop(idle_troops[troop_idx], target_pid)
			troop_idx += 1

func _find_tactical_targets(ai_country_name: String) -> Array:
	var targets: Array = []
	
	for prov_id in MapManager.province_to_country.keys():
		var owner_name = MapManager.province_to_country[prov_id]
		var troops_here = TroopManager.get_troops_in_province(prov_id)
		
		# Priority 1: Enemy provinces with troops (Attack!)
		if owner_name != ai_country_name and WarManager.is_at_war_names(ai_country_name, owner_name):
			if troops_here.size() > 0:
				targets.push_front(prov_id) # Push to front to prioritize
		
		# Priority 2: Our own empty provinces (Defend/Re-occupy)
		elif owner_name == ai_country_name and troops_here.size() == 0:
			targets.append(prov_id)

	return targets
