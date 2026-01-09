extends Resource
class_name Province


@export var type:  int
@export var id: int
@export var country: String
@export var city: String
@export var population: int = 0
@export var gdp: int = 1000
@export var center: Vector2
@export var neighbors: Array[int] = []
