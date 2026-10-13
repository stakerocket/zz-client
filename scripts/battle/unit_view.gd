extends Node2D
class_name ZZUnitView

const BAR_W := 40.0
const BAR_H := 5.0
const MOVE_DURATION := 0.28

var player_id: String = ""
var nick: String = ""
var hp: int = 100
var max_hp: int = 100
var color: Color = Color(0.3, 0.65, 0.95)
var is_dead: bool = false
var is_dying: bool = false
var is_moving: bool = false

var _label: Label
var _alive_color: Color = Color(0.3, 0.65, 0.95)
var _radius: float = 14.0
var _max_initialized: bool = false
var _move_tween: Tween
var posture: String = "stand"
## When set, draw crosshair + hit chance over this unit.
var _aim_chance: Variant = null # null | {blocked: bool, chance: float, can_shoot: bool}


func _ready() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-48, -44)
	_label.size = Vector2(96, 18)
	_label.add_theme_font_size_override("font_size", 12)
	add_child(_label)
	_refresh_label()
	queue_redraw()


func setup(id: String, player_nick: String, unit_color: Color) -> void:
	player_id = id
	nick = player_nick
	color = unit_color
	_alive_color = unit_color
	_refresh_label()
	queue_redraw()


func set_max_hp(value: int) -> void:
	if value > 0:
		max_hp = value
		_max_initialized = true
		queue_redraw()
		_refresh_label()


func set_hp(value: int, animate_death: bool = true) -> void:
	var prev := hp
	hp = value
	if not _max_initialized:
		max_hp = maxi(hp, 1)
		_max_initialized = true
	elif hp > max_hp:
		max_hp = hp
	_refresh_label()
	queue_redraw()
	if animate_death and prev > 0 and hp <= 0 and not is_dead:
		play_death()
	elif hp > 0 and is_dead:
		_reset_alive_visual()


func apply_hit(damage: int, hp_after: int) -> void:
	show_damage_number(damage)
	await flash_hit()
	set_hp(hp_after, true)
	if is_dying:
		await get_tree().create_timer(0.55).timeout


func apply_heal(heal: int, hp_after: int) -> void:
	if heal > 0:
		show_heal_number(heal)
	await flash_heal()
	set_hp(hp_after, false)


func show_heal_number(heal: int) -> void:
	_float_label("+%d" % heal, Color(0.3, 0.95, 0.4, 1.0))


func flash_heal() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0.55, 1.15, 0.65, 1.0), 0.08)
	tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.12)
	await tw.finished


func snap_to(world_pos: Vector2) -> void:
	if _move_tween != null and is_instance_valid(_move_tween):
		_move_tween.kill()
	_move_tween = null
	is_moving = false
	position = world_pos


func animate_move_to(world_pos: Vector2, with_sfx: bool = false) -> void:
	if is_dead or is_dying:
		return
	if _move_tween != null and is_instance_valid(_move_tween):
		_move_tween.kill()
	is_moving = true
	if with_sfx:
		Sfx.play_walk()
	var tw := create_tween()
	_move_tween = tw
	tw.tween_property(self, "position", world_pos, MOVE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if _move_tween == tw:
		position = world_pos
		is_moving = false
		_move_tween = null


func show_damage_number(damage: int) -> void:
	_float_label("-%d" % damage, Color(1.0, 0.35, 0.25, 1.0))


func show_miss() -> void:
	_float_label("мимо", Color(0.75, 0.78, 0.85, 1.0))


func _float_label(text: String, col: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 40
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 1.0))
	lbl.add_theme_constant_override("outline_size", 4)
	# World-space popup: ignore unit flash scale/modulate (same for damage and heal).
	lbl.top_level = true
	add_child(lbl)
	lbl.global_position = global_position + Vector2(-32, -58)
	lbl.size = Vector2(64, 24)
	var start_y := lbl.global_position.y
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position:y", start_y - 36.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)


func apply_miss() -> void:
	show_miss()
	await flash_miss()


func flash_miss() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0.7, 0.75, 0.85, 1.0), 0.08)
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.18)
	await tw.finished


func set_posture(value: String) -> void:
	match value:
		"sit":
			posture = "sit"
		"cover":
			posture = "cover"
		_:
			posture = "stand"
	if not is_dying and not is_dead:
		scale = Vector2.ONE
	_refresh_label()
	queue_redraw()


func set_aim_preview(info: Variant) -> void:
	_aim_chance = info
	queue_redraw()


func clear_aim_preview() -> void:
	if _aim_chance == null:
		return
	_aim_chance = null
	queue_redraw()


func flash_hit() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1.4, 0.55, 0.45, 1.0), 0.08)
	tw.tween_property(self, "scale", Vector2(1.18, 1.18), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.12)
	await tw.finished


func play_death() -> void:
	if is_dying or is_dead:
		return
	is_dying = true
	is_dead = true
	clear_aim_preview()
	var sink_y := position.y + 32.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.2, 0.2), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", sink_y, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(_paint_death_color, 0.0, 1.0, 0.4)
	tw.chain().tween_callback(_on_death_finished)


func _paint_death_color(t: float) -> void:
	color = _alive_color.lerp(Color(0.25, 0.25, 0.25, 1.0), t)
	queue_redraw()


func _on_death_finished() -> void:
	is_dying = false
	if _label:
		_label.visible = false
	queue_redraw()


func _reset_alive_visual() -> void:
	is_dead = false
	is_dying = false
	is_moving = false
	scale = Vector2.ONE
	modulate = Color(1, 1, 1, 1)
	color = _alive_color
	if _label:
		_label.visible = true
	queue_redraw()


func _refresh_label() -> void:
	if _label:
		var shown := hp if hp > 0 else 0
		_label.text = "%s (%d)" % [nick, shown]


func _hp_ratio() -> float:
	var pool := maxf(float(max_hp), 1.0)
	return clampf(float(hp) / pool, 0.0, 1.0)


func _hp_bar_color(ratio: float) -> Color:
	if ratio >= 0.5:
		var t := (1.0 - ratio) * 2.0
		return Color(0.22, 0.82, 0.28).lerp(Color(0.95, 0.82, 0.18), t)
	var t2 := (0.5 - ratio) * 2.0
	return Color(0.95, 0.82, 0.18).lerp(Color(0.9, 0.18, 0.14), t2)


func _draw() -> void:
	if modulate.a <= 0.01:
		return
	draw_circle(Vector2.ZERO, _radius, color)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, Color(0, 0, 0, 0.55), 2.0, true)
	_draw_posture_mark()
	_draw_hp_bar()
	_draw_aim_preview()


func _draw_posture_mark() -> void:
	var ink := Color(1, 1, 1, 0.92)
	var outline := Color(0.05, 0.08, 0.12, 0.85)
	match posture:
		"sit":
			_draw_arrow_h(Vector2.ZERO, _radius * 0.55, ink, outline)
		"cover":
			_draw_arrow_v(Vector2(0, _radius * 0.28), _radius * 0.42, false, ink, outline)
		_:
			_draw_arrow_v(Vector2.ZERO, _radius * 0.55, true, ink, outline)


func _draw_arrow_v(origin: Vector2, half_len: float, point_up: bool, ink: Color, outline: Color) -> void:
	var dir := -1.0 if point_up else 1.0
	var tip := origin + Vector2(0, dir * half_len)
	var tail := origin - Vector2(0, dir * half_len * 0.15)
	var head := half_len * 0.35
	_stroke_line(tail, tip, outline, 3.2)
	_stroke_line(tail, tip, ink, 2.0)
	var left := tip + Vector2(-head * 0.55, -dir * head)
	var right := tip + Vector2(head * 0.55, -dir * head)
	_stroke_line(tip, left, outline, 3.2)
	_stroke_line(tip, right, outline, 3.2)
	_stroke_line(tip, left, ink, 2.0)
	_stroke_line(tip, right, ink, 2.0)


func _draw_arrow_h(origin: Vector2, half_len: float, ink: Color, outline: Color) -> void:
	var tip := origin + Vector2(half_len, 0)
	var tail := origin - Vector2(half_len * 0.15, 0)
	var head := half_len * 0.35
	_stroke_line(tail, tip, outline, 3.2)
	_stroke_line(tail, tip, ink, 2.0)
	var up := tip + Vector2(-head, -head * 0.55)
	var down := tip + Vector2(-head, head * 0.55)
	_stroke_line(tip, up, outline, 3.2)
	_stroke_line(tip, down, outline, 3.2)
	_stroke_line(tip, up, ink, 2.0)
	_stroke_line(tip, down, ink, 2.0)


func _stroke_line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	draw_line(a, b, col, width, true)


func _draw_aim_preview() -> void:
	if _aim_chance == null or typeof(_aim_chance) != TYPE_DICTIONARY:
		return
	var info: Dictionary = _aim_chance
	var r := _radius + 8.0
	var col := Color(0.95, 0.25, 0.22, 0.95)
	if bool(info.get("blocked", false)):
		col = Color(0.55, 0.55, 0.58, 0.95)
	elif not bool(info.get("can_shoot", true)):
		col = Color(0.65, 0.55, 0.2, 0.95)
	# Crosshair
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, 2.0, true)
	draw_line(Vector2(0, -r - 4), Vector2(0, -r + 6), col, 2.0, true)
	draw_line(Vector2(0, r - 6), Vector2(0, r + 4), col, 2.0, true)
	draw_line(Vector2(-r - 4, 0), Vector2(-r + 6, 0), col, 2.0, true)
	draw_line(Vector2(r - 6, 0), Vector2(r + 4, 0), col, 2.0, true)
	# Chance / block label
	var text := "блок"
	if bool(info.get("can_shoot", true)) and not bool(info.get("blocked", false)):
		text = "%d%%" % int(round(float(info.get("chance", 0.0)) * 100.0))
	elif not bool(info.get("can_shoot", true)):
		text = "—"
	var font := ThemeDB.fallback_font
	var fs := 13
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var origin := Vector2(-sz.x * 0.5, r + 16.0)
	draw_rect(Rect2(origin + Vector2(-4, -sz.y + 2), sz + Vector2(8, 4)), Color(0.05, 0.08, 0.12, 0.8), true)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_hp_bar() -> void:
	var ratio := _hp_ratio()
	var origin := Vector2(-BAR_W * 0.5, -20.0)
	var bg := Rect2(origin, Vector2(BAR_W, BAR_H))
	draw_rect(bg, Color(0.08, 0.08, 0.08, 0.8), true)
	if ratio > 0.0:
		draw_rect(Rect2(origin, Vector2(BAR_W * ratio, BAR_H)), _hp_bar_color(ratio), true)
	draw_rect(bg, Color(0, 0, 0, 0.65), false, 1.0)
