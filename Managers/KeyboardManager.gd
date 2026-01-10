extends Node

# Use the same names as your MapManager functions for clarity
enum MapView { COUNTRIES, POPULATION, GDP }
var current_view = MapView.COUNTRIES

signal toggle_menu

var _debounce := false


func _process(_delta: float) -> void:
	if Console.is_visible():
		return
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

	if GameState.current_world:
		var clock := GameState.current_world.clock
		if Input.is_action_just_pressed("pause_game"):
			clock.toggle_pause()

		if Input.is_action_just_pressed("increase_speed"):
			clock.increase_speed()

		if Input.is_action_just_pressed("decrease_speed"):
			clock.decrease_speed()


func _cycle_map_mode() -> void:
	match current_view:
		MapView.COUNTRIES:
			current_view = MapView.POPULATION
			MapManager.show_population_map()
			print("Map Mode: Population")

		MapView.POPULATION:
			current_view = MapView.GDP
			MapManager.show_gdp_map()
			print("Map Mode: GDP")

		MapView.GDP:
			current_view = MapView.COUNTRIES
			MapManager.show_countries_map()
			print("Map Mode: Countries")
