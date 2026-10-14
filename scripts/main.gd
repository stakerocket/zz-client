extends Node

const ORTHO_SIZE_MIN := 22.0 # closest — default battle zoom (no auto-fit)
const ORTHO_SIZE_MAX := 40.0 # farthest — beyond this the map becomes a postage stamp
const ZOOM_STEP := 0.08
const PAN_KEY_SPEED := 18.0 # world units / sec
const CAM_PITCH_DEG := -55.0
## Yaw 0: map axes align with screen (rectangle). Non-zero yaw turns the field into a diamond.
const CAM_YAW_DEG := 0.0
const CAM_HEIGHT := 28.0
## Fallback if chat dock rect is not ready yet.
const CHAT_BOTTOM_FRAC := 0.28
## Extra gap above the real chat/players strip so the map does not sit under it.
const CHAT_PAD_PX := 20.0

## Battle-only ortho camera. Lobby/login must NEVER make this current.
@onready var battle_camera: Camera3D = $Camera3D
@onready var world: Node3D = $World
@onready var grid: ZZGridView = $World/Grid
@onready var units: Node3D = $World/Units
@onready var ui: ZZAppUI = $UI
@onready var ws: ZZWSClient = $WSClient
@onready var battle: ZZBattleController = $BattleController

var _panning := false
var _pan_last_screen := Vector2.ZERO
var _focus := Vector3.ZERO
## Battle-only 3D environment (charcoal void). Detached outside battle.
var _battle_world_env: WorldEnvironment
var _battle_environment: Environment


func _ready() -> void:
	_apply_window_fill()
	_ensure_environment()
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
	battle.room_players_changed.connect(ui.set_room_players)
	battle.chat_received.connect(func(nick: String, text: String, channel: String):
		ui.append_chat(nick, text, channel)
	)
	battle.input_lock_changed.connect(func(locked: bool):
		var can_plan := not locked and battle.in_battle
		ui.set_end_enabled(can_plan)
		ui.set_undo_enabled(can_plan and not battle.action_queue.is_empty())
		_refresh_medkit_btn()
	)
	battle.history_changed.connect(func(lines: Array):
		ui.set_history(lines)
		ui.set_undo_enabled(not battle.input_locked and battle.in_battle and not lines.is_empty())
		_refresh_medkit_btn()
	)
	battle.ap_changed.connect(func(_v):
		ui.set_posture(battle.local_posture)
		_refresh_medkit_btn()
	)
	battle.hp_changed.connect(func(_v):
		_refresh_medkit_btn()
	)
	battle.medkits_changed.connect(func(count: int):
		ui.set_medkit_count(count, battle.medkit_heal_min, battle.medkit_heal_max, battle.medkit_cost)
		_refresh_medkit_btn()
	)

	ui.continue_pressed.connect(_on_continue)
	ui.find_match_pressed.connect(_on_find_match)
	ui.end_turn_pressed.connect(battle.request_end_turn)
	ui.undo_pressed.connect(battle.request_undo)
	ui.posture_pressed.connect(battle.request_posture)
	ui.medkit_pressed.connect(battle.request_medkit)
	ui.chat_submitted.connect(func(text: String, channel: String):
		battle.send_chat(text, channel)
	)
	ui.return_to_lobby_pressed.connect(_on_return_to_lobby)


func _apply_window_fill() -> void:
	## Lobby/login must fill the native window. Never use keep/expand (pillarbox).
	var w := get_window()
	if w == null:
		return
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	w.content_scale_size = Vector2i(1280, 720)


func _ensure_environment() -> void:
	## Build battle Environment once; attach only while in battle so lobby/login stay untouched.
	if _battle_environment == null:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.03, 0.03, 0.035) # near-black void around hex map
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.62, 0.58, 0.52)
		env.ambient_light_energy = 0.48
		env.fog_enabled = true
		env.fog_light_color = Color(0.16, 0.16, 0.17)
		env.fog_density = 0.012
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		_battle_environment = env
	if has_node("WorldEnvironment"):
		_battle_world_env = $WorldEnvironment
	else:
		_battle_world_env = WorldEnvironment.new()
		_battle_world_env.name = "WorldEnvironment"
		add_child(_battle_world_env)
	# Inactive outside battle вЂ” no shared clear color with lobby/login.
	_battle_world_env.environment = null
	if has_node("DirectionalLight3D"):
		var sun: DirectionalLight3D = $DirectionalLight3D
		sun.light_color = Color(1.0, 0.92, 0.78)
		sun.light_energy = 1.05
		sun.shadow_opacity = 0.65


func _set_battle_view_active(active: bool) -> void:
	## Single switch: battle camera + void env + world. Off = pure 2D lobby/login.
	world.visible = active
	if _battle_world_env != null:
		_battle_world_env.environment = _battle_environment if active else null
	if active:
		battle_camera.make_current()
	else:
		battle_camera.current = false


func _setup_battle_camera() -> void:
	battle_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	battle_camera.size = ORTHO_SIZE_MIN
	battle_camera.near = 0.05
	battle_camera.far = 200.0
	battle_camera.rotation_degrees = Vector3(CAM_PITCH_DEG, CAM_YAW_DEG, 0.0)
	battle_camera.current = false


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
	_set_battle_view_active(true)
	_fit_camera_to_map()
	ui.show_battle()
	ui.set_turn(battle.current_turn)
	ui.set_ap(battle.local_ap)
	ui.set_hp(battle.local_hp)
	ui.set_posture(battle.local_posture)
	ui.set_history([])
	ui.set_undo_enabled(false)


func _on_viewport_size_changed() -> void:
	if not world.visible or not battle.in_battle:
		return
	_clamp_focus()
	_apply_camera_from_focus()


func _fit_camera_to_map() -> void:
	battle_camera.size = ORTHO_SIZE_MIN
	var center := grid.map_center()
	var player := grid.grid_to_world(battle.local_pos.x, battle.local_pos.y)
	_focus = player.lerp(center, 0.28)
	_focus.y = 0.0
	_focus += Vector3.RIGHT * minf(grid.map_extents().x * 0.06, 2.5)
	_clamp_focus()
	_apply_camera_from_focus()


func _chat_strip_top_y() -> float:
	## Screen Y of the top edge of chat/players (works windowed + fullscreen).
	var vp := get_viewport().get_visible_rect()
	var top := vp.position.y + vp.size.y
	var found := false
	if ui != null and ui.chat_dock != null and ui.chat_dock.visible:
		top = minf(top, ui.chat_dock.get_global_rect().position.y)
		found = true
	if ui != null and ui.bottom_bar != null and ui.bottom_bar.visible:
		top = minf(top, ui.bottom_bar.get_global_rect().position.y)
		found = true
	if not found:
		return vp.position.y + vp.size.y * (1.0 - CHAT_BOTTOM_FRAC)
	return top - CHAT_PAD_PX


func _chat_bottom_frac() -> float:
	var vp := get_viewport().get_visible_rect()
	if vp.size.y < 1.0:
		return CHAT_BOTTOM_FRAC
	var reserved := (vp.position.y + vp.size.y) - _chat_strip_top_y()
	return clampf(reserved / vp.size.y, 0.22, 0.50)


func _apply_camera_from_focus() -> void:
	# Fixed Fallout-like angle: place camera along -forward from focus.
	var basis := Basis.from_euler(Vector3(deg_to_rad(CAM_PITCH_DEG), deg_to_rad(CAM_YAW_DEG), 0.0))
	var forward := -basis.z.normalized()
	# Shift look-target toward screen-down so the playable map sits above the chat HUD.
	var screen_up := basis.y
	screen_up.y = 0.0
	var focus_view := _focus
	var chat_frac := _chat_bottom_frac()
	if screen_up.length_squared() > 0.0001:
		screen_up = screen_up.normalized()
		focus_view -= screen_up * (battle_camera.size * chat_frac)
	battle_camera.global_position = focus_view - forward * CAM_HEIGHT
	battle_camera.rotation_degrees = Vector3(CAM_PITCH_DEG, CAM_YAW_DEG, 0.0)


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
		_pan_focus(dir.normalized() * PAN_KEY_SPEED * delta * (battle_camera.size / ORTHO_SIZE_MIN))
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
			_zoom(1.0 / (1.0 + ZOOM_STEP))
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 + ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		var delta_screen := mm.position - _pan_last_screen
		_pan_last_screen = mm.position
		# Drag map with cursor: screen right → world along camera right, screen up → along camera "up" on XZ.
		var right := battle_camera.global_transform.basis.x
		var up := battle_camera.global_transform.basis.y
		right.y = 0.0
		up.y = 0.0
		if right.length_squared() > 0.0001:
			right = right.normalized()
		if up.length_squared() > 0.0001:
			up = up.normalized()
		var scale := battle_camera.size / maxf(get_viewport().get_visible_rect().size.y, 1.0)
		_focus -= right * delta_screen.x * scale
		_focus += up * delta_screen.y * scale
		_clamp_focus()
		_apply_camera_from_focus()
		get_viewport().set_input_as_handled()


func _pan_focus(delta_xz: Vector2) -> void:
	var right := battle_camera.global_transform.basis.x
	var forward := -battle_camera.global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	if right.length_squared() > 0.0001:
		right = right.normalized()
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	# WASD: A/D along right, W/S along forward on ground.
	_focus += right * delta_xz.x + forward * (-delta_xz.y)


func _zoom(factor: float) -> void:
	battle_camera.size = clampf(battle_camera.size * factor, ORTHO_SIZE_MIN, ORTHO_SIZE_MAX)
	_clamp_focus()
	_apply_camera_from_focus()


func _ground_at_screen(screen_pos: Vector2) -> Vector3:
	var from := battle_camera.project_ray_origin(screen_pos)
	var dir := battle_camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector3(from.x, 0.0, from.z)
	var t := (0.0 - from.y) / dir.y
	return from + dir * t


func _playable_screen_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect()
	var top := vp.position.y
	var bot := _chat_strip_top_y()
	return Rect2(vp.position.x, top, vp.size.x, maxf(1.0, bot - top))


func _view_x_span_at_mid() -> Vector2:
	## World X at left/right of playable area (mid height) — no oblique AABB inflate.
	var r := _playable_screen_rect()
	var mid_y := r.position.y + r.size.y * 0.5
	var a := _ground_at_screen(Vector2(r.position.x, mid_y))
	var b := _ground_at_screen(Vector2(r.position.x + r.size.x, mid_y))
	return Vector2(minf(a.x, b.x), maxf(a.x, b.x))


func _view_z_span_at_mid() -> Vector2:
	## World Z at top/bottom of playable area (mid width) — pan uses this, not corner AABB.
	var r := _playable_screen_rect()
	var mid_x := r.position.x + r.size.x * 0.5
	var a := _ground_at_screen(Vector2(mid_x, r.position.y))
	var b := _ground_at_screen(Vector2(mid_x, r.position.y + r.size.y))
	return Vector2(minf(a.z, b.z), maxf(a.z, b.z))


func _clamp_focus() -> void:
	## Flush map to playable edges. Vertical pan free when map taller than view.
	## Zoom is never changed here.
	_focus.y = 0.0
	var map_r := grid.map_xz_bounds()
	var map_min := map_r.position
	var map_max := map_r.position + map_r.size
	for _i in 6:
		_apply_camera_from_focus()
		var xs := _view_x_span_at_mid()
		var zs := _view_z_span_at_mid()
		var dx := 0.0
		var dz := 0.0
		var view_w := xs.y - xs.x
		var view_h := zs.y - zs.x
		if view_w >= map_r.size.x - 0.05:
			dx = (map_min.x + map_max.x) * 0.5 - (xs.x + xs.y) * 0.5
		else:
			if xs.y > map_max.x:
				dx -= xs.y - map_max.x
			if xs.x < map_min.x:
				dx += map_min.x - xs.x
		# Mid-line Z (not corner AABB) so tall maps can pan to the north edge.
		if view_h >= map_r.size.y - 0.05:
			dz = map_max.y - zs.y # pin south to chat line
		else:
			if zs.y > map_max.y:
				dz -= zs.y - map_max.y
			if zs.x < map_min.y:
				dz += map_min.y - zs.x
		_focus.x += dx
		_focus.z += dz
		if absf(dx) < 0.001 and absf(dz) < 0.001:
			break
	_focus.y = 0.0


func _refresh_medkit_btn() -> void:
	var can_plan := not battle.input_locked and battle.in_battle
	ui.set_medkit_enabled(
		can_plan
		and battle.local_ap >= battle.medkit_cost
		and battle.local_medkits > 0
	)


func _on_battle_ended(winner_id: String) -> void:
	ui.set_end_enabled(false)
	ui.set_medkit_enabled(false)
	ui.show_battle_result(winner_id != "" and winner_id == battle.your_id)


func _on_return_to_lobby() -> void:
	_set_battle_view_active(false)
	battle.clear_battle_visuals()
	ui.show_lobby()
	ui.set_find_enabled(false)
	await battle.connect_and_join_lobby(ui.player_nick)
	ui.set_find_enabled(true)
