extends Node

enum INDUSTRY { NOTHING = 0, FACTORY = 1, PORT = 2 }

var current_world: World

var choosing_deploy_city := false
var industry_building := INDUSTRY.NOTHING

var game_ui: GameUI


func reset_industry_building():
	industry_building = INDUSTRY.NOTHING
