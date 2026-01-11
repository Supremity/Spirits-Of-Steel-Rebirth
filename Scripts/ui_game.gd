extends CanvasLayer
class_name GameUI

# ── Enums ─────────────────────────────────────────────
enum Context { SELF, WAR, DIPLOMACY }
enum Category { GENERAL, ECONOMY, MILITARY }

# ── Top Bar Nodes ─────────────────────────────────────
@onready var nation_flag: TextureRect = $Topbar/nation_flag
@onready var label_date: Label = $Topbar/MarginContainer2/ColorRect/MarginContainer/label_date
@onready var stats_labels := {
	"pp": $Topbar/MarginContainer/HBoxContainer/PoliticalPower/HBoxContainer/label_politicalpower,
	"manpower": $Topbar/MarginContainer/HBoxContainer/Manpower/HBoxContainer/label_manpower,
	"money": $Topbar/MarginContainer/HBoxContainer/Money/HBoxContainer/label_money,
	"industry": $Topbar/MarginContainer/HBoxContainer/Industry/HBoxContainer/label_industry,
	"stability": $Topbar/MarginContainer/HBoxContainer/Stability/HBoxContainer/label_stability
}

# ── Side Menu Nodes ───────────────────────────────────
@onready var sidemenu: Control = $SidemenuBG
@onready
var sidemenu_flag: TextureRect = $SidemenuBG/Sidemenu/PanelContainer/VBoxContainer/Flag/TextureRect
@onready var label_country_sidemenu: Label = $SidemenuBG/Sidemenu/PanelContainer/VBoxContainer/Label
@onready var label_category: Label = $SidemenuBG/Sidemenu/Panel/label_category
@onready var actions_container: VBoxContainer = $SidemenuBG/Sidemenu/ScrollContainer/ActionsList
@onready var progress_bar: ProgressBar = $Topbar/MarginContainer2/ColorRect/ProgressBar

# Use the class_name of your action scene if available, or load strictly as packed scene
@export var action_scene: PackedScene

# ── Speed Controls ────────────────────────────────────
@onready var plus: Button = $SpeedPanel/GameSpeedControl/PlusPanel/Plus
@onready var minus: Button = $SpeedPanel/GameSpeedControl/MinusPanel/Minus

# ── State Variables ───────────────────────────────────
var player: CountryData = null
var selected_country: CountryData = null

# Animation State
@export var slide_duration: float = 0.2
var is_open := false
var pos_open := Vector2.ZERO
var pos_closed := Vector2.ZERO

# Navigation State
var current_context: Context = Context.SELF
var current_category: Category = Category.GENERAL


func _ready() -> void:
	pos_open = sidemenu.position
	pos_closed = Vector2(pos_open.x - sidemenu.size.x, pos_open.y)
	sidemenu.position = pos_closed

	GameState.game_ui = self

	MapManager.province_clicked.connect(_on_province_clicked)
	MapManager.close_sidemenu.connect(close_menu)

	KeyboardManager.toggle_menu.connect(toggle_menu)

	CountryManager.player_stats_changed.connect(_on_stats_changed)
	CountryManager.player_country_changed.connect(_on_player_change)
	updateProgressBar()

	var clock := GameState.current_world.clock
	clock.hour_passed.connect(_on_time_passed)
	plus.pressed.connect(clock.increase_speed)
	minus.pressed.connect(clock.decrease_speed)
	label_date.text = clock.get_datetime_string()


func _get_menu_actions(context: Context, category: Category) -> Array:
	# Note: I removed placeholders for cleaner reading, add back as needed
	var data = {
		Context.SELF:
		{
			Category.GENERAL:
			[
				{"text": "Decisions", "func": "open_decisions_tree"},
				{"text": "Improve Stability", "cost": 25, "func": "improve_stability"},
				{"text": "Releasables", "func": "_improve_relations"}
			],
			Category.ECONOMY:
			[
				{"text": "Research", "cost": 0, "func": "open_research_tree"},
				{"text": "Build Factory", "cost": 0, "func": "_build_factory"},
				{"text": "Build Port", "cost": 0, "func": "_build_port"},
			],
			Category.MILITARY:
			[
				{"text": "Choose Deployment Province", "func": "_choose_deploy_city"},
				{
					"text": "Training (10k)",
					"func": "_conscript",
					"type": "training",
					"manpower": 10000
				},
				{
					"text": "Training (50k)",
					"func": "_conscript",
					"type": "training",
					"manpower": 50000
				}
			]
		},
		Context.WAR:
		{
			Category.GENERAL:
			[
				{"text": "Propose Ceasefire", "cost": 50, "func": "_propose_peace"},
			],
			Category.MILITARY:
			[
				{"text": "Launch Nuke", "cost": 500, "func": "_launch_nuke"},
			]
		},
		Context.DIPLOMACY:
		{
			Category.GENERAL:
			[
				{"text": "Declare War", "cost": 50, "func": "_declare_war"},
				{"text": "Request Access", "cost": 25, "func": "_request_access"},
				{"text": "Improve Relations", "cost": 15, "func": "_improve_relations"},
				{"text": "Form Alliance", "cost": 80, "func": "_form_alliance"},
			],
			Category.ECONOMY:
			[
				{"text": "Demand Tribute", "cost": 40, "func": "_demand_tribute"},
				{"text": "Trade Deal", "cost": 10, "func": "_trade_deal"},
			]
		}
	}

	if data.has(context) and data[context].has(category):
		return data[context][category]
	return []


func _on_player_change() -> void:
	player = CountryManager.player_country
	_update_flag()
	_on_stats_changed()


func _on_province_clicked(_pid: int, country_name: String) -> void:
	selected_country = CountryManager.get_country(country_name)

	sidemenu_flag.texture = TroopManager.get_flag(country_name)
	label_country_sidemenu.text = country_name.capitalize().replace("_", " ")

	if !GameState.choosing_deploy_city:
		var new_context = Context.DIPLOMACY

		if country_name == player.country_name:
			new_context = Context.SELF
		elif WarManager.is_at_war(player, selected_country):
			new_context = Context.WAR

		open_menu(new_context, Category.GENERAL)


func toggle_menu(context := Context.SELF) -> void:
	if is_open:
		close_menu()
	else:
		selected_country = player
		label_country_sidemenu.text = player.country_name
		sidemenu_flag.texture = nation_flag.texture
		open_menu(context, Category.GENERAL)


func open_menu(context: Context, category: Category) -> void:
	current_context = context
	current_category = category

	_build_action_list()

	if !is_open:
		MusicManager.play_sfx(MusicManager.SFX.OPEN_MENU)
		slide_in()


func _on_tab_changed(new_category_index: int) -> void:
	current_category = new_category_index as Category
	_build_action_list()
	MusicManager.play_sfx(MusicManager.SFX.HOVERED)


func _on_menu_button_button_up(_menu_index: int) -> void:
	current_category = _menu_index as Category
	if _menu_index == Category.ECONOMY:
		MapManager.show_industry_country(player.country_name)
		pass
	else:
		MapManager.set_country_color(player.country_name, Color.TRANSPARENT)
		GameState.industry_building = GameState.INDUSTRY.NOTHING
		MapManager.show_countries_map()
	_build_action_list()


#	print("Switched category to: ", Category.keys()[current_category])


# ── Action List Builder (FIXED) ───────────────────────
func _build_action_list() -> void:
	# Clear existing
	for child in actions_container.get_children():
		child.queue_free()

	label_category.text = Category.keys()[current_category].capitalize()

	# 1. Standard Actions (from Dictionary)
	var actions = _get_menu_actions(current_context, current_category)
	for item in actions:
		var btn = action_scene.instantiate()
		actions_container.add_child(btn)

		# CRITICAL FIX: The function called must accept an argument because we use .bind(item)
		var call_ref = Callable(self, item.func).bind(item)
		btn.setup(item, call_ref)

	# 2. Dynamic Military Actions (Training / Deploy)
	if current_context == Context.SELF and current_category == Category.MILITARY:
		var player_ref = CountryManager.player_country

		# Ongoing Training
		for troop in player_ref.ongoing_training:
			var btn = action_scene.instantiate()
			actions_container.add_child(btn)
			btn.setup_training(troop)
			# We connect the signal emitted by ActionRow when days_left <= 0
			if not btn.training_finished.is_connected(_build_action_list):
				btn.training_finished.connect(_build_action_list)

		# Ready to Deploy
		for troop in player_ref.ready_troops:
			var btn = action_scene.instantiate()
			actions_container.add_child(btn)
			# Callable points to deploy_troop, passing the specific troop object
			var deploy_call = Callable(self, "deploy_troop").bind(troop)
			btn.setup_ready(troop, deploy_call)


# ── UI Updates ────────────────────────────────────────
func _update_ui() -> void:
	_update_flag()
	_on_time_passed()
	_on_stats_changed()


func _on_stats_changed() -> void:
	if !player:
		return
	stats_labels.pp.text = str(floori(player.political_power))
	stats_labels.stability.text = str(round(player.stability * 100)) + "%"
	stats_labels.manpower.text = format_number(player.manpower)
	stats_labels.money.text = "$" + format_number(player.money)


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


func _on_time_passed() -> void:
	label_date.text = GameState.current_world.clock.get_datetime_string()


func updateProgressBar():
	var clock = GameState.current_world.clock
	progress_bar.value = (clock.time_scale / clock.MAX_SPEED) * 100.0
	var bg_style = progress_bar.get_theme_stylebox("background")
	if clock.paused:
		bg_style.border_color = Color.DARK_RED
		label_date.add_theme_color_override("font_color", Color.RED)
	else:
		bg_style.border_color = Color.DARK_CYAN
		label_date.add_theme_color_override("font_color", Color.WHITE)


func _update_flag() -> void:
	if !player:
		return
	var path = "res://assets/flags/%s_flag.png" % player.country_name.to_lower()
	if ResourceLoader.exists(path):
		nation_flag.texture = load(path)


func close_menu() -> void:
	if is_open:
		MusicManager.play_sfx(MusicManager.SFX.CLOSE_MENU)
	slide_out()


func slide_in() -> void:
	if is_open:
		return
	is_open = true
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(sidemenu, "position", pos_open, slide_duration)


func slide_out() -> void:
	if not is_open:
		return
	is_open = false
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(sidemenu, "position", pos_closed, slide_duration)


# ── Action Callbacks ──────────────────────────────────
# IMPORTANT: All callbacks invoked by ActionRow (Standard) must accept
# one argument (the data dictionary) because of the .bind(item) in _build_action_list.


func _choose_deploy_city(_data: Dictionary):
	GameState.choosing_deploy_city = true


func _declare_war(_data: Dictionary):
	WarManager.declare_war(player, selected_country)
	open_menu(Context.WAR, Category.GENERAL)


func _conscript(data: Dictionary):
	if data.has("manpower"):
		var manpower = data.manpower / 10000  # Example math
		CountryManager.player_country.train_troops(manpower, 10, 1000)
	_on_stats_changed()
	_build_action_list()


# Troop argument comes from .bind(troop)
func deploy_troop(troop):
	if player.deploy_pid == -1:
		player.deploy_ready_troop_to_random(troop)
	else:
		player.deploy_ready_troop_to_pid(troop)
	_build_action_list()


func improve_stability(_data: Dictionary):
	CountryManager.player_country.stability += 0.02
	_on_stats_changed()


# These must accept _data to prevent crashing
func _build_factory(_data: Dictionary):
	GameState.industry_building = GameState.INDUSTRY.FACTORY
	#MapManager.show_industry_country(player.country_name)

	pass


func _build_port(_data: Dictionary):
	GameState.industry_building = GameState.INDUSTRY.PORT
	#MapManager.show_industry_country(player.country_name)
	pass


func _request_access(_data: Dictionary):
	pass


func _improve_relations(_data: Dictionary):
	print("Improving relations")


func _propose_peace(_data: Dictionary):
	print("Proposing peace")


func _launch_nuke(_data: Dictionary):
	print("NUKE!")


func _form_alliance(_data: Dictionary):
	print("Alliance formed")


func _demand_tribute(_data: Dictionary):
	print("Pay up!")


func _trade_deal(_data: Dictionary):
	print("Trading...")


func open_research_tree(_data: Dictionary):
	print("Opening Research")


func open_decisions_tree(_data: Dictionary):
	print("Opening Decisions")
