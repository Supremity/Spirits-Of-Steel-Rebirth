extends Node


func _ready() -> void:
	# Same thing
	Console.add_command("play_country", CountryManager.set_player_country, ["country_name"])
	Console.add_command("play_as", CountryManager.set_player_country, ["country_name"])
	Console.add_command("start_war", start_war, ["a", "b"], 2, "Start a war between 2 countries`")
	Console.add_command(
		"annex", MapManager.annex_country, ["country_name"], 1, "Annex Country for Player"
	)
	pass  # Replace with function body.


func start_war(country_a, country_b):
	country_a = CountryManager.get_country(country_a)
	country_b = CountryManager.get_country(country_b)
	WarManager.add_war_silent(country_a, country_b)
	pass
