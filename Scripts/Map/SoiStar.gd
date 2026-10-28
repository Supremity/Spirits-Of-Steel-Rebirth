extends AStar2D
class_name SoiStar
# NOTE(soi): I AM A SUPERSTAR

# Set of country names (name -> true) a path may enter. Empty = no restriction.
var context_allowed_countries: Dictionary = {}

# NOTE: No _compute_cost override on purpose. The default native cost (point
# distance) is used, and AStar2D skips any neighbor _filter_neighbor rejects.

func _filter_neighbor(from_id: int, to_id: int) -> bool:
	if context_allowed_countries.is_empty():
		return false

	var from_prov = MapManager.province_objects.get(from_id)
	var to_prov = MapManager.province_objects.get(to_id)
	
	if !from_prov || !to_prov:
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
	# Destination is allowed -> Go ahead
	if context_allowed_countries.has(to_owner):
		return false

	# ESCAPE RULE: Starting province is disallowed?
	# Allow one-step movement to find a way out.
	if !context_allowed_countries.has(from_owner):
		return false

	# Restricted: Path tries to enter territory we don't have access to
	return true
