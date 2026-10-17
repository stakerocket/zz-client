extends RefCounted
class_name ZZLos

## Offset col/row math matching server (pointy-top odd-r).
## All balance numbers come from server `rules` (lobby_state / battle_start / state.rules).
## No balance hardcoding — empty until apply_rules().

static var _rules: Dictionary = {}

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
		_rules["shoot_ap"] = int(wd["shoot_ap"])
	if wd.has("range"):
		_rules["weapon_range"] = int(wd["range"])
	if wd.has("damage_min"):
		_rules["damage_min"] = int(wd["damage_min"])
	if wd.has("damage_max"):
		_rules["damage_max"] = int(wd["damage_max"])
	if wd.has("accuracy"):
		_rules["weapon_accuracy"] = float(wd["accuracy"])
	if wd.has("mag_size"):
		_rules["weapon_mag_size"] = int(wd["mag_size"])
	if wd.has("reload_ap"):
		_rules["weapon_reload_ap"] = int(wd["reload_ap"])


static func rules() -> Dictionary:
	return _rules


static func has_rules() -> bool:
	return not _rules.is_empty()


static func rule_f(key: String) -> float:
	return float(_rules.get(key, 0.0))


static func rule_i(key: String) -> int:
	return int(_rules.get(key, 0))


static func default_stat() -> int:
	return rule_i("default_stat")


static func compute_max_hp(endurance: int = -1) -> int:
	if endurance < 0:
		endurance = default_stat()
	var hp := rule_i("hp_base") + rule_i("hp_per_endurance") * endurance
	return maxi(1, hp)


static func compute_max_ap(strength: int = -1, agility: int = -1, endurance: int = -1) -> int:
	var d := default_stat()
	if strength < 0:
		strength = d
	if agility < 0:
		agility = d
	if endurance < 0:
		endurance = d
	var raw := (
		rule_f("ap_from_strength") * float(strength)
		+ rule_f("ap_from_agility") * float(agility)
		+ rule_f("ap_from_endurance") * float(endurance)
	)
	return maxi(0, int(floor(raw)))


static func compute_carry_weight(strength: int = -1) -> int:
	if strength < 0:
		strength = default_stat()
	return rule_i("carry_weight_base") + rule_i("carry_weight_per_strength") * strength


static func weapon_range() -> int:
	return rule_i("weapon_range")


static func range_hit_penalty(distance: int) -> float:
	var wr := weapon_range()
	if distance < 1 or wr < 1:
		return 1.0
	if distance <= wr:
		return 0.0
	return rule_f("range_over_hit_per_hex") * float(distance - wr)


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


## Mirrors server EvaluateShot. Stats/coeffs only from applied rules + args.
## Returns {blocked, chance, wall, soft, distance}.
static func evaluate_shot(
	walls: Dictionary,
	x0: int, y0: int, x1: int, y1: int,
	shooter_posture: String,
	target_posture: String,
	shooter_marksmanship: int = -1,
	target_agility: int = -1
) -> Dictionary:
	var dist := hex_distance(x0, y0, x1, y1)
	var dstat := default_stat()
	if shooter_marksmanship < 0:
		shooter_marksmanship = dstat
	if target_agility < 0:
		target_agility = dstat

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
	var path_obs: Array = []
	for o in obs:
		var kind := str(o.kind)
		var ox := int(o.x)
		var oy := int(o.y)
		if (kind == "half" or kind == "window") and is_hex_neighbor(ox, oy, x0, y0) and not is_hex_neighbor(ox, oy, x1, y1):
			continue
		path_obs.append(o)
	if target_posture == "cover" and not path_obs.is_empty():
		var first: Dictionary = path_obs[0]
		return {
			"blocked": true,
			"chance": 0.0,
			"wall": Vector2i(int(first.x), int(first.y)),
			"soft": false,
			"distance": dist,
		}

	var defense := 0.0
	var soft_wall := Vector2i(-1, -1)
	var has_soft := false
	for o in path_obs:
		var kind := str(o.kind)
		if kind != "half" and kind != "window":
			continue
		var d := _soft_defense(target_posture, kind)
		if not has_soft or d > defense:
			defense = d
			soft_wall = Vector2i(int(o.x), int(o.y))
			has_soft = true
	if not has_soft:
		defense = _open_defense(target_posture)

	var pose := rule_f("hit_pose_bonus_sit") if shooter_posture == "sit" else rule_f("hit_pose_bonus_stand")
	var mark := float(maxi(0, shooter_marksmanship)) * rule_f("hit_per_accuracy_stat")
	var dodge := float(maxi(0, target_agility)) * rule_f("dodge_per_agility")
	var chance := (
		rule_f("weapon_accuracy")
		+ rule_f("shooter_skill") * rule_f("shooter_skill_mod")
		- range_hit_penalty(dist)
		+ pose
		- defense
		+ mark
		- dodge
	)
	chance = clampf(chance, 0.0, rule_f("hit_chance_cap"))
	return {
		"blocked": false,
		"chance": chance,
		"wall": soft_wall,
		"soft": has_soft,
		"distance": dist,
	}


static func _open_defense(target_posture: String) -> float:
	if target_posture == "cover":
		return rule_f("def_cover_open")
	if target_posture == "sit":
		return rule_f("def_sit_open")
	return rule_f("def_stand_open")


static func _soft_defense(target_posture: String, kind: String) -> float:
	if target_posture == "sit":
		return rule_f("def_sit_window") if kind == "window" else rule_f("def_sit_half")
	if kind == "window":
		return rule_f("def_stand_window")
	return rule_f("def_stand_half")


static func can_shoot_from(posture: String) -> bool:
	return posture == "stand" or posture == "sit"
