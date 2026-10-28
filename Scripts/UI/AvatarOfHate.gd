extends Control


@export var USSR: Array[Texture]
@export var AvatarImage: TextureRect
@export_dir var directory_path: String

func _ready() -> void:
	if directory_path != "":
		_load_images_from_dir(directory_path)

func _load_images_from_dir(path: String) -> void:
	# ResourceLoader.list_directory works in exported builds, where the original
	# .png files are stripped and DirAccess only sees the .import/.remap files.
	var files := ResourceLoader.list_directory(path)
	if files.is_empty():
		printerr("AvatarOfHate: No resources found in directory: ", path)
		return
	for file_name in files:
		if file_name.ends_with("/"):
			continue
		var ext = file_name.get_extension().to_lower()
		if ext in ["png", "jpg", "jpeg", "webp", "svg"]:
			var tex = load(path.path_join(file_name))
			if tex is Texture:
				USSR.append(tex)

func OnTimerTimeout() -> void:
	AvatarImage.texture = USSR.pick_random()
