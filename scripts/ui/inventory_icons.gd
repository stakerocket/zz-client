extends RefCounted
class_name ZZInventoryIcons

## Icons for current catalog item ids (transparent PNG preferred).

const DIR := "res://assets/inventory/"

static var _cache: Dictionary = {}


static func tex(item_id: String) -> Texture2D:
	var path := path_for(item_id)
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	_cache[path] = t
	return t


static func path_for(item_id: String) -> String:
	var base := ""
	match item_id:
		"kar98":
			base = "icon_rifle"
		"glock17":
			base = "icon_pistol"
		"medkit_small":
			base = "icon_medkit"
		"ammo_7.62mm":
			base = "icon_ammo_rifle"
		"ammo_9mm":
			base = "icon_ammo_pistol"
		"leather_armor":
			base = "icon_vest"
		_:
			return ""
	return DIR + base + ".png"


static func shell_bg() -> Texture2D:
	return _load_tex(DIR + "bg_shell.png")


static func _load_tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	_cache[path] = t
	return t
