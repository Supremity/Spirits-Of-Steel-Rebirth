extends Node

enum Type {MENU, WORLD, EDITOR, SELECT_COUNTRY}

const SCENE_MAP = {
	Type.MENU: "res://Scenes/main_menu.tscn",
	Type.WORLD: "res://Scenes/world.tscn",
	Type.EDITOR: "res://Scenes/MapEditor.tscn",
	Type.SELECT_COUNTRY: "res://Scenes/select_country.tscn"
}


var _world_cache: Node = null # We only care about saving this one
var _current_type: int = -1
var _loading_screen: Node = null

func _ready() -> void:
	# Instantiate loading screen and add it as a sibling of CurrentScene's parent (Main)
	# or just add it to the scene tree root to be persistent
	var ls_scene = preload("res://Scenes/LoadingScreen.tscn")
	if ls_scene:
		_loading_screen = ls_scene.instantiate()
		add_child(_loading_screen)

func has_active_world() -> bool:
	return is_instance_valid(_world_cache)
	
func is_world_active() -> bool:
	return _current_type == Type.WORLD

func switch_to(scene_type: Type, init_callback: Callable = Callable()) -> void:
	if scene_type == _current_type: return
		
	if _loading_screen:
		_loading_screen.show_screen()
		_loading_screen.set_progress(0)

	# Small delay to ensure loading screen is visible
	await get_tree().create_timer(0.1).timeout

	var main := get_tree().current_scene
	var container := main.get_node("CurrentScene")
	
	# 1. Handle the scene we are LEAVING
	if container.get_child_count() > 0:
		var old_scene = container.get_child(0)
		if _current_type == Type.WORLD:
			container.remove_child(old_scene)
		else:
			old_scene.queue_free()

	# 2. Handle the scene we are ENTERING
	var next_scene: Node
	var progress = []
	
	if scene_type == Type.WORLD and _world_cache:
		next_scene = _world_cache
		if _loading_screen: _loading_screen.set_progress(1.0)
	else:
		var path = SCENE_MAP.get(scene_type)
		ResourceLoader.load_threaded_request(path)
		
		while true:
			match ResourceLoader.load_threaded_get_status(path, progress):
				ResourceLoader.THREAD_LOAD_LOADED:
					break
				ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					if _loading_screen:
						_loading_screen.set_progress(progress[0])
				_:
					push_error("Failed to load scene: " + path)
					break
			await get_tree().process_frame
		
		var packed_scene = ResourceLoader.load_threaded_get(path)
		next_scene = packed_scene.instantiate()
		if scene_type == Type.WORLD:
			_world_cache = next_scene

	# 2.5 Execute initialization callback if provided
	if init_callback.is_valid():
		progress = [0.0]
		var bongo: Thread = Thread.new()
		bongo.start(init_callback.bind(progress))

		#print("Buz")
		while bongo.is_alive():
			#print("Prae")
			if progress[0]:
				_loading_screen.set_progress(progress[0])
			#print("Schlung: %d" % progress[0])
			await get_tree().process_frame
			#print("Post")
		#print("Biz")

		bongo.wait_to_finish()

	# 3. Add to tree
	if next_scene:
		container.add_child(next_scene)
		if _current_type == Type.MENU && scene_type == Type.WORLD:
			progress = [0]
			var bingo: Thread = Thread.new()
			bingo.start(next_scene.DoSetup.bind(progress))
			
			while bingo.is_alive():
				if progress.size() <= 0:
					progress = [0]
				_loading_screen.set_progress(progress[0])
				await get_tree().process_frame

			bingo.wait_to_finish()
		elif scene_type == Type.EDITOR:
			GameState.current_world.clock.pause()
		elif _current_type == Type.WORLD:
			GameState.tooltip.shouldBeVisible = false
		_current_type = scene_type

	if _loading_screen:
		_loading_screen.set_progress(1.0)
		await get_tree().create_timer(0.2).timeout # Stay at 100% briefly
		_loading_screen.hide_screen()

func _instantiate_by_type(type: Type) -> Node:
	var path = SCENE_MAP.get(type)
	var packed_scene = load(path)
	return packed_scene.instantiate() if packed_scene else null
