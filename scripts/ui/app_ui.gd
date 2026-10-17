extends CanvasLayer
class_name ZZAppUI

signal continue_pressed(nick: String)
signal find_match_pressed
signal end_turn_pressed
signal undo_pressed
signal posture_pressed(posture: String)
signal medkit_pressed
signal reload_pressed
signal weapon_slot_pressed(slot_index: int)
signal chat_submitted(text: String, channel: String)
signal return_to_lobby_pressed

const TAB_LOBBY := 0
const TAB_BATTLE := 1
const CHAT_W := 420.0
const CHAT_H := 150.0
const CHAT_COLLAPSED_H := 36.0
const PLAN_W := 160.0
const SOCIAL_EDGE := 8.0
const CHAT_FADE_IDLE_SEC := 7.0
const CHAT_FADE_DUR := 0.45

var player_nick: String = ""
var _in_battle_ui: bool = false
var _chat_history_visible: bool = true
var _chat_fade_tween: Tween
var _chat_idle_timer: Timer
var _battle_turn: int = 1
var _battle_timer_text: String = "0:30"
var _max_hp: int = 100
var _max_ap: int = 10
var _ammo_in_mag: int = 0
var _ammo_reserve: int = 0
var _reload_cost: int = 6
var _shoot_cost: int = 3
var _medkit_count: int = 5
var _active_posture: String = "stand"
var _reload_can_use: bool = false
var _medkit_can_use: bool = false
var _switch_weapon_cost: int = 1
var _switch_look_ok: bool = true
var _active_weapon_look_ok: bool = true
var _active_weapon_idx: int = 0
var _weapon_slots: Array = [] # Dictionaries: id, shoot_ap, reload_ap, ammo_in_mag, ammo_reserve
var _weapon2_btn: Button
const ACTION_DIM := Color(1, 1, 1, 0.45)

@onready var login_screen: Control = $LoginScreen
@onready var lobby_screen: Control = $LobbyScreen
@onready var battle_hud: Control = $BattleHud
@onready var chat_dock: PanelContainer = $ChatDock
@onready var plan_dock: PanelContainer = $PlanDock

@onready var nick_edit: LineEdit = $LoginScreen/Center/Panel/Margin/InnerCenter/VBox/NickEdit
@onready var continue_btn: Button = $LoginScreen/Center/Panel/Margin/InnerCenter/VBox/ContinueBtn
@onready var login_error: Label = $LoginScreen/Center/Panel/Margin/InnerCenter/VBox/ErrorLabel

@onready var lobby_nick: Label = $LobbyScreen/PlayerCard/VBox/CardTitle
@onready var lobby_level: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/LevelLabel
@onready var lobby_str: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/StrLabel
@onready var lobby_agi: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/AgiLabel
@onready var lobby_end: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/EndLabel
@onready var lobby_intu: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/IntuLabel
@onready var lobby_acc: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/AccLabel
@onready var lobby_int: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/IntLabel
@onready var lobby_hp: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/HPLabel
@onready var lobby_ap: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/APLabel
@onready var lobby_carry: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/CarryLabel
@onready var find_btn: Button = $LobbyScreen/FindCenter/FindBtn

@onready var chat_tabs: TabContainer = $ChatDock/Margin/MainRow/ChatCol/Tabs
@onready var lobby_chat_log: RichTextLabel = $ChatDock/Margin/MainRow/ChatCol/Tabs/Лобби
@onready var battle_chat_log: RichTextLabel = $ChatDock/Margin/MainRow/ChatCol/Tabs/Бой
@onready var chat_input_frame: PanelContainer = $ChatDock/Margin/MainRow/ChatCol/InputFrame
@onready var chat_edit: LineEdit = $ChatDock/Margin/MainRow/ChatCol/InputFrame/InputRow/ChatEdit
@onready var chat_send_btn: Button = $ChatDock/Margin/MainRow/ChatCol/InputFrame/InputRow/SendBtn
@onready var players_col: VBoxContainer = $ChatDock/Margin/MainRow/PlayersCol
@onready var room_list: ItemList = $ChatDock/Margin/MainRow/PlayersCol/PlayerList

@onready var turn_bar: PanelContainer = $BattleHud/TurnBar
@onready var char_dock: PanelContainer = $BattleHud/CharDock
@onready var battle_turn_timer: Label = $BattleHud/TurnBar/VBox/TurnTimerLabel
@onready var end_btn: Button = $BattleHud/TurnBar/VBox/EndBtn
@onready var stand_btn: Button = $BattleHud/CharDock/VBox/ActionRow/QuickGrid/StandBtn
@onready var sit_btn: Button = $BattleHud/CharDock/VBox/ActionRow/QuickGrid/SitBtn
@onready var run_btn: Button = $BattleHud/CharDock/VBox/ActionRow/QuickGrid/RunBtn
@onready var cover_btn: Button = $BattleHud/CharDock/VBox/ActionRow/QuickGrid/CoverBtn
@onready var undo_btn: Button = $BattleHud/CharDock/VBox/TitleRow/UndoBtn
@onready var medkit_btn: Button = $BattleHud/CharDock/VBox/ActionRow/MedkitBtn
@onready var medkit_icon: TextureRect = $BattleHud/CharDock/VBox/ActionRow/MedkitBtn/Icon
@onready var medkit_cost_label: Label = $BattleHud/CharDock/VBox/ActionRow/MedkitBtn/CostLabel
@onready var medkit_count_label: Label = $BattleHud/CharDock/VBox/ActionRow/MedkitBtn/CountLabel
@onready var reload_btn: Button = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn
@onready var rifle_icon: TextureRect = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/RifleIcon
@onready var reload_icon: TextureRect = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/ReloadRow/ReloadIcon
@onready var reload_cost_label: Label = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/ReloadRow/ReloadCostLabel
@onready var shot_cost_label: Label = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/ShotCostLabel
@onready var ammo_col: HBoxContainer = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/AmmoRow/AmmoCol
@onready var ammo_count_label: Label = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/AmmoRow/AmmoCountLabel
@onready var history_list: ItemList = $PlanDock/Margin/VBox/HistoryList
@onready var battle_nick: Label = $BattleHud/CharDock/VBox/TitleRow/CardTitle
@onready var battle_hp_bar: ProgressBar = $BattleHud/CharDock/VBox/HPRow/HPBar
@onready var battle_hp_value: Label = $BattleHud/CharDock/VBox/HPRow/HPValue
@onready var battle_ap_bar: ProgressBar = $BattleHud/CharDock/VBox/APRow/APBar
@onready var battle_ap_value: Label = $BattleHud/CharDock/VBox/APRow/APValue

var _bullet_tex: Texture2D
var _mag_size: int = 6

@onready var result_overlay: Control = $BattleHud/ResultOverlay
@onready var result_label: Label = $BattleHud/ResultOverlay/Center/Panel/VBox/ResultLabel
@onready var lobby_btn: Button = $BattleHud/ResultOverlay/Center/Panel/VBox/LobbyBtn


func _ready() -> void:
	continue_btn.pressed.connect(_on_continue)
	nick_edit.text_submitted.connect(func(_t): _on_continue())
	find_btn.pressed.connect(func(): find_match_pressed.emit())
	end_btn.pressed.connect(func(): end_turn_pressed.emit())
	undo_btn.pressed.connect(func(): undo_pressed.emit())
	stand_btn.pressed.connect(func(): posture_pressed.emit("stand"))
	sit_btn.pressed.connect(func(): posture_pressed.emit("sit"))
	run_btn.pressed.connect(func(): posture_pressed.emit("run"))
	cover_btn.pressed.connect(func(): posture_pressed.emit("cover"))
	medkit_btn.pressed.connect(_on_medkit_pressed)
	reload_btn.pressed.connect(func(): weapon_slot_pressed.emit(0))
	_ensure_weapon2_btn()
	lobby_btn.pressed.connect(func(): return_to_lobby_pressed.emit())
	chat_send_btn.pressed.connect(_on_chat_send)
	chat_edit.text_submitted.connect(func(_t): _on_chat_send())
	chat_tabs.tab_changed.connect(_on_chat_tab_changed)
	chat_edit.focus_entered.connect(_reveal_chat_history)
	chat_dock.gui_input.connect(_on_chat_dock_gui_input)
	end_btn.disabled = true
	undo_btn.disabled = true
	result_overlay.visible = false
	_apply_hud_icons()
	# Keep social UI above full-screen lobby/battle layers.
	chat_dock.z_index = 100
	plan_dock.z_index = 100
	move_child(chat_dock, get_child_count() - 1)
	move_child(plan_dock, get_child_count() - 1)
	lobby_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	plan_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_setup_chat_fade_timer()
	_make_chat_tabs_transparent()
	show_login()


func _make_chat_tabs_transparent() -> void:
	if chat_tabs == null:
		return
	var empty := StyleBoxEmpty.new()
	chat_tabs.add_theme_stylebox_override("panel", empty)
	var tab := StyleBoxFlat.new()
	tab.bg_color = Color(0.1, 0.1, 0.12, 0.35)
	tab.set_corner_radius_all(2)
	tab.content_margin_left = 6
	tab.content_margin_right = 6
	tab.content_margin_top = 2
	tab.content_margin_bottom = 2
	chat_tabs.add_theme_stylebox_override("tab_selected", tab)
	var tab_un := tab.duplicate()
	tab_un.bg_color = Color(0.08, 0.08, 0.09, 0.2)
	chat_tabs.add_theme_stylebox_override("tab_unselected", tab_un)
	for log in [lobby_chat_log, battle_chat_log]:
		if log == null:
			continue
		log.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		log.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9, 0.92))


func _unhandled_input(event: InputEvent) -> void:
	if not chat_dock.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_reveal_chat_history()
			if chat_edit.editable and not chat_edit.has_focus():
				chat_edit.grab_focus()
			get_viewport().set_input_as_handled()


func _setup_chat_fade_timer() -> void:
	_chat_idle_timer = Timer.new()
	_chat_idle_timer.wait_time = CHAT_FADE_IDLE_SEC
	_chat_idle_timer.one_shot = true
	_chat_idle_timer.timeout.connect(_fade_chat_history)
	add_child(_chat_idle_timer)


func _on_chat_dock_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_reveal_chat_history()


func show_login() -> void:
	login_screen.visible = true
	lobby_screen.visible = false
	battle_hud.visible = false
	_set_social_visible(false)
	_in_battle_ui = false
	login_error.text = ""
	nick_edit.grab_focus()


func show_lobby() -> void:
	login_screen.visible = false
	lobby_screen.visible = true
	battle_hud.visible = false
	result_overlay.visible = false
	lobby_nick.text = player_nick
	refresh_lobby_stats_from_rules()
	find_btn.text = "Найти бой"
	set_find_enabled(false)
	_set_room_players([player_nick])
	_apply_social_context(false)
	chat_edit.grab_focus()


func show_battle() -> void:
	login_screen.visible = false
	lobby_screen.visible = false
	battle_hud.visible = true
	result_overlay.visible = false
	battle_nick.text = player_nick
	if battle_chat_log != null:
		battle_chat_log.clear()
	_apply_social_context(true)


func show_battle_result(won: bool) -> void:
	battle_hud.visible = true
	result_overlay.visible = true
	result_label.text = "Победа" if won else "Поражение"
	end_btn.disabled = true
	lobby_btn.grab_focus()


func set_find_enabled(enabled: bool) -> void:
	find_btn.disabled = not enabled
	if enabled:
		find_btn.text = "Найти бой"


func set_searching(searching: bool) -> void:
	if searching:
		find_btn.disabled = true
		find_btn.text = "Поиск..."
	else:
		set_find_enabled(true)


func set_room_players(nicks: Array) -> void:
	_set_room_players(nicks)


func append_chat(nick: String, text: String, channel: String = "lobby") -> void:
	var t := Time.get_datetime_dict_from_system()
	var stamp := "%02d:%02d" % [int(t.hour), int(t.minute)]
	var line := "[color=#9aa]%s[/color]  %s: %s\n" % [stamp, nick, text]
	if channel == "battle":
		if battle_chat_log != null:
			battle_chat_log.append_text(line)
	else:
		if lobby_chat_log != null:
			lobby_chat_log.append_text(line)
	_reveal_chat_history()


func set_turn(turn: int) -> void:
	_battle_turn = turn
	_refresh_turn_timer()


func set_timer_seconds(seconds: float) -> void:
	var s := maxi(0, int(ceil(seconds)))
	_battle_timer_text = "%d:%02d" % [s / 60, s % 60]
	_refresh_turn_timer()


func set_vital_caps(max_hp: int, max_ap: int) -> void:
	_max_hp = maxi(1, max_hp)
	_max_ap = maxi(1, max_ap)
	if battle_hp_bar != null:
		battle_hp_bar.max_value = float(_max_hp)
	if battle_ap_bar != null:
		battle_ap_bar.max_value = float(_max_ap)


func set_shoot_cost(ap_cost: int) -> void:
	_shoot_cost = maxi(0, ap_cost)
	_refresh_weapon_slot()


func set_mag_size(mag_size: int) -> void:
	_mag_size = maxi(1, mag_size)
	_refresh_weapon_slot()


func refresh_lobby_stats_from_rules() -> void:
	if not ZZLos.has_rules():
		_set_lobby_stats_placeholder()
		return
	var lvl := ZZLos.rule_i("default_level")
	var s := ZZLos.default_stat()
	var carry := ZZLos.compute_carry_weight(s)
	var inv_w := ZZLos.compute_loadout_weight()
	var ap := ZZLos.compute_effective_max_ap(s, s, s)
	lobby_level.text = "Уровень: %d" % lvl
	lobby_str.text = "Сила: %d" % s
	lobby_agi.text = "Ловкость: %d" % s
	lobby_end.text = "Выносливость: %d" % s
	lobby_intu.text = "Интуиция: %d" % s
	lobby_acc.text = "Меткость: %d" % s
	lobby_int.text = "Интеллект: %d" % s
	lobby_hp.text = "ХП: %d" % ZZLos.compute_max_hp(s)
	lobby_ap.text = "ОД: %d" % ap
	if inv_w > float(carry):
		lobby_carry.text = "Вес: %.1f/%d (перегруз)" % [inv_w, carry]
	else:
		lobby_carry.text = "Вес: %.1f/%d" % [inv_w, carry]


func _set_lobby_stats_placeholder() -> void:
	lobby_level.text = "Уровень: —"
	lobby_str.text = "Сила: —"
	lobby_agi.text = "Ловкость: —"
	lobby_end.text = "Выносливость: —"
	lobby_intu.text = "Интуиция: —"
	lobby_acc.text = "Меткость: —"
	lobby_int.text = "Интеллект: —"
	lobby_hp.text = "ХП: —"
	lobby_ap.text = "ОД: —"
	lobby_carry.text = "Вес: —"


func set_ap(value: int) -> void:
	var ap := maxi(0, value)
	if battle_ap_bar != null:
		battle_ap_bar.max_value = float(_max_ap)
		battle_ap_bar.value = float(ap)
	if battle_ap_value != null:
		battle_ap_value.text = "%d / %d" % [ap, _max_ap]


func set_hp(value: int) -> void:
	var hp := maxi(0, value)
	if battle_hp_bar != null:
		battle_hp_bar.max_value = float(_max_hp)
		battle_hp_bar.value = float(hp)
	if battle_hp_value != null:
		battle_hp_value.text = "%d / %d" % [hp, _max_hp]


func set_posture(posture: String) -> void:
	_active_posture = posture
	_refresh_posture_highlight()


func set_history(lines: Array) -> void:
	if history_list == null:
		return
	history_list.clear()
	for line in lines:
		var idx := history_list.add_item(str(line))
		history_list.set_item_selectable(idx, false)
	if not lines.is_empty():
		history_list.select(lines.size() - 1)
		history_list.ensure_current_is_visible()
	if plan_dock != null and _in_battle_ui:
		plan_dock.visible = true


func set_end_enabled(enabled: bool) -> void:
	end_btn.disabled = not enabled
	stand_btn.disabled = not enabled
	sit_btn.disabled = not enabled
	run_btn.disabled = not enabled
	cover_btn.disabled = not enabled


func set_medkit_enabled(enabled: bool) -> void:
	set_medkit_affordance(enabled, enabled)


func set_reload_enabled(enabled: bool) -> void:
	set_reload_affordance(enabled, enabled)


func set_medkit_affordance(can_press: bool, look_affordable: bool) -> void:
	# Do not use Button.disabled for dim — disabled StyleBox == normal (no visible gray).
	_medkit_can_use = can_press
	if medkit_btn != null:
		medkit_btn.disabled = false
		medkit_btn.modulate = Color.WHITE if look_affordable else ACTION_DIM


func set_reload_affordance(can_press: bool, look_affordable: bool) -> void:
	# Full mag: can_press=false, look_affordable=true if AP enough (panel must not look “no AP”).
	_reload_can_use = can_press
	_active_weapon_look_ok = look_affordable
	_refresh_weapon_slot_modulate()


func set_switch_weapon_affordance(look_ok: bool) -> void:
	_switch_look_ok = look_ok
	_refresh_weapon_slot_modulate()


func set_weapons(weapons: Array, active_idx: int, switch_ap: int = 1) -> void:
	_weapon_slots = weapons.duplicate()
	_active_weapon_idx = clampi(active_idx, 0, maxi(0, _weapon_slots.size() - 1))
	_switch_weapon_cost = maxi(0, switch_ap)
	if _weapon2_btn != null:
		_weapon2_btn.visible = _weapon_slots.size() >= 2
	_apply_weapon_slot_visuals()


func set_medkit_count(count: int, heal_min: int = 15, heal_max: int = 30, ap_cost: int = 3) -> void:
	_medkit_count = maxi(0, count)
	if medkit_count_label != null:
		medkit_count_label.text = "%d шт." % _medkit_count
	if medkit_cost_label != null:
		medkit_cost_label.text = "%d ОД" % ap_cost
	medkit_btn.tooltip_text = "Аптечка +%d–%d ХП / %d ОД" % [heal_min, heal_max, ap_cost]


func set_reload_cost(ap_cost: int) -> void:
	_reload_cost = maxi(0, ap_cost)
	_refresh_weapon_slot()


func set_ammo(in_mag: int, reserve: int) -> void:
	_ammo_in_mag = maxi(0, in_mag)
	_ammo_reserve = maxi(0, reserve)
	_refresh_weapon_slot()


func set_undo_enabled(enabled: bool) -> void:
	undo_btn.disabled = not enabled


func _refresh_turn_timer() -> void:
	if battle_turn_timer != null:
		battle_turn_timer.text = "Ход %d | %s" % [_battle_turn, _battle_timer_text]


func _apply_hud_icons() -> void:
	_bullet_tex = ZZHudIcons.bullet(8)
	stand_btn.icon = ZZHudIcons.posture_stand(32)
	sit_btn.icon = ZZHudIcons.posture_sit(32)
	run_btn.icon = ZZHudIcons.posture_run(32)
	cover_btn.icon = ZZHudIcons.posture_cover(32)
	undo_btn.icon = ZZHudIcons.undo(20)
	stand_btn.expand_icon = true
	sit_btn.expand_icon = true
	run_btn.expand_icon = true
	cover_btn.expand_icon = true
	undo_btn.expand_icon = true
	if medkit_icon != null:
		medkit_icon.texture = ZZHudIcons.medkit(52)
	if rifle_icon != null:
		rifle_icon.texture = ZZHudIcons.rifle(90, 28)
	if reload_icon != null:
		reload_icon.texture = ZZHudIcons.icon_reload(14)
	_apply_weapon_slot_visuals()


func _ensure_weapon2_btn() -> void:
	if reload_btn == null or _weapon2_btn != null:
		return
	reload_btn.custom_minimum_size = Vector2(110, 60)
	_weapon2_btn = reload_btn.duplicate() as Button
	_weapon2_btn.name = "WeaponBtn2"
	_weapon2_btn.custom_minimum_size = Vector2(110, 60)
	reload_btn.get_parent().add_child(_weapon2_btn)
	reload_btn.get_parent().move_child(_weapon2_btn, reload_btn.get_index() + 1)
	_weapon2_btn.pressed.connect(func(): weapon_slot_pressed.emit(1))
	var icon2: TextureRect = _weapon2_btn.get_node_or_null("RifleIcon")
	if icon2 != null:
		icon2.texture = ZZHudIcons.pistol(70, 28)
	var reload_icon2: TextureRect = _weapon2_btn.get_node_or_null("ReloadRow/ReloadIcon")
	if reload_icon2 != null:
		reload_icon2.texture = ZZHudIcons.icon_reload(14)


func _apply_weapon_slot_visuals() -> void:
	_fill_weapon_btn(reload_btn, 0)
	if _weapon2_btn != null:
		_fill_weapon_btn(_weapon2_btn, 1)
	_refresh_weapon_slot_modulate()


func _fill_weapon_btn(btn: Button, slot: int) -> void:
	if btn == null:
		return
	var w: Dictionary = {}
	if slot < _weapon_slots.size() and typeof(_weapon_slots[slot]) == TYPE_DICTIONARY:
		w = _weapon_slots[slot]
	var shoot_ap := int(w.get("shoot_ap", _shoot_cost if slot == _active_weapon_idx else 2))
	var reload_ap := int(w.get("reload_ap", _reload_cost if slot == _active_weapon_idx else 3))
	var in_mag := int(w.get("ammo_in_mag", _ammo_in_mag if slot == _active_weapon_idx else 0))
	var reserve := int(w.get("ammo_reserve", _ammo_reserve if slot == _active_weapon_idx else 0))
	var mag_size := int(w.get("mag_size", 6 if slot == 0 else 10))
	var total := in_mag + reserve
	var wid := str(w.get("id", "rifle" if slot == 0 else "pistol"))
	var shot_lbl: Label = btn.get_node_or_null("ShotCostLabel")
	var reload_lbl: Label = btn.get_node_or_null("ReloadRow/ReloadCostLabel")
	var reload_ic: TextureRect = btn.get_node_or_null("ReloadRow/ReloadIcon")
	var ammo_row: HBoxContainer = btn.get_node_or_null("AmmoRow")
	var ammo_lbl: Label = btn.get_node_or_null("AmmoRow/AmmoCountLabel")
	var icon: TextureRect = btn.get_node_or_null("RifleIcon")
	if shot_lbl != null:
		shot_lbl.text = "ОД: %d (ВЫСТРЕЛ)" % shoot_ap
	if reload_lbl != null:
		reload_lbl.text = "%d ОД" % reload_ap
		reload_lbl.visible = true
	if reload_ic != null:
		reload_ic.texture = ZZHudIcons.icon_reload(14)
		reload_ic.visible = true
	var reload_row: HBoxContainer = btn.get_node_or_null("ReloadRow")
	if reload_row != null:
		reload_row.visible = true
	# Widen ammo strip so all mag ticks + count fit (scene default ~104px clips pistol).
	if ammo_row != null:
		ammo_row.offset_left = -54.0
		ammo_row.offset_right = 54.0
		ammo_row.add_theme_constant_override("separation", 2)
	if ammo_lbl != null:
		ammo_lbl.text = "%d/%d" % [in_mag, total]
	if icon != null:
		icon.texture = ZZHudIcons.rifle(90, 28) if wid == "rifle" else ZZHudIcons.pistol(70, 28)
	var active := slot == _active_weapon_idx
	if active:
		btn.tooltip_text = "Перезарядка (%d ОД) · %d/%d" % [reload_ap, in_mag, total]
	else:
		btn.tooltip_text = "Сменить оружие (%d ОД) · %d/%d" % [_switch_weapon_cost, in_mag, total]
	var col: HBoxContainer = btn.get_node_or_null("AmmoRow/AmmoCol")
	_refresh_ammo_bullets_on(col, in_mag, mag_size)


func _refresh_weapon_slot_modulate() -> void:
	# Active: bright (or dim if no AP for reload). Inactive: always shaded.
	var active_hi := Color(1.0, 0.95, 0.82, 1.0) if _active_weapon_look_ok else ACTION_DIM
	var idle_col := ACTION_DIM if _switch_look_ok else Color(1, 1, 1, 0.28)
	if reload_btn != null:
		reload_btn.disabled = false
		reload_btn.modulate = active_hi if _active_weapon_idx == 0 else idle_col
	if _weapon2_btn != null:
		_weapon2_btn.disabled = false
		_weapon2_btn.modulate = active_hi if _active_weapon_idx == 1 else idle_col


func _refresh_weapon_slot() -> void:
	if _weapon_slots.is_empty():
		if shot_cost_label != null:
			shot_cost_label.text = "ОД: %d (ВЫСТРЕЛ)" % _shoot_cost
		if reload_cost_label != null:
			reload_cost_label.text = "%d ОД" % _reload_cost
		if ammo_count_label != null:
			var total := _ammo_in_mag + _ammo_reserve
			ammo_count_label.text = "%d/%d" % [_ammo_in_mag, total]
		if reload_btn != null:
			reload_btn.tooltip_text = "Перезарядка (%d ОД) · %d/%d" % [
				_reload_cost, _ammo_in_mag, _ammo_in_mag + _ammo_reserve
			]
		_refresh_ammo_bullets_on(ammo_col, _ammo_in_mag, _mag_size)
	else:
		# Keep active slot ammo mirrored for legacy setters.
		if _active_weapon_idx < _weapon_slots.size() and typeof(_weapon_slots[_active_weapon_idx]) == TYPE_DICTIONARY:
			_weapon_slots[_active_weapon_idx]["ammo_in_mag"] = _ammo_in_mag
			_weapon_slots[_active_weapon_idx]["ammo_reserve"] = _ammo_reserve
			_weapon_slots[_active_weapon_idx]["shoot_ap"] = _shoot_cost
			_weapon_slots[_active_weapon_idx]["reload_ap"] = _reload_cost
			_weapon_slots[_active_weapon_idx]["mag_size"] = _mag_size
		_apply_weapon_slot_visuals()


func _refresh_ammo_bullets_on(col: HBoxContainer, in_mag: int, mag_size: int) -> void:
	if col == null:
		return
	if _bullet_tex == null:
		_bullet_tex = ZZHudIcons.bullet(8)
	# One tick per chamber — no cap below mag_size (was clipping pistol visually).
	var need := maxi(1, mag_size)
	var tick_w := 7.0 if need <= 6 else (5.0 if need <= 10 else 4.0)
	col.add_theme_constant_override("separation", 1 if need <= 6 else 0)
	while col.get_child_count() < need:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.texture = _bullet_tex
		col.add_child(tr)
	while col.get_child_count() > need:
		var last := col.get_child(col.get_child_count() - 1)
		col.remove_child(last)
		last.queue_free()
	for i in range(col.get_child_count()):
		var cell: TextureRect = col.get_child(i)
		cell.custom_minimum_size = Vector2(tick_w, 7)
		cell.modulate = Color(1, 1, 1, 1) if i < in_mag else Color(1, 1, 1, 0.22)


func _refresh_posture_highlight() -> void:
	var active := Color(1.0, 0.92, 0.7, 1.0)
	var idle := Color(1, 1, 1, 1)
	stand_btn.modulate = active if _active_posture == "stand" else idle
	sit_btn.modulate = active if _active_posture == "sit" else idle
	run_btn.modulate = active if _active_posture == "run" else idle
	cover_btn.modulate = active if _active_posture == "cover" else idle


## Shared social chrome (chat + room list). Same UI in lobby and battle;
## battle only adds the "Бой" tab.
func _apply_social_context(in_battle: bool) -> void:
	_in_battle_ui = in_battle
	_layout_social()
	_set_social_visible(true)
	_set_battle_tab_visible(in_battle)
	chat_tabs.current_tab = TAB_BATTLE if in_battle else TAB_LOBBY
	_refresh_chat_send_enabled()


func _set_social_visible(visible: bool) -> void:
	chat_dock.visible = visible
	if not visible and plan_dock != null:
		plan_dock.visible = false


func _layout_social() -> void:
	# Bottom-left: chat + players in one dock. Bottom-right: battle plan only.
	chat_dock.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_dock.anchor_left = 0.0
	chat_dock.anchor_right = 0.0
	chat_dock.anchor_top = 1.0
	chat_dock.anchor_bottom = 1.0
	chat_dock.offset_left = SOCIAL_EDGE
	chat_dock.offset_right = SOCIAL_EDGE + CHAT_W
	chat_dock.offset_bottom = -SOCIAL_EDGE
	chat_dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if plan_dock != null:
		plan_dock.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		plan_dock.anchor_left = 1.0
		plan_dock.anchor_right = 1.0
		plan_dock.anchor_top = 1.0
		plan_dock.anchor_bottom = 1.0
		plan_dock.offset_left = -(SOCIAL_EDGE + PLAN_W)
		plan_dock.offset_right = -SOCIAL_EDGE
		plan_dock.offset_top = -(SOCIAL_EDGE + CHAT_H)
		plan_dock.offset_bottom = -SOCIAL_EDGE
		plan_dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		plan_dock.custom_minimum_size = Vector2(PLAN_W, CHAT_H)
		plan_dock.visible = _in_battle_ui
	_reveal_chat_history()


func _apply_chat_dock_height(expanded: bool) -> void:
	# Keep full height so the embedded players list stays usable.
	var h := CHAT_H if expanded else CHAT_COLLAPSED_H
	if players_col != null:
		players_col.visible = expanded
	chat_dock.custom_minimum_size = Vector2(CHAT_W if expanded else CHAT_W - 110.0, h)
	chat_dock.offset_top = -(SOCIAL_EDGE + h)
	chat_dock.offset_bottom = -SOCIAL_EDGE


func _reveal_chat_history() -> void:
	if chat_tabs == null:
		return
	_chat_history_visible = true
	if _chat_fade_tween != null and _chat_fade_tween.is_valid():
		_chat_fade_tween.kill()
	chat_tabs.visible = true
	chat_tabs.modulate.a = 1.0
	_apply_chat_dock_height(true)
	if _chat_idle_timer != null:
		_chat_idle_timer.start(CHAT_FADE_IDLE_SEC)


func _fade_chat_history() -> void:
	if chat_tabs == null:
		return
	if chat_edit != null and chat_edit.has_focus():
		_chat_idle_timer.start(CHAT_FADE_IDLE_SEC)
		return
	_chat_history_visible = false
	if _chat_fade_tween != null and _chat_fade_tween.is_valid():
		_chat_fade_tween.kill()
	_chat_fade_tween = create_tween()
	_chat_fade_tween.tween_property(chat_tabs, "modulate:a", 0.0, CHAT_FADE_DUR)
	_chat_fade_tween.tween_callback(func():
		if _chat_history_visible:
			return
		chat_tabs.visible = false
		_apply_chat_dock_height(false)
	)


func _set_battle_tab_visible(visible: bool) -> void:
	if chat_tabs == null:
		return
	chat_tabs.set_tab_hidden(TAB_BATTLE, not visible)
	if not visible and chat_tabs.current_tab == TAB_BATTLE:
		chat_tabs.current_tab = TAB_LOBBY


func _on_medkit_pressed() -> void:
	if not _medkit_can_use:
		return
	medkit_pressed.emit()


func _on_continue() -> void:
	var nick := nick_edit.text.strip_edges()
	if nick == "":
		login_error.text = "Введите ник"
		return
	player_nick = nick
	continue_pressed.emit(player_nick)
	show_lobby()


func _on_chat_tab_changed(_tab: int) -> void:
	_refresh_chat_send_enabled()


func _refresh_chat_send_enabled() -> void:
	var channel := _active_chat_channel()
	var can_send := (_in_battle_ui and channel == "battle") or (not _in_battle_ui and channel == "lobby")
	chat_send_btn.disabled = not can_send
	chat_edit.editable = can_send
	if channel == "battle" and not _in_battle_ui:
		chat_edit.placeholder_text = "Доступно в бою"
	elif channel == "lobby" and _in_battle_ui:
		chat_edit.placeholder_text = "Доступно в лобби"
	else:
		chat_edit.placeholder_text = "Сообщение..."


func _active_chat_channel() -> String:
	return "battle" if chat_tabs.current_tab == TAB_BATTLE else "lobby"


func _on_chat_send() -> void:
	if chat_send_btn.disabled:
		return
	var text := chat_edit.text.strip_edges()
	if text == "":
		return
	chat_edit.text = ""
	chat_submitted.emit(text, _active_chat_channel())


func _set_room_players(nicks: Array) -> void:
	room_list.clear()
	for n in nicks:
		var idx := room_list.add_item(str(n))
		room_list.set_item_selectable(idx, false)
	room_list.deselect_all()
