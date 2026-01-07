extends Node

# Use the same names as your MapManager functions for clarity
enum MapView { COUNTRIES, POPULATION }
var current_view = MapView.COUNTRIES

signal toggle_menu()

var _debounce := false

func _process(_delta: float) -> void:
	# --- 1. MENU TOGGLE (Esc / Tab / Etc) ---
	if Input.is_action_just_pressed("open_menu"):
		if not _debounce:
			_debounce = true
			toggle_menu.emit()
	
	if Input.is_action_just_released("open_menu"):
		_debounce = false

	# --- 2. MAP MODE CYCLING (Independent of Menu) ---
	if Input.is_action_just_pressed("cycle_map_mode"):
		_cycle_map_mode()
		
	if Input.is_action_just_pressed("pause_game"):
		MainClock.toggle_pause()
	
	if Input.is_action_just_pressed("increase_speed"):
		MainClock.increase_speed()

	if Input.is_action_just_pressed("decrease_speed"):
		MainClock.decrease_speed()


func _cycle_map_mode() -> void:
	match current_view:
		MapView.COUNTRIES:
			current_view = MapView.POPULATION
			print("KeyboardManager: Switching to POPULATION")
			MapManager.show_population_map()
			
		MapView.POPULATION:
			current_view = MapView.COUNTRIES
			print("KeyboardManager: Switching to COUNTRIES")
			MapManager.show_countries_map()
