extends Node

# --- CONFIGURATION ---
const BATTLE_TICK_RATE := 1.0   # Damage applied every 1.0 "game seconds"
const DAMAGE_PER_DIVISION := 0.25 # Damage factor
const MIN_DIVS_TO_ATTACK := 1
const REINFORCE_RANGE_SQ := 8000.0 * 8000.0

# --- STATE ---
var war_pairs: Array = []
var reserved_provinces: Dictionary = {} # { province_id: country_name }

# Dictionary of { province_id: Battle }
# Now stores Battle instances instead of raw dictionaries
var active_battles: Dictionary = {} 

var time_scale := 1.0

# =============================================================
#  INNER CLASS: BATTLE INSTANCE
#  (Encapsulates logic for a single battle)
# =============================================================
class Battle:
	var province_id: int
	var participants: Array = []  # [String, String] - country names
	var timer: float = 0.0
	var manager: Node  # Reference to your WarManager

	func _init(pid: int, country_a: String, country_b: String, p_manager: Node) -> void:
		province_id = pid
		participants = [country_a, country_b]
		manager = p_manager

	# Called every frame by WarManager
	func tick(delta: float) -> void:
		timer += delta
		if timer >= manager.BATTLE_TICK_RATE:
			timer -= manager.BATTLE_TICK_RATE  # subtract instead of reset for accuracy
			_resolve_round()

	func _resolve_round() -> void:
		var all_troops = TroopManager.get_troops_in_province(province_id)
		
		var group_a = all_troops.filter(func(t): return t.country_name == participants[0])
		var group_b = all_troops.filter(func(t): return t.country_name == participants[1])
		
		var total_a = group_a.reduce(func(acc, t): return acc + t.divisions, 0)
		var total_b = group_b.reduce(func(acc, t): return acc + t.divisions, 0)
		
		# Check for victory
		if total_a <= 0:
			_print_victory(participants[1])
			manager._end_battle(province_id)
			return
		if total_b <= 0:
			_print_victory(participants[0])
			manager._end_battle(province_id)
			return
		
		# Calculate damage per tick
		var damage_from_a := _calc_dps(group_a)
		var damage_from_b := _calc_dps(group_b)
		
		print_rich("[color=cyan]%s[/color] → deals [b]%.2f[/b] damage" % [participants[0], damage_from_a])
		print_rich("[color=red]%s[/color] → deals [b]%.2f[/b] damage" % [participants[1], damage_from_b])
		
		# Apply damage
		_apply_damage(group_a, damage_from_b, participants[1])
		_apply_damage(group_b, damage_from_a, participants[0])

	func _calc_dps(troops: Array) -> float:
		var total_divisions := 0
		for troop in troops:
			total_divisions += troop.divisions
		return float(total_divisions) * manager.DAMAGE_PER_DIVISION

	func _apply_damage(target_troops: Array, damage: float, attacker: String) -> void:
		if damage <= 0.0 or target_troops.is_empty():
			return
		
		var remaining_damage: float = damage
		
		for troop in target_troops:
			if remaining_damage <= 0.0:
				break
				
			var before = troop.divisions
			
			if float(troop.divisions) <= remaining_damage:
				# Entire stack dies
				remaining_damage -= troop.divisions
				troop.divisions = 0
				TroopManager.remove_troop_by_war(troop)
				print_rich("  [color=red][b]DEATH[/b][/color] %s's unit in province %d wiped out by %s (%d → 0)" % [troop.country_name, province_id, attacker, before])
			else:
				# Partial kill with proper rounding
				var kill_count := int(remaining_damage)
				if randf() < (remaining_damage - kill_count):
					kill_count += 1
				
				troop.divisions -= kill_count
				remaining_damage = 0.0
				
				print_rich("  [color=orange]-[/color][b]%d[/b]  %s lost %d divisions (%d → %d) to %s" % [kill_count, troop.country_name, kill_count, before, troop.divisions, attacker])
				
				if troop.divisions <= 0:
					troop.divisions = 0
					TroopManager.remove_troop_by_war(troop)
					print_rich("  [color=red][b]DEATH[/b][/color] %s's unit destroyed after combat rounding!" % troop.country_name)

	func _print_victory(winner: String) -> void:
		print_rich("[color=lime]▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜[/color]")
		print_rich("[color=lime]                   VICTORY! %s WINS                    [/color]" % winner.to_upper())
		print_rich("[color=lime]             Province %d is now under %s control!            [/color]" % [province_id, winner])
		print_rich("[color=lime]▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟[/color]\n")

# =============================================================
# LIFECYCLE
# =============================================================
func _ready() -> void:
	set_process(true)
	if MainClock:
		MainClock.hour_passed.connect(_on_ai_tick)
		MainClock.time_scale_changed.connect(_on_time_scale_changed)
		time_scale = MainClock.time_scale

func _on_time_scale_changed(new_scale: float) -> void:
	time_scale = new_scale

# =============================================================
# GAME LOOP (Time-Scaled Battles)
# =============================================================
func _process(delta: float) -> void:
	if active_battles.is_empty(): return

	# Scale delta by game speed
	var game_delta = delta * time_scale
	
	# Iterate a copy of keys to allow modifying dictionary safely
	var ongoing_battles = active_battles.keys()
	
	for pid in ongoing_battles:
		if active_battles.has(pid):
			# Delegate logic to the Battle instance
			active_battles[pid].tick(game_delta)

# =============================================================
# COMBAT LOGIC
# =============================================================

# Called by TroopManager when a troop enters a province
func resolve_province_conflict(province_id: int) -> void:
	# If battle exists, just ensure this new troop stops moving
	if active_battles.has(province_id):
		_lock_troops_in_province(province_id)
		return

	var local_troops = TroopManager.get_troops_in_province(province_id)
	if local_troops.size() < 2:
		_finish_province_actions(province_id)
		return

	# Check for hostile factions
	var countries = _get_countries_in_province(local_troops)
	for i in range(countries.size()):
		for j in range(i + 1, countries.size()):
			var a = countries[i]
			var b = countries[j]
			if is_at_war(a, b):
				_start_battle(province_id, a, b)
				return

func _start_battle(pid: int, country_a: String, country_b: String) -> void:
	print("⚔️ Battle started at %d [%s vs %s]" % [pid, country_a, country_b])
	
	# Create the Battle Instance
	var new_battle = Battle.new(pid, country_a, country_b, self)
	active_battles[pid] = new_battle
	
	_lock_troops_in_province(pid)
	# Optional: Visuals
	# if MapManager: MapManager.add_battle_icon(pid)

func _end_battle(pid: int) -> void:
	active_battles.erase(pid)
	call_deferred("_finish_province_actions", pid)
	print("🏁 Battle ended at %d" % pid)
	# if MapManager: MapManager.remove_battle_icon(pid)

func _lock_troops_in_province(pid: int) -> void:
	var troops = TroopManager.get_troops_in_province(pid)
	for t in troops:
		if t.is_moving:
			TroopManager._stop_troop(t)

# =============================================================
# AI ORCHESTRATION
# =============================================================
func _on_ai_tick(_hour: int = 0) -> void:
	var all_countries = MapManager.country_to_provinces.keys()
	var player_country = CountryManager.player_country.country_name if CountryManager else ""

	for country in all_countries:
		if country == player_country: continue
		var enemies = get_enemies(country)
		if enemies.is_empty(): continue

		_orchestrate_ai_country(country, enemies)

func _orchestrate_ai_country(country: String, enemies: Array) -> void:
	var my_troops = TroopManager.get_troops_for_country(country)
	var available_troops = my_troops.filter(func(t): return not t.is_moving and not _is_troop_in_battle(t))
	
	if available_troops.is_empty(): return

	# Priority 1: Reinforce Active Battles
	var battle_targets = _find_active_battles_near_me(country, available_troops)
	
	# Priority 2: Attack Empty/Weak Enemy Provinces
	var attack_targets = []
	if battle_targets.is_empty():
		attack_targets = _find_weak_targets(country, enemies)

	# Execute Moves
	var payload: Array = []
	
	for troop in available_troops:
		if troop.divisions < MIN_DIVS_TO_ATTACK: continue
		
		var target_pid = -1
		
		if not battle_targets.is_empty():
			target_pid = _get_closest_pid(troop.position, battle_targets)
		elif not attack_targets.is_empty():
			target_pid = _get_closest_pid(troop.position, attack_targets)
			
		if target_pid != -1:
			if reserved_provinces.get(target_pid) != country:
				reserved_provinces[target_pid] = country
				payload.append({ "troop": troop, "province_id": target_pid })

	if not payload.is_empty():
		TroopManager.command_move_assigned(payload)

# AI Helper: Find battles involving 'country' or enemies
func _find_active_battles_near_me(country: String, troops: Array) -> Array:
	var targets = []
	for pid in active_battles.keys():
		var battle = active_battles[pid] # This is now a Battle object
		var participants = battle.participants
		
		if participants.has(country) or is_at_war(participants[0], country) or is_at_war(participants[1], country):
			targets.append(pid)
	return targets

func _find_weak_targets(country: String, enemies: Array) -> Array:
	var targets = []
	for enemy in enemies:
		var provs = MapManager.country_to_provinces.get(enemy, [])
		targets.append_array(provs)
	return targets

func _get_closest_pid(from_pos: Vector2, pids: Array) -> int:
	var best_pid = -1
	var min_dist = INF
	for pid in pids:
		var pos = MapManager.province_centers.get(pid, Vector2.ZERO)
		var d = from_pos.distance_squared_to(pos)
		if d < min_dist:
			min_dist = d
			best_pid = pid
	return best_pid

# =============================================================
# PUBLIC HELPERS & API
# =============================================================

## Returns true if the specific troop is in an active battle
func _is_troop_in_battle(troop: TroopData) -> bool:
	return active_battles.has(troop.province_id)

## Returns battle stats for UI or Logic
func get_troop_battle_info(troop: TroopData) -> Variant:
	if not active_battles.has(troop.province_id):
		return null
		
	var battle = active_battles[troop.province_id] # Battle Object
	var my_country = troop.country_name
	var enemy_country = ""
	
	if battle.participants[0] == my_country: enemy_country = battle.participants[1]
	else: enemy_country = battle.participants[0]
	
	# Calculate balance of power dynamically
	var local_troops = TroopManager.get_troops_in_province(troop.province_id)
	var my_power = 0
	var enemy_power = 0
	
	for t in local_troops:
		if t.country_name == my_country: my_power += t.divisions
		elif t.country_name == enemy_country: enemy_power += t.divisions
		
	return {
		"is_fighting": true,
		"location": troop.province_id,
		"enemy_country": enemy_country,
		"my_total_divisions": my_power,
		"enemy_total_divisions": enemy_power,
		"is_winning": my_power > enemy_power
	}

# =============================================================
# DIPLOMACY & CONQUEST (Preserved Functions)
# =============================================================

func declare_war(country_a: String, country_b: String) -> void:
	if country_a == country_b: return
	var sorted_pair = [country_a, country_b]
	sorted_pair.sort()
	if not is_at_war(country_a, country_b):
		war_pairs.append(sorted_pair)
		PopupManager.show_alert("war", country_a, country_b)
		MusicManager.play_sfx(MusicManager.SFX.DECLARE_WAR)
		MusicManager.play_music(MusicManager.MUSIC.BATTLE_THEME)

func is_at_war(country_a: String, country_b: String) -> bool:
	var pair = [country_a, country_b]
	pair.sort()
	return pair in war_pairs

# --- PRESERVED GET_ENEMIES FUNCTION ---
func get_enemies(country: String) -> Array[String]:
	var enemies: Array[String] = []
	for pair in war_pairs:
		if pair[0] == country: enemies.append(pair[1])
		elif pair[1] == country: enemies.append(pair[0])
	return enemies

func _get_countries_in_province(troops: Array) -> Array:
	var countries: Array = []
	for t in troops:
		if not countries.has(t.country_name):
			countries.append(t.country_name)
	return countries

func _finish_province_actions(pid: int) -> void:
	if active_battles.has(pid): return # Safety check
	
	var troops = TroopManager.get_troops_in_province(pid)
	if reserved_provinces.has(pid): reserved_provinces.erase(pid)
	if troops.is_empty(): return

	var dominant = troops[0].country_name
	for t in troops:
		if t.country_name != dominant: return # Still mixed, shouldn't happen here

	var owner = MapManager.province_to_country.get(pid)
	# Conquest logic: If I occupy it, and I'm at war with owner (or it's neutral)
	if dominant != owner and (is_at_war(dominant, owner) or owner == "Neutral"):
		_update_map_ownership(pid, dominant)

func _update_map_ownership(pid: int, new_owner: String) -> void:
	var old_owner = MapManager.province_to_country.get(pid)
	if MapManager.country_to_provinces.has(old_owner):
		MapManager.country_to_provinces[old_owner].erase(pid)

	MapManager.province_to_country[pid] = new_owner
	if not MapManager.country_to_provinces.has(new_owner):
		MapManager.country_to_provinces[new_owner] = []
	MapManager.country_to_provinces[new_owner].append(pid)

	if MapManager.has_method("update_province_color"):
		MapManager.update_province_color(pid, new_owner)
