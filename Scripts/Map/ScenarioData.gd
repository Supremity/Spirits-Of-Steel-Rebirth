class_name ScenarioData
extends RefCounted

# Scenario data lives in <start_folder>/map_data/, one json file per top level key
# (provinces.json, polities.json, factions.json, ...). The key is the file's basename.
# Falls back to the legacy single <start_folder>/map_data.json if the folder is missing.

const DATA_DIR = "map_data/"
const LEGACY_FILE = "map_data.json"

static func exists(start_folder: String) -> bool:
	start_folder = _with_slash(start_folder)
	return DirAccess.dir_exists_absolute(start_folder + DATA_DIR) \
		or FileAccess.file_exists(start_folder + LEGACY_FILE)

static func load_start(start_folder: String) -> Dictionary:
	start_folder = _with_slash(start_folder)
	var data_dir := start_folder + DATA_DIR
	if DirAccess.dir_exists_absolute(data_dir):
		var result: Dictionary = {}
		for file_name in DirAccess.get_files_at(data_dir):
			if file_name.get_extension() != "json":
				continue
			result[file_name.get_basename()] = _read_json(data_dir + file_name)
		return result

	var legacy = _read_json(start_folder + LEGACY_FILE)
	return legacy if legacy is Dictionary else {}

static func save_split(data: Dictionary, folder: String) -> bool:
	folder = _with_slash(folder)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		push_error("ScenarioData: Failed to create folder: ", folder)
		return false
	for key in data.keys():
		var file := FileAccess.open(folder + str(key) + ".json", FileAccess.WRITE)
		if not file:
			push_error("ScenarioData: Failed to write: ", folder + str(key) + ".json")
			return false
		file.store_string(JSON.stringify(data[key], "\t"))
		file.close()
	return true

static func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ScenarioData: Failed to open: ", path)
		return null
	return JSON.parse_string(file.get_as_text())

static func _with_slash(path: String) -> String:
	return path if path.ends_with("/") else path + "/"
