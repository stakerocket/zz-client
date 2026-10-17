extends Node
class_name ZZBattleController

## From server rules only (lobby_state / battle_start / state.rules). Start at 0 until applied.
var move_cost_stand: int = 0
var move_cost_sit: int = 0
var move_ap_run_frac: float = 0.5
var shoot_cost: int = 0
var posture_cost: int = 0
var medkit_cost: int = 0
var medkit_heal_min: int = 0
var medkit_heal_max: int = 0
var medkit_max: int = 0
var reload_cost: int = 0
var switch_weapon_cost: int = 1
## Max AP/HP from player snapshot or ZZLos.compute_* after rules.
var max_ap: int = 0
var max_hp: int = 0
const PROJECTILE_TIME := 0.35
const ProjectileBoltScript := preload("res://scripts/battle/projectile_bolt.gd")
const WallBurstScript := preload("res://scripts/battle/wall_burst.gd")

signal ap_changed(value: int)
signal hp_changed(value: int)
signal medkits_changed(value: int)
signal ammo_changed(in_mag: int, reserve: int)
signal weapons_changed(weapons: Array, active_idx: int)
signal turn_changed(turn: int)
signal timer_changed(seconds_left: float)
signal input_lock_changed(locked: bool)
signal history_changed(lines: Array)
signal battle_started
signal battle_ended(winner_id: String)
signal room_players_changed(nicks: Array)
signal chat_received(nick: String, text: String, channel: String)
signal rules_changed
signal inventory_state_received(data: Dictionary)

var ws: ZZWSClient
var grid: ZZGridView
var units_root: Node3D

var local_nick: String = ""
var your_id: String = ""
var input_locked: bool = true
var local_ap: int = 0
var local_hp: int = 0
var local_medkits: int = 5
## Hotbar item ids from inventory quick slots (len 4).
var local_quick: Array = ["", "", "", ""]
## Last known inventory stacks (for quick-slot qty badges).
var local_inventory: Array = []
signal quick_changed
## Ammo: server state is source of truth; local queue mirrors like medkits until resolve.
var local_ammo_in_mag: int = 6
var local_ammo_reserve: int = 24
var local_weapons: Array = []
var local_active_weapon_idx: int = 0
var _turn_start_weapons: Array = []
var _turn_start_active_weapon_idx: int = 0
var local_mag_size: int = 6
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
var _turn_start_medkits: int = 5
var _turn_start_ammo_in_mag: int = 6
var _turn_start_ammo_reserve: int = 24
## Last hover path steps (excluding start), for click-to-queue.
var _hover_path: Array = []
var _hover_path_ap: int = 0
var _hover_affordable_steps: int = 0
var _end_turn_sent: bool = false

var _colors := [
	Color(0.30, 0.65, 0.95),
	Color(0.95, 0.55, 0.25),
	Color(0.35, 0.82, 0.45),
	Color(0.90, 0.35, 0.75),
	Color(0.95, 0.85, 0.30),
	Color(0.45, 0.85, 0.90),
	Color(0.85, 0.45, 0.35),
	Color(0.65, 0.55, 0.95),
]


func setup(ws_client: ZZWSClient, grid_view: ZZGridView, units: Node3D) -> void:
	ws = ws_client
	grid = grid_view
	units_root = units
	ws.message_received.connect(_on_message)
	grid.tile_clicked.connect(_on_tile_clicked)
	grid.tile_hovered.connect(_on_tile_hovered)
	grid.unit_cell_pick = _pick_unit_cell_at_screen


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


func request_inventory_get() -> void:
	if not ws.is_open() or in_battle:
		return
	ws.send_dict(ZZProtocol.inventory_get())


func request_inventory_equip(item_id: String, slot: String) -> void:
	if not ws.is_open() or in_battle or item_id == "" or slot == "":
		return
	ws.send_dict(ZZProtocol.inventory_equip(item_id, slot))


func request_inventory_unequip(slot: String) -> void:
	if not ws.is_open() or in_battle or slot == "":
		return
	ws.send_dict(ZZProtocol.inventory_unequip(slot))


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
	if posture != "stand" and posture != "sit" and posture != "cover" and posture != "run":
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


func request_medkit() -> void:
	if input_locked or not in_battle or _playing_events:
		return
	if local_ap < medkit_cost:
		return
	if local_medkits <= 0:
		return
	action_queue.append(ZZProtocol.medkit_action())
	local_ap -= medkit_cost
	local_medkits -= 1
	ap_changed.emit(local_ap)
	medkits_changed.emit(local_medkits)
	_emit_history()


func request_reload() -> void:
	if input_locked or not in_battle or _playing_events:
		return
	if local_ap < reload_cost:
		return
	# Client-only: no point queuing reload when mag is already full (or no reserve).
	if local_ammo_in_mag >= local_mag_size or local_ammo_reserve <= 0:
		return
	action_queue.append(ZZProtocol.reload_action())
	local_ap -= reload_cost
	var after := _sim_reload_ammo(local_ammo_in_mag, local_ammo_reserve)
	local_ammo_in_mag = after.x
	local_ammo_reserve = after.y
	_sync_active_weapon_ammo_local()
	ap_changed.emit(local_ap)
	ammo_changed.emit(local_ammo_in_mag, local_ammo_reserve)
	weapons_changed.emit(local_weapons, local_active_weapon_idx)
	_emit_history()


func request_weapon_slot(slot_index: int) -> void:
	if input_locked or not in_battle or _playing_events:
		return
	if slot_index < 0 or slot_index >= local_weapons.size():
		return
	if slot_index == local_active_weapon_idx:
		request_reload()
		return
	request_switch_weapon(slot_index)


func request_switch_weapon(slot_index: int) -> void:
	if input_locked or not in_battle or _playing_events:
		return
	if slot_index < 0 or slot_index >= local_weapons.size():
		return
	if slot_index == local_active_weapon_idx:
		return
	if local_ap < switch_weapon_cost:
		return
	action_queue.append(ZZProtocol.switch_weapon_action(slot_index))
	local_ap -= switch_weapon_cost
	_apply_local_switch(slot_index)
	ap_changed.emit(local_ap)
	_emit_history()


func _apply_local_switch(slot_index: int) -> void:
	_sync_active_weapon_ammo_local()
	local_active_weapon_idx = slot_index
	var w: Dictionary = local_weapons[slot_index]
	ZZLos.apply_weapon(w)
	shoot_cost = int(w.get("shoot_ap", shoot_cost))
	reload_cost = int(w.get("reload_ap", reload_cost))
	local_mag_size = maxi(1, int(w.get("mag_size", local_mag_size)))
	local_ammo_in_mag = int(w.get("ammo_in_mag", 0))
	local_ammo_reserve = int(w.get("ammo_reserve", 0))
	ammo_changed.emit(local_ammo_in_mag, local_ammo_reserve)
	weapons_changed.emit(local_weapons, local_active_weapon_idx)


func _sync_active_weapon_ammo_local() -> void:
	if local_active_weapon_idx < 0 or local_active_weapon_idx >= local_weapons.size():
		return
	if typeof(local_weapons[local_active_weapon_idx]) != TYPE_DICTIONARY:
		return
	local_weapons[local_active_weapon_idx]["ammo_in_mag"] = local_ammo_in_mag
	local_weapons[local_active_weapon_idx]["ammo_reserve"] = local_ammo_reserve


func request_undo() -> void:
	if input_locked or not in_battle or _playing_events:
		return
	if action_queue.is_empty():
		return
	# Path was queued as many move actions — undo the whole trailing streak at once.
	var last: Variant = action_queue[action_queue.size() - 1]
	if typeof(last) == TYPE_DICTIONARY and str(last.get("type", "")) == "move":
		while not action_queue.is_empty():
			var a: Variant = action_queue[action_queue.size() - 1]
			if typeof(a) != TYPE_DICTIONARY or str(a.get("type", "")) != "move":
				break
			action_queue.pop_back()
	else:
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
			_apply_combat_rules(data.get("rules", {}))
			ZZLos.apply_item_catalog(data.get("item_catalog", {}))
			rules_changed.emit()
			room_players_changed.emit(data.get("players", []))
		"inventory_state":
			_apply_quick_from_payload(data)
			inventory_state_received.emit(data)
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
	var events: Array = _as_array(data.get("events", []))
	var incoming_turn := int(data.get("turn", current_turn))
	# Mid-join / disconnect roster sync: same turn, no events — keep local plan.
	var sync_only := (
		kind == "state"
		and in_battle
		and events.is_empty()
		and incoming_turn == current_turn
	)
	if sync_only:
		_apply_state(data.get("state", {}), false, false)
		_emit_room_nicks_from_state(data.get("state", {}))
		_playing_events = false
		return
	if kind == "state":
		turn_deadline_ms = int(data.get("turn_deadline_ms", 30000))
		if data.has("turn"):
			current_turn = incoming_turn
			turn_changed.emit(current_turn)
	await _play_events(events)
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
	_refresh_unit_outlines()


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
	move_cost_stand = ZZLos.rule_i("move_ap_stand")
	move_cost_sit = ZZLos.rule_i("move_ap_sit")
	move_ap_run_frac = ZZLos.rule_f("move_ap_run_frac")
	if move_ap_run_frac <= 0.0:
		move_ap_run_frac = 0.5
	shoot_cost = ZZLos.rule_i("shoot_ap")
	posture_cost = ZZLos.rule_i("posture_ap")
	medkit_cost = ZZLos.rule_i("medkit_ap")
	medkit_heal_min = ZZLos.rule_i("medkit_heal_min")
	medkit_heal_max = ZZLos.rule_i("medkit_heal_max")
	if medkit_heal_max < medkit_heal_min:
		medkit_heal_max = medkit_heal_min
	medkit_max = ZZLos.rule_i("medkit_max")
	reload_cost = ZZLos.rule_i("weapon_reload_ap")
	switch_weapon_cost = ZZLos.rule_i("switch_weapon_ap")
	if switch_weapon_cost <= 0:
		switch_weapon_cost = 1
	var mag := ZZLos.rule_i("weapon_mag_size")
	if mag > 0:
		local_mag_size = mag
	if max_ap <= 0:
		max_ap = ZZLos.compute_max_ap()
	if max_hp <= 0:
		max_hp = ZZLos.compute_max_hp()
	rules_changed.emit()


func _apply_quick_from_payload(data: Dictionary) -> void:
	local_quick = ["", "", "", ""]
	var q: Variant = data.get("quick", [])
	if typeof(q) == TYPE_ARRAY:
		for i in range(mini(4, q.size())):
			local_quick[i] = str(q[i])
	var inv: Variant = data.get("inventory", [])
	if typeof(inv) == TYPE_ARRAY and not inv.is_empty():
		local_inventory = inv
	quick_changed.emit()


func stack_qty(item_id: String) -> int:
	if item_id == "":
		return 0
	for s in local_inventory:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("item_id", "")) == item_id:
			return int(s.get("qty", 0))
	## Medkit qty is also mirrored in local_medkits during battle.
	if str(ZZLos.item_def(item_id).get("type", "")) == "medkit":
		return local_medkits
	return 0


func _apply_local_weapon(pd: Dictionary) -> void:
	if not pd.has("weapon") and not pd.has("weapons"):
		return
	local_weapons.clear()
	var raw_ws: Variant = pd.get("weapons", [])
	if typeof(raw_ws) == TYPE_ARRAY:
		for item in raw_ws:
			if typeof(item) == TYPE_DICTIONARY:
				local_weapons.append((item as Dictionary).duplicate())
	var w: Variant = pd.get("weapon")
	if local_weapons.is_empty() and typeof(w) == TYPE_DICTIONARY:
		local_weapons.append((w as Dictionary).duplicate())
	local_active_weapon_idx = clampi(int(pd.get("active_weapon_idx", 0)), 0, maxi(0, local_weapons.size() - 1))
	_turn_start_weapons = []
	for item in local_weapons:
		_turn_start_weapons.append((item as Dictionary).duplicate())
	_turn_start_active_weapon_idx = local_active_weapon_idx
	if typeof(w) != TYPE_DICTIONARY and local_active_weapon_idx < local_weapons.size():
		w = local_weapons[local_active_weapon_idx]
	ZZLos.apply_weapon(w)
	shoot_cost = ZZLos.rule_i("shoot_ap")
	reload_cost = ZZLos.rule_i("weapon_reload_ap")
	if typeof(w) == TYPE_DICTIONARY:
		_set_ammo_from_weapon(w)
	weapons_changed.emit(local_weapons, local_active_weapon_idx)


func _player_stat(pd: Dictionary, key: String) -> int:
	var fallback := ZZLos.default_stat()
	var st: Variant = pd.get("stats", {})
	if typeof(st) != TYPE_DICTIONARY:
		return fallback
	return int(st.get(key, fallback))


func _evaluate_shot_at(from: Vector2i, shooter_posture: String, target_pd: Dictionary) -> Dictionary:
	var tgt_posture := str(target_pd.get("posture", "stand"))
	if tgt_posture == "":
		tgt_posture = "stand"
	var self_pd: Dictionary = players.get(your_id, {})
	return ZZLos.evaluate_shot(
		grid.walls_dict(),
		from.x, from.y,
		int(target_pd.get("x", 0)), int(target_pd.get("y", 0)),
		shooter_posture,
		tgt_posture,
		_player_stat(self_pd, "accuracy"),
		_player_stat(target_pd, "agility")
	)


func _set_ammo_from_weapon(w: Dictionary) -> void:
	if w.has("mag_size"):
		local_mag_size = maxi(1, int(w.get("mag_size", local_mag_size)))
	local_ammo_in_mag = int(w.get("ammo_in_mag", local_ammo_in_mag))
	local_ammo_reserve = int(w.get("ammo_reserve", local_ammo_reserve))
	_turn_start_ammo_in_mag = local_ammo_in_mag
	_turn_start_ammo_reserve = local_ammo_reserve
	ammo_changed.emit(local_ammo_in_mag, local_ammo_reserve)


func _apply_ammo_after_event(actor_id: String, e: Dictionary) -> void:
	# Always prefer event fields when present (0 is valid).
	if not e.has("ammo_in_mag_after"):
		return
	var in_mag := int(e.get("ammo_in_mag_after", 0))
	var reserve := int(e.get("ammo_reserve_after", local_ammo_reserve if actor_id == your_id else 0))
	if players.has(actor_id):
		var pd: Dictionary = players[actor_id]
		var w: Variant = pd.get("weapon", {})
		if typeof(w) != TYPE_DICTIONARY:
			w = {}
		w["ammo_in_mag"] = in_mag
		w["ammo_reserve"] = reserve
		pd["weapon"] = w
		players[actor_id] = pd
	if actor_id == your_id:
		local_ammo_in_mag = in_mag
		local_ammo_reserve = reserve
		_turn_start_ammo_in_mag = in_mag
		_turn_start_ammo_reserve = reserve
		ammo_changed.emit(local_ammo_in_mag, local_ammo_reserve)


func _sim_reload_ammo(in_mag: int, reserve: int) -> Vector2i:
	var need := local_mag_size - in_mag
	if need > 0 and reserve > 0:
		var take: int = mini(need, reserve)
		in_mag += take
		reserve -= take
	return Vector2i(in_mag, reserve)


func _refresh_unit_outlines() -> void:
	if grid == null:
		return
	# During turn replay, hide hex rings under units (don't slide them hex-to-hex).
	if _playing_events:
		grid.clear_unit_outlines()
		return
	var enemies: Array = []
	for pid in players.keys():
		if str(pid) == your_id:
			continue
		var pd: Dictionary = players[pid]
		if int(pd.get("hp", 0)) <= 0:
			continue
		enemies.append(Vector2i(int(pd.get("x", -1)), int(pd.get("y", -1))))
	var own := local_pos
	if your_id != "" and players.has(your_id) and int(players[your_id].get("hp", 0)) <= 0:
		own = Vector2i(-1, -1)
	grid.set_unit_outlines(own, enemies)


func _play_events(events: Variant) -> void:
	if grid != null:
		grid.clear_unit_outlines()
	var list: Array = _as_array(events)
	if list.is_empty():
		return
	var groups := _group_events_by_clock(list)
	var gi := 0
	while gi < groups.size():
		var group: Array = groups[gi]
		# Continuous path for one actor (incl. same-clock free run steps at 0 AP).
		if _is_solo_actor_move_group(group):
			var chain: Array = group.duplicate()
			var actor_id := str(group[0].get("actor_id", ""))
			var j := gi + 1
			while j < groups.size() and _is_solo_actor_move_group(groups[j]):
				var nxt: Array = groups[j]
				if str(nxt[0].get("actor_id", "")) != actor_id:
					break
				chain.append_array(nxt)
				j += 1
			await _play_move_chain(chain)
			gi = j
		else:
			await _play_event_group(group, groups, gi)
			gi += 1


func _is_solo_actor_move_group(group: Array) -> bool:
	## True if every event is a move by the same actor (1+ steps; run free-steps share clock).
	if group.is_empty():
		return false
	var actor_id := ""
	for ev in group:
		if typeof(ev) != TYPE_DICTIONARY:
			return false
		var e: Dictionary = ev
		if str(e.get("type", "")) != "move":
			return false
		var aid := str(e.get("actor_id", ""))
		if actor_id == "":
			actor_id = aid
		elif aid != actor_id:
			return false
	return actor_id != ""


func _actor_move_continues(groups: Array, gi: int, actor_id: String) -> bool:
	for j in range(gi + 1, groups.size()):
		var g: Array = groups[j]
		for ev in g:
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			var e: Dictionary = ev
			var t := str(e.get("type", ""))
			if t == "move" and str(e.get("actor_id", "")) == actor_id:
				return true
			# Any other action by this actor breaks the run streak.
			if str(e.get("actor_id", "")) == actor_id and t != "move":
				return false
	return false


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


func _play_event_group(group: Array, groups: Array = [], gi: int = 0) -> void:
	if group.is_empty():
		return
	if group.size() == 1:
		await _play_one_event(group[0], groups, gi)
		return
	# Same clock may pack several free run-steps for one actor — never tween those in parallel.
	var move_by_actor: Dictionary = {}
	var others: Array = []
	for ev in group:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = ev
		if str(e.get("type", "")) == "move":
			var aid := str(e.get("actor_id", ""))
			if not move_by_actor.has(aid):
				move_by_actor[aid] = []
			(move_by_actor[aid] as Array).append(e)
		else:
			others.append(e)
	var tasks := move_by_actor.size() + others.size()
	if tasks <= 0:
		return
	if tasks == 1 and others.is_empty():
		for aid in move_by_actor.keys():
			await _play_move_chain_for_group(move_by_actor[aid], groups, gi)
		return
	var pending := {"n": tasks}
	for aid in move_by_actor.keys():
		_play_move_chain_parallel(move_by_actor[aid], pending, groups, gi)
	for e in others:
		_play_one_event_parallel(e, pending, groups, gi)
	while int(pending.n) > 0:
		await get_tree().process_frame


func _play_move_chain_parallel(moves: Array, pending: Dictionary, groups: Array = [], gi: int = 0) -> void:
	await _play_move_chain_for_group(moves, groups, gi)
	pending.n = int(pending.n) - 1


func _play_move_chain_for_group(moves: Array, groups: Array = [], gi: int = 0) -> void:
	if moves.is_empty():
		return
	var actor_id := str(moves[0].get("actor_id", ""))
	var continues := false
	if not groups.is_empty():
		continues = _actor_move_continues(groups, gi, actor_id)
	await _play_move_chain(moves, not continues)


func _play_one_event_parallel(e: Dictionary, pending: Dictionary, groups: Array = [], gi: int = 0) -> void:
	await _play_one_event(e, groups, gi)
	pending.n = int(pending.n) - 1


func _play_one_event(e: Dictionary, groups: Array = [], gi: int = 0) -> void:
	match str(e.get("type", "")):
		"move":
			var actor_id := str(e.get("actor_id", ""))
			var stop_at_end := true
			if not groups.is_empty():
				stop_at_end = not _actor_move_continues(groups, gi, actor_id)
			await _play_move_event(e, stop_at_end)
		"posture":
			await _play_posture_event(e)
		"medkit":
			await _play_medkit_event(e)
		"reload":
			await _play_reload_event(e)
		"switch_weapon":
			await _play_switch_weapon_event(e)
		"shoot":
			await _play_shoot_event(e)
		_:
			pass


func _play_switch_weapon_event(e: Dictionary) -> void:
	var actor_id := str(e.get("actor_id", ""))
	var idx := int(e.get("weapon_index", 0))
	var wid := str(e.get("weapon_id", ""))
	if players.has(actor_id):
		players[actor_id]["active_weapon_idx"] = idx
		if wid != "":
			var w: Variant = players[actor_id].get("weapon", {})
			if typeof(w) == TYPE_DICTIONARY:
				w["id"] = wid
			players[actor_id]["weapon"] = w
	if actor_id == your_id:
		_apply_ammo_after_event(actor_id, e)
		if idx >= 0 and idx < local_weapons.size():
			local_active_weapon_idx = idx
			var slot: Dictionary = local_weapons[idx]
			if wid != "":
				slot["id"] = wid
			if e.has("ammo_in_mag_after"):
				slot["ammo_in_mag"] = int(e.get("ammo_in_mag_after", 0))
				slot["ammo_reserve"] = int(e.get("ammo_reserve_after", 0))
			ZZLos.apply_weapon(slot)
			shoot_cost = int(slot.get("shoot_ap", shoot_cost))
			reload_cost = int(slot.get("reload_ap", reload_cost))
			local_mag_size = maxi(1, int(slot.get("mag_size", local_mag_size)))
			weapons_changed.emit(local_weapons, local_active_weapon_idx)
	await get_tree().create_timer(0.2).timeout


func _play_reload_event(e: Dictionary) -> void:
	var actor_id := str(e.get("actor_id", ""))
	_apply_ammo_after_event(actor_id, e)
	await get_tree().create_timer(0.25).timeout


func _play_medkit_event(e: Dictionary) -> void:
	var actor_id := str(e.get("actor_id", ""))
	var heal := int(e.get("heal", 0))
	var hp_after := int(e.get("hp_after", 0))
	var medkits_after := int(e.get("medkits_after", 0))
	var uv: ZZUnitView = unit_nodes.get(actor_id)
	if uv != null and is_instance_valid(uv):
		await uv.apply_heal(heal, hp_after)
	if players.has(actor_id):
		players[actor_id]["hp"] = hp_after
		players[actor_id]["medkits"] = medkits_after
	if actor_id == your_id:
		local_hp = hp_after
		local_medkits = medkits_after
		_turn_start_medkits = medkits_after
		hp_changed.emit(local_hp)
		medkits_changed.emit(local_medkits)
	await get_tree().create_timer(0.35).timeout


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


func _play_move_chain(events: Array, stop_after_last: bool = true) -> void:
	if events.is_empty():
		return
	var first: Dictionary = events[0]
	var actor_id := str(first.get("actor_id", ""))
	var uv: ZZUnitView = unit_nodes.get(actor_id)
	if uv == null or not is_instance_valid(uv):
		return
	var from0 := Vector2i(int(first.get("from_x", 0)), int(first.get("from_y", 0)))
	# Rewind once to path start (local prediction already finished at destination).
	uv.position = grid.grid_to_world(from0.x, from0.y)
	for i in range(events.size()):
		var e: Dictionary = events[i]
		var to := Vector2i(int(e.get("to_x", 0)), int(e.get("to_y", 0)))
		var stop_at_end := stop_after_last and i == events.size() - 1
		await uv.animate_move_to(grid.grid_to_world(to.x, to.y), true, stop_at_end)
		if players.has(actor_id):
			players[actor_id]["x"] = to.x
			players[actor_id]["y"] = to.y
		if actor_id == your_id:
			local_pos = to


func _play_move_event(e: Dictionary, stop_at_end: bool = true) -> void:
	var actor_id := str(e.get("actor_id", ""))
	var uv: ZZUnitView = unit_nodes.get(actor_id)
	if uv == null or not is_instance_valid(uv):
		return
	var from := Vector2i(int(e.get("from_x", 0)), int(e.get("from_y", 0)))
	var to := Vector2i(int(e.get("to_x", 0)), int(e.get("to_y", 0)))
	var from_w := grid.grid_to_world(from.x, from.y)
	# Avoid micro-snaps between chained steps (planning path is already smooth).
	if uv.global_position.distance_squared_to(from_w) > 0.0004:
		uv.position = from_w
	await uv.animate_move_to(grid.grid_to_world(to.x, to.y), true, stop_at_end)
	if players.has(actor_id):
		players[actor_id]["x"] = to.x
		players[actor_id]["y"] = to.y
	if actor_id == your_id:
		local_pos = to


func _play_shoot_event(e: Dictionary) -> void:
	var actor_id := str(e.get("actor_id", ""))
	var target_id := str(e.get("target_id", ""))
	_apply_ammo_after_event(actor_id, e)
	var actor: ZZUnitView = unit_nodes.get(actor_id)
	if actor == null or not is_instance_valid(actor):
		return
	var impact := grid.grid_to_world(int(e.get("to_x", 0)), int(e.get("to_y", 0))) + Vector3(0, 1.4, 0)
	var hit_wall := bool(e.get("hit_wall", false))
	actor.face_world(impact)
	# Fire pose + bolt slightly overlap for snappier feedback.
	actor.play_fire()
	Sfx.play_shoot()
	await get_tree().create_timer(0.12).timeout
	await _fly_projectile(_unit_muzzle(actor), impact, actor.color)
	if hit_wall:
		Sfx.play_hit_wall()
		await _wall_burst_at(impact)
		return
	var target: ZZUnitView = unit_nodes.get(target_id)
	if target == null or not is_instance_valid(target):
		return
	var damage := int(e.get("damage", 0))
	var hp_after := int(e.get("hp_after", 0))
	var crit := bool(e.get("crit", false))
	if damage > 0:
		Sfx.play_hit_target()
		await target.apply_hit(damage, hp_after, _is_death_front_blocked(target_id, target), crit)
	else:
		Sfx.play_miss()
		await target.apply_miss()
		target.set_hp(hp_after, true, _is_death_front_blocked(target_id, target))
	if players.has(target_id):
		players[target_id]["hp"] = hp_after
	if target_id == your_id:
		local_hp = hp_after
		hp_changed.emit(local_hp)


func _unit_muzzle(uv: ZZUnitView) -> Vector3:
	return uv.global_position + Vector3(0, ZZUnitView.CAPSULE_HEIGHT * 0.62, 0)


func _pick_unit_cell_at_screen(screen_pos: Vector2) -> Vector2i:
	var pid := _unit_id_at_screen(screen_pos)
	if pid == "" or not players.has(pid):
		return Vector2i(-1, -1)
	var pd: Dictionary = players[pid]
	if int(pd.get("hp", 0)) <= 0:
		return Vector2i(-1, -1)
	return Vector2i(int(pd.get("x", -1)), int(pd.get("y", -1)))


func _unit_id_at_screen(screen_pos: Vector2) -> String:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return ""
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if dir.length_squared() < 0.0001:
		return ""
	dir = dir.normalized()
	var best_id := ""
	var best_t := INF
	var pick_r := ZZGridView.HEX_SIZE * 0.9
	var pick_h := ZZUnitView.CAPSULE_HEIGHT * ZZUnitView.MODEL_SCALE * 0.55
	for pid in unit_nodes.keys():
		var uv: ZZUnitView = unit_nodes[pid]
		if uv == null or not is_instance_valid(uv) or uv.is_dead or uv.is_dying:
			continue
		var t := _ray_hit_unit_t(origin, dir, uv.global_position, pick_h, pick_r)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_id = str(pid)
	return best_id


func _ray_hit_unit_t(origin: Vector3, dir: Vector3, feet: Vector3, height: float, radius: float) -> float:
	# Closest approach between camera ray and vertical unit axis.
	var axis_b := feet + Vector3(0, maxf(height, 0.5), 0)
	var ray_b := origin + dir * 250.0
	var pts := Geometry3D.get_closest_points_between_segments(origin, ray_b, feet, axis_b)
	if pts.size() < 2:
		return -1.0
	if pts[0].distance_to(pts[1]) > radius:
		return -1.0
	var t := (pts[0] - origin).dot(dir)
	if t < 0.0:
		return -1.0
	return t


func _is_death_front_blocked(pid: String, uv: ZZUnitView) -> bool:
	if grid == null or uv == null or not is_instance_valid(uv):
		return false
	var pd: Dictionary = players.get(pid, {})
	var cell := Vector2i(int(pd.get("x", 0)), int(pd.get("y", 0)))
	var facing := uv.facing_forward_xz()
	var origin := grid.grid_to_world(cell.x, cell.y)
	var best_n := Vector2i(-1, -1)
	var best_dot := -INF
	for n in ZZLos.hex_neighbors(cell.x, cell.y):
		var nb: Vector2i = n
		if nb.x < 0 or nb.y < 0 or nb.x >= ZZGridView.GRID_COLS or nb.y >= ZZGridView.GRID_ROWS:
			continue
		var delta := grid.grid_to_world(nb.x, nb.y) - origin
		delta.y = 0.0
		if delta.length_squared() < 0.0001:
			continue
		var d := delta.normalized().dot(facing)
		if d > best_dot:
			best_dot = d
			best_n = nb
	# Need a clearly forward neighbor; otherwise treat as clear.
	if best_n.x < 0 or best_dot < 0.35:
		return false
	return grid.has_wall(best_n.x, best_n.y)


func _fly_projectile(from: Vector3, to: Vector3, tint: Color, preview: bool = false) -> void:
	var bolt: Node3D = ProjectileBoltScript.new()
	bolt.set_meta("zz_preview", preview)
	bolt.set("tint", tint.lightened(0.35))
	units_root.add_child(bolt)
	var start := from
	var end := to
	if end.y < 0.3:
		end.y = 1.0
	if start.y < 0.3:
		start.y = 1.1
	bolt.global_position = start
	var tw := units_root.create_tween()
	tw.tween_property(bolt, "global_position", end, PROJECTILE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	if is_instance_valid(bolt):
		bolt.queue_free()


func _preview_shoot(target_id: String, outcome: Dictionary) -> void:
	var actor: ZZUnitView = unit_nodes.get(your_id)
	var target: ZZUnitView = unit_nodes.get(target_id)
	if actor == null or target == null:
		return
	if not is_instance_valid(actor) or not is_instance_valid(target):
		return
	var impact: Vector3
	var hit_wall := bool(outcome.get("blocked", false))
	if hit_wall:
		var wc: Vector2i = outcome.get("wall", Vector2i.ZERO)
		impact = grid.grid_to_world(wc.x, wc.y) + Vector3(0, 1.0, 0)
	else:
		impact = _unit_muzzle(target)
	actor.face_world(impact)
	actor.play_fire()
	await get_tree().create_timer(0.12).timeout
	await _fly_projectile(_unit_muzzle(actor), impact, actor.color, true)
	if hit_wall:
		await _wall_burst_at(impact)
		return
	if is_instance_valid(target) and not target.is_dead and not target.is_dying:
		await target.flash_hit()


func _wall_burst_at(world_pos: Vector3) -> void:
	var fx: Node3D = WallBurstScript.new()
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


func _apply_map_size_from_state(st: Dictionary) -> void:
	if grid == null:
		return
	var cols := int(st.get("grid_w", st.get("grid", ZZGridView.GRID_COLS)))
	var rows := int(st.get("grid_h", ZZGridView.GRID_ROWS))
	# Legacy square payload: only `grid` set.
	if not st.has("grid_h") and st.has("grid") and not st.has("grid_w"):
		rows = cols
	grid.set_map_size(cols, rows)


func _apply_state(state: Variant, reset_queue: bool, snap_positions: bool) -> void:
	if typeof(state) != TYPE_DICTIONARY:
		return
	var st: Dictionary = state
	_apply_map_size_from_state(st)
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
	var seen: Dictionary = {}
	var idx := 0
	for p in list:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = p
		var pid := str(pd.get("id", ""))
		seen[pid] = true
		players[pid] = pd
		_ensure_unit(pid, str(pd.get("nick", "?")), idx)
		var uv: ZZUnitView = unit_nodes[pid]
		if pd.has("max_hp"):
			uv.set_max_hp(maxi(1, int(pd.get("max_hp", 100))))
		var hp_val := int(pd.get("hp", 0))
		if uv.is_dead or uv.is_dying:
			uv.set_hp(hp_val, false)
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
			if pd.has("max_ap"):
				max_ap = maxi(1, int(pd.get("max_ap", max_ap)))
			local_hp = hp_val
			local_medkits = int(pd.get("medkits", medkit_max))
			if pd.has("max_hp"):
				max_hp = maxi(1, int(pd.get("max_hp", max_hp)))
				uv.set_max_hp(max_hp)
			else:
				max_hp = maxi(uv.max_hp, local_hp)
			local_pos = Vector2i(gx, gy)
			local_posture = posture
			_turn_start_pos = local_pos
			_turn_start_ap = local_ap
			_turn_start_posture = local_posture
			_turn_start_medkits = local_medkits
			_apply_local_weapon(pd)
			_apply_quick_from_payload(pd)
			ap_changed.emit(local_ap)
			hp_changed.emit(local_hp)
			medkits_changed.emit(local_medkits)
		idx += 1
	for pid in unit_nodes.keys():
		if seen.has(pid):
			continue
		var orphan: Node = unit_nodes[pid]
		unit_nodes.erase(pid)
		if is_instance_valid(orphan):
			orphan.queue_free()
	_refresh_unit_outlines()


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
		grid.clear_unit_outlines()
	_clear_hover_path()
	_clear_aim_previews()


func _ensure_unit(pid: String, nick: String, idx: int) -> void:
	if unit_nodes.has(pid):
		return
	var uv := ZZUnitView.new()
	units_root.add_child(uv)
	var color: Color = _colors[idx % _colors.size()]
	uv.setup(pid, nick, color)
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
	var outcome := _evaluate_shot_at(local_pos, local_posture, pd2)
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
	# ×2 of max turn AP so full-budget paths + gray preview beyond current AP.
	# Run: ~2 hexes per AP → horizon scales with 1/frac.
	if local_posture == "run" and move_ap_run_frac > 0.0:
		return maxi(1, int(ceil(float(max_ap) / move_ap_run_frac * 2.0)))
	return maxi(1, int(ceil(float(max_ap) * 2.0)))


func _path_to(g: Vector2i) -> Dictionary:
	if local_posture == "cover":
		return {"path": [], "ap": 0, "affordable_steps": 0}
	var step := _move_cost_for(local_posture)
	var frac := 0.0
	if local_posture == "run":
		frac = move_ap_run_frac
		step = 1
	elif step <= 0:
		return {"path": [], "ap": 0, "affordable_steps": 0}
	# budget_ap = remaining AP (green/gray); max_steps = 2 × max_ap pool.
	var streak := _run_streak_in_queue() if local_posture == "run" else 0
	return ZZPathfind.find_path(
		local_pos, g, grid.walls_dict(), _occupied_keys_except_self(),
		step, local_ap, ZZGridView.GRID_COLS, ZZGridView.GRID_ROWS, _path_preview_steps(), frac, streak
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
	var affordable_ap := ap_cost
	if affordable < _hover_path.size():
		if local_posture == "run":
			affordable_ap = ZZPathfind.run_extra_ap(_run_streak_in_queue(), affordable)
		else:
			affordable_ap = affordable * _move_cost_for(local_posture)
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
	if posture == "run":
		return 1 # odd-step; even free — use _run_step_cost / path ceil
	return move_cost_stand


func _run_step_cost(streak: int) -> int:
	# 1-based next step: odd pay 1, even free (matches server NextMoveAPCost).
	if (streak + 1) % 2 == 1:
		return 1
	return 0


func _run_streak_in_queue() -> int:
	# Trailing consecutive moves while posture is run at that point in the plan.
	var streak := 0
	var posture := _turn_start_posture
	for a in action_queue:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var act: Dictionary = a
		match str(act.get("type", "")):
			"posture":
				posture = str(act.get("posture", "stand"))
				streak = 0
			"move":
				if posture == "run":
					streak += 1
				else:
					streak = 0
			_:
				streak = 0
	return streak if posture == "run" else 0


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
	if local_posture == "cover":
		return
	var run := local_posture == "run"
	var step_cost := _move_cost_for(local_posture)
	if not run and step_cost <= 0:
		return
	var moved_cells: Array = []
	var prev := local_pos
	var streak := _run_streak_in_queue() if run else 0
	for step in path:
		var cell: Vector2i = step
		if not ZZLos.is_hex_neighbor(prev.x, prev.y, cell.x, cell.y):
			break
		if grid.has_wall(cell.x, cell.y):
			break
		var cost := _run_step_cost(streak) if run else step_cost
		if local_ap < cost:
			break
		# One ActionMove per hex — server resolves them as a chain.
		action_queue.append(ZZProtocol.move_action(cell.x, cell.y))
		local_ap -= cost
		if run:
			streak += 1
		prev = cell
		local_pos = cell
		moved_cells.append(cell)
	if moved_cells.is_empty():
		return
	ap_changed.emit(local_ap)
	grid.set_highlight(local_pos)
	_refresh_unit_outlines()
	_emit_history()
	_clear_hover_path()
	if unit_nodes.has(your_id):
		_animate_local_path(moved_cells)


func _animate_local_path(cells: Array) -> void:
	var uv: ZZUnitView = unit_nodes.get(your_id)
	if uv == null or not is_instance_valid(uv):
		return
	# Local plan preview — silent; SFX only during turn resolve playback.
	for i in range(cells.size()):
		var g: Vector2i = cells[i]
		var stop_at_end := i == cells.size() - 1
		await uv.animate_move_to(grid.grid_to_world(g.x, g.y), false, stop_at_end)


func _queue_shoot(target_id: String) -> void:
	if local_ap < shoot_cost:
		return
	if local_ammo_in_mag <= 0:
		return
	if not ZZLos.can_shoot_from(local_posture):
		return
	var pd: Dictionary = players.get(target_id, {})
	var tx := int(pd.get("x", 0))
	var ty := int(pd.get("y", 0))
	var outcome := _evaluate_shot_at(local_pos, local_posture, pd)
	action_queue.append(ZZProtocol.shoot_action(target_id))
	local_ap -= shoot_cost
	local_ammo_in_mag = maxi(0, local_ammo_in_mag - 1)
	_sync_active_weapon_ammo_local()
	ap_changed.emit(local_ap)
	ammo_changed.emit(local_ammo_in_mag, local_ammo_reserve)
	weapons_changed.emit(local_weapons, local_active_weapon_idx)
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
	local_medkits = _turn_start_medkits
	local_ammo_in_mag = _turn_start_ammo_in_mag
	local_ammo_reserve = _turn_start_ammo_reserve
	local_weapons = []
	for item in _turn_start_weapons:
		local_weapons.append((item as Dictionary).duplicate())
	local_active_weapon_idx = _turn_start_active_weapon_idx
	if local_active_weapon_idx < local_weapons.size():
		var aw: Dictionary = local_weapons[local_active_weapon_idx]
		ZZLos.apply_weapon(aw)
		shoot_cost = int(aw.get("shoot_ap", shoot_cost))
		reload_cost = int(aw.get("reload_ap", reload_cost))
		local_mag_size = maxi(1, int(aw.get("mag_size", local_mag_size)))
	if unit_nodes.has(your_id):
		var uv: ZZUnitView = unit_nodes[your_id]
		if uv != null and is_instance_valid(uv) and not uv.is_dead:
			uv.snap_to(grid.grid_to_world(local_pos.x, local_pos.y))
			uv.set_posture(local_posture)
	var run_streak := 0
	for a in action_queue:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var act: Dictionary = a
		match str(act.get("type", "")):
			"move":
				var mcost: int
				if local_posture == "run":
					mcost = _run_step_cost(run_streak)
					run_streak += 1
				else:
					mcost = _move_cost_for(local_posture)
					run_streak = 0
				local_pos = Vector2i(int(act.get("x", 0)), int(act.get("y", 0)))
				local_ap -= mcost
			"shoot":
				local_ap -= shoot_cost
				local_ammo_in_mag = maxi(0, local_ammo_in_mag - 1)
				_sync_active_weapon_ammo_local()
				run_streak = 0
			"posture":
				local_posture = str(act.get("posture", "stand"))
				local_ap -= posture_cost
				run_streak = 0
			"medkit":
				local_ap -= medkit_cost
				local_medkits = maxi(0, local_medkits - 1)
				run_streak = 0
			"reload":
				local_ap -= reload_cost
				var after := _sim_reload_ammo(local_ammo_in_mag, local_ammo_reserve)
				local_ammo_in_mag = after.x
				local_ammo_reserve = after.y
				_sync_active_weapon_ammo_local()
				run_streak = 0
			"switch_weapon":
				local_ap -= switch_weapon_cost
				_apply_local_switch(int(act.get("weapon_index", 0)))
				run_streak = 0
	if unit_nodes.has(your_id):
		var uv2: ZZUnitView = unit_nodes[your_id]
		if uv2 != null and is_instance_valid(uv2) and not uv2.is_dead:
			uv2.snap_to(grid.grid_to_world(local_pos.x, local_pos.y))
			uv2.set_posture(local_posture)
	if grid != null:
		grid.set_highlight(local_pos if local_pos != _turn_start_pos else Vector2i(-1, -1))
	_clear_hover_path()
	ap_changed.emit(local_ap)
	medkits_changed.emit(local_medkits)
	ammo_changed.emit(local_ammo_in_mag, local_ammo_reserve)
	weapons_changed.emit(local_weapons, local_active_weapon_idx)
	_refresh_unit_outlines()
	_emit_history()
	# Re-preview last shoot if present.
	if not action_queue.is_empty():
		var last: Dictionary = action_queue[action_queue.size() - 1]
		if str(last.get("type", "")) == "shoot":
			var tid := str(last.get("target_id", ""))
			var tpd: Dictionary = players.get(tid, {})
			var outcome := _evaluate_shot_at(local_pos, local_posture, tpd)
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
	var run_streak := 0
	for a in action_queue:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var act: Dictionary = a
		match str(act.get("type", "")):
			"move":
				var step_c: int
				if sim_posture == "run":
					step_c = _run_step_cost(run_streak)
					run_streak += 1
				else:
					step_c = _move_cost_for(sim_posture)
					run_streak = 0
				sim_pos = Vector2i(int(act.get("x", 0)), int(act.get("y", 0)))
				move_end = sim_pos
				move_run += 1
				move_ap += step_c
			"shoot":
				_flush_move_history(lines, move_run, move_end, move_ap)
				move_run = 0
				move_ap = 0
				run_streak = 0
				var tid := str(act.get("target_id", ""))
				var nick := str(players.get(tid, {}).get("nick", tid))
				var tpd: Dictionary = players.get(tid, {})
				var outcome := _evaluate_shot_at(sim_pos, sim_posture, tpd)
				if bool(outcome.get("blocked", false)):
					lines.append("Выстрел → %s (блок)" % nick)
				else:
					var pct := int(round(float(outcome.get("chance", 0.0)) * 100.0))
					lines.append("Выстрел → %s (%d%%)" % [nick, pct])
			"posture":
				_flush_move_history(lines, move_run, move_end, move_ap)
				move_run = 0
				move_ap = 0
				run_streak = 0
				sim_posture = str(act.get("posture", "stand"))
				var label := "стоя"
				if sim_posture == "sit":
					label = "сидя"
				elif sim_posture == "cover":
					label = "укрылся"
				elif sim_posture == "run":
					label = "бег"
				lines.append("Стойка: %s" % label)
			"medkit":
				_flush_move_history(lines, move_run, move_end, move_ap)
				move_run = 0
				move_ap = 0
				run_streak = 0
				lines.append("Аптечка (+%d–%d ХП) · %d ОД" % [medkit_heal_min, medkit_heal_max, medkit_cost])
			"reload":
				_flush_move_history(lines, move_run, move_end, move_ap)
				move_run = 0
				move_ap = 0
				run_streak = 0
				lines.append("Перезарядка · %d ОД" % reload_cost)
			"switch_weapon":
				_flush_move_history(lines, move_run, move_end, move_ap)
				move_run = 0
				move_ap = 0
				run_streak = 0
				var widx := int(act.get("weapon_index", 0))
				var wname := "оружие"
				if widx < local_weapons.size() and typeof(local_weapons[widx]) == TYPE_DICTIONARY:
					var wid := str(local_weapons[widx].get("id", ""))
					if wid == "glock17":
						wname = "пистолет"
					elif wid == "kar98":
						wname = "винтовка"
					elif wid != "":
						var def := ZZLos.item_def(wid)
						wname = str(def.get("name", wid))
				lines.append("Смена: %s · %d ОД" % [wname, switch_weapon_cost])
	_flush_move_history(lines, move_run, move_end, move_ap)
	history_changed.emit(lines)
