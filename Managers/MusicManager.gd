extends Node

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []

var current_track_type: int = -1

# --- Enums ---
enum SFX {
	TROOP_MOVE, TROOP_SELECTED, BATTLE_START, OPEN_MENU, DECLARE_WAR, HOVERED, CLOSE_MENU, GAME_OVER
}

enum MUSIC { MAIN_THEME, BATTLE_THEME }

const gameMusic = "res://assets/music/gameMusic"
const warMusic = "res://assets/music/warMusic"

var sfx_map = {
	SFX.TROOP_MOVE: preload("res://assets/snd/moveDivSound.mp3"),
	SFX.TROOP_SELECTED: preload("res://assets/snd/selectDivSound.mp3"),
	SFX.OPEN_MENU: preload("res://assets/snd/openMenuSound.mp3"),
	SFX.CLOSE_MENU: preload("res://assets/snd/closeMenuSound.mp3"),
	SFX.DECLARE_WAR: preload("res://assets/snd/declareWarSound.mp3"),
	SFX.HOVERED: preload("res://assets/snd/hoveredSound.mp3"),
	SFX.GAME_OVER: preload("res://assets/snd/endGameSound.mp3")
}

var sfx_volume_map = {
	SFX.TROOP_MOVE: 0.1,
	SFX.TROOP_SELECTED: 1.6,
	SFX.BATTLE_START: 0.8,
	SFX.OPEN_MENU: 0.5,
	SFX.CLOSE_MENU: 0.5,
	SFX.DECLARE_WAR: 0.9,
	SFX.HOVERED: 0.3,
	SFX.GAME_OVER: 0.5
}

var music_map = {MUSIC.MAIN_THEME: [], MUSIC.BATTLE_THEME: []}

var music_volume_map = {MUSIC.MAIN_THEME: 0.4, MUSIC.BATTLE_THEME: 0.5}


func _ready():
	_load_music_folder(gameMusic, MUSIC.MAIN_THEME)
	_load_music_folder(warMusic, MUSIC.BATTLE_THEME)

	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.finished.connect(_on_music_finished)
	add_child(music_player)

	for i in 8:
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		sfx_players.append(p)

	play_music(MUSIC.MAIN_THEME)


func _load_music_folder(path: String, track_enum: int):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and not file_name.ends_with(".import"):
				var full_path = path + "/" + file_name
				var stream = load(full_path)
				if stream:
					music_map[track_enum].append(stream)
			file_name = dir.get_next()


# --- Music Logic ---


func play_music(track: int):
	# 1. Safety check for empty folders
	if not music_map.has(track) or music_map[track].is_empty():
		return

	if current_track_type == track and music_player.playing:
		return

	current_track_type = track

	music_player.stream = music_map[track].pick_random()
	music_player.volume_db = linear_to_db(music_volume_map.get(track, 1.0))
	music_player.play()


func _on_music_finished():
	var temp_type = current_track_type
	current_track_type = -1
	play_music(temp_type)


func fade_out_music(duration: float = 1.0):
	var tween = create_tween()
	tween.tween_property(music_player, "volume_db", -80.0, duration)
	await tween.finished
	music_player.stop()
	current_track_type = -1


# --- SFX Logic ---


func play_sfx(sfx: int):
	if sfx not in sfx_map:
		return
	var player = sfx_players.filter(func(p): return not p.playing).front()
	if not player:
		player = sfx_players[0]

	player.stream = sfx_map[sfx]
	player.volume_db = linear_to_db(sfx_volume_map.get(sfx, 1.0))
	player.play()


func stop_all_sfx():
	for p in sfx_players:
		p.stop()


func set_music_volume(volume_linear: float):
	music_player.volume_db = linear_to_db(volume_linear)


func set_sfx_volume(volume_linear: float):
	for p in sfx_players:
		p.volume_db = linear_to_db(volume_linear)
