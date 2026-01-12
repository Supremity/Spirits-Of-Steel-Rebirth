# World.gd
extends Node2D
class_name World

@onready var map_sprite: Sprite2D = $MapContainer/CultureSprite as Sprite2D
@onready var camera: Camera2D = $Camera2D as Camera2D
@onready var troop_renderer: CustomRenderer = $MapContainer/CustomRenderer as CustomRenderer

const MAP_SHADER = preload("res://shaders/map_shader.gdshader")

var map_width: float = 0.0
var map_height: float = 0.0

@export var clock: GameClock

var mat: ShaderMaterial


func _enter_tree() -> void:
	GameState.current_world = self


func _ready() -> void:
	await get_tree().process_frame
	TroopManager.troop_selection = $TroopSelection as TroopSelection

	# TODO(pol): Load CountryManager after map instead of an autoload to avoid this.
	clock.hour_passed.connect(CountryManager._on_hour_passed)
	clock.day_passed.connect(CountryManager._on_day_passed)

	MapManager.load_country_data()
	if MapManager.id_map_image != null:
		_on_map_ready()


func _on_map_ready() -> void:
	print("World: Map is ready -> configuring visuals...")
	map_width = MapManager.id_map_image.get_width()
	map_height = MapManager.id_map_image.get_height()
	mat = ShaderMaterial.new()
	mat.shader = MAP_SHADER

	var id_tex := ImageTexture.create_from_image(MapManager.id_map_image)
	mat.set_shader_parameter("region_id_map", id_tex)
	mat.set_shader_parameter("state_colors", MapManager.state_color_texture)

	# Inside World.gd -> _on_map_ready()
	var type_img = Image.create(map_width, map_height, false, Image.FORMAT_L8)

	for y in range(map_height):
		for x in range(map_width):
			var pid = MapManager._get_pid_fast(x, y)
			var province = MapManager.province_objects.get(pid)

			if province:
				if province.type == 0:  # SEA
					type_img.set_pixel(x, y, Color(0, 0, 0))
				else:  # LAND
					type_img.set_pixel(x, y, Color(1, 1, 1))

			elif pid == 1:
				# IT'S A BORDER/GRID LINE: Check neighbors to decide if Land or Sea
				var is_neighbor_land = false

				# Check 4 cardinal neighbors (staying inside image bounds)
				var checks = [
					Vector2i(x + 1, y), Vector2i(x - 1, y), Vector2i(x, y + 1), Vector2i(x, y - 1)
				]
				for pos in checks:
					if pos.x >= 0 and pos.x < map_width and pos.y >= 0 and pos.y < map_height:
						var n_id = MapManager._get_pid_fast(pos.x, pos.y)
						var n_province = MapManager.province_objects.get(n_id)
						# If any neighbor is a Land Province, this border belongs to the Land
						if n_province and n_province.type != 0:
							is_neighbor_land = true
							break

				if is_neighbor_land:
					type_img.set_pixel(x, y, Color(1, 1, 1))  # Treat as Land Border
				else:
					type_img.set_pixel(x, y, Color(0, 0, 0))  # Treat as Sea Grid

	var type_tex = ImageTexture.create_from_image(type_img)
	mat.set_shader_parameter("type_map", type_tex)

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
	mat.set_shader_parameter("sea_speed", 0.00)  # Changed by MainClock
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
	CountryManager.set_player_country("brazil")
	MapManager.force_bidirectional_connections()


func _create_ghost_map(offset: Vector2, p_material: ShaderMaterial) -> void:
	var ghost := Sprite2D.new()
	ghost.texture = map_sprite.texture
	ghost.centered = map_sprite.centered
	ghost.material = p_material
	ghost.position = map_sprite.position + offset
	$MapContainer.add_child(ghost)


var water_offset: Vector2 = Vector2.ZERO


func _process(_delta: float) -> void:
	if camera.position.x > map_sprite.position.x + map_width:
		camera.position.x -= map_width
	elif camera.position.x < map_sprite.position.x - map_width:
		camera.position.x += map_width
	if mat and !clock.paused:
		var move_amount = clock.time_scale * 0.001 * _delta
		water_offset.x += move_amount
		mat.set_shader_parameter("ocean_offset", water_offset)


func _input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and !event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		MapManager.handle_click(get_global_mouse_position(), map_sprite)
	if event is InputEventMouseMotion:
		MapManager.handle_hover(get_global_mouse_position(), map_sprite)
