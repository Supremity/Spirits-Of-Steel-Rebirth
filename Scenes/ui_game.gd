extends CanvasLayer

enum MenuContext { SELF, WAR, DIPLOMACY }

# ── Top Bar Nodes ─────────────────────────────────────
@onready var nation_flag: TextureRect = $Topbar/MarginContainer/HBoxContainer/nation_flag
@onready var label_date: Label = $Topbar/MarginContainer2/ColorRect/MarginContainer/label_date
@onready var label_merge: Label = $Label
@onready var label_politicalpower: Label = $Topbar/MarginContainer/HBoxContainer/label_politicalpower
@onready var label_manpower: Label = $Topbar/MarginContainer/HBoxContainer/label_manpower
@onready var label_money: Label = $Topbar/MarginContainer/HBoxContainer/label_money
@onready var label_industry: Label = $Topbar/MarginContainer/HBoxContainer/label_industry
@onready var label_stability: Label = $Topbar/MarginContainer/HBoxContainer/label_stability

# ── Side Menu Nodes ───────────────────────────────────
@onready var sidemenu: Control = $Sidemenu
@onready var sidemenu_flag: TextureRect = $Sidemenu/TextureRect
@onready var label_country_sidemenu: Label = $Sidemenu/Label
@onready var actions_container: VBoxContainer = $Sidemenu/ScrollContainer/ActionsList

@export var action_scene: PackedScene = preload("res://Scenes/action.tscn")
@export var label_merge_status: Label


var player: CountryData = null

# Animation
@export var slide_duration: float = 0.2
var is_open := false
var pos_open := Vector2.ZERO
var pos_closed := Vector2.ZERO

var selected_country: CountryData = null
# Menu Data
var menus := {
	MenuContext.SELF: [
		{"text": "Decisions",       "cost": 0,  "func": "open_decisions_tree"},
		{"text": "Research",          "cost": 0,  "func": "open_research_tree"},
		{"text": "Releasables", "cost": 0,  "func": "_improve_relations"}
	],
	MenuContext.WAR: [
		{"text": "Propose Ceasefire", "cost": 50, "func": "_propose_peace"},
		{"text": "Propose a Deal", "cost": 50, "func": "_launch_nuke"},
	],
	MenuContext.DIPLOMACY: [
		{"text": "Declare War",       "cost": 25, "func": "_declare_war"},
		{"text": "Improve Relations", "cost": 15, "func": "_improve_relations"},
		{"text": "Form Alliance",     "cost": 80, "func": "_form_alliance"},
		{"text": "Demand Tribute",    "cost": 40, "func": "_demand_tribute"},
	]
}

func _ready() -> void:

	pos_open = sidemenu.position
	pos_closed = Vector2(pos_open.x - sidemenu.size.x, pos_open.y)
	sidemenu.position = pos_closed
	
	await get_tree().process_frame
	
	_connect_signals()


@onready var plus: Button = $GameSpeedControl/Plus
@onready var minus: Button = $GameSpeedControl/Minus
func _connect_signals() -> void:
	if MainClock:
		MainClock.hour_passed.connect(_on_time_passed)
	if MapManager:
		MapManager.province_clicked.connect(_on_province_clicked)
		MapManager.close_sidemenu.connect(close_menu)
	if KeyboardManager:
		KeyboardManager.toggle_menu.connect(toggle_menu)
	if CountryManager:
		CountryManager.player_stats_changed.connect(_on_stats_changed)
		CountryManager.player_country_changed.connect(_on_player_change)
		
		
	plus.pressed.connect(_on_speed_button_pressed.bind(true))
	minus.pressed.connect(_on_speed_button_pressed.bind(false))


func _on_player_change() -> void: 
	player = CountryManager.player_country 
	_update_flag()
	print("UI Player changed to: ", player.country_name) 
	_on_stats_changed()


func _on_province_clicked(pid: int, country: String) -> void:
	selected_country = CountryManager.get_country(country)
	sidemenu_flag.texture = TroopManager.get_flag(country)
	label_country_sidemenu.text = country
	
	if country == player.country_name:
		open_menu(MenuContext.SELF)
	elif WarManager.is_at_war(CountryManager.player_country, CountryManager.get_country(country)):
		open_menu(MenuContext.WAR)
	else:
		open_menu(MenuContext.DIPLOMACY)


func toggle_menu(context := MenuContext.SELF) -> void:
	if is_open:
		close_menu()
	else:
		selected_country = player
		label_country_sidemenu.text = player.country_name
		sidemenu_flag.texture = nation_flag.texture
		open_menu(context)

# ── Menu Control ──────────────────────────────────────
func open_menu(context: MenuContext) -> void:
	build_menu(context)
	if !is_open:
		MusicManager.play_sfx(MusicManager.SFX.OPEN_MENU)
	slide_in()

func close_menu() -> void:
	if is_open:
		MusicManager.play_sfx(MusicManager.SFX.CLOSE_MENU)
	slide_out()
		

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

func build_menu(context: MenuContext) -> void:
	for child in actions_container.get_children():
		child.queue_free()
	
	for item in menus.get(context, []):
		var btn = action_scene.instantiate()
		actions_container.add_child(btn)
		btn.setup(item.text, item.cost, Callable(self, item.func))
	
	_refresh_buttons()

func _refresh_buttons() -> void:
	if not is_open: return
	for btn in actions_container.get_children():
		if btn.has_method("check_affordability"):
			btn.check_affordability(player.political_power)

# ── UI Updates ────────────────────────────────────────
func _update_ui() -> void:
	_update_flag()
	_update_merge_label()
	_on_time_passed()
	_on_stats_changed()

func _on_stats_changed() -> void:
	label_politicalpower.text = str(player.political_power)
	label_manpower.text       = str(player.manpower)
	label_money.text          = str(player.money)
	label_stability.text      = str(player.stability)
	_refresh_buttons()

func _on_time_passed(_h := 0) -> void:
	label_date.text = MainClock.get_datetime_string()

func _update_flag() -> void:
	if !player: return
	var path = "res://assets/flags/%s_flag.png" % player.country_name.to_lower()
	if ResourceLoader.exists(path):
		nation_flag.texture = load(path)

func _update_merge_label() -> void:
	if label_merge_status:
		label_merge_status.text = "A" if TroopManager.AUTO_MERGE else "M"

# ── Action Callbacks ──────────────────────────────────
func _declare_war():
	WarManager.declare_war(CountryManager.player_country, selected_country)
	open_menu(MenuContext.WAR)
func _send_aid():         print("Sending aid!")
func _improve_relations(): print("Improving relations")
func _propose_peace():    print("Proposing peace")
func _launch_nuke():      print("NUKE!")
func _surrender():        print("We surrender...")
func _form_alliance():    print("Alliance formed")
func _demand_tribute():   print("Pay up!")





func _on_speed_button_pressed(increase: bool):
	print (increase)
	if increase: MainClock.increaseSpeed()
	else: MainClock.decreaseSpeed()

func _on_button_mouse_entered() -> void:
	MusicManager.play_sfx(MusicManager.SFX.HOVERED)
