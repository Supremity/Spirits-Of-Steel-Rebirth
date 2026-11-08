extends Resource
class_name Province

enum { SEA = 0, LAND = 1 }
enum {NO_FACTORY = 0, NO_PORT = 0, FACTORY_BUILDING = 1, PORT_BUILDING = 1, FACTORY_BUILT = 2, PORT_BUILT = 2}

@export var type: int = Province.LAND
@export var id: int
@export var name: String
@export var country: String
@export var occupier: String
@export var biome: String
@export var resources: Array[ResourceNode]
@export var city: String
@export var buildings: Array[BuildingData]
@export var populations: Array[PopulationData]
@export var gdp: int = 1000
@export var center: Vector2
# @export var neighbors: PackedInt32Array = []
@export var claims: PackedStringArray = []
@export var infrastructure: int = 0
@export var maxInfrastructure: int = 3


func ToDict(troops_data: Array = []) -> Dictionary:
	var resource_array = []
	for resourceData in resources:
		resource_array.append(resourceData.ToDict())

	var population_array = []
	for populationData in populations:
		population_array.append(populationData.ToDict())


	var building_array = []
	for buildingData in buildings:
		building_array.append(buildingData.ToDict())

	var province_dict = {
		"type" : self.type,
		"name": self.name,
		"polity": self.country,
		"occupier": self.occupier,
		"biome": self.biome,
		"resources": resource_array,
		"city": self.city,
		"buildings": building_array,
		"populations": population_array,
		"gdp": self.gdp,
		"claims": [] as PackedStringArray if (self.claims.size() == 1 && self.claims[0] == self.country) else self.claims,
		"infrastructure": self.infrastructure,
		"max_infrastructure": self.maxInfrastructure,
		"troops": troops_data
	}
	return province_dict


static func FromDict(a_data: Dictionary) -> Province:
	var province: Province = Province.new()
	
	if a_data.get("type", Province.SEA) == Province.SEA:
		# SEA LOGIC: Unique ID, but 0 stats
		province.type = Province.SEA
		province.name = "Sea"
		province.country = "Sea"
		province.occupier = ""
		province.biome = a_data.get("biome", "Sea")
		for resourceData: Dictionary in a_data.get("resources", []):
			province.resources.append(ResourceNode.FromDict(resourceData))
		province.city = ""
		province.buildings = []
		province.populations = []
		province.gdp = 0
		province.infrastructure = a_data.get("infrastructure", 0)
		province.maxInfrastructure = a_data.get("max_infrastructure", 0)
	else:
		# LAND LOGIC
		province.type = Province.LAND
		province.name = a_data["name"]
		province.country = a_data["polity"]
		province.occupier = a_data.get("occupier", "")
		province.biome = a_data.get("biome", "Plains")
		for resourceData: Dictionary in a_data.get("resources", []):
			province.resources.append(ResourceNode.FromDict(resourceData))
		province.city =  a_data.get("city", "")
		for buildingData: Dictionary in a_data.get("buildings", []):
			province.buildings.append(BuildingData.FromDict(buildingData))
		for populationData: Dictionary in a_data.get("populations", []):
			province.populations.append(PopulationData.FromDict(populationData))
		province.claims = [province.country] if a_data.get("claims", []).is_empty() else a_data.get("claims", [])
		# province.claims = a_data.get("claims", [])
		province.gdp = a_data.get("gdp", 1000)
		province.infrastructure = a_data.get("infrastructure", 0)
		province.maxInfrastructure = a_data.get("max_infrastructure", 5)
	
	return province


func GetPopulation() -> int:
	var totalPopulation: int = 0
	for subpopulation: PopulationData in self.populations:
		totalPopulation += subpopulation.amount
	return totalPopulation

func GetFactories() -> int:
	var totalFactories: int = 0
	for building: BuildingData in buildings:
		if building.state == BuildingData.BuildingState.FUNCTIONAL:
			totalFactories += 1
	return totalFactories

func GetFunctionalOwner() -> String:
	if occupier == "":
		return country
	else:
		return occupier


func GetResources() -> String:
	var counts: Dictionary = {}
	for resource in resources:
		if counts.has(resource.type):
			counts[resource.type] += resource.amount
		else:
			counts[resource.type] = resource.amount

	var list: String = ""
	for resource_type in counts:
		if list != "":
			list += "\n"
		list += "%s: %d" % [ resource_type, counts[resource_type] ]
	return list
