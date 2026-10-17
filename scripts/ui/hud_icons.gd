extends RefCounted
class_name ZZHudIcons

## Procedural HUD icons — soft white silhouettes on transparent.


static func posture_stand(sz: int = 36) -> Texture2D:
	var img := _blank(sz)
	var c := _ink()
	var cx := sz * 0.50
	# head
	_circle(img, cx, sz * 0.18, sz * 0.10, c)
	# neck + torso
	_line(img, cx, sz * 0.28, cx, sz * 0.58, maxi(2, int(sz * 0.10)), c)
	# arms down at slight angle
	_line(img, cx, sz * 0.34, sz * 0.22, sz * 0.55, maxi(2, int(sz * 0.07)), c)
	_line(img, cx, sz * 0.34, sz * 0.78, sz * 0.55, maxi(2, int(sz * 0.07)), c)
	# legs
	_line(img, cx, sz * 0.58, sz * 0.32, sz * 0.90, maxi(2, int(sz * 0.08)), c)
	_line(img, cx, sz * 0.58, sz * 0.68, sz * 0.90, maxi(2, int(sz * 0.08)), c)
	return _tex(img)


static func posture_run(sz: int = 36) -> Texture2D:
	var img := _blank(sz)
	var c := _ink()
	# leaning forward runner
	_circle(img, sz * 0.62, sz * 0.16, sz * 0.09, c)
	_line(img, sz * 0.56, sz * 0.24, sz * 0.38, sz * 0.52, maxi(2, int(sz * 0.10)), c) # torso
	# arms swing
	_line(img, sz * 0.50, sz * 0.32, sz * 0.18, sz * 0.28, maxi(2, int(sz * 0.07)), c)
	_line(img, sz * 0.50, sz * 0.32, sz * 0.78, sz * 0.48, maxi(2, int(sz * 0.07)), c)
	# stride legs
	_line(img, sz * 0.40, sz * 0.50, sz * 0.22, sz * 0.88, maxi(2, int(sz * 0.08)), c)
	_line(img, sz * 0.40, sz * 0.50, sz * 0.72, sz * 0.70, maxi(2, int(sz * 0.08)), c)
	_line(img, sz * 0.72, sz * 0.70, sz * 0.86, sz * 0.90, maxi(2, int(sz * 0.07)), c)
	return _tex(img)


static func posture_sit(sz: int = 36) -> Texture2D:
	var img := _blank(sz)
	var c := _ink()
	var cx := sz * 0.50
	_circle(img, cx, sz * 0.22, sz * 0.10, c)
	# upright torso
	_line(img, cx, sz * 0.32, cx, sz * 0.55, maxi(2, int(sz * 0.10)), c)
	# arms resting on knees
	_line(img, cx, sz * 0.38, sz * 0.26, sz * 0.58, maxi(2, int(sz * 0.07)), c)
	_line(img, cx, sz * 0.38, sz * 0.74, sz * 0.58, maxi(2, int(sz * 0.07)), c)
	# thighs horizontal + shins down
	_line(img, cx, sz * 0.55, sz * 0.22, sz * 0.58, maxi(2, int(sz * 0.09)), c)
	_line(img, cx, sz * 0.55, sz * 0.78, sz * 0.58, maxi(2, int(sz * 0.09)), c)
	_line(img, sz * 0.22, sz * 0.58, sz * 0.22, sz * 0.88, maxi(2, int(sz * 0.08)), c)
	_line(img, sz * 0.78, sz * 0.58, sz * 0.78, sz * 0.88, maxi(2, int(sz * 0.08)), c)
	return _tex(img)


static func posture_cover(sz: int = 36) -> Texture2D:
	var img := _blank(sz)
	var c := _ink()
	var wall := Color(0.78, 0.76, 0.72, 1)
	# cover block
	_rect(img, sz * 0.08, sz * 0.42, sz * 0.28, sz * 0.48, wall)
	_rect(img, sz * 0.06, sz * 0.38, sz * 0.34, sz * 0.07, wall)
	# crouched figure behind / peeking
	_circle(img, sz * 0.66, sz * 0.30, sz * 0.09, c)
	_line(img, sz * 0.58, sz * 0.38, sz * 0.48, sz * 0.58, maxi(2, int(sz * 0.09)), c)
	# kneeling legs
	_line(img, sz * 0.48, sz * 0.56, sz * 0.70, sz * 0.58, maxi(2, int(sz * 0.08)), c)
	_line(img, sz * 0.48, sz * 0.56, sz * 0.42, sz * 0.88, maxi(2, int(sz * 0.08)), c)
	_line(img, sz * 0.70, sz * 0.58, sz * 0.78, sz * 0.88, maxi(2, int(sz * 0.07)), c)
	# arm on cover
	_line(img, sz * 0.54, sz * 0.42, sz * 0.30, sz * 0.40, maxi(2, int(sz * 0.07)), c)
	return _tex(img)


static func medkit(sz: int = 64) -> Texture2D:
	var img := _blank(sz)
	var c := _ink()
	_rounded_rect(img, sz * 0.16, sz * 0.28, sz * 0.68, sz * 0.56, int(sz * 0.06), c)
	_rect(img, sz * 0.34, sz * 0.16, sz * 0.32, sz * 0.10, c)
	_rect(img, sz * 0.34, sz * 0.12, sz * 0.08, sz * 0.14, c)
	_rect(img, sz * 0.58, sz * 0.12, sz * 0.08, sz * 0.14, c)
	var clear := Color(0, 0, 0, 0)
	_rect(img, sz * 0.42, sz * 0.40, sz * 0.16, sz * 0.32, clear)
	_rect(img, sz * 0.34, sz * 0.48, sz * 0.32, sz * 0.16, clear)
	var cross := Color(0.95, 0.35, 0.32, 1)
	_rect(img, sz * 0.44, sz * 0.42, sz * 0.12, sz * 0.28, cross)
	_rect(img, sz * 0.36, sz * 0.50, sz * 0.28, sz * 0.12, cross)
	return _tex(img)


static func rifle(w: int = 120, h: int = 40) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := _ink()
	_rect(img, w * 0.08, h * 0.38, w * 0.55, h * 0.16, c)
	_rect(img, w * 0.48, h * 0.28, w * 0.28, h * 0.36, c)
	_rect(img, w * 0.74, h * 0.30, w * 0.18, h * 0.32, c)
	_rect(img, w * 0.88, h * 0.22, w * 0.06, h * 0.48, c)
	_rect(img, w * 0.58, h * 0.58, w * 0.10, h * 0.28, c)
	_rect(img, w * 0.22, h * 0.26, w * 0.04, h * 0.14, c)
	_rect(img, w * 0.52, h * 0.62, w * 0.06, h * 0.20, c)
	return _tex(img)


static func pistol(w: int = 80, h: int = 40) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := _ink()
	# short slide + grip
	_rect(img, w * 0.12, h * 0.28, w * 0.52, h * 0.22, c)
	_rect(img, w * 0.48, h * 0.22, w * 0.22, h * 0.34, c)
	_rect(img, w * 0.52, h * 0.52, w * 0.16, h * 0.34, c)
	_rect(img, w * 0.58, h * 0.58, w * 0.08, h * 0.22, c)
	return _tex(img)


static func bullet(sz: int = 10) -> Texture2D:
	var img := _blank(sz)
	var c := _ink()
	_rect(img, sz * 0.30, sz * 0.18, sz * 0.40, sz * 0.62, c)
	_circle(img, sz * 0.50, sz * 0.16, sz * 0.16, c)
	return _tex(img)


static func undo(sz: int = 36) -> Texture2D:
	var img := _blank(sz)
	var c := _ink()
	var cx := sz * 0.52
	var cy := sz * 0.52
	var r := sz * 0.28
	var thick := maxi(2, int(sz * 0.08))
	for a in range(40, 250):
		var rad := deg_to_rad(float(a))
		_disc(img, int(cx + cos(rad) * r), int(cy - sin(rad) * r), thick / 2, c)
	var tip_a := deg_to_rad(250.0)
	var tip := Vector2(cx + cos(tip_a) * r, cy - sin(tip_a) * r)
	_rect(img, tip.x - sz * 0.02, tip.y - sz * 0.02, sz * 0.18, sz * 0.07, c)
	_rect(img, tip.x - sz * 0.02, tip.y - sz * 0.02, sz * 0.07, sz * 0.18, c)
	return _tex(img)


static func icon_reload(sz: int = 16) -> Texture2D:
	var img := _blank(sz)
	var c := _ink()
	var cx := sz * 0.50
	var cy := sz * 0.50
	var r := sz * 0.30
	var thick := maxi(1, int(sz * 0.10))
	for a in range(30, 300):
		var rad := deg_to_rad(float(a))
		_disc(img, int(cx + cos(rad) * r), int(cy - sin(rad) * r), thick / 2, c)
	var tip_a := deg_to_rad(30.0)
	var tip := Vector2(cx + cos(tip_a) * r, cy - sin(tip_a) * r)
	_rect(img, tip.x - 1.0, tip.y - sz * 0.02, sz * 0.16, sz * 0.06, c)
	_rect(img, tip.x + sz * 0.06, tip.y - sz * 0.10, sz * 0.06, sz * 0.16, c)
	return _tex(img)


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
