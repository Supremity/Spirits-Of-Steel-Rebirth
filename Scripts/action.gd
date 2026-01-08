class_name ActionRow
extends HBoxContainer

@onready var button: Button = $ColorRect/Button

var data: Dictionary = {}
var base_text: String = ""
var _callback: Callable
var source_object: Variant = null # Holds TroopTraining or ReadyTroop objects


func _ready() -> void:
	button.pressed.connect(_on_button_pressed)
	GameState.current_world.clock.day_passed.connect(refresh_ui)


func setup(item_data: Dictionary, on_click: Callable) -> void:
	data = item_data
	_callback = on_click
	source_object = null # Reset since this is a standard action
	base_text = data.get("text", "Unknown Action")
	
	if not is_node_ready(): await ready
	refresh_ui()

# Specialized setup for Training batches
func setup_training(troop: CountryData.TroopTraining) -> void:
	source_object = troop
	data = {"is_status": true} 
	_callback = Callable() # Training batches aren't clickable
	base_text = "Training %d Divs" % troop.divisions
	
	if not is_node_ready(): await ready
	button.disabled = true
	button.modulate = Color.GOLD
	refresh_ui()

# Specialized setup for Ready-to-Deploy troops
func setup_ready(troop: CountryData.ReadyTroop, on_click: Callable) -> void:
	source_object = troop
	data = {"is_deploy": true}
	_callback = on_click 
	base_text = "Deploy %d Divisions" % troop.divisions
	
	if not is_node_ready(): await ready
	button.disabled = false
	button.modulate = Color.SPRING_GREEN
	refresh_ui()
	
# ── UI Refresh Logic ──────────────────────────────────
signal training_finished 

func refresh_ui() -> void:
	var player = CountryManager.player_country
	if not player: return
	
	if source_object is CountryData.TroopTraining:
		if source_object.days_left <= 0:
			training_finished.emit()
			return 
	_update_button_text()
	_update_clickable_state(player)

func _update_button_text() -> void:
	# 1. Handle Training countdown
	if source_object is CountryData.TroopTraining:
		button.text = "%s (%d Days Left)" % [base_text, source_object.days_left]
		return

	# 2. Handle Ready Troops (The fix)
	if source_object is CountryData.ReadyTroop:
		button.text = base_text # This will now show "Deploy X Divisions"
		return

	# 3. Handle standard buttons (Decisions, etc.)
	var cost_pp = data.get("cost", 0)
	var cost_mp = data.get("manpower", 0)
	var suffix := ""
	
	if cost_pp > 0:
		suffix = " (%d)" % cost_pp
	elif cost_mp > 0:
		suffix = " (%s)" % _format_manpower(cost_mp)
		
	button.text = base_text + suffix

func _update_clickable_state(player: CountryData) -> void:
	# Status/Training rows are always disabled
	if data.get("is_status", false):
		button.disabled = true
		button.modulate = Color.GOLD
		return

	# Check affordability for everything else
	var can_afford = _check_affordability(player)
	button.disabled = !can_afford
	
	# Visual styling based on type
	if data.get("is_deploy", false):
		button.modulate = Color.SPRING_GREEN if can_afford else Color(0.5, 0.5, 0.5)
	else:
		button.modulate = Color.WHITE if can_afford else Color(1, 0.6, 0.6)

# ── Helpers ───────────────────────────────────────────

func _check_affordability(player: CountryData) -> bool:
	var cost_pp = data.get("cost", 0)
	var cost_mp = data.get("manpower", 0)
	return player.political_power >= cost_pp and player.manpower >= cost_mp

func _format_manpower(value: int) -> String:
	return str(value / 1000) + "k" if value >= 1000 else str(value)

func _on_button_pressed() -> void:
	if _callback.is_valid():
		# Only spend PP if the data explicitly has a cost (standard actions)
		var cost = data.get("cost", 0)
		if cost > 0:
			CountryManager.player_country.spend_politicalpower(cost)
		
		_callback.call()
