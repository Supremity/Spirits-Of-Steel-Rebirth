extends Node

const BATTLE_TICK := 5
const PROGRESS_MAX := 99.0

# General Constants
const MORALE_DECAY_RATE := 0.05
const BASE_DAMAGE_DIVISIONS := 1
const MORALE_BOOST_DEFENDER := 5.0 
const HP_PER_DIVISION = 10

var wars := {} 
var active_battles := []

const AI_TICK_INTERVAL := 5.0
var ai_timer := 0.0

class Battle:
	var attacker_pid: int
	var defender_pid: int
	var attacker_country: String
	var defender_country: String
	
	# References to country data for live stats
	var attacker_stats: CountryData
	var defender_stats: CountryData

	var attack_progress := 0.0
	var att_morale: float
	var def_morale: float

	var province_hp: float
	var province_max_hp: float

	var total_initial_strength: float
	var timer := 0.0
	var position: Vector2
	var manager

	func _init(atk_pid: int, def_pid: int, atk_c: String, def_c: String, pos: Vector2, m):
		attacker_pid = atk_pid
		defender_pid = def_pid
		attacker_country = atk_c
		defender_country = def_c
		position = pos
		manager = m
		
		# Fetch Country Data Objects
		attacker_stats = CountryManager.get_country(attacker_country)
		defender_stats = CountryManager.get_country(defender_country)

		var att_divs = _get_divisions(attacker_pid, attacker_country)
		var def_divs = _get_divisions(defender_pid, defender_country)

		total_initial_strength = max(1.0, att_divs + def_divs)

		province_max_hp = max(1.0, def_divs * manager.HP_PER_DIVISION)
		province_hp = province_max_hp

		# --- DYNAMIC MORALE INIT ---
		# If country data exists, use its calculated max morale. Fallback to 80 if null.
		if attacker_stats:
			att_morale = attacker_stats.get_max_morale()
		else:
			att_morale = 80.0
			
		if defender_stats:
			def_morale = defender_stats.get_max_morale() + manager.MORALE_BOOST_DEFENDER
		else:
			def_morale = 80.0 + manager.MORALE_BOOST_DEFENDER

	func tick(delta: float):
		timer += delta
		if timer >= manager.BATTLE_TICK:
			timer -= manager.BATTLE_TICK
			_resolve_round()

	func _resolve_round():
		var att_divs = _get_divisions(attacker_pid, attacker_country)
		var def_divs = _get_divisions(defender_pid, defender_country)

		if att_divs <= 0:
			manager.end_battle(self)
			return

		# --- DYNAMIC MODIFIERS ---
		var att_mult = 1.0
		var def_mult = 1.0
		
		if attacker_stats: att_mult = attacker_stats.get_attack_efficiency()
		if defender_stats: def_mult = defender_stats.get_defense_efficiency()

		# --- Effective combat power ---
		# Morale is normalized against a baseline (e.g. 100) for calculation
		var att_ecp = att_divs * (att_morale / 100.0) * att_mult
		var def_ecp = def_divs * (def_morale / 100.0) * def_mult * 1.2 # 1.2 is base defender terrain/entrenchment bonus

		# --- Province HP damage ---
		province_hp -= att_ecp * manager.BASE_DAMAGE_DIVISIONS
		province_hp = max(0.0, province_hp)

		# --- Morale Damage ---
		att_morale = max(0.0, att_morale - def_ecp * manager.MORALE_DECAY_RATE)
		def_morale = max(0.0, def_morale - att_ecp * manager.MORALE_DECAY_RATE)

		# --- Progress ---
		attack_progress += (att_ecp - def_ecp) / total_initial_strength * 10.0
		attack_progress = clamp(
			attack_progress,
			-manager.PROGRESS_MAX,
			manager.PROGRESS_MAX
		)

		# --- Victory conditions ---
		if province_hp <= 0 or def_morale <= 1.0:
			_defender_loses()
		elif att_morale <= 1.0:
			manager.end_battle(self)

	func _defender_loses():
		var troops = TroopManager.get_troops_in_province(defender_pid)

		for t in troops:
			if t.country_name != defender_country:
				continue

			if t.divisions <= 1:
				TroopManager.remove_troop_by_war(t)
				continue

			var retreat_pid = _find_retreat_province(defender_pid, defender_country)

			# 50% chance to retreat or die
			if retreat_pid == -1 or randf() < 0.5:
				TroopManager.remove_troop_by_war(t)
				continue

			# Otherwise retreat
			t.divisions = max(1, int(t.divisions * 0.5))
			TroopManager.teleport_troop_to_province(t, retreat_pid)

		manager.conquer_province(defender_pid, attacker_country)
		manager.end_battle(self)

	func _find_retreat_province(from_pid: int, country: String) -> int:
		if not MapManager.adjacency_list.has(from_pid):
			return -1

		for n in MapManager.adjacency_list[from_pid]:
			var province_troops = TroopManager.troops_by_province.get(n, [])
			# Check if there are no troops from the same country in the province
			if province_troops.size() == 0 and MapManager.province_to_country[n] == country:
				return n

		return -1

	func _get_divisions(pid: int, country: String) -> float:
		return float(TroopManager.get_province_strength(pid, country))

	func get_player_relative_progress(player_country: String) -> float:
		return attack_progress if attacker_country == player_country else -attack_progress


func _process(delta: float):
	if wars.is_empty(): return
	var scaled = delta * GameClock.MIN_SPEED
	ai_timer += scaled
	if ai_timer >= AI_TICK_INTERVAL:
		ai_timer -= AI_TICK_INTERVAL
		_ai_decision_tick()
	
	if active_battles.is_empty(): return
	for battle in active_battles:
		battle.tick(scaled)
		

func _ai_decision_tick():
	if not CountryManager or not TroopManager or not MapManager:
		return

	# Loop over all countries currently at war
	for ai_country_data in wars.keys():
		var ai_country = ai_country_data.name
		if ai_country == CountryManager.player_country.country_name:
			continue

		var ai_troops = TroopManager.get_troops_for_country(ai_country)
		if ai_troops.is_empty(): continue

		# Only consider idle troops
		var idle_troops = ai_troops.filter(func(t): return not t.is_moving)
		if idle_troops.is_empty(): continue

		# --- Step 1: Collect enemy provinces (provinces with troops of a country AI is at war with) ---
		var enemy_targets: Array = []
		var empty_targets: Array = []

		for prov in MapManager.province_to_country.keys():
			var country_of_this_province = MapManager.province_to_country[prov]
			var troops_here = TroopManager.get_troops_in_province(prov)

			if country_of_this_province != ai_country and is_at_war_names(ai_country, country_of_this_province):
				# Add only if there are enemy troops
				if troops_here.size() > 0:
					enemy_targets.append(prov)
			elif country_of_this_province == ai_country and troops_here.size() == 0:
				# Empty province in AI territory
				empty_targets.append(prov)

		# If there are no targets, skip
		if enemy_targets.is_empty() and empty_targets.is_empty():
			continue

		# --- Step 2: Prioritize enemy targets first ---
		var targets: Array = enemy_targets.duplicate()
		targets += empty_targets  # append empty provinces after enemy provinces

		# --- Step 3: Split idle troops across targets ---
		var num_targets = targets.size()
		var base_divisions = idle_troops.size() / num_targets
		var remainder = idle_troops.size() % num_targets

		var troop_index = 0
		for target_pid in targets:
			var num_to_send = base_divisions
			if remainder > 0:
				num_to_send += 1
				remainder -= 1

			for i in range(num_to_send):
				if troop_index >= idle_troops.size():
					break
				var troop = idle_troops[troop_index]
				troop_index += 1
				TroopManager.order_move_troop(troop, target_pid)


func apply_casualties(pid: int, country: String, damage_divisions: float):
	var troops_list = TroopManager.get_troops_in_province(pid).filter(func(t): return t.country_name == country)
	if troops_list.is_empty() or damage_divisions <= 0: return
	
	var total_divisions = float(TroopManager.get_province_strength(pid, country))
	
	# Distribute damage proportionally
	for t in troops_list:
		var troop_proportion = t.divisions / total_divisions if total_divisions > 0 else 0
		var damage = damage_divisions * troop_proportion
		t.divisions -= damage
		
		if t.divisions <= 0:
			t.divisions = 0
			TroopManager.remove_troop_by_war(t)
			

func start_battle(attacker_pid: int, defender_pid: int):
	# Prevent duplicates
	for b in active_battles:
		if b.attacker_pid == attacker_pid and b.defender_pid == defender_pid: return

	var att_troops = TroopManager.get_troops_in_province(attacker_pid)
	var def_troops = TroopManager.get_troops_in_province(defender_pid)
	
	if att_troops.is_empty() or def_troops.is_empty(): return

	var atk_country = att_troops[0].country_name
	var def_country = def_troops[0].country_name
	var midpoint = get_province_midpoint(attacker_pid, defender_pid)
	
	var battle = Battle.new(attacker_pid, defender_pid, atk_country, def_country, midpoint, self)
	active_battles.append(battle)


func resolve_province_arrival(pid: int, troop: TroopData):
	var country = MapManager.province_to_country.get(pid)
	if country != troop.country_name and is_at_war_names(troop.country_name, country):
		var enemies = TroopManager.get_province_strength(pid, country)
		if enemies <= 0:
			conquer_province(pid, troop.country_name)


func end_battle(battle: Battle):
	active_battles.erase(battle)


func conquer_province(pid: int, new_owner: String):
	var old_owner = MapManager.province_to_country.get(pid)
	if old_owner == new_owner: return

	# Data Update
	if MapManager.country_to_provinces.has(old_owner):
		MapManager.country_to_provinces[old_owner].erase(pid)

	MapManager.province_to_country[pid] = new_owner
	if not MapManager.country_to_provinces.has(new_owner):
		MapManager.country_to_provinces[new_owner] = []
	MapManager.country_to_provinces[new_owner].append(pid)

	# Visuals
	MapManager.update_province_color(pid, new_owner)
	

func declare_war(a: CountryData, b: CountryData) -> void:
	add_war_silent(a, b)
	PopupManager.show_alert("war", a, b)
	MusicManager.play_sfx(MusicManager.SFX.DECLARE_WAR)
	MusicManager.play_music(MusicManager.MUSIC.BATTLE_THEME)


func is_at_war(a: CountryData, b: CountryData) -> bool:
	return wars.has(a) and wars[a].has(b)


func is_at_war_names(a_name: String, b_name: String) -> bool:
	if not CountryManager: return false
	var a_data = CountryManager.get_country(a_name)
	var b_data = CountryManager.get_country(b_name)
	if a_data and b_data: return is_at_war(a_data, b_data)
	return false


func add_war_silent(a: CountryData, b: CountryData) -> void:
	if a == b or is_at_war(a, b): return
	if not wars.has(a): wars[a] = {}
	if not wars.has(b): wars[b] = {}
	
	wars[a][b] = true
	wars[b][a] = true
	if a.allowedCountries.find(b.name) == -1: a.allowedCountries.append(b.name)
	if b.allowedCountries.find(a.name) == -1: b.allowedCountries.append(a.name)


func get_province_midpoint(pid1: int, pid2: int) -> Vector2:
	if not MapManager: return Vector2.ZERO
	var c1 = MapManager.province_centers.get(pid1, Vector2.ZERO)
	var c2 = MapManager.province_centers.get(pid2, Vector2.ZERO)
	return (c1 + c2) * 0.5
