extends RefCounted
class_name ZZPathfind

## Hex BFS. Searches up to max_steps (preview horizon), independent of current AP.
## budget_ap marks how much of the path is affordable this turn (UI shows only that).
## Returns { path, ap, affordable_steps } — path excludes start; affordable_steps is
## how many leading steps fit in budget_ap (0 if none).
## Caller sets max_steps (e.g. ceil(player_max_ap * 2)).
## ap_frac > 0: run billing via run_extra_ap; step_ap ignored for billing.


static func find_path(
	from: Vector2i,
	to: Vector2i,
	walls: Dictionary,
	blocked: Dictionary,
	step_ap: int,
	budget_ap: int,
	grid_cols: int = 60,
	grid_rows: int = 45,
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


## All cells reachable with budget_ap this turn (excludes start). Empty if no move.
static func reachable_cells(
	from: Vector2i,
	walls: Dictionary,
	blocked: Dictionary,
	step_ap: int,
	budget_ap: int,
	grid_cols: int = 60,
	grid_rows: int = 45,
	ap_frac: float = 0.0,
	run_streak: int = 0
) -> Array:
	var out: Array = []
	var use_frac := ap_frac > 0.0
	if budget_ap <= 0:
		return out
	if not use_frac and step_ap <= 0:
		return out
	var max_steps: int
	if use_frac:
		# Odd/even run: roughly 2 hexes per AP remaining, plus streak slack.
		max_steps = maxi(1, budget_ap * 2 + 1)
	else:
		max_steps = maxi(1, budget_ap / step_ap)
	var steps_at: Dictionary = {}
	var start_key := ZZLos.wall_key(from.x, from.y)
	steps_at[start_key] = 0
	var queue: Array = [from]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		var cur_key := ZZLos.wall_key(cur.x, cur.y)
		var cur_steps: int = steps_at[cur_key]
		if cur_steps >= max_steps:
			continue
		for n in ZZLos.hex_neighbors(cur.x, cur.y):
			if not _in_bounds(n, grid_cols, grid_rows):
				continue
			var nk := ZZLos.wall_key(n.x, n.y)
			if walls.has(nk):
				continue
			if blocked.has(nk):
				continue
			var next_steps := cur_steps + 1
			if next_steps > max_steps:
				continue
			var next_ap: int
			if use_frac:
				next_ap = run_extra_ap(run_streak, next_steps)
			else:
				next_ap = next_steps * step_ap
			if next_ap > budget_ap:
				continue
			if steps_at.has(nk) and int(steps_at[nk]) <= next_steps:
				continue
			var was_new := not steps_at.has(nk)
			steps_at[nk] = next_steps
			if was_new:
				out.append(n)
			queue.append(n)
	return out


static func _in_bounds(c: Vector2i, grid_cols: int, grid_rows: int) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < grid_cols and c.y < grid_rows
