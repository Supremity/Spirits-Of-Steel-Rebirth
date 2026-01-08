extends Node


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_sfx_changed(value: float) -> void:
	MusicManager.set_sfx_volume(value)


func _on_music_changed(value: float) -> void:
	MusicManager.set_music_volume(value)


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_packed(preload("res://Scenes/world.tscn"))


func _on_settings_pressed() -> void:
	$"/root/Main Menu/Settings".visible = true


func _on_exit_settings_pressed() -> void:
	$"/root/Main Menu/Settings".visible = false


func _on_credits_pressed() -> void:
	$"/root/Main Menu/Credits".visible = true


func _on_exit_credits_pressed() -> void:
	$"/root/Main Menu/Credits".visible = false
