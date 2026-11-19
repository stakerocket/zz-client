extends Node3D
class_name ZZGridView

## Rectangular hex map: offset col/row (x/y), flat-top odd-q — same as server (Fallout-style).
## Size comes from server (`state.grid_w` / `grid_h`); defaults match server constants.
## 42×36 ≈ square XZ footprint (flat-top) for square battle bg.
## World plane is XZ (y = up).
static var GRID_COLS := 42 # X / width
static var GRID_ROWS := 36 # Y / height
const HEX_SIZE := 0.5 # center → vertex; flat-to-flat ≈ √3 m, vertex-to-vertex = 1 m
const HEX_THICK := 0.08 # only for unit/path pads (no full-map grid)
const GROUND_TEX_PATH := "res://assets/maps/bg.jpg"
## Props: block/block_wall 2×1 (wall = 2 stacked), car 6×2. Scale from mesh AABB.
## car long=X; block long=Z.
const HALF_BLOCK_SCENE := preload("res://assets/maps/block.glb")
const HALF_CAR_SCENE := preload("res://assets/maps/car.glb")

signal tile_clicked(grid_pos: Vector2i)
signal tile_hovered(grid_pos: Vector2i)

var _highlight: Vector2i = Vector2i(-1, -1)
var _walls: Dictionary = {} # "x,y" -> kind string
var _path_cells: Array = [] # Vector2i including start
var _path_ap: int = 0
var _path_affordable_ap: int = 0
var _path_affordable_steps: int = 0
var _reach_cells: Array = [] # Vector2i affordable move targets
var _range_cells: Array = [] # Vector2i weapon range wash
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _last_hover_emit: Vector2i = Vector2i(-999, -999)

var _floor_mm: MultiMeshInstance3D
var _overlay_mm: MultiMeshInstance3D
var _walls_root: Node3D
var _ground: MeshInstance3D
var _path_label: Label3D
var _mat_path_ok: StandardMaterial3D
var _mat_reach: StandardMaterial3D
var _mat_range: StandardMaterial3D
var _mat_hl: StandardMaterial3D
var _mat_block: StandardMaterial3D ## Space clear-mode: blocked hexes
var _mat_own_outline: StandardMaterial3D
var _mat_enemy_outline: StandardMaterial3D
var _mat_ground: StandardMaterial3D
var _hex_wash_mesh: ArrayMesh ## flat top — path / reach / range / highlight
var _hex_outline_mesh: ArrayMesh
var _built := false
var _obstacle_clear_on := false ## Space: hide props, dark wash on wall cells
## MeshInstances under walls — faded when they occlude a unit from the camera.
var _wall_mesh_cache: Array = [] # MeshInstance3D
const OCCLUSION_FADE := 0.72 ## GeometryInstance3D.transparency when blocking a unit
const CAPSULE_HEIGHT_REF := 1.80 ## matches ZZUnitView height for occlusion rays
var _own_cell: Vector2i = Vector2i(-1, -1)
var _enemy_cells: Array = [] # Vector2i
var _outlines_root: Node3D
## Optional: screen → unit hex (so aim works on torso/head, not only feet).
var unit_cell_pick: Callable


func _ready() -> void:
	_build_materials()
	## 0.95 leaves a thin seam between washes (1.0 = flush, 1.01 killed gaps).
	## Wash Y must clear DirtBed (y=0) enough for ortho depth — 0.02 Z-fought → shattered hexes.
	const HEX_OVERLAY_R := HEX_SIZE * 0.95
	const HEX_OUTLINE_R := HEX_SIZE * 0.94
	_hex_wash_mesh = _make_hex_top(HEX_OVERLAY_R, 0.07)
	_hex_outline_mesh = _make_hex_outline_mesh(HEX_OUTLINE_R, 0.075)
	_ground = MeshInstance3D.new()
	_ground.name = "DirtBed"
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_path_label = Label3D.new()
	_path_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_path_label.font_size = 48
	_path_label.outline_size = 8
	_path_label.position = Vector3(0, 0.35, 0)
	_path_label.visible = false
	add_child(_path_label)
	_rebuild_floor()
	_built = true


func grid_to_world(col: int, row: int) -> Vector3:
	## Flat-top odd-q: odd columns shoved down (+Z).
	var x := HEX_SIZE * 1.5 * float(col)
	var z := HEX_SIZE * sqrt(3.0) * (float(row) + 0.5 * float(col & 1))
	# Units / props sit on the slab top.
	return Vector3(x, HEX_THICK, z)


func world_to_grid(world: Vector3) -> Vector2i:
	var flat := Vector2(world.x, world.z)
	## Flat-top inverse (redblobgames).
	var q := (2.0 / 3.0 * flat.x) / HEX_SIZE
	var r := (-1.0 / 3.0 * flat.x + sqrt(3.0) / 3.0 * flat.y) / HEX_SIZE
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
			for d in ZZLos.NEIGHBOR_DIRS[c.x & 1]:
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


func ground_plane_size() -> Vector2:
	## World XZ size of DirtBed (matches _rebuild_ground_bed).
	var e := map_extents()
	return Vector2(e.x * 2.0, e.z * 2.0)


func ground_texel_size() -> Vector2i:
	if _mat_ground != null and _mat_ground.albedo_texture != null:
		var t := _mat_ground.albedo_texture
		return Vector2i(t.get_width(), t.get_height())
	return Vector2i(4096, 4096)


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


func set_reach_preview(_cells: Array) -> void:
	## Reach wash disabled — keep path / highlight / Ctrl range only.
	if not _reach_cells.is_empty():
		_reach_cells.clear()
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


func set_obstacle_clear(on: bool) -> void:
	## Hold Space: hide cover props; dark wash on every blocked hex. Units stay visible.
	if on == _obstacle_clear_on:
		return
	_obstacle_clear_on = on
	if _walls_root != null:
		_walls_root.visible = not on
	_rebuild_overlay()


func clear_obstacle_clear() -> void:
	set_obstacle_clear(false)


func _cache_wall_meshes() -> void:
	_wall_mesh_cache.clear()
	if _walls_root == null:
		return
	for child in _walls_root.find_children("*", "MeshInstance3D", true, false):
		_wall_mesh_cache.append(child)


func _aabb_view_depth_min(ab: AABB, origin: Vector3, view: Vector3) -> float:
	## Nearest AABB corner along camera forward (into the scene).
	var mn := INF
	for i in 8:
		var d: float = (ab.get_endpoint(i) - origin).dot(view)
		if d < mn:
			mn = d
	return mn


func update_occlusion_fade(cam: Camera3D, unit_feet: Array) -> void:
	## Fade when some part of the prop is closer to the camera than the unit and the
	## view-ray hits it. (Requiring the whole fat car AABB in front never fired.)
	if _wall_mesh_cache.is_empty():
		return
	if _obstacle_clear_on or cam == null:
		for mi in _wall_mesh_cache:
			if is_instance_valid(mi):
				(mi as GeometryInstance3D).transparency = 0.0
		return
	var view := -cam.global_transform.basis.z.normalized()
	var cam_pos := cam.global_position
	var occlude: Dictionary = {} # MeshInstance3D -> true
	for feet_v in unit_feet:
		if typeof(feet_v) != TYPE_VECTOR3:
			continue
		var feet: Vector3 = feet_v
		var samples: Array[Vector3] = [
			feet + Vector3(0, 0.35, 0),
			feet + Vector3(0, CAPSULE_HEIGHT_REF * 0.55, 0),
			feet + Vector3(0, CAPSULE_HEIGHT_REF * 0.88, 0),
		]
		for sample in samples:
			var from := sample - view * 80.0
			var unit_d: float = (sample - cam_pos).dot(view)
			for mi in _wall_mesh_cache:
				if not is_instance_valid(mi) or occlude.has(mi):
					continue
				var mesh_i := mi as MeshInstance3D
				if mesh_i.mesh == null:
					continue
				var ab: AABB = mesh_i.global_transform * mesh_i.mesh.get_aabb()
				## Shrink fat GLB padding so side-grazing doesn't count as cover.
				var c := ab.get_center()
				var half := ab.size * 0.38
				ab = AABB(c - half, half * 2.0)
				if not ab.intersects_segment(from, sample):
					continue
				## Unit in front of entire prop → skip; else something blocks the view.
				var prop_near := _aabb_view_depth_min(ab, cam_pos, view)
				if prop_near < unit_d - 0.12:
					occlude[mi] = true
	for mi2 in _wall_mesh_cache:
		if not is_instance_valid(mi2):
			continue
		var g := mi2 as GeometryInstance3D
		g.transparency = OCCLUSION_FADE if occlude.has(mi2) else 0.0


func set_walls(list: Array) -> void:
	_walls.clear()
	for w in list:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var wd: Dictionary = w
		var kind := str(wd.get("kind", "block_wall"))
		if kind == "":
			kind = "block_wall"
		_walls[ZZLos.wall_key(int(wd.get("x", 0)), int(wd.get("y", 0)))] = kind
	_rebuild_walls()
	if _obstacle_clear_on:
		_rebuild_overlay()


func clear_walls() -> void:
	_walls.clear()
	_rebuild_walls()
	if _obstacle_clear_on:
		_rebuild_overlay()


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
	## Shaded so DirectionalLight shadows land on the dirt (unshaded receives none).
	_mat_ground = _make_mat(Color(1, 1, 1, 1.0))
	_mat_ground.roughness = 1.0
	_mat_ground.metallic = 0.0
	var tex: Texture2D = load(GROUND_TEX_PATH) as Texture2D
	if tex != null:
		_mat_ground.albedo_texture = tex
		## No mipmaps: keep texel sharpness at ~1:1 ortho (pan for the rest of the map).
		_mat_ground.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	else:
		_mat_ground.albedo_color = Color(0.18, 0.16, 0.14, 1.0)
	## Flat washes: path / highlight only (no reach “can move here” fill).
	_mat_reach = _make_wash_mat(Color(0.55, 0.78, 0.42, 0.16)) ## unused while reach wash off
	_mat_path_ok = _make_wash_mat(Color(0.55, 0.78, 0.42, 0.28))
	_mat_range = _make_wash_mat(Color(0.85, 0.45, 0.38, 0.16))
	_mat_hl = _make_wash_mat(Color(0.55, 0.78, 0.40, 0.34))
	_mat_block = _make_wash_mat(Color(0.06, 0.05, 0.05, 0.62))
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


func _make_wash_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	## Depth-test ON so unit feet occlude the wash; don't write depth (soft stack of washes).
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = false
	m.render_priority = -2
	return m


func _make_line_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	## Was no_depth_test — ring drew over boots. Depth-test so the model wins.
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = -1
	return m


func _hex_ring(size: float, y: float) -> Array[Vector3]:
	## Flat-top: vertices at 0°, 60°, … (flat edges north/south on XZ).
	var pts: Array[Vector3] = []
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i))
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


func _make_hex_outline_mesh(size: float, y: float = 0.025) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := size * 0.88
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
		_outlines_root.remove_child(c)
		c.free()
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
	# Outline only — same cell center/Y as wash (no raised offset → no pitch parallax).
	var ring := MeshInstance3D.new()
	ring.mesh = _hex_outline_mesh
	ring.material_override = outline_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := grid_to_world(pc.x, pc.y)
	ring.position = Vector3(c.x, 0.0, c.z)
	_outlines_root.add_child(ring)


func _rebuild_ground_bed() -> void:
	if _ground == null:
		return
	var center := map_center()
	var ext := map_extents()
	var plane := PlaneMesh.new()
	# Tight to playable AABB; square bg maps 1:1 when extents.x ≈ extents.z.
	plane.size = Vector2(ext.x * 2.0, ext.z * 2.0)
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
	## free() not queue_free — hover rebuilds every move; deferred free stacked ghost hexes.
	for c in _overlay_mm.get_children():
		_overlay_mm.remove_child(c)
		c.free()
	_overlay_mm.multimesh = null
	var path_keys: Dictionary = {}
	for i in range(_path_cells.size()):
		if i > 0 and i > _path_affordable_steps:
			break
		var pc: Vector2i = _path_cells[i]
		path_keys[ZZLos.wall_key(pc.x, pc.y)] = true
	## Space clear-mode: dark wash on every obstacle hex (under other washes).
	if _obstacle_clear_on and _mat_block != null:
		for key in _walls.keys():
			var parts: PackedStringArray = str(key).split(",")
			if parts.size() < 2:
				continue
			_spawn_overlay_hex(Vector2i(int(parts[0]), int(parts[1])), _mat_block, true)
	## Ctrl range wash only — no “reachable hexes” green fill.
	if not _range_cells.is_empty():
		for fc in _range_cells:
			if typeof(fc) != TYPE_VECTOR2I:
				continue
			var fcell: Vector2i = fc
			if path_keys.has(ZZLos.wall_key(fcell.x, fcell.y)):
				continue
			_spawn_overlay_hex(fcell, _mat_range, true)
	## Path steps only (skip start — unit outline already marks it; wash under feet Z-fights boots).
	for i in range(_path_cells.size()):
		if i == 0:
			continue
		if i > _path_affordable_steps:
			break
		var pc2: Vector2i = _path_cells[i]
		_spawn_overlay_hex(pc2, _mat_path_ok)
	if _highlight.x >= 0 and not path_keys.has(ZZLos.wall_key(_highlight.x, _highlight.y)):
		_spawn_overlay_hex(_highlight, _mat_hl)


func _spawn_overlay_hex(pc: Vector2i, mat: StandardMaterial3D, _soft_wash: bool = true) -> void:
	var mi := MeshInstance3D.new()
	## Flat hex top only — same as reach/range (no extruded prism).
	mi.mesh = _hex_wash_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := grid_to_world(pc.x, pc.y)
	mi.position = Vector3(c.x, 0.0, c.z)
	_overlay_mm.add_child(mi)


func _update_path_label() -> void:
	if _path_label == null:
		return
	## Like 2d: only affordable AP cost, no "X / Y" beyond-budget label.
	var show_ap := _path_affordable_ap if _path_affordable_ap > 0 else 0
	if _path_cells.is_empty() or show_ap <= 0 or _path_affordable_steps <= 0:
		_path_label.visible = false
		return
	## Anchor at last affordable step (not beyond-ОД tip).
	var end_i := clampi(_path_affordable_steps, 0, _path_cells.size() - 1)
	var end: Vector2i = _path_cells[end_i]
	var c := grid_to_world(end.x, end.y)
	## Low over the hex top — was 1.6 (looked sky-high under iso pitch).
	_path_label.position = c + Vector3(0, 0.35, 0)
	_path_label.text = "%d ОД" % show_ap
	_path_label.modulate = Color(0.45, 0.95, 0.55)
	_path_label.visible = true


func _rebuild_walls() -> void:
	if _walls_root == null:
		return
	## Free immediately so mesh cache does not keep queued-for-delete instances.
	while _walls_root.get_child_count() > 0:
		var old: Node = _walls_root.get_child(0)
		_walls_root.remove_child(old)
		old.free()
	_walls_root.visible = not _obstacle_clear_on
	## kind → cells; multi-cell props cluster into one mesh (or stack) each.
	var prop_cells: Dictionary = {} # kind -> Array[Vector2i]
	for key in _walls.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 2:
			continue
		var x := int(parts[0])
		var y := int(parts[1])
		var kind := str(_walls[key])
		## Legacy "full" buckets with block_wall (same prop + tier full).
		var bucket := "block_wall" if kind == "full" else kind
		if bucket == "block" or bucket == "car" or bucket == "half" or bucket == "block_wall":
			if not prop_cells.has(bucket):
				prop_cells[bucket] = []
			(prop_cells[bucket] as Array).append(Vector2i(x, y))
			continue
		var node := _make_wall_node(kind, x, y)
		node.position = grid_to_world(x, y)
		_walls_root.add_child(node)
	for kind in prop_cells.keys():
		var k := str(kind)
		var want := _prop_kind_footprint(k)
		var cells: Array = prop_cells[kind]
		for cluster in _cluster_prop_cells(cells):
			## Split merged neighbors into exact kind rects (2×1 / 6×2) so mesh ↔ black hexes match.
			for rect in _extract_kind_rects(cluster, want.x, want.y):
				var prop := _spawn_prop_cluster(k, rect)
				if prop != null:
					_walls_root.add_child(prop)
	_cache_wall_meshes()


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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	parent.add_child(mi)


func _make_wall_node(_kind: String, _col: int = 0, _row: int = 0) -> Node3D:
	## Window only: low sill + two side posts (open middle) — not the old tall double-box columns.
	var root := Node3D.new()
	var concrete := _make_cover_mat(
		Color(0.88, 0.88, 0.86, 1.0), 82,
		Color(0.28, 0.28, 0.27), Color(0.48, 0.47, 0.45), Color(0.68, 0.67, 0.64)
	)
	var w := HEX_SIZE * 1.55
	var d := HEX_SIZE * 0.42
	## Sill / low wall across the hex.
	_spawn_cover_box(root, Vector3(w, 0.55, d), concrete, Vector3(0.0, 0.28, 0.0), 0.0)
	## Side posts leave a window gap in the middle.
	var post_w := HEX_SIZE * 0.28
	var post_h := 1.15
	_spawn_cover_box(root, Vector3(post_w, post_h, d * 0.95), concrete, Vector3(-w * 0.38, 0.55 + post_h * 0.5, 0.0), 0.0)
	_spawn_cover_box(root, Vector3(post_w, post_h, d * 0.95), concrete, Vector3(w * 0.38, 0.55 + post_h * 0.5, 0.0), 0.0)
	## Thin lintel on top of posts.
	_spawn_cover_box(root, Vector3(w * 0.92, 0.22, d * 0.9), concrete, Vector3(0.0, 0.55 + post_h + 0.11, 0.0), 0.0)
	return root


func _cluster_prop_cells(cells: Array) -> Array:
	## Connected components (one server rect → one mesh).
	var pending: Dictionary = {}
	for c in cells:
		if typeof(c) != TYPE_VECTOR2I:
			continue
		pending[ZZLos.wall_key(c.x, c.y)] = c
	var clusters: Array = []
	while not pending.is_empty():
		var start_key: String = pending.keys()[0]
		var start: Vector2i = pending[start_key]
		pending.erase(start_key)
		var cluster: Array = [start]
		var qi := 0
		while qi < cluster.size():
			var cur: Vector2i = cluster[qi]
			qi += 1
			for n in ZZLos.hex_neighbors(cur.x, cur.y):
				var nk := ZZLos.wall_key(n.x, n.y)
				if not pending.has(nk):
					continue
				pending.erase(nk)
				cluster.append(n)
		clusters.append(cluster)
	return clusters


## Axial neighbor steps (same order as server cubeAxialSteps).
const _AXIAL_STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
## Invariant: prop mesh must stay inside its occupied hexes — never spill onto empty neighbors.
## Scale target = footprint flats * this factor (< 1 leaves a margin at the hex border).
const PROP_FIT := 0.92
## block_wall: upper block sinks this fraction of AABB height so it rests on concrete, not rebar hooks.
const BLOCK_STACK_NEST := 0.30


func _prop_kind_footprint(kind: String) -> Vector2i:
	if kind == "car":
		return Vector2i(6, 2)
	return Vector2i(2, 1) # block / block_wall / half


func _axial_to_ij(ax: Vector2i, origin: Vector2i, sl: Vector2i, sw: Vector2i) -> Vector2i:
	## Solve ax = origin + i*sl + j*sw in axial coords (det ±1 for neighbor steps).
	var dq := ax.x - origin.x
	var dr := ax.y - origin.y
	var det := sl.x * sw.y - sw.x * sl.y
	if det == 0:
		return Vector2i(-99999, -99999)
	var i := (dq * sw.y - sw.x * dr) / det
	var j := (sl.x * dr - dq * sl.y) / det
	if origin.x + i * sl.x + j * sw.x != ax.x or origin.y + i * sl.y + j * sw.y != ax.y:
		return Vector2i(-99999, -99999)
	return Vector2i(i, j)


func _fits_axial_rect(axials: Array[Vector2i], sl: Vector2i, sw: Vector2i, length: int, width: int) -> bool:
	if axials.is_empty() or axials.size() != length * width:
		return false
	var origin: Vector2i = axials[0]
	var min_i := 1 << 30
	var min_j := 1 << 30
	var coords: Array[Vector2i] = []
	for ax in axials:
		var ij := _axial_to_ij(ax, origin, sl, sw)
		if ij.x <= -90000:
			return false
		coords.append(ij)
		min_i = mini(min_i, ij.x)
		min_j = mini(min_j, ij.y)
	var filled: Dictionary = {}
	for ij2 in coords:
		var i := ij2.x - min_i
		var j := ij2.y - min_j
		if i < 0 or j < 0 or i >= length or j >= width:
			return false
		filled[Vector2i(i, j)] = true
	return filled.size() == length * width


func _prop_long_step(axials: Array[Vector2i], want_len: int, want_wid: int) -> Vector2i:
	## Facing from true hex parallelogram (not axial "dot" — that mis-reads width).
	for i in _AXIAL_STEPS.size():
		var sl: Vector2i = _AXIAL_STEPS[i]
		var sw: Vector2i = _AXIAL_STEPS[(i + 1) % _AXIAL_STEPS.size()]
		if _fits_axial_rect(axials, sl, sw, want_len, want_wid):
			return sl
	for i2 in _AXIAL_STEPS.size():
		var sl2: Vector2i = _AXIAL_STEPS[i2]
		var sw2: Vector2i = _AXIAL_STEPS[(i2 + 1) % _AXIAL_STEPS.size()]
		if _fits_axial_rect(axials, sl2, sw2, want_wid, want_len):
			return sw2
	return _AXIAL_STEPS[0]


func _rect_cells_from(start_ax: Vector2i, sl: Vector2i, sw: Vector2i, length: int, width: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in length:
		for j in width:
			var aq := start_ax.x + sl.x * i + sw.x * j
			var ar := start_ax.y + sl.y * i + sw.y * j
			out.append(ZZLos.axial_to_offset(aq, ar))
	return out


func _extract_kind_rects(cluster: Array, want_len: int, want_wid: int) -> Array:
	## Pull exact kind-sized parallelograms out of a connected blob (merged props).
	var pending: Dictionary = {}
	for c in cluster:
		if typeof(c) != TYPE_VECTOR2I:
			continue
		pending[ZZLos.wall_key(c.x, c.y)] = c
	var rects: Array = []
	var guard := 0
	while not pending.is_empty() and guard < 256:
		guard += 1
		var found := false
		var starts: Array = pending.values()
		for start_v in starts:
			var start: Vector2i = start_v
			var start_ax := ZZLos.offset_to_axial(start.x, start.y)
			for di in _AXIAL_STEPS.size():
				var sl: Vector2i = _AXIAL_STEPS[di]
				var sw: Vector2i = _AXIAL_STEPS[(di + 1) % _AXIAL_STEPS.size()]
				var cand := _rect_cells_from(start_ax, sl, sw, want_len, want_wid)
				var ok := true
				for cell in cand:
					if not pending.has(ZZLos.wall_key(cell.x, cell.y)):
						ok = false
						break
				if not ok:
					continue
				var rect: Array = []
				for cell2 in cand:
					var ck := ZZLos.wall_key(cell2.x, cell2.y)
					rect.append(pending[ck])
					pending.erase(ck)
				rects.append(rect)
				found = true
				break
			if found:
				break
		if not found:
			## Leftover cells that aren't a full kind rect — drop (avoid wrong-size mesh).
			break
	return rects


func _prop_mesh_aabb(root: Node3D) -> AABB:
	## Merged mesh AABB in root-local space (reads real GLB size).
	var merged := AABB()
	var has := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var ab: AABB = xf * mi.mesh.get_aabb()
		if not has:
			merged = ab
			has = true
		else:
			merged = merged.merge(ab)
	return merged if has else AABB(Vector3.ZERO, Vector3.ONE)


func _spawn_prop_cluster(kind: String, cluster: Array) -> Node3D:
	## Footprint from kind; scale from mesh AABB. block_wall = two blocks stacked (tier full).
	if cluster.is_empty():
		return null
	var use_car := kind == "car"
	var is_wall := kind == "block_wall"
	if not use_car and not is_wall and kind != "block" and kind != "half":
		return null
	var fp := _prop_kind_footprint(kind)
	var want_len := fp.x
	var want_wid := fp.y
	if cluster.size() != want_len * want_wid:
		return null
	var mid := Vector3.ZERO
	var axials: Array[Vector2i] = []
	for c in cluster:
		var cell: Vector2i = c
		mid += grid_to_world(cell.x, cell.y)
		axials.append(ZZLos.offset_to_axial(cell.x, cell.y))
	mid /= float(cluster.size())
	mid.y = 0.0
	var step_l := _prop_long_step(axials, want_len, want_wid)
	var hex_span := HEX_SIZE * sqrt(3.0) * PROP_FIT
	## Size locked to kind (car 6×2 / block 2×1). Cluster only picks facing.
	var len_span := float(want_len) * hex_span
	var wid_span := float(want_wid) * hex_span
	var o0 := ZZLos.axial_to_offset(0, 0)
	var o1 := ZZLos.axial_to_offset(step_l.x, step_l.y)
	var dir := grid_to_world(o1.x, o1.y) - grid_to_world(o0.x, o0.y)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(0, 0, 1)
	else:
		dir = dir.normalized()
	var scene: PackedScene = HALF_CAR_SCENE if use_car else HALF_BLOCK_SCENE
	var probe := scene.instantiate() as Node3D
	if probe == null:
		return null
	var ab := _prop_mesh_aabb(probe)
	probe.free()
	## block.glb long=Z. car.glb is ~cube — keep length on local X (scale.x = len).
	var model_len := ab.size.x if use_car else ab.size.z
	var model_wid := ab.size.z if use_car else ab.size.x
	var model_h := maxf(ab.size.y, 0.01)
	var s_len := len_span / maxf(model_len, 0.01)
	var s_wid := wid_span / maxf(model_wid, 0.01)
	var s_y := (s_len + s_wid) * 0.5
	## Align length axis with footprint: car local +X, block local +Z.
	var yaw := rad_to_deg(atan2(dir.x, dir.z))
	if use_car:
		yaw -= 90.0
	var root := Node3D.new()
	root.position = mid
	root.rotation_degrees.y = yaw
	var layers := 2 if is_wall else 1
	## Full AABB includes rebar loops; nest upper block so it sits on the slab, not on hooks.
	var stack_step := model_h * s_y * (1.0 - BLOCK_STACK_NEST) if is_wall else model_h * s_y
	for i in layers:
		var piece := scene.instantiate() as Node3D
		if piece == null:
			continue
		if use_car:
			piece.scale = Vector3(s_len, s_y, s_wid)
		else:
			piece.scale = Vector3(s_wid, s_y, s_len)
		piece.position.y = float(i) * stack_step - ab.position.y * s_y
		root.add_child(piece)
	_enable_mesh_shadows(root)
	return root


func _enable_mesh_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in node.get_children():
		_enable_mesh_shadows(c)


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
