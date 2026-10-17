extends Control
class_name ZZInventoryUI

## Lobby inventory — mockup layout, procedural panels (no bg textures).

signal closed
signal equip_requested(item_id: String, slot: String)
signal unequip_requested(slot: String)

## Fixed design size inside 1280×720 canvas.
## Width fits left column + 4×5 bag grid (no black strip right of bag).
const SHELL_W := 580.0
## Shell height is fitted to left column after layout (preview + quick).
const SHELL_H := 360.0
const GRID_COLS := 4
const GRID_ROWS := 5
const CELL_SEP := 3
## Equal inset around the item grid (left / right / top). Bottom stays tighter for weight.
const BAG_PAD := 4
const SCROLL_W := 3
## Armor + both weapons: same square slot size.
const EQUIP_SLOT := Vector2(56, 56)
const WEAPON_SLOT := EQUIP_SLOT
const ARMOR_SLOT := EQUIP_SLOT
const EQUIP_BOX_SEP := 2
const EQUIP_COL_SEP := 6
const EQUIP_CAPTION_H := 12
## Model pane height = 3 equip slots + captions + gaps.
const PREVIEW_H := (
	3.0 * (EQUIP_SLOT.y + float(EQUIP_BOX_SEP) + float(EQUIP_CAPTION_H))
	+ 2.0 * float(EQUIP_COL_SEP)
)
const QUICK_SLOT := Vector2(40, 40)
const QUICK_COUNT := 4
const QUICK_ROW_SEP := 3
## Shared header row (nick ↔ «Инвентарь») — fixed height so stage tops match bag.
const HEADER_H := 18
const COL_SEP := 0
const QUICK_SEP := 2
const WEIGHT_ROW_H := 16
## Preview panel width ≤ four quick slots (+ gaps).
const PREVIEW_COL_W := QUICK_COUNT * QUICK_SLOT.x + float(QUICK_COUNT - 1) * QUICK_ROW_SEP
## Fixed bag cell size (do not shrink to fill tall bag — bag height hugs the grid).
const CELL_FIXED := 50
## Cool steel palette (STALKER-like) — no warm brown chrome.
const COL_LABEL := Color(0.78, 0.80, 0.84)
const COL_TITLE := Color(0.90, 0.91, 0.93)
const COL_MUTED := Color(0.58, 0.60, 0.64)
const COL_SHELL_BG := Color(0.08, 0.085, 0.095, 0.96)
const COL_SHELL_BORDER := Color(0.32, 0.35, 0.39, 0.90)
const COL_PANEL_BG := Color(0.11, 0.115, 0.125, 1.0)
const COL_PANEL_BORDER := Color(0.28, 0.31, 0.35, 0.85)
const COL_BAG_BG := Color(0.055, 0.058, 0.065, 0.98)
const COL_BAG_BORDER := Color(0.24, 0.26, 0.30, 0.85)
## Fixed RT + TextureRect (SubViewportContainer.stretch locks size to panel ≈ мыло).
const PREVIEW_RT := Vector2i(900, 1200)
const PREVIEW_YAW_SENS := 0.012
const PREVIEW_PLATFORM_H := 0.14
const PREVIEW_PLATFORM_SIDE := 1.35
const PREVIEW_PLATFORM_SIZE := Vector3(PREVIEW_PLATFORM_SIDE, PREVIEW_PLATFORM_H, PREVIEW_PLATFORM_SIDE)
## Sink feet into pedestal so boots don't hover above the slab.
const PREVIEW_UNIT_SINK := 0.08
## Lift pedestal+unit in frame (world Y).
const PREVIEW_PIVOT_Y := 0.18

var _nick: String = ""
var _inventory: Array = []
var _equipped: Dictionary = {"primary": "", "secondary": "", "armor": ""}
## Quick-access slots (battle hotbar later): item_id or "".
var _quick: Array = ["", "", "", ""]
var _weight: float = 0.0
var _carry: float = 50.0
var _overweight: bool = false

var _shell: Control
var _dim: ColorRect
var _close_btn: Button
var _left_col: VBoxContainer
var _nick_label: Label
var _weight_label: Label
var _item_dragging: bool = false
var _drag_cursor_tex: Texture2D
var _armor_btn: ZZInvDragItem
var _primary_btn: ZZInvDragItem
var _secondary_btn: ZZInvDragItem
var _quick_btns: Array = [] # ZZInvDragItem × 4
var _grid: GridContainer
var _bag_scroll: ScrollContainer
var _bag_drop_zone: ZZInvDragItem
var _bag_panel: PanelContainer
var _bag_margin: MarginContainer
var _preview_panel: PanelContainer
var _preview_host: Control
var _preview_rect: TextureRect
var _preview_vp: SubViewport
var _preview_pivot: Node3D
var _preview_dragging: bool = false
var _equip_col: VBoxContainer
var _quick_box: VBoxContainer
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
	## Rebuild preview so camera/unit tweaks apply every open; yaw resets to 0.
	_unit = null
	_preview_pivot = null
	_preview_dragging = false
	if _preview_vp != null:
		for c in _preview_vp.get_children():
			c.queue_free()
	_ensure_preview()
	_reset_preview_yaw()
	_refresh()
	## Grid size depends on bag panel layout — rebuild next frame.
	call_deferred("_fit_shell_to_left")
	call_deferred("_refresh_grid")
	## Second pass after shell/bag sizes settle — cells fill without bottom void.
	call_deferred("_refresh_grid")
	call_deferred("_bind_preview_texture")


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
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(_dim)

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
		COL_SHELL_BG,
		COL_SHELL_BORDER,
		1, 0
	))
	_shell.add_child(shell_bg)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 8)
	root.add_theme_constant_override("margin_top", 4)
	root.add_theme_constant_override("margin_right", 8)
	root.add_theme_constant_override("margin_bottom", 8)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shell.add_child(root)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	root.add_child(root_vbox)

	# --- Body ---
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root_vbox.add_child(body)

	# Left: compact header + stage + quick — shrink to content (no expand void).
	_left_col = VBoxContainer.new()
	_left_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_left_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_left_col.add_theme_constant_override("separation", COL_SEP)
	body.add_child(_left_col)

	## Nick only — fixed HEADER_H so stage top matches bag top.
	var left_header := Control.new()
	left_header.custom_minimum_size = Vector2(PREVIEW_COL_W, HEADER_H)
	left_header.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left_header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left_header.clip_contents = true
	_left_col.add_child(left_header)
	_nick_label = Label.new()
	_nick_label.text = "—"
	_nick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nick_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_nick_label.add_theme_font_size_override("font_size", 12)
	_nick_label.add_theme_color_override("font_color", COL_TITLE)
	_nick_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_nick_label.offset_bottom = -3.0 ## small gap under nick before preview
	left_header.add_child(_nick_label)

	var stage := HBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stage.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stage.add_theme_constant_override("separation", 8)
	## Preview left, equip stack (armor + weapons) right — no empty armor column.
	stage.alignment = BoxContainer.ALIGNMENT_BEGIN
	_left_col.add_child(stage)

	## Character preview (height = equip column). Quick sits below full left column.
	_preview_panel = PanelContainer.new()
	_preview_panel.custom_minimum_size = Vector2(PREVIEW_COL_W, PREVIEW_H)
	_preview_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_preview_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.04, 0.042, 0.048, 1.0),
		COL_PANEL_BORDER,
		1, 1
	))
	stage.add_child(_preview_panel)
	_preview_host = Control.new()
	_preview_host.custom_minimum_size = Vector2(PREVIEW_COL_W - 4.0, PREVIEW_H - 4.0)
	_preview_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_host.clip_contents = true
	_preview_host.gui_input.connect(_on_preview_gui_input)
	_preview_panel.add_child(_preview_host)
	## Viewport outside SubViewportContainer so size is not forced to panel px.
	_preview_vp = SubViewport.new()
	_preview_vp.name = "InvPreviewVP"
	_preview_vp.own_world_3d = true
	_preview_vp.transparent_bg = false
	_preview_vp.handle_input_locally = false
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.msaa_3d = Viewport.MSAA_8X
	_preview_vp.size = PREVIEW_RT
	add_child(_preview_vp)
	_preview_rect = TextureRect.new()
	_preview_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview_host.add_child(_preview_rect)
	call_deferred("_bind_preview_texture")

	## Equip column: armor on top, weapons below (same square slots).
	_equip_col = VBoxContainer.new()
	_equip_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	_equip_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_equip_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_equip_col.add_theme_constant_override("separation", EQUIP_COL_SEP)
	stage.add_child(_equip_col)

	var armor_box := VBoxContainer.new()
	armor_box.add_theme_constant_override("separation", EQUIP_BOX_SEP)
	_equip_col.add_child(armor_box)
	_armor_btn = _make_equip_slot("armor", ARMOR_SLOT)
	armor_box.add_child(_armor_btn)
	armor_box.add_child(_caption("БРОНЯ", 8))

	var prim_box := VBoxContainer.new()
	prim_box.add_theme_constant_override("separation", EQUIP_BOX_SEP)
	_equip_col.add_child(prim_box)
	_primary_btn = _make_equip_slot("primary", WEAPON_SLOT)
	prim_box.add_child(_primary_btn)
	prim_box.add_child(_caption("ОСНОВНОЕ", 8))

	var sec_box := VBoxContainer.new()
	sec_box.add_theme_constant_override("separation", EQUIP_BOX_SEP)
	_equip_col.add_child(sec_box)
	_secondary_btn = _make_equip_slot("secondary", WEAPON_SLOT)
	sec_box.add_child(_secondary_btn)
	sec_box.add_child(_caption("ДОПОЛНИТ.", 8))

	## Gap only before quick (header↔stage uses COL_SEP=0 to match inventory title↔bag).
	var quick_gap := Control.new()
	quick_gap.custom_minimum_size = Vector2(0, QUICK_SEP)
	quick_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_col.add_child(quick_gap)

	## Quick tight under stage.
	_quick_box = VBoxContainer.new()
	_quick_box.custom_minimum_size = Vector2(PREVIEW_COL_W, 0)
	_quick_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_quick_box.size_flags_vertical = Control.SIZE_SHRINK_END
	_quick_box.add_theme_constant_override("separation", 0)
	_left_col.add_child(_quick_box)
	_quick_box.add_child(_caption("БЫСТРЫЙ ДОСТУП", 8))
	var quick_row := HBoxContainer.new()
	quick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	quick_row.add_theme_constant_override("separation", QUICK_ROW_SEP)
	_quick_box.add_child(quick_row)
	_quick_btns.clear()
	for i in range(QUICK_COUNT):
		var qb := _make_equip_slot("quick_%d" % i, QUICK_SLOT)
		_quick_btns.append(qb)
		quick_row.add_child(qb)

	# Right column: title + bag — shrink so no void under the bag frame.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right.add_theme_constant_override("separation", 0)
	body.add_child(right)

	var bag_header := Control.new()
	bag_header.custom_minimum_size = Vector2(0, HEADER_H)
	bag_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(bag_header)
	var bag_title := Label.new()
	bag_title.text = "Инвентарь"
	bag_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	bag_title.add_theme_font_size_override("font_size", 12)
	bag_title.add_theme_color_override("font_color", COL_TITLE)
	bag_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bag_title.offset_bottom = -3.0 ## same gap under title as under nick
	bag_header.add_child(bag_title)

	_bag_panel = PanelContainer.new()
	_bag_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## Height hugs 4×5 grid — do not expand into empty void under cells.
	_bag_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_bag_panel.add_theme_stylebox_override("panel", _panel_style(
		COL_BAG_BG,
		COL_BAG_BORDER,
		1, 0
	))
	right.add_child(_bag_panel)

	var bag_vbox := VBoxContainer.new()
	bag_vbox.add_theme_constant_override("separation", 2)
	bag_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_bag_panel.add_child(bag_vbox)

	_bag_drop_zone = ZZInvDragItem.new()
	_bag_drop_zone.host = self
	_bag_drop_zone.accept_slot = ""
	_bag_drop_zone.from_slot = ""
	_bag_drop_zone.item_id = ""
	_bag_drop_zone.flat = true
	_bag_drop_zone.focus_mode = Control.FOCUS_NONE
	_bag_drop_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_drop_zone.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_transparent_btn(_bag_drop_zone)
	bag_vbox.add_child(_bag_drop_zone)

	_bag_margin = MarginContainer.new()
	_bag_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bag_margin.add_theme_constant_override("margin_left", BAG_PAD)
	_bag_margin.add_theme_constant_override("margin_top", BAG_PAD)
	_bag_margin.add_theme_constant_override("margin_right", BAG_PAD)
	_bag_margin.add_theme_constant_override("margin_bottom", BAG_PAD)
	_bag_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_drop_zone.add_child(_bag_margin)

	_bag_scroll = ScrollContainer.new()
	_bag_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_bag_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bag_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_bag_scroll.clip_contents = true
	_bag_margin.add_child(_bag_scroll)
	_style_thin_scrollbar(_bag_scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", CELL_SEP)
	_grid.add_theme_constant_override("v_separation", CELL_SEP)
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_bag_scroll.add_child(_grid)

	# Weight inside bag frame — compact footer, same right inset as the grid.
	var weight_pad := MarginContainer.new()
	weight_pad.add_theme_constant_override("margin_left", BAG_PAD)
	weight_pad.add_theme_constant_override("margin_right", BAG_PAD)
	weight_pad.add_theme_constant_override("margin_top", 0)
	weight_pad.add_theme_constant_override("margin_bottom", BAG_PAD)
	bag_vbox.add_child(weight_pad)
	var weight_row := HBoxContainer.new()
	weight_row.alignment = BoxContainer.ALIGNMENT_END
	weight_row.add_theme_constant_override("separation", 3)
	weight_pad.add_child(weight_row)
	var weight_cap := Label.new()
	weight_cap.text = "Вес"
	weight_cap.add_theme_font_size_override("font_size", 9)
	weight_cap.add_theme_color_override("font_color", COL_LABEL)
	weight_row.add_child(weight_cap)
	_weight_label = Label.new()
	_weight_label.add_theme_font_size_override("font_size", 10)
	_weight_label.add_theme_color_override("font_color", COL_TITLE)
	_weight_label.text = "0 / 50 ед."
	weight_row.add_child(_weight_label)

	## Close on shell corner — visible hover (not fully transparent).
	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.pressed.connect(close)
	_close_btn.custom_minimum_size = Vector2(22, 22)
	_style_close_btn(_close_btn)
	_close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_close_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_close_btn.grow_vertical = Control.GROW_DIRECTION_END
	_close_btn.offset_left = -28.0
	_close_btn.offset_right = -4.0
	_close_btn.offset_top = 2.0
	_close_btn.offset_bottom = 22.0
	_shell.add_child(_close_btn)

	## Rebuild grid after layout has real sizes; fit shell to left column height.
	call_deferred("_fit_shell_to_left")
	call_deferred("_refresh_grid")
	call_deferred("_refresh_grid")
	resized.connect(func():
		if visible:
			call_deferred("_fit_shell_to_left")
			call_deferred("_refresh_grid")
			call_deferred("_refresh_grid")
	)


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_preview_dragging = mb.pressed
			_preview_host.accept_event()
	elif event is InputEventMouseMotion and _preview_dragging:
		var mm := event as InputEventMouseMotion
		if _preview_pivot != null and is_instance_valid(_preview_pivot):
			_preview_pivot.rotation.y -= mm.relative.x * PREVIEW_YAW_SENS
		_preview_host.accept_event()


func _reset_preview_yaw() -> void:
	if _preview_pivot != null and is_instance_valid(_preview_pivot):
		_preview_pivot.rotation = Vector3.ZERO
	_preview_dragging = false


func _style_thin_scrollbar(scroll: ScrollContainer) -> void:
	var sb := scroll.get_v_scroll_bar()
	if sb == null:
		return
	sb.custom_minimum_size.x = SCROLL_W
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.42, 0.45, 0.50, 0.75)
	grab.set_corner_radius_all(2)
	grab.content_margin_left = 0
	grab.content_margin_right = 0
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.10, 0.105, 0.12, 0.55)
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
	## Cool charcoal like STALKER ref — no warm brown tint.
	s.bg_color = Color(0.102, 0.106, 0.118, 1.0) # ~#1A1B1E
	s.border_color = Color(0.208, 0.227, 0.251, 1.0) # ~#353A40 slate
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
	hover.bg_color = Color(0.145, 0.152, 0.168, 1.0)
	hover.border_color = Color(0.45, 0.48, 0.52, 1.0)
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


func _style_close_btn(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("focus", empty)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.14)
	hover.set_corner_radius_all(3)
	hover.content_margin_left = 2
	hover.content_margin_right = 2
	hover.content_margin_top = 1
	hover.content_margin_bottom = 1
	b.add_theme_stylebox_override("hover", hover)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1.0, 1.0, 1.0, 0.22)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", COL_TITLE)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.55))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	b.add_theme_font_size_override("font_size", 15)


func _bag_inner_size() -> Vector2:
	if _bag_scroll != null and _bag_scroll.size.x > 8.0 and _bag_scroll.size.y > 8.0:
		return _bag_scroll.size
	if _bag_panel != null and _bag_panel.size.x > 8.0:
		## Subtract weight row + equal pads so 5 rows are not sized into the footer.
		return Vector2(
			_bag_panel.size.x - float(BAG_PAD * 2) - 2.0,
			maxi(100.0, _bag_panel.size.y - float(BAG_PAD * 2) - float(WEIGHT_ROW_H) - 4.0)
		)
	return Vector2(280, 240)


func _cell_px() -> int:
	## Fixed size — bag height is fitted to the grid, not the other way around.
	return CELL_FIXED


func _grid_pixel_size() -> Vector2i:
	var side := CELL_FIXED
	return Vector2i(
		side * GRID_COLS + CELL_SEP * (GRID_COLS - 1),
		side * GRID_ROWS + CELL_SEP * (GRID_ROWS - 1)
	)


func _bag_content_size() -> Vector2:
	## Exact bag outer size for 4×5 @ CELL_FIXED + equal pads + weight row.
	var g := _grid_pixel_size()
	var w := float(g.x + BAG_PAD * 2 + 2)
	var h := float(BAG_PAD + g.y + BAG_PAD + 2 + WEIGHT_ROW_H + BAG_PAD)
	return Vector2(w, h)


func _sync_bag_equal_pads() -> void:
	## Keep left = right = top = bottom (BAG_PAD) around the grid.
	if _bag_margin == null:
		return
	_bag_margin.add_theme_constant_override("margin_left", BAG_PAD)
	_bag_margin.add_theme_constant_override("margin_right", BAG_PAD)
	_bag_margin.add_theme_constant_override("margin_top", BAG_PAD)
	_bag_margin.add_theme_constant_override("margin_bottom", BAG_PAD)


func _visible_rows(_side: int) -> int:
	return GRID_ROWS


func _cell_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.102, 0.106, 0.118, 0.98)
	s.border_color = Color(0.208, 0.227, 0.251, 1.0)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	return s


func _fit_shell_to_left() -> void:
	## Bag is authority (fixed 4×5). Preview height fills so left bottom = bag bottom — no voids.
	if _shell == null or _left_col == null:
		return
	var bag := _bag_content_size()
	_apply_bag_fixed_size()

	var quick_h := float(QUICK_SLOT.y + 12)
	if _quick_box != null:
		quick_h = maxf(quick_h, _quick_box.get_combined_minimum_size().y)
	var stage_h := bag.y - float(QUICK_SEP) - quick_h
	var eh := 0.0
	if _equip_col != null:
		eh = maxf(_equip_col.get_combined_minimum_size().y, _equip_col.size.y)
	if eh >= 32.0:
		stage_h = maxf(stage_h, eh)
	if _preview_panel != null and stage_h >= 32.0:
		_preview_panel.custom_minimum_size = Vector2(PREVIEW_COL_W, stage_h)
		if _preview_host != null:
			_preview_host.custom_minimum_size = Vector2(PREVIEW_COL_W - 4.0, maxf(8.0, stage_h - 4.0))

	var left_w := _left_col.get_combined_minimum_size().x
	if left_w < 8.0:
		left_w = maxf(_left_col.size.x, PREVIEW_COL_W + 8.0 + EQUIP_SLOT.x)
	var left_h := float(HEADER_H) + stage_h + float(QUICK_SEP) + quick_h
	var right_h := float(HEADER_H) + bag.y
	## Prefer bag height; only grow if equip column truly needs more.
	var h := maxf(left_h, right_h) + 12.0
	var w := 16.0 + left_w + 8.0 + bag.x
	w = minf(w, SHELL_W)
	_shell.custom_minimum_size = Vector2(w, h)
	_shell.size = Vector2(w, h)


func _apply_bag_fixed_size() -> void:
	## Lock bag + scroll to exact 4×5 @ CELL_FIXED.
	if _bag_panel == null:
		return
	var bag := _bag_content_size()
	var g := _grid_pixel_size()
	_bag_panel.custom_minimum_size = bag
	_bag_panel.size = Vector2(bag.x, bag.y)
	if _bag_drop_zone != null:
		var zone_h := float(BAG_PAD + g.y + BAG_PAD)
		_bag_drop_zone.custom_minimum_size = Vector2(0.0, zone_h)
	if _bag_scroll != null:
		_bag_scroll.custom_minimum_size = Vector2(float(g.x), float(g.y))


func _bind_preview_texture() -> void:
	if _preview_rect == null or _preview_vp == null:
		return
	_preview_vp.size = PREVIEW_RT
	_preview_rect.texture = _preview_vp.get_texture()


func _ensure_preview() -> void:
	if _preview_vp == null:
		return
	if _unit != null and is_instance_valid(_unit):
		return
	for c in _preview_vp.get_children():
		c.queue_free()
	_preview_vp.positional_shadow_atlas_size = 2048
	var world := Node3D.new()
	_preview_vp.add_child(world)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.038, 0.045, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.50, 0.54)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	world.add_child(env_node)
	## Key from the side — frontal light blew out the jacket/helmet.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 70, 0)
	key.light_color = Color(1.0, 0.96, 0.90)
	key.light_energy = 1.15
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -100, 0)
	fill.light_color = Color(0.70, 0.76, 0.90)
	fill.light_energy = 0.40
	world.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-5, 160, 0)
	rim.light_energy = 0.35
	world.add_child(rim)
	## Pivot: drag-yaw; reset to 0 every inventory open.
	_preview_pivot = Node3D.new()
	_preview_pivot.name = "PreviewPivot"
	_preview_pivot.position = Vector3(0.0, PREVIEW_PIVOT_Y, 0.0)
	world.add_child(_preview_pivot)
	_preview_pivot.add_child(_make_preview_platform())
	_unit = ZZUnitView.new()
	_preview_pivot.add_child(_unit)
	## Feet on pedestal top (sink so boots plant on the slab).
	_unit.position = Vector3(0.0, PREVIEW_PLATFORM_H - PREVIEW_UNIT_SINK, 0.0)
	_unit.setup("preview", _nick if _nick != "" else "—", Color(0.55, 0.5, 0.42))
	if _unit.get_node_or_null("UnitUI") != null:
		_unit.get_node("UnitUI").visible = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 30.0
	## Camera fixed — raised pivot puts pedestal+unit higher in the pane.
	cam.position = Vector3(0.0, 1.35, 5.6)
	cam.current = true
	world.add_child(cam)
	cam.look_at(Vector3(0.0, 1.45, 0.0), Vector3.UP)
	_reset_preview_yaw()


func _make_preview_platform() -> Node3D:
	## Dark metal pedestal (v6). Real directional shadow only — no fake blob.
	var root := Node3D.new()
	root.name = "Pedestal"
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = PREVIEW_PLATFORM_SIZE
	body.mesh = box
	body.position = Vector3(0.0, PREVIEW_PLATFORM_H * 0.5, 0.0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.105, 0.12)
	mat.metallic = 0.45
	mat.roughness = 0.72
	body.material_override = mat
	root.add_child(body)
	return root


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

	_sync_bag_equal_pads()
	var side := _cell_px()
	var rows := _visible_rows(side)
	var need := maxi(GRID_COLS * rows, int(ceil(float(cells.size()) / float(GRID_COLS))) * GRID_COLS)
	var sz := Vector2(side, side)
	## Bag + shell width/height locked to fixed 4×5 (no empty strip under cells).
	_apply_bag_fixed_size()
	if _shell != null and _left_col != null:
		var bag := _bag_content_size()
		var left_w := maxf(_left_col.get_combined_minimum_size().x, _left_col.size.x)
		var shell_w := minf(16.0 + left_w + 8.0 + bag.x, SHELL_W)
		_shell.custom_minimum_size.x = shell_w
		_shell.size.x = shell_w

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
	return ZZItemTooltip.build(item_id, qty)


## Trim trailing zeros: 49.6, 50, 0.012 — never "50.0" / "0.100".
func _fmt_num(v: float) -> String:
	return ZZItemTooltip.fmt_num(v)


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


func notify_item_drag_started() -> void:
	_item_dragging = true
	set_process(true)
	_apply_drag_cursor()
	## Let drops fall through chrome to this root (accepts drag → no forbidden cursor).
	if _dim != null:
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shell != null:
		_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _close_btn != null:
		_close_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _preview_host != null:
		_preview_host.mouse_filter = Control.MOUSE_FILTER_IGNORE


func notify_item_drag_ended() -> void:
	_item_dragging = false
	set_process(false)
	_clear_drag_cursor()
	if _dim != null:
		_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	if _shell != null:
		_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	if _close_btn != null:
		_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if _preview_host != null:
		_preview_host.mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	## Viewport forces CAN_DROP/FORBIDDEN during DnD — re-assert grab cursor every frame.
	if _item_dragging:
		DisplayServer.cursor_set_shape(DisplayServer.CURSOR_DRAG)


func _ensure_drag_cursor_tex() -> Texture2D:
	if _drag_cursor_tex != null:
		return _drag_cursor_tex
	## Tiny grab-hand so DRAG / CAN_DROP / FORBIDDEN all look the same.
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(0.95, 0.95, 0.97, 1.0)
	var edge := Color(0.08, 0.08, 0.10, 1.0)
	## Palm
	for y in range(12, 24):
		for x in range(6, 20):
			img.set_pixel(x, y, ink)
	## Fingers (closed fist bumps)
	for x in [7, 11, 15, 19]:
		for y in range(6, 14):
			img.set_pixel(x, y, ink)
			img.set_pixel(x + 1, y, ink)
	## Outline
	for y in range(28):
		for x in range(28):
			if img.get_pixel(x, y).a < 0.5:
				continue
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if nx < 0 or ny < 0 or nx >= 28 or ny >= 28:
						continue
					if img.get_pixel(nx, ny).a < 0.5:
						img.set_pixel(nx, ny, edge)
	_drag_cursor_tex = ImageTexture.create_from_image(img)
	return _drag_cursor_tex


func _apply_drag_cursor() -> void:
	## Godot DnD never keeps CURSOR_DRAG — it switches to CAN_DROP/FORBIDDEN.
	## Bind the same grab texture to all three so the hand always shows.
	var tex := _ensure_drag_cursor_tex()
	var hot := Vector2(6, 4)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_DRAG, hot)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_CAN_DROP, hot)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_FORBIDDEN, hot)
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	DisplayServer.cursor_set_shape(DisplayServer.CURSOR_DRAG)


func _clear_drag_cursor() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_DRAG)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_CAN_DROP)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_FORBIDDEN)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	## Whole inventory accepts drag for cursor purposes; drop may no-op.
	return typeof(data) == TYPE_DICTIONARY and str(data.get("item_id", "")) != ""


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	## Drop on chrome / empty areas: unequip back to bag if that was the intent.
	if can_drop_on_bag(data):
		drop_on_bag(data)


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
	var swapped_back := ""
	if from_slot != "":
		## Slot ↔ slot: swap when the displaced item fits the source slot.
		if (
			_is_quick_slot(from_slot)
			or from_slot == "primary"
			or from_slot == "secondary"
			or from_slot == "armor"
		):
			var swap_ok := true
			if prev != "":
				var fake := {"item_id": prev, "from_slot": ""}
				swap_ok = can_drop_on_slot(from_slot, fake)
			if swap_ok and prev != "":
				_set_slot_item(from_slot, prev)
				swapped_back = prev
			else:
				_set_slot_item(from_slot, "")
	## From bag onto occupied slot: prev leaves the slot and reappears in the bag grid.
	_refresh()
	equip_requested.emit(item_id, slot_name)
	if swapped_back != "":
		equip_requested.emit(swapped_back, from_slot)


func drop_on_bag_target(target_id: String, data: Variant) -> void:
	## Drop onto an occupied bag cell: bag↔bag swap, or slot↔bag swap if types allow.
	if typeof(data) != TYPE_DICTIONARY:
		return
	var item_id := str(data.get("item_id", ""))
	var from_slot := str(data.get("from_slot", ""))
	if item_id == "" or target_id == "" or item_id == target_id:
		return
	if from_slot == "":
		_swap_bag_stacks(item_id, target_id)
		_refresh()
		return
	## Equip/quick → bag item: put bag item into the source slot if it fits.
	var fake := {"item_id": target_id, "from_slot": ""}
	if not can_drop_on_slot(from_slot, fake):
		drop_on_bag(data)
		return
	_set_slot_item(from_slot, target_id)
	_refresh()
	equip_requested.emit(target_id, from_slot)


func drop_on_bag(data: Variant) -> void:
	if not can_drop_on_bag(data):
		return
	var from_slot := str(data.get("from_slot", ""))
	_set_slot_item(from_slot, "")
	_refresh()
	unequip_requested.emit(from_slot)


func _swap_bag_stacks(id_a: String, id_b: String) -> void:
	## Reorder two stacks in the local inventory list (visual swap in the grid).
	var ia := -1
	var ib := -1
	for i in range(_inventory.size()):
		var s: Variant = _inventory[i]
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var id := str(s.get("item_id", ""))
		if id == id_a and ia < 0:
			ia = i
		elif id == id_b and ib < 0:
			ib = i
	if ia < 0 or ib < 0 or ia == ib:
		return
	var tmp: Variant = _inventory[ia]
	_inventory[ia] = _inventory[ib]
	_inventory[ib] = tmp


## For battle HUD later.
func get_quick_slots() -> Array:
	return _quick.duplicate()
