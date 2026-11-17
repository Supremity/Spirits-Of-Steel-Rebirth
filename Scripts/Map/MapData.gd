@tool
extends Resource
class_name MapData

# NOTE(soi): 0 clue what we could even need these for
@export var id_map_image: Image
@export var adjacency_list: Dictionary
@export var province_centers: Dictionary

@export var province_to_country: Dictionary
@export var country_to_provinces: Dictionary
@export var max_province_id: int
@export var province_objects: Dictionary

static func _LoadJSON(path: String):
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())

static func _SaveJSON(path, filename, string):
	var file: FileAccess = FileAccess.open(path+filename, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(string , "\t"))
		file.close()
		print("Scenario exported to: ", path)
	else:
		push_error("Failed to export_mapdata scenario to: ", path)

static func SaveMapData(path: String) -> void:
	var fig_dicts: Array[Dictionary] = []
	for x: ImportantFigure in MapManager.significantFigures.values():
		fig_dicts.append(x.ToDict())
	var export_map_data = {
		"ideologies": IdeologyManager.ideologies,
		"buildings": MapManager.SaveBuildingData(),
		"resources": MapManager.SaveResourcesData(),
		"biomes": MapManager.SaveBiomeData(),
		"clock": GameState.current_world.clock.ToDict() if GameState.current_world.clock else {},
	}

	var export_scenario = {
		"significant_figures": fig_dicts,
		"polities": CountryManager.SaveCountries(),
		"factions": FactionManager.SaveFactions(),
	}

	var export_province = MapManager.SaveProvinces()

	_SaveJSON(path, "map_data.json",      export_map_data)
	_SaveJSON(path, "provinces.json",     export_province)
	_SaveJSON(path, "scenario_data.json", export_scenario)

static func LoadMapData(a_start_path: String, a_percent: Array = [0]):
	var map_data:      Dictionary = _LoadJSON("%s/map_data.json"%a_start_path)
	var provinces:     Dictionary = _LoadJSON("%s/provinces.json"%a_start_path)
	var scenario_data: Dictionary = _LoadJSON("%s/scenario_data.json"%a_start_path)

	# print(map_data)
	# print(provinces)
	# print(scenario_data)

	var regions_tex: Texture2D = load("%s/regions.png"%a_start_path)
	print("%s/regions.png"%a_start_path)

	# GameState.current_start = a_text
	a_percent[0] = 0.01
	EconomyManager.initialize(a_start_path + "/building_functions.json")
	a_percent[0] = 0.02
	PlansManager.load_plans_from_path(a_start_path + "plans.json")
	a_percent[0] = 0.06
	EventManager.load_super_events(a_start_path + "superevents.json")
	a_percent[0] = 0.18

	var b_data: Array = map_data.get("biomes", [])
	MapManager.LoadBiomes(b_data)
	
	var r_data: Array = map_data.get("resources", [])
	MapManager.LoadResources(r_data)
	
	var buildingData = map_data.get("buildings")
	EconomyManager.LoadBuildings(buildingData if buildingData is Dictionary else {})
	
	var ideologyData = map_data.get("ideologies", {})
	IdeologyManager.Initialize(ideologyData)
	a_percent[0] = 0.3
	
	
	DecisionManager.load_decisions_from_path("%s/decisions/"%a_start_path)
	a_percent[0] = 0.2
	TroopManager.set_custom_flag_path("%s/flags/"%a_start_path)
	a_percent[0] = 0.12
	CountryManager.initialize_countries(scenario_data.get("polities", []) as Array)
	a_percent[0] = 0.75
	MapManager.LoadProvinces(
		regions_tex,
		provinces,
		a_percent,
	)
	a_percent[0] = 0.6
	
	# Restore Clock
	if GameState.current_world.clock:
		if map_data.has("clock"):
			GameState.current_world.clock.FromDict(map_data["clock"])
		else:
			# Default start date for scenarios/new games
			GameState.current_world.clock.FromDict({"hour": 0, "date": {"year": 2010, "month": 1, "day": 1}})
	
	WarManager.load_wars(map_data.get("wars", []))
	WarManager.load_original_territories(map_data.get("original_territories", {}))
	WarManager.check_for_new_battles()
	
	MapManager.BuildLookupTexture()
	a_percent[0] = 0.85
	FactionManager.Initialize(scenario_data.get("factions", []))
	a_percent[0] = 0.9
	
	for fig in scenario_data.get("significant_figures", []):
		MapManager.significantFigures[fig["name"]] = ImportantFigure.FromDict(fig)
	CountryManager.generate_missing_leaders()
	CountryManager.cleanup_empty_countries()
	
	Console.add_command_autocomplete_list("tag", CountryManager.countries.keys())
