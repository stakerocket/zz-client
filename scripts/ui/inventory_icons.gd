extends RefCounted
class_name ZZInventoryIcons

## Icons for current catalog item ids (transparent PNG preferred).

const DIR := "res://assets/inventory/"

static var _cache: Dictionary = {}
static var _tight_cache: Dictionary = {}


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


## Crop transparent padding so long thin weapons fill HUD cards like pistols.
static func tex_tight(item_id: String) -> Texture2D:
	var path := path_for(item_id)
	if path == "":
		return null
	var key := path + "#tight"
	if _tight_cache.has(key):
		return _tight_cache[key]
	var src := tex(item_id)
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		_tight_cache[key] = src
		return src
	if img.is_compressed():
		img.decompress()
	var used := img.get_used_rect()
	if used.size.x < 4 or used.size.y < 4:
		_tight_cache[key] = src
		return src
	## Pad 2% so edges aren't clipped when stretched.
	var pad_x := maxi(1, int(used.size.x * 0.02))
	var pad_y := maxi(1, int(used.size.y * 0.02))
	used.position.x = maxi(0, used.position.x - pad_x)
	used.position.y = maxi(0, used.position.y - pad_y)
	used.end.x = mini(img.get_width(), used.end.x + pad_x)
	used.end.y = mini(img.get_height(), used.end.y + pad_y)
	var cropped := img.get_region(used)
	var out := ImageTexture.create_from_image(cropped)
	_tight_cache[key] = out
	return out


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
