class_name Tooltip extends PanelContainer

func _enter_tree() -> void:
	GameState.tooltip = self
	visible = false

@export var offset: Vector2 = Vector2.ZERO

@export var tabs: TabContainer
@export var resourceTemplate: HBoxContainer
@export var resourcesList: VBoxContainer
@export var provinceName: Label
@export var provinceDescription: RichTextLabel
@export var provinceInfrastructure: Label
@export var provinceClaims: Label

@export var buildingsLabel: Label
@export var resourcesGrid: Container

var tooltipLatch: bool = false
var shouldBeVisible: bool = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	set_position(get_global_mouse_position() + offset)
	position.x = clamp(position.x, 0, get_viewport_rect().size.x - size.x)
	position.y = clamp(position.y, 0, get_viewport_rect().size.y - size.y)

func _physics_process(_delta: float) -> void:
	visible = shouldBeVisible #&& Input.is_key_pressed(KEY_ALT)

func SwitchTooltip(a_mode: int) -> void:
	match a_mode:
		-1:
			shouldBeVisible = false
		0:
			shouldBeVisible = true
			if !tooltipLatch:
				DeferredUpdate.call_deferred()
				tooltipLatch = true
			tabs.current_tab = 0
			for resource: HBoxContainer in resourcesList.get_children():
				resource.queue_free()
			var prov: Province = MapManager.province_objects[MapManager.current_hovered_pid]
			for resource: ResourceNode in prov.resources:
				var resourceBop: HBoxContainer = resourceTemplate.duplicate()
				resourceBop.get_node("TextureRect").texture = MapManager.GetResourceIcon(resource.type)
				resourceBop.get_node("Label").text = "%s - %d (%.2f%%)" % [resource.type, resource.amount, 100 * resource.quality]
				resourceBop.visible = true
				resourcesList.add_child(resourceBop)
		1:
			var fmt_claims: String = ""
			shouldBeVisible = true
			if !tooltipLatch:
				DeferredUpdate.call_deferred()
				tooltipLatch = true
			tabs.current_tab = 1
			var prov: Province = MapManager.province_objects[MapManager.current_hovered_pid]
			provinceName.text = prov.name
			
			var desc_text = ""
			if !prov.city.is_empty():
				desc_text += prov.city
			
			var active_buildings = ""
			for building in prov.buildings:
				var state_str = ""
				match building.state:
					BuildingData.BuildingState.CONSTRUCTION:
						state_str = " (Under Construction)"
					BuildingData.BuildingState.RUIN:
						state_str = " (Ruin)"
				active_buildings += building.type + state_str + "\n"
			buildingsLabel.text = active_buildings
			
			# if !active_buildings.is_empty():
			# 	if !desc_text.is_empty():
			# 		desc_text += "\n"
			# 	desc_text += "Buildings:"
			# 	for b in active_buildings:
			# 		desc_text += "\n- " + b
			
			# var active_resources = []

			for resource in resourcesGrid.get_children(): resource.queue_free()
			for resource in prov.resources:
				var resourceBop: HBoxContainer = resourceTemplate.duplicate()
				resourceBop.get_node("TextureRect").texture = MapManager.GetResourceIcon(resource.type)
				resourceBop.get_node("TextureRect").modulate = MapManager.resources[resource.type].color
				resourceBop.get_node("Label").text = "%s - %d (%.2f%%)" % [resource.type, resource.amount, 100 * resource.quality]
				resourceBop.visible = true
				resourcesGrid.add_child(resourceBop)

				# active_resources.append("%s - %d (%.2f%%)" % [resource.type, resource.amount, 100.0 * resource.quality])
			
			# if !active_resources.is_empty():
			# 	if !resouce_text.is_empty():
			# 		resouce_text += "\n"
			# 	for r in active_resources:
			# 		resouce_text += "\n- " + r
			
			provinceDescription.text = desc_text
			# provinceInfrastructure.text = "%d/%d" % [prov.infrastructure, prov.maxInfrastructure]
			for claim in prov.claims:
				fmt_claims += claim+"\n"
			provinceClaims.text = fmt_claims


func DeferredUpdate() -> void:
	reset_size()
	tooltipLatch = false
