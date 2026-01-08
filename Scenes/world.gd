# World.gd
extends Node2D

@onready var map_sprite: Sprite2D = $MapContainer/CultureSprite as Sprite2D
@onready var camera: Camera2D = $Camera2D as Camera2D
@onready var troop_renderer: CustomRenderer = $MapContainer/CustomRenderer as CustomRenderer

const MAP_SHADER = preload("res://shaders/map_shader.gdshader")

var map_width: float = 0.0
var map_height: float = 0.0

func _ready() -> void:
	await get_tree().process_frame # wait for Managers (singletons) to load
	
	if MapManager.id_map_image != null:
		_on_map_ready()

	TroopManager.troop_selection = $TroopSelection as TroopSelection

	MainClock.pause()


func _on_map_ready() -> void:
	print("World: Map is ready -> configuring visuals...")
	map_width = MapManager.id_map_image.get_width()
	map_height = MapManager.id_map_image.get_height()
	var mat := ShaderMaterial.new()
	mat.shader = MAP_SHADER
	
	var id_tex := ImageTexture.create_from_image(MapManager.id_map_image)
	mat.set_shader_parameter("region_id_map", id_tex)
	mat.set_shader_parameter("state_colors", MapManager.state_color_texture)
	
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH 
	
	noise.frequency = 0.005 
	
	# 3. Add detail (ripples)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.5

	var noise_tex = NoiseTexture2D.new()
	noise_tex.seamless = true
	noise_tex.width = 512     
	noise_tex.height = 512
	noise_tex.noise = noise
	
	await noise_tex.changed
	mat.set_shader_parameter("ocean_noise", noise_tex)
	# ---------------------------------------------
	mat.set_shader_parameter("original_texture", map_sprite.texture)
	mat.set_shader_parameter("sea_speed", 0.01) # Very Slow
	mat.set_shader_parameter("tex_size", Vector2(map_width, MapManager.id_map_image.get_height()))
	mat.set_shader_parameter("country_border_color", Color.BLACK)
	
	map_sprite.material = mat
	
	#_create_ghost_map(Vector2(-map_width, 0), mat)
	#_create_ghost_map(Vector2(map_width, 0), mat)
	for i in [-2, -1, 1, 2]:
		_create_ghost_map(Vector2(i * map_width, 0), mat)

	
	if troop_renderer:
		troop_renderer.map_sprite = map_sprite
		troop_renderer.map_width = map_width
	else:
		push_error("CustomRenderer node not found!")
	
	
	CountryManager.initialize_countries()
	CountryManager.set_player_country("spain")

	for c in ["netherlands", "france", "portugal", "spain", "germany"]:
		var provinces = MapManager.country_to_provinces.get(c, []).duplicate()
		provinces.shuffle()
		var selected_provinces = provinces.slice(0, min(5, provinces.size()))
		for pid in selected_provinces:
			TroopManager.create_troop(c, randi_range(1, 10), pid)
	


func _create_ghost_map(offset: Vector2, p_material: ShaderMaterial) -> void:
	var ghost := Sprite2D.new()
	ghost.texture = map_sprite.texture
	ghost.centered = map_sprite.centered
	ghost.material = p_material
	ghost.position = map_sprite.position + offset
	$MapContainer.add_child(ghost)


func _process(_delta: float) -> void:
	if camera.position.x > map_sprite.position.x + map_width:
		camera.position.x -= map_width
	elif camera.position.x < map_sprite.position.x - map_width:
		camera.position.x += map_width


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and !event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		MapManager.handle_click(get_global_mouse_position(), map_sprite)
	if event is InputEventMouseMotion:
		MapManager.update_hover(get_global_mouse_position(), map_sprite)
