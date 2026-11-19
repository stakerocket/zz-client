extends CanvasLayer
class_name ZZAppUI

signal continue_pressed(nick: String)
signal find_match_pressed
signal cancel_match_pressed
signal end_turn_pressed
signal undo_pressed
signal posture_pressed(posture: String)
signal medkit_pressed
signal quick_slot_pressed(slot_index: int)
signal reload_pressed
signal weapon_slot_pressed(slot_index: int)
signal chat_submitted(text: String, channel: String)
signal return_to_lobby_pressed
signal inventory_open_pressed
signal battle_inventory_pressed
signal inventory_equip_requested(item_id: String, slot: String)
signal inventory_unequip_requested(slot: String)
signal inventory_withdraw_requested(item_id: String, qty: int)
signal inventory_deposit_requested(item_id: String, qty: int)
signal set_level_requested(level: int)
signal spend_stat_requested(stat: String, delta: int)

const TAB_LOBBY := 0
const TAB_BATTLE := 1
const CHAT_W := 420.0
## Expanded chat matches CharDock height (scene: offset_top −132, bottom −6 → 126).
const CHAT_H := 126.0
const CHAT_COLLAPSED_H := 36.0
const SOCIAL_EDGE := 8.0
## Same bottom inset as CharDock so tops line up when heights match.
const CHAT_BOTTOM := 6.0
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
var _quick_ids: Array = ["", "", "", ""]
var _quick_can_use: Array = [false, false, false, false]
var _quick_btns: Array = [] # Button × 4
var _switch_weapon_cost: int = 1
var _switch_look_ok: bool = true
var _active_weapon_look_ok: bool = true
var _active_weapon_idx: int = 0
var _weapon_slots: Array = [] # Dictionaries: id, shoot_ap, reload_ap, ammo_in_mag, ammo_reserve
var _weapon2_btn: Button
var enemy_dossier: ZZEnemyDossier
const ACTION_DIM := Color(1, 1, 1, 0.45)

@onready var login_screen: Control = $LoginScreen
@onready var lobby_screen: Control = $LobbyScreen
@onready var battle_hud: Control = $BattleHud
@onready var chat_dock: PanelContainer = $ChatDock

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
@onready var inventory_btn: Button = $LobbyScreen/PlayerCard/VBox/InventoryBtn
@onready var find_btn: Button = $LobbyScreen/FindCenter/FindBtn

var inventory_ui: ZZInventoryUI
var _lobby_level_opt: OptionButton
var _lobby_unspent: Label
var _lobby_profile: Dictionary = {}
var _lobby_stat_btns: Dictionary = {} # stat -> {minus, plus, value label}
var _updating_lobby_profile: bool = false
var _searching: bool = false

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
@onready var battle_inv_btn: Button = $BattleHud/CharDock/VBox/TopRow/BattleInvBtn
@onready var undo_btn: Button = $BattleHud/CharDock/VBox/TopRow/UndoBtn
@onready var quick_bar: HBoxContainer = $BattleHud/CharDock/VBox/TopRow/QuickBar
@onready var reload_btn: Button = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn
@onready var rifle_icon: TextureRect = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/RifleIcon
@onready var reload_icon: TextureRect = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/ReloadRow/ReloadIcon
@onready var reload_cost_label: Label = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/ReloadRow/ReloadCostLabel
@onready var shot_cost_label: Label = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/ShotCostLabel
@onready var ammo_col: HBoxContainer = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/AmmoRow/AmmoCol
@onready var ammo_count_label: Label = $BattleHud/CharDock/VBox/ActionRow/WeaponBtn/AmmoRow/AmmoCountLabel
@onready var battle_hp_bar: ProgressBar = $BattleHud/CharDock/VBox/TopRow/VitalCol/HPRow/HPBar
@onready var battle_hp_value: Label = $BattleHud/CharDock/VBox/TopRow/VitalCol/HPRow/HPValue
@onready var battle_ap_bar: ProgressBar = $BattleHud/CharDock/VBox/TopRow/VitalCol/APRow/APBar
@onready var battle_ap_value: Label = $BattleHud/CharDock/VBox/TopRow/VitalCol/APRow/APValue

var _bullet_tex: Texture2D
var _mag_size: int = 6
var _fire_mode_hint: String = "Одиночный"

@onready var result_overlay: Control = $BattleHud/ResultOverlay
@onready var result_label: Label = $BattleHud/ResultOverlay/Center/Panel/VBox/ResultLabel
@onready var lobby_btn: Button = $BattleHud/ResultOverlay/Center/Panel/VBox/LobbyBtn


func _ready() -> void:
	continue_btn.pressed.connect(_on_continue)
	nick_edit.text_submitted.connect(func(_t): _on_continue())
	find_btn.pressed.connect(_on_find_btn_pressed)
	_setup_lobby_profile_controls()
	if inventory_btn != null:
		inventory_btn.pressed.connect(_on_inventory_btn)
	if battle_inv_btn != null:
		battle_inv_btn.pressed.connect(_on_battle_inventory_btn)
	end_btn.pressed.connect(func(): end_turn_pressed.emit())
	## Space = obstacle clear toggle in battle; don't let End/Undo eat ui_accept.
	end_btn.focus_mode = Control.FOCUS_NONE
	undo_btn.focus_mode = Control.FOCUS_NONE
	undo_btn.pressed.connect(func(): undo_pressed.emit())
	stand_btn.pressed.connect(func(): posture_pressed.emit("stand"))
	sit_btn.pressed.connect(func(): posture_pressed.emit("sit"))
	run_btn.pressed.connect(func(): posture_pressed.emit("run"))
	cover_btn.pressed.connect(func(): posture_pressed.emit("cover"))
	for _pb in [stand_btn, sit_btn, run_btn, cover_btn]:
		if _pb != null:
			_pb.focus_mode = Control.FOCUS_NONE
	_bind_quick_bar()
	_wire_tip_host(reload_btn)
	_wire_weapon_slot_btn(reload_btn, 0)
	_ensure_weapon2_btn()
	var top_row := char_dock.get_node_or_null("VBox/TopRow") as Control if char_dock != null else null
	if top_row != null and not top_row.resized.is_connected(_sync_weapon_card_widths):
		top_row.resized.connect(_sync_weapon_card_widths)
	if char_dock != null and not char_dock.resized.is_connected(_on_char_dock_resized):
		char_dock.resized.connect(_on_char_dock_resized)
	lobby_btn.pressed.connect(func(): return_to_lobby_pressed.emit())
	chat_send_btn.pressed.connect(_on_chat_send)
	chat_edit.text_submitted.connect(func(_t): _on_chat_send())
	chat_tabs.tab_changed.connect(_on_chat_tab_changed)
	chat_edit.focus_entered.connect(_reveal_chat_history)
	chat_dock.gui_input.connect(_on_chat_dock_gui_input)
	end_btn.disabled = true
	undo_btn.disabled = true
	result_overlay.visible = false
	_kill_default_tooltip_panel()
	_apply_hud_icons()
	_setup_posture_tips()
	_setup_battle_inv_tip()
	_ensure_inventory_ui()
	_ensure_enemy_dossier()
	# Keep social UI above full-screen lobby/battle layers.
	chat_dock.z_index = 100
	move_child(chat_dock, get_child_count() - 1)
	if inventory_ui != null:
		move_child(inventory_ui, get_child_count() - 1)
	lobby_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_setup_chat_fade_timer()
	_make_chat_tabs_transparent()
	show_login()


func _ensure_enemy_dossier() -> void:
	if enemy_dossier != null:
		return
	enemy_dossier = ZZEnemyDossier.new()
	enemy_dossier.name = "EnemyDossier"
	if battle_hud != null:
		battle_hud.add_child(enemy_dossier)
	else:
		add_child(enemy_dossier)


func show_enemy_dossier(pd: Dictionary, canvas_anchor: Vector2, canvas_shooter: Vector2 = Vector2.ZERO) -> void:
	_ensure_enemy_dossier()
	var canvas_size := Vector2(1280, 720)
	if battle_hud != null:
		var r := battle_hud.get_global_rect()
		if r.size.x > 1.0 and r.size.y > 1.0:
			canvas_size = r.size
	enemy_dossier.show_dossier(pd, canvas_anchor, canvas_size, canvas_shooter)


func hide_enemy_dossier() -> void:
	if enemy_dossier != null:
		enemy_dossier.hide_dossier()


func _ensure_inventory_ui() -> void:
	if inventory_ui != null:
		return
	inventory_ui = ZZInventoryUI.new()
	inventory_ui.name = "InventoryScreen"
	add_child(inventory_ui)
	inventory_ui.closed.connect(func(): pass)
	inventory_ui.equip_requested.connect(func(item_id: String, slot: String):
		inventory_equip_requested.emit(item_id, slot)
	)
	inventory_ui.unequip_requested.connect(func(slot: String):
		inventory_unequip_requested.emit(slot)
	)
	inventory_ui.withdraw_requested.connect(func(item_id: String, qty: int):
		inventory_withdraw_requested.emit(item_id, qty)
	)
	inventory_ui.deposit_requested.connect(func(item_id: String, qty: int):
		inventory_deposit_requested.emit(item_id, qty)
	)


func _on_inventory_btn() -> void:
	if inventory_ui == null:
		_ensure_inventory_ui()
	if inventory_ui.visible:
		inventory_ui.close()
		return
	inventory_ui.open_for(player_nick, true)
	inventory_open_pressed.emit()


func _on_battle_inventory_btn() -> void:
	if inventory_ui != null and inventory_ui.visible:
		inventory_ui.close()
		return
	battle_inventory_pressed.emit()


func open_battle_inventory(data: Dictionary) -> void:
	if inventory_ui == null:
		_ensure_inventory_ui()
	inventory_ui.apply_state(data)
	inventory_ui.open_for(player_nick, false)


func apply_inventory_state(data: Dictionary) -> void:
	if inventory_ui == null:
		_ensure_inventory_ui()
	inventory_ui.apply_state(data)
	_apply_lobby_profile(data)


func hide_inventory() -> void:
	if inventory_ui != null and inventory_ui.visible:
		inventory_ui.close()


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


func show_login(clear_error: bool = true) -> void:
	login_screen.visible = true
	lobby_screen.visible = false
	battle_hud.visible = false
	hide_enemy_dossier()
	hide_inventory()
	_set_social_visible(false)
	_in_battle_ui = false
	if clear_error:
		login_error.text = ""
	continue_btn.disabled = false
	nick_edit.grab_focus()


func set_login_error(msg: String) -> void:
	login_error.add_theme_color_override("font_color", Color(0.92, 0.42, 0.38, 1))
	login_error.text = msg
	continue_btn.disabled = false
	nick_edit.grab_focus()


func _set_login_status(msg: String) -> void:
	## Neutral status (connecting) — gray, not error red.
	login_error.add_theme_color_override("font_color", Color(0.62, 0.62, 0.64, 1))
	login_error.text = msg


func show_lobby() -> void:
	login_screen.visible = false
	lobby_screen.visible = true
	battle_hud.visible = false
	result_overlay.visible = false
	hide_enemy_dossier()
	hide_inventory()
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
	hide_inventory()
	if battle_chat_log != null:
		battle_chat_log.clear()
	_apply_social_context(true)
	call_deferred("_sync_weapon_card_widths")
	## CharDock size is ready next frame — match expanded chat height to it.
	call_deferred("_apply_chat_dock_height", true)


func show_battle_result(won: bool) -> void:
	battle_hud.visible = true
	result_overlay.visible = true
	hide_enemy_dossier()
	result_label.text = "Победа" if won else "Поражение"
	end_btn.disabled = true
	lobby_btn.grab_focus()


func set_find_enabled(enabled: bool) -> void:
	_searching = false
	find_btn.disabled = not enabled
	if enabled:
		find_btn.text = "Найти бой"


func set_searching(searching: bool) -> void:
	_searching = searching
	if searching:
		find_btn.disabled = false
		find_btn.text = "Отменить"
	else:
		set_find_enabled(true)


func _on_find_btn_pressed() -> void:
	if _searching:
		cancel_match_pressed.emit()
	else:
		find_match_pressed.emit()


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
	_mag_size = maxi(0, mag_size)
	_refresh_weapon_slot()


func refresh_lobby_stats_from_rules() -> void:
	## Prefer live profile from inventory_state; fall back to rules defaults.
	if not _lobby_profile.is_empty():
		_apply_lobby_profile(_lobby_profile)
		return
	if not ZZLos.has_rules():
		_set_lobby_stats_placeholder()
		return
	var s := ZZLos.default_stat()
	_set_lobby_stat_texts(1, {
		"strength": s, "agility": s, "endurance": s,
		"intuition": s, "accuracy": s, "intelligence": s,
	}, 0, 0.0, float(ZZLos.compute_carry_weight(s)))


func _setup_lobby_profile_controls() -> void:
	var box: VBoxContainer = lobby_level.get_parent() as VBoxContainer if lobby_level != null else null
	if box == null:
		return
	## Level selector under "Уровень" label.
	_lobby_level_opt = OptionButton.new()
	_lobby_level_opt.focus_mode = Control.FOCUS_NONE
	for lv in range(1, 7):
		_lobby_level_opt.add_item("Уровень %d" % lv, lv)
	_lobby_level_opt.select(0)
	_lobby_level_opt.item_selected.connect(_on_lobby_level_selected)
	box.add_child(_lobby_level_opt)
	box.move_child(_lobby_level_opt, lobby_level.get_index() + 1)
	lobby_level.visible = false
	## Stats are auto-filled from level gear reqs — no ± / unspent UI.
	_lobby_unspent = Label.new()
	_lobby_unspent.add_theme_font_size_override("font_size", 11)
	_lobby_unspent.text = "Статы под топ шмот уровня"
	box.add_child(_lobby_unspent)
	box.move_child(_lobby_unspent, _lobby_level_opt.get_index() + 1)
	_wire_lobby_stat_row(lobby_str, "strength", "Сила")
	_wire_lobby_stat_row(lobby_agi, "agility", "Ловкость")
	_wire_lobby_stat_row(lobby_end, "endurance", "Выносливость")
	_wire_lobby_stat_row(lobby_intu, "intuition", "Интуиция")
	_wire_lobby_stat_row(lobby_acc, "accuracy", "Меткость")
	_wire_lobby_stat_row(lobby_int, "intelligence", "Интеллект")


func _wire_lobby_stat_row(lab: Label, stat: String, title: String) -> void:
	if lab == null:
		return
	lab.text = "%s: 5" % title
	_lobby_stat_btns[stat] = {"label": lab, "title": title}


func _on_lobby_level_selected(idx: int) -> void:
	if _updating_lobby_profile or _lobby_level_opt == null:
		return
	var lv := int(_lobby_level_opt.get_item_id(idx))
	set_level_requested.emit(lv)


func _apply_lobby_profile(data: Dictionary) -> void:
	_lobby_profile = data.duplicate(true)
	var tip_stats: Variant = data.get("stats", {})
	if typeof(tip_stats) == TYPE_DICTIONARY:
		ZZItemTooltip.set_player_context(int(data.get("level", 1)), tip_stats as Dictionary)
	var lvl := maxi(1, int(data.get("level", 1)))
	var stats_v: Variant = data.get("stats", {})
	var stats: Dictionary = stats_v if typeof(stats_v) == TYPE_DICTIONARY else {}
	var unspent := int(data.get("unspent_points", 0))
	var inv_w := float(data.get("inventory_weight", 0.0))
	var carry := float(data.get("carry_weight", 50.0))
	_set_lobby_stat_texts(lvl, stats, unspent, inv_w, carry)


func _set_lobby_stat_texts(lvl: int, stats: Dictionary, unspent: int, inv_w: float, carry: float) -> void:
	_updating_lobby_profile = true
	if _lobby_level_opt != null:
		var sel := clampi(lvl - 1, 0, 5)
		if _lobby_level_opt.selected != sel:
			_lobby_level_opt.select(sel)
	if _lobby_unspent != null:
		_lobby_unspent.text = "Статы под топ шмот уровня"
	var map := {
		"strength": lobby_str, "agility": lobby_agi, "endurance": lobby_end,
		"intuition": lobby_intu, "accuracy": lobby_acc, "intelligence": lobby_int,
	}
	var titles := {
		"strength": "Сила", "agility": "Ловкость", "endurance": "Выносливость",
		"intuition": "Интуиция", "accuracy": "Меткость", "intelligence": "Интеллект",
	}
	for key in map.keys():
		var lab: Label = map[key]
		if lab != null:
			lab.text = "%s: %d" % [titles[key], int(stats.get(key, 5))]
	var strv := int(stats.get("strength", 5))
	var agiv := int(stats.get("agility", 5))
	var endv := int(stats.get("endurance", 5))
	var ap := ZZLos.compute_max_ap(strv, agiv, endv)
	if inv_w > carry:
		var frac := ZZLos.rule_f("overweight_ap_frac")
		if frac <= 0.0:
			frac = 0.2
		ap = maxi(0, int(floor(float(ap) * frac)))
	lobby_hp.text = "ХП: %d" % ZZLos.compute_max_hp(endv)
	lobby_ap.text = "ОД: %d" % ap
	if inv_w > carry:
		lobby_carry.text = "Вес: %.1f/%.0f (перегруз)" % [inv_w, carry]
	else:
		lobby_carry.text = "Вес: %.1f/%.0f" % [inv_w, carry]
	_updating_lobby_profile = false


func _set_lobby_stats_placeholder() -> void:
	if _lobby_unspent != null:
		_lobby_unspent.text = "Статы под топ шмот уровня"
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
		battle_ap_value.text = str(ap)
		battle_ap_value.tooltip_text = "%d / %d" % [ap, _max_ap]
	_refresh_battle_inv_affordance(ap)


func set_hp(value: int) -> void:
	var hp := maxi(0, value)
	if battle_hp_bar != null:
		battle_hp_bar.max_value = float(_max_hp)
		battle_hp_bar.value = float(hp)
	if battle_hp_value != null:
		battle_hp_value.text = str(hp)
		battle_hp_value.tooltip_text = "%d / %d" % [hp, _max_hp]


func set_posture(posture: String) -> void:
	_active_posture = posture
	_refresh_posture_highlight()


func set_end_enabled(enabled: bool) -> void:
	end_btn.disabled = not enabled
	stand_btn.disabled = not enabled
	sit_btn.disabled = not enabled
	run_btn.disabled = not enabled
	cover_btn.disabled = not enabled
	if battle_inv_btn != null:
		battle_inv_btn.disabled = not enabled


func set_medkit_enabled(enabled: bool) -> void:
	## Legacy: dim/enable all medkit-type quick slots the same way.
	set_medkit_affordance(enabled, enabled)


func set_reload_enabled(enabled: bool) -> void:
	set_reload_affordance(enabled, enabled)


func set_medkit_affordance(can_press: bool, look_affordable: bool) -> void:
	_medkit_can_use = can_press
	for i in range(_quick_ids.size()):
		if _item_type_of(str(_quick_ids[i])) == "medkit":
			set_quick_affordance(i, can_press, look_affordable)


func set_quick_affordance(slot_index: int, can_press: bool, look_affordable: bool) -> void:
	if slot_index < 0 or slot_index >= _quick_can_use.size():
		return
	_quick_can_use[slot_index] = can_press
	if slot_index < _quick_btns.size() and _quick_btns[slot_index] != null:
		var b: Button = _quick_btns[slot_index]
		b.disabled = false
		b.modulate = Color.WHITE if look_affordable else ACTION_DIM


func set_reload_affordance(can_press: bool, look_affordable: bool) -> void:
	# Full mag: can_press=false, look_affordable=true if AP enough (panel must not look “no AP”).
	_reload_can_use = can_press
	_active_weapon_look_ok = look_affordable
	_refresh_weapon_slot_modulate()


func set_switch_weapon_affordance(look_ok: bool) -> void:
	_switch_look_ok = look_ok
	_refresh_weapon_slot_modulate()


func set_weapons(weapons: Array, active_idx: int, switch_ap: int = 1) -> void:
	## Deep-copy slot dicts so legacy ammo setters never mutate battle.local_weapons.
	_weapon_slots = []
	for item in weapons:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = (item as Dictionary).duplicate()
		if str(d.get("id", "")) == "":
			continue
		_weapon_slots.append(d)
	_active_weapon_idx = clampi(active_idx, 0, maxi(0, _weapon_slots.size() - 1))
	_switch_weapon_cost = maxi(0, switch_ap)
	## Always two HUD slots (primary/secondary). Empty when unequipped — never hide #2.
	if _weapon2_btn != null:
		_weapon2_btn.visible = true
	call_deferred("_sync_weapon_card_widths")
	_apply_weapon_slot_visuals()


func set_medkit_count(count: int, heal_min: int = 15, heal_max: int = 30, ap_cost: int = 3) -> void:
	_medkit_count = maxi(0, count)
	## Refresh medkit tooltips / counts on quick bar.
	_refresh_quick_medkit_meta(heal_min, heal_max, ap_cost)


## slots: Array of item_id (len 4). counts: optional qty per slot (-1 = hide).
func set_quick_slots(slots: Array, counts: Array = [], heal_min: int = 15, heal_max: int = 30, medkit_ap: int = 3) -> void:
	_quick_ids = ["", "", "", ""]
	for i in range(mini(4, slots.size())):
		_quick_ids[i] = str(slots[i])
	_ensure_quick_btns()
	for i in range(4):
		var id := str(_quick_ids[i]) if i < _quick_ids.size() else ""
		var btn: Button = _quick_btns[i] if i < _quick_btns.size() else null
		if btn == null:
			continue
		var icon := btn.get_node_or_null("Icon") as TextureRect
		var count_lbl := btn.get_node_or_null("CountLabel") as Label
		var tip := _wire_tip_host(btn)
		if id == "":
			if icon != null:
				icon.texture = null
			if count_lbl != null:
				count_lbl.text = ""
			if tip != null:
				tip.tip_item_id = ""
				tip.tip_extra = []
			btn.tooltip_text = ""
			btn.modulate = ACTION_DIM
			continue
		if icon != null:
			icon.texture = _quick_icon_for(id)
		var qty := 0
		if i < counts.size():
			qty = int(counts[i])
		elif _item_type_of(id) == "medkit":
			qty = _medkit_count
		if count_lbl != null:
			count_lbl.text = ("x%d" % qty) if qty > 1 else ("" if qty <= 0 else "")
		if tip != null:
			tip.tip_item_id = id
			tip.tip_qty = maxi(qty, 1)
			tip.tip_extra = []
		btn.tooltip_text = " "  # non-empty → custom tip
	_refresh_quick_medkit_meta(heal_min, heal_max, medkit_ap)


func _refresh_quick_medkit_meta(heal_min: int, heal_max: int, ap_cost: int) -> void:
	for i in range(_quick_ids.size()):
		var id := str(_quick_ids[i])
		if _item_type_of(id) != "medkit":
			continue
		var btn: Button = _quick_btns[i] if i < _quick_btns.size() else null
		if btn == null:
			continue
		var count_lbl := btn.get_node_or_null("CountLabel") as Label
		if count_lbl != null and _medkit_count > 1:
			count_lbl.text = "x%d" % _medkit_count
		elif count_lbl != null and _medkit_count <= 0:
			count_lbl.text = ""
		var tip := _wire_tip_host(btn)
		if tip != null:
			tip.tip_item_id = id
			tip.tip_qty = maxi(_medkit_count, 1)
			tip.tip_extra = []
		btn.tooltip_text = " "


func _item_type_of(item_id: String) -> String:
	if item_id == "":
		return ""
	return str(ZZLos.item_def(item_id).get("type", ""))


func _quick_icon_for(item_id: String) -> Texture2D:
	var mock := ZZInventoryIcons.tex(item_id)
	if mock != null:
		return mock
	match _item_type_of(item_id):
		"medkit":
			return ZZHudIcons.medkit(48)
		"ammo":
			return ZZHudIcons.ammo_rifle(48)
		_:
			return ZZHudIcons.medkit(48)


func _bind_quick_bar() -> void:
	_ensure_quick_btns()
	for i in range(_quick_btns.size()):
		var b: Button = _quick_btns[i]
		if b == null:
			continue
		var idx := i
		b.pressed.connect(func(): _on_quick_pressed(idx))


func _ensure_quick_btns() -> void:
	if not _quick_btns.is_empty():
		return
	if quick_bar == null:
		return
	_quick_btns = [
		quick_bar.get_node_or_null("Quick0"),
		quick_bar.get_node_or_null("Quick1"),
		quick_bar.get_node_or_null("Quick2"),
		quick_bar.get_node_or_null("Quick3"),
	]
	for b in _quick_btns:
		if b == null:
			continue
		_wire_tip_host(b)
		_style_quick_qty_badge(b.get_node_or_null("CountLabel") as Label)


func _kill_default_tooltip_panel() -> void:
	## Same as inventory: empty TooltipPanel so custom cards have no halo.
	if char_dock == null:
		return
	var tip_theme := Theme.new()
	tip_theme.set_stylebox("panel", "TooltipPanel", StyleBoxEmpty.new())
	char_dock.theme = tip_theme


func _wire_tip_host(btn: Button) -> ZZTipHostBtn:
	if btn == null:
		return null
	if btn is ZZTipHostBtn:
		return btn as ZZTipHostBtn
	btn.set_script(preload("res://scripts/ui/tip_host_btn.gd"))
	return btn as ZZTipHostBtn


func _setup_posture_tips() -> void:
	var ap := ZZLos.rule_i("posture_ap")
	if ap <= 0:
		ap = 1
	var dodge_run := int(round(ZZLos.rule_f("hit_pose_dodge_run") * 100.0))
	if dodge_run <= 0:
		dodge_run = 25
	## Cover open defense shown as уклонение.
	var dodge_cover := int(round(ZZLos.rule_f("def_cover_open") * 100.0))
	if dodge_cover <= 0:
		dodge_cover = 60
	var sit_acc := int(round(ZZLos.rule_f("hit_pose_bonus_sit") * 100.0))
	if sit_acc <= 0:
		sit_acc = 15
	var sit_dodge := int(round(ZZLos.rule_f("def_sit_open") * 100.0))
	if sit_dodge <= 0:
		sit_dodge = 15
	var run_acc := int(round(ZZLos.rule_f("hit_pose_bonus_run") * 100.0))
	if run_acc == 0:
		run_acc = -20
	_set_posture_tip(stand_btn, "Стоя", [
		["Смена", "%d ОД" % ap],
		["Движение", "обычно"],
	])
	_set_posture_tip(sit_btn, "Сидя", [
		["Смена", "%d ОД" % ap],
		["Уклонение", "%+d" % sit_dodge],
		["Меткость", "%+d" % sit_acc],
		["Движение", "медленнее"],
	])
	_set_posture_tip(run_btn, "Бег", [
		["Смена", "%d ОД" % ap],
		["Уклонение", "%+d" % dodge_run],
		["Меткость", "%+d" % run_acc],
		["Движение", "быстрее"],
	])
	_set_posture_tip(cover_btn, "Укрыться", [
		["Смена", "%d ОД" % ap],
		["Уклонение", "%+d" % dodge_cover],
		["Движение", "нет"],
		["Выстрел", "авто → сидя (+%d ОД)" % ap],
	])
	_clear_ap_badge(stand_btn)
	_clear_ap_badge(sit_btn)
	_clear_ap_badge(run_btn)
	_clear_ap_badge(cover_btn)


func _set_posture_tip(btn: Button, title: String, rows: Array) -> void:
	_set_simple_tip(btn, title, "Стойка", rows)


func _set_simple_tip(btn: Button, title: String, subtitle: String, rows: Array) -> void:
	var tip := _wire_tip_host(btn)
	if tip == null:
		return
	tip.tip_item_id = ""
	tip.tip_title = title
	tip.tip_subtitle = subtitle
	tip.tip_extra = rows
	btn.tooltip_text = " "


func _clear_ap_badge(btn: Button) -> void:
	if btn == null:
		return
	var lbl := btn.get_node_or_null("ApCost")
	if lbl != null:
		lbl.queue_free()


func _setup_battle_inv_tip() -> void:
	if battle_inv_btn == null:
		return
	var ap := ZZLos.rule_i("inventory_ap")
	if ap <= 0:
		ap = 2
	_set_simple_tip(battle_inv_btn, "Инвентарь", "", [
		["Открыть", "%d ОД" % ap],
	])
	_clear_ap_badge(battle_inv_btn)


func _refresh_battle_inv_affordance(ap: int) -> void:
	if battle_inv_btn == null:
		return
	var cost := ZZLos.rule_i("inventory_ap")
	if cost <= 0:
		cost = 2
	## Keep clickable when open (close is free); dim only if can't afford open.
	var open := inventory_ui != null and inventory_ui.visible
	var look_ok := open or ap >= cost
	battle_inv_btn.modulate = Color.WHITE if look_ok else ACTION_DIM


func _style_quick_qty_badge(lbl: Label) -> void:
	## Match inventory QtyBadge (bottom-right, outline).
	if lbl == null:
		return
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05, 0.9))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_quick_pressed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _quick_ids.size():
		return
	if slot_index >= _quick_can_use.size() or not _quick_can_use[slot_index]:
		return
	var id := str(_quick_ids[slot_index])
	if id == "":
		return
	if _item_type_of(id) == "medkit":
		medkit_pressed.emit()
		return
	quick_slot_pressed.emit(slot_index)


func set_reload_cost(ap_cost: int) -> void:
	_reload_cost = maxi(0, ap_cost)
	_refresh_weapon_slot()


func set_ammo(in_mag: int, reserve: int) -> void:
	_ammo_in_mag = maxi(0, in_mag)
	_ammo_reserve = maxi(0, reserve)
	_refresh_weapon_slot()


func set_fire_mode_hint(label: String) -> void:
	_fire_mode_hint = label if label != "" else "Одиночный"
	_refresh_weapon_slot()
	_apply_weapon_slot_visuals()


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
	undo_btn.icon = ZZHudIcons.undo(22)
	if battle_inv_btn != null:
		battle_inv_btn.icon = ZZHudIcons.inventory(24)
		battle_inv_btn.expand_icon = true
	stand_btn.expand_icon = true
	sit_btn.expand_icon = true
	run_btn.expand_icon = true
	cover_btn.expand_icon = true
	undo_btn.expand_icon = true
	if reload_icon != null:
		reload_icon.texture = ZZHudIcons.icon_reload(14)
	_apply_weapon_slot_visuals()


func _ensure_weapon2_btn() -> void:
	if reload_btn == null or _weapon2_btn != null:
		return
	## Fixed widths from _sync_weapon_card_widths (align to quick slots / undo).
	reload_btn.size_flags_horizontal = 0
	_weapon2_btn = reload_btn.duplicate() as Button
	_weapon2_btn.name = "WeaponBtn2"
	_weapon2_btn.size_flags_horizontal = 0
	_wire_tip_host(_weapon2_btn)
	reload_btn.get_parent().add_child(_weapon2_btn)
	reload_btn.get_parent().move_child(_weapon2_btn, reload_btn.get_index() + 1)
	_wire_weapon_slot_btn(_weapon2_btn, 1)
	var icon2: TextureRect = _weapon2_btn.get_node_or_null("RifleIcon")
	if icon2 != null:
		icon2.texture = null
	var reload_icon2: TextureRect = _weapon2_btn.get_node_or_null("ReloadRow/ReloadIcon")
	if reload_icon2 != null:
		reload_icon2.texture = ZZHudIcons.icon_reload(14)
	call_deferred("_sync_weapon_card_widths")


func _wire_weapon_slot_btn(btn: Button, slot: int) -> void:
	if btn == null:
		return
	if not btn.pressed.is_connected(_on_weapon_slot_pressed.bind(slot)):
		btn.pressed.connect(_on_weapon_slot_pressed.bind(slot))
	if not btn.gui_input.is_connected(_on_weapon_slot_gui_input.bind(slot)):
		btn.gui_input.connect(_on_weapon_slot_gui_input.bind(slot))


func _on_weapon_slot_pressed(slot: int) -> void:
	weapon_slot_pressed.emit(slot)


func _on_weapon_slot_gui_input(event: InputEvent, slot: int) -> void:
	## ПКМ по активному стволу — всегда перезарядка (ЛКМ — режим огня / смена слота).
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if slot != _active_weapon_idx:
		return
	if not _reload_can_use:
		return
	reload_pressed.emit()
	get_viewport().set_input_as_handled()


func _apply_weapon_slot_visuals() -> void:
	_fill_weapon_btn(reload_btn, 0)
	if _weapon2_btn != null:
		_fill_weapon_btn(_weapon2_btn, 1)
	_refresh_weapon_slot_modulate()


func _sync_weapon_card_widths() -> void:
	## Equal-width weapon cards filling ActionRow from posture grid to undo right edge.
	var top := char_dock.get_node_or_null("VBox/TopRow") as Control if char_dock != null else null
	var action := char_dock.get_node_or_null("VBox/ActionRow") as HBoxContainer if char_dock != null else null
	if top == null or action == null or reload_btn == null or undo_btn == null:
		return
	var grid := action.get_node_or_null("QuickGrid") as Control
	if grid == null:
		return
	## Wait until TopRow has laid out.
	if top.size.x < 8.0 or undo_btn.size.x < 1.0:
		return
	var sep := float(action.get_theme_constant("separation"))
	var undo_right := undo_btn.position.x + undo_btn.size.x
	var grid_w := grid.size.x if grid.size.x > 1.0 else grid.get_combined_minimum_size().x
	var avail := undo_right - grid_w - sep
	var w: float
	if _weapon2_btn != null:
		w = maxf(110.0, (avail - sep) * 0.5)
	else:
		w = maxf(110.0, avail)
	var cur1 := reload_btn.custom_minimum_size.x
	var cur2 := _weapon2_btn.custom_minimum_size.x if _weapon2_btn != null else 0.0
	if absf(cur1 - w) < 0.5 and (_weapon2_btn == null or absf(cur2 - w) < 0.5):
		return
	reload_btn.custom_minimum_size = Vector2(w, 64)
	if _weapon2_btn != null:
		_weapon2_btn.custom_minimum_size = Vector2(w, 64)
	_apply_weapon_slot_visuals()


func _weapon_at(slot: int) -> Dictionary:
	if slot < 0 or slot >= _weapon_slots.size():
		return {}
	if typeof(_weapon_slots[slot]) != TYPE_DICTIONARY:
		return {}
	var w: Dictionary = _weapon_slots[slot]
	if str(w.get("id", "")) == "":
		return {}
	return w


func _fill_weapon_btn(btn: Button, slot: int) -> void:
	if btn == null:
		return
	btn.clip_contents = true
	var w := _weapon_at(slot)
	var shot_lbl: Label = btn.get_node_or_null("ShotCostLabel")
	var reload_lbl: Label = btn.get_node_or_null("ReloadRow/ReloadCostLabel")
	var reload_ic: TextureRect = btn.get_node_or_null("ReloadRow/ReloadIcon")
	var ammo_row: HBoxContainer = btn.get_node_or_null("AmmoRow")
	var ammo_lbl: Label = btn.get_node_or_null("AmmoRow/AmmoCountLabel")
	var icon: TextureRect = btn.get_node_or_null("RifleIcon")
	var reload_row: HBoxContainer = btn.get_node_or_null("ReloadRow")
	var tip := _wire_tip_host(btn)
	## Empty primary/secondary: clear icon/AP/ammo — never fake kar98/glock.
	if w.is_empty():
		if shot_lbl != null:
			shot_lbl.text = ""
		if reload_row != null:
			reload_row.visible = false
		if reload_lbl != null:
			reload_lbl.visible = false
		if reload_ic != null:
			reload_ic.visible = false
		if ammo_row != null:
			ammo_row.visible = false
		if ammo_lbl != null:
			ammo_lbl.visible = false
		if icon != null:
			icon.texture = null
		if tip != null:
			tip.tip_item_id = ""
			tip.tip_qty = 0
			tip.tip_extra = []
		btn.tooltip_text = ""
		var empty_col: HBoxContainer = btn.get_node_or_null("AmmoRow/AmmoCol")
		if empty_col != null:
			for c in empty_col.get_children():
				c.queue_free()
		return
	var melee := bool(w.get("melee", false)) or ZZLos.is_melee_weapon(str(w.get("id", "")))
	var shoot_ap := int(w.get("shoot_ap", _shoot_cost if slot == _active_weapon_idx else 2))
	var reload_ap := int(w.get("reload_ap", 0))
	var in_mag := int(w.get("ammo_in_mag", _ammo_in_mag if slot == _active_weapon_idx else 0))
	var reserve := int(w.get("ammo_reserve", _ammo_reserve if slot == _active_weapon_idx else 0))
	var mag_size := int(w.get("mag_size", 0))
	var show_reload := not melee and reload_ap > 0
	var show_mag := not melee and mag_size > 0
	var total := in_mag + reserve
	var wid := str(w.get("id", ""))
	## Bottom «ОД:» text pad; reload icon has transparent bleed — pull row left to match.
	const CARD_PAD_X := 6.0
	const RELOAD_PAD_X := 2.0
	if shot_lbl != null:
		if slot == _active_weapon_idx and _fire_mode_hint == "Очередь":
			shot_lbl.text = "Оч: %d" % int(w.get("burst_ap", shoot_ap))
		elif slot == _active_weapon_idx and _fire_mode_hint == "Дуплет":
			shot_lbl.text = "Ду: %d" % int(w.get("duplet_ap", shoot_ap))
		elif shoot_ap > 0:
			shot_lbl.text = "ОД: %d" % shoot_ap
		elif int(w.get("burst_ap", 0)) > 0:
			shot_lbl.text = "Оч: %d" % int(w.get("burst_ap"))
		elif int(w.get("duplet_ap", 0)) > 0:
			shot_lbl.text = "Ду: %d" % int(w.get("duplet_ap"))
		else:
			shot_lbl.text = "ОД: —"
		shot_lbl.add_theme_font_size_override("font_size", 9)
		shot_lbl.offset_left = CARD_PAD_X
	if reload_row != null:
		reload_row.visible = show_reload
		if show_reload:
			reload_row.offset_left = RELOAD_PAD_X
			reload_row.offset_top = 2.0
			reload_row.offset_right = RELOAD_PAD_X + 70.0
			reload_row.offset_bottom = 16.0
			reload_row.add_theme_constant_override("separation", 1)
	if reload_lbl != null:
		reload_lbl.visible = show_reload
		if show_reload:
			reload_lbl.text = "%d ОД" % reload_ap
			reload_lbl.add_theme_font_size_override("font_size", 9)
	if reload_ic != null:
		reload_ic.visible = show_reload
		if show_reload:
			reload_ic.texture = ZZHudIcons.icon_reload(14)
	if ammo_row != null:
		ammo_row.visible = show_mag
		if show_mag:
			var card_w := maxf(btn.custom_minimum_size.x, btn.size.x)
			var half := maxf(52.0, card_w * 0.46)
			ammo_row.offset_left = -half
			ammo_row.offset_right = half
			ammo_row.offset_top = 14.0
			ammo_row.offset_bottom = 26.0
			ammo_row.add_theme_constant_override("separation", 2)
	if ammo_lbl != null:
		ammo_lbl.visible = show_mag
		if show_mag:
			ammo_lbl.text = "%d/%d" % [in_mag, total]
			ammo_lbl.add_theme_font_size_override("font_size", 9)
	if icon != null:
		var mock := ZZInventoryIcons.tex_tight(wid)
		if mock != null:
			icon.texture = mock
		elif wid == "glock17":
			icon.texture = ZZHudIcons.pistol(120, 40)
		else:
			icon.texture = ZZHudIcons.rifle(160, 48)
		var card_w2 := maxf(btn.custom_minimum_size.x, btn.size.x)
		_fit_weapon_icon(icon, card_w2)
	if tip != null:
		tip.tip_item_id = wid
		tip.tip_qty = 1
		var loaded := str(w.get("loaded_ammo_id", ""))
		var dmg := ZZLos.total_weapon_damage(wid, loaded)
		if w.has("damage_min"):
			dmg = Vector2i(int(w.get("damage_min", dmg.x)), int(w.get("damage_max", dmg.y)))
		var extra: Array = [
			["Урон", "%s–%s" % [ZZItemTooltip.fmt_val(dmg.x), ZZItemTooltip.fmt_val(dmg.y)]],
		]
		if melee:
			extra.append(["Тип", "Ближний бой"])
		else:
			extra.append(["Патроны", "%d/%d" % [in_mag, total]])
			if loaded != "":
				extra.append(["Заряжено", str(ZZLos.item_def(loaded).get("name", loaded))])
			if show_reload:
				var reload_hint := "%s ОД" % ZZItemTooltip.fmt_val(reload_ap)
				if slot == _active_weapon_idx:
					reload_hint += " · ПКМ"
				extra.append(["Перезарядка", reload_hint])
		if int(w.get("burst_ap", 0)) > 0:
			extra.append(["Очередь", "%s ОД" % ZZItemTooltip.fmt_val(w.get("burst_ap"))])
		if int(w.get("duplet_ap", 0)) > 0:
			extra.append(["Дуплет", "%s ОД" % ZZItemTooltip.fmt_val(w.get("duplet_ap"))])
		if slot == _active_weapon_idx and not melee and (int(w.get("burst_ap", 0)) > 0 or int(w.get("duplet_ap", 0)) > 0):
			extra.append(["Режим", _fire_mode_hint])
			extra.append(["Смена режима", "ЛКМ"])
		tip.tip_extra = extra
	btn.tooltip_text = " "  # non-empty → custom tip
	var col: HBoxContainer = btn.get_node_or_null("AmmoRow/AmmoCol")
	if show_mag:
		_refresh_ammo_bullets_on(col, in_mag, mag_size)
	elif col != null:
		for c in col.get_children():
			c.queue_free()


func _fit_weapon_icon(icon: TextureRect, card_w: float) -> void:
	## Keep icon inside the card; sit slightly below center (was too high).
	var half_w := minf(58.0, maxf(42.0, card_w * 0.40))
	icon.offset_left = -half_w
	icon.offset_right = half_w
	icon.offset_top = -16.0
	icon.offset_bottom = 14.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


func _refresh_weapon_slot_modulate() -> void:
	# Active: bright (or dim if needs reload and no AP). Inactive / empty: shaded.
	var active_hi := Color(1.0, 0.95, 0.82, 1.0) if _active_weapon_look_ok else ACTION_DIM
	var idle_col := ACTION_DIM if _switch_look_ok else Color(1, 1, 1, 0.28)
	var empty_col := Color(1, 1, 1, 0.28)
	if reload_btn != null:
		reload_btn.disabled = false
		if _weapon_at(0).is_empty():
			reload_btn.modulate = empty_col
		else:
			reload_btn.modulate = active_hi if _active_weapon_idx == 0 else idle_col
	if _weapon2_btn != null:
		_weapon2_btn.disabled = false
		if _weapon_at(1).is_empty():
			_weapon2_btn.modulate = empty_col
		else:
			_weapon2_btn.modulate = active_hi if _active_weapon_idx == 1 else idle_col


func _refresh_weapon_slot() -> void:
	if _weapon_slots.is_empty():
		_apply_weapon_slot_visuals()
	else:
		# Mirror ammo only — never overwrite reload_ap / mag_size / shoot_ap from globals
		# (that leaked knife reload_ap=0 onto the revolver while UI active_idx was stale).
		if _active_weapon_idx < _weapon_slots.size() and typeof(_weapon_slots[_active_weapon_idx]) == TYPE_DICTIONARY:
			var aw: Dictionary = _weapon_slots[_active_weapon_idx]
			var melee := bool(aw.get("melee", false)) or ZZLos.is_melee_weapon(str(aw.get("id", "")))
			if not melee:
				aw["ammo_in_mag"] = _ammo_in_mag
				aw["ammo_reserve"] = _ammo_reserve
		_apply_weapon_slot_visuals()


func _refresh_ammo_bullets_on(col: HBoxContainer, in_mag: int, mag_size: int) -> void:
	if col == null:
		return
	if mag_size <= 0:
		for c in col.get_children():
			c.queue_free()
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


func _layout_social() -> void:
	# Bottom-left: chat + players.
	chat_dock.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_dock.anchor_left = 0.0
	chat_dock.anchor_right = 0.0
	chat_dock.anchor_top = 1.0
	chat_dock.anchor_bottom = 1.0
	chat_dock.offset_left = SOCIAL_EDGE
	chat_dock.offset_right = SOCIAL_EDGE + CHAT_W
	chat_dock.offset_bottom = -CHAT_BOTTOM
	chat_dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_reveal_chat_history()


func _on_char_dock_resized() -> void:
	if _chat_history_visible:
		_apply_chat_dock_height(true)


func _char_dock_height() -> float:
	if char_dock != null:
		var h := char_dock.get_global_rect().size.y
		if h < 1.0:
			h = char_dock.size.y
		if h < 1.0:
			h = char_dock.get_combined_minimum_size().y
		if h > 1.0:
			return h
	return CHAT_H


func _apply_chat_dock_height(expanded: bool) -> void:
	# Expanded height = CharDock (action panel); collapsed keeps a thin strip.
	var h := _char_dock_height() if expanded else CHAT_COLLAPSED_H
	var w := CHAT_W if expanded else CHAT_W - 110.0
	if players_col != null:
		players_col.visible = expanded
	## Scene logs had min height 88 — that forced the dock taller than CharDock.
	if lobby_chat_log != null:
		lobby_chat_log.custom_minimum_size = Vector2(0, 0)
		lobby_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if battle_chat_log != null:
		battle_chat_log.custom_minimum_size = Vector2(0, 0)
		battle_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_dock.clip_contents = true
	chat_dock.custom_minimum_size = Vector2(w, h)
	## Cap growth: min alone loses to child mins; pin size + offsets.
	chat_dock.size = Vector2(w, h)
	chat_dock.offset_left = SOCIAL_EDGE
	chat_dock.offset_top = -(CHAT_BOTTOM + h)
	chat_dock.offset_bottom = -CHAT_BOTTOM


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



func _on_continue() -> void:
	var nick := nick_edit.text.strip_edges()
	if nick == "":
		set_login_error("Введите ник")
		return
	player_nick = nick
	_set_login_status("Подключение...")
	continue_btn.disabled = true
	## Lobby only after main confirms WebSocket (see main._on_continue).
	continue_pressed.emit(player_nick)


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
