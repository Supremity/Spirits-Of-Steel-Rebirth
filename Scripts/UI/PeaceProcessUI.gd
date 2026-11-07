extends CanvasLayer

enum MouseMode {
	ANNEX,
	PUPPET,
	ANNEX_NEW,
}

@export var sidebar_panel: PanelContainer
@export var summary_label: Label
@export var stats_label: Label
@export var loser_label: Label

@export var newDropdown: OptionButton
@export var newName: LineEdit
@export var newOwner: OptionButton
@export var newColor: ColorPickerButton

@export var subsumeButton: Button

var mouseMode: MouseMode = MouseMode.ANNEX

var creating: Array[Dictionary] = []
var winners: Array[CountryData] = []
var creating_selected: int = 0
var current_selected: CountryData
var current_loser: CountryData
var provinces_to_take: Dictionary = {} # PID -> CountryData
var provincesCreating: Dictionary = {} # PID -> String (For the newly created)
var creatingProvinces: Dictionary[String, PackedInt32Array] = {} 
var ownersCreating: Dictionary[String, CountryData] = {} 
var hovered_pid: int = -1
var puppeting: Dictionary[CountryData, CountryData] = {}
var puppetang: Dictionary[CountryData, CountryData] = {}
@export var participant_selector: OptionButton
var provinces_discussing: Array = []

# Color Palette
const COLOR_BG = Color(0.1, 0.1, 0.12, 0.98)
const COLOR_GOLD = Color(0.85, 0.65, 0.2)
const COLOR_SELECT = Color(0.0, 1.0, 0.8) # Cyan/Teal for treaty selection
const COLOR_DANGER = Color(0.7, 0.2, 0.2)

func _ready() -> void:
	self.hide()

func _setup_missing_ui_elements():
	# Find the main VBoxContainer in the sidebar
	var main_vbox = sidebar_panel.get_node("VBoxContainer")
	if not main_vbox:
		return

	# Add Beneficiary Selector label and OptionButton to the existing sidebar
	var beneficiary_label = Label.new()
	beneficiary_label.text = "SELECT BENEFICIARY:"
	beneficiary_label.add_theme_font_size_override("font_size", 14)
	
	# Insert before the button container (which is usually the last child)
	var button_container = main_vbox.get_child(main_vbox.get_child_count() - 1)
	main_vbox.add_child(beneficiary_label)
	main_vbox.move_child(beneficiary_label, button_container.get_index())
	
	# winner_selector = OptionButton.new()
	# winner_selector.item_selected.connect(_on_winner_selected)
	# main_vbox.add_child(winner_selector)
	# main_vbox.move_child(winner_selector, button_container.get_index())

func _unhandled_input(event: InputEvent) -> void:
	if not self.visible:
		return

	# 1. Ignore input if clicking on the sidebar itself
	if get_viewport().get_mouse_position().x < sidebar_panel.size.x:
		return

	# 2. Convert Screen position to Map/World position
	# We use the World's camera to get the correct global coordinates
	var world = GameState.current_world
	if not world:
		return

	var map_pos = world.get_global_mouse_position()

	# 3. Handle Hover (Motion) and Click (Button) separately
	if event is InputEventMouseMotion:
		_process_hover(map_pos)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_process_click(map_pos)

func _process_hover(map_pos: Vector2):
	# 1. Get the PID using your radius logic
	var pid = get_province_with_radius(map_pos, GameState.current_world.map_sprite, 5)

	if pid != hovered_pid:
		# 2. Reset the visual of the PREVIOUS hovered province
		if hovered_pid > 1:
			_reset_province_visual(hovered_pid)

		hovered_pid = pid

		# 3. Apply NEW hover visual (if it's a valid land province belonging to the loser)
		if hovered_pid > 1:
			var province = MapManager.province_objects.get(hovered_pid)
			if province and province.country == current_loser.country_name:
				_update_map_visual(hovered_pid, Color(1.5, 1.5, 1.5), CountryManager.GetCountryColor(province.country))
				Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
			else:
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		else:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _process_click(map_pos: Vector2):
	var pid = get_province_with_radius(map_pos, GameState.current_world.map_sprite, 5)
	if pid <= 1:
		return
	
	if Input.is_key_pressed(KEY_CTRL):
		current_selected = CountryManager.countries[MapManager.province_objects[pid].country]
	else:
		match mouseMode:
			MouseMode.ANNEX:
				if pid not in provinces_discussing:
					return
				
				if provincesCreating.has(pid):
					creatingProvinces[provincesCreating[pid]].erase(pid)
					provincesCreating.erase(pid)
					
					
				if provinces_to_take.has(pid) && provinces_to_take[pid] == current_selected:
					provinces_to_take.erase(pid)
					_reset_province_visual(pid)
				else:
					provinces_to_take[pid] = current_selected
					_update_map_visual(pid, current_selected.country_color.lightened(0.2), CountryManager.GetCountryColor(MapManager.province_objects[pid].country))
			MouseMode.PUPPET:
				if pid not in provinces_discussing:
					return
				
				var count: CountryData = CountryManager.countries[MapManager.province_objects[pid].country]
				if count != current_selected:
					if count in puppeting && puppeting[count] == current_selected:
						puppeting.erase(count)
						for province: int in provinces_discussing:
							if !provinces_to_take.has(province) && !provincesCreating.has(province):
								_reset_province_visual(province)
					else:
						puppeting[count] = current_selected
						for province: int in provinces_discussing:
							if !provinces_to_take.has(province) && !provincesCreating.has(province):
								_update_map_visual(province, CountryManager.GetCountryColor(MapManager.province_objects[province].country) * 0.8 + puppeting[count].country_color * 0.2, CountryManager.GetCountryColor(MapManager.province_objects[province].country))
			MouseMode.ANNEX_NEW:
				if pid not in provinces_discussing:
					return
				
				if provinces_to_take.has(pid):
					provinces_to_take.erase(pid)
					
				if provincesCreating.has(pid) && provincesCreating[pid] == creating[creating_selected].name:
					provincesCreating.erase(pid)
					creatingProvinces.get_or_add(creating[creating_selected].name, []).push_back(pid)
					_reset_province_visual(pid)
				else:
					if provincesCreating.has(pid):
						creatingProvinces[provincesCreating[pid]].erase(pid)
					provincesCreating[pid] = creating[creating_selected].name
					creatingProvinces.get_or_add(creating[creating_selected].name, []).push_back(pid)
					print(Color.from_string(creating[creating_selected].color, Color.DEEP_SKY_BLUE).lightened(0.2).to_html())
					_update_map_visual(pid, Color.from_string(creating[creating_selected].color, Color.DEEP_SKY_BLUE).lightened(0.2), CountryManager.GetCountryColor(MapManager.province_objects[pid].country))

	_update_summary()

func m_OnDropdownSelected(a_selected: int) -> void:
	if a_selected == 0:
		creating_selected = newDropdown.item_count - 1
		newDropdown.add_item("...")
		newName.text = "..."
		newOwner.select(0)
		newColor.color = Color(randf(), randf(), randf())
		creating.append(
			{
				"name": "...",
				"color": "#"+newColor.color.to_html(false).to_upper(),
				"money": 0,
				"ideology": [0, 0],
				"political_power": 100,
				"stability": 0.5,
				"war_support": 0.5,
				"puppets": [],
				"accepted_cultures": [],
				"hostedGovernments": [],
				"figures": [],
			}
		)
	else:
		creating_selected = a_selected - 1
		newName.text = creating[creating_selected].name
		if creating[creating_selected].name not in ownersCreating:
			newOwner.select(0)
		else:
			for i in range(newOwner.item_count):
				if newOwner.get_item_text(i) == ownersCreating[creating[creating_selected].name].country_name:
					newOwner.select(i)
					break
		newColor.color = Color.from_string(creating[creating_selected].color, Color.DEEP_SKY_BLUE)

func m_OnNameNewSubmitted(a_value: String) -> void:
	if creating_selected < 0:
		return
	if creating[creating_selected].name in creatingProvinces:
		creatingProvinces[a_value] = creatingProvinces[creating[creating_selected].name].duplicate()
	for pid: int in creatingProvinces.get(creating[creating_selected].name, []):
		provincesCreating[pid] = a_value
	creatingProvinces.erase(creating[creating_selected].name)
	print("%d - %d" % [creating_selected, creating_selected + 1])
	newDropdown.set_item_text(creating_selected + 1, a_value)
	if creating[creating_selected].name in ownersCreating:
		ownersCreating[a_value] = ownersCreating[creating[creating_selected].name]
		ownersCreating.erase(creating[creating_selected].name)
	creating[creating_selected].name = a_value

func m_OnColorNewSubmitted(a_value: Color) -> void:
	creating[creating_selected].color = "#"+a_value.to_html(false).to_upper()
	for pid: int in creatingProvinces.get(creating[creating_selected].name, []):
		_update_map_visual(pid, a_value.lightened(0.2), CountryManager.GetCountryColor(MapManager.province_objects[pid].country))

func m_OnOwnerNewSelected(a_index: int) -> void:
	if a_index == 0:
		ownersCreating.erase(creating[creating_selected].name)
	else:
		ownersCreating[creating[creating_selected].name] = current_loser if a_index == newOwner.item_count else winners[a_index - 1]

func m_OnAnnexNewPressed() -> void:
	mouseMode = MouseMode.ANNEX_NEW
	subsumeButton.disabled = false
	
func m_OnDeleteNewPressed() -> void:
	for pid: int in creatingProvinces.get(creating[creating_selected].name, []):
		provincesCreating.erase(pid)
	creatingProvinces.erase(creating[creating_selected].name)
	newDropdown.remove_item(creating_selected + 1)
	
	creating.remove_at(creating_selected)
	creating_selected = -1

func _on_annex_all_pressed():
	mouseMode = MouseMode.ANNEX
	subsumeButton.disabled = false

func _on_winner_selected(index: int):
	current_selected = winners[index] if index < winners.size() else current_loser
	mouseMode = MouseMode.ANNEX

func _on_puppet_pressed():
	mouseMode = MouseMode.PUPPET
	subsumeButton.disabled = true
	#_update_summary()

func _on_clear_selection_pressed():
	var pids = provinces_to_take.keys()
	provinces_to_take.clear()
	for pid in pids:
		_reset_province_visual_immediate(pid)
	_update_summary()

func _reset_province_visual_immediate(pid: int):
	_update_map_visual(pid, CountryManager.GetCountryColor(MapManager.province_objects[pid].GetFunctionalOwner(), Color.WHITE), CountryManager.GetCountryColor(MapManager.province_objects[pid].country, Color.WHITE))

func m_AnnexAll():
	match mouseMode:
		MouseMode.ANNEX:
			for province: int in provinces_discussing:
				if !provinces_to_take.has(province) && !provincesCreating.has(province):
					provinces_to_take[province] = current_selected
					_update_map_visual(province, current_selected.country_color.lightened(0.2), CountryManager.GetCountryColor(MapManager.province_objects[province].country))
		MouseMode.ANNEX_NEW:
			for province: int in provinces_discussing:
				if !provinces_to_take.has(province) && !provincesCreating.has(province):
					provincesCreating[province] = creating[creating_selected].name
					creatingProvinces.get_or_add(creating[creating_selected].name, []).push_back(province)
					_update_map_visual(province, Color.from_string(creating[creating_selected].color, Color.DEEP_SKY_BLUE).lightened(0.2), CountryManager.GetCountryColor(MapManager.province_objects[province].country))

	_update_summary()

# --- Logic & Integration ---

func open_menu(p_winners: Array[CountryData], p_loser: CountryData):
	mouseMode = MouseMode.ANNEX
	subsumeButton.disabled = false
	self.show()
	winners = p_winners
	current_loser = p_loser
	provinces_to_take.clear()
	provinces_discussing = MapManager.country_to_owned_provinces[p_loser.country_name].duplicate()
	puppeting = {}
	creating.clear()
	creatingProvinces.clear()
	provincesCreating.clear()
	creating_selected = -1
	ownersCreating.clear()
	
	newName.text = ""
	
	# Setup Winner Selector
	newDropdown.clear()
	newDropdown.add_item("New")
	newOwner.clear()
	newOwner.add_item("None")
	participant_selector.clear()
	var player_index = -1
	for i in range(winners.size()):
		newOwner.add_item(winners[i].country_name)
		participant_selector.add_item(winners[i].country_name)
		if winners[i].is_player:
			player_index = i
	newOwner.add_item(p_loser.country_name)
	participant_selector.add_item(p_loser.country_name)
	
	if player_index != -1:
		participant_selector.selected = player_index
		current_selected = winners[player_index]
	else:
		participant_selector.selected = 0
		current_selected = winners[0]

	# NOTE(Sockmit2007): What is this?
	# AUTO-ANNEX CLAIMS
	#for pid in MapManager.province_objects.keys():
	#	var province = MapManager.province_objects[pid]
	#	if province.country == current_loser.country_name:
	#		# Check each winner for a claim
	#		for w in winners:
	#			if province.claims.has(w.country_name):
	#				provinces_to_take[pid] = w
	#				var color = w.country_color.lightened(0.2)
	#				var base_color = CountryManager.GetCountryColor(province.country)
	#				_update_map_visual(pid, color, base_color)
	#				break # First winner who claims it gets it in auto-assign

	var game_ui = get_tree().root.find_child("ui_game", true, false)
	if game_ui:
		game_ui.visible = false
	GameState.current_world.clock.pause()
	loser_label.text = "Negotations: %s" % p_loser.country_name
	GameState.in_peace_process = true
	_update_summary()

func _update_summary():
	summary_label.text = "Provinces Selected: %d" % provinces_to_take.size()

	# Calculate percentage for flavor
	var total_loser_provinces = 0
	for p in MapManager.province_objects.values():
		if p.country == current_loser.country_name:
			total_loser_provinces += 1

	if total_loser_provinces > 0:
		stats_label.text = "Total Country Loss: %d%%" % int((float(provinces_to_take.size()) / total_loser_provinces) * 100)

func _on_confirm_pressed():
	for pid in provinces_to_take:
		var recipient = provinces_to_take[pid]
		MapManager.TransferOwnership(pid, recipient.country_name)
	
	for puppet in puppeting:
		# Use the first winner (usually the war leader/player) to puppet
		CountryManager.make_puppet(puppeting[puppet], puppet)
	
	for country: Dictionary in creating:
		if country.name in creatingProvinces:
			MapManager.InstantiateCountryFromProvinces(country, creatingProvinces[country.name])
	
	for puppet: String in ownersCreating:
		if puppet in CountryManager.countries:
			CountryManager.make_puppet(ownersCreating[puppet], CountryManager.countries[puppet])
	
	var game_ui = get_tree().root.find_child("ui_game", true, false)
	if game_ui:
		game_ui.visible = true
	GameState.in_peace_process = false
	GameState.current_world.clock.resume()

	self.hide()

func force_close():
	self.set_process(false)
	self.set_physics_process(false)
	self.hide()
	
	# Clear selections & state
	provinces_to_take.clear()
	winners.clear()
	current_loser = null
	puppeting = {}
	hovered_pid = -1
	
	# Reset global flags
	GameState.in_peace_process = false
	
	# Restore standard UI if possible
	var game_ui = get_tree().root.find_child("ui_game", true, false)
	if game_ui:
		game_ui.visible = true
	
	# Essential to resume clock if we were paused by the peace menu
	if GameState.current_world:
		GameState.current_world.clock.resume()

# Your existing logic function
func get_province_with_radius(global_pos: Vector2, map_sprite: Sprite2D, radius: int) -> int:
	# This uses the code logic you already have in MapManager
	return MapManager.get_province_with_radius(global_pos, map_sprite, radius)

func _update_map_visual(pid: int, color: Color, secondary_color: Color):
	# We call MapManager's lookup update to refresh the shader texture
	MapManager.SetProvinceColors(pid, color, secondary_color)

func _reset_province_visual(pid: int):
	# If it's currently selected, keep the selected color
	if provinces_to_take.has(pid):
		_update_map_visual(pid, provinces_to_take[pid].country_color.lightened(0.2), CountryManager.GetCountryColor(MapManager.province_objects[pid].country))
	elif provincesCreating.has(pid):
		_update_map_visual(pid, Color.from_string(creating[creating.find_custom(func (pr): return pr.name == provincesCreating[pid])].color, Color.DEEP_SKY_BLUE).lightened(0.2), CountryManager.GetCountryColor(MapManager.province_objects[pid].country))
	else:
		# Otherwise, revert to the original country color (legal owner)
		var province = MapManager.province_objects.get(pid)
		if province and province.country != "Sea":
			_update_map_visual(pid, CountryManager.GetCountryColor(province.GetFunctionalOwner()), CountryManager.GetCountryColor(province.country))


func m_OnLineEditFocusExited() -> void:
	m_OnNameNewSubmitted(newName.text)
