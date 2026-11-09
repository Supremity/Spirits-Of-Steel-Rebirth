extends Node2D
class_name World

@onready var map_sprite: Sprite2D = $"../../MapContainer/CultureSprite" as Sprite2D
@onready var camera: Camera2D = $"../../Camera2D" as Camera2D
@onready var troop_renderer: CustomRenderer = $CustomRenderer as CustomRenderer

@export var map_shader: Shader
var clock: GameClock

var water_offset: Vector2 = Vector2.ZERO

var type_img: Image

var mat: ShaderMaterial

func _process(_delta: float) -> void:
	if !map_sprite or !MapManager.id_map_image: return
	var map_width := MapManager.id_map_image.get_width()
	if camera.position.x > map_sprite.position.x + map_width:
		camera.position.x -= map_width
	elif camera.position.x < map_sprite.position.x - map_width:
		camera.position.x += map_width
	if map_sprite.material and clock and !clock.paused:
		var move_amount = clock.time_scale * 0.001 * _delta
		water_offset.x += move_amount
		map_sprite.material.set_shader_parameter("ocean_offset", water_offset)
		map_sprite.material.set_shader_parameter("absolute_days", clock.get_absolute_days())


func _enter_tree() -> void:
	GameState.current_world = self
	clock = $/root/Main/Clock
	clock.FromDict(GameState.clock_cache)
	KeyboardManager.settings = $/root/Main/SettingsLayer
	TroopManager.troop_selection = $TroopSelection as TroopSelection
	# TODO(pol): Load CountryManager after map instead of an autoload to avoid this.

func DoSetup(a_progress: Array) -> void:
	var mapData: Dictionary = {}
	var path = "res://starts/%s" % GameState.current_start

	if GameState.pending_load_save != "":
		var save_path = "res://saves/" + GameState.pending_load_save + ".json"
		if FileAccess.file_exists(save_path):
			var file = FileAccess.open(save_path, FileAccess.READ)
			var save_json = JSON.parse_string(file.get_as_text())
			if save_json is Dictionary:
				mapData = save_json
				path = mapData.get("scenario_path", path)
				# GameState.current_scenario_path = path
				GameState.is_loading_game = true
				print("World: Pending save found. Loading from: ", GameState.pending_load_save)

	# if mapData.is_empty():
	# 	print(path)
	# 	var json_data = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	# 	mapData = json_data if json_data is Dictionary else {}

	a_progress[0] = 0.05

	# NOTE(soi): this is here bcuz sometimes main menu is used and im too lazy to comment this out
	if MapManager.province_objects.is_empty() or GameState.is_loading_game:
		LoadMapData(path, a_progress)
	
	if GameState.is_loading_game:
		GameState.is_loading_game = false
		GameState.pending_load_save = ""
	a_progress[0] = 0.2

	print("World: Map is ready -> configuring visuals...")

	MapManager.all_cities = MapManager.GetAllCities()
	a_progress[0] = 0.21

	if !CountryManager.player_country:
		# CountryManager.set_player_country(CountryManager.countries.keys().pick_random())
		GameState.selectingCountry = true
		# NOTE(soi): wait so like when i click on a country this should magically play as it?????. damm
	# For debugging purposes. Create some troops first
	# MapManager.force_bidirectional_connections()
	a_progress[0] = 0.30
	MapManager._build_global_registry()
	a_progress[0] = 0.35
	var map_width: int = MapManager.MAP_WIDTH
	var map_height: int = MapManager.MAP_HEIGHT

	mat = ShaderMaterial.new()
	mat.shader = map_shader
	mat.set_shader_parameter("region_id_map", ImageTexture.create_from_image(MapManager.id_map_image))
	mat.set_shader_parameter("state_colors", MapManager.state_color_texture)

	# @warning_ignore("narrowing_conversion")
	type_img = Image.create_empty(map_width, map_height, false, Image.FORMAT_L8)

	print(map_width, map_height)
	MapManager._set_type_map(mat, type_img)

	var noise = FastNoiseLite.new()
	noise.seed = randi()

	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	noise.frequency = 0.005

	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 3.0
	noise.fractal_gain = 0.5

	var noise_tex = NoiseTexture2D.new()
	noise_tex.seamless = true
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.noise = noise

	await noise_tex.changed
	mat.set_shader_parameter("ocean_noise", noise_tex)

	mat.set_shader_parameter("original_texture", map_sprite.texture)
	mat.set_shader_parameter("sea_speed", 0.00) # Changed by MainClock
	mat.set_shader_parameter("tex_size", Vector2(map_width, map_height))
	mat.set_shader_parameter("country_border_color", Color.BLACK)

	map_sprite.material = mat
	a_progress[0] = 0.9
	_clear_ghost_maps()
	for i in [-2, -1, 1, 2]:
		_create_ghost_map(Vector2(i * map_width, 0), mat)
		a_progress[0] += 0.015

	if troop_renderer:
		troop_renderer.map_sprite = map_sprite
		troop_renderer.map_width = map_width
	else:
		push_error("CustomRenderer node not found!")

	SettingsManager.apply_settings()

	a_progress[0] = 1.0
	
	clock.hour_passed.connect(CountryManager._on_hour_passed)
	clock.day_passed.connect(CountryManager._on_day_passed)
	clock.day_passed.connect(EventManager._on_day_passed)
	
	_refresh_map_visuals()

func _refresh_map_visuals() -> void:
	if mat and MapManager.state_color_texture:
		mat.set_shader_parameter("state_colors", MapManager.state_color_texture)

func _LoadJSON(path: String):
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())

func LoadMapData(a_start_path: String, a_percent: Array = [0]):
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
	EconomyManager.initialize(a_start_path + "building_functions.json")
	a_percent[0] = 0.02
	PlansManager.load_plans_from_path(a_start_path + "plans.json")
	a_percent[0] = 0.06
	EventManager.load_super_events(a_start_path + "superevents.json")
	a_percent[0] = 0.18

	var b_data = map_data.get("biomes", [])
	MapManager.LoadBiomes(b_data)
	
	var r_data = map_data.get("resources", [])
	MapManager.LoadResources(r_data)
	
	var buildingData = map_data.get("buildings")
	EconomyManager.LoadBuildings(buildingData if buildingData is Dictionary else {})
	
	var i_data = map_data.get("ideologies", {})
	IdeologyManager.Initialize(i_data)
	a_percent[0] = 0.3
	
	
	DecisionManager.load_decisions_from_path("%s/decisions/"%a_start_path)
	a_percent[0] = 0.2
	TroopManager.set_custom_flag_path("%s/flags/"%a_start_path)
	a_percent[0] = 0.12
	CountryManager.initialize_countries(scenario_data.get("polities", []) as Array)
	a_percent[0] = 0.75
	MapManager.LoadCountryData(
		regions_tex,
		provinces,
		a_percent,
	)
	a_percent[0] = 0.6
	
	# Restore Clock
	if clock:
		if map_data.has("clock"):
			clock.FromDict(map_data["clock"])
		else:
			# Default start date for scenarios/new games
			clock.FromDict({"hour": 0, "date": {"year": 2010, "month": 1, "day": 1}})
	
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


func save_game(slot: String):
	# Construct a unified save dictionary
	var save_data: Dictionary = {
		"clock": clock.ToDict() if clock else {},
		"resources": MapManager.SaveResourcesData(),
		"biomes": MapManager.SaveBiomeData(),
		"buildings": MapManager.SaveBuildingData(),
		"provinces": MapManager.SaveCountryData(),
		"polities": CountryManager.save_countries(),
		"ideologies": IdeologyManager.ideologies,
		"factions": FactionManager.save_factions(),
		"wars": WarManager.save_wars(),
		"original_territories": WarManager.save_original_territories(),
		"scheduled_events": EventManager.save_events()
	}
	
	# Ensure directory exists
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("saves/"):
		dir.make_dir_recursive("saves/")
		
	var path = "res://saves/" + slot + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(save_data, "\t")
		if json_string == "":
			push_error("Save failed! JSON stringify returned empty. Check for non-serializable types.")
		else:
			file.store_string(json_string)
			file.close()
			print("Game State saved successfully to: ", ProjectSettings.globalize_path(path))
	else:
		push_error("Save failed! Could not open " + path + " for writing. Error: " + str(FileAccess.get_open_error()))

	
func load_game(save_name: String):
	var path: String = "res://saves/" + save_name + ".json"

	if not FileAccess.file_exists(path):
		push_error("Save file not found: " + path)
		return

	var file = FileAccess.open(path, FileAccess.READ)
	var json_text = file.get_as_text()
	var save_data = JSON.parse_string(json_text)
	
	if not save_data:
		push_error("Failed to parse save JSON: " + path)
		return

	# Pause systems that react to state
	if troop_renderer:
		troop_renderer.set_process(false)

	# Update current scenario tracking
	# GameState.current_scenario_path = save_data.get("scenario_path", "")
	# 1. Full State Reset
	TroopManager.clear_all_troops()
	WarManager.reset_state()
	
	# Close Peace UI if open
	var peace_ui = get_tree().root.find_child("PeaceProcessUI", true, false)
	if peace_ui and peace_ui.has_method("force_close"):
		peace_ui.force_close()
	GameState.in_peace_process = false
	
	# 2. Load the save data in strict dependency order:
	# A. Countries first (so they exist in managers)
	CountryManager.initialize_countries(save_data.get("polities", []) as Array)
	
	# B. Map/Provinces/Troops next (they need the countries above)
	LoadMapData(save_data)
	
	# C. Factions/Clock/etc last
	FactionManager.Initialize(save_data.get("factions", []) as Array)
	if save_data.has("clock") && clock:
		clock.FromDict(save_data["clock"])
	
	WarManager.load_wars(save_data.get("wars", []))
	WarManager.load_original_territories(save_data.get("original_territories", {}))
	WarManager.check_for_new_battles()
	
	EventManager.load_events(save_data.get("scheduled_events", []))
	
	GameState.is_loading_game = false
	_refresh_map_visuals()

	if troop_renderer:
		troop_renderer.set_process(true)

	print("Game loaded successfully:", save_name)


func _exit_tree() -> void:
	_clear_ghost_maps()


func _clear_ghost_maps() -> void:
	var container = get_node_or_null("../../MapContainer")
	if container:
		for child in container.get_children():
			if child.has_meta("is_ghost"):
				child.queue_free()


func _create_ghost_map(offset: Vector2, p_material: ShaderMaterial) -> void:
	var ghost := Sprite2D.new()
	ghost.texture = map_sprite.texture
	ghost.centered = map_sprite.centered
	ghost.material = p_material
	ghost.position = map_sprite.position + offset
	ghost.set_meta("is_ghost", true)
	$"../../MapContainer".add_child(ghost)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			MapManager.HandleClickDown(get_global_mouse_position(), map_sprite)
		else:
			MapManager.HandleClick(get_global_mouse_position(), map_sprite)
	if event is InputEventMouseMotion:
		MapManager.HandleHover(get_global_mouse_position(), map_sprite)
