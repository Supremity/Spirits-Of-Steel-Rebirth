extends Node


func _ready() -> void:
	Console.add_command("play_country", CountryManager.set_player_country, ["country_name"])
	Console.add_command("play_as", CountryManager.set_player_country, ["country_name"])
	Console.add_command("start_war", start_war, ["a", "b"], 2, "Start a war between 2 countries`")
	Console.add_command(
		"annex", MapManager.annex_country, ["country_name"], 1, "Annex Country for Player"
	)


func start_war(country_a, country_b):
	country_a = CountryManager.get_country(country_a)
	country_b = CountryManager.get_country(country_b)
	WarManager.declare_war(country_a, country_b)
