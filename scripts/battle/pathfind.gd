extends RefCounted
class_name ZZPathfind

## Hex BFS. Searches up to max_steps (preview horizon), independent of current AP.
## budget_ap only marks how much of the path is affordable this turn.
## Returns { path, ap, affordable_steps } — path excludes start; affordable_steps is
## how many leading steps fit in budget_ap (0 if none).
## Caller sets max_steps (e.g. ceil(player_max_ap * 1.5)).


static func find_path(
	from: Vector2i,
	to: Vector2i,
	walls: Dictionary,
	blocked: Dictionary,
	step_ap: int,
	budget_ap: int,
	grid_cols: int = 40,
	grid_rows: int = 30,
	max_steps: int = 24
) -> Dictionary:
	var empty := {"path": [], "ap": 0, "affordable_steps": 0}
	if step_ap <= 0 or max_steps <= 0:
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

	var max_search_ap := max_steps * step_ap
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
			var next_cost := cur_cost + step_ap
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

	var total_ap := int(cost_ap[goal_key])
	var affordable := 0
	if budget_ap >= step_ap:
		affordable = mini(path.size(), budget_ap / step_ap)
	return {"path": path, "ap": total_ap, "affordable_steps": affordable}


static func _in_bounds(c: Vector2i, grid_cols: int, grid_rows: int) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < grid_cols and c.y < grid_rows
