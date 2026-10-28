extends Control

@onready var background_rect: TextureRect = $"VBoxContainer/background"
# @onready var heading_label: Label = $"PanelContainer/VBoxContainer/description"
@onready var button: Button = $"VBoxContainer/Button"

func _ready():
	pass

func setup(a_text: String, a_background: String, start_folder: String):
	# Data format: { "background": "ww3", "desc": "...", "button": "..." }
	# if data.has("desc"):
	# 	desc_label.text = data["desc"]
	if button:
		button.text = a_text
		var map_data: Dictionary = ScenarioData.load_start(start_folder)
		
		var load_map_data = func():
			SceneSwitcher.switch_to(SceneSwitcher.Type.WORLD, func(a_percent: Array):
				#a_percent = [0.0]
				GameState.current_start = a_text
				# GameState.current_scenario_path = start_folder #dear god lets not 
				a_percent[0] = 0.01
				EconomyManager.initialize(start_folder + "building_functions.json")
				a_percent[0] = 0.02
				PlansManager.load_plans_from_path(start_folder + "plans.json")
				a_percent[0] = 0.06
				DecisionManager.load_decisions_from_path(start_folder + "decisions/")
				a_percent[0] = 0.12
				EventManager.load_super_events(start_folder + "superevents.json")
				a_percent[0] = 0.18
				TroopManager.set_custom_flag_path(start_folder + "flags/")
				a_percent[0] = 0.2
				IdeologyManager.Initialize(map_data.get("ideologies", {}) as Dictionary)
				a_percent[0] = 0.3
				var b_data = map_data.get("biomes")
				MapManager.LoadBiomes(b_data if b_data is Array else [])
				var recipes_data = map_data.get("recipes")
				MapManager.LoadRecipes(recipes_data if recipes_data is Array else [])
				var r_data = map_data.get("resources")
				MapManager.LoadResources(r_data if r_data is Array else [])
				MapManager.load_country_data(
					load(start_folder + "regions.png"),
					map_data.get("provinces", {}) as Dictionary,
					a_percent
				)
				a_percent[0] = 0.6
				if map_data.has("significant_figures"):
					for fig in map_data["significant_figures"]:
						MapManager.significantFigures[fig["name"]] = ImportantFigure.FromDict(fig)
				a_percent[0] = 0.65
				CountryManager.initialize_countries(map_data.get("polities", []) as Array)
				a_percent[0] = 0.75
				MapManager.build_lookup_texture()
				a_percent[0] = 0.85
				FactionManager.Initialize(map_data.get("factions", []))
				a_percent[0] = 0.9
				Console.add_command_autocomplete_list("tag", CountryManager.countryNames)
				a_percent[0] = 1.0
				#CountryManager.generate_missing_leaders()
			)
		button.pressed.connect(load_map_data)
		
	if a_background:
		if FileAccess.file_exists(a_background) or ResourceLoader.exists(a_background):
			background_rect.texture = load(a_background)
		else:
			push_warning("StartEntry: Background image not found at %s" % a_background)

# func _on_button_pressed():
	# queue_free()
