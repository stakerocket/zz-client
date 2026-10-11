extends CanvasLayer
class_name ZZAppUI

signal continue_pressed(nick: String)
signal find_match_pressed
signal end_turn_pressed
signal undo_pressed
signal posture_pressed(posture: String)
signal chat_submitted(text: String, channel: String)
signal return_to_lobby_pressed

const DEFAULT_HP := 100
const DEFAULT_AP := 16
const TAB_LOBBY := 0
const TAB_BATTLE := 1

var player_nick: String = ""
var _in_battle_ui: bool = false

@onready var login_screen: Control = $LoginScreen
@onready var lobby_screen: Control = $LobbyScreen
@onready var battle_hud: Control = $BattleHud
@onready var chat_dock: PanelContainer = $ChatDock
@onready var bottom_bar: HBoxContainer = $BottomBar

@onready var nick_edit: LineEdit = $LoginScreen/Center/Panel/Margin/InnerCenter/VBox/NickEdit
@onready var continue_btn: Button = $LoginScreen/Center/Panel/Margin/InnerCenter/VBox/ContinueBtn
@onready var login_error: Label = $LoginScreen/Center/Panel/Margin/InnerCenter/VBox/ErrorLabel

@onready var lobby_nick: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/NickLabel
@onready var lobby_hp: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/HPLabel
@onready var lobby_ap: Label = $LobbyScreen/PlayerCard/VBox/InfoMargin/InfoVBox/APLabel
@onready var find_btn: Button = $LobbyScreen/FindCenter/FindBtn

@onready var chat_tabs: TabContainer = $ChatDock/Margin/VBox/Tabs
@onready var lobby_chat_log: RichTextLabel = $ChatDock/Margin/VBox/Tabs/Лобби
@onready var battle_chat_log: RichTextLabel = $ChatDock/Margin/VBox/Tabs/Бой
@onready var chat_edit: LineEdit = $ChatDock/Margin/VBox/InputRow/ChatEdit
@onready var chat_send_btn: Button = $ChatDock/Margin/VBox/InputRow/SendBtn
@onready var room_list: ItemList = $BottomBar/PlayersPanel/VBox/PlayerList

@onready var battle_turn: Label = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/TurnLabel
@onready var battle_timer: Label = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/TimerLabel
@onready var end_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/EndBtn
@onready var stand_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/PostureRow/StandBtn
@onready var sit_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/PostureRow/SitBtn
@onready var cover_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/PostureRow/CoverBtn
@onready var undo_btn: Button = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/UndoBtn
@onready var history_list: ItemList = $BattleHud/BattlePanel/VBox/InfoMargin/InfoVBox/HistoryList
@onready var battle_nick: Label = $BattleHud/PlayerCard/VBox/InfoMargin/InfoVBox/NickLabel
@onready var battle_hp: Label = $BattleHud/PlayerCard/VBox/InfoMargin/InfoVBox/HPLabel
@onready var battle_ap: Label = $BattleHud/PlayerCard/VBox/InfoMargin/InfoVBox/APLabel
@onready var battle_posture: Label = $BattleHud/PlayerCard/VBox/InfoMargin/InfoVBox/PostureLabel

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
	lobby_btn.pressed.connect(func(): return_to_lobby_pressed.emit())
	chat_send_btn.pressed.connect(_on_chat_send)
	chat_edit.text_submitted.connect(func(_t): _on_chat_send())
	chat_tabs.tab_changed.connect(_on_chat_tab_changed)
	end_btn.disabled = true
	undo_btn.disabled = true
	result_overlay.visible = false
	# Keep social UI above full-screen lobby/battle layers.
	chat_dock.z_index = 100
	bottom_bar.z_index = 100
	move_child(chat_dock, get_child_count() - 1)
	move_child(bottom_bar, get_child_count() - 1)
	lobby_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_login()


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
	lobby_hp.text = "ХП: %d" % DEFAULT_HP
	lobby_ap.text = "ОД: %d" % DEFAULT_AP
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


func set_turn(turn: int) -> void:
	battle_turn.text = "Ход %d" % turn


func set_timer_seconds(seconds: float) -> void:
	var s := maxi(0, int(ceil(seconds)))
	battle_timer.text = "%d:%02d" % [s / 60, s % 60]


func set_ap(value: int) -> void:
	battle_ap.text = "ОД: %d" % value
	if lobby_screen.visible:
		lobby_ap.text = "ОД: %d" % value


func set_hp(value: int) -> void:
	battle_hp.text = "ХП: %d" % value
	if lobby_screen.visible:
		lobby_hp.text = "ХП: %d" % value


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
	# Fixed strip: chat left, players right — identical in every screen.
	chat_dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	chat_dock.anchor_left = 0.0
	chat_dock.anchor_right = 1.0
	chat_dock.offset_left = 16.0
	chat_dock.offset_right = -268.0
	chat_dock.offset_top = -240.0
	chat_dock.offset_bottom = -16.0
	chat_dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_bar.anchor_left = 1.0
	bottom_bar.anchor_right = 1.0
	bottom_bar.anchor_top = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.offset_left = -252.0
	bottom_bar.offset_right = -16.0
	bottom_bar.offset_top = -240.0
	bottom_bar.offset_bottom = -16.0
	bottom_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN


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
