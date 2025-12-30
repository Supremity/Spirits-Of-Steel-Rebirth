extends CanvasLayer

# ── Enums ─────────────────────────────────────────────
enum Context { SELF, WAR, DIPLOMACY }
enum Category { GENERAL, ECONOMY, MILITARY }

# ── Top Bar Nodes ─────────────────────────────────────
@onready var nation_flag: TextureRect = $Topbar/nation_flag
@onready var label_date: Label = $Topbar/MarginContainer2/ColorRect/MarginContainer/label_date
# Grouping stats for easier updates
@onready var stats_labels := {
	"pp": $Topbar/MarginContainer/HBoxContainer/PoliticalPower/HBoxContainer/label_politicalpower,
	"manpower": $Topbar/MarginContainer/HBoxContainer/Manpower/HBoxContainer/label_manpower,
	"money": $Topbar/MarginContainer/HBoxContainer/Money/HBoxContainer/label_money,
	"industry": $Topbar/MarginContainer/HBoxContainer/Industry/HBoxContainer/label_industry,
	"stability": $Topbar/MarginContainer/HBoxContainer/Stability/HBoxContainer/label_stability
}

# ── Side Menu Nodes ───────────────────────────────────
@onready var sidemenu: Control = $SidemenuBG/Sidemenu
@onready var sidemenu_flag: TextureRect = $SidemenuBG/Sidemenu/PanelContainer/VBoxContainer/Flag/TextureRect
@onready var label_country_sidemenu: Label = $SidemenuBG/Sidemenu/PanelContainer/VBoxContainer/Label
@onready var label_category: Label = $SidemenuBG/Sidemenu/Panel/label_category
@onready var actions_container: VBoxContainer = $SidemenuBG/Sidemenu/ScrollContainer/ActionsList

@export var action_scene: PackedScene = preload("res://Scenes/action.tscn")

# ── Speed Controls ────────────────────────────────────
@onready var plus: Button = $SpeedPanel/GameSpeedControl/Plus
@onready var minus: Button = $SpeedPanel/GameSpeedControl/Minus

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
	
	# Wait one frame to ensure singletons are ready
	await get_tree().process_frame
	_connect_signals()

# ── Data Definition ───────────────────────────────────
# Returns the specific list of actions based on Context + Category
func _get_menu_actions(context: Context, category: Category) -> Array:
	# Base structure: Dictionary[Context][Category] = Array of Actions
	var data = {
		Context.SELF: {
			Category.GENERAL: [
				{"text": "Decisions", "func": "open_decisions_tree"},
				{"text": "Improve Stability", "cost": 25, "func": "improve_stability"},

				
				{"text": "Releasables", "func": "_improve_relations"} # Placeholder
			],
			Category.ECONOMY: [
				{"text": "Research", "cost": 0, "func": "open_research_tree"},
				{"text": "Build Industry", "cost": 0, "func": "_build_industry"}
			],
			Category.MILITARY: [
				{"text": "Training", "func": "_conscript", "type": "training", "manpower": 10000},
				{"text": "Training", "func": "_conscript", "type": "training", "manpower": 50000}
			]
		},
		Context.WAR: {
			Category.GENERAL: [
				{"text": "Propose Ceasefire", "cost": 50, "func": "_propose_peace"},
			],
			Category.MILITARY: [
				{"text": "Launch Nuke", "cost": 500, "func": "_launch_nuke"},
			]
		},
		Context.DIPLOMACY: {
			Category.GENERAL: [
				{"text": "Declare War", "cost": 50, "func": "_declare_war"},
				{"text": "Request Access", "cost": 25, "func": "_declare_war"},
				
				{"text": "Improve Relations", "cost": 15, "func": "_improve_relations"},
				{"text": "Form Alliance", "cost": 80, "func": "_form_alliance"},
			],
			Category.ECONOMY: [
				{"text": "Demand Tribute", "cost": 40, "func": "_demand_tribute"},
				{"text": "Trade Deal", "cost": 10, "func": "_trade_deal"},
			]
		}
	}
	
	# Return the list if it exists, otherwise return empty array
	if data.has(context) and data[context].has(category):
		return data[context][category]
	return []

# ── Signal Connections ────────────────────────────────
func _connect_signals() -> void:
	MainClock.hour_passed.connect(_on_time_passed)
	
	MapManager.province_clicked.connect(_on_province_clicked)
	MapManager.close_sidemenu.connect(close_menu)
	
	KeyboardManager.toggle_menu.connect(toggle_menu)
	
	CountryManager.player_stats_changed.connect(_on_stats_changed)
	CountryManager.player_country_changed.connect(_on_player_change)
	
	plus.pressed.connect(func(): MainClock.increaseSpeed())
	minus.pressed.connect(func(): MainClock.decreaseSpeed())

# ── Interaction Logic ─────────────────────────────────
func _on_player_change() -> void: 
	player = CountryManager.player_country 
	_update_flag()
	_on_stats_changed()

func _on_province_clicked(_pid: int, country_name: String) -> void:
	selected_country = CountryManager.get_country(country_name)
	
	# Update Sidebar Header
	sidemenu_flag.texture = TroopManager.get_flag(country_name)
	label_country_sidemenu.text = country_name.capitalize().replace('_', ' ')
	
	# Determine Context
	var new_context = Context.DIPLOMACY
	
	if country_name == player.country_name:
		new_context = Context.SELF
	elif WarManager.is_at_war(player, selected_country):
		new_context = Context.WAR
	
	# Reset to General tab when switching countries
	open_menu(new_context, Category.GENERAL)
	
func _on_menu_button_button_up(_menu_index: int) -> void:
	current_category = _menu_index as Category
	_build_action_list()		
#	print("Switched category to: ", Category.keys()[current_category])

func toggle_menu(context := Context.SELF) -> void:
	if is_open:
		close_menu()
	else:
		selected_country = player
		label_country_sidemenu.text = player.country_name
		sidemenu_flag.texture = nation_flag.texture
		open_menu(context, Category.GENERAL)

# ── Menu Core ─────────────────────────────────────────
# This sets the state and triggers the build
func open_menu(context: Context, category: Category) -> void:
	current_context = context
	current_category = category
	
	_build_action_list()
	
	if !is_open:
		MusicManager.play_sfx(MusicManager.SFX.OPEN_MENU)
		slide_in()

# Connect this to your tab buttons (Diplomacy/Economy/Military icons)
func _on_tab_changed(new_category_index: int) -> void:
	# Convert int index to Enum if necessary, or pass Enum directly
	current_category = new_category_index as Category
	_build_action_list() # Rebuilds list without closing menu
	MusicManager.play_sfx(MusicManager.SFX.HOVERED)

func _build_action_list() -> void:
	# 1. Clear old buttons
	for child in actions_container.get_children():
		child.queue_free()
	
	label_category.text = Category.keys()[current_category].capitalize()



	# 3. GENERATE STANDARD BUTTONS (From your Dictionary)
	var actions = _get_menu_actions(current_context, current_category)
	for item in actions:
		var btn = action_scene.instantiate()
		actions_container.add_child(btn)
		
		# Point the button to the WRAPPER instead of the raw function
		btn.setup(item, Callable(self, item.func).bind(item))

	if current_context == Context.SELF and current_category == Category.MILITARY:
		var player_ref = CountryManager.player_country
			
		# Ongoing Training
		for troop in player_ref.ongoing_training:
			var btn = action_scene.instantiate()
			actions_container.add_child(btn)
			btn.setup_training(troop)
			btn.training_finished.connect(_build_action_list)
		# Ready to Deploy
		for troop in player_ref.ready_troops:
			var btn = action_scene.instantiate()
			var deploy_call = Callable(self, "deploy_troop").bind(troop)
			btn.setup_ready(troop, deploy_call)
			actions_container.add_child(btn)
			
	await get_tree().process_frame # Fixes buttons appearing disabled sometimes


		
func close_menu() -> void:
	if is_open:
		MusicManager.play_sfx(MusicManager.SFX.CLOSE_MENU)
	slide_out()

# ── Animations ────────────────────────────────────────
func slide_in() -> void:
	if is_open: return
	is_open = true
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(sidemenu, "position", pos_open, slide_duration)

func slide_out() -> void:
	if not is_open: return
	is_open = false
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(sidemenu, "position", pos_closed, slide_duration)

# ── UI Updates ────────────────────────────────────────
func _update_ui() -> void:
	_update_flag()
	_on_time_passed()
	_on_stats_changed()

func _on_stats_changed() -> void:
	if !player: return
	stats_labels.pp.text = str(player.political_power)
	stats_labels.manpower.text = str(player.manpower)
	stats_labels.money.text = str(player.money)
	#stats_labels.industry.text = str(player.com) # Added missing label
	stats_labels.stability.text = str(round(player.stability * 100)) + "%"

func _on_time_passed() -> void:
	label_date.text = MainClock.get_datetime_string()

func _update_flag() -> void:
	if !player: return
	var path = "res://assets/flags/%s_flag.png" % player.country_name.to_lower()
	if ResourceLoader.exists(path):
		nation_flag.texture = load(path)

# ── Action Callbacks ──────────────────────────────────
func _declare_war():
	WarManager.declare_war(player, selected_country)
	open_menu(Context.WAR, Category.GENERAL)

func _conscript(data: Dictionary):
	if data.has("manpower"):
		var manpower = data.manpower / 10000
		CountryManager.player_country.train_troops(manpower, 10, 1000)
	_on_stats_changed()
	_build_action_list()
	
func deploy_troop(troop):
	player.deploy_ready_troop_to_random(troop)
	_build_action_list()
	pass

func improve_stability():
	CountryManager.player_country.stability += 0.02
	_on_stats_changed()

func _improve_relations(): print("Improving relations")
func _propose_peace():     print("Proposing peace")
func _launch_nuke():       print("NUKE!")
func _form_alliance():     print("Alliance formed")
func _demand_tribute():    print("Pay up!")
func _trade_deal():        print("Trading...")
func _build_industry():    print("Building...")
func open_research_tree():  print("Opening Research")
