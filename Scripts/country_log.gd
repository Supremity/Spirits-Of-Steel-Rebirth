extends CanvasLayer

@onready var income: Label = $ColorRect/VBoxContainer2/income
@onready var armycost: Label = $ColorRect/VBoxContainer2/armycost
@onready var armylevel: Label = $ColorRect/VBoxContainer2/armylevel
@onready var totalmanpower: Label = $ColorRect/VBoxContainer2/totalmanpower
@onready var availablemanpower: Label = $ColorRect/VBoxContainer2/availablemanpower
@onready var infield: Label = $ColorRect/VBoxContainer2/infield

@onready var armylevelagain: Label = $ColorRect/armylevelagain
@onready var basecost: Label = $ColorRect/basecost

var player: CountryData = null


func _ready() -> void:
	GameState.game_log = self
	player = CountryManager.player_country
	CountryManager.player_stats_changed.connect(_on_stats_changed)


func _on_stats_changed():
	# Re-fetch the player in case it was null at start
	if player == null:
		player = CountryManager.player_country

	# SAFETY CHECK: If player is still null, don't run the code
	if player == null:
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
	player.army_level += 1
	pass  # Replace with function body.


func _on_button_2_button_up() -> void:
	if player.army_level <= 1:
		return
	player.army_level -= 1
	pass  # Replace with function body.
