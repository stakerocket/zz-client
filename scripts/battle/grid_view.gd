extends Node3D
class_name ZZGridView

## Rectangular hex map: offset col/row (x/y), pointy-top odd-r — same as server.
## Size comes from server (`state.grid_w` / `grid_h`); defaults match server constants.
## World plane is XZ (y = up).
static var GRID_COLS := 40 # X / width
static var GRID_ROWS := 30 # Y / height
const HEX_SIZE := 0.5 # center → vertex; ~1 m vertex-to-vertex across
const HEX_THICK := 0.08 # only for unit/path pads (no full-map grid)

signal tile_clicked(grid_pos: Vector2i)
signal tile_hovered(grid_pos: Vector2i)

var _highlight: Vector2i = Vector2i(-1, -1)
var _walls: Dictionary = {} # "x,y" -> kind string
var _path_cells: Array = [] # Vector2i including start
var _path_ap: int = 0
var _path_affordable_ap: int = 0
var _path_affordable_steps: int = 0
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _last_hover_emit: Vector2i = Vector2i(-999, -999)
var _aim_from: Vector2i = Vector2i(-1, -1)
var _aim_to: Vector2i = Vector2i(-1, -1)
var _aim_weapon_range: int = 0

var _floor_mm: MultiMeshInstance3D
var _overlay_mm: MultiMeshInstance3D
var _walls_root: Node3D
var _ground: MeshInstance3D
var _aim_mesh: MeshInstance3D
var _path_label: Label3D
var _mat_pad: StandardMaterial3D
var _mat_path_ok: StandardMaterial3D
var _mat_path_over: StandardMaterial3D
var _mat_hl: StandardMaterial3D
var _mat_own_outline: StandardMaterial3D
var _mat_enemy_outline: StandardMaterial3D
var _mat_ground: StandardMaterial3D
var _hex_mesh: ArrayMesh
var _hex_overlay_mesh: ArrayMesh
var _hex_outline_mesh: ArrayMesh
var _built := false
var _own_cell: Vector2i = Vector2i(-1, -1)
var _enemy_cells: Array = [] # Vector2i
var _outlines_root: Node3D
## Optional: screen → unit hex (so aim works on torso/head, not only feet).
var unit_cell_pick: Callable


func _ready() -> void:
	_build_materials()
	# ~1.0 = tiles touch; smaller values were leaving wide dirt "frames".
	_hex_mesh = _make_hex_prism(HEX_SIZE * 0.96, HEX_THICK)
	_hex_overlay_mesh = _make_hex_prism(HEX_SIZE * 0.94, HEX_THICK)
	_hex_outline_mesh = _make_hex_outline_mesh(HEX_SIZE * 0.98)
	_ground = MeshInstance3D.new()
	_ground.name = "DirtBed"
	add_child(_ground)
	# Full hex grid disabled — pads only under units / path preview.
	_floor_mm = MultiMeshInstance3D.new()
	_floor_mm.name = "Floor"
	_floor_mm.visible = false
	add_child(_floor_mm)
	_overlay_mm = MultiMeshInstance3D.new()
	_overlay_mm.name = "Overlay"
	add_child(_overlay_mm)
	_outlines_root = Node3D.new()
	_outlines_root.name = "UnitOutlines"
	add_child(_outlines_root)
	_walls_root = Node3D.new()
	_walls_root.name = "Walls"
	add_child(_walls_root)
	_aim_mesh = MeshInstance3D.new()
	_aim_mesh.name = "AimRay"
	add_child(_aim_mesh)
	_path_label = Label3D.new()
	_path_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_path_label.font_size = 48
	_path_label.outline_size = 8
	_path_label.position = Vector3(0, 1.2, 0)
	_path_label.visible = false
	add_child(_path_label)
	_rebuild_floor()
	_built = true


func grid_to_world(col: int, row: int) -> Vector3:
	var x := HEX_SIZE * sqrt(3.0) * (float(col) + 0.5 * float(row & 1))
	var z := HEX_SIZE * 1.5 * float(row)
	# Units / props sit on the slab top.
	return Vector3(x, HEX_THICK, z)


func world_to_grid(world: Vector3) -> Vector2i:
	var flat := Vector2(world.x, world.z)
	var q := (sqrt(3.0) / 3.0 * flat.x - 1.0 / 3.0 * flat.y) / HEX_SIZE
	var r := (2.0 / 3.0 * flat.y) / HEX_SIZE
	var axial := _axial_round(q, r)
	var approx := _axial_to_offset(axial.x, axial.y)
	# Clamp first, then nearest among seed + 2 rings so border outer halves
	# still resolve to a real edge hex under the oblique camera.
	var seed := Vector2i(
		clampi(approx.x, 0, GRID_COLS - 1),
		clampi(approx.y, 0, GRID_ROWS - 1)
	)
	var best := seed
	var best_d := _flat_dist_sq(grid_to_world(seed.x, seed.y), world)
	var seen: Dictionary = {ZZLos.wall_key(seed.x, seed.y): true}
	var ring: Array = [seed]
	for _depth in 2:
		var next_ring: Array = []
		for cell in ring:
			var c: Vector2i = cell
			for d in ZZLos.NEIGHBOR_DIRS[c.y & 1]:
				var n: Vector2i = c + d
				if not in_bounds(n):
					continue
				var nk := ZZLos.wall_key(n.x, n.y)
				if seen.has(nk):
					continue
				seen[nk] = true
				next_ring.append(n)
				var dd := _flat_dist_sq(grid_to_world(n.x, n.y), world)
				if dd < best_d:
					best_d = dd
					best = n
		ring = next_ring
	return best


func map_xz_bounds() -> Rect2:
	## Inclusive XZ bounds covering border hex vertices (for camera + picking).
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for c in [
		grid_to_world(0, 0),
		grid_to_world(GRID_COLS - 1, 0),
		grid_to_world(0, GRID_ROWS - 1),
		grid_to_world(GRID_COLS - 1, GRID_ROWS - 1),
		grid_to_world(0, 1),
		grid_to_world(GRID_COLS - 1, 1),
	]:
		min_x = minf(min_x, c.x)
		max_x = maxf(max_x, c.x)
		min_z = minf(min_z, c.z)
		max_z = maxf(max_z, c.z)
	var pad := HEX_SIZE
	return Rect2(
		Vector2(min_x - pad, min_z - pad),
		Vector2((max_x - min_x) + pad * 2.0, (max_z - min_z) + pad * 2.0)
	)


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < GRID_COLS and c.y < GRID_ROWS


func set_map_size(cols: int, rows: int) -> void:
	## Authoritative size from server battle state (`grid_w` / `grid_h`).
	var c := maxi(1, cols)
	var r := maxi(1, rows)
	if c == GRID_COLS and r == GRID_ROWS and _ground != null and _ground.mesh != null:
		return
	GRID_COLS = c
	GRID_ROWS = r
	_rebuild_ground_bed()


func map_center() -> Vector3:
	var a := grid_to_world(0, 0)
	var b := grid_to_world(GRID_COLS - 1, GRID_ROWS - 1)
	return (a + b) * 0.5


func map_extents() -> Vector3:
	## Half-size of map AABB on XZ (y unused).
	var half := Vector3.ZERO
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for c in [
		grid_to_world(0, 0),
		grid_to_world(GRID_COLS - 1, 0),
		grid_to_world(0, GRID_ROWS - 1),
		grid_to_world(GRID_COLS - 1, GRID_ROWS - 1),
	]:
		min_x = minf(min_x, c.x)
		max_x = maxf(max_x, c.x)
		min_z = minf(min_z, c.z)
		max_z = maxf(max_z, c.z)
	# Pad past border hex vertices so oblique edge clicks still hit.
	half.x = (max_x - min_x) * 0.5 + HEX_SIZE * 1.5
	half.z = (max_z - min_z) * 0.5 + HEX_SIZE * 1.5
	return half


## Kept for callers that used 2D map size; returns (width, depth) on XZ.
func map_pixel_size() -> Vector2:
	var e := map_extents()
	return Vector2(e.x * 2.0, e.z * 2.0)


func is_hex_neighbor(a: Vector2i, b: Vector2i) -> bool:
	return ZZLos.is_hex_neighbor(a.x, a.y, b.x, b.y)


func set_highlight(pos: Vector2i) -> void:
	_highlight = pos
	_rebuild_overlay()


## Unit hex pads/outlines disabled — map shows path/aim only.
func set_unit_outlines(_own: Vector2i, _enemies: Array) -> void:
	clear_unit_outlines()


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
	if affordable_ap < 0:
		_path_affordable_ap = ap_cost
	else:
		_path_affordable_ap = affordable_ap
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


func set_aim_ray(from: Vector2i, to: Vector2i, weapon_range: int) -> void:
	_aim_from = from
	_aim_to = to
	_aim_weapon_range = maxi(0, weapon_range)
	_rebuild_aim()


func clear_aim_ray() -> void:
	if _aim_from.x < 0 and _aim_to.x < 0:
		return
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


func screen_to_ground(screen_pos: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	# Intersect slab top plane so picking matches unit feet.
	var plane_y := HEX_THICK
	if absf(dir.y) < 0.0001:
		return Vector3(from.x, plane_y, from.z)
	var t := (plane_y - from.y) / dir.y
	if t < 0.0:
		return Vector3.ZERO
	return from + dir * t


func _flat_dist_sq(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz


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


func _build_materials() -> void:
	_mat_pad = _make_mat(Color(0.40, 0.38, 0.35, 1.0))
	_mat_pad.roughness = 0.9
	_mat_ground = _make_mat(Color(0.18, 0.16, 0.14, 1.0))
	_mat_ground.roughness = 1.0
	_mat_path_ok = _make_mat(Color(0.45, 0.72, 0.42, 0.78), true)
	_mat_path_over = _make_mat(Color(0.50, 0.48, 0.45, 0.7), true)
	_mat_hl = _make_mat(Color(0.55, 0.78, 0.40, 0.82), true)
	_mat_own_outline = _make_line_mat(Color(0.35, 0.78, 1.0, 1.0))
	_mat_enemy_outline = _make_line_mat(Color(0.95, 0.28, 0.22, 1.0))


func _make_mat(col: Color, transparent: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.88
	m.metallic = 0.0
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_line_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 1
	return m


func _hex_ring(size: float, y: float) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in 6:
		var angle := deg_to_rad(-30.0 + 60.0 * float(i))
		pts.append(Vector3(cos(angle) * size, y, sin(angle) * size))
	return pts


func _make_hex_top(size: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := _hex_ring(size, y)
	var center := Vector3(0, y, 0)
	var n := Vector3.UP
	for i in 6:
		var j := (i + 1) % 6
		st.set_normal(n)
		st.add_vertex(center)
		st.set_normal(n)
		st.add_vertex(pts[i])
		st.set_normal(n)
		st.add_vertex(pts[j])
	st.generate_normals()
	return st.commit()


func _make_hex_prism(size: float, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := _hex_ring(size, thick)
	var bot := _hex_ring(size, 0.0)
	var center_top := Vector3(0, thick, 0)
	# Top cap.
	for i in 6:
		var j := (i + 1) % 6
		st.set_normal(Vector3.UP)
		st.add_vertex(center_top)
		st.set_normal(Vector3.UP)
		st.add_vertex(top[i])
		st.set_normal(Vector3.UP)
		st.add_vertex(top[j])
	# Side walls (outward).
	for i in 6:
		var j := (i + 1) % 6
		var edge := top[j] - top[i]
		var outward := Vector3(edge.z, 0.0, -edge.x).normalized()
		if outward.length_squared() < 0.001:
			outward = Vector3.RIGHT
		st.set_normal(outward)
		st.add_vertex(bot[i])
		st.set_normal(outward)
		st.add_vertex(bot[j])
		st.set_normal(outward)
		st.add_vertex(top[j])
		st.set_normal(outward)
		st.add_vertex(bot[i])
		st.set_normal(outward)
		st.add_vertex(top[j])
		st.set_normal(outward)
		st.add_vertex(top[i])
	st.generate_normals()
	return st.commit()


func _make_hex_outline_mesh(size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.04
	var inner := size * 0.86
	var outer := size
	var n := Vector3.UP
	var outer_pts := _hex_ring(outer, y)
	var inner_pts := _hex_ring(inner, y)
	for i in 6:
		var j := (i + 1) % 6
		st.set_normal(n)
		st.add_vertex(inner_pts[i])
		st.set_normal(n)
		st.add_vertex(outer_pts[i])
		st.set_normal(n)
		st.add_vertex(outer_pts[j])
		st.set_normal(n)
		st.add_vertex(inner_pts[i])
		st.set_normal(n)
		st.add_vertex(outer_pts[j])
		st.set_normal(n)
		st.add_vertex(inner_pts[j])
	return st.commit()


func _rebuild_unit_outlines() -> void:
	if _outlines_root == null:
		return
	for c in _outlines_root.get_children():
		c.queue_free()
	if _own_cell.x >= 0:
		_spawn_unit_pad(_own_cell, _mat_own_outline)
	for e in _enemy_cells:
		if typeof(e) != TYPE_VECTOR2I:
			continue
		var cell: Vector2i = e
		if cell.x < 0:
			continue
		if cell == _own_cell:
			continue
		_spawn_unit_pad(cell, _mat_enemy_outline)


func _spawn_unit_pad(pc: Vector2i, outline_mat: StandardMaterial3D) -> void:
	var base := MeshInstance3D.new()
	base.mesh = _hex_mesh
	base.material_override = _mat_pad
	base.position = Vector3(
		grid_to_world(pc.x, pc.y).x,
		0.0,
		grid_to_world(pc.x, pc.y).z
	)
	_outlines_root.add_child(base)
	var ring := MeshInstance3D.new()
	ring.mesh = _hex_outline_mesh
	ring.material_override = outline_mat
	ring.position = grid_to_world(pc.x, pc.y) + Vector3(0, 0.02, 0)
	_outlines_root.add_child(ring)


func _rebuild_ground_bed() -> void:
	if _ground == null:
		return
	var center := map_center()
	var ext := map_extents()
	var plane := PlaneMesh.new()
	# Keep dirt close to the hex field so void under the chat stays clear gray.
	plane.size = Vector2(ext.x * 2.05, ext.z * 2.05)
	_ground.mesh = plane
	_ground.material_override = _mat_ground
	_ground.position = Vector3(center.x, 0.0, center.z)


func _rebuild_floor() -> void:
	# No full-map hex grid — continuous ground only.
	_rebuild_ground_bed()
	if _floor_mm != null:
		_floor_mm.multimesh = null
		_floor_mm.visible = false


func _rebuild_overlay() -> void:
	if _overlay_mm == null:
		return
	# Clear previous overlay children (colored hex instances).
	for c in _overlay_mm.get_children():
		c.queue_free()
	_overlay_mm.multimesh = null
	var path_keys: Dictionary = {}
	for i in range(_path_cells.size()):
		var pc: Vector2i = _path_cells[i]
		var affordable := i == 0 or i <= _path_affordable_steps
		path_keys[ZZLos.wall_key(pc.x, pc.y)] = true
		_spawn_overlay_hex(pc, _mat_path_ok if affordable else _mat_path_over)
	if _highlight.x >= 0 and not path_keys.has(ZZLos.wall_key(_highlight.x, _highlight.y)):
		_spawn_overlay_hex(_highlight, _mat_hl)


func _spawn_overlay_hex(pc: Vector2i, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _hex_overlay_mesh
	mi.material_override = mat
	# Sit on ground; path pads are the only grid visible while planning.
	var c := grid_to_world(pc.x, pc.y)
	mi.position = Vector3(c.x, 0.0, c.z)
	_overlay_mm.add_child(mi)


func _update_path_label() -> void:
	if _path_label == null:
		return
	if _path_cells.is_empty():
		_path_label.visible = false
		return
	var end: Vector2i = _path_cells[_path_cells.size() - 1]
	var c := grid_to_world(end.x, end.y)
	_path_label.position = c + Vector3(0, 1.6, 0)
	if _path_affordable_ap < _path_ap:
		_path_label.text = "%d / %d ОД" % [_path_affordable_ap, _path_ap]
		_path_label.modulate = Color(0.75, 0.78, 0.82)
	else:
		_path_label.text = "%d ОД" % _path_ap
		_path_label.modulate = Color(0.45, 0.95, 0.55)
	_path_label.visible = true


func _rebuild_aim() -> void:
	if _aim_mesh == null:
		return
	if _aim_from.x < 0 or _aim_to.x < 0 or _aim_from == _aim_to:
		_aim_mesh.mesh = null
		return
	var from_w := grid_to_world(_aim_from.x, _aim_from.y) + Vector3(0, 1.35, 0)
	var to_w := grid_to_world(_aim_to.x, _aim_to.y) + Vector3(0, 1.35, 0)
	var hex_dist := ZZLos.hex_distance(_aim_from.x, _aim_from.y, _aim_to.x, _aim_to.y)
	var mid_w := to_w
	var use_split := false
	if _aim_weapon_range > 0 and hex_dist > _aim_weapon_range:
		var t := float(_aim_weapon_range) / float(hex_dist)
		mid_w = from_w.lerp(to_w, t)
		use_split = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.set_color(Color(0.35, 0.9, 0.45, 0.95))
	st.add_vertex(from_w)
	st.add_vertex(mid_w if use_split else to_w)
	if use_split:
		st.set_color(Color(0.62, 0.64, 0.68, 0.85))
		st.add_vertex(mid_w)
		st.add_vertex(to_w)
	_aim_mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_mesh.material_override = mat


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
		var node := _make_wall_node(kind)
		node.position = grid_to_world(x, y)
		_walls_root.add_child(node)


func _make_cover_noise(seed_v: int, dark: Color, mid: Color, lit: Color) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.11
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([dark, mid, lit])
	const SZ := 64
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)
	for y in SZ:
		for x in SZ:
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var grit := (noise.get_noise_2d(float(x) * 2.7 + 8.0, float(y) * 2.7) + 1.0) * 0.5
			img.set_pixel(x, y, grad.sample(clampf(n * 0.7 + grit * 0.3, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _make_cover_mat(tint: Color, seed_v: int, dark: Color, mid: Color, lit: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _make_cover_noise(seed_v, dark, mid, lit)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.94
	m.metallic = 0.0
	m.uv1_scale = Vector3(1.8, 1.8, 1.8)
	return m


func _add_box_face(st: SurfaceTool, verts: Array, normal: Vector3, col: Color, uvs: Array) -> void:
	# Two triangles: 0-1-2, 0-2-3
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_color(col)
		st.set_uv(uvs[idx])
		st.add_vertex(verts[idx])


func _make_faceted_box(size: Vector3) -> ArrayMesh:
	## Box with darker sides / bottom so edges read under flat lighting.
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var top_c := Color(1.05, 1.05, 1.02, 1.0)
	var side_c := Color(0.55, 0.56, 0.54, 1.0)
	var end_c := Color(0.42, 0.43, 0.41, 1.0)
	var bot_c := Color(0.28, 0.28, 0.27, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Top (+Y)
	_add_box_face(st, [
		Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz)
	], Vector3.UP, top_c, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	# Bottom (-Y)
	_add_box_face(st, [
		Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz)
	], Vector3.DOWN, bot_c, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	# +Z / -Z (long sides)
	_add_box_face(st, [
		Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz)
	], Vector3.FORWARD, side_c, [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
	_add_box_face(st, [
		Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, -hz)
	], Vector3.BACK, side_c, [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
	# +X / -X (ends — darkest)
	_add_box_face(st, [
		Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(hx, hy, -hz), Vector3(hx, -hy, -hz)
	], Vector3.RIGHT, end_c, [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
	_add_box_face(st, [
		Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(-hx, -hy, hz)
	], Vector3.LEFT, end_c, [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
	st.generate_normals()
	return st.commit()


func _spawn_cover_box(parent: Node3D, size: Vector3, mat: StandardMaterial3D, pos: Vector3, yaw_deg: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _make_faceted_box(size)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	parent.add_child(mi)


func _make_wall_node(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"half":
			# Sandbags: 2 stacked rows with offset so facets read as volume.
			var sand := _make_cover_mat(
				Color(0.92, 0.82, 0.62, 1.0), 71,
				Color(0.38, 0.30, 0.18), Color(0.58, 0.48, 0.32), Color(0.78, 0.68, 0.48)
			)
			_spawn_cover_box(root, Vector3(HEX_SIZE * 1.28, 0.42, HEX_SIZE * 0.72), sand, Vector3(0.02, 0.22, 0.0), 18.0)
			_spawn_cover_box(root, Vector3(HEX_SIZE * 1.18, 0.40, HEX_SIZE * 0.68), sand, Vector3(-0.04, 0.62, 0.03), -12.0)
			_spawn_cover_box(root, Vector3(HEX_SIZE * 0.55, 0.38, HEX_SIZE * 0.55), sand, Vector3(0.28, 0.22, 0.18), 40.0)
		"window":
			var concrete := _make_cover_mat(
				Color(0.88, 0.88, 0.86, 1.0), 82,
				Color(0.28, 0.28, 0.27), Color(0.48, 0.47, 0.45), Color(0.68, 0.67, 0.64)
			)
			_spawn_cover_box(root, Vector3(HEX_SIZE * 1.35, 1.05, HEX_SIZE * 0.52), concrete, Vector3(0.0, 0.55, 0.0), 8.0)
			_spawn_cover_box(root, Vector3(HEX_SIZE * 1.15, 0.95, HEX_SIZE * 0.48), concrete, Vector3(0.06, 1.55, -0.02), -6.0)
		_:
			var ruin := _make_cover_mat(
				Color(0.82, 0.80, 0.76, 1.0), 93,
				Color(0.18, 0.17, 0.16), Color(0.36, 0.35, 0.33), Color(0.55, 0.53, 0.50)
			)
			_spawn_cover_box(root, Vector3(HEX_SIZE * 1.42, 1.55, HEX_SIZE * 0.58), ruin, Vector3(0.0, 0.78, 0.0), 5.0)
			_spawn_cover_box(root, Vector3(HEX_SIZE * 1.28, 1.45, HEX_SIZE * 0.52), ruin, Vector3(-0.04, 2.2, 0.03), -4.0)
	return root


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var g := _grid_at_screen((event as InputEventMouseMotion).position)
		if g != _last_hover_emit:
			_last_hover_emit = g
			_hover_cell = g
			tile_hovered.emit(g)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var g := _grid_at_screen((event as InputEventMouseButton).position)
		if in_bounds(g):
			tile_clicked.emit(g)
			get_viewport().set_input_as_handled()


func _grid_at_screen(screen_pos: Vector2) -> Vector2i:
	if unit_cell_pick.is_valid():
		var ucell: Variant = unit_cell_pick.call(screen_pos)
		if typeof(ucell) == TYPE_VECTOR2I:
			var u: Vector2i = ucell
			if in_bounds(u):
				return u
	var ground := screen_to_ground(screen_pos)
	var g := world_to_grid(ground)
	if not in_bounds(g):
		return Vector2i(-1, -1)
	# Accept anything near a real hex center (incl. outer half of border cells).
	var c := grid_to_world(g.x, g.y)
	var max_d := HEX_SIZE * 1.75
	if _flat_dist_sq(c, ground) > max_d * max_d:
		return Vector2i(-1, -1)
	return g
