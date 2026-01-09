extends Node
class_name CountryData

#region --- Properties ---
var country_name: String
var is_player: bool = false 

var political_power: float = 50.0
var money: float = 0
var gdp: int = 0
var stability: float = 0.5      

var total_population: int = 0
var manpower: int = 0         
var war_support: float = 0.5    

var manpower_per_division = 10000


var daily_pp_gain: float = 0.04
var hourly_money_income: float = 4000
var military_size = 0.005 # 0.5%

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
	allowedCountries.append(p_name)
	
	total_population = CountryManager.get_country_population(country_name)
	gdp = CountryManager.get_country_gdp(country_name) * total_population * 0.000001
	money = gdp
	manpower = int(total_population * 0.005)

func process_hour() -> void:
	political_power += daily_pp_gain
	money += gdp / 8760 * 0.5 
	money -= calculate_army_upkeep()
	
	update_manpower_pool()
	
	if not is_player:
		AiManager.process_hour(self)

func process_day() -> void:
	gdp = CountryManager.get_country_gdp(country_name) * total_population * 0.000001 
	_process_training()
	
	if not is_player:
		AiManager.process_day(self)
#endregion



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
		total += troop.divisions * 10.0
	return total
#endregion

#region --- Deployment ---
func deploy_ready_troop_to_random(troop: ReadyTroop) -> bool:
	var index = ready_troops.find(troop)
	if index == -1: return false
	
	var my_provinces: Array = MapManager.country_to_provinces.get(country_name, [])
	if my_provinces.is_empty(): return false
		
	var random_province_id = my_provinces.pick_random()
	TroopManager.create_troop(country_name, troop.divisions, random_province_id)
	ready_troops.remove_at(index)
	return true
	
func deploy_ready_troop_to_pid(troop: ReadyTroop) -> bool:
	var index = ready_troops.find(troop)
	if index == -1: return false
	TroopManager.create_troop(country_name, troop.divisions, deploy_pid)
	ready_troops.remove_at(index)
	return true
#endregion


func update_manpower_pool() -> void:
	var total_reservoir = int(total_population * military_size)
	var used = CountryManager.get_country_used_manpower(country_name, self)
	manpower = max(0, total_reservoir - used)
	
#region --- Stats & Getters ---
func get_max_morale() -> float:
	var base := 60.0 + (stability * 40.0)
	return base * 0.5 if money < 0 else base

func get_attack_efficiency() -> float:
	var eff := 0.9 + (war_support * 0.3)
	return eff * 0.7 if money < 0 else eff

func get_defense_efficiency() -> float:
	var eff := 1.0 + (stability * 0.15)
	return eff * 0.8 if money < 0 else eff

func spend_politicalpower(cost: int) -> bool:
	if floori(political_power) >= cost:
		political_power -= float(cost)
		return true 
	return false 
#endregion
