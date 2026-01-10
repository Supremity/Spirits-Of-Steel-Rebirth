extends Node
class_name GameClock

signal hour_passed
signal day_passed

@export var hours_per_tick := 1  # How many in-game hours pass per tick
@export var seconds_per_tick := 1.0  # Real seconds per tick

@export var start_year := 2010
@export var start_month := 1  # 1-12
@export var start_day := 1  # 1-31
@export var start_hour := 0

var time_scale := MIN_SPEED
const MIN_SPEED := 0
const MAX_SPEED := 75.0

var hour: int = start_hour
var date_dict: Dictionary = {"year": start_year, "month": start_month, "day": start_day}
var accumulated_time: float = 0.0

var paused: bool


func _ready() -> void:
	pause()


func _process(delta: float) -> void:
	if paused:
		return

	accumulated_time += delta * time_scale
	while accumulated_time >= seconds_per_tick:
		accumulated_time -= seconds_per_tick
		_tick_hour()


func _tick_hour() -> void:
	hour += hours_per_tick
	hour_passed.emit()

	var date_dict_as_unix_time: int = Time.get_unix_time_from_datetime_dict(date_dict)
	while hour >= 24:
		hour -= 24
		date_dict_as_unix_time += (24 * 60 * 60)
		day_passed.emit()

	date_dict = Time.get_datetime_dict_from_unix_time(date_dict_as_unix_time)


func get_time_string() -> String:
	return "%02d:00" % hour


func get_date_string() -> String:
	return "%04d-%02d-%02d" % [date_dict.year, date_dict.month, date_dict.day]


func get_datetime_string() -> String:
	return "%s %s" % [get_time_string(), get_date_string()]


func set_speed(scale: float) -> void:
	time_scale = clamp(scale, MIN_SPEED, MAX_SPEED)
	GameState.game_ui.updateProgressBar()
	if time_scale <= 0:
		pause()


func decrease_speed():
	set_speed(time_scale - 15)


func increase_speed():
	set_speed(time_scale + 15)
	if paused:
		resume()


func pause() -> void:
	paused = true
	GameState.game_ui.updateProgressBar()


func resume() -> void:
	paused = false
	GameState.game_ui.updateProgressBar()


func toggle_pause() -> void:
	if time_scale == 0:
		return
	if paused:
		resume()
	else:
		pause()
	GameState.game_ui.updateProgressBar()
