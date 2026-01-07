extends Node

var music_player: AudioStreamPlayer

enum SFX {
	TROOP_MOVE,
	TROOP_SELECTED,
	BATTLE_START,
	OPEN_MENU,
	DECLARE_WAR,
	HOVERED,
	CLOSE_MENU,
}

enum MUSIC {
	MAIN_THEME,
	BATTLE_THEME
}

var sfx_volume_map = {
	SFX.TROOP_MOVE: 0.1,
	SFX.TROOP_SELECTED: 1.6,
	SFX.BATTLE_START: 0.8,
	SFX.OPEN_MENU: 0.5,
	SFX.CLOSE_MENU: 0.5,
	SFX.DECLARE_WAR: 0.9,
	SFX.HOVERED: 0.3
}

var music_volume_map = {
	MUSIC.MAIN_THEME: 0.4,
	MUSIC.BATTLE_THEME: 0.5
}

var sfx_map = {
	SFX.TROOP_MOVE: preload("res://assets/snd/moveDivSound.mp3"),
	SFX.TROOP_SELECTED: preload("res://assets/snd/selectDivSound.mp3"),
	SFX.OPEN_MENU: preload("res://assets/snd/openMenuSound.mp3"),
	SFX.CLOSE_MENU: preload("res://assets/snd/closeMenuSound.mp3"),
	SFX.DECLARE_WAR: preload("res://assets/snd/declareWarSound.mp3"),
	SFX.HOVERED: preload("res://assets/snd/hoveredSound.mp3")
}

var music_map = {
	MUSIC.MAIN_THEME: [],
	MUSIC.BATTLE_THEME: []
	# MUSIC.BATTLE_THEME: preload("res://assets/music/battle_theme.ogg")
}

var sfx_players: Array[AudioStreamPlayer] = []

const gameMusic = "res://assets/music/gameMusic"
const warMusic = "res://assets/music/warMusic"

func load_music(Music):
	for song in DirAccess.open(Music).get_files():
		if song.get_extension() != "import":
			music_map[MUSIC.MAIN_THEME].append(load(Music + "/" + song))

func _ready():
	# Music player

	load_music(gameMusic)
	load_music(warMusic)

	print(music_map)

	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.bus = "Music"
	
	# SFX Players Pool (8 players for overlapping sounds
	for i in 8:
		var player = AudioStreamPlayer.new()
		add_child(player)
		player.bus = "SFX"
		sfx_players.append(player)
	play_music(MUSIC.MAIN_THEME)


func play_sfx(sfx: int):
	if sfx not in sfx_map:
		return
	
	var player = null
	for p in sfx_players:
		if not p.playing:
			player = p
			break
	
	if not player:
		player = sfx_players[0]
	
	player.stream = sfx_map[sfx]
	player.volume_db = linear_to_db(sfx_volume_map.get(sfx, 1.0))
	player.play()


func play_music(track: int):
	if track not in music_map:
		return
	
	music_player.stream = music_map[track].pick_random()
	music_player.volume_db = linear_to_db(music_volume_map.get(track, 1.0))  # Apply track-specific volume
	music_player.play()


# *** BONUS: Stop all SFX ***
func stop_all_sfx():
	for player in sfx_players:
		player.stop()


# *** BONUS: Fade out music ***
func fade_out_music(duration: float = 1.0):
	var tween = create_tween()
	tween.tween_method(set_music_volume, 1.0, 0.0, duration)
	await tween.finished
	music_player.stop()


func set_music_volume(volume: float):
	music_player.volume_db = linear_to_db(volume)
