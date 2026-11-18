extends RefCounted
class_name ZZPixelArt

## Runtime placeholder pixel textures (no bake / no external tools).


## Flat hex tile (no slab / no 3D thickness). Fill radius = 0.5 so neighbors flush.
const TILE_DEPTH := 0
const HEX_TEX_DIR := "res://assets/battle/hex/"


static func hex_tile(w: int = 56, face_h: int = 38, fill: Color = Color(0.28, 0.26, 0.22), outline: Color = Color(0.08, 0.07, 0.06)) -> ImageTexture:
	return hex_tile_variant("dirt", 0, w, face_h, fill, outline)


static func hex_tile_from_file(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func hex_tile_paths() -> Array:
	## Photo-cropped variants (preferred). Order matches grid_view weights.
	return [
		HEX_TEX_DIR + "hex_dirt_01.png",
		HEX_TEX_DIR + "hex_dirt_02.png",
		HEX_TEX_DIR + "hex_cracked_01.png",
		HEX_TEX_DIR + "hex_cracked_02.png",
		HEX_TEX_DIR + "hex_grass_01.png",
		HEX_TEX_DIR + "hex_grass_02.png",
		HEX_TEX_DIR + "hex_rubble_01.png",
		HEX_TEX_DIR + "hex_scorched_01.png",
	]


static func hex_tile_variant(
	kind: String = "dirt",
	seed: int = 0,
	w: int = 56,
	face_h: int = 38,
	fill: Color = Color(0.30, 0.28, 0.24),
	outline: Color = Color(0.05, 0.045, 0.04)
) -> ImageTexture:
	## Procedural flat fallback when photo PNG missing.
	var img := Image.create(w, face_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := w * 0.5
	var cy := face_h * 0.5
	var rx := w * 0.5
	var ry := face_h * 0.5
	var pts: Array[Vector2] = _hex_points(cx, cy, rx, ry)
	var base := fill
	match kind:
		"cracked":
			base = Color(0.36, 0.35, 0.33)
		"grass":
			base = Color(0.32, 0.31, 0.24)
		"rubble":
			base = Color(0.33, 0.31, 0.28)
		"scorched":
			base = Color(0.22, 0.20, 0.18)
		_:
			base = Color(0.30, 0.28, 0.24)
	_fill_poly(img, pts, base)
	_texture_hex_face(img, pts, kind, seed, base)
	_stroke_poly(img, pts, outline)
	return ImageTexture.create_from_image(img)


static func hex_tile_depth() -> int:
	return 0


static func hex_outline(w: int = 56, h: int = 38, col: Color = Color(0.35, 0.85, 1.0)) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pts: Array[Vector2] = _hex_points(w * 0.5, h * 0.5, w * 0.5, h * 0.5)
	_stroke_poly(img, pts, col)
	_stroke_poly(img, _hex_points(w * 0.5, h * 0.5, w * 0.42, h * 0.42), Color(col.r, col.g, col.b, 0.35))
	return ImageTexture.create_from_image(img)


static func hex_wash(w: int = 56, h: int = 38, col: Color = Color(0.5, 0.8, 0.4, 0.35)) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	## Pointy-top verts at ±30°: flat-to-flat width = rx*√3. Match HEX_W (=w) so
	## washes share edges. Slight oversize seals raster/sub-pixel seams (clipped by img).
	var rx := float(w) / sqrt(3.0) * 1.02
	var ry := float(h) * 0.5 * 1.02
	var pts: Array[Vector2] = _hex_points(w * 0.5, h * 0.5, rx, ry)
	_fill_poly(img, pts, col)
	return ImageTexture.create_from_image(img)


## Full cover: tall ruined concrete wall with exposed rebar.
static func cover_full(w: int = 56, h: int = 52) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c0 := Color(0.38, 0.37, 0.34)
	var c1 := Color(0.30, 0.29, 0.27)
	var c2 := Color(0.46, 0.45, 0.41)
	var outline := Color(0.05, 0.045, 0.04)
	var rebar := Color(0.42, 0.28, 0.18)
	var rebar_d := Color(0.28, 0.16, 0.10)
	## Main wall body (slight iso lean).
	_fill_rect(img, 10, 14, 34, 34, c0)
	_fill_rect(img, 12, 16, 30, 30, c2.darkened(0.05))
	_fill_rect(img, 14, 18, 10, 28, c1) ## left shade
	_stroke_rect(img, 10, 14, 34, 34, outline)
	## Broken top edge (jagged)
	for i in 7:
		var bx := 10 + i * 5
		var drop := 2 + (i * 3) % 5
		_fill_rect(img, bx, 14, 5, drop, Color(0, 0, 0, 0))
		if i % 2 == 0:
			_draw_rebar(img, bx + 2, 14 + drop - 1, 7 + (i % 3) * 2, rebar, rebar_d)
	## Concrete block stack detail on face
	_stroke_rect(img, 16, 28, 12, 8, outline)
	_stroke_rect(img, 28, 28, 12, 8, outline)
	_stroke_rect(img, 16, 36, 12, 8, outline)
	_stroke_rect(img, 28, 36, 12, 8, outline)
	## Debris at base
	_fill_rect(img, 8, 44, 8, 5, c1)
	_stroke_rect(img, 8, 44, 8, 5, outline)
	_fill_rect(img, 38, 45, 10, 4, c0.darkened(0.1))
	_stroke_rect(img, 38, 45, 10, 4, outline)
	_draw_rebar(img, 40, 42, 6, rebar, rebar_d)
	_outline_opaque(img, outline)
	return ImageTexture.create_from_image(img)


## Half cover: low concrete block / jersey barrier.
static func cover_half(w: int = 56, h: int = 36) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c0 := Color(0.40, 0.39, 0.36)
	var c1 := Color(0.32, 0.31, 0.29)
	var c2 := Color(0.48, 0.47, 0.43)
	var outline := Color(0.05, 0.045, 0.04)
	## Two stacked concrete blocks, slightly offset for depth.
	_fill_rect(img, 8, 18, 40, 14, c0)
	_fill_rect(img, 10, 20, 36, 10, c2)
	_fill_rect(img, 8, 18, 8, 14, c1)
	_stroke_rect(img, 8, 18, 40, 14, outline)
	_fill_rect(img, 12, 10, 32, 12, c0.lightened(0.04))
	_fill_rect(img, 14, 12, 28, 8, c2)
	_fill_rect(img, 12, 10, 6, 12, c1)
	_stroke_rect(img, 12, 10, 32, 12, outline)
	## Seam / wear
	_fill_rect(img, 18, 14, 20, 1, c1)
	_fill_rect(img, 16, 24, 24, 1, c1.darkened(0.05))
	## Tiny rebar stub peeking from crack
	_draw_rebar(img, 44, 16, 5, Color(0.40, 0.26, 0.16), Color(0.26, 0.14, 0.09))
	## Shadow base
	_fill_rect(img, 10, 31, 36, 3, Color(0.12, 0.11, 0.10, 0.55))
	_outline_opaque(img, outline)
	return ImageTexture.create_from_image(img)


## Window / soft cover: ruined wall with a hole and rebar cage.
static func cover_window(w: int = 56, h: int = 48) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c0 := Color(0.37, 0.36, 0.33)
	var c1 := Color(0.28, 0.27, 0.25)
	var outline := Color(0.05, 0.045, 0.04)
	var rebar := Color(0.44, 0.30, 0.18)
	var rebar_d := Color(0.28, 0.16, 0.10)
	## Wall frame
	_fill_rect(img, 10, 10, 36, 34, c0)
	_fill_rect(img, 12, 12, 8, 30, c1)
	_stroke_rect(img, 10, 10, 36, 34, outline)
	## Window hole
	_fill_rect(img, 20, 16, 16, 16, Color(0, 0, 0, 0))
	## Inner rim
	_stroke_rect(img, 20, 16, 16, 16, outline)
	## Rebar grate across opening
	for i in 3:
		var rx := 22 + i * 5
		_draw_rebar(img, rx, 15, 18, rebar, rebar_d)
	for i in 2:
		var ry := 20 + i * 6
		for x in range(21, 35):
			if img.get_pixel(x, ry).a < 0.1:
				img.set_pixel(x, ry, rebar if (x + ry) % 2 == 0 else rebar_d)
	## Broken crown + sticks
	_fill_rect(img, 10, 10, 8, 4, Color(0, 0, 0, 0))
	_draw_rebar(img, 14, 8, 8, rebar, rebar_d)
	_draw_rebar(img, 38, 9, 7, rebar, rebar_d)
	## Rubble pile
	_fill_rect(img, 14, 40, 10, 5, c1)
	_stroke_rect(img, 14, 40, 10, 5, outline)
	_fill_rect(img, 30, 41, 12, 4, c0.darkened(0.08))
	_stroke_rect(img, 30, 41, 12, 4, outline)
	_outline_opaque(img, outline)
	return ImageTexture.create_from_image(img)


## Back-compat aliases (old names).
static func cover_sandbags(w: int = 56, h: int = 52) -> ImageTexture:
	return cover_full(w, h)


static func cover_barrier(w: int = 56, h: int = 36) -> ImageTexture:
	return cover_half(w, h)


static func cover_ruin(w: int = 56, h: int = 48) -> ImageTexture:
	return cover_window(w, h)


static func _draw_rebar(img: Image, x: int, y: int, length: int, col: Color, col_d: Color) -> void:
	## Vertical rod with slight bend / rust speckles.
	for i in length:
		var xx := clampi(x + ((i / 3) % 2), 0, img.get_width() - 1)
		var yy := clampi(y - i, 0, img.get_height() - 1)
		img.set_pixel(xx, yy, col if i % 2 == 0 else col_d)
		if xx + 1 < img.get_width() and i % 4 == 0:
			img.set_pixel(xx + 1, yy, col_d)


static func unit_frame(pose: String, team: Color, armed: bool = false, frame: int = 0) -> ImageTexture:
	var w := 48
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var outline := Color(0.05, 0.05, 0.05)
	var body := Color(team.r * 0.45 + 0.15, team.g * 0.45 + 0.18, team.b * 0.35 + 0.12)
	var cloth := Color(0.28, 0.34, 0.26)
	var skin := Color(0.72, 0.58, 0.46)
	var bob := 0
	if pose == "run" or pose == "walk":
		bob = (frame % 2) * 2
	var crouch := pose == "sit" or pose == "cover"
	var y_off := 10 if crouch else 0
	## Legs
	var leg_y := 44 + y_off + bob
	if pose == "run":
		_fill_rect(img, 18 - (frame % 2) * 3, leg_y, 5, 14 - y_off / 2, cloth.darkened(0.1))
		_fill_rect(img, 26 + (frame % 2) * 3, leg_y, 5, 14 - y_off / 2, cloth.darkened(0.1))
	elif crouch:
		_fill_rect(img, 16, leg_y, 7, 10, cloth.darkened(0.1))
		_fill_rect(img, 26, leg_y, 7, 10, cloth.darkened(0.1))
	else:
		_fill_rect(img, 18, leg_y, 5, 16, cloth.darkened(0.1))
		_fill_rect(img, 26, leg_y, 5, 16, cloth.darkened(0.1))
	## Torso
	var torso_h := 14 if crouch else 18
	_fill_rect(img, 15, 24 + y_off + bob, 18, torso_h, cloth)
	_stroke_rect(img, 15, 24 + y_off + bob, 18, torso_h, outline)
	## Head
	_fill_rect(img, 18, 12 + y_off + bob, 12, 12, skin)
	_stroke_rect(img, 18, 12 + y_off + bob, 12, 12, outline)
	_fill_rect(img, 17, 10 + y_off + bob, 14, 5, cloth.darkened(0.2)) ## helmet
	## Arms + gun
	if armed:
		_fill_rect(img, 30, 28 + y_off + bob, 14, 3, Color(0.2, 0.2, 0.18))
		_stroke_rect(img, 30, 28 + y_off + bob, 14, 3, outline)
		_fill_rect(img, 12, 28 + y_off + bob, 5, 8, skin)
	else:
		_fill_rect(img, 11, 28 + y_off + bob, 5, 10, skin)
		_fill_rect(img, 32, 28 + y_off + bob, 5, 10, skin)
	if pose == "cover":
		_fill_rect(img, 14, 34 + bob, 20, 8, cloth.darkened(0.25))
	if pose == "death":
		img.fill(Color(0, 0, 0, 0))
		_fill_rect(img, 8, 40, 32, 10, cloth)
		_stroke_rect(img, 8, 40, 32, 10, outline)
		_fill_rect(img, 6, 38, 10, 10, skin)
		_stroke_rect(img, 6, 38, 10, 10, outline)
	## Outer silhouette outline pass
	_outline_opaque(img, outline)
	## Team tint stripe
	_fill_rect(img, 16, 26 + y_off + bob, 16, 3, body)
	return ImageTexture.create_from_image(img)


static func _hex_points(cx: float, cy: float, rx: float, ry: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for i in 6:
		var a := deg_to_rad(-30.0 + 60.0 * float(i))
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts


static func _draw_hex_slab(
	img: Image,
	pts: Array[Vector2],
	depth: int,
	side_a: Color,
	side_b: Color,
	outline: Color
) -> void:
	## Pointy-top verts: 0=NE,1=E,2=SE,3=SW,4=W,5=NW. Extrude bottom three edges.
	var drop := Vector2(0, float(depth))
	var faces: Array = [[1, 2], [2, 3], [3, 4]]
	for fi in faces.size():
		var edge: Array = faces[fi]
		var a: Vector2 = pts[edge[0]]
		var b: Vector2 = pts[edge[1]]
		var quad: Array[Vector2] = [a, b, b + drop, a + drop]
		var col := side_a if fi != 1 else side_b
		_fill_poly(img, quad, col)
		_stroke_poly(img, quad, outline)


static func _texture_hex_face(img: Image, pts: Array[Vector2], kind: String, seed: int, base: Color) -> void:
	var min_x := 9999
	var max_x := -9999
	var min_y := 9999
	var max_y := -9999
	for p in pts:
		min_x = mini(min_x, int(p.x))
		max_x = maxi(max_x, int(p.x))
		min_y = mini(min_y, int(p.y))
		max_y = maxi(max_y, int(p.y))
	min_x = clampi(min_x, 0, img.get_width() - 1)
	max_x = clampi(max_x, 0, img.get_width() - 1)
	min_y = clampi(min_y, 0, img.get_height() - 1)
	max_y = clampi(max_y, 0, img.get_height() - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if not _point_in_poly(Vector2(x + 0.5, y + 0.5), pts):
				continue
			var n := _hash2(x + seed * 3, y + seed * 7)
			var shade := float(n % 5) * 0.018 - 0.036
			if (x + y + seed) % 3 == 0:
				shade -= 0.03
			var c := Color(
				clampf(base.r + shade, 0.0, 1.0),
				clampf(base.g + shade * 0.9, 0.0, 1.0),
				clampf(base.b + shade * 0.75, 0.0, 1.0),
				1.0
			)
			img.set_pixel(x, y, c)
	match kind:
		"cracked":
			_draw_cracks(img, pts, seed, Color(0.10, 0.09, 0.08))
		"grass":
			_draw_grass_tufts(img, pts, seed)
		"rubble":
			_draw_rubble(img, pts, seed)
		"scorched":
			_draw_scorch(img, pts, seed, base)
		_:
			## Light dirt speckles
			for i in 10:
				var px := min_x + _hash2(seed + i * 17, i * 31) % maxi(1, max_x - min_x)
				var py := min_y + _hash2(i * 13, seed + i * 29) % maxi(1, max_y - min_y)
				if _point_in_poly(Vector2(px + 0.5, py + 0.5), pts):
					img.set_pixel(px, py, base.darkened(0.14))


static func _draw_cracks(img: Image, pts: Array[Vector2], seed: int, col: Color) -> void:
	var cx := int((pts[0].x + pts[3].x) * 0.5)
	var cy := int((pts[0].y + pts[3].y) * 0.5)
	for branch in 3:
		var x := cx + (_hash2(seed, branch) % 9) - 4
		var y := cy + (_hash2(branch, seed) % 7) - 3
		var len := 6 + _hash2(seed + branch, 9) % 8
		var dir := Vector2(1 if branch != 1 else -1, 1 if branch != 2 else -1)
		for i in len:
			if _point_in_poly(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(clampi(x, 0, img.get_width() - 1), clampi(y, 0, img.get_height() - 1), col)
			x += int(dir.x) if (i + seed) % 3 != 0 else 0
			y += int(dir.y) if (i + seed) % 2 == 0 else 0
			if _hash2(x, y + seed) % 4 == 0:
				dir = Vector2(dir.y, -dir.x)


static func _draw_grass_tufts(img: Image, pts: Array[Vector2], seed: int) -> void:
	var grass := Color(0.42, 0.46, 0.22)
	var dry := Color(0.50, 0.44, 0.26)
	var min_x := int(pts[4].x) + 2
	var max_x := int(pts[1].x) - 2
	var min_y := int(pts[5].y) + 2
	var max_y := int(pts[2].y) - 2
	for i in 8:
		var px := min_x + _hash2(seed + i * 11, i * 19) % maxi(1, max_x - min_x)
		var py := min_y + _hash2(i * 23, seed + i * 7) % maxi(1, max_y - min_y)
		if not _point_in_poly(Vector2(px + 0.5, py + 0.5), pts):
			continue
		var col := grass if (i + seed) % 2 == 0 else dry
		img.set_pixel(px, py, col)
		if py > 0:
			img.set_pixel(px, py - 1, col.lightened(0.08))
		if px + 1 < img.get_width() and _point_in_poly(Vector2(px + 1.5, py + 0.5), pts):
			img.set_pixel(px + 1, py, col.darkened(0.06))


static func _draw_rubble(img: Image, pts: Array[Vector2], seed: int) -> void:
	var rock := Color(0.40, 0.38, 0.36)
	var rock_d := Color(0.22, 0.21, 0.20)
	for i in 5:
		var px := int(pts[0].x) + (_hash2(seed, i * 41) % 28) - 8
		var py := int(pts[5].y) + (_hash2(i * 17, seed) % 18) + 2
		var rw := 2 + _hash2(i, seed) % 3
		var rh := 2 + _hash2(seed + i, 3) % 2
		for yy in range(py, py + rh):
			for xx in range(px, px + rw):
				if xx < 0 or yy < 0 or xx >= img.get_width() or yy >= img.get_height():
					continue
				if _point_in_poly(Vector2(xx + 0.5, yy + 0.5), pts):
					img.set_pixel(xx, yy, rock if (xx + yy) % 2 == 0 else rock_d)


static func _draw_scorch(img: Image, pts: Array[Vector2], seed: int, base: Color) -> void:
	var cx := int((pts[0].x + pts[3].x) * 0.5) + (_hash2(seed, 1) % 5) - 2
	var cy := int((pts[0].y + pts[3].y) * 0.5) + (_hash2(2, seed) % 5) - 2
	for y in range(cy - 6, cy + 7):
		for x in range(cx - 8, cx + 9):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if not _point_in_poly(Vector2(x + 0.5, y + 0.5), pts):
				continue
			var d := absf(float(x - cx)) * 0.6 + absf(float(y - cy))
			if d < 5.5 + float(_hash2(x, y) % 3) * 0.4:
				img.set_pixel(x, y, base.darkened(0.18 + (5.5 - d) * 0.04))


static func _hash2(a: int, b: int) -> int:
	var n := a * 374761393 + b * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return abs(n)


static func _fill_poly(img: Image, pts: Array[Vector2], col: Color) -> void:
	var min_x := 9999
	var max_x := -9999
	var min_y := 9999
	var max_y := -9999
	for p in pts:
		min_x = mini(min_x, int(p.x))
		max_x = maxi(max_x, int(p.x))
		min_y = mini(min_y, int(p.y))
		max_y = maxi(max_y, int(p.y))
	min_x = clampi(min_x, 0, img.get_width() - 1)
	max_x = clampi(max_x, 0, img.get_width() - 1)
	min_y = clampi(min_y, 0, img.get_height() - 1)
	max_y = clampi(max_y, 0, img.get_height() - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _point_in_poly(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(x, y, col)


static func _dither_poly(img: Image, pts: Array[Vector2], col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if (x + y) % 2 != 0:
				continue
			if _point_in_poly(Vector2(x + 0.5, y + 0.5), pts):
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					img.set_pixel(x, y, col)


static func _stroke_poly(img: Image, pts: Array[Vector2], col: Color) -> void:
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		_line(img, a, b, col)


static func _point_in_poly(p: Vector2, pts: Array[Vector2]) -> bool:
	var inside := false
	var j := pts.size() - 1
	for i in pts.size():
		var pi: Vector2 = pts[i]
		var pj: Vector2 = pts[j]
		if ((pi.y > p.y) != (pj.y > p.y)) and (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y + 0.0001) + pi.x):
			inside = not inside
		j = i
	return inside


static func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var steps := maxi(1, int(a.distance_to(b)))
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var x := clampi(int(round(p.x)), 0, img.get_width() - 1)
		var y := clampi(int(round(p.y)), 0, img.get_height() - 1)
		img.set_pixel(x, y, col)


static func _fill_rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for yy in range(maxi(0, y), mini(img.get_height(), y + h)):
		for xx in range(maxi(0, x), mini(img.get_width(), x + w)):
			img.set_pixel(xx, yy, col)


static func _stroke_rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	_line(img, Vector2(x, y), Vector2(x + w - 1, y), col)
	_line(img, Vector2(x, y + h - 1), Vector2(x + w - 1, y + h - 1), col)
	_line(img, Vector2(x, y), Vector2(x, y + h - 1), col)
	_line(img, Vector2(x + w - 1, y), Vector2(x + w - 1, y + h - 1), col)


static func _outline_opaque(img: Image, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var mark: Array = []
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = int(x) + d.x
				var ny: int = int(y) + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h or img.get_pixel(nx, ny).a < 0.5:
					mark.append(Vector2i(int(x), int(y)))
					break
	for p in mark:
		## Expand outline outward
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = p.x + d.x
			var ny: int = p.y + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if img.get_pixel(nx, ny).a < 0.5:
				img.set_pixel(nx, ny, col)
