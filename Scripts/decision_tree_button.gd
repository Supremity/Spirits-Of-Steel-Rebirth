extends Button

@export var decision_tree: DecisionTree


func _on_button_up() -> void:
	decision_tree.show()
	
	GameState.current_world.set_process(false)
	GameState.current_world.clock.set_process(false)
	TroopManager.set_process(false)
	
	GameState.decision_tree_open = true
