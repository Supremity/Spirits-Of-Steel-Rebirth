extends Node
class_name CountryData

#region --- Properties ---
var country_name: String
var is_player: bool = false

var political_power: float = 50.0
var money: float = 0
var gdp: int = 0
var stability: float = 0.5
var factories_amount = 0
var income = 0.0
var province_cost = 500.0
var total_population: int = 0
var manpower: int = 0
var war_support: float = 0.5
var troop_speed_modifier = 1.0

var army_level = 1
var army_cost = 0.0
var army_base_cost = 100  # This goes times level. Each level makes army stronger and faster

var manpower_per_division = 10000
const MANPOWER_RECOVERY_PER_YEAR := 0.10  # 10%
const MANPOWER_RECOVERY_PER_DAY := MANPOWER_RECOVERY_PER_YEAR / 365.0

var daily_pp_gain: float = 0.04
var hourly_money_income: float = 4000
var military_size = 0.005  # 0.5%

# State Management
var allowedCountries: Array[String] = []
var ongoing_training: Array[TroopTraining] = []
var ready_troops: Array[ReadyTroop] = []
var deploy_pid = -1
#endregion


#region --- Inner Classes ---
class TroopTraining:
	var divisions: int
	var days_left: int
	var daily_cost: float

	func _init(_divisions: int, _days: int, _daily_cost: float):
		divisions = _divisions
		days_left = _days
		daily_cost = _daily_cost


class ReadyTroop:
	var divisions: int

	func _init(_divisions: int):
		divisions = _divisions


#endregion


#region --- Lifecycle ---
func _init(p_name: String) -> void:
	country_name = p_name
	self.name = p_name
	allowedCountries.append_array([p_name, "sea"])

	total_population = CountryManager.get_country_population(country_name)
	manpower = (
		(total_population - CountryManager.get_country_used_manpower(country_name, self))
		* military_size
	)
	gdp = (CountryManager.get_country_gdp(country_name) * total_population * 0.000001) * 0.5
	money = 0


func process_hour() -> void:
	political_power += 0.04  # daily_pp_gain

	income = (gdp / 8760) * 0.2
	income += factories_amount * 1000
	army_cost = calculate_army_upkeep()
	money += income - army_cost
	troop_speed_modifier = 1 + army_level * 0.1

	update_manpower_pool()
	if is_player:
		pass
		#print("income: ", income, " | army_cost: ", army_cost, " | province_cost: ", province_cost)
	else:
		AiManager.ai_handle_deployment(self)
		AiManager.ai_consider_recruitment(self)


func process_day() -> void:
	total_population = CountryManager.get_country_population(country_name)  # Update it due to war an dstuff
	gdp = CountryManager.get_country_gdp(country_name) * total_population * 0.000001
	_process_training()
	factories_amount = CountryManager.get_factories_country(country_name)
	if not is_player:
		AiManager.evaluate_frontline_moves(self)


#endregion


func get_daily_state_income() -> float:
	var tax_rate := 0.15
	var tax_efficiency := 0.7
	return (gdp * tax_rate * tax_efficiency) / 365.0


#region --- Military Management ---
func train_troops(divisions: int, days: int, cost_per_day: float) -> bool:
	var manpower_needed = divisions * manpower_per_division
	var first_hour_cost := divisions * cost_per_day

	if manpower < manpower_needed or money < first_hour_cost:
		return false

	manpower -= manpower_needed
	money -= first_hour_cost
	ongoing_training.append(TroopTraining.new(divisions, days, cost_per_day))
	return true


func _process_training() -> void:
	for training in ongoing_training:
		var daily_cost := training.divisions * training.daily_cost
		if money >= daily_cost:
			money -= daily_cost
			training.days_left -= 1

	for i in range(ongoing_training.size() - 1, -1, -1):
		var training = ongoing_training[i]
		if training.days_left <= 0:
			ready_troops.append(ReadyTroop.new(training.divisions))
			ongoing_training.remove_at(i)


func calculate_army_upkeep() -> float:
	var total := 0.0
	for troop in TroopManager.get_troops_for_country(country_name):
		total += troop.divisions * (army_level * army_base_cost)
	return total


func get_army_pressure() -> float:
	var army := 0
	for troop in TroopManager.get_troops_for_country(country_name):
		army += troop.divisions

	var capacity = max(1.0, (gdp * 0.03) + factories_amount * 5)
	return army / capacity


#endregion


#region --- Deployment ---
func deploy_ready_troop_to_random(troop: ReadyTroop) -> bool:
	var index = ready_troops.find(troop)
	if index == -1:
		return false

	var my_provinces: Array = MapManager.country_to_provinces.get(country_name, [])
	if my_provinces.is_empty():
		return false

	var random_province_id = my_provinces.pick_random()
	TroopManager.create_troop(country_name, troop.divisions, random_province_id)
	ready_troops.remove_at(index)
	return true


func deploy_ready_troop_to_pid(troop: ReadyTroop) -> bool:
	var index = ready_troops.find(troop)
	if index == -1:
		return false
	TroopManager.create_troop(country_name, troop.divisions, deploy_pid)
	ready_troops.remove_at(index)
	return true


#endregion


func reset_manpower() -> void:
	manpower = (
		(total_population - CountryManager.get_country_used_manpower(country_name, self))
		* military_size
	)


func update_manpower_pool() -> void:
	var base_reservoir := int(total_population * military_size)
	var max_cap := int(base_reservoir * 1.5)
	var used := CountryManager.get_country_used_manpower(country_name, self)

	if (manpower + used) < max_cap:
		var daily_gain := int(base_reservoir * MANPOWER_RECOVERY_PER_DAY)

		if daily_gain == 0 and total_population > 0:
			daily_gain = 1

		manpower += daily_gain

	# Ensure we don't exceed the absolute limit
	if (manpower + used) > max_cap:
		manpower = max(0, max_cap - used)


#region --- Stats & Getters ---
func get_max_morale() -> float:
	var base := 60.0 + (stability * 40.0)
	base += army_level * 5  # Each army level boosts morale
	return base * 0.5 if money < 0 else base


func get_attack_efficiency() -> float:
	var eff := 0.9 + (war_support * 0.3)
	eff += army_level * 0.05  # Each army level gives extra attack power
	return eff * 0.7 if money < 0 else eff


func get_defense_efficiency() -> float:
	var eff := 1.0 + (stability * 0.15)
	eff += army_level * 0.05  # Each army level gives extra defense
	return eff * 0.8 if money < 0 else eff


#endregion


func spend_politicalpower(cost: int) -> bool:
	if floori(political_power) >= cost:
		political_power -= float(cost)
		return true
	return false
#endregion
