class_name WindowHandle
extends Control
## Alça da janela: arrastar (start_drag), gaveta, som e recolher.
## Recolhida, a janela vira uma aba de ~48×16 com icon_show e no máximo uma luz verde de atenção;
## clique na aba restaura, arrastar a aba move a janela. A simulação segue (WindowService cuida).

signal drawer_toggled(open: bool)
signal collapsed_changed(on: bool)
## Segundo clique no X (o primeiro só pergunta "Sair?"): quem escuta fecha o jogo (o WindowService salva antes).
signal quit_requested()

const TAB_SIZE := Vector2i(48, 16)
const PULSE_SECONDS: float = 10.0
const DRAG_THRESHOLD: float = 3.0
const QUIT_ASK_SECONDS: float = 3.0

var collapsed: bool = false
var drawer_open: bool = false

var _row: HBoxContainer
var _grab: Button
var _drawer_btn: Button
var _sound_btn: Button
var _collapse_btn: Button
var _close_btn: Button
var _quit_ask_left: float = 0.0
var _tab_layer: CanvasLayer
var _tab: Control
var _light: ColorRect
var _attention: bool = false
var _pulse_left: float = 0.0
var _press_pos: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _last_sound_mode: String = "ambient"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	ScreenUtil.connect_to("I18n", "locale_changed", _on_locale_changed)
	ScreenUtil.connect_to("Settings", "changed", _on_setting_changed)
	ScreenUtil.connect_to("WindowService", "hidden_changed", _on_hidden_changed)
	for s: String in ["radio_line", "house_item_bought", "antenna_changed", "item_finished"]:
		ScreenUtil.connect_to("Game", s, _on_game_event)
	ScreenUtil.connect_to("Game", "state_changed", _refresh_attention)
	ScreenUtil.connect_to("Game", "box_state_changed", _on_box_state)
	collapsed = bool(ScreenUtil.call_on("WindowService", "is_collapsed", [], false))
	_apply_collapsed_view()
	_refresh_attention()


func _exit_tree() -> void:
	ScreenUtil.disconnect_from("I18n", "locale_changed", _on_locale_changed)
	ScreenUtil.disconnect_from("Settings", "changed", _on_setting_changed)
	ScreenUtil.disconnect_from("WindowService", "hidden_changed", _on_hidden_changed)


## Recolhe/expande. Usa WindowService quando há; o visual da aba é desta cena.
func set_collapsed(on: bool) -> void:
	if on == collapsed:
		return
	collapsed = on
	ScreenUtil.call_on("WindowService", "set_collapsed", [on])
	_apply_collapsed_view()
	collapsed_changed.emit(on)


## O fluxo avisa quando a gaveta abriu/fechou por outro caminho (troca o ícone).
func set_drawer_open(open: bool) -> void:
	drawer_open = open
	_update_icons()


## Liga a luz de atenção (pulsa por 10 s; para no hover; fica acesa enquanto a causa existir).
func notify_attention() -> void:
	_refresh_attention()
	if _attention:
		_pulse_left = PULSE_SECONDS


func has_attention() -> bool:
	return _attention


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	theme = UiTheme.build()
	# Fundo escuro discreto: os ícones claros somem sobre o céu de dia.
	var back := ColorRect.new()
	back.name = "Back"
	back.color = Color(UiTheme.INK, 0.55)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override("separation", 0)
	add_child(_row)

	_grab = ScreenUtil.icon_button("grab", "ui.handle")
	_grab.name = "Grab"
	_grab.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_grab.button_down.connect(_on_grab_down)
	_row.add_child(_grab)

	_drawer_btn = ScreenUtil.icon_button("arrow_up")
	_drawer_btn.name = "Drawer"
	_drawer_btn.pressed.connect(_on_drawer_pressed)
	_row.add_child(_drawer_btn)

	_sound_btn = ScreenUtil.icon_button("speaker_off")
	_sound_btn.name = "Sound"
	_sound_btn.pressed.connect(_on_sound_pressed)
	_row.add_child(_sound_btn)

	_collapse_btn = ScreenUtil.icon_button("hide", "tray.collapse")
	_collapse_btn.name = "Collapse"
	_collapse_btn.pressed.connect(func() -> void: set_collapsed(true))
	_row.add_child(_collapse_btn)

	_close_btn = ScreenUtil.icon_button("quit", "screens.handle.quit")
	_close_btn.name = "Close"
	_close_btn.pressed.connect(_on_close_pressed)
	_row.add_child(_close_btn)

	custom_minimum_size = _row.get_combined_minimum_size()
	size = custom_minimum_size
	_build_tab()
	_update_icons()


func _build_tab() -> void:
	# Aba recolhida: camada própria por cima de tudo, ocupa a janela inteira (48×16).
	_tab_layer = CanvasLayer.new()
	_tab_layer.name = "TabLayer"
	_tab_layer.layer = 101   # acima da aba genérica do WindowService (camada 100)
	add_child(_tab_layer)
	_tab = Control.new()
	_tab.name = "Tab"
	_tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tab.mouse_filter = Control.MOUSE_FILTER_STOP
	_tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_tab.tooltip_text = ScreenUtil.tr_key("tray.show")
	_tab.gui_input.connect(_on_tab_input)
	_tab.mouse_entered.connect(_stop_pulse)
	_tab_layer.add_child(_tab)
	var border := ColorRect.new()
	border.color = UiTheme.INK
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab.add_child(border)
	var fill := ColorRect.new()
	fill.color = UiTheme.DARK2
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.offset_left = 1
	fill.offset_top = 1
	fill.offset_right = -1
	fill.offset_bottom = -1
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab.add_child(fill)
	var top_line := ColorRect.new()   # realce de luz em cima, como os painéis
	top_line.color = UiTheme.DARK3
	top_line.position = Vector2(1, 1)
	top_line.size = Vector2(TAB_SIZE.x - 2, 1)
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab.add_child(top_line)
	var show_icon := TextureRect.new()
	show_icon.texture = UiTheme.icon("show")
	show_icon.position = Vector2(4, 4)
	show_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab.add_child(show_icon)
	var radio := TextureRect.new()
	radio.texture = UiTheme.icon("radio")
	radio.position = Vector2(20, 4)
	radio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab.add_child(radio)
	# Luz de atenção: 1 só, 3×3 com moldura escura (apagada = dark3)
	var socket := ColorRect.new()
	socket.color = UiTheme.INK
	socket.position = Vector2(TAB_SIZE.x - 11, 5)
	socket.size = Vector2(5, 5)
	socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab.add_child(socket)
	_light = ColorRect.new()
	_light.name = "Light"
	_light.position = Vector2(TAB_SIZE.x - 10, 6)
	_light.size = Vector2(3, 3)
	_light.color = UiTheme.DARK3
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab.add_child(_light)


func _apply_collapsed_view() -> void:
	if _tab_layer == null:
		return
	_tab_layer.visible = collapsed
	_row.visible = not collapsed
	(get_node("Back") as CanvasItem).visible = not collapsed
	if collapsed:
		_refresh_attention()
	_update_light()


## X da janela: o primeiro clique pergunta "Sair?" por uns segundos; o segundo fecha (salvando).
func _on_close_pressed() -> void:
	if _quit_ask_left > 0.0:
		_quit_ask_left = 0.0
		_refresh_close()
		quit_requested.emit()
		return
	_quit_ask_left = QUIT_ASK_SECONDS
	_refresh_close()


func is_asking_quit() -> bool:
	return _quit_ask_left > 0.0


func _refresh_close() -> void:
	var ask: bool = _quit_ask_left > 0.0
	if ask:
		_close_btn.icon = null
		_close_btn.text = ScreenUtil.tr_key("screens.handle.quit.ask")
		_close_btn.add_theme_color_override("font_color", UiTheme.AMBER3)
	else:
		_close_btn.icon = UiTheme.icon("quit")
		_close_btn.text = ""
		_close_btn.remove_theme_color_override("font_color")
	custom_minimum_size = _row.get_combined_minimum_size()
	size = custom_minimum_size


func _update_icons() -> void:
	if _drawer_btn == null:
		return
	_drawer_btn.icon = UiTheme.icon("arrow_down" if drawer_open else "arrow_up")
	_drawer_btn.tooltip_text = ScreenUtil.tr_key("screens.handle.drawer.close" if drawer_open else "screens.handle.drawer.open")
	var on: bool = _sound_on()
	_sound_btn.icon = UiTheme.icon("speaker_on" if on else "speaker_off")
	_sound_btn.tooltip_text = ScreenUtil.tr_key("screens.handle.sound.off" if on else "screens.handle.sound.on")


func _sound_on() -> bool:
	var mode: String = str(ScreenUtil.setting("audio_mode", "ambient"))
	var unlocked: bool = bool(ScreenUtil.setting("sound_unlocked", false))
	return mode != "silent" and unlocked


func _process(delta: float) -> void:
	if _quit_ask_left > 0.0:
		_quit_ask_left -= delta
		if _quit_ask_left <= 0.0:
			_quit_ask_left = 0.0
			_refresh_close()
	if _pulse_left > 0.0:
		_pulse_left = maxf(0.0, _pulse_left - delta)
		_update_light()
	if _pressing and collapsed:
		var m: Vector2 = get_viewport().get_mouse_position()
		if m.distance_to(_press_pos) >= DRAG_THRESHOLD:
			_pressing = false
			ScreenUtil.call_on("WindowService", "start_drag")


func _update_light() -> void:
	if _light == null:
		return
	if not _attention:
		_light.color = UiTheme.DARK3
		return
	var c: Color = UiTheme.SIGNAL
	var calm: bool = bool(ScreenUtil.setting("reduce_flicker", false))
	if _pulse_left > 0.0 and not calm:
		# liga/desliga a cada 0,5 s (funciona até a 2 fps do modo recolhido)
		var on: bool = int(_pulse_left * 2.0) % 2 == 0
		c = UiTheme.SIGNAL if on else UiTheme.LEAF2
	_light.color = c


func _refresh_attention(_a: Variant = null, _b: Variant = null) -> void:
	var was: bool = _attention
	var unread: int = int(ScreenUtil.call_on("Game", "unread_count", [], 0))
	var goal: bool = bool(ScreenUtil.call_on("Game", "goal_ready", [], false))
	var box_over: bool = float(ScreenUtil.call_on("Game", "box_fill", [], 0.0)) > 1.0
	var no_power: bool = not bool(ScreenUtil.call_on("Game", "power_ok", [], true))
	_attention = unread > 0 or goal or box_over or no_power
	if _attention and not was:
		_pulse_left = PULSE_SECONDS
	if not _attention:
		_pulse_left = 0.0
	_update_light()


func _on_game_event(_a: Variant = null, _b: Variant = null) -> void:
	notify_attention()


func _on_box_state(_fill: float, overflow: bool) -> void:
	if overflow:
		notify_attention()
	else:
		_refresh_attention()


func _stop_pulse() -> void:
	_pulse_left = 0.0
	_update_light()


func _on_tab_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_pressing = true
		_press_pos = get_viewport().get_mouse_position()
	elif _pressing:
		_pressing = false
		set_collapsed(false)
	_tab.accept_event()


func _on_grab_down() -> void:
	ScreenUtil.call_on("WindowService", "start_drag")


func _on_drawer_pressed() -> void:
	drawer_open = not drawer_open
	_update_icons()
	drawer_toggled.emit(drawer_open)


func _on_sound_pressed() -> void:
	var mode: String = str(ScreenUtil.setting("audio_mode", "ambient"))
	ScreenUtil.call_on("AudioManager", "unlock")
	if _sound_on():
		_last_sound_mode = mode
		mode = "silent"
	else:
		mode = _last_sound_mode if mode == "silent" else mode
		ScreenUtil.set_setting("sound_unlocked", true)
	ScreenUtil.set_setting("audio_mode", mode)
	ScreenUtil.call_on("AudioManager", "set_mode", [mode])
	_update_icons()


func _on_hidden_changed(is_hidden: bool) -> void:
	if is_hidden == collapsed:
		return
	collapsed = is_hidden
	_apply_collapsed_view()
	collapsed_changed.emit(is_hidden)


func _on_locale_changed(_code: String) -> void:
	call_deferred("_rebuild_keep")


func _on_setting_changed(key: String) -> void:
	if key in ["audio_mode", "sound_unlocked"]:
		_update_icons()
	elif key == "reduce_flicker":
		_update_light()


func _rebuild_keep() -> void:
	_build()
	_apply_collapsed_view()
