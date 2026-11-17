extends CanvasLayer

class GovernmentPosition:
	var sigFig: String
	var position: String
	var sigPos: Label
	var sigName: RichTextLabel
	var sigPortrait: TextureRect
	var sigBlood: TextureRect
	var sigOpt: OptionButton
	var sigDesc: RichTextLabel
	
@export var country: CountryData
@export var template: PanelContainer
@export var listOfPositions: HBoxContainer
var positions: Dictionary[String, GovernmentPosition] = {}

var m_wasPaused: bool = false


func m_OnBackPressed() -> void:
	var game_ui = get_tree().root.find_child("ui_game", true, false)
	if game_ui:
		game_ui.visible = true
	#GameState.in_peace_process = false
	if !m_wasPaused:
		GameState.current_world.clock.resume()

	self.hide()
	
	country = null
	positions.clear()
	for child: Node in listOfPositions.get_children():
		child.queue_free()

func OpenMenu(a_country: CountryData):
	self.show()
	country = a_country
	
	# Leader
	for position: String in a_country.governmentPositions:
		for I_figure: String in a_country.governmentPositions[position]:
			var govPos: GovernmentPosition = GovernmentPosition.new()
			govPos.sigFig = I_figure
			govPos.position = position
			var leader: PanelContainer = template.duplicate()
			govPos.sigPos = leader.get_node("VBoxContainer/Label")
			govPos.sigPos.text = position
			govPos.sigName = leader.get_node("VBoxContainer/Header/ScrollContainer/Label")
			govPos.sigPortrait = leader.get_node("VBoxContainer/Picture/TextureRect")
			govPos.sigBlood = leader.get_node("VBoxContainer/Picture/TextureRect/Blood")
			govPos.sigOpt = leader.get_node("VBoxContainer/PanelContainer3/OptionButton2")
			for sigFig: String in a_country.figures:
				govPos.sigOpt.add_item(sigFig)
			govPos.sigDesc = leader.get_node("VBoxContainer/Display/RichTextLabel")
			if a_country.governmentPositions[position]:
				var figure: ImportantFigure = MapManager.significantFigures[I_figure]
				govPos.sigName.text = figure.name
				govPos.sigPortrait.texture = ImportantFigure.GetPortrait(figure)
				govPos.sigBlood.visible = figure.status == ImportantFigure.Status.WOUNDED
				govPos.sigDesc.text = "[center][font_size=24]Traits[/font_size][/center][code][ul bullet=]\n[/ul][/code][hr]\n[center][font_size=24]Skills[/font_size][/center][code][ul bullet=]%s\n[/ul][/code]" % figure.GetDisplaySkills()
				for i in range(govPos.sigOpt.item_count):
					if govPos.sigOpt.get_item_text(i) == figure.name:
						govPos.sigOpt.select(i)
			govPos.sigOpt.item_selected.connect(func (a_index: int):
				var figureName: String = govPos.sigOpt.get_item_text(a_index)
				var figure: ImportantFigure = MapManager.significantFigures[figureName]
				govPos.sigName.text = figure.name
				govPos.sigPortrait.texture = ImportantFigure.GetPortrait(figure)
				govPos.sigBlood.visible = figure.status == ImportantFigure.Status.WOUNDED
				govPos.sigDesc.text = "[center][font_size=24]Traits[/font_size][/center][code][ul bullet=]\n[/ul][/code][hr]\n[center][font_size=24]Skills[/font_size][/center][code][ul bullet=]%s\n[/ul][/code]" % figure.GetDisplaySkills()
				country.SetGovernmentPosition(govPos.position, figure)
			)
			listOfPositions.add_child(leader)
			leader.visible = true
			positions[position] = govPos
	
	var game_ui = get_tree().root.find_child("ui_game", true, false)
	if game_ui:
		game_ui.visible = false
	m_wasPaused = GameState.current_world.clock.paused
	GameState.current_world.clock.pause()
	#GameState.in_peace_process = true
