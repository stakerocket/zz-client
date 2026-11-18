extends Node

const ZOOM_MAX := 1.35 ## closest
const ZOOM_MIN := 0.55 ## farthest
const ZOOM_STEP := 0.08
const PAN_KEY_SPEED := 420.0 ## px / sec at zoom 1
const HUD_BOTTOM_FRAC := 0.18
const HUD_PAD_PX := 2.0
const TOP_VOID_MAX_PX := 50.0
const SIDE_VOID_MAX_PX := 100.0

## Battle-only Camera2D. Lobby/login must NEVER make this current.
@onready var battle_camera: Camera2D = $Camera2D
@onready var world: Node2D = $World
@onready var grid: ZZGridView = $World/Grid
@onready var units: Node2D = $World/Units
@onready var ui: ZZAppUI = $UI
@onready var ws: ZZWSClient = $WSClient
@onready var battle: ZZBattleController = $BattleController

var _panning := false
var _pan_last_screen := Vector2.ZERO
var _focus := Vector2.ZERO


func _ready() -> void:
	_apply_window_fill()
	RenderingServer.set_default_clear_color(Color(0.11, 0.10, 0.09))
	battle.setup(ws, grid, units)
	_setup_battle_camera()
	_fit_camera_to_map()
	_set_battle_view_active(false)
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	battle.ap_changed.connect(ui.set_ap)
	battle.hp_changed.connect(ui.set_hp)
	battle.turn_changed.connect(ui.set_turn)
	battle.timer_changed.connect(ui.set_timer_seconds)
	battle.battle_started.connect(_on_battle_started)
	battle.battle_ended.connect(_on_battle_ended)
	battle.rules_changed.connect(ui.refresh_lobby_stats_from_rules)
	battle.room_players_changed.connect(ui.set_room_players)
	battle.chat_received.connect(func(nick: String, text: String, channel: String):
		ui.append_chat(nick, text, channel)
	)
	battle.input_lock_changed.connect(func(locked: bool):
		var can_plan := not locked and battle.in_battle
		ui.set_end_enabled(can_plan)
		ui.set_undo_enabled(can_plan and not battle.action_queue.is_empty())
		_refresh_consumable_btns()
	)
	battle.history_changed.connect(func(_lines: Array):
		ui.set_undo_enabled(not battle.input_locked and battle.in_battle and not battle.action_queue.is_empty())
		_refresh_consumable_btns()
	)
	battle.ap_changed.connect(func(_v):
		ui.set_posture(battle.local_posture)
		_refresh_consumable_btns()
	)
	battle.hp_changed.connect(func(_v):
		_refresh_consumable_btns()
	)
	battle.medkits_changed.connect(func(count: int):
		ui.set_medkit_count(count, battle.medkit_heal_min, battle.medkit_heal_max, battle.medkit_cost)
		_refresh_quick_bar()
		_refresh_consumable_btns()
	)
	battle.quick_changed.connect(func():
		_refresh_quick_bar()
		_refresh_consumable_btns()
	)
	battle.ammo_changed.connect(func(in_mag: int, reserve: int):
		ui.set_ammo(in_mag, reserve)
		ui.set_reload_cost(battle.reload_cost)
		_refresh_consumable_btns()
	)
	battle.weapons_changed.connect(func(weapons: Array, active_idx: int):
		ui.set_weapons(weapons, active_idx, battle.switch_weapon_cost)
		ui.set_reload_cost(battle.reload_cost)
		ui.set_shoot_cost(battle.shoot_cost)
		_refresh_consumable_btns()
		_refresh_fire_mode_hint()
	)
	battle.fire_mode_changed.connect(func(_mode: String):
		_refresh_fire_mode_hint()
	)
	battle.enemy_dossier_changed.connect(_on_enemy_dossier_changed)

	ui.continue_pressed.connect(_on_continue)
	ui.find_match_pressed.connect(_on_find_match)
	ui.cancel_match_pressed.connect(_on_cancel_match)
	battle.queue_left.connect(func(): ui.set_searching(false))
	ui.end_turn_pressed.connect(battle.request_end_turn)
	ui.undo_pressed.connect(battle.request_undo)
	ui.posture_pressed.connect(battle.request_posture)
	ui.medkit_pressed.connect(battle.request_medkit)
	ui.reload_pressed.connect(battle.request_reload)
	ui.weapon_slot_pressed.connect(battle.request_weapon_slot)
	ui.quick_slot_pressed.connect(_on_quick_slot_pressed)
	ui.chat_submitted.connect(func(text: String, channel: String):
		battle.send_chat(text, channel)
	)
	ui.return_to_lobby_pressed.connect(_on_return_to_lobby)
	ui.inventory_open_pressed.connect(func():
		battle.request_inventory_get()
	)
	ui.battle_inventory_pressed.connect(battle.request_inventory_open)
	ui.inventory_equip_requested.connect(battle.request_inventory_equip)
	ui.inventory_unequip_requested.connect(battle.request_inventory_unequip)
	ui.inventory_withdraw_requested.connect(battle.request_inventory_withdraw)
	ui.inventory_deposit_requested.connect(battle.request_inventory_deposit)
	ui.set_level_requested.connect(battle.request_set_level)
	ui.spend_stat_requested.connect(battle.request_spend_stat)
	battle.inventory_state_received.connect(ui.apply_inventory_state)
	battle.battle_inventory_opened.connect(ui.open_battle_inventory)


func _apply_window_fill() -> void:
	## Lobby/login must fill the native window. Never use keep/expand (pillarbox).
	var w := get_window()
	if w == null:
		return
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	w.content_scale_size = Vector2i(1280, 720)


func _set_battle_view_active(active: bool) -> void:
	## Battle Camera2D + world. Off = lobby/login (UI only).
	world.visible = active
	battle_camera.enabled = active
	if active:
		battle_camera.make_current()
	else:
		battle_camera.enabled = false


func _setup_battle_camera() -> void:
	battle_camera.enabled = false
	battle_camera.zoom = Vector2(ZOOM_MAX, ZOOM_MAX)
	battle_camera.position = Vector2.ZERO


func _on_continue(nick: String) -> void:
	battle.set_local_nick(nick)
	ui.set_room_players([nick])
	var ok: bool = await battle.connect_and_join_lobby(nick)
	if not ok:
		ui.show_login(false)
		var err := battle.last_connect_error
		ui.set_login_error(err if err != "" else "Сервер недоступен")
		return
	ui.show_lobby()
	ui.set_find_enabled(true)


func _on_find_match() -> void:
	ui.set_searching(true)
	var ok: bool = await battle.connect_and_find(ui.player_nick)
	if not ok:
		ui.set_searching(false)
		ui.show_login(false)
		var err := battle.last_connect_error
		ui.set_login_error(err if err != "" else "Сервер недоступен")


func _on_cancel_match() -> void:
	battle.cancel_find_match()
	## Optimistic UI; server confirms with queue_left.
	ui.set_searching(false)


func _on_battle_started() -> void:
	_set_battle_view_active(true)
	_fit_camera_to_map()
	ui.show_battle()
	ui.set_turn(battle.current_turn)
	ui.set_vital_caps(battle.max_hp, battle.max_ap)
	ui.set_shoot_cost(battle.shoot_cost)
	ui.set_mag_size(battle.local_mag_size)
	ui.set_ap(battle.local_ap)
	ui.set_hp(battle.local_hp)
	ui.set_posture(battle.local_posture)
	ui.set_ammo(battle.local_ammo_in_mag, battle.local_ammo_reserve)
	ui.set_reload_cost(battle.reload_cost)
	ui.set_medkit_count(
		battle.local_medkits, battle.medkit_heal_min, battle.medkit_heal_max, battle.medkit_cost
	)
	_refresh_quick_bar()
	ui.set_undo_enabled(false)
	_refresh_consumable_btns()


func _on_viewport_size_changed() -> void:
	if not world.visible or not battle.in_battle:
		return
	_clamp_focus()
	_apply_camera_from_focus()


func _fit_camera_to_map() -> void:
	battle_camera.zoom = Vector2(ZOOM_MAX, ZOOM_MAX)
	var center := grid.map_center()
	var player := grid.grid_to_world(battle.local_pos.x, battle.local_pos.y)
	_focus = player.lerp(center, 0.28)
	_focus.x += minf(grid.map_extents().x * 0.06, 80.0)
	_clamp_focus()
	_apply_camera_from_focus()


func _ui_to_viewport(ui_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * ui_pos


func _viewport_to_ui(vp_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * vp_pos


func _on_enemy_dossier_changed(payload: Dictionary) -> void:
	if payload.is_empty() or not payload.has("player"):
		ui.hide_enemy_dossier()
		return
	var pd: Variant = payload.get("player", {})
	if typeof(pd) != TYPE_DICTIONARY or (pd as Dictionary).is_empty():
		ui.hide_enemy_dossier()
		return
	var world_v: Variant = payload.get("world_pos", Vector2.ZERO)
	var world_pos: Vector2 = world_v if typeof(world_v) == TYPE_VECTOR2 else Vector2.ZERO
	var canvas_anchor := _viewport_to_ui(world_pos)
	var shooter_v: Variant = payload.get("shooter_world_pos", world_pos)
	var shooter_world: Vector2 = shooter_v if typeof(shooter_v) == TYPE_VECTOR2 else world_pos
	var canvas_shooter := _viewport_to_ui(shooter_world)
	ui.show_enemy_dossier(pd as Dictionary, canvas_anchor, canvas_shooter)


func _hud_band_top_y() -> float:
	var vp := get_viewport().get_visible_rect()
	if ui != null and ui.char_dock != null and ui.char_dock.visible:
		var top_ui := ui.char_dock.get_global_rect().position.y
		return _ui_to_viewport(Vector2(0.0, top_ui)).y
	return vp.position.y + vp.size.y * (1.0 - HUD_BOTTOM_FRAC)


func _hud_strip_top_y() -> float:
	return _hud_band_top_y() - HUD_PAD_PX


func _apply_camera_from_focus() -> void:
	## Shift focus up so map sits above CharDock.
	var hud_frac := 0.18
	var vp := get_viewport().get_visible_rect()
	if vp.size.y > 1.0:
		var reserved := (vp.position.y + vp.size.y) - _hud_strip_top_y()
		hud_frac = clampf(reserved / vp.size.y, 0.12, 0.22)
	var half_h := (vp.size.y * 0.5) / maxf(battle_camera.zoom.y, 0.01)
	battle_camera.position = _focus + Vector2(0.0, half_h * hud_frac)


func _process(delta: float) -> void:
	if not world.visible or not battle.in_battle:
		return
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		_focus += dir.normalized() * PAN_KEY_SPEED * delta / maxf(battle_camera.zoom.x, 0.01)
		_clamp_focus()
		_apply_camera_from_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not world.visible or not battle.in_battle:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_panning = true
				_pan_last_screen = mb.position
				get_viewport().set_input_as_handled()
			else:
				_panning = false
				get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.0 + ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / (1.0 + ZOOM_STEP))
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		var delta_screen := mm.position - _pan_last_screen
		_pan_last_screen = mm.position
		_focus -= delta_screen / maxf(battle_camera.zoom.x, 0.01)
		_clamp_focus()
		_apply_camera_from_focus()
		get_viewport().set_input_as_handled()


func _zoom(factor: float) -> void:
	var z := clampf(battle_camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	battle_camera.zoom = Vector2(z, z)
	_clamp_focus()
	_apply_camera_from_focus()


func _clamp_focus() -> void:
	## Keep map edges within void limits vs viewport / CharDock.
	var center := grid.map_center()
	var ext := grid.map_extents()
	var vp := get_viewport().get_visible_rect().size
	var half := Vector2(vp.x, vp.y) * 0.5 / maxf(battle_camera.zoom.x, 0.01)
	var min_x := center.x - ext.x + half.x - SIDE_VOID_MAX_PX
	var max_x := center.x + ext.x - half.x + SIDE_VOID_MAX_PX
	var min_y := center.y - ext.y + half.y - TOP_VOID_MAX_PX
	var max_y := center.y + ext.y - half.y + 40.0
	if min_x > max_x:
		_focus.x = center.x
	else:
		_focus.x = clampf(_focus.x, min_x, max_x)
	if min_y > max_y:
		_focus.y = center.y
	else:
		_focus.y = clampf(_focus.y, min_y, max_y)


func _refresh_quick_bar() -> void:
	var counts: Array = []
	for i in range(4):
		var id := ""
		if i < battle.local_quick.size():
			id = str(battle.local_quick[i])
		counts.append(battle.stack_qty(id) if id != "" else 0)
	ui.set_quick_slots(
		battle.local_quick,
		counts,
		battle.medkit_heal_min,
		battle.medkit_heal_max,
		battle.medkit_cost
	)


func _refresh_fire_mode_hint() -> void:
	var mode := battle.fire_mode
	var label := "Одиночный"
	if mode == "burst":
		label = "Очередь"
	elif mode == "duplet":
		label = "Дуплет"
	## Show on shoot cost / weapon area via status if available.
	if ui.has_method("set_fire_mode_hint"):
		ui.set_fire_mode_hint(label)
	elif ui.get("battle_status") != null:
		pass


func _on_quick_slot_pressed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= battle.local_quick.size():
		return
	var id := str(battle.local_quick[slot_index])
	if id == "":
		return
	if str(ZZLos.item_def(id).get("type", "")) == "ammo":
		battle.request_select_ammo(id)


func _ammo_fits_active_weapon(ammo_id: String) -> bool:
	if battle.local_active_weapon_idx < 0 or battle.local_active_weapon_idx >= battle.local_weapons.size():
		return false
	var w: Variant = battle.local_weapons[battle.local_active_weapon_idx]
	if typeof(w) != TYPE_DICTIONARY:
		return false
	return ZZLos.ammo_fits_weapon(ammo_id, str(w.get("id", "")))


func _refresh_consumable_btns() -> void:
	var can_plan := not battle.input_locked and battle.in_battle
	var ap_medkit := can_plan and battle.local_ap >= battle.medkit_cost
	var ap_reload := can_plan and battle.local_ap >= battle.reload_cost
	var ap_switch := can_plan and battle.local_ap >= battle.switch_weapon_cost
	var mag_needs := (
		battle.local_mag_size > 0
		and battle.local_ammo_in_mag < battle.local_mag_size
		and battle.local_ammo_reserve > 0
	)
	# Per quick slot: medkit needs AP+charges; empty/non-usable dimmed.
	for i in range(4):
		var id := ""
		if i < battle.local_quick.size():
			id = str(battle.local_quick[i])
		if id == "":
			ui.set_quick_affordance(i, false, false)
			continue
		var t := str(ZZLos.item_def(id).get("type", ""))
		if t == "medkit":
			var ok := ap_medkit and battle.local_medkits > 0
			ui.set_quick_affordance(i, ok, ok)
		elif t == "ammo":
			var can_sel := can_plan and _ammo_fits_active_weapon(id)
			ui.set_quick_affordance(i, can_sel, can_sel)
		else:
			ui.set_quick_affordance(i, false, true)
	ui.set_medkit_affordance(
		ap_medkit and battle.local_medkits > 0,
		ap_medkit and battle.local_medkits > 0
	)
	# Active card: bright while planning. Dim only when mag needs reload and no AP
	# (full mag / melee stay bright — gray would look like “no AP” / inactive).
	var melee := false
	if battle.local_active_weapon_idx >= 0 and battle.local_active_weapon_idx < battle.local_weapons.size():
		var aw: Variant = battle.local_weapons[battle.local_active_weapon_idx]
		if typeof(aw) == TYPE_DICTIONARY:
			melee = bool(aw.get("melee", false)) or ZZLos.is_melee_weapon(str(aw.get("id", "")))
	var look_active := can_plan if (melee or not mag_needs) else ap_reload
	ui.set_reload_affordance(ap_reload and mag_needs and not melee, look_active)
	ui.set_switch_weapon_affordance(ap_switch)


func _on_battle_ended(winner_id: String) -> void:
	ui.set_end_enabled(false)
	ui.set_medkit_enabled(false)
	ui.set_reload_enabled(false)
	ui.show_battle_result(winner_id != "" and winner_id == battle.your_id)


func _on_return_to_lobby() -> void:
	_set_battle_view_active(false)
	battle.clear_battle_visuals()
	ui.set_find_enabled(false)
	var ok: bool = await battle.connect_and_join_lobby(ui.player_nick)
	if not ok:
		ui.show_login(false)
		var err := battle.last_connect_error
		ui.set_login_error(err if err != "" else "Сервер недоступен")
		return
	ui.show_lobby()
	ui.set_find_enabled(true)
