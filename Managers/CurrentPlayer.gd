extends Node

signal stats_changed()

var country_name: String = "spain"
var flag_texture: Texture2D = TroopManager.get_flag(country_name)

#-------
# Stats
var political_power: int = 0
var stability: float = 0.75   # 0.0 → 1.0
var money: int = 1000
var manpower: int = 50000



# Constants for now
var MIN_STABILITY := 0.0
var MAX_STABILITY := 1.0
var POLITICAL_POWER_GAIN_DAILY := 2.0
var DOLLAR_INCOME_DAILY := 480.0      # example: 20/hour * 24
var MANPOWER_GROWTH_DAILY := 600       # example: 25/hour * 24



func get_country():
	return self.country_name.to_lower()
func _ready() -> void:
	await get_tree().process_frame  # wait until all singletons are ready
	if MainClock and not MainClock.is_connected("day_passed", Callable(self, "_on_day_passed")):
		MainClock.connect("day_passed", Callable(self, "_on_day_passed"))




# Connected to day_passed signal of gameclock
func _on_day_passed(day, month, year) -> void:
	_update_daily_resources()
	emit_signal("stats_changed")

# Resource updates
func _update_daily_resources() -> void:
	_add_political_power(POLITICAL_POWER_GAIN_DAILY)
	_add_money(DOLLAR_INCOME_DAILY)
	_add_manpower(MANPOWER_GROWTH_DAILY)
	_update_stability_over_time()

# pp stuff 
func _add_political_power(amount: float) -> void:
	political_power += amount
	political_power = max(political_power, 0.0)

func spend_political_power(amount: float) -> bool:
	if political_power < amount:
		return false
	political_power -= amount
	return true


func change_stability(delta: float) -> void:
	stability = clamp(stability + delta, MIN_STABILITY, MAX_STABILITY)


# This logic is getting changed. This is just for testing
func _update_stability_over_time() -> void:
	var target := 0.75
	stability += (target - stability) * 0.01
	stability = clamp(stability, MIN_STABILITY, MAX_STABILITY)



func _add_money(amount: float) -> void:
	money += amount

func spend_dollars(amount: float) -> bool:
	if money < amount:
		return false
	money -= amount
	return true


func _add_manpower(amount: int) -> void:
	manpower += amount

func spend_manpower(amount: int) -> bool:
	if manpower < amount:
		return false
	manpower -= amount
	return true


func setup_player_country(_name: String, _flagName: String) -> void:
	country_name = _name
	#flag_texture = DataManager.get_country_flag(country_name) 
	print("Player country set to:", country_name)
	emit_signal("stats_changed")



func format_k(number: int) -> String:
	if number >= 1000:
		return str(number / 1000) + "k"
	else:
		return str(number)


# 1. Returns a Dictionary → use this for UI updates
func get_stats() -> Dictionary:
	return {
		"political_power": political_power,
		"manpower": manpower,
		"money": money,
		"stability": stability,
	}

func get_stats_string () -> Dictionary:
	return {
		"political_power": str(political_power),
		"stability": str(stability * 100.0),
		"money": format_k(money),
		"manpower": format_k(manpower)
		
	}
	

# Helper
func get_summary() -> Dictionary:
	return {
		"name": country_name,
		"flag": flag_texture,
		"political_power": int(political_power),
		"stability": int(stability * 100.0),
		"money": int(money),
		"manpower": manpower
	}
