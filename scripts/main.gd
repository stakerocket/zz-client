extends Node2D

## Left battle panel (~264px) + margin — keep map usable beside HUD.
const LEFT_UI_PAD_PX := 300.0
const ZOOM_MIN := 0.35
const ZOOM_MAX := 1.8
const ZOOM_STEP := 0.08
const PAN_KEY_SPEED := 520.0 # world units / sec at zoom 1

@onready var camera: Camera2D = $Camera2D
@onready var world: Node2D = $World
@onready var grid: ZZGridView = $World/Grid
@onready var units: Node2D = $World/Units
@onready var ui: ZZAppUI = $UI
@onready var ws: ZZWSClient = $WSClient
@onready var battle: ZZBattleController = $BattleController

var _panning := false
var _pan_last_screen := Vector2.ZERO


func _ready() -> void:
	battle.setup(ws, grid, units)
	_fit_camera_to_map()
	camera.make_current()
	world.visible = false

	battle.ap_changed.connect(ui.set_ap)
	battle.hp_changed.connect(ui.set_hp)
	battle.turn_changed.connect(ui.set_turn)
	battle.timer_changed.connect(ui.set_timer_seconds)
	battle.battle_started.connect(_on_battle_started)
	battle.battle_ended.connect(_on_battle_ended)
	battle.room_players_changed.connect(ui.set_room_players)
	battle.chat_received.connect(func(nick: String, text: String, channel: String):
		ui.append_chat(nick, text, channel)
	)
	battle.input_lock_changed.connect(func(locked: bool):
		var can_plan := not locked and battle.in_battle
		ui.set_end_enabled(can_plan)
		ui.set_undo_enabled(can_plan and not battle.action_queue.is_empty())
	)
	battle.history_changed.connect(func(lines: Array):
		ui.set_history(lines)
		ui.set_undo_enabled(not battle.input_locked and battle.in_battle and not lines.is_empty())
	)
	battle.ap_changed.connect(func(_v):
		ui.set_posture(battle.local_posture)
	)

	ui.continue_pressed.connect(_on_continue)
	ui.find_match_pressed.connect(_on_find_match)
	ui.end_turn_pressed.connect(battle.request_end_turn)
	ui.undo_pressed.connect(battle.request_undo)
	ui.posture_pressed.connect(battle.request_posture)
	ui.chat_submitted.connect(func(text: String, channel: String):
		battle.send_chat(text, channel)
	)
	ui.return_to_lobby_pressed.connect(_on_return_to_lobby)


func _on_continue(nick: String) -> void:
	battle.set_local_nick(nick)
	ui.set_room_players([nick])
	ui.set_find_enabled(false)
	await battle.connect_and_join_lobby(nick)
	ui.set_find_enabled(true)


func _on_find_match() -> void:
	ui.set_searching(true)
	var ok: bool = await battle.connect_and_find(ui.player_nick)
	if not ok:
		ui.set_searching(false)


func _on_battle_started() -> void:
	world.visible = true
	_fit_camera_to_map()
	ui.show_battle()
	ui.set_turn(battle.current_turn)
	ui.set_ap(battle.local_ap)
	ui.set_hp(battle.local_hp)
	ui.set_posture(battle.local_posture)
	ui.set_history([])
	ui.set_undo_enabled(false)


func _fit_camera_to_map() -> void:
	var map_size: Vector2 = grid.map_pixel_size()
	var view := get_viewport().get_visible_rect().size
	if view.x <= 1.0 or view.y <= 1.0 or map_size.x <= 1.0 or map_size.y <= 1.0:
		camera.zoom = Vector2(0.75, 0.75)
		camera.position = grid.map_center()
		return
	# Fit into the free area to the right of the battle HUD.
	var usable := Vector2(maxi(120.0, view.x - LEFT_UI_PAD_PX), view.y)
	var margin := 0.92
	var zx := usable.x * margin / map_size.x
	var zy := usable.y * margin / map_size.y
	var z: float = clampf(minf(zx, zy), ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	# Shift view so map sits in the free (right) portion of the screen.
	var center := grid.map_center()
	var shift_x := (LEFT_UI_PAD_PX * 0.5) / z
	camera.position = center + Vector2(shift_x, 0.0)
	_clamp_camera()


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
		camera.position += dir.normalized() * (PAN_KEY_SPEED / maxf(camera.zoom.x, 0.01)) * delta
		_clamp_camera()


func _unhandled_input(event: InputEvent) -> void:
	if not world.visible or not battle.in_battle:
		return
	# Middle mouse or right mouse drag to pan (left click stays for move/shoot).
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
			_zoom_at_screen(mb.position, 1.0 + ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at_screen(mb.position, 1.0 / (1.0 + ZOOM_STEP))
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		var delta_screen := mm.position - _pan_last_screen
		_pan_last_screen = mm.position
		camera.position -= delta_screen / camera.zoom
		_clamp_camera()
		get_viewport().set_input_as_handled()


func _zoom_at_screen(screen_pos: Vector2, factor: float) -> void:
	var old_zoom := camera.zoom.x
	var new_zoom := clampf(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var before := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	camera.zoom = Vector2(new_zoom, new_zoom)
	var after := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	camera.position += before - after
	_clamp_camera()


func _clamp_camera() -> void:
	var half := grid.map_pixel_size() * 0.5
	var center := grid.map_center()
	var pad := Vector2(80.0, 80.0)
	var min_p := center - half - pad
	var max_p := center + half + pad
	camera.position = camera.position.clamp(min_p, max_p)


func _on_battle_ended(winner_id: String) -> void:
	ui.set_end_enabled(false)
	ui.show_battle_result(winner_id != "" and winner_id == battle.your_id)


func _on_return_to_lobby() -> void:
	world.visible = false
	battle.clear_battle_visuals()
	ui.show_lobby()
	ui.set_find_enabled(false)
	await battle.connect_and_join_lobby(ui.player_nick)
	ui.set_find_enabled(true)
