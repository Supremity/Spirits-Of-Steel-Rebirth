extends Node
class_name CountryData


# --- Stats ---
var country_name: String
var political_power: int = 25
var money: float = 1000.0
var manpower: int = 50000
var stability: float = 0.75

# --- Daily Gains ---
var daily_pp_gain: int = 2
var daily_money_income: float = 1000
var daily_manpower_growth: int = 600


var allowedCountries: Array[String] = [] # for pathfinding (country names)


func _init(p_name: String) -> void:
	country_name = p_name
	self.name = p_name 
	allowedCountries.append(p_name)

# Called by country manager
func process_turn() -> void:
	political_power += daily_pp_gain
	money += (daily_money_income - calculate_army_upkeep())
	manpower += daily_manpower_growth
	
	# Stability logic
	var target := 0.75
	stability += (target - stability) * 0.01


func calculate_army_upkeep() -> float:
	var total_upkeep = 0.0
	
	for troop in TroopManager.get_troops_for_country(country_name):
		total_upkeep += troop.divisions * 10
		
	return total_upkeep
