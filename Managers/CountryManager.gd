extends Node

signal player_country_changed
var countries: Dictionary[String, CountryData] = {}
var countryNames: PackedStringArray = []
var player_country: CountryData

var Releasables: Array[ReleasableData] = []
var dead_countries: Dictionary[String, CountryData] = {}

#var mutexer: Mutex = Mutex.new()

func _on_hour_passed() -> void:
	#if GameState.is_loading_game:
	#	return
	#var timeStart = Time.get_unix_time_from_system()
	#WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(func (a_index: int): countries[countryNames[a_index]].process_hour(), countryNames.size()))

	for c_name: String in countryNames:
		countries[c_name].process_hour()
	#print("Hour passing took %f" % (Time.get_unix_time_from_system() - timeStart))

func _on_day_passed() -> void:
	#if GameState.is_loading_game:
	#	return

	EconomyManager.process_economy_day()
	#var timeStart = Time.get_unix_time_from_system()
	#WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(func (a_index: int): countries[countryNames[a_index]].process_day(), countryNames.size()))
	
	for c_name: String in countryNames:
		countries[c_name].process_day()
	#print("Day passing took %f" % (Time.get_unix_time_from_system() - timeStart))
	EventManager.check_super_events()

func initialize_countries(a_countriesData: Array) -> void:
	# Clear existing data before adding
	countries.clear()
	countryNames.clear()
	dead_countries.clear()
	player_country = null
	
	if GameState.is_loading_game:
		print("CountryManager: Initializing from save data...")
	
	#var timeStart = Time.get_unix_time_from_system()
	#WorkerThreadPool.wait_for_group_task_completion(
	#	WorkerThreadPool.add_group_task(
	#		func (a_index: int): add_country(a_countriesData[a_index]),
	#		a_countriesData.size()
	#	)
	#)
	
	for country: Dictionary in a_countriesData:
		add_country(country)
	#print("Adding Countries took %f" % (Time.get_unix_time_from_system() - timeStart))

	# print(countries.size())
	# print(JSON.stringify(countries, " "))
	# print()
	# print(countryNames.size())
	# print(JSON.stringify(countryNames, " "))

	# NOTE(soi): highkirkenuenly hv 0 idea why it crashes here sometimes
	for country: String in countryNames:
		if countries.has(country):
			countries[country].update_relations()
			for puppeted: String in countries[country].puppets:
				InformPuppet(countries[country], countries[puppeted])

	print("CountryManager: Initialized %d countries." % countries.size())

func _ensure_country_has_leader(country: CountryData) -> void:
	if !MapManager.significantFigures.get(country.governmentPositions["Leader"]):
		var new_figure = ImportantFigure.FromRandom(country.country_name)
		new_figure.occupation = "Leader"
		MapManager.significantFigures[new_figure.name] = new_figure
		country.figures.append(new_figure.name)
		country.governmentPositions["Leader"] = new_figure.name
		print("CountryManager: Assigned random leader %s to %s" % [new_figure.name, country.country_name])

func generate_missing_leaders() -> void:
	for c_name: String in countryNames:
		var country: CountryData = countries[c_name]
		_ensure_country_has_leader(country)
		country.InitializeCabinet()

func save_countries() -> Array:
	var polities: Array = []
	for country: CountryData in countries.values():
		polities.append(country.ToDict())
	for country: CountryData in dead_countries.values():
		polities.append(country.ToDict())
	return polities

func GetCountryColor(a_country: String, a_defaultColor: Color = Color.BLACK) -> Color:
	return countries[a_country].country_color if countries.has(a_country) else a_defaultColor

func set_player_country(country_name: String) -> void:
	var country: CountryData = countries.get(country_name)
	if !country:
		push_error("CountryManager: Requested non-existent country '%s'" % country_name)
		return

	if player_country:
		player_country.is_player = false
		#player_country.ai_controller = CountryAI.new(player_country)
	player_country = country
	player_country.is_player = true
	#player_country.ai_controller = null

	print("Player is now playing as: ", country_name)
	player_country_changed.emit()

func add_country(a_countryData: Dictionary) -> CountryData:
	if a_countryData["name"] == "Sea": return
	var tempName = a_countryData["name"]
	
	# 1. Check if it already exists
	if countries.has(tempName):
		push_warning("CountryManager: Country '%s' already exists!" % tempName)
		return countries[tempName]

	if dead_countries.has(tempName):
		var revived: CountryData = dead_countries[tempName]
		dead_countries.erase(tempName)
		countries[tempName] = revived
		countryNames.append(tempName)
		if revived.is_player:
			player_country = revived
		print("CountryManager: Revived country '%s'." % tempName)
		return revived

	# NOTE(soi): I DONT CARE WHO THE IRS SENDS IM NOT PAYNG MY TAXES
	# 2. Check if the flag exists before proceeding
	# if TroopManager.get_flag(tempName, IdeologyManager.get_ideology_name(
	# 	Vector2(a_countryData.get("ideology", [0, 0])[0], a_countryData.get("ideology", [0, 0])[0])
	# )) == null:
	# 	push_error("CountryManager: Cannot add '%s'. No flag found." % tempName)
	# 	return null

	# 3. If flag exists, create and store the country
	var new_country: CountryData = CountryData.FromDict(a_countryData)
	
	# NOTE Z21: Relations should be based on political affinity and stuff
	#for existing_name in countries.keys():
	#	new_country.set_relation_with(existing_name, 50)
	#	countries[existing_name].set_relation_with(tempName, 50)
	
	#mutexer.lock()
	countries[tempName] = new_country
	print(countries[tempName])
	countryNames.append(tempName)
	
	if new_country.is_player:
		player_country = new_country
		#player_country.ai_controller = null # Ensure player doesn't have an AI brain
	
	return new_country

# HELPER FUNCTIONS ==========================================

func get_country_population(country_name: String) -> int:
	if !MapManager.country_to_provinces.has(country_name):
		return 0
	var total_pop: int = 0
	for pid in MapManager.country_to_provinces[country_name]:
		if MapManager.province_objects.has(pid):
			total_pop += MapManager.province_objects[pid].GetPopulation()
	return total_pop

func get_country_gdp(country_name: String) -> int:
	if !MapManager.country_to_provinces.has(country_name):
		return 0
	var total_gdp: int = 0
	for pid: int in MapManager.country_to_provinces[country_name]:
		if MapManager.province_objects.has(pid):
			total_gdp += MapManager.province_objects[pid].gdp
	return total_gdp

func get_factories_amount(country_name: String) -> int:
	var factoryCount: int = 0
	if !MapManager.country_to_provinces.has(country_name): return 0
	for province: int in MapManager.country_to_provinces[country_name]:
		for building: BuildingData in MapManager.province_objects[province].buildings:
			#print("Checking %d, it is a %s in the %s state." % [province, building.type, building.state])
			if building.type == "Factory" && building.state == BuildingData.BuildingState.FUNCTIONAL:
				factoryCount += 1
	return factoryCount
	#return MapManager.country_to_provinces.get(country_name, []).reduce(
	#	func(pid: int, accum: int):
	#		return (accum + MapManager.province_objects[pid].buildings.reduce(
	#			func(building: BuildingData, b_accum: int): 
	#				return (b_accum + 1) if (building.type == "Factory" && building.state == BuildingData.BuildingState.FUNCTIONAL) else b_accum,\
	#			0
	#		) if (MapManager.province_objects.has(pid)) else 0),
	#	0
	#)

# NOTE(pol): We should keep track of the manpower used instead of recalculating
# In CountryManager.gd (or wherever this static function lives)
static func get_country_used_manpower(country_obj: CountryData) -> int:
	var total_used: int = 0
	var toUse: Dictionary[String, float] = {}


	# 2. Ongoing Training (Already using templates, but cleaned up)
	for training: CountryData.TroopTraining in country_obj.ongoing_training:
		toUse[training.division_type] = toUse.get(training.division_type, 0) + training.divisions_count

	# 3. Troops in the "Ready" queue (deployment pool)
	for batch: CountryData.ReadyTroop in country_obj.ready_troops:
		toUse[batch.division.type] = toUse.get(batch.division.type, 0) + batch.count
	
	for entry: String in toUse:
		total_used += int(toUse[entry] * _get_manpower_from_template(entry))

	# 1. Active Troops on the field
	for troop: TroopData in TroopManager.get_troops_for_country(country_obj.country_name):
		for div in troop.stored_divisions:
			total_used += int(div.hp * div.manpowerPerHP)
	
	return total_used

# Helper to keep the code DRY (Don't Repeat Yourself)
static func _get_manpower_from_template(type: String) -> int:
	return DivisionData.TEMPLATES.get(type, DivisionData.TEMPLATES["infantry"])["manpower"]

var cleanupLock: bool = false

func cleanup_empty_countries() -> void:
	var to_remove: PackedStringArray = []
	
	for c_name: String in countryNames:
		if MapManager.country_to_provinces.get(c_name, []).is_empty() && !countries[c_name].is_exiled:
			to_remove.append(c_name)

	for c_name: String in to_remove:
		print("CountryManager: Removing '%s' (No provinces found)." % c_name)
		# So here, we offer options: Government In Exile, or Dissolution
		var country: CountryData = countries[c_name]
		if country.is_player:
			# Uh oh.
			var lostTerritoryUI = get_tree().root.find_child("LostTerritoryUI", true, false)
			if lostTerritoryUI:
				# Pass the player as the default winner/beneficiary, and the full list of winners
				lostTerritoryUI.open_menu(country)
			pass
		else:
			var deleting: CountryData = CountryManager.countries[c_name]
			dead_countries[c_name] = deleting
			#CountryManager.Releasables.append(ReleasableData.FromDict({}))
			if deleting.owner in countryNames:
				CountryManager.release_puppet(CountryManager.countries[deleting.owner], deleting)
				
			for puppet: String in deleting.puppets:
				CountryManager.release_puppet(deleting, CountryManager.countries[puppet])
			
			FactionManager.clear_faction(deleting)
			
			MapManager.country_to_provinces.erase(c_name)
			MapManager.country_to_occupied_provinces.erase(c_name)
			MapManager.country_to_rightful_provinces.erase(c_name)
			MapManager.country_to_owned_provinces.erase(c_name)
			countries.erase(c_name)
			countryNames.erase(c_name)

func InformPuppet(puppeter: CountryData, puppetee: CountryData):
	puppeter.allowedCountries.append(puppetee.country_name)
	puppetee.allowedCountries.append(puppeter.country_name)
	puppetee.is_puppet = true
	puppetee.owner = puppeter.country_name
	puppetee.ideology = puppeter.ideology
	puppetee.relations[puppeter.country_name] = 200

func make_puppet(puppeter: CountryData, puppetee: CountryData):
	puppeter.puppets.append(puppetee.country_name)
	puppeter.allowedCountries.append(puppetee.country_name)
	puppetee.allowedCountries.append(puppeter.country_name)
	MapManager.allow_pids(puppeter, puppetee)
	MapManager.allow_pids(puppetee, puppeter)
	puppetee.is_puppet = true
	puppetee.owner = puppeter.country_name
	puppetee.ideology = puppeter.ideology
	puppetee.relations[puppeter.country_name] = 200
	FactionManager.clear_faction(puppetee)
	puppetee.factions = puppeter.factions
	FactionManager.invite_faction(puppeter, puppetee)
	MapManager.show_countries_map()

func release_puppet(puppeter: CountryData, puppetee: CountryData):
	MapManager.unallow_pids(puppeter, puppetee)
	puppeter.puppets.erase(puppetee.country_name)
	puppeter.allowedCountries.erase(puppetee.country_name)
	puppetee.allowedCountries.erase(puppeter.country_name)
	puppetee.is_puppet = false
	puppetee.owner = ""
	puppetee.factions = []
	MapManager.show_countries_map()

func MakeHost(a_host: CountryData, a_hosted: CountryData) -> void:
	a_host.hostedGovernments.append(a_hosted.country_name)
	a_host.allowedCountries.append(a_hosted.country_name)
	a_hosted.allowedCountries.append(a_host.country_name)
	a_hosted.is_exiled = true
	a_hosted.host = a_host.country_name
	MapManager.show_countries_map()

func FreeHost(a_host: CountryData, a_hosted: CountryData):
	a_host.puppets.erase(a_hosted.country_name)
	a_host.allowedCountries.erase(a_hosted.country_name)
	a_hosted.allowedCountries.erase(a_host.country_name)
	a_hosted.is_exiled = false
	a_hosted.host = ""
	MapManager.show_countries_map()

func RenameCountry(_a_old: String, _a_new: String) -> void:
	pass
