extends CanvasLayer

@onready var income: Label = $ColorRect/VBoxContainer2/income
@onready var armycost: Label = $ColorRect/VBoxContainer2/armycost
@onready var armylevel: Label = $ColorRect/VBoxContainer2/armylevel
@onready var totalmanpower: Label = $ColorRect/VBoxContainer2/totalmanpower
@onready var availablemanpower: Label = $ColorRect/VBoxContainer2/availablemanpower
@onready var infield: Label = $ColorRect/VBoxContainer2/infield

@onready var armylevelagain: Label = $ColorRect/armylevelagain
@onready var basecost: Label = $ColorRect/basecost


func _ready() -> void:
	GameState.game_log = self
	GameState.current_world.clock.hour_passed.connect(_on_hour_passed)


func _on_hour_passed():
	var player := CountryManager.player_country

	# SAFETY CHECK: If player is still null, don't run the code
	if CountryManager.player_country == null:
		return

	income.text = format_number(player.income)
	armycost.text = format_number(player.army_cost)
	# Don't forget to update your other labels too!
	armylevel.text = str(player.army_level)
	availablemanpower.text = format_number(player.manpower)
	infield.text = format_number(
		CountryManager.get_country_used_manpower(player.country_name, player)
	)
	basecost.text = "Base Cost Divison: " + format_number(player.army_base_cost * player.army_level)
	armylevelagain.text = str(player.army_level)


func format_number(value: float) -> String:
	var abs_val = abs(value)
	var sign_str = "-" if value < 0 else ""
	if abs_val >= 1_000_000_000:
		return sign_str + "%.2fB" % (abs_val / 1_000_000_000.0)
	elif abs_val >= 1_000_000:
		return sign_str + "%.2fM" % (abs_val / 1_000_000.0)
	elif abs_val >= 1_000:
		return sign_str + "%.1fK" % (abs_val / 1_000.0)
	return sign_str + str(floori(abs_val))


func _on_button_button_up() -> void:
	CountryManager.player_country.army_level += 1


func _on_button_2_button_up() -> void:
	if CountryManager.player_country.army_level <= 1:
		return
	CountryManager.player_country.army_level -= 1
