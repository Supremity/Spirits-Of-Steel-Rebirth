extends Node

signal player_stats_changed
signal player_country_changed
var countries: Dictionary[String, CountryData] = {}
var player_country: CountryData


func _on_hour_passed() -> void:
	for c_name: String in countries:
		var country_obj: CountryData = countries[c_name]
		country_obj.process_hour()
	player_stats_changed.emit()


func _on_day_passed() -> void:
	for c_name: String in countries:
		var country_obj: CountryData = countries[c_name]
		country_obj.process_day()
	player_stats_changed.emit()


func initialize_countries() -> void:
	countries.clear()

	var detected_countries = MapManager.country_to_provinces.keys()
	if detected_countries.is_empty():
		push_warning("CountryManager: No countries detected in MapManager!")
		detected_countries = MapManager.COUNTRY_COLORS.keys()

	for country_name in detected_countries:
		var new_country := CountryData.new(country_name)
		add_child(new_country)
		countries[country_name] = new_country

	print("CountryManager: Initialized %d countries." % countries.size())


func get_country(c_name: String) -> CountryData:
	c_name = c_name.to_lower()
	if countries.has(c_name):
		return countries[c_name]
	push_error("CountryManager: Requested non-existent country '%s'" % c_name)
	return null


func set_player_country(country_name: String) -> void:
	var country := countries.get(country_name.to_lower()) as CountryData
	if !country:
		push_error("CountryManager: Requested non-existent country '%s'" % country_name)
		return

	# Disable AI for the previous player country (if switching is allowed)
	if player_country:
		player_country.is_player = false

	player_country = country
	player_country.is_player = true  # <--- IMPORTANT: Disable AI for this country

	print("Player is now playing as: ", country_name)
	emit_signal("player_country_changed")


# HELPER FUNCTIONS ==========================================


func get_country_population(country_name: String) -> int:
	if not MapManager.country_to_provinces.has(country_name):
		return 0
	var total_pop: int = 0
	var pids = MapManager.country_to_provinces[country_name]
	for pid in pids:
		if MapManager.province_objects.has(pid):
			total_pop += MapManager.province_objects[pid].population
	return total_pop


func get_country_gdp(country_name: String) -> int:
	if not MapManager.country_to_provinces.has(country_name):
		return 0

	var total_gdp: int = 0
	var pids = MapManager.country_to_provinces[country_name]

	for pid in pids:
		if MapManager.province_objects.has(pid):
			total_gdp += MapManager.province_objects[pid].gdp

	return total_gdp


func get_country_used_manpower(country_name, country_obj) -> int:
	var total_divisions = 0
	var troop_list = TroopManager.get_troops_for_country(country_name)
	for troop in troop_list:
		total_divisions += troop.divisions
	for training in country_obj.ongoing_training:
		total_divisions += training.divisions
	for ready in country_obj.ready_troops:
		total_divisions += ready.divisions
	return total_divisions * country_obj.manpower_per_division
