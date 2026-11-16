extends Node

# Use the same names as your MapManager functions for clarity
var settings: CanvasLayer

func _ready() -> void:
	settings = $/root/Main/SettingsLayer

# NOTE(soi): What was this even for
# func OnWorldLoad() -> void:
# 	settings = get_tree().root.find_child("Settings", true, false)
# 	print(settings)

func _process(_delta: float) -> void:
	if Console.is_visible():
		return
	if Input.is_action_just_pressed("deselect_troops"):
		settings.visible = !settings.visible
		match SceneSwitcher._current_type:
			SceneSwitcher.Type.WORLD:
				if !TroopManager.troop_selection.selected_troops.is_empty():
					TroopManager.troop_selection.deselect_all()
				elif GameState.game_ui.is_open:
					MapManager.close_sidemenu.emit()
				else:
					pass
					# get_tree().root.find_child("Menu", true, false).toggle_menu()


	if SceneSwitcher._current_type != SceneSwitcher.Type.EDITOR:
		if Input.is_action_just_pressed("open_menu"):
			if CountryManager.player_country:
				GameState.game_ui.ChangeContextCategory(
					GameState.game_ui.Context.PLAYER,
					GameState.game_ui.Category.GENERAL,
				)
				GameState.game_ui.selected_country = CountryManager.player_country
				GameState.game_ui.DoUpdateSidemenuVisuals()
			GameState.game_ui.ToggleSideMenu()

	# --- 2. MAP MODE CYCLING (Independent of Menu) ---
	if Input.is_action_just_pressed("cycle_map_mode"):
		_cycle_map_mode(Input.is_action_pressed("Shift"))

	if GameState.current_world && SceneSwitcher._current_type == SceneSwitcher.Type.WORLD:
		var clock := GameState.current_world.clock
		if Input.is_action_just_pressed("pause_game"):
			clock.toggle_pause()

		if Input.is_action_just_pressed("increase_speed"):
			clock.increase_speed()

		if Input.is_action_just_pressed("decrease_speed"):
			clock.decrease_speed()


func _cycle_map_mode(shift: bool) -> void:
	MapManager.CycleMapMode(shift)
