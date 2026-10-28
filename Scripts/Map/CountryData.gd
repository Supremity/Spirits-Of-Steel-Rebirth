class_name CountryData extends Resource

var economy_law_penalty: float = 0.0 # 0.10 means 10% income loss
var army_composition_cache: Dictionary = {"infantry": 0, "tank": 0, "artillery": 0}
#region --- Configuration & Constants ---
const MANPOWER_RECOVERY_PER_YEAR := 0.10
const MANPOWER_RECOVERY_PER_DAY := MANPOWER_RECOVERY_PER_YEAR / 365.0
var military_size_ratio := 0.005
const BASE_ARMY_COST := 20
#endregion

#region --- Properties ---
var country_name: String
var display_name: String
var capital: String
var country_color: Color
var is_player: bool = false
var is_puppet: bool = false
var is_exiled: bool = false
var ai_controller: CountryAI = null

var relations: Dictionary = {}

var factory_port_daily_cost = 0.2 # The less the better. It's percentage based

# Economy
var money: float = 0.0
var gdp: int = 0
var income: float = 0.0
var factories_amount: int = 0
var factory_income = 100
var hourly_money_income: float = 0.0 # Calculated value

var divCostMod: float = 1.0

signal ideology_changed

# Politics
var driftTargets: Dictionary[String, IdeologyDriftTarget]
var political_power: float = 5000.0
var base_daily_pp_gain: float = 0.04
var daily_pp_gain: float = 0.04
var base_stability: float = 0.5
var stability: float = 0.5
var base_war_support: float = 0.5
var war_support: float = 0.5
var ideology: Vector2 = Vector2(randi_range(-100, 100), randi_range(-100, 100)):
	set(value):
		ideology = value
		refresh_ideology_name()
		ideology_changed.emit()
var ideology_name: String = "neutral" # Initialized, will be updated by setter



# Population & Manpower
var total_population: int = 0
var total_power: int = 1000
var total_water: int = 1000
var total_sewage: int = 1000

var manpower: int = 0
var mobilized: int = 0

# Military State
var army_level: int = 1
var army_cost: float = 0.0
var troop_speed_modifier: float = 1.0

var troopSpeedExtra: float = 1.0

var troopAttackAdd: float = 0.0
var troopAttackMod: float = 1.0
var troopDefendAdd: float = 0.0
var troopDefendMod: float = 1.0

var attacker_attack_mitigation: float = 1.0
var defender_attack_mitigation: float = 1.0

# Deployment & Training State
var allowedCountries: Array[String] = []
var accepted_cultures: Array = []
var puppets: Array = []
var hostedGovernments: Array = []
var owner: String
var host: String
var factions: Array[String] = []
var finished_decisions: Array[String] = []
var ongoing_training: Array[TroopTraining] = []
var ready_troops: Array[ReadyTroop] = []
var deploy_pid: int = -1 # ID of province to deploy to
var pre_war_provinces: Array = [] # Snapshotted provinces before a war
#endregion

func get_all_allowed_countries() -> Array[String]:
	var combined: Array[String] = allowedCountries.duplicate()
	for faction_name in factions:
		if faction_name in FactionManager.factions:
			for member in FactionManager.factions[faction_name].members:
				if not member.polity in combined:
					combined.append(member.polity)
	return combined

# for optimization
var is_at_war: bool = false
var war_dirty: bool = true
var _is_loading: bool = false
var dirty: bool = true
var dirty_manpower: bool = true
var enemies: Array = []

var figures: PackedStringArray = []
var governmentPositions: Dictionary[String, String] = {
	"Leader": ""
}

#region --- Inner Classes ---
class TroopTraining:
	var divisions_count: int
	var division_type: String
	var days_left: int
	var daily_cost: float

	func _init(_count: int, _type: String, _days: int, _cost: float):
		divisions_count = _count
		division_type = _type
		days_left = _days
		daily_cost = _cost


class ReadyTroop:
	var division: DivisionData
	var count: int

	func _init(a_division: DivisionData, a_count: int):
		self.division = a_division
		self.count    = a_count


#endregion

#func setup_ai():
#	if not is_player:
#		ai_controller = CountryAI.new(self)

#region --- Lifecycle ---

func _init() -> void:
# NOTE(soi): why was this commented out?
# NOTE(Sockmit2007): I don't remember.
#	if p_country_name != "":
#		country_name = p_country_name
#	if _is_loading:
#		return
#	allowedCountries.append_array([p_country_name, "sea"])
#	_refresh_economic_stats()
#	refresh_ideology_name()
#
#	# Initial Manpower Calculation
#	var manpower_used = CountryManager.get_country_used_manpower(self)
#	manpower = int((total_population * military_size_ratio) - manpower_used)
#	_setup_starting_army()
	#setup_ai()
	ai_controller = CountryAI.new(self)


func ToDict() -> Dictionary:
	return {
		"name": country_name,
		"display_name": display_name,
		"capital": capital,
		"color": "#"+country_color.to_html(false).to_upper(),
		"money": money,
		"ideology": [ideology.x, ideology.y],
		"political_power": political_power,
		"stability": base_stability,
		"war_support": base_war_support,
		"puppets": puppets,
		"accepted_cultures": accepted_cultures,
		"hostedGovernments": hostedGovernments,
		"figures": figures,
		"government_positions": governmentPositions,
		"is_player": is_player,
		"finished_decisions": finished_decisions,
	}
	# NOTE(soi): AAAAUHHHHHGGG

static func FromDict(a_data: Dictionary) -> CountryData:
	var country: CountryData = CountryData.new()
	
	country.country_name = a_data["name"]
	country.display_name = a_data.get("display_name", a_data["name"])
	country.capital = a_data.get("capital", "")
	country.country_color = Color.html(a_data.get("color", "#FFFFFF"))
	country.money = a_data.get("money", 0)
	country.ideology = Vector2(a_data.get("ideology", [0, 0])[0], a_data.get("ideology", [0, 0])[1])
	country.political_power = a_data.get("political_power", 5000)
	country.base_stability = a_data.get("stability", 0.5)
	country.base_war_support = a_data.get("war_support", 0.5)
	country.puppets = a_data.get("puppets", [])
	country.accepted_cultures = a_data.get("accepted_cultures", [])
	country.hostedGovernments = a_data.get("hosted_governments", [])
	country.allowedCountries.append_array([country.country_name, "Sea"])
	country.figures = a_data.get("figures", [])
	country.governmentPositions.merge(a_data.get("government_positions", {}), true)
	country.is_player = a_data.get("is_player", false)
	country.finished_decisions = Array(a_data.get("finished_decisions", []), TYPE_STRING, &"", null)
	
	for id in country.finished_decisions:
		country.set_meta("finished_" + id, true)
	# country._refresh_economic_stats()
	# country.refresh_ideology_name()
	
	country.stability = country.base_stability
	country.war_support = country.base_war_support

	# NOTE(Sockmit2007): Urgh...
	# NOTE(soi): indeed
	# NOTE(soi): ok the refresh things cause the map editor to crash when u make a country so...
	#country.manpower = int((country.total_population * country.military_size_ratio) - CountryManager.get_country_used_manpower(country))
	
	return country

func InitializeCabinet() -> void:
	for position: String in governmentPositions:
		var figure: ImportantFigure = MapManager.significantFigures.get(governmentPositions[position])
		if figure:
			for skill: String in figure.skills:
				match skill:
					"stability":
						stability += figure.skills[skill]
					"warSupport":
						war_support += figure.skills[skill]
					"dailyPPGain":
						daily_pp_gain += figure.skills[skill]
					"divCostMod":
						divCostMod *= figure.skills[skill]
					"troopSpeed":
						troopSpeedExtra += figure.skills[skill]
					"troopAttackAdd":
						troopAttackAdd += figure.skills[skill]
					"troopAttackMod":
						troopAttackMod *= figure.skills[skill]
					"troopDefendAdd":
						troopDefendAdd += figure.skills[skill]
					"troopDefendMod":
						troopDefendMod *= figure.skills[skill]
					"attackerAttackMitigation":
						attacker_attack_mitigation *= figure.skills[skill]
					"defenderAttackMitigation":
						defender_attack_mitigation *= figure.skills[skill]

func process_hour() -> void:
	if _is_loading:
		return
	
	#print("Processing %s" % country_name)

	political_power += daily_pp_gain

	# Economic Cycle
	# (GDP / Hours in a year) * Tax Rate + Factory Output
	hourly_money_income = ((gdp * 0.0000228310502) + (factories_amount * factory_income)) * (1.0 - economy_law_penalty)
	army_cost = calculate_army_upkeep()
	income = hourly_money_income - army_cost
	money += income

	troop_speed_modifier = 1.0 + (army_level * 0.1) + troopSpeedExtra

	update_manpower_pool()
	_process_reinforcements()

	if dirty_manpower and !dirty:  # Because if dirty. refresh_economic_stats will do it anyways
		update_manpower_pool()

	if war_dirty:  # For the AI
		update_is_at_war()

	if !is_player:
		#print("Thinking %s" % country_name)
		ai_controller.think_hour()
	else:
		#print("Total: %d Militiable: %d Manpower: %d Mobilized: %d Armed: %d" % [total_population, total_population * military_size_ratio, manpower, mobilized, manpower + mobilized])
		pass

func process_day() -> void:
	if _is_loading:
		return

	#if ideology != Vector2(0, 0):
	#	print(ideology)
	var moveAmount: Vector2 = Vector2(0, 0)
	for ideaTarget: IdeologyDriftTarget in driftTargets.values():
		moveAmount += ideology.direction_to(ideaTarget.finalPosition) * ideaTarget.driftAmount
	ideology += moveAmount

	# Refresh stats that change daily/weekly
	_refresh_economic_stats()
	_process_training()
	DecisionManager.process_country_day(self)
	if !is_player:
		ai_controller.think_day()

func _refresh_economic_stats() -> void:
	if not dirty:
		return  # Already up to date

	total_population = CountryManager.get_country_population(country_name)
	factories_amount = CountryManager.get_factories_amount(country_name)
	# GDP calculation based on population (Simplified for performance)
	gdp = int(CountryManager.get_country_gdp(country_name) * total_population * 0.000001)
	update_manpower_pool()
	self.dirty = false

#endregion

func refresh_ideology_name() -> void:
	ideology_name = IdeologyManager.get_ideology_name(ideology)

#region --- Military Management ---
func train_troops(count: int, type: String = "infantry") -> bool:
	var template = DivisionData.TEMPLATES.get(type)
	if not template:
		push_error("Unknown division type: %s" % type)
		return false

	var total_manpower_needed = count * template["manpower"]

	# Check affordability (Manpower + First day of cost)
	if manpower < total_manpower_needed or money < count * template["cost"] * divCostMod:
		return false

	manpower -= total_manpower_needed
	mobilized += total_manpower_needed
	#dirty_manpower = true

	# Add to training queue
	ongoing_training.append(TroopTraining.new(count, type, template["days"], template["cost"]))
	return true


func _process_training() -> void:
	# Loop backwards so we can safely remove finished batches
	for i in range(ongoing_training.size() - 1, -1, -1):
		var training = ongoing_training[i]
		var batch_daily_cost = training.divisions_count * training.daily_cost * divCostMod

		if money >= batch_daily_cost:
			money -= batch_daily_cost
			training.days_left -= 1

		if training.days_left <= 0:
			_graduate_troops(training)
			ongoing_training.remove_at(i)


func _graduate_troops(training: TroopTraining) -> void:
	ready_troops.append(ReadyTroop.new(DivisionData.create_division(training.division_type), training.divisions_count))
	#dirty_manpower = true


#endregion


#region --- Stats & Manpower ---
func update_manpower_pool() -> void:
	var max_allowed_manpower = int(total_population * military_size_ratio)
	var total_mobilized = manpower + mobilized

	if total_mobilized < max_allowed_manpower:
		var daily_growth = max(1, int(total_population * 0.0001))
		manpower += daily_growth

	if (total_mobilized) > max_allowed_manpower:
		manpower = max(0, max_allowed_manpower - mobilized)

	# HARD SAFETY: Never let the variable itself be negative
	manpower = max(0, manpower)
	dirty_manpower = false


func get_army_pressure() -> float:
	var army_size = 0
	for troop: TroopData in TroopManager.get_troops_for_country(country_name):
		army_size += troop.divisions_count # assuming .divisions property exists on TroopData

	var capacity = max(1.0, (gdp * 0.03) + factories_amount * 5)
	return army_size / capacity


func get_max_morale() -> float:
	return (60.0 + (stability * 40.0) + (army_level * 5.0)) * (0.5 if money < 0 else 1.0)


func get_attack_efficiency() -> float:
	return (troopAttackAdd + 0.9 + (war_support * 0.3) + (army_level * 0.05)) * (0.7 if money < 0 else 1.0) * troopAttackMod


func get_defense_efficiency() -> float:
	return (troopDefendAdd + 1.0 + (stability * 0.15) + (army_level * 0.05)) * (0.8 if money < 0 else 1.0) * troopDefendMod

#endregion

func RemoveGovernmentPosition(a_position: String) -> void:
	var currentFigure: ImportantFigure = MapManager.significantFigures.get(governmentPositions[a_position], null)
	if currentFigure:
		for skill: String in currentFigure.skills:
			match skill:
				"stability":
					stability -= currentFigure.skills[skill]
				"warSupport":
					war_support -= currentFigure.skills[skill]
				"dailyPPGain":
					daily_pp_gain -= currentFigure.skills[skill]
				"divCostMod":
					divCostMod /= currentFigure.skills[skill]
				"troopSpeed":
					troopSpeedExtra -= currentFigure.skills[skill]
				"troopAttackAdd":
					troopAttackAdd -= currentFigure.skills[skill]
				"troopAttackMod":
					troopAttackMod /= currentFigure.skills[skill]
				"troopDefendAdd":
					troopDefendAdd -= currentFigure.skills[skill]
				"troopDefendMod":
					troopDefendMod /= currentFigure.skills[skill]
				"attackerAttackMitigation":
					attacker_attack_mitigation /= currentFigure.skills[skill]
				"defenderAttackMitigation":
					defender_attack_mitigation /= currentFigure.skills[skill]
		currentFigure.occupation = ""
	governmentPositions[a_position] = ""

func SetGovernmentPosition(a_position: String, a_figure: ImportantFigure) -> void:
	RemoveGovernmentPosition(a_position)
	governmentPositions[a_position] = a_figure.name
	for skill: String in a_figure.skills:
		match skill:
			"stability":
				stability += a_figure.skills[skill]
			"warSupport":
				war_support += a_figure.skills[skill]
			"dailyPPGain":
				daily_pp_gain += a_figure.skills[skill]
			"divCostMod":
				divCostMod *= a_figure.skills[skill]
			"troopSpeed":
				troopSpeedExtra += a_figure.skills[skill]
			"troopAttackAdd":
				troopAttackAdd += a_figure.skills[skill]
			"troopAttackMod":
				troopAttackMod *= a_figure.skills[skill]
			"troopDefendAdd":
				troopDefendAdd += a_figure.skills[skill]
			"troopDefendMod":
				troopDefendMod *= a_figure.skills[skill]
			"attackerAttackMitigation":
				attacker_attack_mitigation *= a_figure.skills[skill]
			"defenderAttackMitigation":
				defender_attack_mitigation *= a_figure.skills[skill]
	a_figure.occupation = a_position

#region --- Deployment Helper ---
func deploy_ready_troop(troop: ReadyTroop, specific_pid: int = -1) -> bool:
	var index = ready_troops.find(troop)
	if index == -1:
		return false

	var target_pid = specific_pid

	# If no specific ID provided, pick random
	if target_pid == -1:
		var provinces = MapManager.country_to_provinces.get(country_name, [])
		if provinces.is_empty():
			return false
		target_pid = provinces.pick_random()

	TroopManager.DeployReady(country_name, troop, target_pid)
	ready_troops.remove_at(index)
	return true


#endregion

var cached_garrison_hubs: Array = []


#func demobilize_troop(troop: TroopData, count: int = -1) -> void:
#	if not troop or troop.country_name != country_name:
#		return
#
#	var divs_to_reserve: Array[DivisionData] = []
#
#	if count == -1 or count >= troop.divisions_count:
#		# Full Demobilization
#		divs_to_reserve = troop.stored_divisions.duplicate()
#		TroopManager.RemoveTroop(troop)
#	else:
#		# Partial Demobilization (Peel off the surplus)
#		for i in range(count):
#			divs_to_reserve.append(troop.stored_divisions.pop_back())
#		# Update the TroopManager's view of this troop (re-calculate strength)
#		# No need to remove from map, just update the existing object.
#
#	if not divs_to_reserve.is_empty():
#		var reserve = ReadyTroop.new(divs_to_reserve)
#		ready_troops.append(reserve)
#	#dirty_manpower = true


## Enhanced upkeep: Reserves cost 25% of active troops
func calculate_army_upkeep() -> float:
	var active_divisions = 0
	for troop in TroopManager.get_troops_for_country(country_name):
		active_divisions += troop.divisions_count

	var reserve_divisions = 0
	for rt: ReadyTroop in ready_troops:
		reserve_divisions += rt.count

	return (active_divisions + (reserve_divisions * 0.25)) * army_level * BASE_ARMY_COST * divCostMod


func _setup_starting_army() -> void:
	# 1. Economic Safety: Calculate what we can actually afford
	# We use the same math as process_hour to see our projected income
	# Don't spend more than 25% of hourly income on starting upkeep
	# 2. Determine count (Strictly capped to prevent icon spam)
	var final_count = clampi(int((((gdp* 0.0000228310502) + factories_amount * factory_income) * 0.25) / max(1.0, (army_level * BASE_ARMY_COST))), 1, 6) # Start very small (1-6 divs)

	# 3. Manpower Check
	var template = DivisionData.TEMPLATES.get("infantry")

	if manpower < final_count * template["manpower"]:
		final_count = int(manpower / max(1, template["manpower"]))

	if final_count <= 0:
		return

	# 4. Create the DivisionData objects
	var starting_divisions: Array[DivisionData] = []
	for i in range(final_count):
		starting_divisions.append(DivisionData.create_division("infantry"))

	# 5. Safety: Deduct manpower now
	manpower -= (final_count * template["manpower"])

	# 6. Deploy via a safe call
	# Using 'call_deferred' ensures that MapManager/TroopManager are fully loaded
	# before we try to place troops in provinces.
	_deploy_initial_force.call_deferred(starting_divisions)


func _deploy_initial_force(divisions: Array[DivisionData]) -> void:
	var provinces = MapManager.country_to_provinces.get(country_name, [])
	if provinces.is_empty():
		return

	# Get cities specifically to look more "organized"
	var cities = MapManager.get_cities_province_country(country_name)
	var deploy_targets = cities if not cities.is_empty() else provinces

	# If we have a lot of divisions, split them into small stacks (e.g., 5 per stack)
	var stack_size = 5
	var current_batch: Array[DivisionData] = []

	for i in range(divisions.size()):
		current_batch.append(divisions[i])

		# Once batch is full OR it's the last division
		if current_batch.size() >= stack_size or i == divisions.size() - 1:
			var target_pid = deploy_targets.pick_random()
			TroopManager.deploy_specific_divisions(country_name, current_batch, target_pid)
			current_batch = [] # Reset for next stack


func _process_reinforcements():
	for troop in TroopManager.get_troops_for_country(country_name):
		if troop.is_moving:
			continue

		for div in troop.stored_divisions:
			if div.hp < div.max_hp:
				var percentage: float = min(0.05, float(div.max_hp - div.hp) / float(div.max_hp))
				var template = DivisionData.TEMPLATES[div.type]
				var men_needed = int(template["manpower"] * percentage) # 5% reinforcement
				var moneyNeeded = int(template["cost"] * percentage * divCostMod) # 5% reinforcement

				# REINFORCEMENT SAFETY: Stop if it would drop us below zero
				if manpower >= men_needed && money >= moneyNeeded:
					money -= moneyNeeded
					manpower -= men_needed
					mobilized += men_needed
					div.hp += percentage * div.max_hp
					
					
func set_relation_with(other_country_name: String, value: int) -> void:
	relations[other_country_name] = clampi(value, 0, 100)
	#var finish_game = true


func update_relations() -> void:
	for otherName in relations:
		if CountryManager.countries.has(otherName):
			relations[otherName] = 141 - ideology.distance_to(CountryManager.countries[otherName].ideology)
		else:
			#print(otherName)
			relations[otherName] = 50

func get_relation_with(other_country_name: String) -> int:
	if CountryManager.countries.has(other_country_name):
		return relations.get(other_country_name, 50)
	else:
		relations.erase(other_country_name)
		return 0


func update_is_at_war():
	enemies = WarManager.get_enemies_of(self.country_name)
	is_at_war = !enemies.is_empty()
	war_dirty = false
