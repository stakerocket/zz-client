extends RefCounted
class_name ZZHudIcons

## HUD icons — prefer assets/hud PNGs; procedural soft silhouettes as fallback.

const HUD_DIR := "res://assets/hud/"

static var _cache: Dictionary = {}


static func posture_stand(sz: int = 36) -> Texture2D:
	var t := _hud_tex("posture_stand", sz)
	if t != null:
		return t
	var img := _blank(sz)
	var c := _ink()
	var cx := sz * 0.50
	_circle(img, cx, sz * 0.16, sz * 0.11, c)
	_line(img, cx, sz * 0.27, cx, sz * 0.56, maxi(3, int(sz * 0.12)), c)
	_line(img, cx, sz * 0.34, sz * 0.18, sz * 0.52, maxi(2, int(sz * 0.08)), c)
	_line(img, cx, sz * 0.34, sz * 0.82, sz * 0.52, maxi(2, int(sz * 0.08)), c)
	_line(img, cx, sz * 0.56, sz * 0.30, sz * 0.92, maxi(3, int(sz * 0.09)), c)
	_line(img, cx, sz * 0.56, sz * 0.70, sz * 0.92, maxi(3, int(sz * 0.09)), c)
	return _tex(img)


static func posture_run(sz: int = 36) -> Texture2D:
	var t := _hud_tex("posture_run", sz)
	if t != null:
		return t
	var img := _blank(sz)
	var c := _ink()
	_circle(img, sz * 0.64, sz * 0.14, sz * 0.10, c)
	_line(img, sz * 0.56, sz * 0.24, sz * 0.36, sz * 0.52, maxi(3, int(sz * 0.11)), c)
	_line(img, sz * 0.50, sz * 0.30, sz * 0.14, sz * 0.26, maxi(2, int(sz * 0.08)), c)
	_line(img, sz * 0.50, sz * 0.30, sz * 0.82, sz * 0.46, maxi(2, int(sz * 0.08)), c)
	_line(img, sz * 0.38, sz * 0.50, sz * 0.18, sz * 0.90, maxi(3, int(sz * 0.09)), c)
	_line(img, sz * 0.38, sz * 0.50, sz * 0.74, sz * 0.68, maxi(3, int(sz * 0.09)), c)
	_line(img, sz * 0.74, sz * 0.68, sz * 0.88, sz * 0.90, maxi(2, int(sz * 0.08)), c)
	return _tex(img)


static func posture_sit(sz: int = 36) -> Texture2D:
	## Crouch / sneak silhouette (low profile, knees bent, leaning forward).
	var t := _hud_tex("posture_sit", sz)
	if t != null:
		return t
	return _tex(_draw_posture_sit(sz))


static func posture_cover(sz: int = 36) -> Texture2D:
	## Prone cover: low to ground, arms forward — no wall.
	var t := _hud_tex("posture_cover", sz)
	if t != null:
		return t
	return _tex(_draw_posture_cover(sz))


static func _draw_posture_sit(sz: int) -> Image:
	## Side-view crouch-sneak: low hips, knees bent, torso lean, arms ready.
	var img := _blank(sz)
	var c := _ink()
	var thick := maxi(2, int(sz * 0.09))
	var torso := maxi(3, int(sz * 0.12))
	_circle(img, sz * 0.58, sz * 0.20, sz * 0.11, c)
	_line(img, sz * 0.52, sz * 0.30, sz * 0.38, sz * 0.55, torso, c) # torso lean
	_line(img, sz * 0.48, sz * 0.34, sz * 0.78, sz * 0.42, thick, c) # front arm
	_line(img, sz * 0.48, sz * 0.38, sz * 0.22, sz * 0.48, thick, c) # back arm
	_line(img, sz * 0.38, sz * 0.55, sz * 0.55, sz * 0.72, torso, c) # front thigh
	_line(img, sz * 0.38, sz * 0.55, sz * 0.22, sz * 0.72, torso, c) # back thigh
	_line(img, sz * 0.55, sz * 0.72, sz * 0.62, sz * 0.92, thick, c) # front shin
	_line(img, sz * 0.22, sz * 0.72, sz * 0.28, sz * 0.92, thick, c) # back shin
	return img


static func _draw_posture_cover(sz: int) -> Image:
	## Flat on ground, facing left; arms stretched forward on dirt — no wall.
	var img := _blank(sz)
	var c := _ink()
	var thick := maxi(2, int(sz * 0.09))
	var body := maxi(3, int(sz * 0.11))
	_circle(img, sz * 0.30, sz * 0.38, sz * 0.10, c) # head low
	_line(img, sz * 0.38, sz * 0.46, sz * 0.78, sz * 0.62, body, c) # torso along ground
	# Both arms forward + hands on ground.
	_line(img, sz * 0.42, sz * 0.50, sz * 0.08, sz * 0.58, thick, c)
	_line(img, sz * 0.44, sz * 0.54, sz * 0.10, sz * 0.70, thick, c)
	_circle(img, sz * 0.06, sz * 0.58, sz * 0.055, c)
	_circle(img, sz * 0.08, sz * 0.72, sz * 0.055, c)
	# Legs tucked / bent at rear.
	_line(img, sz * 0.78, sz * 0.62, sz * 0.92, sz * 0.52, thick, c)
	_line(img, sz * 0.78, sz * 0.62, sz * 0.90, sz * 0.78, thick, c)
	return img


static func medkit(sz: int = 64) -> Texture2D:
	var mock := ZZInventoryIcons.tex("medkit_small")
	if mock != null:
		return mock
	var img := _blank(sz)
	var box := Color(0.92, 0.92, 0.90, 1)
	_rounded_rect(img, sz * 0.14, sz * 0.22, sz * 0.72, sz * 0.58, int(sz * 0.04), box)
	var cross := Color(0.88, 0.18, 0.16, 1)
	_rect(img, sz * 0.44, sz * 0.32, sz * 0.12, sz * 0.38, cross)
	_rect(img, sz * 0.30, sz * 0.44, sz * 0.40, sz * 0.14, cross)
	return _tex(img)


static func rifle(w: int = 120, h: int = 40) -> Texture2D:
	var mock := ZZInventoryIcons.tex("kar98")
	if mock != null:
		return mock
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.78, 0.76, 0.70, 1)
	_rect(img, w * 0.02, h * 0.38, w * 0.34, h * 0.12, c)
	_rect(img, w * 0.28, h * 0.28, w * 0.38, h * 0.32, c)
	_rect(img, w * 0.66, h * 0.30, w * 0.30, h * 0.28, c)
	return _tex(img)


static func pistol(w: int = 80, h: int = 40) -> Texture2D:
	var mock := ZZInventoryIcons.tex("glock17")
	if mock != null:
		return mock
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.78, 0.76, 0.70, 1)
	_rect(img, w * 0.08, h * 0.22, w * 0.58, h * 0.28, c)
	_rect(img, w * 0.48, h * 0.48, w * 0.22, h * 0.42, c)
	return _tex(img)


static func bullet(sz: int = 10) -> Texture2D:
	## Tiny mag-tick bullet (HUD ammo row).
	return ammo_rifle(sz)


static func ammo_rifle(sz: int = 48) -> Texture2D:
	var mock := ZZInventoryIcons.tex("ammo_7.62mm")
	if mock != null:
		return mock
	var img := _blank(sz)
	var brass := Color(0.82, 0.68, 0.28, 1)
	var tip := Color(0.55, 0.52, 0.48, 1)
	var rim := Color(0.70, 0.58, 0.22, 1)
	var cx := sz * 0.50
	var case_w := sz * 0.22
	var case_h := sz * 0.52
	var case_y := sz * 0.28
	_rect(img, cx - case_w * 0.5, case_y, case_w, case_h, brass)
	_rect(img, cx - case_w * 0.55, case_y + case_h - sz * 0.06, case_w * 1.1, sz * 0.06, rim)
	_circle(img, cx, case_y - sz * 0.02, case_w * 0.45, tip)
	_rect(img, cx - case_w * 0.28, case_y - sz * 0.18, case_w * 0.56, sz * 0.18, tip)
	_circle(img, cx, case_y - sz * 0.20, case_w * 0.22, tip)
	return _tex(img)


static func ammo_pistol(sz: int = 48) -> Texture2D:
	var mock := ZZInventoryIcons.tex("ammo_9mm")
	if mock != null:
		return mock
	var img := _blank(sz)
	var brass := Color(0.88, 0.74, 0.32, 1)
	var tip := Color(0.62, 0.58, 0.52, 1)
	var rim := Color(0.72, 0.60, 0.24, 1)
	var cx := sz * 0.50
	var case_w := sz * 0.28
	var case_h := sz * 0.36
	var case_y := sz * 0.38
	_rect(img, cx - case_w * 0.5, case_y, case_w, case_h, brass)
	_rect(img, cx - case_w * 0.58, case_y + case_h - sz * 0.07, case_w * 1.16, sz * 0.07, rim)
	_circle(img, cx, case_y + sz * 0.02, case_w * 0.48, tip)
	_rect(img, cx - case_w * 0.32, case_y - sz * 0.10, case_w * 0.64, sz * 0.14, tip)
	return _tex(img)


static func ammo_box(sz: int = 48) -> Texture2D:
	## Legacy alias → rifle cartridge.
	return ammo_rifle(sz)


static func vest(sz: int = 48) -> Texture2D:
	var mock := ZZInventoryIcons.tex("leather_armor")
	if mock != null:
		return mock
	var img := _blank(sz)
	var c := _ink()
	_rect(img, sz * 0.28, sz * 0.22, sz * 0.44, sz * 0.58, c)
	_rect(img, sz * 0.18, sz * 0.28, sz * 0.16, sz * 0.36, c)
	_rect(img, sz * 0.66, sz * 0.28, sz * 0.16, sz * 0.36, c)
	_rect(img, sz * 0.36, sz * 0.12, sz * 0.10, sz * 0.14, c)
	_rect(img, sz * 0.54, sz * 0.12, sz * 0.10, sz * 0.14, c)
	return _tex(img)


static func undo(sz: int = 36) -> Texture2D:
	## Same crisp circular arrow as reload.png, mirrored (undo = reverse).
	var key := "undo_reload_flip@%d" % maxi(16, sz)
	if _cache.has(key):
		return _cache[key]
	var img := _load_hud_image(HUD_DIR + "reload.png")
	if img != null:
		var side := maxi(16, sz)
		img.convert(Image.FORMAT_RGBA8)
		img.resize(side, side, Image.INTERPOLATE_LANCZOS)
		img.flip_x()
		var out := ImageTexture.create_from_image(img)
		_cache[key] = out
		return out
	## Fallback: same procedural as icon_reload, flipped angles (CCW).
	img = _blank(sz)
	var c := _ink()
	var cx := sz * 0.50
	var cy := sz * 0.50
	var r := sz * 0.32
	var thick := maxi(2, int(sz * 0.14))
	_arc(img, cx, cy, r, 130.0, -150.0, thick, c)
	var tip_a := deg_to_rad(130.0)
	var tip := Vector2(cx + cos(tip_a) * r, cy - sin(tip_a) * r)
	var tang := Vector2(sin(tip_a), cos(tip_a))
	var norm := Vector2(-tang.y, tang.x)
	var ah := maxf(sz * 0.22, 3.0)
	var aw := maxf(sz * 0.16, 2.5)
	_filled_tri(
		img,
		tip + tang * (ah * 0.15),
		tip - tang * ah + norm * aw,
		tip - tang * ah - norm * aw,
		c
	)
	var tex := _tex(img)
	_cache[key] = tex
	return tex


static func icon_reload(sz: int = 16) -> Texture2D:
	## Classic circular refresh arrow — clear at tiny HUD sizes.
	var t := _hud_tex("reload", sz)
	if t != null:
		return t
	var img := _blank(sz)
	var c := _ink()
	var cx := sz * 0.50
	var cy := sz * 0.50
	var r := sz * 0.32
	var thick := maxi(2, int(sz * 0.14))
	# Open arc ~300° clockwise; gap near top-right so arrowhead reads clearly.
	_arc(img, cx, cy, r, 50.0, 330.0, thick, c)
	var tip_a := deg_to_rad(50.0)
	var tip := Vector2(cx + cos(tip_a) * r, cy - sin(tip_a) * r)
	var tang := Vector2(-sin(tip_a), -cos(tip_a)) # clockwise tangent
	var norm := Vector2(-tang.y, tang.x)
	var ah := maxf(sz * 0.22, 3.0)
	var aw := maxf(sz * 0.16, 2.5)
	_filled_tri(
		img,
		tip + tang * (ah * 0.15),
		tip - tang * ah + norm * aw,
		tip - tang * ah - norm * aw,
		c
	)
	return _tex(img)


static func _hud_tex(base: String, target_sz: int) -> Texture2D:
	var path := HUD_DIR + base + ".png"
	var key := "%s@%d" % [path, target_sz]
	if _cache.has(key):
		return _cache[key]
	var img := _load_hud_image(path)
	if img == null:
		return null
	var side := maxi(16, target_sz)
	if base.begins_with("posture"):
		side = maxi(32, target_sz)
	img.convert(Image.FORMAT_RGBA8)
	img.resize(side, side, Image.INTERPOLATE_LANCZOS)
	var out := ImageTexture.create_from_image(img)
	_cache[key] = out
	return out


static func _load_hud_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var src: Texture2D = load(path)
		if src != null:
			var from_tex := src.get_image()
			if from_tex != null:
				return from_tex
	# Raw PNG works before first editor import.
	var abs := ProjectSettings.globalize_path(path)
	var img := Image.new()
	if img.load(abs) == OK:
		return img
	return null


static func _ink() -> Color:
	return Color(0.94, 0.93, 0.90, 1)


static func _blank(sz: int) -> Image:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _tex(img: Image) -> Texture2D:
	return ImageTexture.create_from_image(img)


static func _rect(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	var x0 := maxi(0, int(x))
	var y0 := maxi(0, int(y))
	var x1 := mini(img.get_width(), int(x + w))
	var y1 := mini(img.get_height(), int(y + h))
	for py in range(y0, y1):
		for px in range(x0, x1):
			img.set_pixel(px, py, c)


static func _rounded_rect(img: Image, x: float, y: float, w: float, h: float, _radius: int, c: Color) -> void:
	_rect(img, x, y, w, h, c)


static func _circle(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	var rr := r * r
	var x0 := maxi(0, int(cx - r - 1))
	var y0 := maxi(0, int(cy - r - 1))
	var x1 := mini(img.get_width(), int(cx + r + 2))
	var y1 := mini(img.get_height(), int(cy + r + 2))
	for py in range(y0, y1):
		for px in range(x0, x1):
			var dx := float(px) + 0.5 - cx
			var dy := float(py) + 0.5 - cy
			if dx * dx + dy * dy <= rr:
				img.set_pixel(px, py, c)


static func _disc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	if r <= 0:
		if cx >= 0 and cy >= 0 and cx < img.get_width() and cy < img.get_height():
			img.set_pixel(cx, cy, c)
		return
	_circle(img, float(cx), float(cy), float(r), c)


static func _line(img: Image, x0: float, y0: float, x1: float, y1: float, thickness: int, c: Color) -> void:
	var dx := x1 - x0
	var dy := y1 - y0
	var steps := maxi(1, int(ceil(maxf(absf(dx), absf(dy)))))
	var r := maxi(1, thickness / 2)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		_disc(img, int(x0 + dx * t), int(y0 + dy * t), r, c)


static func _arc(img: Image, cx: float, cy: float, r: float, a0_deg: float, a1_deg: float, thickness: int, c: Color) -> void:
	var steps := maxi(24, int(absf(a1_deg - a0_deg)))
	var rad_r := maxi(1, thickness / 2)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := deg_to_rad(lerpf(a0_deg, a1_deg, t))
		_disc(img, int(cx + cos(a) * r), int(cy - sin(a) * r), rad_r, c)


static func _filled_tri(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var min_x := maxi(0, int(floor(minf(a.x, minf(b.x, c.x)))))
	var max_x := mini(img.get_width() - 1, int(ceil(maxf(a.x, maxf(b.x, c.x)))))
	var min_y := maxi(0, int(floor(minf(a.y, minf(b.y, c.y)))))
	var max_y := mini(img.get_height() - 1, int(ceil(maxf(a.y, maxf(b.y, c.y)))))
	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			var p := Vector2(float(px) + 0.5, float(py) + 0.5)
			if _point_in_tri(p, a, b, c):
				img.set_pixel(px, py, col)


static func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var v0 := c - a
	var v1 := b - a
	var v2 := p - a
	var dot00 := v0.dot(v0)
	var dot01 := v0.dot(v1)
	var dot02 := v0.dot(v2)
	var dot11 := v1.dot(v1)
	var dot12 := v1.dot(v2)
	var inv := 1.0 / (dot00 * dot11 - dot01 * dot01)
	var u := (dot11 * dot02 - dot01 * dot12) * inv
	var v := (dot00 * dot12 - dot01 * dot02) * inv
	return u >= 0.0 and v >= 0.0 and (u + v) <= 1.0
