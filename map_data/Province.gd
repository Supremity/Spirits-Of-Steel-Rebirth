extends Resource
class_name Province

enum { SEA = 0, LAND = 1 }

@export var type: int = LAND
@export var id: int
@export var country: String
@export var city: String
@export var population: int = 0

@export var has_factory: bool = false
@export var has_port: bool = false
@export var gdp: int = 1000
@export var center: Vector2
@export var neighbors: Array[int] = []
