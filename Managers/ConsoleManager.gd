extends Node

func m_GatesOfHell() -> void:
	var sizer: int = CountryManager.countryNames.size()
	for countryA: int in range(sizer):
		for countryB: int in range(countryA, sizer):
			m_StartWarSilent(CountryManager.countryNames[countryA], CountryManager.countryNames[countryB])

func m_Editor() -> void:
	print("Current Scene: %d" % SceneSwitcher._current_type)
	if SceneSwitcher._current_type == SceneSwitcher.Type.WORLD:
		SceneSwitcher.switch_to(SceneSwitcher.Type.EDITOR)
	elif SceneSwitcher._current_type == SceneSwitcher.Type.EDITOR:
		SceneSwitcher.switch_to(SceneSwitcher.Type.WORLD)
	
func _ready() -> void:
	Console.add_command("play_country", _play_country, ["country_name"], 1, "Change player country")
	# Console.add_command("play_as", _play_country, ["country_name"], 1, "Change player country")
	# Console.add_command_autocomplete_list("play_as", CountryManager.)
	# Console.add_command("play", _play_country, ["country_name"], 1, "Change player country")
	Console.add_command("tag", _play_country, ["country_name"], 1, "Change player country")
	Console.add_command("drew_durnil_mode", _drew_durnil_mode, [], 0, "Lets u spectate the map")
	Console.add_command("access", m_AddAccess, ["accesser", "accessee"], 1, "Add military access to a country")
	Console.add_command("puppet", _puppet_country, ["country_name"], 1, "Change player country")
	Console.add_command("invite", _invite_country, ["country_name"], 1, "Change player country")
	Console.add_command("debug_decisions", _debug_decisions, [], 0, "Lets u do any focus and does it instantly")
	Console.add_command("set_ideology", _set_ideology, ["x", "y"], 2, "Change player ideology")
	Console.add_command("reload_decisions", _reload_decisions, [], 0, "Reloads all the decision trees")
	Console.add_command("instabuild", _instabuild, [], 0, "Toggles instant construction")

	Console.add_command("gates_of_hell", m_GatesOfHell, [], 0, "Start armageddon")
	Console.add_command("start_war", _start_war, ["a", "b"], 2, "Start a war between 2 countries")
	Console.add_command("annex", _annex, ["annexer", "annexee"], 2, "Annex Country for Player")
	Console.add_command("pp", _add_pp, ["amount"], 1, "Add Poltical power to player")
	Console.add_command("manpower", _add_manpower, ["amount"], 1, "Add Manpower to Country")
	Console.add_command(
		"set_manpower", _set_manpower, ["amount"], 1, "Sets manpower to a specific amount"
	)
	Console.add_command(
		"peace_treaty", _peace_treaty, ["country"], 1, "Spawns a peace treaty with country"
	)
	# TODO: Rework this.
	Console.add_command(
		"release", _release_country, ["country"], 1, "Releases a country based on all its claims; the country must exist, to create a new country, look to instantiate_country"
	)
	Console.add_command(
		"releasables", _show_releasables_country, ["country"], 1, "Shows the releasables of a country"
	)
	Console.add_command(
		"cta", _call_to_arms, ["caller", "target"], 2, "Call a country to arms"
	)
	Console.add_command("editor", m_Editor, [], 0, "Swap Editor")
	Console.add_command("sink_rise", _sink_rise, ["pid", "type", "country_name"], 3, "sink/rise province")
	Console.add_command("random_figure", m_RandomFigure, ["country", "budget"], 2, "Add a randomly generated significant figure to a country.")
	Console.add_command("start_revolution", m_StartRevolution, ["pid", "name", "count"], 3, "Start a revolution.")
	Console.add_command("start_rebellion", m_StartRebellion, ["country", "count"], 2, "Start a multi front rebellion.")
	Console.add_command("partition_country", m_PartitionCountry, ["country", "count"], 2, "Evenly partition a country into X parts.")
	Console.add_command("set_attr", _set_attr, ["country", "attr", "val"], 3, "Sets the atribute of a country")
	Console.add_command_autocomplete_list("tag", CountryManager.countryNames)
	Console.add_command_autocomplete_list("annex", CountryManager.countryNames)

var suffixes: Array[String] = [
	"Diege",
	"Rebellion",
	"Revolution",
	"Revolutioniary_Army",
	"Army",
	"Republic",
	"Reich",
	"Dominion",
	"Kingdom",
	"Empire",
	"Duchy",
]

var prefixes: Array[String] = [
	"Independent",
	"Islamic",
	"Christian",
	"Hindu",
	"Anarchist",
	"Revolutionary",
	"Democratic",
	"Fascist",
	"Divine",
]

func m_StartRebellion(a_country, a_count) -> void:
	var parent_country: CountryData = CountryManager.countries[a_country]
	var city_ids: Array = MapManager.country_to_cities[a_country].duplicate()
	var num_rebels: int = mini(int(a_count), city_ids.size())
	
	if num_rebels <= 0:
		Console.print_line("No cities found in " + a_country + " to start rebellion.")
		return

	var seeds: Array[int] = []
	var names: Array[String] = []
	
	city_ids.shuffle()
	for i: int in range(num_rebels):
		var city_id: int = city_ids.pop_back()
		seeds.append(city_id)
		
		var city_name: String = MapManager.province_objects[city_id].city
		match randi_range(0, 2):
			0: 
				city_name = prefixes.pick_random() + "_" + name
			1: 
				city_name = prefixes.pick_random() + "_" + name + "_" + suffixes.pick_random()
			2: 
				city_name = name + "_" + suffixes.pick_random()
		names.append(city_name)
	
	var total_provinces: int = MapManager.country_to_provinces[a_country].size()
	@warning_ignore("integer_division")
	var target_per_rebel: int = total_provinces / (num_rebels + 1)
	
	var rebels: Array[CountryData] = MultiFill(seeds, names, target_per_rebel * num_rebels)
	
	for rebel in rebels:
		WarManager.declare_war(parent_country, rebel)
	
	for i: int in range(rebels.size()):
		for j: int in range(i + 1, rebels.size()):
			WarManager.declare_war(rebels[i], rebels[j])

func m_PartitionCountry(a_country, a_count) -> void:
	if !CountryManager.countries.has(a_country):
		Console.print_line("Unknown country: " + a_country)
		return
		
	var num_parts: int = int(a_count)
	if num_parts <= 1:
		Console.print_line("Parts must be > 1")
		return

	var country_provinces: Array = MapManager.country_to_provinces[a_country]
	var city_ids: Array = MapManager.country_to_cities[a_country].duplicate()
	
	var seeds: Array[int] = []
	var names: Array[String] = []
	
	city_ids.shuffle()
	while seeds.size() < num_parts && city_ids.size() > 0:
		seeds.append(city_ids.pop_back())
	
	if seeds.size() < num_parts:
		var available = country_provinces.duplicate()
		available.shuffle()
		while seeds.size() < num_parts && available.size() > 0:
			var p = available.pop_back()
			if p not in seeds:
				seeds.append(p)
	
	for i: int in range(seeds.size()):
		names.append(a_country + "_" + str(i + 1))
		
	MultiFill(seeds, names, country_provinces.size())
	

func m_StartRevolution(a_pid, a_name, a_count) -> void:
	var	country: String = MapManager.province_objects[int(a_pid)].country
	QuickFill(int(a_pid), a_name, int(a_count))
	WarManager.declare_war(CountryManager.countries[a_name], CountryManager.countries[country])
	MapManager.allow_pids(CountryManager.countries[a_name], CountryManager.countries[country])

func QuickFill(a_pid, a_name, a_count) -> CountryData:
	var results = MultiFill([a_pid], [a_name], a_count)
	return results[0] if results.size() > 0 else null

func MultiFill(a_seeds: Array[int], a_names: Array[String], a_total_count: int) -> Array[CountryData]:
	if a_seeds.is_empty():
		return []
		
	var parent_country_name: String = MapManager.province_objects[a_seeds[0]].country
	var results: Array[CountryData] = []
	
	var assignments: Array[Array] = []
	var frontiers: Array[Array] = []
	var all_taken: Dictionary = {}
	
	for i: int in range(a_seeds.size()):
		assignments.append([a_seeds[i]])
		all_taken[a_seeds[i]] = true
		
		var frontier: Array[int] = []
		for opt: int in MapManager.province_graph.get_point_connections(a_seeds[i]):
			if MapManager.province_objects[opt].country == parent_country_name && opt not in all_taken:
				frontier.append(opt)
		frontiers.append(frontier)
		
	var remaining_count: int = a_total_count - a_seeds.size()
	var tries: int = a_total_count * 2
	
	while remaining_count > 0 && tries > 0:
		tries -= 1
		var expanded_any: bool = false
		
		for i: int in range(a_seeds.size()):
			if remaining_count <= 0: break
			
			var frontier = frontiers[i]
			if frontier.is_empty():
				continue
				
			var choice_idx: int = randi() % frontier.size()
			var choice: int = frontier[choice_idx]
			frontier.remove_at(choice_idx)
			
			if choice in all_taken:
				continue
				
			assignments[i].append(choice)
			all_taken[choice] = true
			remaining_count -= 1
			expanded_any = true
			
			for opt: int in MapManager.province_graph.get_point_connections(choice):
				if MapManager.province_objects[opt].country == parent_country_name && opt not in all_taken && opt not in frontier:
					frontier.append(opt)
					
		if !expanded_any:
			break
			
	# Instantiate countries
	for i: int in range(a_seeds.size()):
		var country = MapManager.InstantiateCountryFromProvinces({
			"name": a_names[i],
			"color": "#"+Color(randf(), randf(), randf()).to_html(false).to_upper(),
			"money": 10000,
			"ideology": [0, 0],
			"political_power": 100,
			"stability": 0.5,
			"war_support": 1.5,
			"puppets": [],
			"accepted_cultures": [],
			"hostedGovernments": [],
			"figures": [],
		}, assignments[i])
		results.append(country)
		
	return results

func m_RandomFigure(country, budget) -> void:
	var figure: ImportantFigure = ImportantFigure.FromRandom(country, int(budget))
	Console.print_info("%s %s" % [country, figure.name])
	print("%s %s" % [country, figure.name])
	MapManager.significantFigures[figure.name] = figure 
	CountryManager.countries[country].figures.append(figure.name)

func _show_releasables_country(country):
	var releasables = MapManager.get_all_releasables(country).map(func(x): return x.country)
	Console.print_info(JSON.stringify(releasables))


func _release_country(country):
	MapManager.ReleaseCountry(country)


func _add_pp(amount):
	CountryManager.player_country.political_power += float(amount)


func _set_ideology(x, y):
	CountryManager.player_country.ideology = Vector2(int(x), int(y))


func _add_manpower(amount):
	CountryManager.player_country.manpower += int(amount)


func _set_manpower(amount):
	CountryManager.player_country.manpower = int(amount)


func _peace_treaty(country):
	WarManager._handle_total_collapse(country, CountryManager.player_country.country_name)


func _annex(annexer: String, annexee) -> void:
	if CountryManager.countries.has(annexee):
		MapManager.annex_country(annexer, annexee)
		CountryManager.cleanup_empty_countries()
		return

	Console.print_line("Unknown country: " + annexee)


func _play_country(country_name: String) -> void:
	if CountryManager.countries.has(country_name):
		CountryManager.set_player_country(country_name)
		return

	Console.print_line("Unknown country: " + country_name)


func _start_war(country_name1: String, country_name2: String) -> void:
	var country1: CountryData = CountryManager.countries.get(country_name1)
	var country2: CountryData = CountryManager.countries.get(country_name2)

	if country1 and country2:
		WarManager.declare_war(country1, country2)
		return

	if not country1:
		Console.print_line("Unknown country: " + country_name1)
	if not country2:
		Console.print_line("Unknown country: " + country_name2)

func m_AddAccess(country_name1: String, country_name2: String) -> void:
	var country1: CountryData = CountryManager.countries.get(country_name1)

	if country1 && !country_name2 in country1.allowedCountries:
		country1.allowedCountries.append(country_name2)
		return

	if !country1:
		Console.print_line("Unknown country: " + country_name1)
	if !country_name2 in CountryManager.countries:
		Console.print_line("Unknown country: " + country_name2)

func m_StartWarSilent(country_name1: String, country_name2: String) -> void:
	var country1: CountryData = CountryManager.countries.get(country_name1)
	var country2: CountryData = CountryManager.countries.get(country_name2)

	if country1 and country2:
		WarManager.declare_war(country1, country2, true)
		return

	if not country1:
		Console.print_line("Unknown country: " + country_name1)
	if not country2:
		Console.print_line("Unknown country: " + country_name2)

func _call_to_arms(caller_name: String, target_name: String) -> void:
	var caller: CountryData = CountryManager.countries.get(caller_name)
	var target: CountryData = CountryManager.countries.get(target_name)

	if caller and target:
		WarManager.call_to_arms(caller, target)
		return

	if not caller:
		Console.print_line("Unknown country: " + caller_name)
	if not target:
		Console.print_line("Unknown country: " + target_name)

func _reload_decisions():
	DecisionManager._load_decisions("res://starts/"+GameState.current_start+"/decisions/")

func _debug_decisions():
	DecisionManager.debug = !DecisionManager.debug


func _puppet_country(country_name: String):
	CountryManager.make_puppet(CountryManager.player_country, CountryManager.countries[country_name])


func _invite_country(country_name: String):
	FactionManager.invite_faction(CountryManager.player_country, CountryManager.countries[country_name])


func _drew_durnil_mode():
	CountryManager.player_country.is_player = false
	#CountryManager.player_country.ai_controller = CountryAI.new(CountryManager.player_country)


func _instabuild():
	GameState.instabuild = !GameState.instabuild
	Console.print_line("Instabuild: " + str(GameState.instabuild))


func _sink_rise(pid, type, country_name: String):
	print("skibidi")
	MapManager.change_province_types([int(pid)], int(type), country_name)


func _set_attr(country: String, attr: String, val: Variant):
	CountryManager.countries[country][attr] = val
