extends CanvasLayer
class_name ZZAppUI

signal continue_pressed(nick: String)
signal find_match_pressed
signal end_turn_pressed
signal undo_pressed
signal posture_pressed(posture: String)
signal medkit_pressed
signal reload_pressed
signal chat_submitted(text: String, channel: String)
signal return_to_lobby_pressed

const TAB_LOBBY := 0
const TAB_BATTLE := 1
const CHAT_W := 300.0
const CHAT_H := 150.0
const CHAT_COLLAPSED_H := 36.0
const PLAYERS_W := 160.0
const SOCIAL_EDGE := 8.0
const CHAT_FADE_IDLE_SEC := 7.0
const CHAT_FADE_DUR := 0.45

var player_nick: String = ""
var _in_battle_ui: bool = false
var _chat_history_visible: bool = true
var _chat_fade_tween: Tween
var _chat_idle_timer: Timer

@onready var login_screen: Control = $LoginScreen
@onready var lobby_screen: Control = $LobbyScreen
@onready var battle_hud: Control = $BattleHud
@onready var chat_dock: PanelContainer = $ChatDock
@onready var bottom_bar: HBoxContainer = $BottomBar

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

@onready var chat_tabs: TabContainer = $ChatDock/Margin/VBox/Tabs
@onready var lobby_chat_log: RichTextLabel = $ChatDock/Margin/VBox/Tabs/Лобби
@onready var battle_chat_log: RichTextLabel = $ChatDock/Margin/VBox/Tabs/Бой
@onready var chat_input_frame: PanelContainer = $ChatDock/Margin/VBox/InputFrame
@onready var chat_edit: LineEdit = $ChatDock/Margin/VBox/InputFrame/InputRow/ChatEdit
@onready var chat_send_btn: Button = $ChatDock/Margin/VBox/InputFrame/InputRow/SendBtn
@onready var players_panel: PanelContainer = $BottomBar/PlayersPanel
@onready var room_list: ItemList = $BottomBar/PlayersPanel/VBox/PlayerList

@onready var battle_turn: Label = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/TurnLabel
@onready var battle_timer: Label = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/TimerLabel
@onready var end_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/EndBtn
@onready var stand_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/PostureRow/StandBtn
@onready var sit_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/PostureRow/SitBtn
@onready var cover_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/PostureRow/CoverBtn
@onready var medkit_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/MedkitBtn
@onready var reload_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/ReloadBtn
@onready var undo_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/UndoBtn
@onready var history_list: ItemList = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/HistoryList
@onready var battle_nick: Label = $BattleHud/PlayerCard/VBox/CardTitle
@onready var battle_hp: Label = $BattleHud/PlayerCard/VBox/InfoMargin/InfoVBox/HPLabel
@onready var battle_ap: Label = $BattleHud/PlayerCard/VBox/InfoMargin/InfoVBox/APLabel
@onready var battle_posture: Label = $BattleHud/PlayerCard/VBox/InfoMargin/InfoVBox/PostureLabel
@onready var battle_ammo: Label = $BattleHud/PlayerCard/VBox/InfoMargin/InfoVBox/AmmoLabel
@onready var battle_medkits: Label = $BattleHud/PlayerCard/VBox/InfoMargin/InfoVBox/MedkitsLabel

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
	cover_btn.pressed.connect(func(): posture_pressed.emit("cover"))
	medkit_btn.pressed.connect(func(): medkit_pressed.emit())
	reload_btn.pressed.connect(func(): reload_pressed.emit())
	lobby_btn.pressed.connect(func(): return_to_lobby_pressed.emit())
	chat_send_btn.pressed.connect(_on_chat_send)
	chat_edit.text_submitted.connect(func(_t): _on_chat_send())
	chat_tabs.tab_changed.connect(_on_chat_tab_changed)
	chat_edit.focus_entered.connect(_reveal_chat_history)
	chat_dock.gui_input.connect(_on_chat_dock_gui_input)
	end_btn.disabled = true
	undo_btn.disabled = true
	result_overlay.visible = false
	# Keep social UI above full-screen lobby/battle layers.
	chat_dock.z_index = 100
	bottom_bar.z_index = 100
	move_child(chat_dock, get_child_count() - 1)
	move_child(bottom_bar, get_child_count() - 1)
	lobby_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Chat + players panel must block map clicks (STOP).
	chat_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_STOP
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
	battle_turn.text = "Ход %d" % turn


func set_timer_seconds(seconds: float) -> void:
	var s := maxi(0, int(ceil(seconds)))
	battle_timer.text = "%d:%02d" % [s / 60, s % 60]


func refresh_lobby_stats_from_rules() -> void:
	if not ZZLos.has_rules():
		_set_lobby_stats_placeholder()
		return
	var lvl := ZZLos.rule_i("default_level")
	var s := ZZLos.default_stat()
	lobby_level.text = "Уровень: %d" % lvl
	lobby_str.text = "Сила: %d" % s
	lobby_agi.text = "Ловкость: %d" % s
	lobby_end.text = "Выносливость: %d" % s
	lobby_intu.text = "Интуиция: %d" % s
	lobby_acc.text = "Меткость: %d" % s
	lobby_int.text = "Интеллект: %d" % s
	lobby_hp.text = "ХП: %d" % ZZLos.compute_max_hp(s)
	lobby_ap.text = "ОД: %d" % ZZLos.compute_max_ap(s, s, s)
	lobby_carry.text = "Вес: %d" % ZZLos.compute_carry_weight(s)


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
	battle_ap.text = "ОД: %d" % value


func set_hp(value: int) -> void:
	battle_hp.text = "ХП: %d" % value


func set_posture(posture: String) -> void:
	var label := "стоя"
	if posture == "sit":
		label = "сидя"
	elif posture == "cover":
		label = "укрылся"
	battle_posture.text = "Стойка: %s" % label


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


func set_end_enabled(enabled: bool) -> void:
	end_btn.disabled = not enabled
	stand_btn.disabled = not enabled
	sit_btn.disabled = not enabled
	cover_btn.disabled = not enabled


func set_medkit_enabled(enabled: bool) -> void:
	medkit_btn.disabled = not enabled


func set_reload_enabled(enabled: bool) -> void:
	if reload_btn != null:
		reload_btn.disabled = not enabled


func set_medkit_count(count: int, heal_min: int = 15, heal_max: int = 30, ap_cost: int = 3) -> void:
	medkit_btn.text = "Аптечка ×%d (+%d–%d / %d)" % [maxi(0, count), heal_min, heal_max, ap_cost]
	if battle_medkits != null:
		battle_medkits.text = "Аптечки: %d" % maxi(0, count)


func set_reload_cost(ap_cost: int) -> void:
	if reload_btn != null:
		reload_btn.text = "Перезарядка (%d)" % ap_cost


func set_ammo(in_mag: int, reserve: int) -> void:
	if battle_ammo != null:
		battle_ammo.text = "Патроны: %d | %d" % [maxi(0, in_mag), maxi(0, reserve)]


func set_undo_enabled(enabled: bool) -> void:
	undo_btn.disabled = not enabled


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
	bottom_bar.visible = visible


func _layout_social() -> void:
	# Corner docks: map stays visible in the center bottom.
	chat_dock.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_dock.anchor_left = 0.0
	chat_dock.anchor_right = 0.0
	chat_dock.anchor_top = 1.0
	chat_dock.anchor_bottom = 1.0
	chat_dock.offset_left = SOCIAL_EDGE
	chat_dock.offset_right = SOCIAL_EDGE + CHAT_W
	chat_dock.offset_bottom = -SOCIAL_EDGE
	chat_dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_bar.anchor_left = 1.0
	bottom_bar.anchor_right = 1.0
	bottom_bar.anchor_top = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.offset_left = -(SOCIAL_EDGE + PLAYERS_W)
	bottom_bar.offset_right = -SOCIAL_EDGE
	bottom_bar.offset_top = -(SOCIAL_EDGE + CHAT_H)
	bottom_bar.offset_bottom = -SOCIAL_EDGE
	bottom_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom_bar.custom_minimum_size = Vector2(PLAYERS_W, CHAT_H)
	if players_panel != null:
		players_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reveal_chat_history()


func _apply_chat_dock_height(expanded: bool) -> void:
	var h := CHAT_H if expanded else CHAT_COLLAPSED_H
	chat_dock.custom_minimum_size = Vector2(CHAT_W, h)
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
