extends Node


func _ready() -> void:
	# Same thing
	Console.add_command("play_country", CountryManager.set_player_country, ["country_name"])
	Console.add_command("play_as", CountryManager.set_player_country, ["country_name"])

	pass  # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
