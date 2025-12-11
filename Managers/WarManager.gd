extends Node

const BATTLE_TICK := 1.0

var wars := {} 
var active_battles := []
var time_scale := 1.0

class Battle:
	var attacker_id: int
	var defender_id: int
	var timer := 0.0
	var manager
	var position: Vector2 # Place where we can draw the battle icon stuff (maybe numbers like hoi4 later)

	func _init(atk_id: int, def_id: int, position: Vector2, m):
		self.attacker_id = atk_id
		self.defender_id = def_id
		self.position = position
		manager = m

	func tick(delta: float):
		timer += delta
		if timer >= BATTLE_TICK:
			timer -= BATTLE_TICK
			_do_round()

	func _do_round():
		pass
		#print("Tick at battle between %d and %d" % [attacker_id, defender_id])


func _ready():
	if MainClock:
		time_scale = MainClock.time_scale
		MainClock.time_scale_changed.connect(_on_time_scale_changed)
	if MainClock:
		MainClock.hour_passed.connect(_on_ai_tick)


func _on_time_scale_changed(new_scale: float):
	time_scale = new_scale


func _process(delta: float):
	if active_battles.is_empty(): return
	var scaled = delta * time_scale
	for battle in active_battles:
		battle.tick(scaled)


func start_battle(attacker_id: int, defender_id: int):
	var midpoint = get_province_midpoint(attacker_id, defender_id)
	active_battles.append(Battle.new(attacker_id, defender_id, midpoint, self))
	print ("BATTLE STARTED BETWEEN %s" % [str(attacker_id), str(defender_id)])

func end_battle(battle: Battle):
	active_battles.erase(battle)


func _on_ai_tick(_h := 0):
	pass
	
	
func _ensure_country_entry(c: CountryData):
	if not wars.has(c):
		wars[c] = {}

func declare_war(a: CountryData, b: CountryData) -> void:
	add_war_silent(a, b)
	PopupManager.show_alert("war", a, b)
	MusicManager.play_sfx(MusicManager.SFX.DECLARE_WAR)
	MusicManager.play_music(MusicManager.MUSIC.BATTLE_THEME)

func end_war(a: CountryData, b: CountryData) -> void:
	if not is_at_war(a, b): return
	wars[a].erase(b)
	wars[b].erase(a)
	if wars[a].empty(): wars.erase(a)
	if wars[b].empty(): wars.erase(b)
	a.allowedCountries.erase(b.name)
	b.allowedCountries.erase(a.name)

func is_at_war(a: CountryData, b: CountryData) -> bool:
	return wars.has(a) and wars[a].has(b)

func get_enemies(country: CountryData) -> Array:
	if wars.has(country):
		return wars[country].keys()
	return []

func add_war_silent(a: CountryData, b: CountryData) -> void:
	if a == b or is_at_war(a, b): return
	_ensure_country_entry(a)
	_ensure_country_entry(b)
	wars[a][b] = true
	wars[b][a] = true
	a.allowedCountries.append(b.name)
	b.allowedCountries.append(a.name)

func remove_war_silent(a: CountryData, b: CountryData) -> void:
	if not is_at_war(a, b): return
	wars[a].erase(b)
	wars[b].erase(a)
	if wars[a].empty(): wars.erase(a)
	if wars[b].empty(): wars.erase(b)
	a.allowedCountries.erase(b.name)
	b.allowedCountries.erase(a.name)



func _update_map_ownership(pid: int, new_owner: String) -> void:
	var old_owner = MapManager.province_to_country.get(pid)
	if MapManager.country_to_provinces.has(old_owner):
		MapManager.country_to_provinces[old_owner].erase(pid)

	MapManager.province_to_country[pid] = new_owner
	if not MapManager.country_to_provinces.has(new_owner):
		MapManager.country_to_provinces[new_owner] = []
	MapManager.country_to_provinces[new_owner].append(pid)

	MapManager.update_province_color(pid, new_owner)

func get_province_midpoint(pid1: int, pid2: int) -> Vector2:
	var center1: Vector2 = MapManager.province_centers.get(pid1, Vector2.ZERO)
	var center2: Vector2 = MapManager.province_centers.get(pid2, Vector2.ZERO)
	return (center1 + center2) * 0.5
