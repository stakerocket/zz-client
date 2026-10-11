extends Node2D
class_name ZZGridView

## Rectangular hex map: offset col/row (x/y), pointy-top odd-r — same as server.
const GRID_SIZE := 30
const HEX_SIZE := 18.0 # center → vertex; sized to fit 1280x720 @ ~0.75 zoom

signal tile_clicked(grid_pos: Vector2i)
signal tile_hovered(grid_pos: Vector2i)

var _highlight: Vector2i = Vector2i(-1, -1)
var _walls: Dictionary = {} # "x,y" -> kind string
var _path_cells: Array = [] # Vector2i including start
var _path_ap: int = 0
var _path_affordable_ap: int = 0
var _path_affordable_steps: int = 0 # path cells after start that fit current AP
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _last_hover_emit: Vector2i = Vector2i(-999, -999)
var _aim_from: Vector2i = Vector2i(-1, -1)
var _aim_to: Vector2i = Vector2i(-1, -1)
var _aim_weapon_range: int = 0


func grid_to_world(col: int, row: int) -> Vector2:
	var x := HEX_SIZE * sqrt(3.0) * (float(col) + 0.5 * float(row & 1))
	var y := HEX_SIZE * 1.5 * float(row)
	return Vector2(x, y)


func world_to_grid(world: Vector2) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * world.x - 1.0 / 3.0 * world.y) / HEX_SIZE
	var r := (2.0 / 3.0 * world.y) / HEX_SIZE
	var axial := _axial_round(q, r)
	var approx := _axial_to_offset(axial.x, axial.y)
	# Nearest among approx + neighbors — fewer mis-clicks on hex edges.
	var best := approx
	var best_d := grid_to_world(approx.x, approx.y).distance_squared_to(world)
	for d in ZZLos.NEIGHBOR_DIRS[approx.y & 1]:
		var n: Vector2i = approx + d
		if n.x < 0 or n.y < 0 or n.x >= GRID_SIZE or n.y >= GRID_SIZE:
			continue
		var dd := grid_to_world(n.x, n.y).distance_squared_to(world)
		if dd < best_d:
			best_d = dd
			best = n
	return best


func map_center() -> Vector2:
	var a := grid_to_world(0, 0)
	var b := grid_to_world(GRID_SIZE - 1, GRID_SIZE - 1)
	return (a + b) * 0.5


func map_pixel_size() -> Vector2:
	# Bounding box of the rectangular hex field.
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for corners in [
		grid_to_world(0, 0),
		grid_to_world(GRID_SIZE - 1, 0),
		grid_to_world(0, GRID_SIZE - 1),
		grid_to_world(GRID_SIZE - 1, GRID_SIZE - 1),
	]:
		min_x = minf(min_x, corners.x)
		max_x = maxf(max_x, corners.x)
		min_y = minf(min_y, corners.y)
		max_y = maxf(max_y, corners.y)
	return Vector2(max_x - min_x + HEX_SIZE * 2.0, max_y - min_y + HEX_SIZE * 2.0)


func is_hex_neighbor(a: Vector2i, b: Vector2i) -> bool:
	return ZZLos.is_hex_neighbor(a.x, a.y, b.x, b.y)


func set_highlight(pos: Vector2i) -> void:
	_highlight = pos
	queue_redraw()


func set_path_preview(cells: Array, ap_cost: int, affordable_steps: int = -1, affordable_ap: int = -1) -> void:
	_path_cells = cells.duplicate()
	_path_ap = ap_cost
	# affordable_steps = number of hexes after start; -1 → all affordable
	if affordable_steps < 0:
		_path_affordable_steps = maxi(0, _path_cells.size() - 1)
	else:
		_path_affordable_steps = clampi(affordable_steps, 0, maxi(0, _path_cells.size() - 1))
	if affordable_ap < 0:
		_path_affordable_ap = ap_cost
	else:
		_path_affordable_ap = affordable_ap
	queue_redraw()


func clear_path_preview() -> void:
	if _path_cells.is_empty() and _path_ap == 0:
		return
	_path_cells.clear()
	_path_ap = 0
	_path_affordable_ap = 0
	_path_affordable_steps = 0
	queue_redraw()


func set_aim_ray(from: Vector2i, to: Vector2i, weapon_range: int) -> void:
	_aim_from = from
	_aim_to = to
	_aim_weapon_range = maxi(0, weapon_range)
	queue_redraw()


func clear_aim_ray() -> void:
	if _aim_from.x < 0 and _aim_to.x < 0:
		return
	_aim_from = Vector2i(-1, -1)
	_aim_to = Vector2i(-1, -1)
	_aim_weapon_range = 0
	queue_redraw()


func set_walls(list: Array) -> void:
	_walls.clear()
	for w in list:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var wd: Dictionary = w
		var kind := str(wd.get("kind", "full"))
		if kind == "":
			kind = "full"
		_walls[ZZLos.wall_key(int(wd.get("x", 0)), int(wd.get("y", 0)))] = kind
	queue_redraw()


func clear_walls() -> void:
	_walls.clear()
	queue_redraw()


func has_wall(x: int, y: int) -> bool:
	return _walls.has(ZZLos.wall_key(x, y))


func wall_kind(x: int, y: int) -> String:
	return str(_walls.get(ZZLos.wall_key(x, y), ""))


func walls_dict() -> Dictionary:
	return _walls


func _offset_to_axial(col: int, row: int) -> Vector2i:
	return ZZLos.offset_to_axial(col, row)


func _axial_to_offset(q: int, r: int) -> Vector2i:
	return ZZLos.axial_to_offset(q, r)


func _axial_round(fq: float, fr: float) -> Vector2i:
	var fx := fq
	var fz := fr
	var fy := -fx - fz
	var rx := int(round(fx))
	var ry := int(round(fy))
	var rz := int(round(fz))
	var x_diff := absf(float(rx) - fx)
	var y_diff := absf(float(ry) - fy)
	var z_diff := absf(float(rz) - fz)
	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(rx, rz)


func _draw() -> void:
	var green := Color(0.28, 0.72, 0.38, 1.0)
	var gray := Color(0.45, 0.48, 0.5, 1.0)
	var path_color: Dictionary = {} # key -> bool affordable
	for i in range(_path_cells.size()):
		var pc: Vector2i = _path_cells[i]
		# index 0 = start (always "in budget" visually); steps 1..k green
		var affordable := i == 0 or i <= _path_affordable_steps
		path_color[ZZLos.wall_key(pc.x, pc.y)] = affordable
	for row in GRID_SIZE:
		for col in GRID_SIZE:
			var c := grid_to_world(col, row)
			var fill := Color(0.25, 0.55, 0.32, 1.0) if (col + row) % 2 == 0 else Color(0.22, 0.48, 0.28, 1.0)
			if _highlight == Vector2i(col, row):
				fill = Color(0.45, 0.75, 0.4, 1.0)
			elif path_color.has(ZZLos.wall_key(col, row)):
				fill = green if bool(path_color[ZZLos.wall_key(col, row)]) else gray
			_draw_hex(c, fill, Color(0.12, 0.28, 0.16, 1.0))
			if has_wall(col, row):
				_draw_wall_hex(c, wall_kind(col, row))
	_draw_aim_ray()
	_draw_path_overlay()


func _draw_aim_ray() -> void:
	if _aim_from.x < 0 or _aim_to.x < 0:
		return
	if _aim_from == _aim_to:
		return
	var from_w := grid_to_world(_aim_from.x, _aim_from.y)
	var to_w := grid_to_world(_aim_to.x, _aim_to.y)
	var col_in := Color(0.35, 0.9, 0.45, 0.95)
	var col_out := Color(0.62, 0.64, 0.68, 0.85)
	var hex_dist := ZZLos.hex_distance(_aim_from.x, _aim_from.y, _aim_to.x, _aim_to.y)
	if hex_dist <= 0:
		return
	# Straight world ray; green share matches in-range hex fraction (range / dist).
	if _aim_weapon_range <= 0 or hex_dist <= _aim_weapon_range:
		draw_line(from_w, to_w, col_in, 3.0, true)
		return
	var t := float(_aim_weapon_range) / float(hex_dist)
	var mid_w := from_w.lerp(to_w, t)
	draw_line(from_w, mid_w, col_in, 3.0, true)
	draw_line(mid_w, to_w, col_out, 3.0, true)
	draw_circle(mid_w, 4.0, col_in)


func _draw_path_overlay() -> void:
	if _path_cells.is_empty():
		return
	var pts := PackedVector2Array()
	for p in _path_cells:
		var pc: Vector2i = p
		pts.append(grid_to_world(pc.x, pc.y))
	var col_ok := Color(0.35, 0.9, 0.45, 0.95)
	var col_over := Color(0.7, 0.72, 0.75, 0.85)
	if pts.size() >= 2:
		var split := mini(_path_affordable_steps + 1, pts.size()) # points in green polyline
		if split >= 2:
			draw_polyline(_pack_slice(pts, 0, split), col_ok, 3.0, true)
		if split < pts.size():
			var gray_start := maxi(0, split - 1)
			draw_polyline(_pack_slice(pts, gray_start, pts.size()), col_over, 3.0, true)
	elif pts.size() == 1:
		draw_circle(pts[0], 4.0, col_ok)
	var end: Vector2 = pts[pts.size() - 1]
	var label := "%d ОД" % _path_ap
	var label_col := col_ok
	if _path_affordable_ap < _path_ap:
		label = "%d / %d ОД" % [_path_affordable_ap, _path_ap]
		label_col = col_over
	var font := ThemeDB.fallback_font
	var fs := 13
	var sz := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var origin := end + Vector2(-sz.x * 0.5, -HEX_SIZE - 4.0)
	draw_rect(Rect2(origin + Vector2(-3, -sz.y + 2), sz + Vector2(6, 4)), Color(0.05, 0.08, 0.12, 0.75), true)
	draw_string(font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label_col)


func _pack_slice(pts: PackedVector2Array, begin: int, end_i: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(begin, end_i):
		out.append(pts[i])
	return out


func _hex_corners(center: Vector2, size: float = HEX_SIZE) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(-30.0 + 60.0 * float(i))
		pts.append(center + Vector2(cos(angle), sin(angle)) * size)
	return pts


func _draw_hex(center: Vector2, fill: Color, outline: Color) -> void:
	var points := _hex_corners(center)
	draw_colored_polygon(points, fill)
	draw_polyline(points + PackedVector2Array([points[0]]), outline, 1.5, true)


func _draw_wall_hex(center: Vector2, kind: String) -> void:
	match kind:
		"half":
			# Low sandbag / crate: short, warm, flat — reads as soft cover.
			_draw_wall_tier(
				center, 3.5, HEX_SIZE * 0.88,
				Color(0.78, 0.62, 0.38, 1.0),
				Color(0.42, 0.30, 0.16, 1.0),
				Color(0.55, 0.40, 0.22, 1.0)
			)
			_draw_half_cover_marks(center + Vector2(0, -3.5))
		"window":
			_draw_wall_tier(
				center, 8.0, HEX_SIZE * 0.92,
				Color(0.42, 0.44, 0.48, 1.0),
				Color(0.18, 0.19, 0.22, 1.0),
				Color(0.28, 0.30, 0.34, 1.0)
			)
			_draw_wall_tier(
				center + Vector2(0, -8.0), 8.0, HEX_SIZE * 0.92,
				Color(0.52, 0.54, 0.58, 1.0),
				Color(0.22, 0.23, 0.26, 1.0),
				Color(0.34, 0.36, 0.40, 1.0)
			)
			var hole := _hex_corners(center + Vector2(0, -12.0), HEX_SIZE * 0.38)
			draw_colored_polygon(hole, Color(0.35, 0.62, 0.85, 0.7))
			draw_polyline(hole + PackedVector2Array([hole[0]]), Color(0.15, 0.25, 0.35, 0.9), 1.4, true)
		_:
			# Full hard wall: tall dark concrete stack.
			_draw_wall_tier(
				center, 9.0, HEX_SIZE * 0.95,
				Color(0.36, 0.38, 0.42, 1.0),
				Color(0.14, 0.15, 0.18, 1.0),
				Color(0.24, 0.26, 0.30, 1.0)
			)
			_draw_wall_tier(
				center + Vector2(0, -9.0), 9.0, HEX_SIZE * 0.95,
				Color(0.48, 0.50, 0.54, 1.0),
				Color(0.18, 0.19, 0.22, 1.0),
				Color(0.30, 0.32, 0.36, 1.0)
			)
			# Solid cap so it never reads as an open top.
			var cap := _hex_corners(center + Vector2(0, -18.0), HEX_SIZE * 0.72)
			draw_colored_polygon(cap, Color(0.30, 0.32, 0.36, 1.0))
			draw_polyline(cap + PackedVector2Array([cap[0]]), Color(0.10, 0.11, 0.13, 1.0), 1.5, true)


func _draw_half_cover_marks(top_center: Vector2) -> void:
	# Horizontal sandbag seams on the flat top.
	var w := HEX_SIZE * 0.55
	var ink := Color(0.45, 0.32, 0.16, 0.85)
	for dy in [-2.0, 0.5, 3.0]:
		draw_line(
			top_center + Vector2(-w, dy),
			top_center + Vector2(w, dy),
			ink, 1.4, true
		)


func _draw_wall_tier(
	center: Vector2,
	h: float,
	size: float,
	top_color: Color,
	side_dark: Color,
	side_mid: Color
) -> void:
	var top := _hex_corners(center + Vector2(0, -h), size)
	var base := _hex_corners(center, size)
	draw_colored_polygon(top, top_color)
	for i in 6:
		var j := (i + 1) % 6
		var side := side_mid if i % 2 == 0 else side_dark
		draw_colored_polygon(
			PackedVector2Array([top[i], top[j], base[j], base[i]]),
			side
		)
	draw_polyline(top + PackedVector2Array([top[0]]), side_dark.darkened(0.25), 1.4, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local := to_local(get_global_mouse_position())
		var g := world_to_grid(local)
		if g.x < 0 or g.y < 0 or g.x >= GRID_SIZE or g.y >= GRID_SIZE:
			g = Vector2i(-1, -1)
		if g != _last_hover_emit:
			_last_hover_emit = g
			_hover_cell = g
			tile_hovered.emit(g)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := to_local(get_global_mouse_position())
		var g := world_to_grid(local)
		if g.x >= 0 and g.y >= 0 and g.x < GRID_SIZE and g.y < GRID_SIZE:
			tile_clicked.emit(g)
			get_viewport().set_input_as_handled()
