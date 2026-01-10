extends Node

var AlertPopupScene = preload("res://Scenes/AlertPopup.tscn")
var active_popups: Array = []

# The CanvasLayer ensures the UI stays on screen even if the Camera moves
var ui_layer: CanvasLayer = CanvasLayer.new()


func _ready():
	# We add the layer to the Manager itself (since the Manager is an AutoLoad)
	# Layer 100 ensures it draws on top of almost everything else
	ui_layer.layer = 100
	add_child(ui_layer)


func show_alert(type: String, country1: CountryData, country2: CountryData):
	var popup = AlertPopupScene.instantiate()

	# 1. Set Data
	popup.set_data(type, country1, country2)

	# 2. Add to the CanvasLayer
	ui_layer.add_child(popup)

	# 3. Position and Track
	active_popups.append(popup)

	# We wait one frame to position it, to ensure the popup
	# has calculated its own size based on the text inside.
	popup.call_deferred("reset_size")
	call_deferred("_restack_popups")

	popup.tree_exited.connect(
		func():
			active_popups.erase(popup)
			_restack_popups()
	)


func _restack_popups():
	var viewport_size = get_viewport().get_visible_rect().size
	var center_x = viewport_size.x / 2
	var center_y = viewport_size.y / 2

	# How much space between popups?
	var spacing = 20

	for i in range(active_popups.size()):
		var popup = active_popups[i]

		# Calculate X: Center of screen minus half the popup width
		var pos_x = center_x - (popup.size.x / 2)

		# Calculate Y: Center of screen, plus the stack index, minus half popup height
		# This makes the first one appear dead center
		var pos_y = center_y + (i * spacing) - (popup.size.y / 2)

		popup.position = Vector2(pos_x, pos_y)
