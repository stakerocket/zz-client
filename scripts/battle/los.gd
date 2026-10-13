extends RefCounted
class_name ZZLos

## Offset col/row math matching server (pointy-top odd-r).
## Hit / AP / weapon numbers come from server `rules` (battle_start / state.rules).

# Fallback defaults — overwritten by apply_rules() from server.
static var _rules: Dictionary = {
	"hit_base_open": 1.0,
	"hit_base_cover_open": 0.9,
	"hit_base_stand_half": 0.8,
	"hit_base_stand_window": 0.7,
	"hit_base_sit_soft": 0.5,
	"hit_mul_shooter_stand": 0.8,
	"hit_mul_shooter_sit": 0.9,
	"initial_ap": 16,
	"move_ap_stand": 1,
	"move_ap_sit": 2,
	"posture_ap": 1,
	"medkit_ap": 5,
	"medkit_heal": 15,
	"medkit_max": 5,
	"shoot_ap": 4,
	"weapon_range": 16,
	"damage_min": 16,
	"damage_max": 24,
	"range_over_hit_per_hex": 0.1,
	"range_over_damage_per_hex": 0.1,
}

# even row / odd row neighbor deltas — must match server oddrNeighborDirs.
const NEIGHBOR_DIRS := [
	[Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)],
	[Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1)],
]


static func apply_rules(rules: Dictionary) -> void:
	if rules.is_empty():
		return
	for k in rules.keys():
		var key := str(k)
		if key == "default_weapon":
			apply_weapon(rules[k])
			continue
		_rules[key] = rules[k]


static func apply_weapon(w: Variant) -> void:
	if typeof(w) != TYPE_DICTIONARY:
		return
	var wd: Dictionary = w
	if wd.has("shoot_ap"):
		_rules["shoot_ap"] = int(wd.get("shoot_ap", 4))
	if wd.has("range"):
		_rules["weapon_range"] = int(wd.get("range", 16))
	if wd.has("damage_min"):
		_rules["damage_min"] = int(wd.get("damage_min", 16))
	if wd.has("damage_max"):
		_rules["damage_max"] = int(wd.get("damage_max", 24))


static func rules() -> Dictionary:
	return _rules


static func rule_f(key: String, fallback: float) -> float:
	return float(_rules.get(key, fallback))


static func rule_i(key: String, fallback: int) -> int:
	return int(_rules.get(key, fallback))


static func weapon_range() -> int:
	return rule_i("weapon_range", 16)


static func range_hit_mul(distance: int) -> float:
	var wr := weapon_range()
	if distance < 1 or wr < 1:
		return 0.0
	if distance <= wr:
		return 1.0
	var over := float(distance - wr)
	var mul := 1.0 - rule_f("range_over_hit_per_hex", 0.1) * over
	return maxf(0.0, mul)


static func wall_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


static func _half(n: int) -> int:
	return n >> 1


static func offset_to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - _half(row - (row & 1)), row)


static func axial_to_offset(q: int, r: int) -> Vector2i:
	return Vector2i(q + _half(r - (r & 1)), r)


static func is_hex_neighbor(acol: int, arow: int, bcol: int, brow: int) -> bool:
	var dirs: Array = NEIGHBOR_DIRS[arow & 1]
	for d in dirs:
		var delta: Vector2i = d
		if acol + delta.x == bcol and arow + delta.y == brow:
			return true
	return false


static func hex_neighbors(col: int, row: int) -> Array:
	var out: Array = []
	for d in NEIGHBOR_DIRS[row & 1]:
		var delta: Vector2i = d
		out.append(Vector2i(col + delta.x, row + delta.y))
	return out


static func hex_distance(acol: int, arow: int, bcol: int, brow: int) -> int:
	var a := offset_to_axial(acol, arow)
	var b := offset_to_axial(bcol, brow)
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) / 2


static func hex_line(x0: int, y0: int, x1: int, y1: int) -> Array:
	var n := hex_distance(x0, y0, x1, y1)
	if n == 0:
		return [Vector2i(x0, y0)]
	var a_off := offset_to_axial(x0, y0)
	var b_off := offset_to_axial(x1, y1)
	var a := Vector3(float(a_off.x), float(-a_off.x - a_off.y), float(a_off.y))
	var b := Vector3(float(b_off.x), float(-b_off.x - b_off.y), float(b_off.y))
	var cells: Array = []
	for i in range(n + 1):
		var t := float(i) / float(n)
		var c := a.lerp(b, t)
		var axial := _cube_round(c.x, c.y, c.z)
		cells.append(axial_to_offset(axial.x, axial.y))
	return cells


static func _cube_round(fx: float, fy: float, fz: float) -> Vector2i:
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


static func obstacles_on_shot(walls: Dictionary, x0: int, y0: int, x1: int, y1: int) -> Array:
	var out: Array = []
	var cells := hex_line(x0, y0, x1, y1)
	for i in range(cells.size()):
		var c: Vector2i = cells[i]
		if i == 0:
			continue
		if c.x == x1 and c.y == y1:
			break
		var key := wall_key(c.x, c.y)
		if walls.has(key):
			out.append({"x": c.x, "y": c.y, "kind": str(walls[key])})
	return out


static func first_wall_on_shot(walls: Dictionary, x0: int, y0: int, x1: int, y1: int) -> Variant:
	var obs := obstacles_on_shot(walls, x0, y0, x1, y1)
	if obs.is_empty():
		return null
	var o: Dictionary = obs[0]
	return Vector2i(int(o.x), int(o.y))


## Mirrors server EvaluateShot + range falloff.
## Returns {blocked, chance, wall, soft, distance}. Shooting always allowed at any d >= 1.
static func evaluate_shot(
	walls: Dictionary,
	x0: int, y0: int, x1: int, y1: int,
	shooter_posture: String,
	target_posture: String
) -> Dictionary:
	var dist := hex_distance(x0, y0, x1, y1)
	var hit_range_mul := range_hit_mul(dist)

	var obs := obstacles_on_shot(walls, x0, y0, x1, y1)
	for o in obs:
		if str(o.kind) == "full":
			return {
				"blocked": true,
				"chance": 0.0,
				"wall": Vector2i(int(o.x), int(o.y)),
				"soft": false,
				"distance": dist,
			}
	if target_posture == "cover" and not obs.is_empty():
		var first: Dictionary = obs[0]
		return {
			"blocked": true,
			"chance": 0.0,
			"wall": Vector2i(int(first.x), int(first.y)),
			"soft": false,
			"distance": dist,
		}

	var base := 1.0
	var soft_wall := Vector2i(-1, -1)
	var has_soft := false
	for o in obs:
		var kind := str(o.kind)
		if kind != "half" and kind != "window":
			continue
		var ch := _soft_base(target_posture, kind)
		if not has_soft or ch < base:
			base = ch
			soft_wall = Vector2i(int(o.x), int(o.y))
			has_soft = true
	if not has_soft:
		base = rule_f("hit_base_cover_open", 0.9) if target_posture == "cover" else rule_f("hit_base_open", 1.0)

	var mul := rule_f("hit_mul_shooter_sit", 0.9) if shooter_posture == "sit" else rule_f("hit_mul_shooter_stand", 0.8)
	return {
		"blocked": false,
		"chance": base * mul * hit_range_mul,
		"wall": soft_wall,
		"soft": has_soft,
		"distance": dist,
	}


static func _soft_base(target_posture: String, kind: String) -> float:
	if target_posture == "sit":
		return rule_f("hit_base_sit_soft", 0.5)
	if kind == "window":
		return rule_f("hit_base_stand_window", 0.7)
	return rule_f("hit_base_stand_half", 0.8)


static func can_shoot_from(posture: String) -> bool:
	return posture == "stand" or posture == "sit"
