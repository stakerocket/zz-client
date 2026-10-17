extends RefCounted
class_name ZZItemTooltip

## Shared inventory-style item card (used by bag + battle HUD).

const COL_LABEL := Color(0.78, 0.80, 0.84)
const COL_TITLE := Color(0.90, 0.91, 0.93)
const COL_MUTED := Color(0.58, 0.60, 0.64)
const COL_TIP_BG := Color(0.09, 0.095, 0.11, 1.0)
const COL_TIP_BORDER := Color(0.35, 0.38, 0.42, 1.0)


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
				if p.has("damage_min") or p.has("damage_max"):
					box.add_child(_tip_line("Урон", "%s–%s" % [fmt_val(p.get("damage_min", "?")), fmt_val(p.get("damage_max", "?"))]))
				if p.has("range"):
					box.add_child(_tip_line("Дальность", fmt_val(p.get("range"))))
				if p.has("accuracy"):
					box.add_child(_tip_line("Точность", "%d" % int(round(float(p.get("accuracy", 0.0)) * 100.0))))
				if p.has("mag_size"):
					box.add_child(_tip_line("Обойма", fmt_val(p.get("mag_size"))))
				if p.has("shoot_ap"):
					box.add_child(_tip_line("Выстрел", "%s ОД" % fmt_val(p.get("shoot_ap"))))
				if p.has("reload_ap"):
					box.add_child(_tip_line("Перезарядка", "%s ОД" % fmt_val(p.get("reload_ap"))))
			"medkit":
				if p.has("heal_min") or p.has("heal_max"):
					box.add_child(_tip_line("Лечение", "%s–%s" % [fmt_val(p.get("heal_min", "?")), fmt_val(p.get("heal_max", "?"))]))
				if p.has("use_ap"):
					box.add_child(_tip_line("Использование", "%s ОД" % fmt_val(p.get("use_ap"))))
			"ammo":
				var wid := str(p.get("weapon_id", ""))
				if wid != "":
					var wdef := ZZLos.item_def(wid)
					box.add_child(_tip_line("Для", str(wdef.get("name", wid))))
			"armor":
				box.add_child(_tip_line("Тип", "Броня"))

	for row in extra_rows:
		if typeof(row) != TYPE_ARRAY or row.size() < 2:
			continue
		box.add_child(_tip_line(str(row[0]), str(row[1])))
	return panel


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


static func _tip_line(key: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.add_theme_font_size_override("font_size", 11)
	k.add_theme_color_override("font_color", COL_MUTED)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 11)
	v.add_theme_color_override("font_color", COL_LABEL)
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
