extends Control

@export var save_list: VBoxContainer
@export var line_edit: TextEdit

enum Section {SAVE, AUDIO, GRAPHICS, EXIT}
var settings = {}

@export var tab_container: TabContainer
@export var save_settings: Button
@export var graphics_path: GridContainer

@export_group("Audio")
@export var sfx_slider: HSlider
@export var music_slider: HSlider


@export_group("UI")
@export var ui_upper_slider: HSlider
@export var ui_lower_slider: HSlider
@export var ui_dirt_slider: HSlider

@export_group("Map Effects")
@export var scanlines_slider: HSlider
@export var vignette_lower_slider: HSlider
@export var vignette_upper_slider: HSlider
@export var provinceBorderThicknessSlider: HSlider
@export var province_borders_slider: HSlider
@export var daynight_contrast_slider: HSlider
@export var daynight_smoothness_slider: HSlider
@export var clouds_slider: HSlider
@export var edgeness_slider: HSlider

@export var map_effects_btn: CheckButton
@export var debug_mode_btn: CheckButton


func _initialize_ui_values():
	var s = SettingsManager.settings
	sfx_slider.value = s.sfx_volume
	music_slider.value = s.music_volume
	scanlines_slider.value = s.scanlines
	vignette_lower_slider.value = s.vignette_lower
	vignette_upper_slider.value = s.vignette_upper
	map_effects_btn.button_pressed = s.map_effects
	provinceBorderThicknessSlider.value = s.provinceBorderThickness
	province_borders_slider.value = s.province_borders
	ui_upper_slider.value = s.ui_upper
	ui_lower_slider.value = s.ui_lower
	ui_dirt_slider.value = s.ui_dirt
	daynight_contrast_slider.value = s.daynight_contrast
	daynight_smoothness_slider.value = s.daynight_smoothness
	clouds_slider.value = s.clouds
	edgeness_slider.value = s.clouds_edgeness
	debug_mode_btn.button_pressed = s.debug_mode


func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree():
			_refresh_saves()
			_update_tabs_visibility()

func _ready():
	_refresh_saves()
	_initialize_ui_values()
	_update_tabs_visibility()


func _on_save_settings_pressed() -> void:
	SettingsManager.save_settings()


func _refresh_saves():
	if not save_list: return
	for n in save_list.get_children(): n.queue_free()
	
	var path = "res://saves/"
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)

	var files = DirAccess.get_files_at(path)
	var found_any = false

	print("Settings UI: Scanning for saves in: ", ProjectSettings.globalize_path(path))

	for file_name in files:
		if file_name.ends_with(".json"):
			# Skip empty names or hidden system files
			if file_name == ".json" or file_name.begins_with("."):
				continue
				
			found_any = true
			_add_save_row(save_list, file_name.replace(".json", ""), path + file_name)
	
	if not found_any:
		print("Settings UI: No JSON saves found.")
		var lbl = Label.new()
		lbl.text = "No save files found."
		lbl.modulate = Color(0.5, 0.5, 0.5)
		save_list.add_child(lbl)


func _on_sfx_changed(value: float) -> void:
	SettingsManager.settings.sfx_volume = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()


func _on_music_changed(value: float) -> void:
	SettingsManager.settings.music_volume = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()


func _add_save_row(parent: Node, save_name: String, file_path: String) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	
	# Validate scenario path before allowing load
	var scenario_exists = true
	var scenario_path = ""
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_str = file.get_as_text()
		var data = JSON.parse_string(json_str)
		if data is Dictionary:
			scenario_path = "res://starts/%s/" % data.get("current_start", "ModernDay")
			
			if not ScenarioData.exists(scenario_path):
				scenario_exists = false
	
	var lbl = Label.new()
	lbl.text = save_name
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not scenario_exists:
		lbl.modulate = Color(0.5, 0.5, 0.5)
	hbox.add_child(lbl)

	var load_btn = Button.new()
	load_btn.text = "Load"
	load_btn.custom_minimum_size.x = 80
	
	if not scenario_exists:
		load_btn.disabled = true
		load_btn.tooltip_text = "Scenario file missing: " + scenario_path
	
	load_btn.pressed.connect(func():
		if GameState.current_world:
			GameState.current_world.load_game(save_name)
		else:
			# We are in the Main Menu
			GameState.pending_load_save = save_name
			SceneSwitcher.switch_to(SceneSwitcher.Type.WORLD)
	)
	
	var del_btn = Button.new()
	del_btn.text = "X"
	del_btn.modulate = Color(1, 0.4, 0.4)
	del_btn.pressed.connect(func():
		DirAccess.remove_absolute("res://saves/" + save_name + ".json")
		_refresh_saves()
	)

	hbox.add_child(load_btn)
	hbox.add_child(del_btn)
	parent.add_child(hbox)


func _on_save_game_pressed():
	GameState.current_world.save_game(line_edit.text.strip_edges())
	_refresh_saves()


func _on_scanlines_changed(value: float) -> void:
	SettingsManager.settings.scanlines = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()
	

func _on_vignette_upper_changed(value: float) -> void:
	SettingsManager.settings.vignette_upper = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()


func _on_vignette_lower_changed(value: float) -> void:
	SettingsManager.settings.vignette_lower = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()


func _on_map_effects_pressed() -> void:
	SettingsManager.settings.map_effects = !SettingsManager.settings.map_effects
	graphics_path.visible = !graphics_path.visible
	SettingsManager.apply_settings()
	SettingsManager.save_settings()


func m_OnProvinceBorderThicknessChanged(value: float) -> void:
	SettingsManager.settings.provinceBorderThickness = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()
	
func _on_province_borders_changed(value: float) -> void:
	SettingsManager.settings.province_borders = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()


func _on_ui_upper_changed(value: float) -> void:
	SettingsManager.settings.ui_upper = value
	material.set_shader_parameter("upper", value)
	SettingsManager.save_settings()


func _on_ui_lower_changed(value: float) -> void:
	SettingsManager.settings.ui_lower = value
	material.set_shader_parameter("lower", value)
	SettingsManager.save_settings()


func _on_ui_dirt_changed(value: float) -> void:
	SettingsManager.settings.ui_dirt = value
	material.set_shader_parameter("dirt", value)
	SettingsManager.save_settings()


func _on_daynight_contrast_changed(value: float) -> void:
	SettingsManager.settings.daynight_contrast = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()


func _on_daynight_smoothness_changed(value: float) -> void:
	SettingsManager.settings.daynight_smoothness = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()


func _on_clouds_changed(value: float) -> void:
	SettingsManager.settings.clouds = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()


func _on_edgeness_changed(value: float) -> void:
	SettingsManager.settings.clouds_edgeness = value
	SettingsManager.apply_settings()
	SettingsManager.save_settings()


func _on_debug_mode_pressed() -> void:
	SettingsManager.settings.debug_mode = !SettingsManager.settings.debug_mode
	SettingsManager.apply_settings()
	SettingsManager.save_settings()


func _on_exit_start_pressed() -> void:
	KeyboardManager.settings.visible = false
	SceneSwitcher.switch_to(SceneSwitcher.Type.MENU)




func _on_tab_container_tab_changed(tab: int) -> void:
	save_settings.visible = !(tab == Section.EXIT || tab == Section.SAVE)


func _update_tabs_visibility():
	if tab_container:
		var is_menu = SceneSwitcher._current_type == SceneSwitcher.Type.MENU
		tab_container.set_tab_hidden(Section.EXIT, is_menu)
