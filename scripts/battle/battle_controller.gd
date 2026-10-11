extends Node
class_name ZZBattleController

## Defaults until server rules arrive (battle_start / state.rules).
var move_cost_stand: int = 1
var move_cost_sit: int = 2
var shoot_cost: int = 4
var posture_cost: int = 1
## Max AP pool per turn (from server rules.initial_ap).
var max_ap: int = 16
const PROJECTILE_TIME := 0.35
const ProjectileBoltScript := preload("res://scripts/battle/projectile_bolt.gd")
const WallBurstScript := preload("res://scripts/battle/wall_burst.gd")

signal ap_changed(value: int)
signal hp_changed(value: int)
signal turn_changed(turn: int)
signal timer_changed(seconds_left: float)
signal input_lock_changed(locked: bool)
signal history_changed(lines: Array)
signal battle_started
signal battle_ended(winner_id: String)
signal room_players_changed(nicks: Array)
signal chat_received(nick: String, text: String, channel: String)

var ws: ZZWSClient
var grid: ZZGridView
var units_root: Node2D

var local_nick: String = ""
var your_id: String = ""
var input_locked: bool = true
var local_ap: int = 0
var local_hp: int = 0
var local_pos: Vector2i = Vector2i.ZERO
var local_posture: String = "stand"
var action_queue: Array = []
var players: Dictionary = {} # id -> dict
var unit_nodes: Dictionary = {} # id -> ZZUnitView
var turn_deadline_ms: int = 30000
var _deadline_left: float = 0.0
var current_turn: int = 1
var in_battle: bool = false
var _playing_events: bool = false
var _resolve_queue: Array = [] # pending battle_state / battle_end payloads
var _turn_start_pos: Vector2i = Vector2i.ZERO
var _turn_start_ap: int = 0
var _turn_start_posture: String = "stand"
## Last hover path steps (excluding start), for click-to-queue.
var _hover_path: Array = []
var _hover_path_ap: int = 0
var _hover_affordable_steps: int = 0
var _end_turn_sent: bool = false

var _colors := {
	0: Color(0.30, 0.65, 0.95),
	1: Color(0.95, 0.55, 0.25),
}


func setup(ws_client: ZZWSClient, grid_view: ZZGridView, units: Node2D) -> void:
	ws = ws_client
	grid = grid_view
	units_root = units
	ws.message_received.connect(_on_message)
	grid.tile_clicked.connect(_on_tile_clicked)
	grid.tile_hovered.connect(_on_tile_hovered)


func set_local_nick(nick: String) -> void:
	local_nick = nick
	room_players_changed.emit([local_nick])


func _ensure_ws() -> bool:
	if ws.is_open():
		return true
	ws.connect_to_server()
	var tries := 0
	while not ws.is_open() and tries < 50:
		await get_tree().create_timer(0.1).timeout
		tries += 1
	return ws.is_open()


func connect_and_join_lobby(nick: String) -> bool:
	if nick == "":
		return false
	local_nick = nick
	if not await _ensure_ws():
		return false
	ws.send_dict(ZZProtocol.join_lobby(nick))
	return true


func send_chat(text: String, channel: String = "lobby") -> void:
	if text.strip_edges() == "":
		return
	if not ws.is_open():
		return
	if channel != "battle":
		channel = "lobby"
	ws.send_dict(ZZProtocol.chat(text, channel))


func connect_and_find(nick: String) -> bool:
	if nick == "":
		return false
	if not await _ensure_ws():
		return false
	ws.send_dict(ZZProtocol.find_match(nick))
	return true


func request_end_turn() -> void:
	if input_locked or not in_battle or _playing_events or _end_turn_sent:
		return
	_commit_end_turn()


func request_posture(posture: String) -> void:
	if input_locked or not in_battle or _playing_events:
		return
	if posture != "stand" and posture != "sit" and posture != "cover":
		return
	if local_ap < posture_cost:
		return
	if local_posture == posture:
		return
	action_queue.append(ZZProtocol.posture_action(posture))
	local_ap -= posture_cost
	local_posture = posture
	ap_changed.emit(local_ap)
	_apply_local_posture_visual()
	_emit_history()


func request_undo() -> void:
	if input_locked or not in_battle or _playing_events:
		return
	if action_queue.is_empty():
		return
	action_queue.pop_back()
	_recompute_local_from_queue()


func _commit_end_turn() -> void:
	if _end_turn_sent or not in_battle:
		return
	# Snapshot before rewind — same payload for manual end and timer auto-send.
	var actions: Array = action_queue.duplicate(true)
	_end_turn_sent = true
	_set_locked(true)
	_rewind_local_to_turn_start()
	if ws != null and ws.is_open():
		ws.send_dict(ZZProtocol.end_turn(actions))


func _process(delta: float) -> void:
	if _playing_events:
		return
	if not _resolve_queue.is_empty():
		_pump_resolve_queue()
		return
	if not in_battle:
		return
	# Keep ticking after end_turn so the waiting player still sees remaining time.
	if _deadline_left > 0.0:
		_deadline_left -= delta
		timer_changed.emit(_deadline_left)
	# Auto-flush planned queue near/at zero (and on server turn_timeout).
	if not _end_turn_sent and not input_locked and _deadline_left <= 0.0:
		timer_changed.emit(0.0)
		_commit_end_turn()


func _on_message(data: Dictionary) -> void:
	var t: String = str(data.get("type", ""))
	match t:
		"lobby_state":
			room_players_changed.emit(data.get("players", []))
		"chat":
			var ch := str(data.get("channel", "lobby"))
			if ch != "battle":
				ch = "lobby"
			chat_received.emit(str(data.get("nick", "?")), str(data.get("text", "")), ch)
		"queued":
			pass
		"battle_start":
			_apply_battle_start(data)
		"turn_timeout":
			# Server timer fired — send whatever was planned before grace empty-fill.
			if not _end_turn_sent and not input_locked:
				_commit_end_turn()
		"turn_resolving":
			_set_locked(true)
			_rewind_local_to_turn_start()
		"battle_state":
			_resolve_queue.append({"kind": "state", "data": data})
		"battle_end":
			_resolve_queue.append({"kind": "end", "data": data})
		"error", "pong":
			pass
		_:
			pass


func _pump_resolve_queue() -> void:
	if _playing_events or _resolve_queue.is_empty():
		return
	var item: Dictionary = _resolve_queue.pop_front()
	_playing_events = true
	_set_locked(true)
	# Deferred so the coroutine is not started from a WS signal stack.
	call_deferred("_run_resolve", item)


func _run_resolve(item: Dictionary) -> void:
	var data: Dictionary = item.get("data", {})
	var kind: String = str(item.get("kind", "state"))
	if kind == "state":
		turn_deadline_ms = int(data.get("turn_deadline_ms", 30000))
		if data.has("turn"):
			current_turn = int(data.get("turn"))
			turn_changed.emit(current_turn)
	await _play_events(data.get("events", []))
	if kind == "end":
		in_battle = false
		_apply_state(data.get("state", {}), false, false)
		timer_changed.emit(0.0)
		battle_ended.emit(str(data.get("winner_id", "")))
	else:
		_apply_state(data.get("state", {}), true, false)
		_start_deadline()
		_set_locked(false)
	_playing_events = false


func _apply_battle_start(data: Dictionary) -> void:
	in_battle = true
	your_id = str(data.get("your_id", ""))
	turn_deadline_ms = int(data.get("turn_deadline_ms", 30000))
	_resolve_queue.clear()
	_playing_events = false
	_apply_combat_rules(data.get("rules", {}))
	_apply_state(data.get("state", {}), true, true)
	_emit_room_nicks_from_state(data.get("state", {}))
	_start_deadline()
	_set_locked(false)
	battle_started.emit()


func _apply_combat_rules(rules: Variant) -> void:
	if typeof(rules) != TYPE_DICTIONARY:
		return
	var r: Dictionary = rules
	if r.is_empty():
		return
	ZZLos.apply_rules(r)
	move_cost_stand = ZZLos.rule_i("move_ap_stand", move_cost_stand)
	move_cost_sit = ZZLos.rule_i("move_ap_sit", move_cost_sit)
	shoot_cost = ZZLos.rule_i("shoot_ap", shoot_cost)
	posture_cost = ZZLos.rule_i("posture_ap", posture_cost)
	max_ap = maxi(1, ZZLos.rule_i("initial_ap", max_ap))


func _apply_local_weapon(pd: Dictionary) -> void:
	if not pd.has("weapon"):
		return
	ZZLos.apply_weapon(pd.get("weapon"))
	shoot_cost = ZZLos.rule_i("shoot_ap", shoot_cost)


func _play_events(events: Variant) -> void:
	var list: Array = _as_array(events)
	if list.is_empty():
		return
	for group in _group_events_by_clock(list):
		await _play_event_group(group)


func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _group_events_by_clock(list: Array) -> Array:
	var groups: Array = []
	var current_clock := -999999
	var current: Array = []
	for ev in list:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = ev
		var clock := int(e.get("clock", 0))
		if current.is_empty() or clock != current_clock:
			if not current.is_empty():
				groups.append(current)
			current = [e]
			current_clock = clock
		else:
			current.append(e)
	if not current.is_empty():
		groups.append(current)
	return groups


func _play_event_group(group: Array) -> void:
	if group.is_empty():
		return
	if group.size() == 1:
		await _play_one_event(group[0])
		return
	var pending := {"n": group.size()}
	for e in group:
		_play_one_event_parallel(e, pending)
	while int(pending.n) > 0:
		await get_tree().process_frame


func _play_one_event_parallel(e: Dictionary, pending: Dictionary) -> void:
	await _play_one_event(e)
	pending.n = int(pending.n) - 1


func _play_one_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"move":
			await _play_move_event(e)
		"posture":
			await _play_posture_event(e)
		"shoot":
			await _play_shoot_event(e)
		_:
			pass


func _play_posture_event(e: Dictionary) -> void:
	var actor_id := str(e.get("actor_id", ""))
	var posture := str(e.get("posture", "stand"))
	var uv: ZZUnitView = unit_nodes.get(actor_id)
	if uv != null and is_instance_valid(uv):
		uv.set_posture(posture)
	if players.has(actor_id):
		players[actor_id]["posture"] = posture
	if actor_id == your_id:
		local_posture = posture
	await get_tree().create_timer(0.12).timeout


func _play_move_event(e: Dictionary) -> void:
	var actor_id := str(e.get("actor_id", ""))
	var uv: ZZUnitView = unit_nodes.get(actor_id)
	if uv == null or not is_instance_valid(uv):
		return
	var from := Vector2i(int(e.get("from_x", 0)), int(e.get("from_y", 0)))
	var to := Vector2i(int(e.get("to_x", 0)), int(e.get("to_y", 0)))
	# Rewind local prediction so the move tween is visible after planning.
	uv.position = grid.grid_to_world(from.x, from.y)
	await uv.animate_move_to(grid.grid_to_world(to.x, to.y), true)
	if players.has(actor_id):
		players[actor_id]["x"] = to.x
		players[actor_id]["y"] = to.y
	if actor_id == your_id:
		local_pos = to


func _play_shoot_event(e: Dictionary) -> void:
	var actor_id := str(e.get("actor_id", ""))
	var target_id := str(e.get("target_id", ""))
	var actor: ZZUnitView = unit_nodes.get(actor_id)
	if actor == null or not is_instance_valid(actor):
		return
	var impact := grid.grid_to_world(int(e.get("to_x", 0)), int(e.get("to_y", 0)))
	var hit_wall := bool(e.get("hit_wall", false))
	Sfx.play_shoot()
	await _fly_projectile(actor.global_position, impact, actor.color)
	if hit_wall:
		Sfx.play_hit_wall()
		await _wall_burst_at(impact)
		return
	var target: ZZUnitView = unit_nodes.get(target_id)
	if target == null or not is_instance_valid(target):
		return
	var damage := int(e.get("damage", 0))
	var hp_after := int(e.get("hp_after", 0))
	if damage > 0:
		Sfx.play_hit_target()
		await target.apply_hit(damage, hp_after)
	else:
		Sfx.play_miss()
		await target.apply_miss()
		target.set_hp(hp_after, true)
	if players.has(target_id):
		players[target_id]["hp"] = hp_after
	if target_id == your_id:
		local_hp = hp_after
		hp_changed.emit(local_hp)


func _fly_projectile(from: Vector2, to: Vector2, tint: Color, preview: bool = false) -> void:
	var bolt: Node2D = ProjectileBoltScript.new()
	bolt.z_index = 30
	bolt.set_meta("zz_preview", preview)
	bolt.set("tint", tint.lightened(0.35))
	units_root.add_child(bolt)
	bolt.global_position = from
	bolt.queue_redraw()
	var tw := units_root.create_tween()
	tw.tween_property(bolt, "global_position", to, PROJECTILE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	if is_instance_valid(bolt):
		var flash := units_root.create_tween()
		flash.tween_property(bolt, "modulate:a", 0.0, 0.08)
		await flash.finished
		if is_instance_valid(bolt):
			bolt.queue_free()


func _preview_shoot(target_id: String, outcome: Dictionary) -> void:
	var actor: ZZUnitView = unit_nodes.get(your_id)
	var target: ZZUnitView = unit_nodes.get(target_id)
	if actor == null or target == null:
		return
	if not is_instance_valid(actor) or not is_instance_valid(target):
		return
	var impact: Vector2
	var hit_wall := bool(outcome.get("blocked", false))
	if hit_wall:
		var wc: Vector2i = outcome.get("wall", Vector2i.ZERO)
		impact = grid.grid_to_world(wc.x, wc.y)
	else:
		impact = target.global_position
	await _fly_projectile(actor.global_position, impact, actor.color, true)
	if hit_wall:
		await _wall_burst_at(impact)
		return
	if is_instance_valid(target) and not target.is_dead and not target.is_dying:
		await target.flash_hit()


func _wall_burst_at(world_pos: Vector2) -> void:
	var fx: Node2D = WallBurstScript.new()
	fx.z_index = 35
	fx.set_meta("zz_preview", true)
	units_root.add_child(fx)
	fx.global_position = world_pos
	await fx.run()


func _clear_preview_projectiles() -> void:
	if units_root == null:
		return
	for child in units_root.get_children():
		if child.has_meta("zz_preview") and bool(child.get_meta("zz_preview")):
			child.queue_free()


func _apply_state(state: Variant, reset_queue: bool, snap_positions: bool) -> void:
	if typeof(state) != TYPE_DICTIONARY:
		return
	var st: Dictionary = state
	if st.has("rules"):
		_apply_combat_rules(st.get("rules", {}))
	if st.has("turn"):
		current_turn = int(st.get("turn"))
		turn_changed.emit(current_turn)
	if st.has("walls"):
		grid.set_walls(st.get("walls", []))
	if reset_queue:
		action_queue.clear()
		_emit_history()
	players.clear()
	var list: Array = st.get("players", [])
	var idx := 0
	for p in list:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = p
		var pid := str(pd.get("id", ""))
		players[pid] = pd
		_ensure_unit(pid, str(pd.get("nick", "?")), idx)
		var uv: ZZUnitView = unit_nodes[pid]
		var hp_val := int(pd.get("hp", 0))
		if uv.is_dead or uv.is_dying:
			uv.hp = hp_val
			uv.queue_redraw()
		else:
			uv.set_hp(hp_val, snap_positions)
		var gx := int(pd.get("x", 0))
		var gy := int(pd.get("y", 0))
		var posture := str(pd.get("posture", "stand"))
		if posture == "":
			posture = "stand"
		uv.set_posture(posture)
		if not uv.is_dead and not uv.is_dying and not uv.is_moving:
			uv.snap_to(grid.grid_to_world(gx, gy))
		if pid == your_id:
			local_ap = int(pd.get("ap", 0))
			local_hp = hp_val
			local_pos = Vector2i(gx, gy)
			local_posture = posture
			_turn_start_pos = local_pos
			_turn_start_ap = local_ap
			_turn_start_posture = local_posture
			_apply_local_weapon(pd)
			ap_changed.emit(local_ap)
			hp_changed.emit(local_hp)
		idx += 1


func _rewind_local_to_turn_start() -> void:
	_clear_preview_projectiles()
	local_pos = _turn_start_pos
	local_posture = _turn_start_posture
	if unit_nodes.has(your_id):
		var uv: ZZUnitView = unit_nodes[your_id]
		if uv != null and is_instance_valid(uv) and not uv.is_dead:
			uv.snap_to(grid.grid_to_world(_turn_start_pos.x, _turn_start_pos.y))
			uv.set_posture(_turn_start_posture)
	if grid != null:
		grid.set_highlight(Vector2i(-1, -1))
	_clear_hover_path()


func clear_battle_visuals() -> void:
	_resolve_queue.clear()
	_playing_events = false
	action_queue.clear()
	players.clear()
	local_posture = "stand"
	_emit_history()
	_clear_preview_projectiles()
	for pid in unit_nodes.keys():
		var uv: Node = unit_nodes[pid]
		if is_instance_valid(uv):
			uv.queue_free()
	unit_nodes.clear()
	if grid != null:
		grid.set_highlight(Vector2i(-1, -1))
		grid.clear_walls()
	_clear_hover_path()
	_clear_aim_previews()


func _ensure_unit(pid: String, nick: String, idx: int) -> void:
	if unit_nodes.has(pid):
		return
	var uv := ZZUnitView.new()
	units_root.add_child(uv)
	uv.setup(pid, nick, _colors.get(idx % 2, Color.WHITE))
	unit_nodes[pid] = uv


func _emit_room_nicks_from_state(state: Variant) -> void:
	if typeof(state) != TYPE_DICTIONARY:
		return
	var nicks: Array = []
	for p in state.get("players", []):
		if typeof(p) == TYPE_DICTIONARY:
			nicks.append(str(p.get("nick", "?")))
	room_players_changed.emit(nicks)


func _start_deadline() -> void:
	_end_turn_sent = false
	_deadline_left = float(turn_deadline_ms) / 1000.0
	timer_changed.emit(_deadline_left)


func _set_locked(locked: bool) -> void:
	input_locked = locked
	input_lock_changed.emit(locked)
	if locked:
		_clear_hover_path()
		_clear_aim_previews()


func _on_tile_hovered(g: Vector2i) -> void:
	if input_locked or not in_battle or _playing_events:
		_clear_hover_path()
		_clear_aim_previews()
		return
	if _try_show_enemy_aim(g):
		_clear_hover_path()
		return
	_clear_aim_previews()
	_update_path_preview(g)


func _clear_aim_previews() -> void:
	for pid in unit_nodes.keys():
		var uv: ZZUnitView = unit_nodes[pid]
		if uv != null and is_instance_valid(uv):
			uv.clear_aim_preview()
	if grid != null:
		grid.clear_aim_ray()


func _try_show_enemy_aim(g: Vector2i) -> bool:
	if g.x < 0:
		return false
	var target_id := ""
	for pid in players.keys():
		if pid == your_id:
			continue
		var pd: Dictionary = players[pid]
		if int(pd.get("hp", 0)) <= 0:
			continue
		if int(pd.get("x", -1)) == g.x and int(pd.get("y", -1)) == g.y:
			target_id = pid
			break
	if target_id == "":
		return false
	_clear_aim_previews()
	var uv: ZZUnitView = unit_nodes.get(target_id)
	if uv == null or not is_instance_valid(uv):
		return true
	var pd2: Dictionary = players.get(target_id, {})
	var tgt_posture := str(pd2.get("posture", "stand"))
	if tgt_posture == "":
		tgt_posture = "stand"
	var outcome := ZZLos.evaluate_shot(
		grid.walls_dict(),
		local_pos.x, local_pos.y,
		int(pd2.get("x", 0)), int(pd2.get("y", 0)),
		local_posture,
		tgt_posture
	)
	var blocked := bool(outcome.get("blocked", false))
	var can_shoot := ZZLos.can_shoot_from(local_posture) and local_ap >= shoot_cost and not blocked
	uv.set_aim_preview({
		"blocked": blocked,
		"chance": float(outcome.get("chance", 0.0)),
		"can_shoot": can_shoot,
	})
	var tx := int(pd2.get("x", 0))
	var ty := int(pd2.get("y", 0))
	grid.set_aim_ray(local_pos, Vector2i(tx, ty), ZZLos.weapon_range())
	return true


func _occupied_keys_except_self() -> Dictionary:
	var blocked: Dictionary = {}
	for pid in players.keys():
		if pid == your_id:
			continue
		var pd: Dictionary = players[pid]
		if int(pd.get("hp", 0)) <= 0:
			continue
		blocked[ZZLos.wall_key(int(pd.get("x", 0)), int(pd.get("y", 0)))] = true
	return blocked


func _path_preview_steps() -> int:
	# ×1.5 of max turn AP so full-budget paths + a bit of gray preview fit.
	return maxi(1, int(ceil(float(max_ap) * 1.5)))


func _path_to(g: Vector2i) -> Dictionary:
	var step := _move_cost_for(local_posture)
	if step <= 0:
		return {"path": [], "ap": 0, "affordable_steps": 0}
	# budget_ap = remaining AP (green/gray); max_steps = 1.5 × max_ap pool.
	return ZZPathfind.find_path(
		local_pos, g, grid.walls_dict(), _occupied_keys_except_self(),
		step, local_ap, ZZGridView.GRID_SIZE, _path_preview_steps()
	)


func _clear_hover_path() -> void:
	_hover_path.clear()
	_hover_path_ap = 0
	_hover_affordable_steps = 0
	if grid != null:
		grid.clear_path_preview()


func _update_path_preview(g: Vector2i) -> void:
	if grid == null:
		return
	if g.x < 0 or g == local_pos:
		_clear_hover_path()
		return
	var result := _path_to(g)
	var path: Array = result.get("path", [])
	var ap_cost := int(result.get("ap", 0))
	var affordable := int(result.get("affordable_steps", 0))
	if path.is_empty():
		_clear_hover_path()
		return
	_hover_path = path.duplicate()
	_hover_path_ap = ap_cost
	_hover_affordable_steps = affordable
	var draw_cells: Array = [local_pos]
	draw_cells.append_array(_hover_path)
	var step := _move_cost_for(local_posture)
	var affordable_ap := affordable * step
	grid.set_path_preview(draw_cells, ap_cost, affordable, affordable_ap)


func _on_tile_clicked(g: Vector2i) -> void:
	if input_locked or not in_battle or _playing_events:
		return
	for pid in players.keys():
		var pd: Dictionary = players[pid]
		if int(pd.get("x", -1)) == g.x and int(pd.get("y", -1)) == g.y and pid != your_id:
			_queue_shoot(pid)
			return
	# Click any cell on the previewed path (or a freshly reachable target):
	# enqueue one move action per hex under the hood.
	_queue_path_or_move(g)


func _move_cost_for(posture: String) -> int:
	if posture == "sit":
		return move_cost_sit
	if posture == "cover":
		return 0
	return move_cost_stand


func _path_steps_to_click(g: Vector2i) -> Array:
	# Prefer truncating the current hover path if the click is on it.
	if not _hover_path.is_empty():
		for i in range(_hover_path.size()):
			var cell: Vector2i = _hover_path[i]
			if cell == g:
				# Queue at most the green (affordable) prefix toward the click.
				var until := mini(i + 1, _hover_affordable_steps)
				if until <= 0:
					return []
				return _hover_path.slice(0, until)
	var result := _path_to(g)
	var path: Array = result.get("path", [])
	var affordable := int(result.get("affordable_steps", 0))
	if affordable <= 0:
		return []
	if path.size() > affordable:
		return path.slice(0, affordable)
	return path


func _queue_path_or_move(g: Vector2i) -> void:
	var path: Array = _path_steps_to_click(g)
	if path.is_empty():
		return
	var step_cost := _move_cost_for(local_posture)
	if step_cost <= 0:
		return
	var moved_cells: Array = []
	var prev := local_pos
	for step in path:
		var cell: Vector2i = step
		if not ZZLos.is_hex_neighbor(prev.x, prev.y, cell.x, cell.y):
			break
		if grid.has_wall(cell.x, cell.y):
			break
		if local_ap < step_cost:
			break
		# One ActionMove per hex — server resolves them as a chain.
		action_queue.append(ZZProtocol.move_action(cell.x, cell.y))
		local_ap -= step_cost
		prev = cell
		local_pos = cell
		moved_cells.append(cell)
	if moved_cells.is_empty():
		return
	ap_changed.emit(local_ap)
	grid.set_highlight(local_pos)
	_emit_history()
	_clear_hover_path()
	if unit_nodes.has(your_id):
		_animate_local_path(moved_cells)


func _animate_local_path(cells: Array) -> void:
	var uv: ZZUnitView = unit_nodes.get(your_id)
	if uv == null or not is_instance_valid(uv):
		return
	for cell in cells:
		var g: Vector2i = cell
		await uv.animate_move_to(grid.grid_to_world(g.x, g.y))


func _queue_shoot(target_id: String) -> void:
	if local_ap < shoot_cost:
		return
	if not ZZLos.can_shoot_from(local_posture):
		return
	var pd: Dictionary = players.get(target_id, {})
	var tx := int(pd.get("x", 0))
	var ty := int(pd.get("y", 0))
	var tgt_posture := str(pd.get("posture", "stand"))
	if tgt_posture == "":
		tgt_posture = "stand"
	var outcome := ZZLos.evaluate_shot(
		grid.walls_dict(), local_pos.x, local_pos.y, tx, ty, local_posture, tgt_posture
	)
	action_queue.append(ZZProtocol.shoot_action(target_id))
	local_ap -= shoot_cost
	ap_changed.emit(local_ap)
	_emit_history()
	_preview_shoot(target_id, outcome)


func _apply_local_posture_visual() -> void:
	if unit_nodes.has(your_id):
		var uv: ZZUnitView = unit_nodes[your_id]
		if uv != null and is_instance_valid(uv):
			uv.set_posture(local_posture)


func _recompute_local_from_queue() -> void:
	_clear_preview_projectiles()
	local_pos = _turn_start_pos
	local_ap = _turn_start_ap
	local_posture = _turn_start_posture
	if unit_nodes.has(your_id):
		var uv: ZZUnitView = unit_nodes[your_id]
		if uv != null and is_instance_valid(uv) and not uv.is_dead:
			uv.snap_to(grid.grid_to_world(local_pos.x, local_pos.y))
			uv.set_posture(local_posture)
	for a in action_queue:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var act: Dictionary = a
		match str(act.get("type", "")):
			"move":
				var mcost := _move_cost_for(local_posture)
				local_pos = Vector2i(int(act.get("x", 0)), int(act.get("y", 0)))
				local_ap -= mcost
			"shoot":
				local_ap -= shoot_cost
			"posture":
				local_posture = str(act.get("posture", "stand"))
				local_ap -= posture_cost
	if unit_nodes.has(your_id):
		var uv2: ZZUnitView = unit_nodes[your_id]
		if uv2 != null and is_instance_valid(uv2) and not uv2.is_dead:
			uv2.snap_to(grid.grid_to_world(local_pos.x, local_pos.y))
			uv2.set_posture(local_posture)
	if grid != null:
		grid.set_highlight(local_pos if local_pos != _turn_start_pos else Vector2i(-1, -1))
	_clear_hover_path()
	ap_changed.emit(local_ap)
	_emit_history()
	# Re-preview last shoot if present.
	if not action_queue.is_empty():
		var last: Dictionary = action_queue[action_queue.size() - 1]
		if str(last.get("type", "")) == "shoot":
			var tid := str(last.get("target_id", ""))
			var tpd: Dictionary = players.get(tid, {})
			var outcome := ZZLos.evaluate_shot(
				grid.walls_dict(),
				local_pos.x, local_pos.y,
				int(tpd.get("x", 0)), int(tpd.get("y", 0)),
				local_posture,
				str(tpd.get("posture", "stand"))
			)
			_preview_shoot(tid, outcome)


func _flush_move_history(lines: Array, move_run: int, move_end: Vector2i, move_ap: int) -> void:
	if move_run <= 0:
		return
	if move_run == 1:
		lines.append("Ход (%d,%d) · %d ОД" % [move_end.x, move_end.y, move_ap])
	else:
		lines.append("Путь → (%d,%d) · %d кл. / %d ОД" % [move_end.x, move_end.y, move_run, move_ap])


func _emit_history() -> void:
	var lines: Array = []
	var sim_pos := _turn_start_pos
	var sim_posture := _turn_start_posture
	var move_run := 0
	var move_end := sim_pos
	var move_ap := 0
	for a in action_queue:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var act: Dictionary = a
		match str(act.get("type", "")):
			"move":
				var step_c := move_cost_sit if sim_posture == "sit" else move_cost_stand
				sim_pos = Vector2i(int(act.get("x", 0)), int(act.get("y", 0)))
				move_end = sim_pos
				move_run += 1
				move_ap += step_c
			"shoot":
				_flush_move_history(lines, move_run, move_end, move_ap)
				move_run = 0
				move_ap = 0
				var tid := str(act.get("target_id", ""))
				var nick := str(players.get(tid, {}).get("nick", tid))
				var tpd: Dictionary = players.get(tid, {})
				var outcome := ZZLos.evaluate_shot(
					grid.walls_dict(),
					sim_pos.x, sim_pos.y,
					int(tpd.get("x", 0)), int(tpd.get("y", 0)),
					sim_posture,
					str(tpd.get("posture", "stand"))
				)
				if bool(outcome.get("blocked", false)):
					lines.append("Выстрел → %s (блок)" % nick)
				else:
					var pct := int(round(float(outcome.get("chance", 0.0)) * 100.0))
					lines.append("Выстрел → %s (%d%%)" % [nick, pct])
			"posture":
				_flush_move_history(lines, move_run, move_end, move_ap)
				move_run = 0
				move_ap = 0
				sim_posture = str(act.get("posture", "stand"))
				var label := "стоя"
				if sim_posture == "sit":
					label = "сидя"
				elif sim_posture == "cover":
					label = "укрылся"
				lines.append("Стойка: %s" % label)
	_flush_move_history(lines, move_run, move_end, move_ap)
	history_changed.emit(lines)
