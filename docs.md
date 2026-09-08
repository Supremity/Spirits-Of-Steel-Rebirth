# Managers
## AI manager
1. ```increace_world_tension```: takes in an increment amount and clamps it between 0 and 1
2. ```_analyze_frontline_targets```: gets all the enemy provinces neighbouring the enemy troops and increases war score if its an enemy, city or empty province, the blitzkrieg logic looks at the neighbouring neighbouring provinces and attacks if theres is a city in the neighbi=ouring neighbouring provinces
3. ```_handle_peace_movement```: puts troops in cities if there isnt already a troop there
4. ```_get_peace_hubs```: gets a shuffles list of all the cities
5. ```_manage_recruitment```: target recruit clamps the maximum troops it can deploy between 1-10, the target recruit doubles if at war
6. ```_handle_deployment```: deplous to the highest score province or to one of the hubs
7. ```_consider_declaring_war```: based off country strengths, some random change and world tension, has a cooldown, doesnt declare war if broke or has no neighbouring provinces,


