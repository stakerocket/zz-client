extends Control
class_name ZZInventoryUI

## Lobby inventory — mockup layout, procedural panels (no bg textures).

signal closed
signal equip_requested(item_id: String, slot: String)
signal unequip_requested(slot: String)

## Fixed design size inside 1280×720 canvas.
const SHELL_W := 720.0
const SHELL_H := 460.0
const GRID_COLS := 5
const CELL_SEP := 3
const BAG_PAD := 6
const SCROLL_W := 5
const WEAPON_SLOT := Vector2(112, 52)
const ARMOR_SLOT := Vector2(52, 52)
const QUICK_SLOT := Vector2(44, 44)
const QUICK_COUNT := 4
const COL_LABEL := Color(0.82, 0.80, 0.74)
const COL_TITLE := Color(0.90, 0.88, 0.82)
const COL_MUTED := Color(0.70, 0.68, 0.62)
const COL_TIP_BG := Color(0.10, 0.095, 0.09, 1.0)
const COL_TIP_BORDER := Color(0.55, 0.48, 0.36, 1.0)

var _nick: String = ""
var _inventory: Array = []
var _equipped: Dictionary = {"primary": "", "secondary": "", "armor": ""}
## Quick-access slots (battle hotbar later): item_id or "".
var _quick: Array = ["", "", "", ""]
var _weight: float = 0.0
var _carry: float = 50.0
var _overweight: bool = false

var _shell: Control
var _nick_label: Label
var _level_label: Label
var _weight_label: Label
var _armor_btn: ZZInvDragItem
var _primary_btn: ZZInvDragItem
var _secondary_btn: ZZInvDragItem
var _quick_btns: Array = [] # ZZInvDragItem × 4
var _grid: GridContainer
var _bag_scroll: ScrollContainer
var _bag_drop_zone: ZZInvDragItem
var _bag_panel: PanelContainer
var _preview_host: SubViewportContainer
var _preview_vp: SubViewport
var _unit: ZZUnitView


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 120
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## Kill default TooltipPanel halo behind custom item cards.
	var tip_theme := Theme.new()
	tip_theme.set_stylebox("panel", "TooltipPanel", StyleBoxEmpty.new())
	theme = tip_theme
	_build()


func open_for(nick: String) -> void:
	_nick = nick
	if _nick_label != null:
		_nick_label.text = nick if nick != "" else "—"
	visible = true
	## Rebuild preview so camera/unit tweaks apply every open.
	_unit = null
	if _preview_vp != null:
		for c in _preview_vp.get_children():
			c.queue_free()
	_ensure_preview()
	_refresh()
	## Grid size depends on bag panel layout — rebuild next frame.
	call_deferred("_refresh_grid")


func close() -> void:
	visible = false
	closed.emit()


func apply_state(data: Dictionary) -> void:
	var inv_v: Variant = data.get("inventory", [])
	_inventory = inv_v if typeof(inv_v) == TYPE_ARRAY else []
	var eq: Variant = data.get("equipped", {})
	var eq_dict: Dictionary = eq if typeof(eq) == TYPE_DICTIONARY else {}
	_equipped = {
		"primary": str(eq_dict.get("primary", "")),
		"secondary": str(eq_dict.get("secondary", "")),
		"armor": str(eq_dict.get("armor", "")),
	}
	_quick = ["", "", "", ""]
	var qv: Variant = data.get("quick", [])
	if typeof(qv) == TYPE_ARRAY:
		for i in range(mini(QUICK_COUNT, qv.size())):
			_quick[i] = str(qv[i])
	_weight = float(data.get("inventory_weight", 0.0))
	_carry = float(data.get("carry_weight", 50.0))
	_overweight = bool(data.get("overweight", false))
	if visible:
		_refresh()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	## Plain Control so close-button anchors work (PanelContainer overrides children).
	_shell = Control.new()
	_shell.custom_minimum_size = Vector2(SHELL_W, SHELL_H)
	_shell.size = Vector2(SHELL_W, SHELL_H)
	_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_shell)

	var shell_bg := Panel.new()
	shell_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell_bg.add_theme_stylebox_override("panel", _panel_style(
		Color(0.10, 0.095, 0.09, 0.96),
		Color(0.42, 0.38, 0.30, 0.85),
		2, 0
	))
	_shell.add_child(shell_bg)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 10)
	root.add_theme_constant_override("margin_top", 10)
	root.add_theme_constant_override("margin_right", 10)
	root.add_theme_constant_override("margin_bottom", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shell.add_child(root)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	root.add_child(root_vbox)

	# --- Body ---
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root_vbox.add_child(body)

	# Left: nameplate + equip stage (no desc plate)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)

	var nameplate := PanelContainer.new()
	nameplate.add_theme_stylebox_override("panel", _panel_style(
		Color(0.14, 0.13, 0.12, 1.0),
		Color(0.45, 0.40, 0.32, 0.8),
		1, 6
	))
	left.add_child(nameplate)
	var np_box := VBoxContainer.new()
	np_box.add_theme_constant_override("separation", 0)
	nameplate.add_child(np_box)
	_nick_label = Label.new()
	_nick_label.text = "—"
	_nick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nick_label.add_theme_font_size_override("font_size", 14)
	_nick_label.add_theme_color_override("font_color", COL_TITLE)
	np_box.add_child(_nick_label)
	_level_label = Label.new()
	_level_label.text = "Уровень 1"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 11)
	_level_label.add_theme_color_override("font_color", COL_MUTED)
	np_box.add_child(_level_label)

	var stage := HBoxContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 6)
	## Slots sit at the top of the stage (not vertically centered).
	stage.alignment = BoxContainer.ALIGNMENT_BEGIN
	left.add_child(stage)

	var armor_col := VBoxContainer.new()
	armor_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	armor_col.add_theme_constant_override("separation", 4)
	stage.add_child(armor_col)
	armor_col.add_child(_caption("БРОНЯ", 11))
	_armor_btn = _make_equip_slot("armor", ARMOR_SLOT)
	armor_col.add_child(_armor_btn)

	## Center column: character preview + quick-access row under it.
	var mid_col := VBoxContainer.new()
	mid_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_col.add_theme_constant_override("separation", 6)
	stage.add_child(mid_col)

	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.15, 0.14, 0.13, 1.0),
		Color(0.40, 0.36, 0.30, 0.8),
		1, 2
	))
	mid_col.add_child(preview_panel)
	_preview_host = SubViewportContainer.new()
	_preview_host.stretch = true
	_preview_host.custom_minimum_size = Vector2(100, 130)
	_preview_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_child(_preview_host)
	_preview_vp = SubViewport.new()
	_preview_vp.transparent_bg = false
	_preview_vp.handle_input_locally = false
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.msaa_3d = Viewport.MSAA_4X
	_preview_vp.size = Vector2i(280, 360)
	_preview_host.add_child(_preview_vp)

	var quick_row := HBoxContainer.new()
	quick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	quick_row.add_theme_constant_override("separation", 4)
	mid_col.add_child(quick_row)
	_quick_btns.clear()
	for i in range(QUICK_COUNT):
		var qb := _make_equip_slot("quick_%d" % i, QUICK_SLOT)
		_quick_btns.append(qb)
		quick_row.add_child(qb)

	var weap_col := VBoxContainer.new()
	weap_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	weap_col.add_theme_constant_override("separation", 10)
	stage.add_child(weap_col)

	var prim_box := VBoxContainer.new()
	prim_box.add_theme_constant_override("separation", 3)
	weap_col.add_child(prim_box)
	prim_box.add_child(_caption("ОСНОВНОЕ ОРУЖИЕ", 10))
	_primary_btn = _make_equip_slot("primary", WEAPON_SLOT)
	prim_box.add_child(_primary_btn)

	var sec_box := VBoxContainer.new()
	sec_box.add_theme_constant_override("separation", 3)
	weap_col.add_child(sec_box)
	sec_box.add_child(_caption("ДОПОЛНИТЕЛЬНОЕ", 10))
	_secondary_btn = _make_equip_slot("secondary", WEAPON_SLOT)
	sec_box.add_child(_secondary_btn)

	# Right column: title + bag + weight
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.2
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	body.add_child(right)

	var bag_header := HBoxContainer.new()
	bag_header.add_theme_constant_override("separation", 4)
	right.add_child(bag_header)
	var bag_title := Label.new()
	bag_title.text = "Инвентарь"
	bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bag_title.add_theme_font_size_override("font_size", 14)
	bag_title.add_theme_color_override("font_color", COL_TITLE)
	bag_header.add_child(bag_title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	bag_header.add_child(close_btn)

	_bag_panel = PanelContainer.new()
	_bag_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bag_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.07, 0.065, 0.06, 0.98),
		Color(0.35, 0.32, 0.26, 0.8),
		1, 4
	))
	right.add_child(_bag_panel)

	_bag_drop_zone = ZZInvDragItem.new()
	_bag_drop_zone.host = self
	_bag_drop_zone.accept_slot = ""
	_bag_drop_zone.from_slot = ""
	_bag_drop_zone.item_id = ""
	_bag_drop_zone.flat = true
	_bag_drop_zone.focus_mode = Control.FOCUS_NONE
	_bag_drop_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_drop_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_transparent_btn(_bag_drop_zone)
	_bag_panel.add_child(_bag_drop_zone)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", BAG_PAD)
	pad.add_theme_constant_override("margin_top", BAG_PAD)
	pad.add_theme_constant_override("margin_right", BAG_PAD)
	pad.add_theme_constant_override("margin_bottom", BAG_PAD)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_drop_zone.add_child(pad)

	_bag_scroll = ScrollContainer.new()
	_bag_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bag_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bag_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_bag_scroll.clip_contents = true
	pad.add_child(_bag_scroll)
	_style_thin_scrollbar(_bag_scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", CELL_SEP)
	_grid.add_theme_constant_override("v_separation", CELL_SEP)
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_bag_scroll.add_child(_grid)

	# Weight under bag — label next to numbers.
	var weight_row := HBoxContainer.new()
	weight_row.alignment = BoxContainer.ALIGNMENT_END
	weight_row.add_theme_constant_override("separation", 6)
	right.add_child(weight_row)
	var weight_cap := Label.new()
	weight_cap.text = "Вес"
	weight_cap.add_theme_font_size_override("font_size", 12)
	weight_cap.add_theme_color_override("font_color", COL_LABEL)
	weight_row.add_child(weight_cap)
	_weight_label = Label.new()
	_weight_label.add_theme_font_size_override("font_size", 13)
	_weight_label.add_theme_color_override("font_color", COL_TITLE)
	_weight_label.text = "0 / 50 ед."
	weight_row.add_child(_weight_label)

	## Rebuild grid after layout has real sizes.
	call_deferred("_refresh_grid")
	resized.connect(func():
		if visible:
			call_deferred("_refresh_grid")
	)


func _style_thin_scrollbar(scroll: ScrollContainer) -> void:
	var sb := scroll.get_v_scroll_bar()
	if sb == null:
		return
	sb.custom_minimum_size.x = SCROLL_W
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.55, 0.50, 0.40, 0.75)
	grab.set_corner_radius_all(2)
	grab.content_margin_left = 0
	grab.content_margin_right = 0
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.11, 0.10, 0.55)
	track.set_corner_radius_all(2)
	sb.add_theme_stylebox_override("grabber", grab)
	sb.add_theme_stylebox_override("grabber_highlight", grab)
	sb.add_theme_stylebox_override("grabber_pressed", grab)
	sb.add_theme_stylebox_override("scroll", track)
	sb.add_theme_constant_override("padding_left", 0)
	sb.add_theme_constant_override("padding_right", 0)


func _caption(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", COL_LABEL)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_style(bg: Color, border: Color, width: int, margin: int = 8) -> StyleBoxFlat:
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


func _slot_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.15, 0.14, 1.0)
	s.border_color = Color(0.50, 0.46, 0.38, 0.8)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 2
	s.content_margin_top = 2
	s.content_margin_right = 2
	s.content_margin_bottom = 2
	return s


func _style_slot_button(b: Button) -> void:
	var normal := _slot_style()
	var hover := _slot_style()
	hover.bg_color = Color(0.22, 0.20, 0.18, 1.0)
	hover.border_color = Color(0.82, 0.76, 0.58, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _make_equip_slot(slot_name: String, min_size: Vector2) -> ZZInvDragItem:
	var b := ZZInvDragItem.new()
	b.host = self
	b.accept_slot = slot_name
	b.from_slot = slot_name
	b.text = ""
	b.custom_minimum_size = min_size
	b.clip_contents = true
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.expand_icon = false
	_style_slot_button(b)
	return b


func _ensure_slot_icon(btn: Button) -> TextureRect:
	var tr := btn.get_node_or_null("ItemIcon") as TextureRect
	if tr != null:
		return tr
	tr = TextureRect.new()
	tr.name = "ItemIcon"
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.offset_left = 2
	tr.offset_top = 2
	tr.offset_right = -2
	tr.offset_bottom = -2
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	btn.add_child(tr)
	return tr


func _transparent_btn(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	b.add_theme_stylebox_override("focus", empty)


func _bag_inner_size() -> Vector2:
	if _bag_scroll != null and _bag_scroll.size.x > 8.0 and _bag_scroll.size.y > 8.0:
		return _bag_scroll.size
	if _bag_panel != null and _bag_panel.size.x > 8.0:
		return Vector2(
			_bag_panel.size.x - float(BAG_PAD * 2),
			maxi(120.0, _bag_panel.size.y - float(BAG_PAD * 2))
		)
	return Vector2(300, 260)


func _cell_px() -> int:
	var inner := _bag_inner_size()
	var avail_w := maxf(8.0, inner.x - float(SCROLL_W))
	var by_w := floori((avail_w - float(CELL_SEP * (GRID_COLS - 1))) / float(GRID_COLS))
	## Fill bag height (~5–6 rows) instead of tiny 72px cells with empty void below.
	var target_rows := clampi(floori(inner.y / 64.0), 5, 7)
	var by_h := floori((inner.y - float(CELL_SEP * (target_rows - 1))) / float(target_rows))
	var side := by_w
	if by_h > 0:
		side = mini(by_w, by_h)
	return clampi(side, 44, 104)


func _visible_rows(side: int) -> int:
	var inner := _bag_inner_size()
	var rows := floori((inner.y + float(CELL_SEP)) / float(maxi(1, side + CELL_SEP)))
	return clampi(rows, 5, 14)


func _cell_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.15, 0.14, 0.13, 0.95)
	s.border_color = Color(0.50, 0.46, 0.38, 0.8)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	return s


func _ensure_preview() -> void:
	if _preview_vp == null:
		return
	if _unit != null and is_instance_valid(_unit):
		return
	for c in _preview_vp.get_children():
		c.queue_free()
	var world := Node3D.new()
	_preview_vp.add_child(world)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.14, 0.13, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.72, 0.68)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	world.add_child(env_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_color = Color(1.0, 0.96, 0.9)
	light.light_energy = 1.4
	light.shadow_enabled = true
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(15, -110, 0)
	fill.light_color = Color(0.7, 0.78, 0.95)
	fill.light_energy = 0.55
	world.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-5, 160, 0)
	rim.light_energy = 0.4
	world.add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 32.0
	## Centered on unit origin; further back → smaller in frame.
	cam.position = Vector3(0.0, 1.55, 6.0)
	cam.look_at(Vector3(0.0, 1.1, 0.0))
	cam.current = true
	world.add_child(cam)
	_unit = ZZUnitView.new()
	world.add_child(_unit)
	_unit.position = Vector3.ZERO
	_unit.setup("preview", _nick if _nick != "" else "—", Color(0.55, 0.5, 0.42))
	if _unit.get_node_or_null("UnitUI") != null:
		_unit.get_node("UnitUI").visible = false


func _refresh() -> void:
	_refresh_slots()
	_refresh_grid()
	if _weight_label != null:
		var carry := maxf(1.0, _carry)
		var frac := _weight / carry
		_weight_label.text = "%s / %s ед." % [_fmt_num(_weight), _fmt_num(_carry)]
		if _overweight or frac > 1.0:
			_weight_label.add_theme_color_override("font_color", Color(0.95, 0.40, 0.32))
		elif frac >= 0.85:
			_weight_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35))
		else:
			_weight_label.add_theme_color_override("font_color", COL_TITLE)


func _refresh_slots() -> void:
	_fill_slot_btn(_armor_btn, str(_equipped.get("armor", "")), true)
	_fill_slot_btn(_primary_btn, str(_equipped.get("primary", "")), false)
	_fill_slot_btn(_secondary_btn, str(_equipped.get("secondary", "")), false)
	for i in range(_quick_btns.size()):
		var id := ""
		if i < _quick.size():
			id = str(_quick[i])
		_fill_slot_btn(_quick_btns[i], id, true)


func _stack_qty(item_id: String) -> int:
	if item_id == "":
		return 0
	for s in _inventory:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("item_id", "")) == item_id:
			return int(s.get("qty", 0))
	return 0


func _fill_slot_btn(btn: ZZInvDragItem, item_id: String, square: bool) -> void:
	if btn == null:
		return
	var qty := _stack_qty(item_id)
	btn.item_id = item_id
	btn.qty = maxi(qty, 1)
	btn.from_slot = btn.accept_slot
	btn.text = ""
	btn.icon = null
	btn.tooltip_text = " " if item_id != "" else ""
	var tr := _ensure_slot_icon(btn)
	## Qty badge on quick / equip when stack > 1.
	var badge := btn.get_node_or_null("QtyBadge") as Label
	if item_id == "":
		tr.texture = null
		tr.visible = false
		if badge != null:
			badge.visible = false
		return
	tr.visible = true
	tr.texture = _icon_for(item_id, 256, 96)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not square:
		tr.offset_left = 4
		tr.offset_top = 3
		tr.offset_right = -4
		tr.offset_bottom = -3
	if qty > 1:
		if badge == null:
			badge = Label.new()
			badge.name = "QtyBadge"
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.anchor_left = 1.0
			badge.anchor_top = 1.0
			badge.anchor_right = 1.0
			badge.anchor_bottom = 1.0
			badge.offset_left = -28
			badge.offset_top = -14
			badge.offset_right = -2
			badge.offset_bottom = -1
			badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			badge.add_theme_font_size_override("font_size", 11)
			badge.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
			badge.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05, 0.9))
			badge.add_theme_constant_override("outline_size", 2)
			btn.add_child(badge)
		badge.text = "x%d" % qty
		badge.visible = true
	elif badge != null:
		badge.visible = false


func _is_slotted(item_id: String) -> bool:
	if item_id == "":
		return false
	if (
		item_id == str(_equipped.get("primary", ""))
		or item_id == str(_equipped.get("secondary", ""))
		or item_id == str(_equipped.get("armor", ""))
	):
		return true
	for q in _quick:
		if str(q) == item_id:
			return true
	return false


func _refresh_grid() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()

	var cells: Array = []
	for s in _inventory:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var id := str(s.get("item_id", ""))
		var qty := int(s.get("qty", 0))
		if id == "" or qty <= 0:
			continue
		## Equipped / quick items live in their slots — not duplicated in the bag grid.
		if _is_slotted(id):
			continue
		cells.append({"item_id": id, "qty": qty})

	var side := _cell_px()
	var rows := _visible_rows(side)
	## Fill the bag panel with full rows; more rows only if items overflow → scrollbar.
	var need := maxi(GRID_COLS * rows, int(ceil(float(cells.size()) / float(GRID_COLS))) * GRID_COLS)
	var sz := Vector2(side, side)

	for i in range(need):
		## Plain Control so qty badge anchors work.
		var cell := Control.new()
		cell.custom_minimum_size = sz
		cell.size = sz
		_grid.add_child(cell)

		var id2 := ""
		var qty2 := 0
		if i < cells.size():
			var entry: Dictionary = cells[i]
			id2 = str(entry["item_id"])
			qty2 = int(entry["qty"])

		## Every cell is a styled button so hover matches weapon/armor slots.
		var btn := ZZInvDragItem.new()
		btn.host = self
		btn.item_id = id2
		btn.qty = maxi(qty2, 1)
		btn.from_slot = ""
		btn.accept_slot = ""
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.text = ""
		btn.focus_mode = Control.FOCUS_NONE
		btn.expand_icon = false
		btn.icon = null
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.tooltip_text = " " if id2 != "" else ""
		_style_slot_button(btn)
		cell.add_child(btn)

		if id2 != "":
			var icon := TextureRect.new()
			icon.name = "ItemIcon"
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = 3
			icon.offset_top = 3
			icon.offset_right = -3
			icon.offset_bottom = -3
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = _icon_for(id2, side - 6, side - 6)
			btn.add_child(icon)
			## Qty badge — bottom-right of cell.
			if qty2 > 1:
				var q := Label.new()
				q.text = "x%d" % qty2
				q.mouse_filter = Control.MOUSE_FILTER_IGNORE
				q.anchor_left = 1.0
				q.anchor_top = 1.0
				q.anchor_right = 1.0
				q.anchor_bottom = 1.0
				q.offset_left = -28
				q.offset_top = -14
				q.offset_right = -2
				q.offset_bottom = -1
				q.grow_horizontal = Control.GROW_DIRECTION_BEGIN
				q.grow_vertical = Control.GROW_DIRECTION_BEGIN
				q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				q.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
				q.add_theme_font_size_override("font_size", 11)
				q.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
				q.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05, 0.9))
				q.add_theme_constant_override("outline_size", 2)
				cell.add_child(q)

	if _bag_scroll != null:
		_style_thin_scrollbar(_bag_scroll)


func build_item_tooltip(item_id: String, qty: int = 1) -> Control:
	var def := ZZLos.item_def(item_id)
	## Opaque card; parent TooltipPanel is StyleBoxEmpty (see _ready) — no halo.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	var tip_sb := _panel_style(COL_TIP_BG, COL_TIP_BORDER, 1, 10)
	tip_sb.shadow_size = 0
	panel.add_theme_stylebox_override("panel", tip_sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var title := Label.new()
	title.text = str(def.get("name", item_id))
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", COL_TITLE)
	box.add_child(title)

	var type_l := Label.new()
	type_l.text = _type_label(str(def.get("type", "")))
	type_l.add_theme_font_size_override("font_size", 11)
	type_l.add_theme_color_override("font_color", COL_MUTED)
	box.add_child(type_l)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.45, 0.40, 0.32, 0.55)
	box.add_child(sep)

	var unit_w := float(def.get("weight", 0.0))
	var total_w := unit_w * float(maxi(qty, 1))
	box.add_child(_tip_line("Кол-во", "×%d" % maxi(qty, 1)))
	box.add_child(_tip_line("Вес", "%s ед." % _fmt_num(total_w)))

	var params: Variant = def.get("params", {})
	if typeof(params) == TYPE_DICTIONARY:
		var p: Dictionary = params
		match str(def.get("type", "")):
			"weapon":
				if p.has("damage_min") or p.has("damage_max"):
					box.add_child(_tip_line("Урон", "%s–%s" % [str(p.get("damage_min", "?")), str(p.get("damage_max", "?"))]))
				if p.has("range"):
					box.add_child(_tip_line("Дальность", str(p.get("range"))))
				if p.has("accuracy"):
					box.add_child(_tip_line("Точность", "%d%%" % int(round(float(p.get("accuracy", 0.0)) * 100.0))))
				if p.has("mag_size"):
					box.add_child(_tip_line("Обойма", str(p.get("mag_size"))))
				if p.has("shoot_ap"):
					box.add_child(_tip_line("Выстрел", "%s ОД" % str(p.get("shoot_ap"))))
				if p.has("reload_ap"):
					box.add_child(_tip_line("Перезарядка", "%s ОД" % str(p.get("reload_ap"))))
			"medkit":
				if p.has("heal_min") or p.has("heal_max"):
					box.add_child(_tip_line("Лечение", "%s–%s" % [str(p.get("heal_min", "?")), str(p.get("heal_max", "?"))]))
				if p.has("use_ap"):
					box.add_child(_tip_line("Использование", "%s ОД" % str(p.get("use_ap"))))
			"ammo":
				var wid := str(p.get("weapon_id", ""))
				if wid != "":
					var wdef := ZZLos.item_def(wid)
					box.add_child(_tip_line("Для", str(wdef.get("name", wid))))
			"armor":
				box.add_child(_tip_line("Тип", "Броня"))
	return panel


## Trim trailing zeros: 49.6, 50, 0.012 — never "50.0" / "0.100".
func _fmt_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	var s := "%.3f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s


func _tip_line(key: String, value: String) -> HBoxContainer:
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


func _type_label(t: String) -> String:
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


func _icon_for(item_id: String, w: int = 48, h: int = 48) -> Texture2D:
	var mock := ZZInventoryIcons.tex(item_id)
	if mock != null:
		return mock
	var def := ZZLos.item_def(item_id)
	var t := str(def.get("type", ""))
	var sz := maxi(w, h)
	match t:
		"medkit":
			return ZZHudIcons.medkit(sz)
		"ammo":
			var params: Variant = def.get("params", {})
			var weapon_id := ""
			if typeof(params) == TYPE_DICTIONARY:
				weapon_id = str(params.get("weapon_id", ""))
			if item_id == "ammo_9mm" or weapon_id == "glock17":
				return ZZHudIcons.ammo_pistol(sz)
			return ZZHudIcons.ammo_rifle(sz)
		"armor":
			return ZZHudIcons.vest(sz)
		"weapon":
			if item_id == "glock17":
				return ZZHudIcons.pistol(maxi(w, 96), maxi(h, 36))
			return ZZHudIcons.rifle(maxi(w, 128), maxi(h, 40))
		_:
			return ZZHudIcons.ammo_rifle(maxi(16, sz))


func _item_type(item_id: String) -> String:
	return str(ZZLos.item_def(item_id).get("type", ""))


func _is_quick_slot(slot_name: String) -> bool:
	return slot_name.begins_with("quick_")


func _quick_index(slot_name: String) -> int:
	if not _is_quick_slot(slot_name):
		return -1
	return int(slot_name.get_slice("_", 1))


func can_drop_on_slot(slot_name: String, data: Dictionary) -> bool:
	var item_id := str(data.get("item_id", ""))
	if item_id == "" or slot_name == "":
		return false
	var from_slot := str(data.get("from_slot", ""))
	if from_slot == slot_name:
		return false
	var t := _item_type(item_id)
	match slot_name:
		"primary", "secondary":
			return t == "weapon"
		"armor":
			return t == "armor"
		_:
			if _is_quick_slot(slot_name):
				## Battle hotbar: consumables / ammo (not weapons or armor).
				return t == "medkit" or t == "ammo"
			return false


func can_drop_on_bag(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var from_slot := str(data.get("from_slot", ""))
	return (
		from_slot == "primary"
		or from_slot == "secondary"
		or from_slot == "armor"
		or _is_quick_slot(from_slot)
	)


func _get_slot_item(slot_name: String) -> String:
	if _is_quick_slot(slot_name):
		var qi := _quick_index(slot_name)
		if qi >= 0 and qi < _quick.size():
			return str(_quick[qi])
		return ""
	return str(_equipped.get(slot_name, ""))


func _set_slot_item(slot_name: String, item_id: String) -> void:
	if _is_quick_slot(slot_name):
		var qi := _quick_index(slot_name)
		if qi >= 0:
			while _quick.size() < QUICK_COUNT:
				_quick.append("")
			_quick[qi] = item_id
		return
	_equipped[slot_name] = item_id


func drop_on_slot(slot_name: String, data: Dictionary) -> void:
	var item_id := str(data.get("item_id", ""))
	if not can_drop_on_slot(slot_name, data):
		return
	var from_slot := str(data.get("from_slot", ""))
	var prev: String = _get_slot_item(slot_name)
	_set_slot_item(slot_name, item_id)
	if from_slot != "":
		## Swap if dragging from another slot.
		if _is_quick_slot(from_slot) or from_slot == "primary" or from_slot == "secondary" or from_slot == "armor":
			## Only swap if the previous item is valid for the source slot.
			var swap_ok := true
			if prev != "":
				var fake := {"item_id": prev, "from_slot": slot_name}
				swap_ok = can_drop_on_slot(from_slot, fake)
			_set_slot_item(from_slot, prev if swap_ok else "")
	_refresh()
	## Notify server for equip / quick slots (authoritative inventory_state).
	equip_requested.emit(item_id, slot_name)


func drop_on_bag(data: Variant) -> void:
	if not can_drop_on_bag(data):
		return
	var from_slot := str(data.get("from_slot", ""))
	_set_slot_item(from_slot, "")
	_refresh()
	unequip_requested.emit(from_slot)


## For battle HUD later.
func get_quick_slots() -> Array:
	return _quick.duplicate()
