extends Control
class_name ZZEnemyDossier

## Compact enemy sheet on battle hover: stats + preview + equip slots (no quick bar).

const PREVIEW_W := 140.0
const INFO_W := 112.0
const EQUIP_SLOT := Vector2(48, 48)
const EQUIP_BOX_SEP := 2
const EQUIP_COL_SEP := 4
const EQUIP_CAPTION_H := 12
## Model pane height = 3 equip slots + captions + gaps (no black void under feet).
const PREVIEW_H := (
	3.0 * (EQUIP_SLOT.y + float(EQUIP_BOX_SEP) + float(EQUIP_CAPTION_H))
	+ 2.0 * float(EQUIP_COL_SEP)
)
## Same fills as CharDock battle bars (main.tscn StyleHPFill / StyleAPFill / StyleBarBG).
const COL_HP_FILL := Color(0.40, 0.52, 0.36, 1)
const COL_AP_FILL := Color(0.72, 0.62, 0.34, 1)
const COL_BAR_BG := Color(0.05, 0.05, 0.06, 0.42)
const GAP := 28.0
## Extra air when stacking above/below the target (side GAP feels larger).
const GAP_VERT := 52.0
const MARGIN := 8.0
const MARGIN_Y := 20.0
const PREVIEW_RT := Vector2i(360, 480)
const PREVIEW_PLATFORM_H := 0.14
const PREVIEW_PLATFORM_SIDE := 1.35
const PREVIEW_UNIT_SINK := 0.06
const PREVIEW_PIVOT_Y := 0.06

const COL_TITLE := Color(0.90, 0.91, 0.93)
const COL_LABEL := Color(0.78, 0.80, 0.84)
## Match chat dock: soft translucent charcoal.
const COL_SHELL_BG := Color(0.05, 0.05, 0.06, 0.42)
const COL_SHELL_BORDER := Color(0.28, 0.30, 0.34, 0.35)
const COL_PANEL_BG := Color(0.08, 0.08, 0.09, 0.28)
const COL_PANEL_BORDER := Color(0.28, 0.31, 0.35, 0.40)
const COL_SLOT_BG := Color(0.08, 0.08, 0.09, 0.35)
const COL_SLOT_BORDER := Color(0.28, 0.31, 0.35, 0.45)

const _STAT_ROWS := [
	["strength", "Сила"],
	["agility", "Ловкость"],
	["endurance", "Выносливость"],
	["intuition", "Интуиция"],
	["accuracy", "Меткость"],
	["intelligence", "Интеллект"],
]

var _shell: PanelContainer
var _nick_label: Label
var _stat_labels: Dictionary = {}
var _preview_host: Control
var _preview_rect: TextureRect
var _armor_icon: TextureRect
var _primary_icon: TextureRect
var _secondary_icon: TextureRect
var _hp_bar: ProgressBar
var _ap_bar: ProgressBar
var _hp_bar_label: Label
var _ap_bar_label: Label
var _root_col: VBoxContainer
var _built := false
var _current_id: String = ""
var _pending_anchor := Vector2.ZERO
var _pending_shooter := Vector2.ZERO
var _pending_canvas := Vector2(1280, 720)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 40
	_build()


func show_dossier(pd: Dictionary, canvas_anchor: Vector2, canvas_size: Vector2, canvas_shooter: Vector2 = Vector2.ZERO) -> void:
	if not _built:
		_build()
	_fill(pd)
	visible = true
	_current_id = str(pd.get("id", ""))
	_pending_anchor = canvas_anchor
	_pending_shooter = canvas_shooter
	_pending_canvas = canvas_size
	call_deferred("_place_deferred")


func hide_dossier() -> void:
	visible = false
	_current_id = ""


func _place_deferred() -> void:
	if not visible:
		return
	_place(_pending_anchor, _pending_canvas, _pending_shooter)


func _build() -> void:
	if _built:
		return
	_built = true
	_shell = PanelContainer.new()
	_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shell.add_theme_stylebox_override("panel", _panel_style(COL_SHELL_BG, COL_SHELL_BORDER, 1, 6))
	add_child(_shell)

	## [info | black 3D | equip slots]
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	_shell.add_child(row)

	_root_col = VBoxContainer.new()
	_root_col.custom_minimum_size = Vector2(INFO_W, 0)
	_root_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_col.add_theme_constant_override("separation", 3)
	_root_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_root_col)

	_nick_label = Label.new()
	_nick_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nick_label.add_theme_font_size_override("font_size", 13)
	_nick_label.add_theme_color_override("font_color", COL_TITLE)
	_root_col.add_child(_nick_label)

	var bars := VBoxContainer.new()
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_theme_constant_override("separation", 2)
	_root_col.add_child(bars)
	var hp_row := _make_vital_bar_row(COL_HP_FILL, COL_BAR_BG)
	_hp_bar = hp_row["bar"]
	_hp_bar_label = hp_row["label"]
	bars.add_child(hp_row["row"])
	var ap_row := _make_vital_bar_row(COL_AP_FILL, COL_BAR_BG)
	_ap_bar = ap_row["bar"]
	_ap_bar_label = ap_row["label"]
	bars.add_child(ap_row["row"])

	for pair in _STAT_ROWS:
		var key: String = pair[0]
		var lab := Label.new()
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.add_theme_font_size_override("font_size", 11)
		lab.add_theme_color_override("font_color", COL_TITLE)
		_root_col.add_child(lab)
		_stat_labels[key] = lab

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(PREVIEW_W, PREVIEW_H)
	preview_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Solid black frame for the whole 3D pane.
	preview_panel.add_theme_stylebox_override("panel", _panel_style(Color(0, 0, 0, 1), Color(0, 0, 0, 1), 0, 0))
	row.add_child(preview_panel)

	_preview_host = Control.new()
	_preview_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_host.clip_contents = true
	preview_panel.add_child(_preview_host)

	_preview_rect = TextureRect.new()
	_preview_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var preview_path := "res://assets/units/stalker_idle_0_64.png"
	if ResourceLoader.exists(preview_path):
		_preview_rect.texture = load(preview_path)
	else:
		_preview_rect.texture = ZZPixelArt.unit_frame("idle", Color(0.55, 0.5, 0.42), true)
	_preview_host.add_child(_preview_rect)

	var equip_col := VBoxContainer.new()
	equip_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equip_col.add_theme_constant_override("separation", EQUIP_COL_SEP)
	equip_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_child(equip_col)
	_armor_icon = _add_equip_slot(equip_col, "БРОНЯ")
	_primary_icon = _add_equip_slot(equip_col, "ОСНОВНОЕ")
	_secondary_icon = _add_equip_slot(equip_col, "ДОПОЛНИТ.")


func _fill(pd: Dictionary) -> void:
	var nick := str(pd.get("nick", "?"))
	var lvl := maxi(1, int(pd.get("level", 1)))
	_nick_label.text = "%s [%d]" % [nick, lvl]
	var hp := int(pd.get("hp", 0))
	var max_hp := int(pd.get("max_hp", hp))
	var ap := int(pd.get("ap", 0))
	var max_ap := int(pd.get("max_ap", ap))
	_set_vital_bar(_hp_bar, _hp_bar_label, hp, max_hp, "ХП")
	_set_vital_bar(_ap_bar, _ap_bar_label, ap, max_ap, "ОД")

	var stats_v: Variant = pd.get("stats", {})
	var stats: Dictionary = stats_v if typeof(stats_v) == TYPE_DICTIONARY else {}
	for pair in _STAT_ROWS:
		var key: String = pair[0]
		var title: String = pair[1]
		var lab: Label = _stat_labels.get(key)
		if lab != null:
			lab.text = "%s: %d" % [title, int(stats.get(key, 5))]

	var eq_v: Variant = pd.get("equipped", {})
	var eq: Dictionary = eq_v if typeof(eq_v) == TYPE_DICTIONARY else {}
	if _preview_rect != null:
		var preview_path := "res://assets/units/stalker_idle_0_64.png"
		if ResourceLoader.exists(preview_path):
			_preview_rect.texture = load(preview_path)
		else:
			var armed := str(eq.get("primary", "")) != "" or str(eq.get("secondary", "")) != ""
			_preview_rect.texture = ZZPixelArt.unit_frame("idle", Color(0.55, 0.5, 0.42), armed)
	_set_slot_icon(_armor_icon, str(eq.get("armor", "")), true)
	_set_slot_icon(_primary_icon, str(eq.get("primary", "")), false)
	_set_slot_icon(_secondary_icon, str(eq.get("secondary", "")), false)


func _make_vital_bar_row(fill_col: Color, bg_col: Color) -> Dictionary:
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.custom_minimum_size = Vector2(0, 12)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_col
	bg.set_corner_radius_all(2)
	bg.content_margin_left = 0
	bg.content_margin_right = 0
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_col
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	host.add_child(bar)
	var lab := Label.new()
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 10)
	lab.add_theme_color_override("font_color", COL_TITLE)
	host.add_child(lab)
	return {"row": host, "bar": bar, "label": lab}


func _set_vital_bar(bar: ProgressBar, lab: Label, cur: int, mx: int, title: String) -> void:
	if bar == null or lab == null:
		return
	var pool := maxi(mx, 1)
	bar.max_value = float(pool)
	bar.value = float(clampi(cur, 0, pool))
	lab.text = "%s %d/%d" % [title, cur, pool]


func _add_equip_slot(parent: VBoxContainer, caption: String) -> TextureRect:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", EQUIP_BOX_SEP)
	parent.add_child(box)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = EQUIP_SLOT
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(COL_SLOT_BG, COL_SLOT_BORDER, 1, 2))
	box.add_child(panel)
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 2
	icon.offset_top = 2
	icon.offset_right = -2
	icon.offset_bottom = -2
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	panel.add_child(icon)
	var cap := Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_theme_font_size_override("font_size", 8)
	cap.add_theme_color_override("font_color", COL_LABEL)
	box.add_child(cap)
	return icon


func _set_slot_icon(icon: TextureRect, item_id: String, square: bool) -> void:
	if icon == null:
		return
	if item_id == "":
		icon.texture = null
		icon.visible = false
		return
	icon.visible = true
	icon.texture = ZZInventoryIcons.tex(item_id)
	if square:
		icon.offset_left = 2
		icon.offset_top = 2
		icon.offset_right = -2
		icon.offset_bottom = -2
	else:
		icon.offset_left = 4
		icon.offset_top = 3
		icon.offset_right = -4
		icon.offset_bottom = -3


func _place(anchor: Vector2, canvas_size: Vector2, shooter: Vector2 = Vector2.ZERO) -> void:
	## Opposite side from shooter (not between); else above, then below.
	var sz := _shell.get_combined_minimum_size()
	if _shell.size.x > 1.0:
		sz = _shell.size
	custom_minimum_size = sz
	size = sz
	var mid_y := anchor.y - sz.y * 0.45
	var mid_x := anchor.x - sz.x * 0.5
	var prefer_right := shooter.x <= anchor.x
	var candidates: Array[Vector2] = []
	if prefer_right:
		candidates.append(Vector2(anchor.x + GAP, mid_y))
	else:
		candidates.append(Vector2(anchor.x - GAP - sz.x, mid_y))
	candidates.append(Vector2(mid_x, anchor.y - GAP_VERT - sz.y)) ## above
	candidates.append(Vector2(mid_x, anchor.y + GAP_VERT)) ## below
	for c in candidates:
		if _rect_fits(c, sz, canvas_size):
			global_position = c
			return
	## Clamp above if possible, else first candidate.
	var fallback := Vector2(mid_x, anchor.y - GAP_VERT - sz.y)
	fallback.x = clampf(fallback.x, MARGIN, maxf(MARGIN, canvas_size.x - sz.x - MARGIN))
	fallback.y = clampf(fallback.y, MARGIN_Y, maxf(MARGIN_Y, canvas_size.y - sz.y - MARGIN_Y))
	global_position = fallback


func _rect_fits(pos: Vector2, sz: Vector2, canvas_size: Vector2) -> bool:
	return (
		pos.x >= MARGIN
		and pos.y >= MARGIN_Y
		and pos.x + sz.x <= canvas_size.x - MARGIN
		and pos.y + sz.y <= canvas_size.y - MARGIN_Y
	)


func _panel_style(bg: Color, border: Color, width: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(3)
	s.content_margin_left = margin
	s.content_margin_top = margin
	s.content_margin_right = margin
	s.content_margin_bottom = margin
	return s
