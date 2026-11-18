extends Node2D
class_name ZZGridView

## 2D pointy-top odd-r hex map (same coords as server). Screen Y foreshortened ~2:1.

static var GRID_COLS := 60
static var GRID_ROWS := 45
## Pixel spacing: width between flat centers; row pitch ≈ half for iso feel.
const HEX_W := 56.0
const HEX_ROW := 28.0
const TILE_W := 56
const TILE_H := 32

signal tile_clicked(grid_pos: Vector2i)
signal tile_hovered(grid_pos: Vector2i)

var _highlight: Vector2i = Vector2i(-1, -1)
var _walls: Dictionary = {}
var _path_cells: Array = []
var _path_ap: int = 0
var _path_affordable_ap: int = 0
var _path_affordable_steps: int = 0
var _reach_cells: Array = []
var _range_cells: Array = []
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _last_hover_emit: Vector2i = Vector2i(-999, -999)
var _aim_from: Vector2i = Vector2i(-1, -1)
var _aim_to: Vector2i = Vector2i(-1, -1)
var _aim_weapon_range: int = 0
var _own_cell: Vector2i = Vector2i(-1, -1)
var _enemy_cells: Array = []
var unit_cell_pick: Callable

var _floor: Node2D
var _overlay: Node2D
var _outlines: Node2D
var _walls_root: Node2D
var _aim_line: Line2D
var _path_label: Label
var _tex_tiles: Array = [] ## ImageTexture variants
var _tex_wash_reach: ImageTexture
var _tex_wash_range: ImageTexture
var _tex_wash_path: ImageTexture
var _tex_wash_hl: ImageTexture
var _tex_own: ImageTexture
var _tex_enemy: ImageTexture
var _tex_sand: ImageTexture
var _tex_barrier: ImageTexture
var _tex_ruin: ImageTexture
var _tile_depth := 0
var _built := false


func _ready() -> void:
	_tile_depth = ZZPixelArt.hex_tile_depth()
	_tex_tiles = [
		ZZPixelArt.hex_tile_variant("dirt", 1, TILE_W, TILE_H),
		ZZPixelArt.hex_tile_variant("dirt", 2, TILE_W, TILE_H),
		ZZPixelArt.hex_tile_variant("cracked", 3, TILE_W, TILE_H),
		ZZPixelArt.hex_tile_variant("cracked", 4, TILE_W, TILE_H),
		ZZPixelArt.hex_tile_variant("grass", 5, TILE_W, TILE_H),
		ZZPixelArt.hex_tile_variant("grass", 6, TILE_W, TILE_H),
		ZZPixelArt.hex_tile_variant("rubble", 7, TILE_W, TILE_H),
		ZZPixelArt.hex_tile_variant("scorched", 8, TILE_W, TILE_H),
	]
	_tex_wash_reach = ZZPixelArt.hex_wash(TILE_W, TILE_H, Color(0.55, 0.78, 0.42, 0.28))
	_tex_wash_range = ZZPixelArt.hex_wash(TILE_W, TILE_H, Color(0.85, 0.45, 0.38, 0.30))
	_tex_wash_path = ZZPixelArt.hex_wash(TILE_W, TILE_H, Color(0.55, 0.82, 0.45, 0.45))
	_tex_wash_hl = ZZPixelArt.hex_wash(TILE_W, TILE_H, Color(0.70, 0.90, 0.50, 0.50))
	_tex_own = ZZPixelArt.hex_outline(TILE_W, TILE_H, Color(0.35, 0.85, 1.0))
	_tex_enemy = ZZPixelArt.hex_outline(TILE_W, TILE_H, Color(0.95, 0.30, 0.25))
	_tex_sand = ZZPixelArt.cover_full() ## full cover — ruined wall + rebar
	_tex_barrier = ZZPixelArt.cover_half() ## half — concrete blocks
	_tex_ruin = ZZPixelArt.cover_window() ## window — broken wall + grate

	_floor = Node2D.new()
	_floor.name = "Floor"
	_floor.z_index = 0
	add_child(_floor)
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.z_index = 1
	add_child(_overlay)
	_walls_root = Node2D.new()
	_walls_root.name = "Walls"
	_walls_root.z_index = 2
	add_child(_walls_root)
	_outlines = Node2D.new()
	_outlines.name = "UnitOutlines"
	_outlines.z_index = 3
	add_child(_outlines)
	_aim_line = Line2D.new()
	_aim_line.width = 2.0
	_aim_line.default_color = Color(0.35, 0.9, 0.45, 0.9)
	_aim_line.z_index = 4
	add_child(_aim_line)
	_path_label = Label.new()
	_path_label.add_theme_font_size_override("font_size", 14)
	_path_label.add_theme_color_override("font_color", Color(0.75, 0.92, 0.70))
	_path_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_path_label.add_theme_constant_override("outline_size", 4)
	_path_label.z_index = 5
	_path_label.visible = false
	add_child(_path_label)
	_rebuild_floor()
	_built = true


func grid_to_world(col: int, row: int) -> Vector2:
	var x := HEX_W * (float(col) + 0.5 * float(row & 1))
	var y := HEX_ROW * float(row)
	return Vector2(x, y)


func world_to_grid(world: Vector2) -> Vector2i:
	var approx_row := int(round(world.y / HEX_ROW))
	var approx_col := int(round((world.x / HEX_W) - 0.5 * float(approx_row & 1)))
	var seed := Vector2i(
		clampi(approx_col, 0, GRID_COLS - 1),
		clampi(approx_row, 0, GRID_ROWS - 1)
	)
	var best := seed
	var best_d := grid_to_world(seed.x, seed.y).distance_squared_to(world)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var n := Vector2i(seed.x + dx, seed.y + dy)
			if not in_bounds(n):
				continue
			var dd := grid_to_world(n.x, n.y).distance_squared_to(world)
			if dd < best_d:
				best_d = dd
				best = n
	return best


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < GRID_COLS and c.y < GRID_ROWS


func set_map_size(cols: int, rows: int) -> void:
	var c := maxi(1, cols)
	var r := maxi(1, rows)
	if c == GRID_COLS and r == GRID_ROWS and _built:
		return
	GRID_COLS = c
	GRID_ROWS = r
	_rebuild_floor()
	_rebuild_walls()


func map_center() -> Vector2:
	return (grid_to_world(0, 0) + grid_to_world(GRID_COLS - 1, GRID_ROWS - 1)) * 0.5


func map_extents() -> Vector2:
	## Half-size of map AABB in screen px.
	var a := grid_to_world(0, 0)
	var b := grid_to_world(GRID_COLS - 1, GRID_ROWS - 1)
	return Vector2(absf(b.x - a.x) * 0.5 + HEX_W, absf(b.y - a.y) * 0.5 + HEX_ROW)


func map_pixel_size() -> Vector2:
	var e := map_extents()
	return e * 2.0


func is_hex_neighbor(a: Vector2i, b: Vector2i) -> bool:
	return ZZLos.is_hex_neighbor(a.x, a.y, b.x, b.y)


func set_highlight(pos: Vector2i) -> void:
	_highlight = pos
	_rebuild_overlay()


func set_unit_outlines(own: Vector2i, enemies: Array) -> void:
	_own_cell = own
	_enemy_cells = enemies.duplicate()
	_rebuild_unit_outlines()


func clear_unit_outlines() -> void:
	_own_cell = Vector2i(-1, -1)
	_enemy_cells.clear()
	_rebuild_unit_outlines()


func set_path_preview(cells: Array, ap_cost: int, affordable_steps: int = -1, affordable_ap: int = -1) -> void:
	_path_cells = cells.duplicate()
	_path_ap = ap_cost
	if affordable_steps < 0:
		_path_affordable_steps = maxi(0, _path_cells.size() - 1)
	else:
		_path_affordable_steps = clampi(affordable_steps, 0, maxi(0, _path_cells.size() - 1))
	_path_affordable_ap = ap_cost if affordable_ap < 0 else affordable_ap
	_rebuild_overlay()
	_update_path_label()


func clear_path_preview() -> void:
	if _path_cells.is_empty() and _path_ap == 0:
		return
	_path_cells.clear()
	_path_ap = 0
	_path_affordable_ap = 0
	_path_affordable_steps = 0
	_rebuild_overlay()
	_update_path_label()


func set_reach_preview(cells: Array) -> void:
	_reach_cells = cells.duplicate()
	_rebuild_overlay()


func clear_reach_preview() -> void:
	if _reach_cells.is_empty():
		return
	_reach_cells.clear()
	_rebuild_overlay()


func set_range_preview(cells: Array) -> void:
	_range_cells = cells.duplicate()
	_rebuild_overlay()


func clear_range_preview() -> void:
	if _range_cells.is_empty():
		return
	_range_cells.clear()
	_rebuild_overlay()


func set_aim_ray(from: Vector2i, to: Vector2i, weapon_range: int) -> void:
	_aim_from = from
	_aim_to = to
	_aim_weapon_range = maxi(0, weapon_range)
	_rebuild_aim()


func clear_aim_ray() -> void:
	_aim_from = Vector2i(-1, -1)
	_aim_to = Vector2i(-1, -1)
	_aim_weapon_range = 0
	_rebuild_aim()


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
	_rebuild_walls()


func clear_walls() -> void:
	_walls.clear()
	_rebuild_walls()


func has_wall(x: int, y: int) -> bool:
	return _walls.has(ZZLos.wall_key(x, y))


func wall_kind(x: int, y: int) -> String:
	return str(_walls.get(ZZLos.wall_key(x, y), ""))


func walls_dict() -> Dictionary:
	return _walls


func screen_to_ground(screen_pos: Vector2) -> Vector2:
	## screen_pos is viewport coords; convert via canvas transform of this node.
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _tile_for_cell(col: int, row: int) -> Texture2D:
	if _tex_tiles.is_empty():
		return null
	## Weighted mix: mostly dirt/cracked, some grass/rubble, rare scorched.
	var h: int = absi((col * 73856093) ^ (row * 19349663) ^ ((col + row) * 83492791))
	var bucket: int = h % 100
	var idx: int = 0
	if bucket < 28:
		idx = 0
	elif bucket < 48:
		idx = 1
	elif bucket < 66:
		idx = 2
	elif bucket < 80:
		idx = 3
	elif bucket < 90:
		idx = 4
	elif bucket < 96:
		idx = 5
	elif bucket < 99:
		idx = 6
	else:
		idx = 7
	return _tex_tiles[idx] as Texture2D


func _rebuild_floor() -> void:
	if _floor == null:
		return
	for c in _floor.get_children():
		c.queue_free()
	var y_fix := float(_tile_depth) * 0.5
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var spr := Sprite2D.new()
			spr.texture = _tile_for_cell(col, row)
			spr.centered = true
			## Face center stays on grid point; slab thickness hangs below.
			spr.position = grid_to_world(col, row) + Vector2(0.0, y_fix)
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_floor.add_child(spr)


func _rebuild_overlay() -> void:
	if _overlay == null:
		return
	for c in _overlay.get_children():
		c.queue_free()
	var path_keys: Dictionary = {}
	for i in range(_path_cells.size()):
		if i > 0 and i > _path_affordable_steps:
			break
		var pc: Vector2i = _path_cells[i]
		path_keys[ZZLos.wall_key(pc.x, pc.y)] = true
	if not _range_cells.is_empty():
		for fc in _range_cells:
			if path_keys.has(ZZLos.wall_key(fc.x, fc.y)):
				continue
			_spawn_wash(fc, _tex_wash_range)
	else:
		for rc in _reach_cells:
			if path_keys.has(ZZLos.wall_key(rc.x, rc.y)):
				continue
			_spawn_wash(rc, _tex_wash_reach)
	for i in range(_path_cells.size()):
		if i > 0 and i > _path_affordable_steps:
			break
		_spawn_wash(_path_cells[i], _tex_wash_path)
	if _highlight.x >= 0:
		_spawn_wash(_highlight, _tex_wash_hl)


func _spawn_wash(pc: Vector2i, tex: Texture2D) -> void:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.position = grid_to_world(pc.x, pc.y)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.add_child(spr)


func _rebuild_unit_outlines() -> void:
	if _outlines == null:
		return
	for c in _outlines.get_children():
		c.queue_free()
	if _own_cell.x >= 0:
		_spawn_outline(_own_cell, _tex_own)
	for e in _enemy_cells:
		if typeof(e) != TYPE_VECTOR2I:
			continue
		var cell: Vector2i = e
		if cell.x < 0 or cell == _own_cell:
			continue
		_spawn_outline(cell, _tex_enemy)


func _spawn_outline(pc: Vector2i, tex: Texture2D) -> void:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.position = grid_to_world(pc.x, pc.y)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_outlines.add_child(spr)


func _rebuild_walls() -> void:
	if _walls_root == null:
		return
	for c in _walls_root.get_children():
		c.queue_free()
	for key in _walls.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 2:
			continue
		var x := int(parts[0])
		var y := int(parts[1])
		var kind := str(_walls[key])
		var spr := Sprite2D.new()
		var y_lift := -10.0
		match kind:
			"half":
				spr.texture = _tex_barrier
				y_lift = -6.0
			"window":
				spr.texture = _tex_ruin
				y_lift = -10.0
			_:
				spr.texture = _tex_sand ## full
				y_lift = -12.0
		spr.centered = true
		spr.position = grid_to_world(x, y) + Vector2(0, y_lift)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_walls_root.add_child(spr)


func _rebuild_aim() -> void:
	if _aim_line == null:
		return
	_aim_line.clear_points()
	if _aim_from.x < 0 or _aim_to.x < 0 or _aim_from == _aim_to:
		return
	var a := grid_to_world(_aim_from.x, _aim_from.y) + Vector2(0, -20)
	var b := grid_to_world(_aim_to.x, _aim_to.y) + Vector2(0, -20)
	_aim_line.add_point(a)
	_aim_line.add_point(b)


func _update_path_label() -> void:
	if _path_label == null:
		return
	if _path_cells.is_empty():
		_path_label.visible = false
		return
	var end: Vector2i = _path_cells[_path_cells.size() - 1]
	var c := grid_to_world(end.x, end.y)
	_path_label.position = c + Vector2(-16, -36)
	var show_ap := _path_affordable_ap if _path_affordable_ap > 0 else _path_ap
	_path_label.text = "%d ОД" % show_ap
	_path_label.visible = show_ap > 0


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var screen := (event as InputEventMouse).position
		var local := screen_to_ground(screen)
		var g := world_to_grid(local)
		if unit_cell_pick.is_valid():
			var picked: Variant = unit_cell_pick.call(screen)
			if typeof(picked) == TYPE_VECTOR2I and picked.x >= 0:
				g = picked
		if g != _last_hover_emit:
			_last_hover_emit = g
			_hover_cell = g
			tile_hovered.emit(g)
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				tile_clicked.emit(g)
				get_viewport().set_input_as_handled()
