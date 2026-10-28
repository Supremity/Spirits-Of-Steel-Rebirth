extends Node
# Autoload Name: DecisionManager

const ROOT_DEFAULT_PATH := "res://decisions/default.json"

var default_categories: Dictionary = {}
var country_decisions_map: Dictionary = {} # { "China": { "Economy": [...] } }
var country_file_paths: Dictionary = {} # { "Germany": "res://starts/ModernDay/decisions/Germany.json" }
var current_base_path: String = "" # Decisions folder of the loaded start

var active_decisions: Dictionary = {} # { "Germany": { "eco_1": 5 } }
var ui_overlay = null
var debug = false


# Decisions are only loaded from a start's folder (see StartEntry / World).
func load_decisions_from_path(base_path: String):
	_load_decisions(base_path)


func _load_decisions(base_path: String):
	if not base_path.ends_with("/"):
		base_path += "/"
	current_base_path = base_path

	# Clear existing data before loading new ones
	default_categories.clear()
	country_decisions_map.clear()
	country_file_paths.clear()

	# 1. Load Default: start's default.json, else the root default.json
	var default_path = base_path + "default.json"
	if not FileAccess.file_exists(default_path):
		default_path = ROOT_DEFAULT_PATH
	var default_json = _read_json(default_path)
	if default_json is Dictionary:
		default_categories = default_json.get("categories", {})
		country_file_paths["_default"] = default_path

	# 2. Load Country Specific
	var dir = DirAccess.open(base_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json") \
			and file_name != "default.json":
			var country_key = file_name.trim_suffix(".json")
			var json = _read_json(base_path + file_name)
			if json is Dictionary and json.has("categories"):
				country_decisions_map[country_key] = json["categories"]
				country_file_paths[country_key] = base_path + file_name
		file_name = dir.get_next()
	dir.list_dir_end()


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var text = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	return JSON.parse_string(text)


func get_country_categories(country_name: String) -> Dictionary:
	return country_decisions_map.get(country_name, default_categories)


func get_country_categories_editable(country_name: String) -> Dictionary:
	if not country_decisions_map.has(country_name):
		# Create a deep copy of default categories for this country
		var copied_cats = {}
		for cat_name in default_categories.keys():
			copied_cats[cat_name] = default_categories[cat_name].duplicate(true)
		country_decisions_map[country_name] = copied_cats

		# New country trees are saved next to the start's other decisions
		if not country_file_paths.has(country_name):
			country_file_paths[country_name] = current_base_path + country_name + ".json"

	return country_decisions_map[country_name]


# --- TICKING SYSTEM ---
func process_country_day(country: CountryData):
	if not active_decisions.has(country.country_name):
		return

	var tasks = active_decisions[country.country_name]
	var finished = []

	for key in tasks.keys():
		tasks[key] -= 1
		if (tasks[key] <= 0) || debug:
			finished.append(key)
			_finalize_decision(country, key)

	for key in finished:
		if country == CountryManager.player_country:
			# 1. Find the decision data to get the title
			var decision_title = "Unknown Decision"
			var country_cats = get_country_categories(country.country_name)

			# Look through all categories to find the matching ID
			for cat in country_cats.values():
				for decision in cat:
					if decision["id"] == key:
						decision_title = decision["title"]
						break

			# 2. Show the alert with the actual title
			EventManager.show_alert(
				{
					"event": "default",
					"c1": country,
					"text": "%s completed" % decision_title
				}
			)

		tasks.erase(key)

	if ui_overlay and ui_overlay.visible and country.is_player:
		ui_overlay.refresh_status_only() # Efficient refresh


# --- ACTIONS ---
func can_take_decision(country: CountryData, cat: String, index: int) -> bool:
	var data = get_country_categories(country.country_name)[cat][index]
	var id = data["id"]
	if debug: return true

	# 1. NEW: Check if busy with ANY decision
	if is_country_busy(country):
		return false

	# 2. Check if already done or currently this specific one (redundant but safe)
	if country.has_meta("finished_" + id) or is_in_progress(country, id):
		return false

	# 3. Check Prerequisite
	if data.has("prereq"):
		var parent_id = data["prereq"]
		if not country.has_meta("finished_" + parent_id):
			return false

	# 3.5 Check Mutually Exclusive
	if data.has("exclusive"):
		var exclusives = data["exclusive"]
		if not exclusives is Array:
			exclusives = [exclusives]
		for ex_id in exclusives:
			if country.has_meta("finished_" + ex_id) or is_in_progress(country, ex_id):
				return false

	# 4. Check Cost
	if country.political_power < data.get("cost_pp", 0):
		return false

	# 5. Check Cost
	var reqs = data.get("reqs", "")
	if reqs:
		for req in reqs:
			if !InterpreterManager.get_function(reqs):
				return false
	return true


func start_decision(country: CountryData, cat: String, index: int):
	if not can_take_decision(country, cat, index):
		return

	var data = get_country_categories(country.country_name)[cat][index]
	country.political_power -= data.get("cost_pp", 0)

	if not active_decisions.has(country.country_name):
		active_decisions[country.country_name] = {}

	active_decisions[country.country_name][data["id"]] = data.get("days", 5)

	if debug:
		process_country_day(country)

	if ui_overlay and country.is_player:
		ui_overlay.refresh_status_only()


func _finalize_decision(country: CountryData, id: String):
	country.finished_decisions.append(id)
	country.set_meta("finished_" + id.replace("#","_"), true)

	# Find the data to get the action (Slow search, but happens rarely)
	for cat in get_country_categories(country.country_name).values():
		for node in cat:
			if node["id"] == id:
				_apply_reward(country, node.get("action", {}))
				return

func _apply_reward(country: CountryData, action):
	InterpreterManager.get_function(action, country)

# --- HELPERS ---
func is_in_progress(country: CountryData, id: String) -> bool:
	return active_decisions.get(country.country_name, {}).has(id)


func get_days_left(country: CountryData, id: String) -> int:
	return active_decisions.get(country.country_name, {}).get(id, 0)


# Add/Update these functions in DecisionManager.gd


# Check if the country has ANY active timers
func is_country_busy(country: CountryData) -> bool:
	return !active_decisions.get(country.country_name, {}).is_empty()

func has_available_decisions(country: CountryData) -> bool:
	var categories: Dictionary = get_country_categories(country.country_name)
	var choices: Array = []
	for cat in categories.keys():
		var decisions = categories[cat]
		for i in range(decisions.size()):
			if can_take_decision(country, cat, i):
				if country.is_player:
					return true
				choices.append([country, cat, i])
	if choices.is_empty():
		print("No available decisions for %s" % country.country_name)
		return false
	var choice = choices.pick_random()
	if choice:
		start_decision(choice[0], choice[1], choice[2])
	return false


func save_country_decisions(country_name: String):
	var path = country_file_paths.get(country_name)
	var cats = country_decisions_map.get(country_name)
	
	if not cats:
		# If country doesn't have a specific file, check default
		path = country_file_paths.get("_default")
		cats = default_categories
		
	if not path or not cats:
		print("Error: Could not find path or categories for ", country_name)
		return

	var data = { "categories": cats }
	var json_string = JSON.stringify(data, "\t")
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Saved decisions to ", path)
	else:
		print("Error: Could not open file for writing at ", path)
