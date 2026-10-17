extends RefCounted
class_name ZZPathfind

## Hex BFS. Searches up to max_steps (preview horizon), independent of current AP.
## budget_ap only marks how much of the path is affordable this turn.
## Returns { path, ap, affordable_steps } — path excludes start; affordable_steps is
## how many leading steps fit in budget_ap (0 if none).
## Caller sets max_steps (e.g. ceil(player_max_ap * 2)).
## ap_frac > 0: per-hex AP = ap_frac with ceil on path total (run); step_ap ignored for billing.


static func find_path(
	from: Vector2i,
	to: Vector2i,
	walls: Dictionary,
	blocked: Dictionary,
	step_ap: int,
	budget_ap: int,
	grid_cols: int = 40,
	grid_rows: int = 30,
	max_steps: int = 24,
	ap_frac: float = 0.0,
	run_streak: int = 0
) -> Dictionary:
	var empty := {"path": [], "ap": 0, "affordable_steps": 0}
	var use_frac := ap_frac > 0.0
	if (not use_frac and step_ap <= 0) or max_steps <= 0:
		return empty
	if from == to:
		return empty
	if not _in_bounds(to, grid_cols, grid_rows):
		return empty
	if walls.has(ZZLos.wall_key(to.x, to.y)):
		return empty
	if blocked.has(ZZLos.wall_key(to.x, to.y)):
		return empty

	var min_steps := ZZLos.hex_distance(from.x, from.y, to.x, to.y)
	if min_steps > max_steps:
		return empty

	# Graph search always advances 1 step per hex; AP billing may use frac.
	var edge_cost := 1 if use_frac else step_ap
	var max_search_ap := max_steps * edge_cost
	var came_from: Dictionary = {}
	var cost_ap: Dictionary = {}
	var start_key := ZZLos.wall_key(from.x, from.y)
	cost_ap[start_key] = 0
	var queue: Array = [from]
	var qi := 0
	var found := false

	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		var cur_key := ZZLos.wall_key(cur.x, cur.y)
		var cur_cost: int = cost_ap[cur_key]
		if cur == to:
			found = true
			break
		if cur_cost >= max_search_ap:
			continue
		for n in ZZLos.hex_neighbors(cur.x, cur.y):
			if not _in_bounds(n, grid_cols, grid_rows):
				continue
			var nk := ZZLos.wall_key(n.x, n.y)
			if walls.has(nk):
				continue
			if n != to and blocked.has(nk):
				continue
			var next_cost := cur_cost + edge_cost
			if next_cost > max_search_ap:
				continue
			if ZZLos.hex_distance(from.x, from.y, n.x, n.y) > max_steps:
				continue
			if cost_ap.has(nk) and int(cost_ap[nk]) <= next_cost:
				continue
			cost_ap[nk] = next_cost
			came_from[nk] = cur
			queue.append(n)

	var goal_key := ZZLos.wall_key(to.x, to.y)
	if not found and not cost_ap.has(goal_key):
		return empty
	if not cost_ap.has(goal_key):
		return empty

	var path: Array = []
	var walk := to
	while walk != from:
		path.push_front(walk)
		var wk := ZZLos.wall_key(walk.x, walk.y)
		if not came_from.has(wk):
			return empty
		walk = came_from[wk]

	var steps := path.size()
	var total_ap: int
	var affordable: int
	if use_frac:
		# Continuing a run streak: cost(k) = ceil((streak+k)/2) - ceil(streak/2).
		total_ap = run_extra_ap(run_streak, steps)
		affordable = 0
		for k in range(1, steps + 1):
			if run_extra_ap(run_streak, k) <= budget_ap:
				affordable = k
			else:
				break
	else:
		total_ap = int(cost_ap[goal_key])
		affordable = 0
		if budget_ap >= step_ap:
			affordable = mini(path.size(), budget_ap / step_ap)
	return {"path": path, "ap": total_ap, "affordable_steps": affordable}


static func _ceil_steps_frac(steps: int, frac: float) -> int:
	if steps <= 0:
		return 0
	return int(ceil(float(steps) * frac))


static func run_path_ap(steps: int) -> int:
	# ceil(steps * 0.5) for positive ints.
	if steps <= 0:
		return 0
	return (steps + 1) / 2


static func run_extra_ap(streak: int, extra_steps: int) -> int:
	if extra_steps <= 0:
		return 0
	var s := maxi(0, streak)
	return run_path_ap(s + extra_steps) - run_path_ap(s)


static func _in_bounds(c: Vector2i, grid_cols: int, grid_rows: int) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < grid_cols and c.y < grid_rows
