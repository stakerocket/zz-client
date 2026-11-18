extends Node2D
class_name ZZUnitView

const MOVE_DURATION := 0.34
const MOVE_DURATION_RUN := MOVE_DURATION * 0.5
## Kept for callers (muzzle / pick height in px).
const CAPSULE_HEIGHT := 48.0
const MODEL_SCALE := 1.0
const SPRITE_SCALE := 1.15
const STALKER_FRAME_DIR := "res://assets/units/"

var player_id: String = ""
var nick: String = ""
var level: int = 0
var hp: int = 100
var max_hp: int = 100
var color: Color = Color(0.3, 0.65, 0.95)
var is_dead: bool = false
var is_dying: bool = false
var is_moving: bool = false
var posture: String = "stand"
var _run_foot_hex: int = 0
var _aim_chance: Variant = null
var _armed := true
var _anim_frame := 0
var _anim_timer := 0.0
var _move_tween: Tween
var _max_initialized := false
var _use_stalker_atlas := true

var _sprite: Sprite2D
var _nick_label: Label
var _hp_bg: ColorRect
var _hp_fill: ColorRect
var _aim_label: Label
var _ui: Node2D
var _tex_cache: Dictionary = {}
var _stalker_frames: Dictionary = {} ## pose/frame -> Texture2D


func _ready() -> void:
	_load_stalker_frames()
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.position = Vector2(0, -28)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	add_child(_sprite)

	_ui = Node2D.new()
	_ui.z_index = 10
	add_child(_ui)

	_nick_label = Label.new()
	_nick_label.add_theme_font_size_override("font_size", 11)
	_nick_label.add_theme_color_override("font_color", Color(0.92, 0.93, 0.90))
	_nick_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_nick_label.add_theme_constant_override("outline_size", 3)
	_nick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nick_label.position = Vector2(-40, -70)
	_nick_label.size = Vector2(80, 16)
	_ui.add_child(_nick_label)

	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0.08, 0.08, 0.08, 0.75)
	_hp_bg.size = Vector2(36, 5)
	_hp_bg.position = Vector2(-18, -54)
	_ui.add_child(_hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.40, 0.52, 0.36)
	_hp_fill.size = Vector2(36, 5)
	_hp_fill.position = Vector2(-18, -54)
	_ui.add_child(_hp_fill)

	_aim_label = Label.new()
	_aim_label.add_theme_font_size_override("font_size", 14)
	_aim_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_aim_label.add_theme_constant_override("outline_size", 4)
	_aim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_label.position = Vector2(-30, -88)
	_aim_label.size = Vector2(60, 20)
	_aim_label.visible = false
	_ui.add_child(_aim_label)

	_refresh_label()
	_refresh_hp_bar()
	_refresh_sprite()


func _process(delta: float) -> void:
	if is_dead or is_dying:
		return
	var animating := posture == "run" or posture == "walk" or is_moving
	if not animating and _use_stalker_atlas and posture == "stand":
		## Subtle idle breathe between idle_0 / idle_1.
		_anim_timer += delta
		if _anim_timer >= 0.45:
			_anim_timer = 0.0
			_anim_frame = (_anim_frame + 1) % 2
			_refresh_sprite()
		return
	if animating:
		_anim_timer += delta
		if _anim_timer >= 0.12:
			_anim_timer = 0.0
			_anim_frame = (_anim_frame + 1) % 4
			_refresh_sprite()


func setup(id: String, player_nick: String, unit_color: Color) -> void:
	player_id = id
	nick = player_nick
	color = unit_color
	_refresh_label()
	_refresh_hp_bar()
	_refresh_sprite()


func set_max_hp(value: int) -> void:
	if value > 0:
		max_hp = value
		_max_initialized = true
		_refresh_label()
		_refresh_hp_bar()


func set_hp(value: int, _animate: bool = true, _front_blocked: bool = false) -> void:
	hp = value
	if not _max_initialized and value > max_hp:
		max_hp = value
	_refresh_hp_bar()
	_refresh_label()
	if hp <= 0 and not is_dead and not is_dying:
		await play_death(_front_blocked)


func apply_hit(damage: int, hp_after: int, front_blocked: bool = false, crit: bool = false) -> void:
	await flash_hit()
	show_damage_number(damage, crit)
	await set_hp(hp_after, true, front_blocked)


func apply_hits(hits: Array, hp_after: int, front_blocked: bool = false) -> void:
	await flash_hit()
	var i := 0
	for h in hits:
		if typeof(h) != TYPE_DICTIONARY:
			continue
		var hd := int(h.get("damage", 0))
		var hc := bool(h.get("crit", false))
		if hd > 0:
			show_damage_number(hd, hc, 0.0, float(i) * 10.0)
			i += 1
	await set_hp(hp_after, true, front_blocked)


func apply_miss() -> void:
	show_miss()
	await get_tree().create_timer(0.15).timeout


func facing_forward_xz() -> Vector2:
	return Vector2(-1.0 if _sprite != null and _sprite.flip_h else 1.0, 0.0)


func set_level(value: int) -> void:
	level = maxi(0, value)
	_refresh_label()


func set_posture(value: String) -> void:
	match value:
		"sit":
			posture = "sit"
		"cover":
			posture = "cover"
		"run":
			posture = "run"
		_:
			posture = "stand"
	if not is_dying and not is_dead:
		_refresh_sprite()


func set_armed(armed: bool) -> void:
	_armed = armed
	_refresh_sprite()


func snap_to(world_pos: Vector2) -> void:
	position = world_pos


func animate_move_to(world_pos: Vector2, play_sfx: bool = true, stop_at_end: bool = true) -> void:
	if _move_tween != null and is_instance_valid(_move_tween):
		_move_tween.kill()
	is_moving = true
	if play_sfx:
		if posture == "run":
			if _run_foot_hex % 2 == 0:
				Sfx.play_walk()
			_run_foot_hex += 1
		else:
			_run_foot_hex = 0
			Sfx.play_walk()
	var dur := MOVE_DURATION_RUN if posture == "run" else MOVE_DURATION
	face_world(world_pos)
	_move_tween = create_tween()
	if stop_at_end:
		_move_tween.tween_property(self, "position", world_pos, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_move_tween.tween_property(self, "position", world_pos, dur).set_trans(Tween.TRANS_LINEAR)
	await _move_tween.finished
	is_moving = false
	if stop_at_end:
		_run_foot_hex = 0
		_refresh_sprite()


func face_world(world_target: Vector2) -> void:
	if world_target.x < position.x - 1.0:
		_sprite.flip_h = true
	elif world_target.x > position.x + 1.0:
		_sprite.flip_h = false


func play_fire() -> void:
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", Color(1.4, 1.3, 1.0), 0.05)
	tw.tween_property(_sprite, "modulate", Color.WHITE, 0.08)


func flash_hit() -> void:
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", Color(1.0, 0.4, 0.35), 0.06)
	tw.tween_property(_sprite, "modulate", Color.WHITE, 0.12)
	await tw.finished


func play_death(_front_blocked: bool = false) -> void:
	if is_dying or is_dead:
		return
	is_dying = true
	is_dead = true
	clear_aim_preview()
	if _move_tween != null and is_instance_valid(_move_tween):
		_move_tween.kill()
	is_moving = false
	Sfx.play_death()
	posture = "death"
	_refresh_sprite()
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate:a", 0.55, 0.4)
	await tw.finished
	_ui.visible = false


func show_damage_number(damage: int, crit: bool = false, _x_off: float = 0.0, _y_off: float = 0.0) -> void:
	var text := ("крит -%d" % damage) if crit else ("-%d" % damage)
	var col := Color(1.0, 0.85, 0.2) if crit else Color(1.0, 0.35, 0.25)
	_float_text(text, col)


func show_miss() -> void:
	_float_text("мимо", Color(0.75, 0.78, 0.85))


func show_heal(heal: int) -> void:
	_float_text("+%d" % heal, Color(0.3, 0.95, 0.4))


func set_aim_preview(info: Variant) -> void:
	_aim_chance = info
	_refresh_aim_visual()


func clear_aim_preview() -> void:
	if _aim_chance == null:
		return
	_aim_chance = null
	_refresh_aim_visual()


func _float_text(text: String, col: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = Vector2(-24, -78)
	add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 28.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7)
	await tw.finished
	if is_instance_valid(lbl):
		lbl.queue_free()


func _refresh_label() -> void:
	if _nick_label == null:
		return
	if level > 0:
		_nick_label.text = "%s [%d]" % [nick, level]
	else:
		_nick_label.text = nick


func _refresh_hp_bar() -> void:
	if _hp_fill == null:
		return
	var ratio := clampf(float(maxi(hp, 0)) / float(maxi(max_hp, 1)), 0.0, 1.0)
	_hp_fill.size.x = 36.0 * ratio
	if ratio > 0.55:
		_hp_fill.color = Color(0.40, 0.52, 0.36)
	elif ratio > 0.25:
		_hp_fill.color = Color(0.72, 0.62, 0.34)
	else:
		_hp_fill.color = Color(0.75, 0.28, 0.22)
	_ui.visible = not is_dead


func _refresh_aim_visual() -> void:
	if _aim_label == null:
		return
	if _aim_chance == null or typeof(_aim_chance) != TYPE_DICTIONARY:
		_aim_label.visible = false
		return
	var info: Dictionary = _aim_chance
	var blocked := bool(info.get("blocked", false))
	var can_shoot := bool(info.get("can_shoot", false))
	var melee_ok := bool(info.get("melee_reach", true))
	if blocked or not melee_ok:
		_aim_label.text = "блок"
		_aim_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
	else:
		_aim_label.text = "%d%%" % int(round(float(info.get("chance", 0.0)) * 100.0))
		_aim_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.4) if can_shoot else Color(0.7, 0.7, 0.72))
	_aim_label.visible = true


func _pose_key() -> String:
	if is_dead or is_dying or posture == "death":
		return "death"
	if is_moving:
		return "run" if posture == "run" else "walk"
	match posture:
		"sit":
			return "sit"
		"cover":
			return "cover"
		"run":
			return "run"
		_:
			return "idle"


func _load_stalker_frames() -> void:
	_stalker_frames.clear()
	var map := {
		"idle_0": "stalker_idle_0_64.png",
		"idle_1": "stalker_idle_1_64.png",
		"walk_0": "stalker_walk_0_64.png",
		"walk_1": "stalker_walk_1_64.png",
		"walk_2": "stalker_walk_2_64.png",
		"run_0": "stalker_walk_0_64.png",
		"run_1": "stalker_walk_1_64.png",
		"run_2": "stalker_walk_2_64.png",
		"sit_0": "stalker_sit_64.png",
		"cover_0": "stalker_cover_64.png",
		"death_0": "stalker_death_64.png",
	}
	var ok := 0
	for k in map.keys():
		var path: String = STALKER_FRAME_DIR + str(map[k])
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			if tex != null:
				_stalker_frames[k] = tex
				ok += 1
	_use_stalker_atlas = ok >= 5


func _stalker_tex(pose: String, frame: int) -> Texture2D:
	var f := frame
	match pose:
		"idle":
			f = frame % 2
		"walk", "run":
			f = frame % 3
		_:
			f = 0
	var key := "%s_%d" % [pose, f]
	if _stalker_frames.has(key):
		return _stalker_frames[key]
	## fallback aliases
	if pose == "run" and _stalker_frames.has("walk_%d" % f):
		return _stalker_frames["walk_%d" % f]
	if _stalker_frames.has("idle_0"):
		return _stalker_frames["idle_0"]
	return null


func _refresh_sprite() -> void:
	if _sprite == null:
		return
	var pose := _pose_key()
	var frame := _anim_frame if (pose == "run" or pose == "walk" or pose == "idle") else 0
	if _use_stalker_atlas:
		var tex := _stalker_tex(pose, frame)
		if tex != null:
			_sprite.texture = tex
			if not is_dying and not is_dead:
				_sprite.modulate = Color.WHITE
			return
	var key := "%s_%s_%d_%d" % [pose, color.to_html(false), int(_armed), frame]
	if not _tex_cache.has(key):
		_tex_cache[key] = ZZPixelArt.unit_frame(pose, color, _armed, frame)
	_sprite.texture = _tex_cache[key]
