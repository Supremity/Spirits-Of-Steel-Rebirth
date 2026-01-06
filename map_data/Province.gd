extends Resource
class_name Province

@export var id: int
@export var country: String
@export var population: int = 0
@export var center: Vector2
@export var neighbors: Array[int] = []
