extends Node

var factions: Dictionary[String, FactionData] = {}

func Initialize(a_factionData: Array) -> void:
	factions.clear()
	for factionData: Dictionary in a_factionData:
		factions[factionData["name"]] = FactionData.FromDict(factionData)
		for member: FactionMember in factions[factionData["name"]].members:
			var country = CountryManager.countries.get(member.polity)
			if country:
				country.factions.append(factionData["name"])


func SaveFactions() -> Array:
	var factions_array = []
	for faction in factions:
		factions_array.append(FactionManager.factions[faction].ToDict())
	return factions_array


func create_faction(a_leader: String, a_name: String, a_color: Color) -> void:
	factions[a_name] = FactionData.FromValues(a_name, a_color, [FactionMember.FromValues(a_leader, "Leader")])
	CountryManager.countries[a_leader].factions.append(a_name)
	#print(factions)


func clear_faction(country: CountryData):
	var country_factions_copy = country.factions.duplicate()
	for faction_name in country_factions_copy:
		if faction_name in factions:
			var faction = factions[faction_name]
			var index = faction.members.find_custom(func(m): return m.polity == country.country_name)
			if index != -1:
				faction.members.remove_at(index)
				country.factions.erase(faction_name)


func invite_faction(inviter: CountryData, invitee: CountryData) -> void:
	MapManager.AllowPids(inviter, invitee)
	MapManager.AllowPids(invitee, inviter)
	# NOTE(soi): we should add an option to choose which faction to invite to
	var inviter_factions_copy = inviter.factions.duplicate()
	for faction in inviter_factions_copy:
		if faction in factions:
			var faction_data = factions[faction]
			var leader_index = faction_data.members.find_custom(
				func(m): return m.polity == inviter.country_name
			)
			if leader_index != -1 and faction_data.members[leader_index].status == "Leader":
				faction_data.members.append(FactionMember.FromValues(invitee.country_name, "Member"))
				if not faction in invitee.factions:
					invitee.factions.append(faction)
				print("Invited %s to %s" % [invitee.country_name, faction])


func in_faction(inviter: CountryData, invitee: CountryData) -> bool:
	for faction in invitee.factions:
		if faction in inviter.factions:
			return true
	return false


func kick_faction(kicker: CountryData, kickee: CountryData) -> void:
	MapManager.UnallowPids(kicker, kickee)
	for faction in kicker.factions:
		var faction_data: FactionData = factions[faction]
		var kicker_index = faction_data.members.find_custom(func(m): return m.polity == kicker.country_name)
		
		if kicker_index != -1 and faction_data.members[kicker_index].status == "Leader":
			var kickee_index = faction_data.members.find_custom(func(m): return m.polity == kickee.country_name)
			if kickee_index != -1:
				var member_to_kick: FactionMember = faction_data.members[kickee_index]
				if member_to_kick.status == "Leader" and faction_data.members.size() > 1:
					for i in range(faction_data.members.size()):
						if i != kickee_index:
							faction_data.members[i].status = "Leader"
							break
				faction_data.members.remove_at(kickee_index)
				kickee.factions.erase(faction)
	#print(factions)


func dissolve_faction(dissolver: CountryData, faction_name: String) -> void:
	if not faction_name in factions:
		return
	
	var faction_data: FactionData = factions[faction_name]
	var dissolver_index = faction_data.members.find_custom(func(m): return m.polity == dissolver.country_name)
	
	if dissolver_index != -1 and faction_data.members[dissolver_index].status == "Leader":
		for member in faction_data.members:
			var member_country = CountryManager.countries.get(member.polity)
			if member_country:
				member_country.factions.erase(faction_name)
		factions.erase(faction_name)
	#print(factions)


func get_faction_member(country_name: String) -> FactionMember:
	var country = CountryManager.countries.get(country_name)
	if !country || country.factions.is_empty():
		return null
		
	for faction_name in country.factions:
		if faction_name in factions:
			var faction_data = factions[faction_name]
			var index = faction_data.members.find_custom(func(m): return m.polity == country_name)
			if index != -1:
				return faction_data.members[index]
	return null


func update_member_status(faction_name: String, member_name: String, status: int) -> void:
	if not faction_name in factions:
		return
	var faction_data = factions[faction_name]
	var index = faction_data.members.find_custom(func(m): return m.polity == member_name)
	if index != -1:
		faction_data.members[index].status = FactionMember.GetString(status)
