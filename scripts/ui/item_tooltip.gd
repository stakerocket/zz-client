extends RefCounted
class_name ZZItemTooltip

## Shared inventory-style item card (used by bag + battle HUD).

const COL_LABEL := Color(0.78, 0.80, 0.84)
const COL_TITLE := Color(0.90, 0.91, 0.93)
const COL_MUTED := Color(0.58, 0.60, 0.64)
const COL_WARN := Color(0.95, 0.42, 0.38)
const COL_TIP_BG := Color(0.09, 0.095, 0.11, 1.0)
const COL_TIP_BORDER := Color(0.35, 0.38, 0.42, 1.0)

## Live character context for unmet req highlighting (set from inventory / lobby profile).
static var _player_level: int = 1
static var _player_stats: Dictionary = {}


static func set_player_context(level: int, stats: Dictionary) -> void:
	_player_level = maxi(1, level)
	_player_stats = stats.duplicate() if not stats.is_empty() else {}


## Inventory-style card without a catalog item (postures, etc.).
static func build_simple(title: String, subtitle: String = "", rows: Array = []) -> Control:
	var panel := _new_panel()
	var box := panel.get_child(0) as VBoxContainer
	_add_title_block(box, title, subtitle if subtitle != "" else " ")
	for row in rows:
		if typeof(row) != TYPE_ARRAY or row.size() < 2:
			continue
		box.add_child(_tip_line(str(row[0]), str(row[1])))
	return panel


## extra_rows: Array of [key, value] pairs appended after catalog stats.
static func build(item_id: String, qty: int = 1, extra_rows: Array = []) -> Control:
	var def := ZZLos.item_def(item_id)
	var panel := _new_panel()
	var box := panel.get_child(0) as VBoxContainer
	_add_title_block(box, str(def.get("name", item_id)), _type_label(str(def.get("type", ""))))

	var unit_w := float(def.get("weight", 0.0))
	var total_w := unit_w * float(maxi(qty, 1))
	box.add_child(_tip_line("Кол-во", "×%d" % maxi(qty, 1)))
	box.add_child(_tip_line("Вес", "%s ед." % fmt_num(total_w)))

	var params: Variant = def.get("params", {})
	if typeof(params) == TYPE_DICTIONARY:
		var p: Dictionary = params
		match str(def.get("type", "")):
			"weapon":
				var min_lv := int(p.get("min_level", 1))
				if min_lv > 1:
					box.add_child(_tip_line("Уровень", str(min_lv), _player_level < min_lv))
				_add_stat_reqs(box, p)
				if bool(p.get("melee", false)):
					box.add_child(_tip_line("Тип", "Ближний бой"))
				var cal := str(p.get("caliber", ""))
				if cal != "":
					box.add_child(_tip_line("Калибр", cal))
				var tot := ZZLos.total_weapon_damage(item_id)
				if tot.x > 0 or tot.y > 0 or p.has("damage_min"):
					box.add_child(_tip_line("Урон", "%s–%s" % [fmt_val(tot.x), fmt_val(tot.y)]))
					if not bool(p.get("melee", false)):
						var body := "%s–%s" % [fmt_val(p.get("damage_min", 0)), fmt_val(p.get("damage_max", 0))]
						box.add_child(_tip_line("  оружие", body))
						var ammo_id := ZZLos.ammo_id_for_weapon(item_id)
						if ammo_id != "":
							box.add_child(_tip_line("  патрон", fmt_val(ZZLos.ammo_damage(ammo_id))))
				if p.has("range"):
					box.add_child(_tip_line("Дальность", fmt_val(p.get("range"))))
				if p.has("accuracy"):
					box.add_child(_tip_line("Точность", "%d" % int(round(float(p.get("accuracy", 0.0)) * 100.0))))
				if p.has("mag_size") and int(p.get("mag_size", 0)) > 0:
					box.add_child(_tip_line("Обойма", fmt_val(p.get("mag_size"))))
				if p.has("shoot_ap"):
					box.add_child(_tip_line("Одиночный", "%s ОД" % fmt_val(p.get("shoot_ap"))))
				if int(p.get("burst_ap", 0)) > 0:
					box.add_child(_tip_line("Очередь", "%s ОД" % fmt_val(p.get("burst_ap"))))
				if int(p.get("duplet_ap", 0)) > 0:
					box.add_child(_tip_line("Дуплет", "%s ОД" % fmt_val(p.get("duplet_ap"))))
				if p.has("reload_ap") and int(p.get("reload_ap", 0)) > 0:
					box.add_child(_tip_line("Перезарядка", "%s ОД" % fmt_val(p.get("reload_ap"))))
			"medkit":
				if p.has("heal_min") or p.has("heal_max"):
					box.add_child(_tip_line("Лечение", "%s–%s" % [fmt_val(p.get("heal_min", "?")), fmt_val(p.get("heal_max", "?"))]))
				if p.has("use_ap"):
					box.add_child(_tip_line("Использование", "%s ОД" % fmt_val(p.get("use_ap"))))
			"ammo":
				var cal_a := str(p.get("caliber", ""))
				if cal_a == "":
					var wid := str(p.get("weapon_id", ""))
					if wid != "":
						cal_a = ZZLos.weapon_caliber(wid)
				if cal_a != "":
					box.add_child(_tip_line("Калибр", cal_a))
				var ad := int(p.get("damage", 0))
				if ad <= 0:
					ad = int(p.get("damage_min", 0))
				if ad > 0:
					box.add_child(_tip_line("Урон", fmt_val(ad)))
			"armor":
				box.add_child(_tip_line("Тип", "Броня"))
				var min_lv_a := int(p.get("min_level", 1))
				if min_lv_a > 1:
					box.add_child(_tip_line("Уровень", str(min_lv_a), _player_level < min_lv_a))
				_add_stat_reqs(box, p)
				var prot := int(p.get("protection", 0))
				if prot > 0:
					box.add_child(_tip_line("Защита", "+%d" % prot))

	for row in extra_rows:
		if typeof(row) != TYPE_ARRAY or row.size() < 2:
			continue
		box.add_child(_tip_line(str(row[0]), str(row[1])))
	return panel


static func _add_stat_reqs(box: VBoxContainer, p: Dictionary) -> void:
	var labels := {
		"req_strength": ["Сила", "strength"],
		"req_agility": ["Ловкость", "agility"],
		"req_endurance": ["Выносливость", "endurance"],
		"req_intuition": ["Интуиция", "intuition"],
		"req_accuracy": ["Меткость", "accuracy"],
		"req_intelligence": ["Интеллект", "intelligence"],
	}
	for key in labels.keys():
		var need := int(p.get(key, 0))
		if need <= 0:
			continue
		var meta: Array = labels[key]
		var have := int(_player_stats.get(meta[1], 5))
		## No «+» suffix — plain threshold; warn tint when current stat is too low.
		box.add_child(_tip_line(str(meta[0]), str(need), have < need))


static func _new_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = COL_TIP_BG
	tip_sb.border_color = COL_TIP_BORDER
	tip_sb.set_border_width_all(1)
	tip_sb.set_corner_radius_all(3)
	tip_sb.content_margin_left = 10
	tip_sb.content_margin_top = 10
	tip_sb.content_margin_right = 10
	tip_sb.content_margin_bottom = 10
	tip_sb.shadow_size = 0
	panel.add_theme_stylebox_override("panel", tip_sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	return panel


static func _add_title_block(box: VBoxContainer, title_text: String, subtitle: String) -> void:
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", COL_TITLE)
	box.add_child(title)
	if subtitle.strip_edges() != "":
		var type_l := Label.new()
		type_l.text = subtitle
		type_l.add_theme_font_size_override("font_size", 11)
		type_l.add_theme_color_override("font_color", COL_MUTED)
		box.add_child(type_l)
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.32, 0.35, 0.40, 0.55)
	box.add_child(sep)


static func fmt_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	var s := "%.3f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s


## Format catalog numbers (int/float/string) without trailing ".0".
static func fmt_val(v: Variant) -> String:
	match typeof(v):
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return fmt_num(float(v))
		TYPE_STRING:
			if str(v).is_valid_float():
				return fmt_num(float(v))
			return str(v)
		_:
			return str(v)


static func _tip_line(key: String, value: String, warn: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var col_k := COL_WARN if warn else COL_MUTED
	var col_v := COL_WARN if warn else COL_LABEL
	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.add_theme_font_size_override("font_size", 11)
	k.add_theme_color_override("font_color", col_k)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 11)
	v.add_theme_color_override("font_color", col_v)
	row.add_child(v)
	return row


static func _type_label(t: String) -> String:
	match t:
		"weapon":
			return "Оружие"
		"armor":
			return "Броня"
		"medkit":
			return "Медицина"
		"ammo":
			return "Боеприпасы"
		_:
			return t if t != "" else "Предмет"
