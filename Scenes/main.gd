extends Node2D
class_name Main


func _ready() -> void:
	GameState.current_world.clock.pause()
	GameState.game_ui._update_flag()
