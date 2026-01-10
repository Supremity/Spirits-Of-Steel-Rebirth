extends Node

class_name TroopData

# --- Core Properties ---
var country_name: String
var province_id: int
var divisions: int
var position: Vector2
var flag_texture: Texture2D

# --- Movement Properties ---
var is_moving: bool = false
var path: Array = []  # Array of province IDs
var target_position: Vector2 = Vector2.ZERO
var progress: float = 0.0

# Runtime properties (may be injected)
# - start_node_pos: Vector2 (where movement started)
# - travel_hours_remaining: float (for teleport mode)


func _init(
	p_country: String, p_province_id: int, p_divisions: int, p_position: Vector2, p_flag: Texture2D
) -> void:
	country_name = p_country
	province_id = p_province_id
	divisions = p_divisions
	position = p_position
	flag_texture = p_flag


func _to_string() -> String:
	return (
		"TroopData(%s, prov=%d, divs=%d, moving=%s)"
		% [country_name, province_id, divisions, is_moving]
	)
