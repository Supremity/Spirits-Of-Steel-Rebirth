extends AStar2D
class_name SoiStar
# NOTE(soi): I AM A SUPERSTAR

var context_allowed_countries: Array[String] = []


func _compute_cost(from_id: int, to_id: int) -> float:
	return get_point_position(from_id).distance_to(get_point_position(to_id))

func _estimate_cost(from_id: int, to_id: int) -> float:
	return get_point_position(from_id).distance_squared_to(get_point_position(to_id))

func _filter_neighbor(from_id: int, to_id: int) -> bool:
	var from_prov = MapManager.province_objects.get(from_id)
	var to_prov = MapManager.province_objects.get(to_id)
	
	if !(from_prov && to_prov):
		return true

	var from_owner: String = from_prov.GetFunctionalOwner()
	var to_owner: String = to_prov.GetFunctionalOwner()

	# --- 1. Naval Restrictions (Hard requirement) ---
	# if from_prov.type == Province.LAND and to_prov.type == Province.SEA:
	# 	var has_port = false
	# 	for b in from_prov.buildings:
	# 		if b.type == "Port":
	# 			has_port = true
	# 			break
	# 	if !has_port: return true
	#
	# if from_prov.type == Province.SEA and to_prov.type == Province.LAND:
	# 	var has_port = false
	# 	for b in to_prov.buildings:
	# 		if b.type == "Port":
	# 			has_port = true
	# 			break
	# 	if !has_port: return true

	# --- 2. Political Access (Context-aware) ---
	if !context_allowed_countries.is_empty():
		# Destination is allowed -> Go ahead
		if context_allowed_countries.has(to_owner):
			return false
			
		# ESCAPE RULE: Starting province is disallowed? 
		# Allow one-step movement to find a way out.
		if !context_allowed_countries.has(from_owner):
			return false
			
		# Restricted: Path tries to enter territory we don't have access to
		return true
	
	# Default: Allow if no context (used during graph initialization)
	return false
