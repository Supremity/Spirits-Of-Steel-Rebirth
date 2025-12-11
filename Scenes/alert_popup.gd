extends Control

# UI Nodes
@onready var flag_left: TextureRect = $Panel/flag_left
@onready var flag_right: TextureRect = $Panel/flag_right
@onready var description: Label = $Panel/description
@onready var button: Button = $Panel/Button

# Internal Data Variables
var _type: String = ""
var _c1: CountryData = null
var _c2: CountryData = null

# 1. We call this BEFORE adding to the tree. 
# It just stores data. It does NOT touch the UI.
func set_data(type, country1, country2):
	_type = type
	_c1 = country1
	_c2 = country2

# 2. _ready is called automatically when the node enters the tree.
# The UI nodes are guaranteed to exist here.
func _ready():
	button.pressed.connect(_on_ok)
	_update_ui()

func _update_ui():
	# Handle the "Empty String" error you saw earlier
	if _c1 == null or _c2 == null:
		push_warning("Popup Alert created with empty country")
		return

	var flag1 = _get_flag(_c1.name)
	var flag2 = _get_flag(_c2.name)
	
	if flag1: flag_left.texture = flag1
	if flag2: flag_right.texture = flag2

	if _type == "war":
		description.text = "%s has declared war on %s" % [_c1.name, _c2.name]

func _on_ok():
	queue_free()

func _get_flag(country):
	# Optimized loading
	var path = "res://assets/flags/%s_flag.png" % country.to_lower()
	return ResourceLoader.load(path)
