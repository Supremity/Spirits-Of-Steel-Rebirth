extends CanvasLayer
class_name GameUI

# ── Enums ─────────────────────────────────────────────
enum Context {PLAYER, ENEMY, NEUTRAL, PUPPET, ALLY, SELECT}
enum Category {GENERAL, ECONOMY, MILITARY}

@export var settings: PanelContainer

# ── Top Bar Nodes ─────────────────────────────────────
@export_group("Top Bar")
@export var topbar: HBoxContainer
@export var nation_flag: TextureRect
@export var label_date: Label
@export var radios_panel: PanelContainer

@export_subgroup("Stats Labels")
@export var label_pp: Label
@export var label_manpower: Label
@export var label_money: Label
@export var label_industry: Label
@export var label_stability: Label
@export var label_war_support: Label
@export var label_world_tension: Label

var stats_labels := {}
@export var notif_box: HBoxContainer

# ── Speed Controls ────────────────────────────────────
@export_subgroup("Speed Controls")
@export var plus: Button
@export var minus: Button
@export var progress_bar: ProgressBar

# ── Side Menu Nodes ───────────────────────────────────
@export_group("Side Menu")
@export var sidemenu: Control
# NOTE(soi): relations already hv the flag so ehhh
@export var sidemenu_pointer: Sprite2D
@export var play_btn: Button
@export var sidemenu_country_label: Label
@export var sidemenu_context: TabContainer
@export var sidemenu_trooplist: VBoxContainer
@export var sidemenu_buildings: VBoxContainer
@export var sidemenu_leader_portrait: TextureRect
@export var building_dropdown: OptionButton

@export var relations_hbox: HBoxContainer
@export var flag1: TextureRect
@export var flag2: TextureRect
@export var owner1: TextureRect
@export var owner2: TextureRect
@export var relation1: Label
@export var relation2: Label

@export var factions_box: VBoxContainer

@export var faction_prompt: PanelContainer
@export var military_access_label: Label
@export var puppetBadge: TextureRect
@export var warBadge: TextureRect
@export var FALSE_COLOR: Color = Color(0.254, 0.254, 0.254, 1.0)
@export var PUPPET_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var WAR_COLOR: Color = Color(1.0, 0.0, 0.0, 1.0)

@export var accepted_cultures: VBoxContainer
@export var unaccepted_cultures: VBoxContainer
@export var select_player_stat: VBoxContainer

# Use the class_name of your action scene if available, or load strictly as packed scene
@onready var action_scene: PackedScene = preload("res://Scenes/action.tscn")

@export var radio_list: VBoxContainer
@export var now_playing: Label
@export var map_tabs: TabBar

@export var sewage_graph: Line2D
@export var population_graph: Line2D
@export var water_graph: Line2D
@export var power_graph: Line2D


# --- MilitaryExtraPanel ---
@export_group("Military Extra")
@export var military_extra_panel: Control

@export var input_division: SpinBox
@export var button_train: Button
@export var division_type: OptionButton

@export var div_type: Label
@export var div_stats: Label
@export var costs: Label
@export var manpower: Label

@export var troop_container: PanelContainer
@export var troop_list_parent: VBoxContainer


# --- BuildingDesigner ---
@export_group("Building Designer")
@export var building_designer: PanelContainer

# --- Logistics ---
@export_group("Logistics")
@export var logistics: PanelContainer

@export var governmentUI: CanvasLayer


# NOTE(soi): store this somewhere better

# --- State ---
var division_type_selected: String = "infantry"
# ── State Variables ───────────────────────────────────
var selected_country: CountryData = null

# Animation State
@export var slide_duration: float = 0.2
var is_open := false
var pos_open := Vector2.ZERO
var pos_closed := Vector2.ZERO

var economyUpdate: bool = false

# Navigation State
var current_context: Context = Context.SELECT
var current_category: Category = Category.GENERAL


# ── Constants ──────────────────────────────────────────
var action_costs: Dictionary[String, Callable] = {
	"_declare_war": func(player: CountryData, _selected: CountryData): return {
		"cost": 50,
		"can_afford": player.war_support > 0.5
	},
	"_request_access": func(player: CountryData, selected: CountryData): return {
		"cost": 25,
		"can_afford": player.get_relation_with(selected.country_name) > 70
	},
	"_force_puppet": func(player: CountryData, selected: CountryData): return {
		"cost": 150,
		"can_afford": player.gdp > 1000 * selected.gdp
	},
	"_release_puppet": func(_player: CountryData, _selected: CountryData): return {
		"cost": 50,
		"can_afford": true
	},
	"improve_stability": func(player: CountryData, _selected: CountryData): return {
		"cost": int(50 * (1.0 + player.stability)),
		"can_afford": true
	},
	"_improve_relations": func(player: CountryData, _selected: CountryData): return {
		"cost": 40 if player.ideology_name == "liberal" else 50,
		"can_afford": true
	},
	"_propose_peace": func(_player: CountryData, _selected: CountryData): return {
		"cost": 0,
		"can_afford": true
	},
	"_launch_nuke": func(_player: CountryData, _selected: CountryData): return {
		"cost": 250,
		"can_afford": true
	},
	"_form_alliance": func(player: CountryData, selected: CountryData): return {
		"cost": 100,
		"can_afford": player.ideology_name == selected.ideology_name
	},
	"_demand_tribute": func(player: CountryData, selected: CountryData): return {
		"cost": 75,
		"can_afford": player.ideology_name == selected.ideology_name
	},
	"_trade_deal": func(player: CountryData, selected: CountryData): return {
		"cost": 25,
		"can_afford": player.ideology_name == selected.ideology_name
	},
	"open_research_tree": func(_player: CountryData, _selected: CountryData): return {
		"cost": 0,
		"can_afford": true
	},
	"open_decisions_tree": func(_player: CountryData, _selected: CountryData): return {
		"cost": 0,
		"can_afford": true
	},
	"_open_faction": func(_player: CountryData, _selected: CountryData): return {
		"cost": 0,
		"can_afford": true
	},
	"open_manage_country": func(_player: CountryData, _selected: CountryData): return {
		"cost": 0,
		"can_afford": true
	},
	"_build_factory": func(_player: CountryData, _selected: CountryData): return {
		"cost": 0,
		"can_afford": true
	},
	"_build_port": func(_player: CountryData, _selected: CountryData): return {
		"cost": 0,
		"can_afford": true
	},
	"_on_invite_faction_pressed": _get_invite_faction_cost,
	"m_BuildInfrastructure": func(_a_player: CountryData, _a_selected: CountryData): return {
		"cost": 0,
		"can_afford": true
	}
}

func _get_invite_faction_cost(player: CountryData, selected: CountryData) -> Dictionary:
	var member = FactionManager.get_faction_member(player.country_name)
	return {
		"cost": 0,
		"can_afford": (
			player.get_relation_with(selected.country_name) > 120
			and member != null
			and member.status == "Leader"
		)
	}

var all_notifs: Dictionary = {}

# Yeah, not a bad idea.
# Not sure how to impl that though.
# Hmm...
# Ok.
# I guess that could work.
# yeah.
# Then we can have immigrants.
# Hexagons Before Immigrants???
# NOTE(soi): huh?
# NOTE(Soi-Mc Raj of the British but Indian Instead Mc Laddy-Lad): Hexagons are the Deporticons!

func _enter_tree() -> void:
	GameState.game_ui = self


func _ready() -> void:
	set_tooltips_of_tabcontainers()
	
	sidemenu_context.current_tab = Context.SELECT
	for template in DivisionData.TEMPLATES:
		division_type.add_icon_item(
			load("res://starts/%s/assets/division_icons/%s.svg" % [GameState.current_start, template]),
			template.capitalize()
		)
	stats_labels = {
		"pp": label_pp,
		"manpower": label_manpower,
		"money": label_money,
		"industry": label_industry,
		"stability": label_stability,
		"war_support": label_war_support,
		"world_tension": label_world_tension,
	}

	pos_open = sidemenu.position
	pos_closed = Vector2(pos_open.x - sidemenu.custom_minimum_size.x, pos_open.y)
	sidemenu.position = pos_closed

	GameState.game_ui = self

	MapManager.country_clicked.connect(_on_province_clicked)
	MapManager.close_sidemenu.connect(close_menu)

	KeyboardManager.toggle_menu.connect(toggle_menu)

	var world: World = GameState.current_world
	if world and world.clock:
		world.clock.hour_passed.connect(_on_hour_passed)
	
	CountryManager.player_country_changed.connect(_on_player_change)
	if CountryManager.player_country:
		if CountryManager.player_country.ideology_changed.is_connected(_update_flag):
			CountryManager.player_country.ideology_changed.disconnect(_update_flag)
		CountryManager.player_country.ideology_changed.connect(_update_flag)
	
	_update_flag()
	updateProgressBar()
	update_division_menu()
	
	if world and world.clock:
		var clock := world.clock
		clock.hour_passed.connect(_on_time_passed)
		plus.pressed.connect(clock.increase_speed)
		minus.pressed.connect(clock.decrease_speed)
		label_date.text = clock.get_datetime_string()
	else:
		printerr("GameUI: Clock not found in current world!")

	# NOTE(soi): its soiladin time

	const default_music_path = "res://assets/music/"
	const custom_music_path = "res://radios/"
	for radio in MusicManager.music_map[0]:
		var music_path = ""
		print(default_music_path + radio + "/thumbnail.png")
		if ResourceLoader.exists(default_music_path + radio + "/thumbnail.png"):
			music_path = default_music_path
		else:
			music_path = custom_music_path
		var entry = Button.new()
		entry.text = "\n\n\n" + radio
		entry.icon = load(music_path + radio + "/thumbnail.png")
		entry.expand_icon = true
		entry.set_meta("radio_name", radio)
		entry.pressed.connect(
			func():
				if radio in MusicManager.radios:
					MusicManager.radios.erase(radio)
				else:
					MusicManager.radios.append(radio)
				_update_radio_visuals()
				MusicManager.update_interactive_playlists()
				# Restart current track so the player picks up the updated playlist
				MusicManager.current_track_type = -1
				MusicManager.play_music(MusicManager.last_track_type)
				print(MusicManager.radios)
		)
		radio_list.add_child(entry)
		entry.use_parent_material = true
	
	_update_radio_visuals()
	
	var compass = sidemenu_pointer.get_parent()
	compass.mouse_filter = Control.MOUSE_FILTER_PASS
	compass.gui_input.connect(_on_compass_gui_input)


func set_tooltips_of_tabcontainers():
	var tabs := %PlayerTabs as TabContainer
	tabs.set_tab_tooltip(0, "Diplomacy")
	tabs.set_tab_tooltip(1, "Economy")
	tabs.set_tab_tooltip(2, "Military")
	tabs.set_tab_tooltip(3, "Cultures")


func _on_compass_gui_input(event: InputEvent) -> void:
	if not SettingsManager.settings.debug_mode or not selected_country:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_update_ideology_from_mouse(event.position, false)
			else:
				# Export on release
				_update_ideology_from_mouse(event.position, true)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_update_ideology_from_mouse(event.position, false)

func _update_ideology_from_mouse(local_pos: Vector2, do_save: bool) -> void:
	# print(selected_country, GameState.current_scenario_path.is_empty())
	if !selected_country:
		return
		
	var ideology_x = remap(clamp(local_pos.x, 3, 97), 3, 97, -100, 100)
	var ideology_y = remap(clamp(local_pos.y, 3, 97), 3, 97, -100, 100)
	
	selected_country.ideology = Vector2(ideology_x, ideology_y)
	DoUpdateSidemenuVisuals()
	
	if do_save and SettingsManager.settings.debug_mode:
		MapManager.export_scenario_data("user://map_data.json")

func _update_radio_visuals() -> void:
	for child in radio_list.get_children():
		var radio_name: String = child.get_meta("radio_name", "")
		if !radio_name:
			continue
			
		if radio_name in MusicManager.radios:
			child.modulate = Color.WHITE
		else:
			child.modulate = Color(0.5, 0.5, 0.5)

var sidemenuLatch: bool = false

func _update_sidemenu_visuals() -> void:
	if !sidemenuLatch:
		sidemenuLatch = true
		DoUpdateSidemenuVisuals()

func DoUpdateSidemenuVisuals() -> void:

	sidemenu_country_label.text = "%s %s" % [
		selected_country.ideology_name.capitalize(),
		selected_country.display_name.capitalize()
	]

	for entry in factions_box.get_children():
		entry.queue_free()

	for faction in selected_country.factions:
		var faction_entry:Label = Label.new()
		faction_entry.text = faction.capitalize()
		faction_entry.mouse_filter = Control.MOUSE_FILTER_PASS
		faction_entry.tooltip_text = FactionManager.factions[faction].members.map(
		func(x: FactionMember) -> String:
			return "%s: (%s)" % [x.polity.capitalize() , x.status]
		).reduce(
		func(x: String, y: String) -> String:
			return "%s\n%s" % [x, y]
			, ""
		)
		factions_box.add_child(faction_entry)
	
	puppetBadge.modulate = PUPPET_COLOR if selected_country.is_puppet else FALSE_COLOR
	warBadge.modulate = WAR_COLOR if selected_country.is_at_war else FALSE_COLOR

	if GameState.selectingCountry:
		for stat in GameState.game_ui.select_player_stat.get_children(): stat.queue_free()
		for stat: String in [
			"money",
			"gdp",
			"income",
			"political_power",
			"stability",
			"manpower",
			"puppets",
		]:
			var stat_label: Label = Label.new()
			stat_label.text = "%s: %s" % [stat.capitalize(), str(selected_country[stat]).capitalize()]
			select_player_stat.add_child(stat_label)

		nation_flag.texture = TroopManager.get_flag(selected_country.country_name, selected_country.ideology_name)
		# factions.text = selected_country.factions.reduce(func(x, y): return "%s\n%s" %[x, y], "")

		play_btn.text = "Play as %s" % selected_country.country_name.capitalize()

		MapManager.show_countries_map()

	if selected_country.governmentPositions["Leader"]:
		sidemenu_leader_portrait.texture = ImportantFigure.GetPortrait(
			MapManager.significantFigures.get(
				selected_country.governmentPositions["Leader"]
				)
			)
		sidemenu_leader_portrait.tooltip_text = MapManager.significantFigures[selected_country.governmentPositions["Leader"]].GetDisplayString()
	
	sidemenu_pointer.position.x = remap(selected_country.ideology[0], -100, 100, 3, 97)
	sidemenu_pointer.position.y = remap(selected_country.ideology[1], -100, 100, 3, 97)
	
	_update_relations_visuals()
	sidemenuLatch = false


func _on_selected_country_ideology_changed():
	if selected_country:
		_update_sidemenu_visuals()

func _on_player_change() -> void:
	if CountryManager.player_country:
		if CountryManager.player_country.ideology_changed.is_connected(_update_flag):
			CountryManager.player_country.ideology_changed.disconnect(_update_flag)
		CountryManager.player_country.ideology_changed.connect(_update_flag)

	_update_flag()
	update_topbar_stats()
	update_cultures()

func _on_province_clicked(country_name: String) -> void:
	if selected_country && selected_country.ideology_changed.is_connected(_on_selected_country_ideology_changed):
		selected_country.ideology_changed.disconnect(_on_selected_country_ideology_changed)

	selected_country = CountryManager.countries[country_name]
	selected_country.ideology_changed.connect(_on_selected_country_ideology_changed)

	_update_sidemenu_visuals()

	if (
		!GameState.choosing_deploy_city
		|| GameState.industry_building == GameState.IndustryType.DEFAULT
	):
		var new_context = Context.NEUTRAL

		if country_name == CountryManager.player_country.country_name:
			new_context = Context.PLAYER
		elif WarManager.is_at_war(CountryManager.player_country, selected_country):
			new_context = Context.ENEMY
		elif selected_country.country_name in CountryManager.player_country.puppets:
			new_context = Context.PUPPET
		elif FactionManager.in_faction(CountryManager.player_country, selected_country):
			new_context = Context.ALLY
		# elif selected_country.country_name in CountryManager.player_country.puppets:
		# 	new_context = Context.PUPPET

		var allowed = CountryManager.player_country.get_all_allowed_countries()
		relations_hbox.tooltip_text = (
			"Military Access: " + String("Yes" if selected_country.country_name in allowed else "No")
		)

		sidemenu_context.current_tab = new_context
		open_menu(new_context, Category.GENERAL)
		_update_context_actions_visuals()

func toggle_menu(context := Context.PLAYER) -> void:
	if is_open:
		close_menu()
	else:
		selected_country = CountryManager.player_country
		sidemenu_country_label.text = selected_country.country_name
		open_menu(context, Category.GENERAL)
		_update_context_actions_visuals()

var custom_font = preload("res://font/Google_Sans/GoogleSans-VariableFont_GRAD,opsz,wght.ttf")

func open_menu(context: Context, category: Category) -> void:
	if (
		GameState.choosing_deploy_city
		or GameState.industry_building != GameState.IndustryType.DEFAULT
	):
		return
	military_extra_panel.visible = true
	current_context = context
	current_category = category

	if selected_country:
		sidemenu_pointer.position.x = remap(selected_country.ideology[0], -100, 100, 3, 97)
		sidemenu_pointer.position.y = remap(selected_country.ideology[1], -100, 100, 3, 97)
	
	_update_relations_visuals()
	# _build_action_list()

	if !is_open:
		MusicManager.play_sfx(MusicManager.SFX.OPEN_MENU)
		slide_in()
	
	_update_context_actions_visuals()
	update_economy_menu()

func _update_relations_visuals() -> void:
	if current_category != Category.GENERAL:
		return

	var player = CountryManager.player_country
	var target = selected_country

	if player and target and player != target:
		relations_hbox.visible = true
		
		# 1. FAR LEFT:  Target Flag
		flag1.texture = TroopManager.get_flag(target.country_name, target.ideology_name)
		if target.is_puppet:
			owner1.visible = true
			owner1.texture = TroopManager.get_flag(target.owner, target.owner)
		else:
			owner1.visible = false

		
		# 3. CENTER: Dual Opinions
		relation1.text = str(target.get_relation_with(player.country_name))
		relation2.text = str(player.get_relation_with(target.country_name))

		# 5. FAR RIGHT: Player Flag
		flag2.texture = TroopManager.get_flag(player.country_name, player.ideology_name)
		if player.is_puppet:
			owner2.visible = true
			owner2.texture = TroopManager.get_flag(player.owner, player.owner)
		else:
			owner2.visible = false
	else:
		relations_hbox.visible = false

var contextLatch: bool = false
var _actions_list_cache: Array[Dictionary] = []
var _actions_list_cached: bool = false

func _update_context_actions_visuals() -> void:
	if !contextLatch:
		contextLatch = true
		DoUpdateContextActionsVisuals.call_deferred()

func DoUpdateContextActionsVisuals() -> void:
	if not _actions_list_cached:
		_actions_list_cache.clear()
		for context_node in sidemenu_context.get_children():
			var actions_list = context_node.find_child("ActionsList", true, false)
			if actions_list:
				for child in actions_list.get_children():
					if child is Button:
						var method = ""
						for connection in child.pressed.get_connections():
							if connection.callable.get_object() == self:
								method = connection.callable.get_method()
								break
						if method != "" && action_costs.has(method):
							_actions_list_cache.append({
								"btn": child,
								"method": method,
								"base_text": child.text.split(" (")[0]
							})
		_actions_list_cached = true

	if not selected_country:
		contextLatch = false
		return

	# Fast-path rendering
	for data in _actions_list_cache:
		var child: Button = data["btn"]
		var method: String = data["method"]
		if not is_instance_valid(child):
			continue
			
		var cost_data = action_costs[method].call(CountryManager.player_country, selected_country)
		var cost: int = cost_data["cost"]
		child.disabled = not cost_data["can_afford"]
		
		# Update text avoiding split() allocations
		child.text = data["base_text"] + (" (%d PP)" % cost if cost > 0 else "")
		
		# Visual feedback for disabled buttons
		child.modulate = Color(1.0, 0.5, 0.5, 0.7) if child.disabled else Color.WHITE

	contextLatch = false


func _on_tab_changed(new_category_index: int) -> void:
	current_category = new_category_index as Category
	# _build_action_list()
	MusicManager.play_sfx(MusicManager.SFX.HOVERED)

func _on_menu_button_button_up(_menu_index: int) -> void:
	current_category = _menu_index as Category
	if !CountryManager.player_country: return
	if current_context == Context.PLAYER:
		if _menu_index == Category.ECONOMY:
			MapManager.show_industry_country(CountryManager.player_country.country_name)
			print(EconomyManager.building_designs)
			print(EconomyManager.building_designs.get_or_add(CountryManager.player_country.country_name, {}))
			building_dropdown.clear()
			building_dropdown.add_item("Infrastructure")
			for buildingTemplateName: String in EconomyManager.building_designs.get_or_add(CountryManager.player_country.country_name, {}):
				building_dropdown.add_item(buildingTemplateName)
		else:
			MapManager.set_country_color(CountryManager.player_country.country_name, Color.TRANSPARENT)
			GameState.industry_building = GameState.IndustryType.DEFAULT
			MapManager.show_countries_map()

	# _build_action_list()

# NOTE(Z21): Some of the things here are outdated and not used and overall bad way to do things ngl
func _build_trooplist() -> void:
	for child in sidemenu_trooplist.get_children():
		child.queue_free()

	var player = CountryManager.player_country

	for troop in player.ongoing_training:
		var btn = action_scene.instantiate()
		sidemenu_trooplist.add_child(btn)
		btn.setup_training(troop)
		# We connect the signal emitted by ActionRow when days_left <= 0
		if not btn.training_finished.is_connected(_build_trooplist):
			btn.training_finished.connect(_build_trooplist)

	# Ready to Deploy
	for troop in player.ready_troops:
		var btn = action_scene.instantiate()
		sidemenu_trooplist.add_child(btn)
		# Callable points to deploy_troop, passing the specific troop object
		btn.setup_ready(troop, Callable(self , "deploy_troop").bind(troop))

#NOTE(Sockmit2007): Soilad is literally Hitler for this one.

func update_topbar_stats() -> void:
	if !CountryManager.player_country:
		return
	stats_labels.pp.text = str(floori(CountryManager.player_country.political_power))
	stats_labels.stability.text = str(round(CountryManager.player_country.stability * 100)) + "%"
	stats_labels.manpower.text = format_number(CountryManager.player_country.manpower)
	stats_labels.money.text = format_number(CountryManager.player_country.money)
	stats_labels.industry.text = str(CountryManager.player_country.factories_amount)
	stats_labels.war_support.text = str(CountryManager.player_country.war_support * 100) + "%"
	stats_labels.world_tension.text = str(round(MapManager.world_tension * 100)) + "%"
	
	for i in range(population_graph.points.size()-1):
		population_graph.points[i] = population_graph.points[i+1]
		population_graph.points[i].x -= 79

		sewage_graph.points[i] = sewage_graph.points[i+1]
		sewage_graph.points[i].x -= 79

		power_graph.points[i] = power_graph.points[i+1]
		power_graph.points[i].x -= 79

		water_graph.points[i] = water_graph.points[i+1]
		water_graph.points[i].x -= 79

	population_graph.points[-1] = Vector2(316, 236-CountryManager.player_country.total_population * 0.00001)
	sewage_graph.points[-1] = Vector2(316, 236-CountryManager.player_country.total_sewage)
	power_graph.points[-1] = Vector2(316, 236-CountryManager.player_country.total_power)
	water_graph.points[-1] = Vector2(316, 236-CountryManager.player_country.total_water)

	#print(population_graph.points)
	_update_notifications()

func _on_hour_passed() -> void:
	update_topbar_stats()
	update_division_menu()
	if is_open:
		_update_context_actions_visuals()
		update_economy_menu()

func format_number(value: float) -> String:
	var abs_val = abs(value)
	var sign_str = "-" if value < 0 else ""
	if abs_val >= 1_000_000_000:
		return sign_str + "%.2fB" % (abs_val * 0.000000001)
	elif abs_val >= 1_000_000:
		return sign_str + "%.2fM" % (abs_val * 0.000001)
	elif abs_val >= 1_000:
		return sign_str + "%.1fK" % (abs_val * 0.001)
	return sign_str + str(floori(abs_val))

func _on_time_passed() -> void:
	label_date.text = GameState.current_world.clock.get_datetime_string()

func updateProgressBar():
	var clock = GameState.current_world.clock
	progress_bar.value = (clock.time_scale / clock.MAX_SPEED) * 100.0
	var bg_style = progress_bar.get_theme_stylebox("background")
	if clock.paused:
		bg_style.border_color = Color.DARK_RED
		label_date.add_theme_color_override("font_color", Color.GRAY)
	else:
		bg_style.border_color = Color.DARK_CYAN
		label_date.add_theme_color_override("font_color", Color.WHITE)

func _update_flag() -> void:
	if !CountryManager.player_country:
		return
	nation_flag.texture = TroopManager.get_flag(CountryManager.player_country.country_name, CountryManager.player_country.ideology_name)
	#_update_relations_visuals.call_deferred()

func close_menu() -> void:
	if is_open:
		MusicManager.play_sfx(MusicManager.SFX.CLOSE_MENU)
	GameState.reset_industry_building()
	slide_out()
	military_extra_panel.visible = false

func slide_in() -> void:
	if is_open:
		return
	is_open = true
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(sidemenu, "position", pos_open, slide_duration)

func slide_out() -> void:
	if not is_open:
		return
	is_open = false
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN).tween_property(sidemenu, "position", pos_closed, slide_duration)

func _choose_deploy_city():
	GameState.choosing_deploy_city = true

func _declare_war():
	var cost = action_costs["_declare_war"].call(CountryManager.player_country, selected_country)["cost"]
	if CountryManager.player_country.political_power < cost:
		return
	CountryManager.player_country.political_power -= cost
	
	WarManager.declare_war(CountryManager.player_country, selected_country)

	if selected_country.owner:
		WarManager.declare_war(CountryManager.player_country, CountryManager.countries[selected_country.owner])
	for puppet: String in selected_country.puppets:
		WarManager.declare_war(CountryManager.player_country, CountryManager.countries[ puppet ])

	# GameState.game_ui.military_access_label.text = ( "Military Access: " + String("Yes" if selected_country.country_name in CountryManager.player_country.allowedCountries else "No"))

	open_menu(Context.ENEMY, Category.GENERAL)

func _conscript(_data: Dictionary):
	#var manpower = data.manpower * 0.0001
	CountryManager.player_country.train_troops(1, "infantry")
	update_topbar_stats()
	# _build_action_list()

func deploy_troop(troop):
	CountryManager.player_country.deploy_ready_troop(
		troop, CountryManager.player_country.deploy_pid
	)
	_build_trooplist()

func improve_stability():
	var cost = action_costs["improve_stability"].call(CountryManager.player_country, selected_country)["cost"]
	if CountryManager.player_country.political_power < cost:
		return
	CountryManager.player_country.political_power -= cost
	
	CountryManager.player_country.stability += 0.02
	update_topbar_stats()
	_update_context_actions_visuals()

func _on_building_selected(index: int):
	#print()
	match index:
		0:
			GameState.industry_building = GameState.IndustryType.FACTORY
			#MapManager.show_industry_country(player.country_name)
		1:
			GameState.industry_building = GameState.IndustryType.PORT
			#MapManager.show_industry_country(player.country_name)
		2:
			GameState.industry_building = GameState.IndustryType.INFRASTRUCTURE
			#MapManager.show_industry_country(player.country_name)
		_:
			GameState.industry_building = GameState.IndustryType.DEFAULT
	update_economy_menu()

func update_economy_menu() -> void:
	if !economyUpdate:
		DoEconomyMenuUpdate.call_deferred()
		economyUpdate = true

func DoEconomyMenuUpdate() -> void:
	if CountryManager.player_country:
		var playerProvinces: Array = MapManager.country_to_owned_provinces[CountryManager.player_country.country_name]
		for child in sidemenu_buildings.get_children():
			child.queue_free()
		for pid: int in EconomyManager.construction_queue:
			if pid in playerProvinces:
				var entry = ProgressBar.new()
				entry.value = 10 - EconomyManager.construction_queue[pid]["days"]
				entry.max_value = 10
				entry.use_parent_material = true
				var text = Label.new()
				text.text = EconomyManager.construction_queue[pid]["type"]
				text.use_parent_material = true
				entry.add_child(text)
				sidemenu_buildings.add_child(entry)
	economyUpdate = false

func _request_access():
	var cost = action_costs["_request_access"].call(CountryManager.player_country, selected_country)["cost"]
	if CountryManager.player_country.political_power < cost:
		return
	CountryManager.player_country.political_power -= cost
	
	CountryManager.player_country.allowedCountries.append(selected_country.country_name)
	MapManager.allow_pids(CountryManager.player_country, selected_country)
	_update_context_actions_visuals()

func _force_puppet():
	var cost = action_costs["_force_puppet"].call(CountryManager.player_country, selected_country)["cost"]
	if CountryManager.player_country.political_power < cost:
		return
	CountryManager.player_country.political_power -= cost
	
	CountryManager.make_puppet(CountryManager.player_country, selected_country)
	_update_context_actions_visuals()
	close_menu()

func _on_release_puppet_pressed():
	var cost = action_costs["_release_puppet"].call(CountryManager.player_country, selected_country)["cost"]
	if CountryManager.player_country.political_power < cost:
		return
	CountryManager.player_country.political_power -= cost
	
	CountryManager.release_puppet(CountryManager.player_country, selected_country)
	_update_context_actions_visuals()
	close_menu()

func _improve_relations():
	var cost = action_costs["_improve_relations"].call(CountryManager.player_country, selected_country)["cost"]
	if CountryManager.player_country.political_power < cost:
		return
	CountryManager.player_country.political_power -= cost
	
	print("Improving relations")
	_update_context_actions_visuals()

func _propose_peace():
	print("Proposing peace")

func _launch_nuke():
	print("NUKE!")

func _demand_tribute():
	print("Pay up!")

func _trade_deal():
	print("Trading...")

func open_research_tree():
	print("Opening Research")

func open_decisions_tree():
	get_tree().root.find_child("DecisionTreeUI", true, false).open_menu()

func _open_faction():
	faction_prompt.visible = !faction_prompt.visible

func open_manage_country():
	if logistics.visible:
		logistics.close_menu()
	else:
		logistics.open_menu(CountryManager.player_country)

	#GameState.current_world.set_process(false)
	#GameState.current_world.clock.set_process(false)
	#TroopManager.set_process(false)
	#GameState.current_world.find_child("CameraController").set_process(false)


# NOTE(Z21): Everything below is made by a Clanker. I am way too lazy for UI stuff
# NOTE(soi): DAMM YOU Z21

# Theme colors for the military look

# 1. Add this variable at the top with your other @export variables
# NOTE(soi): he did not infact add this at the top
var selected_division_objects: Array[DivisionData] = []
const DIVISION_CARD_SCENE = preload("res://Scenes/DivisionItem.tscn") # Path to your card

func make_troop_container(selected_troops: Array[TroopData]) -> void:
	troop_container.visible = true
	for child in troop_list_parent.get_children():
		child.queue_free()

	for troop: TroopData in selected_troops:
		# --- Group Divisions by Type ---
		# Resulting dict will look like: {"infantry": [div1, div2], "tank": [div3]}
		var groups: Dictionary = {}

		for div in troop.stored_divisions:
			if not groups.has(div.type):
				groups[div.type] = []
			groups[div.type].append(div)

		print(groups)
		# --- Draw One Card Per Type ---
		for type in groups.keys():
			var divisions_of_type: Array = groups[type]

			var card = DIVISION_CARD_SCENE.instantiate()
			troop_list_parent.add_child(card)

			# FIX: Pass 'divisions_of_type' (the Array) as the second argument
			# We no longer pass 'count' here because the card calculates it from the array
			card.setup_grouped(troop, type, divisions_of_type, divisions_of_type[0] in selected_division_objects)

			# Update the signal connection
			if not card.is_connected("clicked", _on_group_clicked):
				# We pass the card node (self) and the array to the handler
				card.clicked.connect(_on_group_clicked)

func _on_group_clicked(card_node: Control, divs_in_group: Array):
	# Check the first div to see if we are selecting or deselecting the group
	var is_already_selected = divs_in_group[0] in selected_division_objects

	for div in divs_in_group:
		if is_already_selected:
			if div in selected_division_objects:
				selected_division_objects.erase(div)
		else:
			if not div in selected_division_objects:
				selected_division_objects.append(div)

	# Toggle the card's visual state
	card_node.is_selected = !is_already_selected
	card_node.update_visuals()

func _on_card_clicked(div: DivisionData, card_node: Control):
	if div in selected_division_objects:
		selected_division_objects.erase(div)
		card_node.is_selected = false
	else:
		selected_division_objects.append(div)
		card_node.is_selected = true

	card_node.update_visuals()
	print("Selected divisions count: ", selected_division_objects.size())

func close_troop_container() -> void:
	troop_container.visible = false

# --- Main Update Logic ---
func update_division_menu():
	var stats = DivisionData.TEMPLATES.get(division_type_selected)
	if !stats:
		return # Safety check

	var player: CountryData = CountryManager.player_country
	if player:
		var max_manpower_divs = player.manpower / stats.manpower if stats.manpower > 0 else 999
		var unit_cost = stats.cost * player.divCostMod
		var max_money_divs = player.money / unit_cost if unit_cost > 0 else 999
		
		input_division.max_value = max(1, floor(min(max_manpower_divs, max_money_divs)))

	var count: int = ceili(input_division.value)

	div_type.text = division_type_selected.capitalize()
	div_stats.text = "%s\n%s\n%s" % [stats.attack, stats.defense, stats.hp]

	var total_manpower: int = stats.manpower * count
	manpower.text = format_number(total_manpower)

	if player:
		costs.text = format_number(stats.cost * count * player.divCostMod)

		# 4. Check Affordability & Update Button State & Visuals
		button_train.disabled = !player || player.manpower < total_manpower

func _on_button_train_troops() -> void:
	if CountryManager.player_country.train_troops(
		max(1, ceili(input_division.value)),
		division_type_selected
	):
		_build_trooplist()
	update_division_menu()

func _on_division_type_button(type: String) -> void:
	print(division_type_selected)
	division_type_selected = type
	print(division_type_selected)
	update_division_menu()

func _on_division_type_selected(index: int) -> void:
	print(division_type_selected)
	print(DivisionData.TEMPLATES)
	division_type_selected = DivisionData.TEMPLATES.keys()[index]
	print(division_type_selected)
	update_division_menu()

func _on_input_division_text_changed(_value: float) -> void:
	update_division_menu()

func _on_music_pressed():
	radios_panel.visible = !radios_panel.visible
	SettingsManager.save_settings()

func _on_create_faction_pressed() -> void:
	FactionManager.create_faction(
		CountryManager.player_country.country_name,
		faction_prompt.get_node("VBoxContainer/HBoxContainer/TextEdit").text,
		faction_prompt.get_node("VBoxContainer/ColorPicker").color
	)
	faction_prompt.get_node("VBoxContainer/HBoxContainer/TextEdit").text = ""
	faction_prompt.get_node("VBoxContainer/ColorPicker").color = Color.WHITE
	faction_prompt.visible = !faction_prompt.visible

func _on_invite_faction_pressed() -> void:
	FactionManager.invite_faction(CountryManager.player_country, selected_country)
	# MapManager.show_faction_map()

func _on_kick_faction_pressed() -> void:
	FactionManager.kick_faction(CountryManager.player_country, selected_country)

func _on_steal_manpower_pressed() -> void:
	if selected_country.total_population > 0:
		CountryManager.player_country.total_population += 1_000
		selected_country.total_population -= 1_000
		CountryManager.player_country.update_manpower_pool()
		selected_country.update_manpower_pool()

func _on_steal_money_pressed() -> void:
	if selected_country.money > 0:
		CountryManager.player_country.money += 1_000
		selected_country.money -= 1_000

func _on_annex_country_pressed() -> void:
	MapManager.annex_country(CountryManager.player_country.country_name, selected_country.country_name)

func _on_call_to_arms_pressed() -> void:
	WarManager.call_to_arms(CountryManager.player_country, selected_country)

func update_cultures() -> void:
	for child in accepted_cultures.get_children():
		child.queue_free()

	for culture in CountryManager.player_country.accepted_cultures:
		var entry = Button.new()
		entry.text = culture
		entry.use_parent_material = true
		accepted_cultures.add_child(entry)

func _on_next_song_pressed() -> void:
	MusicManager.skip_track()

func _on_pause_pressed() -> void:
	MusicManager._toggle_pause()

func add_notif(type: String, tooltip: String):
	if all_notifs.has(type):
		return
	var notif = Button.new()
	notif.icon = load("res://assets/icons/" + type + ".svg")
	notif.expand_icon = true
	notif.use_parent_material = true
	notif.custom_minimum_size = Vector2(30, 0)
	notif.tooltip_text = tooltip
	notif.pressed.connect(func():
		match type:
			"decision":
				open_decisions_tree()
			"plan":
				open_manage_country()
	)
	notif_box.add_child(notif)
	all_notifs[type] = notif

func remove_notif(type: String):
	if all_notifs.has(type):
		var notif = all_notifs[type]
		if is_instance_valid(notif):
			notif.queue_free()
		all_notifs.erase(type)

func _update_notifications():
	#print(all_notifs)
	var player: CountryData = CountryManager.player_country
	if !player:
		return
	
	if player.stability < 0.5:
		add_notif("stability", "Low Stability")
	else:
		remove_notif("stability")
	
	if player.war_support < 0.5:
		add_notif("war_support", "Low War Support")
	else:
		remove_notif("war_support")
	
	if player.political_power < 0:
		add_notif("political_power", "Political Crisis")
	else:
		remove_notif("political_power")
	
	if player.money < 0:
		add_notif("money_icon", "Financial Crisis")
	else:
		remove_notif("money_icon")
	
	if DecisionManager.has_available_decisions(player):
		add_notif("decision", "Decision Available")
	else:
		remove_notif("decision")
	
	if PlansManager.has_available_plans(player):
		add_notif("plan", "Plan Available")
	else:
		remove_notif("plan")

func _on_deploy_all_pressed():
	for troop in sidemenu_trooplist.get_children():
		troop.pressed.emit()

func _on_map_changed(tab: int) -> void:
	match tab:
		KeyboardManager.MapView.COUNTRIES:
			MapManager.show_countries_map()
			print("Map Mode: Countries")

		KeyboardManager.MapView.POPULATION:
			MapManager.show_population_map()
			print("Map Mode: Population")

		KeyboardManager.MapView.INFRASTRUCTURE:
			MapManager.ShowInfrastructureMap()
			print("Map Mode: Infrastructure")
			
		KeyboardManager.MapView.GDP:
			MapManager.show_gdp_map()
			print("Map Mode: GDP")

		KeyboardManager.MapView.ETHNICITY:
			MapManager.show_ethnic_map()
			print("Map Mode: Ethnicity")

		KeyboardManager.MapView.FACTION:
			MapManager.show_faction_map()
			print("Map Mode: Factions")

		KeyboardManager.MapView.RESOURCES:
			MapManager.ShowResourcesMap()
			print("Map Mode: Resources")

		KeyboardManager.MapView.BIOMES:
			MapManager.show_biomes_map()
			print("Map Mode: Biomes")


func _on_building_designer_pressed():
	building_designer.visible = !building_designer.visible


func m_OnGovernmentPressed() -> void:
	governmentUI.OpenMenu(CountryManager.player_country)


func _on_play_as_pressed() -> void:
	CountryManager.set_player_country(selected_country.country_name)
	GameState.selectingCountry = false
	_on_province_clicked(CountryManager.player_country.country_name)
