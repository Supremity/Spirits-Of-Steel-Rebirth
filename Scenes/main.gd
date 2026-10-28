extends Node2D
class_name Main


func _ready() -> void:
	#for i in range(100):
	#	print("%3d) %s %s" % [i + 1, NameGenerator.GenerateName(i % 2 == 0, randi_range(3, 7)).capitalize(), NameGenerator.GenerateName(i % 3 == 0, randi_range(3, 8)).capitalize()])
	SceneSwitcher.switch_to(SceneSwitcher.Type.MENU)
	
	var b := RecipeData.FromDict({"resource_produced": "Hi", "resources_required": ["meta", "aluminum"]})
	print(b.resource_produced)
	print(b.resources_required)
	var c = b.ToDict() # Type inference doesnt work
	print(c)
