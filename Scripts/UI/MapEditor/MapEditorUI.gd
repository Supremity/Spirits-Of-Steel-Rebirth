extends CanvasLayer

@export var map_sprite: Sprite2D

var selectedCountry: String = ""
var selectedFaction: String = ""
var selectedBiome: String = ""
var selectedResource: String = ""
var selected_pid: int = -1
var hovered_pid: int = -1
var original_pid_color: Color

var multiSelectPID: PackedInt32Array = []
var dragging: Drag = Drag.NONE

enum Tool {
	NONE            = 0,
	PAINT_PRIMARY   = 1,
	PAINT_SECONDARY = 2,
	PAINT_TERTIARY  = 3,
	MULTI_SELECT    = 4,
}

enum Mode {
	PROVINCE = 0,
	FACTION  = 1,
	POLITY   = 2,
	BIOME    = 3,
	RESOURCE = 4,
}

enum Drag {
	NONE  = 0,
	LEFT  = 1,
	RIGHT = 2,
}

var currentTool: Tool = Tool.NONE
var currentMode: Mode = Mode.PROVINCE

@export var leftSidebar: TabContainer

# UI References (Ensure these match your .tscn node names)
@export_category("Province")
@export var status_label: Label
@export var provinceName: LineEdit
@export var input_country: LineEdit
@export var inputOccupier: LineEdit
@export var input_city: LineEdit
@export var input_gdp: SpinBox
@export var input_claims: TextEdit
@export var provincePopulationList: VBoxContainer
@export var provincePopulationTemplate: PanelContainer
@export var provinceResourcesList: VBoxContainer
@export var provinceResourcesTemplate: PanelContainer

@export_category("Faction")
@export var factionsItemList: ItemList
@export var factionName: LineEdit
@export var factionColor: ColorPickerButton
@export var factionMemberList: VBoxContainer
@export var factionMemberTemplate: PanelContainer

@export_category("Polity")
@export var politiesItemList: ItemList
@export var polityPuppet: CheckBox
@export var polityOwner: LineEdit
@export var polityInExile: CheckBox
@export var polityHost: LineEdit
@export var polityName: LineEdit
@export var polityColor: ColorPickerButton
@export var polityMoney: SpinBox
@export var polityPoliticalPower: SpinBox
@export var polityWarSupport: SpinBox
@export var polityStability: SpinBox
@export var polityPuppetList: VBoxContainer
@export var polityPuppetTemplate: PanelContainer
@export var polityFactionList: VBoxContainer
@export var polityFactionTemplate: PanelContainer

@export_category("Biome")
@export var biomesItemList: ItemList
@export var biomeName: LineEdit
@export var biomeColor: ColorPickerButton

@export_category("Resource")
@export var resourcesItemList: ItemList
@export var resourceName: LineEdit
@export var resourceColor: ColorPickerButton
@export var resourceIcon: LineEdit
@export var resourceIconTexture: TextureRect

func _ready() -> void:
	SetupFactionList()
	SetupPolitiesList()
	SetupBiomesList()
	SetupResourcesList()
	
	input_claims.focus_exited.connect(m_OnProvinceClaimsSubmitted)

	
	if map_sprite == null:
		map_sprite = get_node_or_null("../../MapContainer/CultureSprite")

func _unhandled_input(event: InputEvent) -> void:
	if MapManager._is_mouse_over_ui() || Console.is_visible():
		_clear_hover()
		return

	if event is InputEventMouseMotion:
		_handle_hover(event.position)
		if dragging != Drag.NONE:
			_handle_paint_selection(hovered_pid)

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if (
						(currentTool == Tool.MULTI_SELECT) ||
						(currentMode == Mode.BIOME && currentTool == Tool.PAINT_PRIMARY)
					):
						dragging = Drag.LEFT
						_handle_paint_selection(hovered_pid)
					_handle_click(event.position, Drag.LEFT)
				else:
					dragging = Drag.NONE
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					if (
						(currentTool == Tool.MULTI_SELECT) ||
						(currentMode == Mode.BIOME && currentTool == Tool.PAINT_PRIMARY)
					):
						dragging = Drag.RIGHT
						_handle_paint_selection(hovered_pid)
					_handle_click(event.position, Drag.RIGHT)
				else:
					dragging = Drag.NONE
	
	if event is InputEventKey:
		if event.ctrl_pressed && event.keycode == KEY_A && event.pressed && currentTool == Tool.MULTI_SELECT:
			if multiSelectPID.size() == 1:
				for pid: int in MapManager.country_to_owned_provinces[MapManager.province_objects[multiSelectPID[0]].country]:
					if !pid in multiSelectPID:
						multiSelectPID.push_back(pid)
						MapManager.SetProvinceColor(pid, Color.CORNSILK)
				update_multi_select_ui()

func _handle_hover(screen_pos: Vector2) -> void:
	if map_sprite == null:
		return
	var world_pos = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var pid = MapManager.get_province_with_radius(world_pos, map_sprite, 5)

	if pid == hovered_pid:
		return
	_clear_hover()

	if pid > 1:
		hovered_pid = pid
		if hovered_pid not in multiSelectPID:
			original_pid_color = MapManager.state_color_image.get_pixel(pid, 0)
			MapManager.state_color_image.set_pixel(pid, 0, original_pid_color.lightened(0.4))
			MapManager.state_color_texture.update(MapManager.state_color_image)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)

func _clear_hover() -> void:
	if hovered_pid > 1:
		if hovered_pid not in multiSelectPID:
			MapManager.state_color_image.set_pixel(hovered_pid, 0, original_pid_color)
		MapManager.state_color_texture.update(MapManager.state_color_image)
		hovered_pid = -1
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _handle_paint_selection(pid: int) -> void:
	if pid <= 1:
		return
	match currentTool:
		Tool.MULTI_SELECT:
			if Input.is_key_pressed(KEY_CTRL):
				match dragging:
					Drag.LEFT:
						if !pid in multiSelectPID:
							multiSelectPID.push_back(pid)
							MapManager.SetProvinceColor(pid, Color.CORNSILK)
							update_multi_select_ui()
					Drag.RIGHT:
						if pid in multiSelectPID:
							multiSelectPID.erase(pid)
							MapManager.ResetProvinceColor(pid)
							update_multi_select_ui()
		Tool.PAINT_PRIMARY:
			match currentMode:
				Mode.BIOME:
					if !Input.is_key_pressed(KEY_CTRL):
						match dragging:
							Drag.LEFT:
								if selectedBiome in MapManager.biomes:
									MapManager.province_objects[hovered_pid].biome = selectedBiome
									MapManager.SetProvinceColors(hovered_pid, MapManager.biomes[selectedBiome].color, MapManager.biomes[selectedBiome].color)
								original_pid_color = MapManager.biomes[selectedBiome].color
							Drag.RIGHT:
								MapManager.province_objects[hovered_pid].biome = ""
								MapManager.SetProvinceColors(hovered_pid, Color.ANTIQUE_WHITE, Color.ANTIQUE_WHITE)
								original_pid_color = Color.ANTIQUE_WHITE
				Mode.POLITY:
					if !Input.is_key_pressed(KEY_CTRL):
						match dragging:
							Drag.LEFT:
								if MapManager.province_objects[hovered_pid].country != "Sea" && selectedCountry in CountryManager.countries:
									if MapManager.province_objects[hovered_pid].country != selectedCountry:
										MapManager.OccupyProvince(hovered_pid, selectedCountry)
									else:
										MapManager.DeoccupyProvince(hovered_pid)
							Drag.RIGHT:
								if MapManager.province_objects[hovered_pid].occupier != "":
									MapManager.DeoccupyProvince(hovered_pid)

func _handle_click(_screenPos: Vector2, a_button: Drag) -> void:
	get_viewport().gui_release_focus()
	
	if hovered_pid > 1:
		match currentMode:
			Mode.PROVINCE:
				match currentTool:
					Tool.NONE:
						select_province(hovered_pid)
					Tool.MULTI_SELECT:
						MultiSelectProvince(hovered_pid)
			Mode.FACTION:
				match currentTool:
					Tool.NONE:
						select_province(hovered_pid)
					Tool.PAINT_PRIMARY:
						match a_button:
							Drag.LEFT:
								if MapManager.province_objects[hovered_pid].country != "Sea" && selectedFaction in FactionManager.factions:
									match FactionManager.factions[selectedFaction].GetMemberStatus(MapManager.province_objects[hovered_pid].country):
										"Member":
											FactionManager.factions[selectedFaction].SetMemberStatus(MapManager.province_objects[hovered_pid].country, "Leader")
										"":
											FactionManager.factions[selectedFaction].SetMemberStatus(MapManager.province_objects[hovered_pid].country, "Member")
											original_pid_color = FactionManager.factions[selectedFaction].color
							Drag.LEFT:
								if MapManager.province_objects[hovered_pid].country != "Sea" && selectedFaction in FactionManager.factions:
									match FactionManager.factions[selectedFaction].GetMemberStatus(MapManager.province_objects[hovered_pid].country):
										"Leader":
											FactionManager.factions[selectedFaction].SetMemberStatus(MapManager.province_objects[hovered_pid].country, "Member")
										"Member":
											FactionManager.factions[selectedFaction].KickMemberByName(MapManager.province_objects[hovered_pid].country)
											original_pid_color = Color.GRAY
			Mode.POLITY:
				match currentTool:
					Tool.NONE:
						select_province(hovered_pid)
					Tool.PAINT_PRIMARY:
						match a_button:
							Drag.LEFT:
								if MapManager.province_objects[hovered_pid].country != "Sea" && selectedCountry in CountryManager.countries:
									if MapManager.province_objects[hovered_pid].country != selectedCountry:
										MapManager.OccupyProvince(hovered_pid, selectedCountry)
									else:
										MapManager.DeoccupyProvince(hovered_pid)
							Drag.RIGHT:
								if MapManager.province_objects[hovered_pid].occupier != "":
									MapManager.DeoccupyProvince(hovered_pid)
					Tool.PAINT_SECONDARY:
						if MapManager.province_objects[hovered_pid].country != "Sea" && selectedCountry in CountryManager.countries:
							MapManager.transfer_ownership(hovered_pid, selectedCountry)
							original_pid_color = CountryManager.countries[selectedCountry].country_color
					Tool.MULTI_SELECT:
						match a_button:
							Drag.RIGHT:
								if hovered_pid in multiSelectPID:
									multiSelectPID.erase(hovered_pid)
									MapManager.ResetProvinceColor(hovered_pid)
									update_multi_select_ui()
							Drag.LEFT:
								if !hovered_pid in multiSelectPID:
									multiSelectPID.push_back(hovered_pid)
									MapManager.SetProvinceColor(hovered_pid, Color.CORNSILK)
									update_multi_select_ui()
			Mode.BIOME:
				match currentTool:
					Tool.NONE:
						select_province(hovered_pid)
					Tool.PAINT_PRIMARY:
						match a_button:
							Drag.LEFT:
								if selectedBiome in MapManager.biomes:
									MapManager.province_objects[hovered_pid].biome = selectedBiome
									MapManager.SetProvinceColors(hovered_pid, MapManager.biomes[selectedBiome].color, MapManager.biomes[selectedBiome].color)
								original_pid_color = MapManager.biomes[selectedBiome].color
							Drag.RIGHT:
								MapManager.province_objects[hovered_pid].biome = ""
								MapManager.SetProvinceColors(hovered_pid, Color.ANTIQUE_WHITE, Color.ANTIQUE_WHITE)
								original_pid_color = Color.ANTIQUE_WHITE

func IndexOfText(a_itemList: ItemList, a_text: String) -> int:
	for i in range(a_itemList.item_count):
		if a_itemList.get_item_text(i) == a_text:
			return i
	return -1

func select_province(pid: int) -> void:
	selected_pid = pid
	var prov = MapManager.province_objects.get(pid)
	if not prov:
		return

	#var color_str = _color_to_rgb_string(prov.r_color) if prov.r_color else "Unknown"
	status_label.text = "Selected PID: %d" % [pid]

	# Set Fields
	provinceName.editable = true
	provinceName.text = prov.name
	input_country.editable = true
	input_country.text = prov.country
	inputOccupier.editable = true
	inputOccupier.text = prov.occupier
	input_city.editable = true
	input_city.text = prov.city
	input_gdp.editable = true
	input_gdp.value = prov.gdp
	input_claims.editable = true
	input_claims.text = ", ".join(prov.claims)
	
	for child in provincePopulationList.get_children():
		child.queue_free()
	for population: PopulationData in prov.populations:
		var populationEntry: PanelContainer = provincePopulationTemplate.duplicate()
		populationEntry.visible = true
		populationEntry.get_node("MarginContainer/HBoxContainer/Button").pressed.connect(func():
			prov.populations.erase(population)
			populationEntry.queue_free()
		)
		populationEntry.get_node("MarginContainer/HBoxContainer/InputEthName").text = population.ethnicity
		populationEntry.get_node("MarginContainer/HBoxContainer/InputEthName").text_submitted.connect(func(a_ethnicity: String): population.ethnicity = a_ethnicity)
		populationEntry.get_node("MarginContainer/HBoxContainer/InputPop").value = population.amount
		populationEntry.get_node("MarginContainer/HBoxContainer/InputPop").value_changed.connect(func(a_amount: float): population.amount = a_amount)
		provincePopulationList.add_child(populationEntry)
		
	for child in provinceResourcesList.get_children():
		child.queue_free()
	for resource: ResourceNode in prov.resources:
		var resourceEntry: PanelContainer = provinceResourcesTemplate.duplicate()
		resourceEntry.visible = true
		resourceEntry.get_node("MarginContainer/HBoxContainer/Button").pressed.connect(func():
			prov.resources.erase(resource)
			resourceEntry.queue_free()
		)
		resourceEntry.get_node("MarginContainer/HBoxContainer/InputResource").text = resource.type
		resourceEntry.get_node("MarginContainer/HBoxContainer/InputResource").text_submitted.connect(func(a_type: String): resource.type = a_type)
		resourceEntry.get_node("MarginContainer/HBoxContainer/InputAmount").value = resource.amount
		resourceEntry.get_node("MarginContainer/HBoxContainer/InputAmount").value_changed.connect(func(a_amount: float): resource.amount = a_amount)
		resourceEntry.get_node("MarginContainer/HBoxContainer/InputQuality").value = resource.amount
		resourceEntry.get_node("MarginContainer/HBoxContainer/InputQuality").value_changed.connect(func(a_quality: float): resource.quality = a_quality)
		provinceResourcesList.add_child(resourceEntry)
	
	match currentMode:
		Mode.POLITY:
			if prov.country != "Sea":
				var itemIndex: int = IndexOfText(politiesItemList, prov.country)
				politiesItemList.select(itemIndex)
				politiesItemList.item_selected.emit(itemIndex)
		Mode.BIOME:
			if !prov.biome.is_empty():
				var itemIndex: int = IndexOfText(biomesItemList, prov.biome)
				biomesItemList.select(itemIndex)
				biomesItemList.item_selected.emit(itemIndex)

func MultiSelectProvince(pid: int) -> void:
	if pid <= 1:
		return
		
	if pid in multiSelectPID:
		multiSelectPID.erase(pid)
		MapManager.ResetProvinceColor(pid)
	else:
		multiSelectPID.push_back(pid)
		MapManager.SetProvinceColor(pid, Color.CORNSILK)

	update_multi_select_ui()

func update_multi_select_ui() -> void:
	#var color_str = _color_to_rgb_string(prov.r_color) if prov.r_color else "Unknown"
	status_label.text = "Selected: %d" % [multiSelectPID.size()]

	for child in provincePopulationList.get_children():
		child.queue_free()
	
	for child in provinceResourcesList.get_children():
		child.queue_free()

	# Set Fields
	match multiSelectPID.size():
		0:
			provinceName.editable = false
			provinceName.text = "" 
			input_country.editable = false
			input_country.text = ""
			inputOccupier.editable = false
			inputOccupier.text = ""
			input_city.editable = false
			input_city.text = ""
			input_gdp.editable = false
			input_gdp.value = 0
			input_claims.editable = false
			input_claims.text = ""
		1:
			var prov: Province = MapManager.province_objects.get(multiSelectPID[0])
			if not prov:
				return
			provinceName.editable = true
			provinceName.text = prov.name
			input_country.editable = true
			input_country.text = prov.country
			inputOccupier.editable = true
			inputOccupier.text = prov.occupier
			input_city.editable = true
			input_city.text = prov.city
			input_gdp.editable = true
			input_gdp.value = prov.gdp
			input_claims.editable = true
			input_claims.text = ", ".join(prov.claims)
			
			for population: PopulationData in prov.populations:
				var populationEntry: PanelContainer = provincePopulationTemplate.duplicate()
				populationEntry.visible = true
				populationEntry.get_node("MarginContainer/HBoxContainer/Button").pressed.connect(func():
					prov.populations.erase(population)
					populationEntry.queue_free()
				)
				populationEntry.get_node("MarginContainer/HBoxContainer/InputEthName").text = population.ethnicity
				populationEntry.get_node("MarginContainer/HBoxContainer/InputEthName").text_submitted.connect(func(a_ethnicity: String): population.ethnicity = a_ethnicity)
				populationEntry.get_node("MarginContainer/HBoxContainer/InputPop").value = population.amount
				populationEntry.get_node("MarginContainer/HBoxContainer/InputPop").value_changed.connect(func(a_amount: float): population.amount = a_amount)
				provincePopulationList.add_child(populationEntry)
			for resource: ResourceNode in prov.resources:
				var resourceEntry: PanelContainer = provinceResourcesTemplate.duplicate()
				resourceEntry.visible = true
				resourceEntry.get_node("MarginContainer/HBoxContainer/Button").pressed.connect(func():
					prov.resources.erase(resource)
					resourceEntry.queue_free()
				)
				resourceEntry.get_node("MarginContainer/HBoxContainer/InputResource").text = resource.type
				resourceEntry.get_node("MarginContainer/HBoxContainer/InputResource").text_submitted.connect(func(a_type: String): resource.type = a_type)
				resourceEntry.get_node("MarginContainer/HBoxContainer/InputAmount").value = resource.amount
				resourceEntry.get_node("MarginContainer/HBoxContainer/InputAmount").value_changed.connect(func(a_amount: float): resource.amount = a_amount)
				resourceEntry.get_node("MarginContainer/HBoxContainer/InputQuality").value = resource.amount
				resourceEntry.get_node("MarginContainer/HBoxContainer/InputQuality").value_changed.connect(func(a_quality: float): resource.quality = a_quality)
				provinceResourcesList.add_child(resourceEntry)
		_:
			var prov: Province = MapManager.province_objects.get(multiSelectPID[0])
			if not prov:
				return
			provinceName.editable = false
			provinceName.text = "..." 
			
			var holdCountry: bool = true
			var holdOccupier: bool = true
			var holdGDP: bool = true
			
			var holdClaims: bool = true
			
			for iPID: int in multiSelectPID:
				holdCountry = holdCountry && prov.country == MapManager.province_objects[iPID].country
				holdOccupier = holdOccupier && prov.occupier == MapManager.province_objects[iPID].occupier
				holdGDP = holdGDP && prov.gdp == MapManager.province_objects[iPID].gdp
				holdClaims = holdClaims && prov.claims == MapManager.province_objects[iPID].claims
				if !holdCountry && !holdOccupier && !holdGDP && !holdClaims:
					break
			
			input_country.editable = true
			input_country.text = prov.country if holdCountry else "..."
			inputOccupier.editable = true
			inputOccupier.text = prov.occupier if holdOccupier else "..."
			input_city.editable = false
			input_city.text = "..."
			input_gdp.editable = true
			input_gdp.value = prov.gdp if holdGDP else 0
			input_claims.editable = true
			input_claims.text = ", ".join(prov.claims) if holdClaims else "..."
	
	#match currentMode:
	#	Mode.POLITY:
	#		if prov.country != "Sea":
	#			var itemIndex: int = IndexOfText(politiesItemList, prov.country)
	#			politiesItemList.select(itemIndex)
	#			politiesItemList.item_selected.emit(itemIndex)
	#	Mode.BIOME:
	#		if !prov.biome.is_empty():
	#			var itemIndex: int = IndexOfText(biomesItemList, prov.biome)
	#			biomesItemList.select(itemIndex)
	#			biomesItemList.item_selected.emit(itemIndex)

func _on_apply_pressed() -> void:
	return
	if selected_pid <= 1:
		return
	var prov = MapManager.province_objects.get(selected_pid)
	if not prov:
		return

	var old_country = prov.country
	var new_country = input_country.text.strip_edges()

	# 1. Update MapManager global data

	# 2. Update Province Object

	var raw_claims = input_claims.text.split(",")
	var final_claims = []
	for c in raw_claims:
		var clean = c.strip_edges()
		if clean != "":
			final_claims.append(clean)
	prov.claims = final_claims

	# 3. Cleanup Dictionaries
	if old_country != new_country:
		if MapManager.country_to_provinces.has(old_country):
			MapManager.country_to_provinces[old_country].erase(selected_pid)
		if not MapManager.country_to_provinces.has(new_country):
			MapManager.country_to_provinces[new_country] = []
		MapManager.country_to_provinces[new_country].append(selected_pid)

	MapManager.state_color_texture.update(MapManager.state_color_image)
	print("MapEditor: Applied changes and updated colors for ", new_country)

func _on_export_pressed() -> void:
	MapManager.export_scenario_data("user://map_data/")

func m_OnTabContainerTabChanged(tab: int) -> void:
	m_NoneTool()
	currentMode = tab as Mode
	leftSidebar.current_tab = tab

func SetupFactionList() -> void:
	factionsItemList.clear()
	for faction in FactionManager.factions.keys():
		factionsItemList.add_item(faction)
	factionsItemList.sort_items_by_text()

func SetupPolitiesList() -> void:
	politiesItemList.clear()
	for polity in CountryManager.countryNames:
		politiesItemList.add_item(polity)
	politiesItemList.sort_items_by_text()

func SetupBiomesList() -> void:
	biomesItemList.clear()
	for biome: String in MapManager.biomes:
		biomesItemList.add_item(biome)
	biomesItemList.sort_items_by_text()
	
func SetupResourcesList() -> void:
	resourcesItemList.clear()
	for resource: String in MapManager.resources:
		resourcesItemList.add_item(resource)
	resourcesItemList.sort_items_by_text()

func m_OnFactionSelected(index: int) -> void:
	selectedFaction = factionsItemList.get_item_text(index)
	var faction: FactionData = FactionManager.factions[selectedFaction]
	factionName.text = faction.name
	factionColor.color = faction.color
	for child in factionMemberList.get_children():
		child.queue_free()
	for member: FactionMember in faction.members:
		var memberEntry: PanelContainer = factionMemberTemplate.duplicate()
		memberEntry.visible = true
		memberEntry.get_node("HBoxContainer/Button").pressed.connect(func():
			FactionManager.factions[selectedFaction].KickMember(member)
			memberEntry.queue_free()
		)
		memberEntry.get_node("HBoxContainer/LineEdit").text = member.polity
		memberEntry.get_node("HBoxContainer/OptionButton").select(FactionMember.GetIndex(member.status))
		memberEntry.get_node("HBoxContainer/OptionButton").item_selected.connect(func(a_index: int): FactionManager.factions[selectedFaction].UpdateMemberStatus(member.polity, a_index))
		factionMemberList.add_child(memberEntry)
	
func m_OnPolitySelected(index: int) -> void:
	selectedCountry = politiesItemList.get_item_text(index)
	var polity: CountryData = CountryManager.countries[selectedCountry]
	polityPuppet.set_pressed_no_signal(polity.is_puppet)
	polityOwner.text = polity.owner
	polityInExile.set_pressed_no_signal(polity.is_exiled)
	polityHost.text = polity.host
	polityName.text = polity.country_name
	polityColor.color = polity.country_color
	polityMoney.set_value_no_signal(polity.money)
	polityPoliticalPower.set_value_no_signal(polity.political_power)
	polityWarSupport.set_value_no_signal(polity.war_support)
	polityStability.set_value_no_signal(polity.stability)
	for child in polityPuppetList.get_children():
		child.queue_free()
	for puppet in polity.puppets:
		var puppetEntry: PanelContainer = polityPuppetTemplate.duplicate()
		puppetEntry.visible = true
		puppetEntry.get_node("HBoxContainer/Label").text = puppet
		polityPuppetList.add_child(puppetEntry)
	for child in polityFactionList.get_children():
		child.queue_free()
	for faction in polity.factions:
		var factionEntry: PanelContainer = polityFactionTemplate.duplicate()
		factionEntry.visible = true
		factionEntry.get_node("HBoxContainer/LineEdit").text = faction
		factionEntry.get_node("HBoxContainer/OptionButton").select(FactionMember.GetIndex(FactionManager.factions[faction].members[FactionManager.factions[faction].members.find_custom(func(a): return a.polity == polity.country_name)].status))
		polityFactionList.add_child(factionEntry)

func m_OnBiomeSelected(index: int) -> void:
	selectedBiome = biomesItemList.get_item_text(index)
	var biome: BiomeData = MapManager.biomes[selectedBiome]
	biomeName.text = biome.name
	biomeColor.color = biome.color

func m_OnBiomeNameSubmitted(new_text: String) -> void:
	if selectedBiome in MapManager.biomes && !new_text in MapManager.biomes:
		MapManager.biomes[new_text] = MapManager.biomes[selectedBiome]
		MapManager.biomes[new_text].name = new_text
		MapManager.biomes.erase(selectedBiome)
		for province: Province in MapManager.province_objects.values():
			if province.biome == selectedBiome:
				province.biome = new_text
		selectedBiome = new_text

func m_OnBiomeColorChanged(color: Color) -> void:
	if selectedBiome in MapManager.biomes:
		MapManager.biomes[selectedBiome].color = color

func m_OnResourceSelected(index: int) -> void:
	selectedResource = resourcesItemList.get_item_text(index)
	var resource: ResourceData = MapManager.resources[selectedResource]
	resourceName.text = resource.name
	resourceColor.color = resource.color
	resourceIcon.text = resource.icon
	resourceIconTexture.texture = MapManager.GetResourceIcon(selectedResource)

func m_OnResourceNameSubmitted(new_text: String) -> void:
	if selectedResource in MapManager.resources && !new_text in MapManager.resources:
		MapManager.resources[new_text] = MapManager.resources[selectedResource]
		MapManager.resources[new_text].name = new_text
		MapManager.resources.erase(selectedResource)
		for province: Province in MapManager.province_objects.values():
			for resource: ResourceNode in province.resources:
				if resource.type == selectedResource:
					resource.type = new_text
		selectedResource = new_text

func m_OnResourceColorChanged(color: Color) -> void:
	if selectedResource in MapManager.resources:
		MapManager.resources[selectedResource].color = color

func m_OnResourceIconSubmitted(new_text: String) -> void:
	if selectedResource in MapManager.resources:
		MapManager.resources[selectedResource].icon = new_text
		resourceIconTexture.texture = MapManager.GetResourceIcon(selectedResource)

func m_OnCitySubmitted(new_text: String) -> void:
	if selected_pid in MapManager.province_objects:
		MapManager.province_objects[selected_pid].city = new_text

func m_OnProvinceGDPChanged(value: float) -> void:
	print("Value")
	match currentTool:
		Tool.NONE:
			print(selected_pid)
			if selected_pid in MapManager.province_objects:
				MapManager.province_objects[selected_pid].gdp = value
		Tool.MULTI_SELECT:
			print(multiSelectPID)
			for pid: int in multiSelectPID:
				if pid in MapManager.province_objects:
					MapManager.province_objects[pid].gdp = value

func m_OnColorChanged(color: Color) -> void:
	if selectedCountry in CountryManager.countries:
		CountryManager.countries[selectedCountry].country_color = color
		MapManager.set_country_color(selectedCountry, color)

func m_OnFactionColorChanged(color: Color) -> void:
	if selectedFaction in FactionManager.factions:
		FactionManager.factions[selectedFaction].color = color

func m_OnProvinceNameSubmitted(new_text: String) -> void:
	if selected_pid in MapManager.province_objects:
		#if (new_text == MapManager.province_objects[selected_pid].occupier):
		MapManager.province_objects[selected_pid].name = new_text

func m_OnProvinceClaimsSubmitted() -> void:
	if input_claims.text == "...":
		return

	var raw_claims = input_claims.text.split(",")
	var final_claims: Array[String] = []
	for c in raw_claims:
		final_claims.append(c.strip_edges())
	
	match currentTool:
		Tool.NONE:
			if selected_pid in MapManager.province_objects:
				MapManager.province_objects[selected_pid].claims = final_claims
		Tool.MULTI_SELECT:
			for pid: int in multiSelectPID:
				if pid in MapManager.province_objects:
					MapManager.province_objects[pid].claims = final_claims

func m_OnProvinceOwnerSubmitted(new_text: String) -> void:
	match currentTool:
		Tool.NONE:
			if selected_pid in MapManager.province_objects && CountryManager.countries.has(new_text):
				#if (new_text == MapManager.province_objects[selected_pid].occupier):
				MapManager.transfer_ownership(selected_pid, new_text)
		Tool.MULTI_SELECT:
			for pid: int in multiSelectPID:
				if pid in MapManager.province_objects && CountryManager.countries.has(new_text):
					#if (new_text == MapManager.province_objects[selected_pid].occupier):
					MapManager.transfer_ownership(pid, new_text)
	

func m_OnProvinceOccupierSubmitted(new_text: String) -> void:
	match currentTool:
		Tool.NONE:
			if selected_pid in MapManager.province_objects:
				if new_text.is_empty():
					MapManager.DeoccupyProvince(selected_pid)
				else:
					MapManager.OccupyProvince(selected_pid, new_text)
		Tool.MULTI_SELECT:
			for pid: int in multiSelectPID:
				if pid in MapManager.province_objects:
					if new_text.is_empty():
						MapManager.DeoccupyProvince(pid)
					else:
						MapManager.OccupyProvince(pid, new_text)
	

func m_OnPolityNameSubmitted(new_text: String) -> void:
	if selectedCountry in CountryManager.countries:
		CountryManager.RenameCountry(selectedCountry, new_text)
		selectedCountry = new_text

func m_OnPolityOwnerSubmitted(new_text: String) -> void:
	if selectedCountry in CountryManager.countries:
		if (CountryManager.countries[selectedCountry].owner in CountryManager.countries):
			MapManager.release(CountryManager.countries[selectedCountry].owner, selectedCountry, false, false)
		if (new_text in CountryManager.countries):
			CountryManager.make_puppet(CountryManager.countries[new_text], CountryManager.countries[selectedCountry])

func m_OnPolityMoneyChanged(value: float) -> void:
	if selectedCountry in CountryManager.countries:
		CountryManager.countries[selectedCountry].money = value

func m_OnPolityPoliticalPowerChanged(value: float) -> void:
	if selectedCountry in CountryManager.countries:
		CountryManager.countries[selectedCountry].political_power = value

func m_OnPolityWarSupportChanged(value: float) -> void:
	if selectedCountry in CountryManager.countries:
		CountryManager.countries[selectedCountry].war_support = value

func m_OnPolityStabilityChanged(value: float) -> void:
	if selectedCountry in CountryManager.countries:
		CountryManager.countries[selectedCountry].stability = value

func m_NoneTool() -> void:
	match currentTool:
		Tool.MULTI_SELECT:
			for pid: int in multiSelectPID:
				MapManager.ResetProvinceColor(pid)
			multiSelectPID = []
	currentTool = Tool.NONE

func m_PaintOwnerTool() -> void:
	match currentTool:
		Tool.MULTI_SELECT:
			for pid: int in multiSelectPID:
				MapManager.ResetProvinceColor(pid)
			multiSelectPID = []
	MapManager.show_countries_map()
	currentTool = Tool.PAINT_SECONDARY
	
func m_PaintOccupationTool() -> void:
	match currentTool:
		Tool.MULTI_SELECT:
			for pid: int in multiSelectPID:
				MapManager.ResetProvinceColor(pid)
			multiSelectPID = []
	MapManager.show_countries_map()
	currentTool = Tool.PAINT_PRIMARY
	
func m_PaintFactionTool() -> void:
	match currentTool:
		Tool.MULTI_SELECT:
			for pid: int in multiSelectPID:
				MapManager.ResetProvinceColor(pid)
			multiSelectPID = []
	MapManager.show_faction_map()
	currentTool = Tool.PAINT_PRIMARY

func m_PaintBiomeTool() -> void:
	match currentTool:
		Tool.MULTI_SELECT:
			for pid: int in multiSelectPID:
				MapManager.ResetProvinceColor(pid)
			multiSelectPID = []
	MapManager.show_biomes_map()
	currentTool = Tool.PAINT_PRIMARY

func m_MultiSelectTool() -> void:
	currentTool = Tool.MULTI_SELECT

func AddedFactionMember() -> void:
	var member: FactionMember = FactionManager.factions[selectedFaction].members.back()
	var memberEntry: PanelContainer = factionMemberTemplate.duplicate()
	memberEntry.visible = true
	memberEntry.get_node("HBoxContainer/Button").pressed.connect(func():
		FactionManager.factions[selectedFaction].KickMember(member)
		memberEntry.queue_free()
	)
	memberEntry.get_node("HBoxContainer/LineEdit").text = member.polity
	memberEntry.get_node("HBoxContainer/OptionButton").select(FactionMember.GetIndex(member.status))
	memberEntry.get_node("HBoxContainer/OptionButton").item_selected.connect(func(a_index: int): member.status = FactionMember.GetString(a_index))
	factionMemberList.add_child(memberEntry)

func AddProvincePopulation() -> void:
	var prov: Province = MapManager.province_objects[selected_pid]
	prov.populations.push_back(PopulationData.FromDict({
		"ethnicity": "Unknown",
		"amount": 1
	}))
	var population: PopulationData = prov.populations.back()
	var populationEntry: PanelContainer = provincePopulationTemplate.duplicate()
	populationEntry.visible = true
	populationEntry.get_node("MarginContainer/HBoxContainer/Button").pressed.connect(func():
		prov.populations.erase(population)
		populationEntry.queue_free()
	)
	populationEntry.get_node("MarginContainer/HBoxContainer/InputEthName").text = population.ethnicity
	populationEntry.get_node("MarginContainer/HBoxContainer/InputEthName").text_submitted.connect(func(a_ethnicity: String): population.ethnicity = a_ethnicity)
	populationEntry.get_node("MarginContainer/HBoxContainer/InputPop").value = population.amount
	populationEntry.get_node("MarginContainer/HBoxContainer/InputPop").value_changed.connect(func(a_amount: float): population.amount = a_amount)
	provincePopulationList.add_child(populationEntry)

func AddProvinceResource() -> void:
	var prov: Province = MapManager.province_objects[selected_pid]
	prov.resources.push_back(ResourceNode.FromDict({
		"type": "Unknown"
	}))
	var resource: ResourceNode = prov.resources.back()
	var resourceEntry: PanelContainer = provinceResourcesTemplate.duplicate()
	resourceEntry.visible = true
	resourceEntry.get_node("MarginContainer/HBoxContainer/Button").pressed.connect(func():
		prov.resources.erase(resource)
		resourceEntry.queue_free()
	)
	resourceEntry.get_node("MarginContainer/HBoxContainer/InputResource").text = resource.type
	resourceEntry.get_node("MarginContainer/HBoxContainer/InputResource").text_submitted.connect(func(a_type: String): resource.type = a_type)
	resourceEntry.get_node("MarginContainer/HBoxContainer/InputAmount").value = resource.amount
	resourceEntry.get_node("MarginContainer/HBoxContainer/InputAmount").value_changed.connect(func(a_amount: float): resource.amount = a_amount)
	resourceEntry.get_node("MarginContainer/HBoxContainer/InputQuality").value = resource.amount
	resourceEntry.get_node("MarginContainer/HBoxContainer/InputQuality").value_changed.connect(func(a_quality: float): resource.quality = a_quality)
	provinceResourcesList.add_child(resourceEntry)
