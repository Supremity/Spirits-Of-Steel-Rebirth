extends Node

enum IndustryType { DEFAULT = 0, FACTORY = 1, PORT = 2, INFRASTRUCTURE = 3 }

var current_world: World
var current_start: String
# var current_scenario_path: String

var clock_cache: Dictionary

var choosing_deploy_city := false
var industry_building := IndustryType.DEFAULT
var instabuild: bool = false

var game_ui: GameUI

var decision_menu_open: bool = false
var in_peace_process: bool = false
var lostTerritory: bool = false
var selectingCountry: bool = true

@export var showingTooltip: bool = false
@export var tooltip: Tooltip

func reset_industry_building():
	industry_building = IndustryType.DEFAULT
	MapManager.ShowCountriesMap()

var is_loading_game := false
var pending_load_save: String = ""
