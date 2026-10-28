extends Node

# --- Constants ---
const BATTLE_TICK := 1.0
const MORALE_DECAY_RATE := 0.02 # Adjusted for better flow
const MORALE_BOOST_DEFENDER := 10.0

# --- State ---
var wars := {}
var active_battles := []
var original_territories := {}


func reset_state() -> void:
	wars.clear()
	active_battles.clear()
	original_territories.clear()
	#print("WarManager: State reset.")


func save_wars() -> Array:
	var saved_wars = []
	var processed_pairs = []

	for country_a in wars:
		var name_a = country_a.country_name
		for country_b in wars[country_a]:
			var name_b = country_b.country_name
			
			# Create a sorted pair to avoid saving [A, B] AND [B, A]
			var pair = [name_a, name_b]
			pair.sort()
			var pair_key = str(pair)
			
			if not processed_pairs.has(pair_key):
				saved_wars.append(pair)
				processed_pairs.append(pair_key)
	
	return saved_wars


func load_wars(data: Array) -> void:
	# wars.clear() # Already handled by reset_state() in load_game()
	for pair in data:
		if pair.size() == 2:
			var country_a = CountryManager.countries.get(pair[0])
			var country_b = CountryManager.countries.get(pair[1])
			if country_a && country_b:
				add_war_silent(country_a, country_b)


func save_original_territories() -> Dictionary:
	return original_territories


func load_original_territories(data: Dictionary) -> void:
	original_territories = data


func check_for_new_battles() -> void:
	if not MapManager or not TroopManager:
		return
	
	#print("WarManager: Scanning for overlapping enemies...")
	
	for pid in TroopManager.troops_by_province.keys():
		var province_troops = TroopManager.troops_by_province[pid]
		if province_troops.size() < 2:
			continue
		
		# We need at least two different countries at war in this province
		for i in range(province_troops.size()):
			var troop_a = province_troops[i]
			for j in range(i + 1, province_troops.size()):
				var troop_b = province_troops[j]
				
				if troop_a.country_name != troop_b.country_name:
					if is_at_war_names(troop_a.country_name, troop_b.country_name):
						# We found enemies co-located. Trigger a battle.
						# Note: start_battle checks for existing duplicates internally.
						start_battle(pid, pid) # In same province, we can use pid for both


class Battle:
	var attacker_pid: int
	var defender_pid: int
	var attacker_country: String
	var defender_country: String

	var attacker_stats: CountryData
	var defender_stats: CountryData

	var attack_progress := 0.0
	var att_morale: float
	var def_morale: float
	var initial_def_morale: float

	# These now represent the total combined HP of all divisions in the battle
	var current_def_hp: float = 0.0
	var total_starting_hp: float = 0.0

	var timer := 0.0
	var position: Vector2
	var manager # Reference to WarManager

	func _init(atk_pid: int, def_pid: int, atk_c: String, def_c: String, pos: Vector2, m):
		attacker_pid = atk_pid
		defender_pid = def_pid
		attacker_country = atk_c
		defender_country = def_c
		position = pos
		manager = m

		attacker_stats = CountryManager.countries.get(attacker_country)
		defender_stats = CountryManager.countries.get(defender_country)

		# Sync morale
		att_morale = attacker_stats.get_max_morale() if attacker_stats else 80.0
		initial_def_morale = (
			(defender_stats.get_max_morale() if defender_stats else 80.0)
			+ manager.MORALE_BOOST_DEFENDER
		)
		def_morale = initial_def_morale

		# Set initial HP snapshot
		_update_hp_totals()
		total_starting_hp = current_def_hp

	func _update_hp_totals():
		# This sums up the current HP of every division the defender has in the province
		var total := 0.0
		for t in TroopManager.get_troops_in_province(defender_pid).filter(func(t): return t.country_name == defender_country):
			for div in t.stored_divisions:
				total += div.hp
		current_def_hp = total

	func tick(delta: float):
		timer += delta
		if timer >= manager.BATTLE_TICK:
			timer -= manager.BATTLE_TICK
			_resolve_round()

	func _resolve_round():
		var att_troops = TroopManager.get_troops_in_province(attacker_pid).filter(
			func(t): return t.country_name == attacker_country
		)
		var def_troops = TroopManager.get_troops_in_province(defender_pid).filter(
			func(t): return t.country_name == defender_country
		)
		if att_troops.is_empty():
			manager.end_battle(self )
			return

		# --- NEW: SUPPLY & MONEY CHECK ---
		# Calculate how much it costs to keep these divisions fighting this round
		# We'll use 1% of their recruitment cost as a "per-round" supply cost
		var att_supply_cost = 0.0
		for t in att_troops:
			for div in t.stored_divisions:
				var template = div.TEMPLATES.get(div.type, div.TEMPLATES["infantry"])
				att_supply_cost += template["cost"] * 0.5
		attacker_stats.money -= att_supply_cost

		var def_supply_cost = 0.0
		for t in def_troops:
			for div in t.stored_divisions:
				var template = div.TEMPLATES.get(div.type, div.TEMPLATES["infantry"])
				def_supply_cost += template["cost"] * 0.1

		defender_stats.money -= def_supply_cost
		# Apply costs and determine penalties
		var att_supply_mult = 1.0
		var def_supply_mult = 1.0

		if attacker_stats:
			if attacker_stats.money >= att_supply_cost:
				attacker_stats.money -= att_supply_cost
			else:
				att_supply_mult = 0.4
				att_morale -= 2.0 # Extra morale penalty for hungry troops

		if defender_stats:
			if defender_stats.money >= def_supply_cost:
				defender_stats.money -= def_supply_cost
			else:
				def_supply_mult = 0.4
				def_morale -= 2.0

		# --- 1. Calculate Power (Now including Supply Penalty) ---
		var total_atk_power: float = 0.0
		for t in att_troops:
			for div in t.stored_divisions:
				total_atk_power += div.get_attack_power() * (div.hp / div.max_hp)
		total_atk_power *= att_supply_mult

		var total_def_power: float = 0.0
		for t in def_troops:
			for div in t.stored_divisions:
				total_def_power += div.get_defense_power() * (div.hp / div.max_hp)
		total_def_power *= def_supply_mult

		# --- 2. Modifiers (Morale and Efficiency) ---
		var final_attack: float = total_atk_power * (att_morale * 0.01) * (attacker_stats.get_attack_efficiency() if attacker_stats else 1.0)
		var final_defense: float = total_def_power * (def_morale * 0.01) * (defender_stats.get_defense_efficiency() if defender_stats else 1.0)

		# --- 3. Apply Damage ---
		manager.apply_casualties(defender_pid, defender_country, final_attack * defender_stats.attacker_attack_mitigation)
		manager.apply_casualties(attacker_pid, attacker_country, final_defense * attacker_stats.defender_attack_mitigation * 0.5)

		# --- 4. Update Morale Decay ---
		att_morale -= (final_defense * manager.MORALE_DECAY_RATE)
		def_morale -= (final_attack * manager.MORALE_DECAY_RATE)

		# --- 5. Wrap up Round ---
		_update_hp_totals()

		if current_def_hp <= 0 || def_morale <= 5.0:
			_defender_loses()
			return

		if att_morale <= 5.0:
			manager.end_battle(self )
			return

		# Progress Calculation
		attack_progress = clamp(max(1.0 - (current_def_hp / total_starting_hp) if total_starting_hp > 0 else 1.0, 1.0 - (def_morale / initial_def_morale)), 0.0, 1.0)

	func _defender_loses():
		var retreat_pid = _find_retreat_province(defender_pid, defender_country)

		for t: TroopData in TroopManager.get_troops_in_province(defender_pid).duplicate(): # Duplicate to avoid modification errors during loop
			if t.country_name != defender_country:
				continue

			# If no where to run or bad luck, unit is destroyed
			if retreat_pid == -1 or randf() < 0.2:
				TroopManager.RemoveTroop(t)
			else:
				# RETREAT: Lose 20% of strength then move
				for i: int in range(ceil(t.stored_divisions.size() * 0.2)):
					if !t.stored_divisions.is_empty():
						var removing: int = randi() % t.stored_divisions.size()
						t.country_obj.mobilized -= t.stored_divisions[i].hp * t.stored_divisions[i].manpowerPerHP
						t.stored_divisions.remove_at(removing)

				if t.stored_divisions.is_empty():
					TroopManager.RemoveTroop(t)
				else:
					TroopManager.teleport_troop_to_province(t, retreat_pid)

		MapManager.OccupyProvince(defender_pid, attacker_country)
		manager.check_country_collapse(defender_country, attacker_country)
		manager.end_battle(self )

	func _find_retreat_province(from_pid: int, country: String) -> int:
		if !MapManager.province_graph.has_point(from_pid):
			return -1

		for n in MapManager.province_graph.get_point_connections(from_pid):
			# Retreat logic: Must be owned by self and not currently under attack
			if MapManager.province_objects[n].GetFunctionalOwner() == country:
				return n
		return -1

	func _get_divisions(pid: int, country: String) -> float:
		return float(TroopManager.get_province_strength(pid, country))


func _process(delta: float):
	if active_battles.is_empty() || GameState.current_world.clock.paused:
		return
	var current_intensity = delta * GameState.current_world.clock.time_scale
	if current_intensity <= 0:
		return

	for battle in active_battles:
		battle.tick(current_intensity)


func start_battle(attacker_pid: int, defender_pid: int):
	if GameState.current_world.clock.paused:
		return
	# Prevent duplicate battles
	for b in active_battles:
		if b.attacker_pid == attacker_pid && b.defender_pid == defender_pid:
			return

	var att_troops = TroopManager.get_troops_in_province(attacker_pid)
	var def_troops = TroopManager.get_troops_in_province(defender_pid)

	if att_troops.is_empty() || def_troops.is_empty():
		return

	active_battles.append(Battle.new(
		attacker_pid, 
		defender_pid, 
		att_troops[0].country_name, 
		def_troops[0].country_name, 
		get_province_midpoint(attacker_pid, defender_pid), 
		self
	))


func end_battle(battle: Battle):
	if active_battles.has(battle):
		active_battles.erase(battle)


func apply_casualties(pid: int, country: String, damage_amount: float):
	var troops_list: Array = TroopManager.get_troops_in_province(pid).filter(
		func(t: TroopData): return t.country_name == country
	)

	if troops_list.is_empty() || damage_amount <= 0:
		return
	
	var countryTime: CountryData = CountryManager.countries[country]

	# Distribute total damage among all army stacks in the province
	var damage_per_troop: float = damage_amount / troops_list.size()

	for t: TroopData in troops_list:
		if t.stored_divisions.is_empty():
			continue

		# Distribute troop damage among all divisions in that stack
		var damage_per_div: float = damage_per_troop / t.stored_divisions.size()

		for i in range(t.stored_divisions.size() - 1, -1, -1):
			var div: DivisionData = t.stored_divisions[i]

			# Deduct HP
			countryTime.mobilized -= int(min(div.hp, damage_per_div) * div.manpowerPerHP)
			div.hp -= damage_per_div

			# Gain Experience based on how much damage they took/dealt
			# More fighting = faster elite status
			div.experience += 0.005

			# Remove division if it hits 0 HP
			if div.hp <= 0:
				t.stored_divisions.remove_at(i)

		# If the entire stack is gone, remove the troop icon from the map
		if t.stored_divisions.is_empty():
			TroopManager.RemoveTroop(t)


func resolve_province_arrival(pid: int, troop: TroopData):
	if !MapManager.province_objects.has(pid): return
	var target_country = MapManager.province_objects[pid].GetFunctionalOwner()

	if target_country != troop.country_name && is_at_war_names(troop.country_name, target_country):
		if TroopManager.get_province_strength(pid, target_country) <= 0:
			if !is_at_war_names(troop.country_name, target_country):
				MapManager.DeoccupyProvince(pid)
			else:
				MapManager.OccupyProvince(pid, troop.country_name)
			check_country_collapse(target_country, troop.country_name)


func call_to_arms(caller: CountryData, target: CountryData) -> void:
	if caller == target:
		return
	
	# DEAD CHECK: Target must have land to fight
	if MapManager.country_to_provinces.get(target.country_name, []).is_empty() and !target.is_exiled:
		return

	for enemy_name in get_enemies_of(caller.country_name):
		var enemy_data = CountryManager.countries.get(enemy_name)
		if enemy_data:
			declare_war(target, enemy_data)


func declare_war(warer: CountryData, waree: CountryData, a_silent: bool = false) -> void:
	if warer == waree || is_at_war(warer, waree) || FactionManager.in_faction(warer, waree):
		return

	# DEAD CHECK: Both must have land
	if MapManager.country_to_provinces.get(warer.country_name, []).is_empty() and !warer.is_exiled:
		return
	if MapManager.country_to_provinces.get(waree.country_name, []).is_empty() and !waree.is_exiled:
		return
	#print("%s declared war on %s" % [a.country_name, b.country_name])
	#_snapshot_country_territory(a.country_name)
	#_snapshot_country_territory(b.country_name)
	if !add_war_silent(warer, waree) || a_silent:
		return

	if (
		warer.is_player
		|| waree.is_player 
		|| is_at_war(CountryManager.player_country, warer) 
		|| is_at_war(CountryManager.player_country, waree)
	):
		EventManager.show_alert(
			{
				"event": "war",
				"c1": warer,
				"c2": waree
			}
		)
		MusicManager.play_music(MusicManager.MUSIC.BATTLE_THEME)
		MusicManager.play_sfx(MusicManager.SFX.DECLARE_WAR)


func _snapshot_country_territory(c_name: String) -> void:
	if !original_territories.has(c_name):
		var pids = MapManager.country_to_provinces.get(c_name, []).duplicate()
		original_territories[c_name] = pids
		
		# Also store in CountryData if it exists
		var country_data = CountryManager.countries.get(c_name)
		if country_data and country_data.pre_war_provinces.is_empty():
			country_data.pre_war_provinces = pids.duplicate()


func add_war_silent(a: CountryData, b: CountryData) -> bool:
	if a == b || is_at_war(a, b):
		return false
	##
	wars.get_or_add(a, {})[b] = true
	wars.get_or_add(b, {})[a] = true

	##
	#if !wars.has(a):
	#	wars[a] = {}
	#if !wars.has(b):
	#	wars[b] = {}
	#
	#wars[a][b] = true
	#wars[b][a] = true

	if !a.allowedCountries.has(b.country_name):
		a.allowedCountries.append(b.country_name)
	if !b.allowedCountries.has(a.country_name):
		b.allowedCountries.append(a.country_name)

	return true


func is_at_war(a: CountryData, b: CountryData) -> bool:
	return wars.has(a) && wars[a].has(b)

func is_country_at_war(country_name: String) -> bool:
	var country_data = CountryManager.get(country_name)

	return wars.has(country_data) && !wars[country_data].is_empty()

func is_at_war_names(a_name: String, b_name: String) -> bool:
	## 0.15 ms
	return wars.has(CountryManager.countries.get(a_name)) && wars[CountryManager.countries.get(a_name)].has(CountryManager.countries.get(b_name))
	## 1.49 ms
	#var a: CountryData = CountryManager.countries.get(a_name)
	#return wars.has(a) && wars[a].has(CountryManager.countries.get(b_name))
	## 2.76 ms
	#return is_at_war(CountryManager.countries.get(a_name), CountryManager.countries.get(b_name)) 


# API for AI Manager
func get_countries_at_war() -> Array:
	return wars.keys()

func has_enemies_of(country_name: String) -> bool:
	var country_data = CountryManager.countries.get(country_name)
	return country_data && wars.has(country_data)

## Returns an array of country names that are currently at war with the given country name
func get_enemies_of(country_name: String) -> Array[String]:
	var enemies: Array[String] = []
	var country_data = CountryManager.countries.get(country_name)

	if !country_data || !wars.has(country_data):
		return enemies

	# wars[country_data] returns a Dictionary where keys are enemy CountryData objects
	for enemy_data: CountryData in wars[country_data]:
		enemies.append(enemy_data.country_name)

	#MapManager.get_cities_province_country(country_name)

	return enemies


func get_province_midpoint(pid1: int, pid2: int) -> Vector2:
	return (MapManager.province_centers.get(pid1, Vector2.ZERO) + MapManager.province_centers.get(pid2, Vector2.ZERO)) * 0.5 if MapManager else Vector2.ZERO


func check_country_collapse(country_name: String, victor_name: String):
	if MapManager.get_cities_province_country(country_name).size() == 0:
		_handle_total_collapse(country_name, victor_name)


func _handle_total_collapse(fallen_name: String, victor_name: String) -> void:
	#print("Total Collapse of " + fallen_name + " to " + victor_name)
	var loser: CountryData = CountryManager.countries.get(fallen_name)
	var winner: CountryData = CountryManager.countries.get(victor_name)
	
	# NOTE Z21: Fixes some bug that makes this function run multiple times. Idk how to fix it
	if !wars.has(loser):
		return
	var player := CountryManager.player_country
	# Only counts as a player win if the player (or someone on their side) made the kill.
	# Otherwise, e.g. with gates_of_hell, every collapse would open a peace treaty.
	var player_won = player && player.is_player && CountryManager.countries.has(player.country_name) \
		&& (winner == player || (is_at_war(player, loser) && !is_at_war(player, winner)))
	var winners := get_enemies_of(fallen_name)
	# Ensure the primary winner is included (might already be if they were at war)
	if !winners.has(victor_name):
		winners.append(victor_name)

	# --- 0. Remove all remaining troops ---
	for t in TroopManager.get_troops_for_country(fallen_name).duplicate():
		TroopManager.RemoveTroop(t)

	# --- 1. Clean up wars and permissions ---
	if wars.has(loser):
		wars.erase(loser)
		if loser.allowedCountries.has(victor_name):
			loser.allowedCountries.erase(victor_name)
	
	FactionManager.clear_faction(loser)

	for c in wars:
		if wars[c].has(loser):
			wars[c].erase(loser)

		if c.allowedCountries.has(fallen_name):
			c.allowedCountries.erase(fallen_name)
	
	if loser.is_player || player_won:
		MusicManager.play_music(MusicManager.MUSIC.MAIN_THEME)
		MusicManager.play_sfx(MusicManager.SFX.POPUP)

		EventManager.show_alert(
			{
				"event": "capitulated",
				"c1": loser,
				"c2": loser
			}
		)

		if loser.is_player:
			MusicManager.play_sfx(MusicManager.SFX.GAME_OVER)
			MusicManager.play_music(MusicManager.MUSIC.MAIN_THEME)
		elif !is_country_at_war(player.country_name):
			MusicManager.play_music(MusicManager.MUSIC.MAIN_THEME)

	# --- 2. Return territory occupied BY the loser to original owners ---
	for pid in MapManager.country_to_provinces.get(fallen_name, []).duplicate():
		if !MapManager.country_to_owned_provinces.get(fallen_name).has(pid):
			#print("Deoccupying %d" % pid)
			MapManager.DeoccupyProvince(pid)

	# --- 3. Territory preview (for peace UI only) ---
	if player_won:
		for pid in MapManager.country_to_owned_provinces.get(fallen_name).duplicate():
			MapManager.DeoccupyProvince(pid)

		var winners_data: Array[CountryData] = []
		for w_name in winners:
			var w_data = CountryManager.countries.get(w_name)
			# Don't let the player's own enemies share the spoils
			if w_data and (w_data == player || !is_at_war(player, w_data)):
				winners_data.append(w_data)

		var peace_ui = get_tree().root.find_child("PeaceProcessUI", true, false)
		if peace_ui:
			# Pass all winners to the UI
			peace_ui.open_menu(winners_data, loser)
			original_territories.erase(fallen_name)
	else: # --- 5. AI takes everything ---
		for pid in MapManager.country_to_owned_provinces.get(fallen_name).duplicate():
			if MapManager.province_objects[pid].occupier == "":
				#print("%d is going to victor " % pid + victor_name)
				MapManager.transfer_ownership(pid, victor_name)
				#original_territories[victor_name].append(pid)
			else:
				#print("%d is going to occupier " % pid + MapManager.province_objects[pid].occupier)
				MapManager.transfer_ownership(pid, MapManager.province_objects[pid].occupier)
				#original_territories[MapManager.province_objects[pid].country].append(pid)
			
		original_territories.erase(fallen_name)
		if loser.is_player:
			pass
			
		CountryManager.cleanup_empty_countries()
