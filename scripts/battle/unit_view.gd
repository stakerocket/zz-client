extends Node3D
class_name ZZUnitView

const MOVE_DURATION := 0.34
const CAPSULE_HEIGHT := 2.25
const CAPSULE_RADIUS := 0.38
const MODEL_SCENE := preload("res://assets/units/rider.glb")
const MODEL_SCALE := 2.5
const MODEL_YAW_OFFSET := 0.0
const ANIM_IDLE := "idle.rifle"
const ANIM_RUN := "run.rifle"
const ANIM_FIRE := "fire.rifle"
const ANIM_DEATH := "death.rifle"
const HP_BAR_W := 1.35
const HP_BAR_H := 0.16
const FONT_NICK := 70
const FONT_FLOAT := 96
const FONT_AIM := FONT_FLOAT # chance popup same size/style as damage

var player_id: String = ""
var nick: String = ""
var hp: int = 100
var max_hp: int = 100
var color: Color = Color(0.3, 0.65, 0.95)
var is_dead: bool = false
var is_dying: bool = false
var is_moving: bool = false

var _model_root: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _hips_bone: int = -1
var _hips_rest_xz: Vector2 = Vector2.ZERO
var _meshes: Array[MeshInstance3D] = []
var _anim_idle: String = ""
var _anim_run: String = ""
var _anim_fire: String = ""
var _anim_death_rifle: String = ""
var _anim_death_plain: String = ""
var _ui_root: Node3D
var _label: Label3D
var _aim_label: Label3D
var _hp_root: Node3D
var _hp_bg: MeshInstance3D
var _hp_fill: MeshInstance3D
var _hp_bg_mesh: BoxMesh
var _hp_fill_mesh: BoxMesh
var _hp_fill_mat: StandardMaterial3D
var _aim_root: Node3D
var _aim_ring: MeshInstance3D
var _mat: StandardMaterial3D
var _alive_color: Color = Color(0.3, 0.65, 0.95)
var _max_initialized: bool = false
var _move_tween: Tween
var posture: String = "stand"
var _aim_chance: Variant = null
var _feet_y: float = 0.0


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.roughness = 0.55

	_model_root = Node3D.new()
	_model_root.name = "ModelRoot"
	_model_root.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model_root)
	_spawn_model()

	# Screen-aligned UI (copies camera basis) — no Label3D billboard tilt.
	_ui_root = Node3D.new()
	_ui_root.name = "UnitUI"
	_ui_root.position = Vector3(0, CAPSULE_HEIGHT + 0.78, 0)
	add_child(_ui_root)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_label.font_size = FONT_NICK
	_label.outline_size = 14
	_label.position = Vector3(0, 0.28, 0)
	_label.render_priority = 8
	_label.no_depth_test = true
	_ui_root.add_child(_label)

	_build_hp_bar()
	_build_aim_reticle()

	_aim_label = Label3D.new()
	_aim_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_aim_label.font_size = FONT_AIM
	_aim_label.outline_size = 16
	_aim_label.position = Vector3(0, CAPSULE_HEIGHT + 1.7, 0)
	_aim_label.visible = false
	_aim_label.render_priority = 10
	_aim_label.no_depth_test = true
	add_child(_aim_label)

	_refresh_label()
	_refresh_hp_bar()
	_apply_posture_visual()
	_play_idle()


func _spawn_model() -> void:
	_model = MODEL_SCENE.instantiate() as Node3D
	_model_root.add_child(_model)
	_collect_meshes(_model)
	_anim = _find_anim_player(_model)
	_skeleton = _find_skeleton(_model)
	_cache_hips_bone()
	if _anim != null:
		_anim_idle = _resolve_anim(ANIM_IDLE, "idle")
		_anim_run = _resolve_anim(ANIM_RUN, "run")
		_anim_fire = _resolve_anim(ANIM_FIRE, "fire")
		_anim_death_rifle = _resolve_anim_named(ANIM_DEATH)
		_anim_death_plain = _resolve_anim_named("death")
		_prepare_locomotion_anims()
		# Advance manually so we can kill Hips root-motion after each pose.
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_anim.active = true
	if _meshes.is_empty():
		push_warning("ZZUnitView: rider.glb has no meshes, falling back to capsule")
		_spawn_capsule_fallback()


func _prepare_locomotion_anims() -> void:
	for lib_name in _anim.get_animation_library_list():
		var lib: AnimationLibrary = _anim.get_animation_library(lib_name)
		for anim_key in lib.get_animation_list():
			var src := lib.get_animation(anim_key)
			if src == null:
				continue
			var dup: Animation = src.duplicate(true)
			var key_l := String(anim_key).to_lower()
			# Keep death root motion (fall); strip locomotion drift on the rest.
			if not key_l.contains("death"):
				_strip_hips_root_motion_tracks(dup)
			if key_l.contains("death") or key_l.contains("fire"):
				dup.loop_mode = Animation.LOOP_NONE
			else:
				dup.loop_mode = Animation.LOOP_LINEAR
			lib.remove_animation(anim_key)
			lib.add_animation(anim_key, dup)


func _strip_hips_root_motion_tracks(anim: Animation) -> void:
	# Best-effort: freeze Hips translation keys (Godot track types vary by import).
	for ti in range(anim.get_track_count() - 1, -1, -1):
		var path := String(anim.track_get_path(ti))
		if not path.contains("Hips"):
			continue
		var t := anim.track_get_type(ti)
		if t == Animation.TYPE_POSITION_3D:
			var keys := anim.track_get_key_count(ti)
			if keys <= 0:
				continue
			var base: Vector3 = anim.track_get_key_value(ti, 0)
			for k in keys:
				var v: Vector3 = anim.track_get_key_value(ti, k)
				anim.track_set_key_value(ti, k, Vector3(base.x, v.y, base.z))
		elif t == Animation.TYPE_VALUE:
			# Some imports store Vector3 as value tracks on :position.
			if not path.contains("position"):
				continue
			var keys_v := anim.track_get_key_count(ti)
			if keys_v <= 0:
				continue
			var base_v: Variant = anim.track_get_key_value(ti, 0)
			if typeof(base_v) != TYPE_VECTOR3:
				continue
			var b: Vector3 = base_v
			for k in keys_v:
				var vv: Variant = anim.track_get_key_value(ti, k)
				if typeof(vv) != TYPE_VECTOR3:
					continue
				var v3: Vector3 = vv
				anim.track_set_key_value(ti, k, Vector3(b.x, v3.y, b.z))


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null


func _cache_hips_bone() -> void:
	_hips_bone = -1
	if _skeleton == null:
		return
	for i in _skeleton.get_bone_count():
		var bname := String(_skeleton.get_bone_name(i))
		if bname.contains("Hips"):
			_hips_bone = i
			var rest := _skeleton.get_bone_rest(i).origin
			_hips_rest_xz = Vector2(rest.x, rest.z)
			return


func _lock_hips_in_place() -> void:
	if _skeleton == null or _hips_bone < 0:
		return
	# Death clip may intentionally move the root; don't fight it.
	if is_dying or is_dead:
		return
	if _anim != null and String(_anim.current_animation).to_lower().contains("death"):
		return
	var p := _skeleton.get_bone_pose_position(_hips_bone)
	_skeleton.set_bone_pose_position(
		_hips_bone,
		Vector3(_hips_rest_xz.x, p.y, _hips_rest_xz.y)
	)


func _spawn_capsule_fallback() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var body := MeshInstance3D.new()
	body.mesh = capsule
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = color
	body_mat.roughness = 0.55
	body.material_override = body_mat
	body.position = Vector3(0, CAPSULE_HEIGHT * 0.5, 0)
	_model_root.add_child(body)
	_meshes.append(body)


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_anim_player(c)
		if found != null:
			return found
	return null


func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		_meshes.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_meshes(c)


func _resolve_anim_named(preferred: String) -> String:
	if _anim == null:
		return ""
	for n in _anim.get_animation_list():
		var s := String(n)
		if s == preferred or s.ends_with("/" + preferred):
			return s
	return ""


func _resolve_anim(preferred: String, hint: String) -> String:
	var exact := _resolve_anim_named(preferred)
	if exact != "":
		return exact
	if _anim == null:
		return ""
	for n in _anim.get_animation_list():
		if String(n).to_lower().contains(hint):
			return String(n)
	var names := _anim.get_animation_list()
	if names.size() > 0:
		return String(names[0])
	return ""


func _is_playing_anim(anim_name: String) -> bool:
	if _anim == null or anim_name == "":
		return false
	return _anim.is_playing() and String(_anim.current_animation) == anim_name


func _play_idle() -> void:
	if _anim == null or _anim_idle == "" or is_dead or is_dying:
		return
	if _is_playing_anim(_anim_idle):
		return
	_anim.play(_anim_idle)


func _play_run() -> void:
	if _anim == null or _anim_run == "" or is_dead or is_dying:
		return
	# Critical: StringName != String would restart the clip every hex.
	if _is_playing_anim(_anim_run):
		return
	_anim.play(_anim_run)


func _anim_length(anim_name: String) -> float:
	if _anim == null or anim_name == "":
		return 0.0
	var a := _anim.get_animation(anim_name)
	if a == null:
		return 0.0
	return maxf(a.length, 0.05)


func face_world(world_target: Vector3) -> void:
	_face_toward(world_target)


func facing_forward_xz() -> Vector3:
	var yaw := 0.0
	if _model_root != null:
		yaw = _model_root.rotation.y
	return Vector3(sin(yaw), 0.0, cos(yaw))


func play_fire() -> void:
	if is_dead or is_dying:
		return
	if _anim == null or _anim_fire == "":
		await get_tree().create_timer(0.15).timeout
		return
	_anim.play(_anim_fire)
	await get_tree().create_timer(_anim_length(_anim_fire)).timeout
	if not is_dead and not is_dying and not is_moving:
		_play_idle()


func _face_toward(world_target: Vector3) -> void:
	if _model_root == null:
		return
	var d := world_target - global_position
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return
	var yaw := atan2(d.x, d.z) + MODEL_YAW_OFFSET
	# Skip tiny yaw snaps between co-linear hexes (reduces visual hitch).
	if abs(wrapf(yaw - _model_root.rotation.y, -PI, PI)) < 0.02:
		return
	_model_root.rotation.y = yaw


func _set_overlay_alpha(alpha: float, tint: Color) -> void:
	_mat.albedo_color = Color(tint.r, tint.g, tint.b, clampf(alpha, 0.0, 1.0))
	for mi in _meshes:
		if mi == null or not is_instance_valid(mi):
			continue
		mi.material_overlay = _mat if alpha > 0.02 else null


func _clear_overlay() -> void:
	_set_overlay_alpha(0.0, color)


func _build_hp_bar() -> void:
	# Lives under _ui_root so it stays screen-aligned with the nick.
	_hp_root = Node3D.new()
	_hp_root.name = "HpBar"
	_hp_root.position = Vector3(0, 0.0, 0)
	_ui_root.add_child(_hp_root)

	_hp_bg_mesh = BoxMesh.new()
	_hp_bg_mesh.size = Vector3(HP_BAR_W, HP_BAR_H, 0.04)
	_hp_bg = MeshInstance3D.new()
	_hp_bg.mesh = _hp_bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.08, 0.08, 0.1, 0.92)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 6
	_hp_bg.material_override = bg_mat
	_hp_root.add_child(_hp_bg)

	_hp_fill_mesh = BoxMesh.new()
	_hp_fill_mesh.size = Vector3(HP_BAR_W, HP_BAR_H * 0.72, 0.05)
	_hp_fill = MeshInstance3D.new()
	_hp_fill.mesh = _hp_fill_mesh
	_hp_fill.position = Vector3(0, 0, 0.02)
	_hp_fill_mat = StandardMaterial3D.new()
	_hp_fill_mat.albedo_color = Color(0.22, 0.82, 0.28, 1.0)
	_hp_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fill_mat.no_depth_test = true
	_hp_fill_mat.render_priority = 7
	_hp_fill.material_override = _hp_fill_mat
	_hp_root.add_child(_hp_fill)


func _make_aim_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Draw on top of the body so the reticle is never occluded.
	m.no_depth_test = true
	m.render_priority = 12
	return m


func _build_aim_reticle() -> void:
	_aim_root = Node3D.new()
	_aim_root.name = "AimReticle"
	_aim_root.visible = false
	_aim_root.position = Vector3(0, CAPSULE_HEIGHT * 0.55, 0)
	add_child(_aim_root)

	_aim_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.72
	torus.rings = 12
	torus.ring_segments = 28
	_aim_ring.mesh = torus
	# Torus lies in XZ by default; rotate so ring faces camera after look_at.
	_aim_ring.rotation_degrees = Vector3(90, 0, 0)
	_aim_ring.material_override = _make_aim_mat(Color(0.95, 0.3, 0.25, 0.95))
	_aim_root.add_child(_aim_ring)

	# Crosshair ticks (in aim_root local XY after look_at).
	for i in 4:
		var tick := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 0.36, 0.08)
		tick.mesh = box
		tick.material_override = _make_aim_mat(Color(0.95, 0.3, 0.25, 0.95))
		match i:
			0:
				tick.position = Vector3(0, 0.88, 0)
			1:
				tick.position = Vector3(0, -0.88, 0)
			2:
				tick.position = Vector3(0.88, 0, 0)
				tick.rotation_degrees = Vector3(0, 0, 90)
			3:
				tick.position = Vector3(-0.88, 0, 0)
				tick.rotation_degrees = Vector3(0, 0, 90)
		_aim_root.add_child(tick)


func _face_screen(node: Node3D, cam: Camera3D) -> void:
	# Match camera orientation → UI stays level on screen (like reference plates).
	node.global_basis = cam.global_basis


func _process(delta: float) -> void:
	if _anim != null and _anim.active:
		_anim.advance(delta)
		_lock_hips_in_place()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _ui_root != null and _ui_root.visible:
		_face_screen(_ui_root, cam)
	if _aim_label != null and _aim_label.visible:
		_face_screen(_aim_label, cam)
	if _aim_root != null and _aim_root.visible:
		_face_screen(_aim_root, cam)
		var to_cam := -cam.global_transform.basis.z
		to_cam.y = 0.0
		if to_cam.length_squared() > 0.0001:
			to_cam = to_cam.normalized()
			_aim_root.global_position = global_position + Vector3(0, CAPSULE_HEIGHT * 0.55, 0) + to_cam * 0.55


func setup(id: String, player_nick: String, unit_color: Color) -> void:
	player_id = id
	nick = player_nick
	color = unit_color
	_alive_color = unit_color
	_refresh_label()
	_refresh_hp_bar()


func set_max_hp(value: int) -> void:
	if value > 0:
		max_hp = value
		_max_initialized = true
		_refresh_label()
		_refresh_hp_bar()


func set_hp(value: int, animate_death: bool = true, front_blocked: bool = false) -> void:
	var prev := hp
	hp = value
	if not _max_initialized:
		max_hp = maxi(hp, 1)
		_max_initialized = true
	elif hp > max_hp:
		max_hp = hp
	_refresh_label()
	_refresh_hp_bar()
	if animate_death and prev > 0 and hp <= 0 and not is_dead:
		play_death(front_blocked)
	elif hp > 0 and is_dead:
		_reset_alive_visual()


func apply_hit(damage: int, hp_after: int, front_blocked: bool = false) -> void:
	show_damage_number(damage)
	await flash_hit()
	var will_die := hp > 0 and hp_after <= 0 and not is_dead
	set_hp(hp_after, false)
	if will_die:
		await play_death(front_blocked)


func apply_heal(heal: int, hp_after: int) -> void:
	if heal > 0:
		show_heal_number(heal)
	await flash_heal()
	set_hp(hp_after, false)


func show_heal_number(heal: int) -> void:
	_float_label("+%d" % heal, Color(0.3, 0.95, 0.4, 1.0))


func flash_heal() -> void:
	var tint := Color(0.55, 1.0, 0.65, 1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3(1.12, 1.12, 1.12), 0.08)
	tw.tween_method(func(a: float) -> void: _set_overlay_alpha(a, tint), 0.0, 0.7, 0.08)
	tw.chain().set_parallel(true)
	tw.tween_property(self, "scale", Vector3.ONE, 0.12)
	tw.tween_method(func(a: float) -> void: _set_overlay_alpha(a, tint), 0.7, 0.0, 0.12)
	await tw.finished
	_clear_overlay()


func snap_to(world_pos: Vector3) -> void:
	if _move_tween != null and is_instance_valid(_move_tween):
		_move_tween.kill()
	_move_tween = null
	is_moving = false
	_feet_y = world_pos.y
	position = Vector3(world_pos.x, _feet_y, world_pos.z)
	_play_idle()


func animate_move_to(world_pos: Vector3, with_sfx: bool = false, stop_at_end: bool = true) -> void:
	if is_dead or is_dying:
		return
	if _move_tween != null and is_instance_valid(_move_tween):
		_move_tween.kill()
	is_moving = true
	if with_sfx:
		Sfx.play_walk()
	_feet_y = world_pos.y
	var target := Vector3(world_pos.x, _feet_y, world_pos.z)
	_face_toward(target)
	_play_run()
	var tw := create_tween()
	_move_tween = tw
	# Mid-path: linear (no ease restart each hex). Last step: soft ease-out into idle.
	if stop_at_end:
		tw.tween_property(self, "position", target, MOVE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(self, "position", target, MOVE_DURATION).set_trans(Tween.TRANS_LINEAR)
	await tw.finished
	if _move_tween == tw:
		position = target
		_move_tween = null
		if stop_at_end:
			is_moving = false
			_play_idle()


func show_damage_number(damage: int) -> void:
	_float_label("-%d" % damage, Color(1.0, 0.35, 0.25, 1.0))


func show_miss() -> void:
	_float_label("мимо", Color(0.75, 0.78, 0.85, 1.0))


func _float_label(text: String, col: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = FONT_FLOAT
	lbl.outline_size = 18
	lbl.modulate = col
	lbl.position = Vector3(0, CAPSULE_HEIGHT + 0.95, 0)
	lbl.render_priority = 16
	lbl.no_depth_test = true
	add_child(lbl)
	var start_y := lbl.position.y
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", start_y + 0.9, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)


func apply_miss() -> void:
	show_miss()
	await flash_miss()


func flash_miss() -> void:
	var tint := Color(0.7, 0.75, 0.85, 1.0)
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void: _set_overlay_alpha(a, tint), 0.0, 0.55, 0.08)
	tw.tween_method(func(a: float) -> void: _set_overlay_alpha(a, tint), 0.55, 0.0, 0.18)
	await tw.finished
	_clear_overlay()


func set_posture(value: String) -> void:
	match value:
		"sit":
			posture = "sit"
		"cover":
			posture = "cover"
		_:
			posture = "stand"
	if not is_dying and not is_dead:
		_apply_posture_visual()
	_refresh_label()


func set_aim_preview(info: Variant) -> void:
	_aim_chance = info
	_refresh_aim_visual()


func clear_aim_preview() -> void:
	if _aim_chance == null:
		return
	_aim_chance = null
	_refresh_aim_visual()


func flash_hit() -> void:
	var tint := Color(1.0, 0.45, 0.35, 1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3(1.15, 1.15, 1.15), 0.08)
	tw.tween_method(func(a: float) -> void: _set_overlay_alpha(a, tint), 0.0, 0.75, 0.08)
	tw.chain().set_parallel(true)
	tw.tween_property(self, "scale", Vector3.ONE, 0.12)
	tw.tween_method(func(a: float) -> void: _set_overlay_alpha(a, tint), 0.75, 0.0, 0.12)
	await tw.finished
	_clear_overlay()


func play_death(front_blocked: bool = false) -> void:
	if is_dying or is_dead:
		return
	is_dying = true
	is_dead = true
	clear_aim_preview()
	if _move_tween != null and is_instance_valid(_move_tween):
		_move_tween.kill()
	_move_tween = null
	is_moving = false
	# Clear front → fall with rifle; obstacle ahead → compact death.
	var clip := ""
	if front_blocked:
		clip = _anim_death_plain if _anim_death_plain != "" else _anim_death_rifle
	else:
		clip = _anim_death_rifle if _anim_death_rifle != "" else _anim_death_plain
	if _anim != null and clip != "":
		_anim.play(clip)
		await get_tree().create_timer(_anim_length(clip)).timeout
	else:
		var tint := Color(0.25, 0.25, 0.25, 1.0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "scale", Vector3(0.2, 0.2, 0.2), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_method(func(a: float) -> void: _set_overlay_alpha(a, tint), 0.0, 0.85, 0.4)
		await tw.finished
	_on_death_finished()


func _on_death_finished() -> void:
	is_dying = false
	# Keep corpse mesh in final death pose; only clear HUD.
	if _ui_root:
		_ui_root.visible = false
	if _label:
		_label.visible = false
	if _hp_root:
		_hp_root.visible = false
	elif _hp_bg:
		_hp_bg.visible = false
	if _hp_fill:
		_hp_fill.visible = false
	if _aim_root:
		_aim_root.visible = false
	_clear_overlay()


func _reset_alive_visual() -> void:
	is_dead = false
	is_dying = false
	is_moving = false
	scale = Vector3.ONE
	position.y = _feet_y
	color = _alive_color
	_clear_overlay()
	if _ui_root:
		_ui_root.visible = true
	if _label:
		_label.visible = true
	if _hp_root:
		_hp_root.visible = true
	if _hp_bg:
		_hp_bg.visible = true
	if _hp_fill:
		_hp_fill.visible = true
	if _model_root:
		_model_root.visible = true
	_apply_posture_visual()
	_refresh_hp_bar()
	_play_idle()


func _refresh_label() -> void:
	if _label:
		_label.text = nick


func _hp_ratio() -> float:
	var pool := maxf(float(max_hp), 1.0)
	return clampf(float(maxi(hp, 0)) / pool, 0.0, 1.0)


func _hp_bar_color(ratio: float) -> Color:
	if ratio >= 0.5:
		var t := (1.0 - ratio) * 2.0
		return Color(0.22, 0.82, 0.28).lerp(Color(0.95, 0.82, 0.18), t)
	var t2 := (0.5 - ratio) * 2.0
	return Color(0.95, 0.82, 0.18).lerp(Color(0.9, 0.18, 0.14), t2)


func _refresh_hp_bar() -> void:
	if _hp_fill == null or _hp_fill_mesh == null or _hp_fill_mat == null:
		return
	var ratio := _hp_ratio()
	var fill_w := HP_BAR_W * ratio
	# Resize mesh (not scale) so length matches HP exactly; grow from left edge.
	_hp_fill_mesh.size = Vector3(maxf(fill_w, 0.001), HP_BAR_H * 0.72, 0.05)
	_hp_fill.position = Vector3(-HP_BAR_W * 0.5 + fill_w * 0.5, 0.0, 0.02)
	_hp_fill.visible = ratio > 0.001
	_hp_fill_mat.albedo_color = _hp_bar_color(ratio)


func _refresh_aim_visual() -> void:
	if _aim_label == null or _aim_root == null:
		return
	if _aim_chance == null or typeof(_aim_chance) != TYPE_DICTIONARY:
		_aim_label.visible = false
		_aim_root.visible = false
		return
	var info: Dictionary = _aim_chance
	var text := "блок"
	var col := Color(0.95, 0.25, 0.22, 0.95)
	if bool(info.get("blocked", false)):
		col = Color(0.7, 0.7, 0.72, 0.95)
		text = "блок"
	elif not bool(info.get("can_shoot", true)):
		col = Color(0.85, 0.7, 0.25, 0.95)
		text = "—"
	else:
		text = "%d%%" % int(round(float(info.get("chance", 0.0)) * 100.0))
		col = Color(0.95, 0.35, 0.3, 0.95)
	_aim_label.text = text
	_aim_label.modulate = col
	_aim_label.visible = true
	_aim_root.visible = true
	# Recolor reticle
	for c in _aim_root.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			var m: StandardMaterial3D = mi.material_override
			if m:
				m.albedo_color = Color(col.r, col.g, col.b, 0.95)
				m.no_depth_test = true
				m.render_priority = 12


func _apply_posture_visual() -> void:
	if _model_root == null:
		return
	var s := MODEL_SCALE
	match posture:
		"sit":
			_model_root.scale = Vector3(s, s * 0.72, s)
		"cover":
			_model_root.scale = Vector3(s * 1.05, s * 0.82, s * 0.95)
		_:
			_model_root.scale = Vector3.ONE * s
