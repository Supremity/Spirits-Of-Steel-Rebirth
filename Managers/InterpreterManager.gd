extends Node

enum ExpressionTypes {Variable, List, Event, Function, Loop, Match, Element, IdeologyDrift, Close}

var functions: Dictionary = {
	"return": [ExpressionTypes.Variable],
	"and": [ExpressionTypes.Variable],
	"not": [ExpressionTypes.Function],
	"or": [ExpressionTypes.Variable],
	"xor": [ExpressionTypes.Function, ExpressionTypes.Function],
	"eq": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"gt": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"lt": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"all": [ExpressionTypes.Variable],
	"any": [ExpressionTypes.Variable],
	"probability": [ExpressionTypes.Variable],
	"get": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"set_country_attr": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"add_country_attr": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"add": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"is_at_war": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"army_level_up": [],
	"build_factory": [ExpressionTypes.Variable],
	"declare_war": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"release": [ExpressionTypes.Variable, ExpressionTypes.Variable, ExpressionTypes.Variable, ExpressionTypes.Variable],
	"play_as": [ExpressionTypes.Variable],
	"annex": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"add_ideology_drift": [ExpressionTypes.Variable, ExpressionTypes.Variable, ExpressionTypes.IdeologyDrift],
	"make_puppet": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"has_pids": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"add_plans": [ExpressionTypes.Variable],
	"remove_plan": [ExpressionTypes.Variable],
	"event": [ExpressionTypes.Variable],
	"schedule_event": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"invite": [ExpressionTypes.Variable, ExpressionTypes.Variable],
	"change_province_types": [ExpressionTypes.List, ExpressionTypes.Variable, ExpressionTypes.Variable],
	"set_fig_attr": [ExpressionTypes.Variable, ExpressionTypes.Variable, ExpressionTypes.Variable],
}

var debug: bool:
	get:
		return SettingsManager.settings.debug_mode
var heap: Dictionary = {}
const DUMMY_FUNC = {"func": "return", "args": [true]}

func all(args: Array) -> bool:
	for arg in args:
		if not arg:
			return false
	return true

func any(args: Array) -> bool:
	for arg in args:
		if arg:
			return true
	return false

func get_variable(variable):
	if !variable is String:
		return variable
	# if CountryManager.countries.has(variable):
	# 	return CountryManager.countries[variable]
	match variable:
		"player":
			return CountryManager.player_country.country_name
		"current_date":
			return GameState.current_world.clock.get_date_string()
		"null":
			return null
		_:
			return heap.get(variable, variable)

func get_element(element, grid, country: CountryData = null):
	if element == null:
		return
	var text: String
	if element.has("text"):
		if element["text"] is Array:
			text = get_function(element["text"])
		elif element["text"] is String:
			text = element["text"]

	var condition = element.get("condition", DUMMY_FUNC)
	var finished = element.get("finished", DUMMY_FUNC)

	match element.get("type", ""):
		"country_header":
			var entry = HBoxContainer.new()
			entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var tr1 = TextureRect.new()
			tr1.texture = TroopManager.get_flag(element["country1"])
			tr1.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr1.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr1.custom_minimum_size = Vector2(80, 50)
			entry.add_child(tr1)
			
			var spacer = Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			entry.add_child(spacer)
			
			var tr2 = TextureRect.new()
			tr2.texture = TroopManager.get_flag(element["country2"])
			tr2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr2.custom_minimum_size = Vector2(80, 50)
			entry.add_child(tr2)
			
			grid.add_child(entry)
			entry.material = grid.material
			tr1.material = grid.material
			tr2.material = grid.material
			tr1.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr2.mouse_filter = Control.MOUSE_FILTER_IGNORE

		"button":
			var entry = Button.new()
			entry.text = text
			
			if not get_function(condition, country):
				entry.disabled = true
			
			entry.set_meta("condition", condition)
			entry.set_meta("country_context", country)

			entry.pressed.connect(func():
				if get_function(condition, country):
					get_function(finished, country)
			)
			grid.add_child(entry)
			entry.material = grid.material
			entry.tooltip_text = "Condition - %s\nFinished - %s" % [
				format_functions(condition),
				format_functions(finished)
			]
		"image":
			var entry = TextureRect.new()
			entry.texture = load(
				PlansManager.current_start_folder + "assets/plans/" + element["path"]
			)
			entry.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			entry.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			entry.custom_minimum_size = Vector2(100, 100)
			entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(entry)
			entry.material = grid.material
		"paragraph":
			var entry = RichTextLabel.new()
			entry.add_theme_font_size_override("normal_font_size", 18)
			entry.add_text(text)
			entry.fit_content = true
			entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			entry.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(entry)


func get_function(block, country: CountryData = null):
	# print(block)
	if !block: return

	if country == null:
		country = CountryManager.player_country

	# Handle multiple functions (Recusive Array Support)
	if block is Array:
		var last_result = null
		for item in block:
			last_result = get_function(item, country)
		return last_result

	if !block is Dictionary:
		return block

	var store_key: String = block.get("store", "")
	var result = null

	#match statement
	if block.has("match"):
		var match_val = str(get_function(block["match"], country))
		if match_val != "match": # Prevent collision with 'match' key itself
			result = get_function(block.get(match_val, {}), country)
	#for loop
	if block.has("for"):
		var var_name = block["for"]
		var had_prev = heap.has(var_name)
		var prev_val = heap.get(var_name)
		for item in block["in"]:
			heap[var_name] = item
			var substituted = _substitute(block["do"].duplicate(true), heap)
			result = get_function(substituted, country)
		
		if had_prev:
			heap[var_name] = prev_val
		else:
			heap.erase(var_name)
			
	# #match statement
	# if block.has("match"):
	# 	get_function(block.get(str(get_function(block["match"])), {}))
	
	var args: Array = block.get("args", []).duplicate()
	var evaled_args: Array = []
	for arg in args:
		if arg is Dictionary or arg is Array:
			arg = get_function(arg, country)
		else:
			arg = get_variable(arg)
		evaled_args.push_back(arg)

	var func_name = block.get("func", "")
	if func_name == "" and not (block.has("match") or block.has("for")):
		return block

	if func_name != "" and functions.has(func_name):
		var expected_args = functions[func_name]
		if evaled_args.size() < expected_args.size():
			push_error("Interpreter: Function '%s' expects at least %d args, got %d" % [func_name, expected_args.size(), evaled_args.size()])
			return null

	match func_name:
		# idk stuff
		"return":
			if evaled_args.size() == 1:
				result = evaled_args[0]
		# Comparison stuff
		"and":
			result = true
			for val in evaled_args:
				if not val:
					result = false
					break
		"not":
			if evaled_args.size() >= 1:
				result = !evaled_args[0]
		"or":
			result = false
			for val in evaled_args:
				if val:
					result = true
					break
		"xor":
			if evaled_args.size() >= 2:
				result = bool(evaled_args[0]) != bool(evaled_args[1])
		"eq":
			if evaled_args.size() >= 2:
				result = evaled_args[0] == evaled_args[1]
		"gt":
			if evaled_args.size() >= 2:
				result = evaled_args[0] > evaled_args[1]
		"lt":
			if evaled_args.size() >= 2:
				result = evaled_args[0] < evaled_args[1]
		"all":
			result = all(evaled_args)
		"any":
			result = any(evaled_args)
		"probability":
			result = bool(randi() % int(evaled_args[0]))
		"get":
			if evaled_args.size() >= 2:
				var country_obj = CountryManager.countries.get(evaled_args[0])
				if country_obj:
					result = country_obj.get(evaled_args[1])
				else:
					result = null
		"set_country_attr":
			country[evaled_args[0]] = evaled_args[1]
			result = country[evaled_args[0]]
		"add_country_attr":
			country[evaled_args[0]] += evaled_args[1]
			result = country[evaled_args[0]]
		"set_fig_attr":
			if evaled_args.size() >= 3:
				MapManager.significantFigures[evaled_args[0]][evaled_args[1]] = evaled_args[2]
		# Math stuff**
		"add":
			if evaled_args.size() >= 2:
				result = evaled_args[0] + evaled_args[1]
		# Country stuff
		"is_at_war":
			if evaled_args.size() >= 2:
				result = WarManager.is_at_war_names(
					evaled_args[0],
					evaled_args[1]
				)
		"army_level_up":
			country.army_level += 1
			result = country.army_level
		"build_factory":
			country.factories_amount += evaled_args[0] if evaled_args.size() > 0 else 1
			result = country.factories_amount
		"declare_war":
			if evaled_args.size() >= 2:
				var attacker: CountryData = CountryManager.countries.get(evaled_args[0])
				var defender: CountryData = CountryManager.countries.get(evaled_args[1])
				if attacker and defender:
					WarManager.declare_war(attacker, defender)
					result = true
				else:
					result = false
		"release":
			if evaled_args.size() >= 4:
				MapManager.release(evaled_args[0], evaled_args[1], evaled_args[2], evaled_args[3])
				result = true
		"play_as":
			if evaled_args.size() >= 1:
				if CountryManager.countries.has(args[0]):
					print("player country now " + (args[0]))
					CountryManager.set_player_country((args[0]))

				print("Unknown country: " + (args[0]))
				result = true
		"annex":
			if evaled_args.size() >= 2:
				MapManager.annex_country(evaled_args[0], evaled_args[1])
				result = true
		"add_ideology_drift":
			var country_obj: CountryData = CountryManager.countries.get(evaled_args[0])
			if country_obj:
				country_obj.driftTargets[args[1]] = IdeologyDriftTarget.FromDict(args[2])
				result = country_obj.driftTargets
		"make_puppet":
			var overlord: CountryData = CountryManager.countries.get(evaled_args[0]) if evaled_args.size() >= 2 else null
			var puppet: CountryData = CountryManager.countries.get(evaled_args[1]) if evaled_args.size() >= 2 else null
			if overlord and puppet:
				CountryManager.make_puppet(overlord, puppet)
				result = true
		"has_pids":
			if evaled_args.size() >= 2:
				var i: int = 1
				var province_owner = evaled_args[0]
				var all_owned = true
				while i < evaled_args.size():
					if province_owner != MapManager.province_objects[int(evaled_args[i])].GetFunctionalOwner():
						all_owned = false
						break
					i += 1
				result = all_owned
		"add_plans":
			if !PlansManager.plans.has(country.country_name):
				PlansManager.plans[country.country_name] = []
			PlansManager.plans[country.country_name].append(evaled_args[0])
		"remove_plan":
			PlansManager.plans[country.country_name].remove_at(
				PlansManager.plans[country.country_name].find_custom(
					func(element): return element == args[0]
				)
			)
		"event":
			if evaled_args.size() > 0 && evaled_args[0] is Dictionary:
				EventManager.show_alert(evaled_args[0])
				result = true
		"schedule_event":
			if evaled_args.size() >= 2 and evaled_args[1] is Dictionary:
				EventManager.schedule_event(int(evaled_args[0]), evaled_args[1])
				result = true
		"invite":
			var inviter: CountryData = CountryManager.countries.get(evaled_args[0]) if evaled_args.size() >= 2 else null
			var invitee: CountryData = CountryManager.countries.get(evaled_args[1]) if evaled_args.size() >= 2 else null
			if inviter and invitee:
				FactionManager.invite_faction(inviter, invitee)
		"change_province_types":
			if evaled_args.size() >= 3:
				var pids = evaled_args[0]
				var pids_typed: Array[int] = []
				if pids is float or pids is int:
					pids_typed.append(int(pids))
				elif pids is Array:
					for p in pids:
						pids_typed.append(int(p))
				MapManager.change_province_types(pids_typed, int(evaled_args[1]), str(evaled_args[2]))

	if store_key != "":
		heap[store_key] = result

	return result

func refresh_buttons(container: Node):
	for child in container.get_children():
		if child is Button and child.has_meta("condition"):
			var condition = child.get_meta("condition")
			var country = child.get_meta("country_context")
			child.disabled = !get_function(condition, country)
		
		# Recurse
		refresh_buttons(child)

func format_functions(expression, indent: String = "", no_bullet: bool = false) -> String:
	# return ""
	var funcs = []
	if expression is Array:
		funcs = expression
	elif expression is Dictionary:
		funcs = [expression]
	else:
		return ""

	var formatted: String = ""
	for function in funcs:
		if not function is Dictionary: continue
		
		# Handle 'for' loop
		if function.has("for"):
			formatted += indent + ("• " if not no_bullet else "") + "For each " + str(function["for"]).capitalize()
			formatted += " in " + str(function.get("in", "[]")) + ":\n"
			formatted += format_functions(function.get("do", {}), indent + "  ") + "\n"
			continue
			
		# Handle 'match' statement
		if function.has("match"):
			var match_header = format_functions(function["match"], "", true).strip_edges()
			formatted += indent + ("• " if not no_bullet else "") + "Match " + match_header + ":\n"
			for key in function.keys():
				if key in ["match", "func", "args", "store"]: continue
				formatted += indent + "  - " + str(key).capitalize() + ":\n"
				formatted += format_functions(function[key], indent + "    ") + "\n"
			continue

		if function.has("func"):
			var func_name = function["func"]
			var args = function.get("args", [])
			if not args is Array:
				args = [args]
			
			formatted += indent + ("• " if not no_bullet else "") + func_name.capitalize()
			
			# Check if args contain nested functions (like in 'and', 'or', 'all', 'any')
			var nested_found = false
			for arg in args:
				if (arg is Dictionary and arg.has("func")) or arg is Array:
					nested_found = true
					break
			
			if nested_found:
				formatted += ":\n"
				formatted += format_functions(args, indent + "  ") + "\n"
			else:
				var formatted_args: Array = []
				for arg in args:
					var is_number = typeof(arg) == TYPE_INT or typeof(arg) == TYPE_FLOAT
					# Only lookup province names for specific functions to avoid constant collisions
					var should_lookup_prov = func_name in ["has_pids", "annex", "release"]
					if should_lookup_prov and is_number and MapManager.province_objects.has(int(arg)):
						var prov = MapManager.province_objects[int(arg)]
						formatted_args.append(prov.city if prov.city != "" else prov.name)
					else:
						formatted_args.append(str(arg))
				
				if not formatted_args.is_empty():
					formatted += ": " + ", ".join(formatted_args)
				formatted += "\n"
				
	return formatted.strip_edges() if indent == "" else formatted

# NOTE(soi): recursive string substitution with cycle detection
func _substitute(expression, _heap: Dictionary, visited: Array = []):
	if expression is Dictionary:
		for key in expression.keys():
			expression[key] = _substitute(expression[key], _heap, visited)
		return expression
	elif expression is Array:
		for i in range(expression.size()):
			expression[i] = _substitute(expression[i], _heap, visited)
		return expression
	elif expression is String:
		if _heap.has(expression):
			if expression in visited:
				push_error("Interpreter: Circular reference detected for variable '%s'" % expression)
				return expression
			var new_visited = visited.duplicate()
			new_visited.append(expression)
			return _substitute(_heap[expression], _heap, new_visited)
		else:
			return expression
	else:
		return expression
