extends SceneTree
## Headless: regenerate posture_sit / posture_cover PNGs from procedural drawers.
## godot --headless --path client -s res://tools/export_posture_icons.gd


func _init() -> void:
	var dir := ProjectSettings.globalize_path("res://assets/hud/")
	_save(dir + "posture_sit.png", ZZHudIcons._draw_posture_sit(128))
	_save(dir + "posture_cover.png", ZZHudIcons._draw_posture_cover(128))
	print("wrote posture_sit.png + posture_cover.png")
	quit(0)


func _save(path: String, img: Image) -> void:
	var err := img.save_png(path)
	if err != OK:
		push_error("save failed %s err=%s" % [path, err])
