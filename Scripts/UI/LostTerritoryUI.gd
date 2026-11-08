extends CanvasLayer

var sidebar_panel: PanelContainer
var summary_label: Label
var stats_label: Label
var loser_label: Label
@export var hosts: VBoxContainer
@export var template: PanelContainer

# Color Palette
const COLOR_BG = Color(0.1, 0.1, 0.12, 0.98)
const COLOR_GOLD = Color(0.85, 0.65, 0.2)
const COLOR_SELECT = Color(0.0, 1.0, 0.8)  # Cyan/Teal for treaty selection
const COLOR_DANGER = Color(0.7, 0.2, 0.2)


func _ready() -> void:
	#_setup_ui_elements()
	self.hide()


func _input(_event: InputEvent) -> void:
	if not self.visible:
		return


func _setup_ui_elements():
	# Sidebar Setup
	sidebar_panel = PanelContainer.new()
	sidebar_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sidebar_panel.custom_minimum_size.x = get_viewport().get_visible_rect().size.x * 0.22  # Slightly slimmer

	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.border_width_right = 4
	style.border_color = COLOR_GOLD
	style.shadow_size = 10
	sidebar_panel.add_theme_stylebox_override("panel", style)
	add_child(sidebar_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_bottom", 50)
	sidebar_panel.add_child(margin)

	var v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 25)
	margin.add_child(v_box)

	# --- Header ---
	var title = Label.new()
	title.text = "END OF A NATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	v_box.add_child(title)

	var h_sep = ColorRect.new()
	h_sep.custom_minimum_size.y = 2
	h_sep.color = COLOR_GOLD
	v_box.add_child(h_sep)

	loser_label = Label.new()
	loser_label.add_theme_font_size_override("font_size", 18)
	loser_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v_box.add_child(loser_label)

	# --- Buttons ---
	v_box.add_spacer(false)  # Pushes buttons to bottom

	var governmentInExile_btn = _create_styled_button("GOVERNMENT IN EXILE", Color(0.3, 0.5, 0.3))
	#governmentInExile_btn.pressed.connect(m_OnExilePressed)
	v_box.add_child(governmentInExile_btn)
	
	var dissolution_btn = _create_styled_button("DISSOLVE THE GOVERNMENT", COLOR_GOLD)
	dissolution_btn.pressed.connect(m_OnDissolvePressed)
	v_box.add_child(dissolution_btn)


func _create_styled_button(btn_text: String, accent_color: Color) -> Button:
	var btn = Button.new()
	btn.text = btn_text
	btn.custom_minimum_size.y = 45
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = accent_color * 0.6
	style_normal.border_width_bottom = 4
	style_normal.border_color = accent_color * 0.4
	style_normal.set_corner_radius_all(3)

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = accent_color * 0.8

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_color_override("font_color", Color.WHITE)
	return btn

func m_ExiledHost(a_host: CountryData, a_hosted: CountryData) -> void:
	CountryManager.MakeHost(a_host, a_hosted)
	
	var game_ui = get_tree().root.find_child("ui_game", true, false)
	if game_ui:
		game_ui.visible = true
	GameState.lostTerritory = false
	GameState.current_world.clock.resume()

	self.hide()

func m_CreateHostNationButton(a_nation: CountryData, a_player: CountryData) -> PanelContainer:
	var btn = template.duplicate()
	var button: Button = btn.get_child(0).get_child(1) as Button
	btn.get_child(0).get_child(0).texture = TroopManager.get_flag(a_nation.country_name, a_nation.ideology_name)
	button.text = a_nation.country_name.capitalize()
	button.pressed.connect(func(): m_ExiledHost(a_nation, a_player))
	btn.get_child(0).get_child(2).get_child(0).text = str(a_player.get_relation_with(a_nation.country_name))
	btn.visible = true
	return btn

# --- Logic & Integration ---


func OpenMenu(player: CountryData):
	for child in hosts.get_children().duplicate():
		hosts.remove_child(child)
	for country in player.relations.keys():
		if player.get_relation_with(country) >= 175:
			hosts.add_child(m_CreateHostNationButton(CountryManager.countries[country], player))
	self.show()
	var game_ui = get_tree().root.find_child("ui_game", true, false)
	if game_ui:
		game_ui.visible = false
	GameState.current_world.clock.pause()
	GameState.lostTerritory = true

func m_OnDissolvePressed():
	if CountryManager.player_country.is_puppet:
		CountryManager.release_puppet(CountryManager.countries[CountryManager.player_country.owner], CountryManager.player_country)
	
	for puppet in CountryManager.player_country.puppets:
		print("Deleting Puppet: %s" % puppet)
		CountryManager.release_puppet(CountryManager.player_country, CountryManager.countries[puppet])
	
	CountryManager.countryNames.erase(CountryManager.player_country.country_name)
	CountryManager.countries.erase(CountryManager.player_country.country_name)
	
	var game_ui = get_tree().root.find_child("ui_game", true, false)
	if game_ui:
		game_ui.visible = true
	GameState.lostTerritory = false
	GameState.current_world.clock.resume()
	
	CountryManager.set_player_country(CountryManager.countries.keys().pick_random())
	
	self.hide()
