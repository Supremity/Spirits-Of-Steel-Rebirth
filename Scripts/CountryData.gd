extends Node
class_name CountryData

# --- Country Identity ---
var country_name: String
var is_player: bool = false 

# --- Population & Resources ---
var total_population: int = 0
var political_power: float = 50.0
var money: float = 40000.0
var manpower: int = 0          # Initialized in _init as 0.5% of pop
var stability: float = 0.5      # 0.0 to 1.0
var war_support: float = 0.5    # 0.0 to 1.0

# --- Economy/Growth ---
var daily_pp_gain: float = 0.04
var hourly_money_income: float = 4000
var daily_manpower_growth: int = 100 # Adjust as needed based on pop

var allowedCountries: Array[String] = [] 
var ongoing_training: Array[TroopTraining] = []
var ready_troops: Array[ReadyTroop] = []

var deploy_pid = -1

# --- Inner Classes ---
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

# --- Initialization ---
func _init(p_name: String) -> void:
	country_name = p_name
	self.name = p_name
	allowedCountries.append(p_name)
	
	total_population = CountryManager.get_country_population(country_name)
	
	# 2. Set Manpower to 0.5% of popultion
	manpower = int(total_population * 0.005)

# =========================================================
# Daily Turn Processing
# =========================================================
func process_hour() -> void:
	# 1. Update Economy
	political_power += daily_pp_gain
	money += (hourly_money_income - calculate_army_upkeep())
	#manpower += daily_manpower_growth # You might want to make this % based too
	
	if not is_player:
		_process_ai_decisions()

func process_day() -> void:
	_process_training()

# =========================================================
# AI LOGIC (Daily Updates)
# =========================================================
func _process_ai_decisions() -> void:
	# Deploy units immediately when ready
	if not ready_troops.is_empty():
		_ai_handle_deployment()

	# Recruit if conditions are met
	_ai_consider_recruitment()

func _ai_handle_deployment() -> void:
	var troops_to_deploy = ready_troops.duplicate()
	for troop in troops_to_deploy:
		deploy_ready_troop_to_random(troop)

func _ai_consider_recruitment() -> void:
	# Basic AI safety buffer
	var safety_buffer = hourly_money_income * 10.0
	
	if money < safety_buffer or manpower < 5000:
		return 

	# AI standard recruitment specs
	train_troops(5, 10, 50.0)


func get_max_morale() -> float:
	var base := 60.0 + (stability * 40.0)
	if money < 0: base *= 0.5
	return base

func get_attack_efficiency() -> float:
	var eff := 0.9 + (war_support * 0.3)
	if money < 0: eff *= 0.7
	return eff

func get_defense_efficiency() -> float:
	var eff := 1.0 + (stability * 0.15)
	if money < 0: eff *= 0.8
	return eff

func _process_training() -> void:
	# Handle progress
	for training in ongoing_training:
		var daily_cost := training.divisions * training.daily_cost
		if money >= daily_cost:
			money -= daily_cost
			training.days_left -= 1
	
	# Handle completion
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

func train_troops(divisions: int, days: int, cost_per_day: float) -> bool:
	var manpower_needed := divisions * 10000 
	var first_hour_cost := divisions * cost_per_day
	
	if manpower < manpower_needed:
		return false
		
	if money < first_hour_cost:
		return false
	
	manpower -= manpower_needed
	money -= first_hour_cost
	
	ongoing_training.append(TroopTraining.new(divisions, days, cost_per_day))
	return true

func deploy_ready_troop_to_random(troop: ReadyTroop) -> bool:
	var index = ready_troops.find(troop)
	if index == -1: return false
	
	var my_provinces: Array = MapManager.country_to_provinces.get(country_name, [])
	if my_provinces.is_empty():
		return false
		
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
	
func spend_politicalpower(cost: int) -> bool:
	if floori(political_power) >= cost:
		political_power -= float(cost)
		return true 
	else:
		return false 
	
