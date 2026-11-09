extends Control

@onready var background_rect: TextureRect = $"VBoxContainer/background"
# @onready var heading_label: Label = $"PanelContainer/VBoxContainer/description"
@onready var button: Button = $"VBoxContainer/Button"

func _ready():
	pass

func setup(a_text: String, a_background: String, mapdata_path: String):
	# Data format: { "background": "ww3", "desc": "...", "button": "..." }
	# if data.has("desc"):
	# 	desc_label.text = data["desc"]
	if button:
		button.text = a_text
		var load_map_data = func():
			# World.DoSetup reads map_data.json for this start and reports progress.
			GameState.current_start = mapdata_path.get_base_dir().get_file()
			SceneSwitcher.switch_to(SceneSwitcher.Type.WORLD)
		button.pressed.connect(load_map_data)
		
	if a_background:
		if FileAccess.file_exists(a_background) or ResourceLoader.exists(a_background):
			background_rect.texture = load(a_background)
		#else:
			#push_warning("StartEntry: Background image not found at %s" % a_background)

# func _on_button_pressed():
	# queue_free()
