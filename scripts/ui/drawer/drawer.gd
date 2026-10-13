class_name Drawer
extends Control
## Gaveta de gestão: cresce a janela para cima (WindowService.set_drawer) e mostra até 4 abas
## (Construir, Rádio + uma livre, p.ex. Opções, via add_tab). Também cuida dos avisos
## curtos (toasts), do resumo de "bem-vindo de volta" e da camada de posicionar/escolher
## objetos sobre a faixa do bunker.
##
## Uso na cena principal: instanciar scenes/ui/drawer.tscn num CanvasLayer acima do bunker,
## com âncora em tela cheia. Aberta, a gaveta ocupa y 0..DRAWER_H e a faixa fica embaixo,
## em y DRAWER_H..DRAWER_H+STRIP_H (strip_offset). Fechada, só os avisos aparecem (sobre a faixa).
## Abrir: drawer.open("build"), drawer.select_instance(id) (clique num objeto), drawer.toggle().

signal open_changed(is_open: bool)
signal tab_changed(tab_id: String)
signal placement_changed(mode: String, item_id: String)
## Ao começar a posicionar: o retângulo (no mundo) das posições, para a câmera mostrar onde dá para pôr.
signal reveal_requested(world_rect: Rect2)
## Clicou numa obra com a gaveta aberta: a cena manda ele vir martelar.
signal order_requested(instance_id: int)

const DRAWER_H: int = 120
const MIN_W: int = 344
const MAX_TABS: int = 4
const REFRESH_S: float = 0.25

## Game em uso (o autoload por padrão; os testes injetam um falso com bind_game).
var game: Node = null
## Altura da faixa do bunker abaixo da gaveta (cresce a cada sala cavada; quem manda é a Main).
var strip_h: int = BunkerGeo.H

var _open: bool = false
var _tab: String = "build"
var _tab_ids: Array[String] = []
var _tab_buttons: Dictionary = {}   # id -> Button
var _tab_title_keys: Dictionary = {}
var _tab_icons: Dictionary = {}
var _pages: Dictionary = {}         # id -> Control
var _place_mode: String = ""        # "" | "buy" | "move"
var _place_item: String = ""
var _place_inst: int = -1
var _dirty: bool = true
var _refresh_t: float = 0.0
var _names: Dictionary = {}         # instance_id -> item_id (para o aviso de desmontado)
var _goal_was_ready: bool = false

var _panel: PanelContainer
var _header: HBoxContainer
var _badge: Label
var _scrap: HBoxContainer
var _content: Control
var _overlay: DrawerPlacementOverlay
var _toasts: DrawerToastLayer
var _welcome: DrawerWelcomeCard
var build_tab: DrawerBuildTab
var radio_tab: DrawerRadioTab


func _init() -> void:
	theme = UiTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_bottom = DRAWER_H
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_panel.add_child(v)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 1)
	v.add_child(_header)
	_badge = DrawerUi.colored("", UiTheme.SIGNAL, "LabelSmall")
	_badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.name = "Spacer"
	_header.add_child(spacer)
	_scrap = DrawerUi.icon_text("sucata", "0", "LabelAmber")
	_scrap.size_flags_horizontal = Control.SIZE_SHRINK_END
	_header.add_child(_scrap)
	var close_b: Button = DrawerUi.icon_button("close")
	close_b.name = "CloseButton"
	close_b.pressed.connect(close)
	_header.add_child(close_b)
	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.clip_contents = true
	v.add_child(_content)
	build_tab = DrawerBuildTab.new()
	build_tab.drawer = self
	radio_tab = DrawerRadioTab.new()
	radio_tab.drawer = self
	add_tab("build", "tab.build", "hammer", build_tab)
	add_tab("radio", "tab.radio", "radio", radio_tab)
	_welcome = DrawerWelcomeCard.new()
	_welcome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_welcome.dismissed.connect(_on_welcome_dismissed)
	_content.add_child(_welcome)
	_overlay = DrawerPlacementOverlay.new()
	_overlay.name = "PlacementOverlay"
	_overlay.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_overlay.offset_top = DRAWER_H
	_overlay.offset_bottom = DRAWER_H + strip_h
	_overlay.spot_picked.connect(_on_spot_picked)
	_overlay.instance_picked.connect(_on_instance_picked)
	_overlay.cancelled.connect(cancel_placement)
	add_child(_overlay)
	_toasts = DrawerToastLayer.new()
	_toasts.name = "Toasts"
	_toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toasts.offset_left = -220
	_toasts.offset_right = -4
	add_child(_toasts)
	_place_toasts()
	_show_page()


func _ready() -> void:
	if game == null:
		bind_game(get_node_or_null("/root/Game"))
	var i18n: Node = get_node_or_null("/root/I18n")
	if i18n != null and i18n.has_signal("locale_changed"):
		i18n.connect("locale_changed", _on_locale_changed)
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.has_signal("changed"):
		settings.connect("changed", _on_setting_changed)
	_retitle_tabs()


# ---- API -------------------------------------------------------------------

## Liga a gaveta a um Game (autoload ou falso dos testes) e aos sinais dele.
func bind_game(g: Node) -> void:
	game = g
	if not has_game():
		return
	var links: Dictionary = {
		"state_changed": _on_state_changed, "diary_changed": _on_state_changed,
		"item_placed": _on_item_placed, "item_finished": _on_item_finished,
		"item_removed": _on_item_removed, "room_dug": _on_room_dug,
		"antenna_changed": _on_antenna_changed, "house_item_bought": _on_house_item,
		"welcome_back": show_welcome,
	}
	for s: String in links:
		if g.has_signal(s) and not g.is_connected(s, links[s]):
			g.connect(s, links[s])
	_cache_names()
	_goal_was_ready = bool(g.goal_ready())
	_dirty = true


## true se o Game tem a API do contrato (o stub vazio não tem).
func has_game() -> bool:
	return game != null and game.has_method("catalog")


func audio() -> Node:
	return get_node_or_null("/root/AudioManager") if is_inside_tree() else null


func is_open() -> bool:
	return _open


func current_tab() -> String:
	return _tab


func open(tab_id: String = "") -> void:
	if tab_id != "":
		show_tab(tab_id)
	if _open:
		return
	_open = true
	_panel.visible = true
	_window_drawer(true)
	_place_toasts()
	refresh(true)
	open_changed.emit(true)


func close() -> void:
	if not _open:
		return
	cancel_placement()
	if _tab == "radio":
		radio_tab.mark_read()
	_welcome.visible = false
	_open = false
	_panel.visible = false
	_overlay.clear()
	_window_drawer(false)
	_place_toasts()
	open_changed.emit(false)


func toggle(tab_id: String = "") -> void:
	if _open and (tab_id == "" or tab_id == _tab):
		close()
	else:
		open(tab_id)


func show_tab(tab_id: String) -> void:
	if not _pages.has(tab_id):
		return
	if tab_id != _tab:
		if _tab == "radio":
			radio_tab.mark_read()
		if _tab == "build":
			cancel_placement()
		_tab = tab_id
		tab_changed.emit(tab_id)
	_welcome.visible = false
	_show_page()
	refresh(true)


func set_strip_height(h: int) -> void:
	strip_h = h
	if _toasts != null:
		_place_toasts()
	if _overlay != null:
		_overlay.offset_bottom = DRAWER_H + strip_h


## Clique numa estrutura com a gaveta aberta: seleciona como sempre e, enquanto a ajuda vale, também é um
## pedido para ele (vir martelar ou cuidar das plantas, como o clique com a gaveta fechada; quem trata é a cena).
func _on_instance_picked(instance_id: int) -> void:
	select_instance(instance_id)
	if game != null and game.has_method("help_available") and bool(game.call("help_available")):
		order_requested.emit(instance_id)


## Abre a aba Construir com o objeto escolhido (cultura, mover, desmontar).
func select_instance(instance_id: int) -> void:
	cancel_placement()
	open("build")
	build_tab.select_instance(instance_id)


## Até 4 abas; a 4ª é livre (Opções do módulo de telas). `page` ocupa o conteúdo inteiro.
func add_tab(tab_id: String, title_key: String, icon_name: String, page: Control) -> void:
	if _pages.has(tab_id) or _pages.size() >= MAX_TABS:
		push_warning("Drawer: aba '%s' recusada (repetida ou acima de %d)" % [tab_id, MAX_TABS])
		return
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.visible = false
	_content.add_child(page)
	if _welcome != null:
		_content.move_child(_welcome, -1)
	_pages[tab_id] = page
	_tab_ids.append(tab_id)
	_tab_title_keys[tab_id] = title_key
	_tab_icons[tab_id] = icon_name
	var b: Button = DrawerUi.button(I18nRef.t(title_key), icon_name)
	b.name = "Tab_" + tab_id
	b.pressed.connect(show_tab.bind(tab_id))
	_tab_buttons[tab_id] = b
	_header.add_child(b)
	if tab_id == "radio":
		_header.add_child(_badge)
	_order_header()
	_style_tabs()


## Abas na ordem em que foram adicionadas; o contador de novas fica logo após "Rádio".
func _order_header() -> void:
	var i: int = 0
	for id: String in _tab_ids:
		_header.move_child(_tab_buttons[id], i)
		i += 1
		if id == "radio":
			_header.move_child(_badge, i)
			i += 1


## Aviso curto. `key` é chave do I18n (ou texto pronto se a chave não existir).
func toast(key: String, args: Dictionary = {}, icon_name: String = "") -> void:
	var text: String = I18nRef.t(key, args) if I18nRef.has_key(key) else key
	_toasts.push(text, icon_name)


func toasts() -> DrawerToastLayer:
	return _toasts


## Resumo da ausência: abre a gaveta com o cartão por cima das abas.
func show_welcome(summary: Dictionary) -> void:
	open()
	_welcome.show_summary(summary)


func welcome_visible() -> bool:
	return _welcome.visible


func overlay() -> DrawerPlacementOverlay:
	return _overlay


# ---- posicionar ------------------------------------------------------------

func start_placement(mode: String, item_id: String, instance_id: int, hints: Array, cols: int) -> void:
	_place_mode = mode
	_place_item = item_id
	_place_inst = instance_id
	_overlay.show_hints(hints, cols)
	placement_changed.emit(mode, item_id)
	var rs: Array[Rect2] = _overlay.world_rects()
	if not rs.is_empty() and not _hints_visible(rs):
		reveal_requested.emit(rs[0])


## Alguma posição já está dentro da janela (faixa de strip_h px a partir da rolagem atual)?
func _hints_visible(rs: Array[Rect2]) -> bool:
	for r: Rect2 in rs:
		if r.position.y >= _overlay.scroll_y and r.end.y <= _overlay.scroll_y + float(strip_h):
			return true
	return false


## A vista rolou: a camada de posicionar acompanha.
func set_scroll(y: float) -> void:
	if _overlay != null:
		_overlay.set_scroll(y)


func cancel_placement() -> void:
	if _place_mode == "":
		return
	_place_mode = ""
	_place_item = ""
	_place_inst = -1
	placement_changed.emit("", "")
	update_overlay()
	if build_tab != null and has_game():
		build_tab.refresh(true)


func placement_mode() -> String:
	return _place_mode


func placing_item() -> String:
	return _place_item


## Recalcula o que a camada sobre a faixa mostra (posições ou objetos clicáveis).
func update_overlay() -> void:
	if _place_mode != "":
		return
	if _open and _tab == "build" and has_game() and not _welcome.visible:
		_overlay.show_targets(game.instances(), build_tab.selected_instance())
	else:
		_overlay.clear()


func _on_spot_picked(room: int, col: int) -> void:
	var mode: String = _place_mode
	var item: String = _place_item
	var r: Dictionary
	if mode == "buy":
		r = game.buy(item, room, col)
	elif mode == "move":
		r = game.move(_place_inst, room, col)
	else:
		return
	if bool(r.get("ok", false)):
		var inst: int = _place_inst
		cancel_placement()
		if mode == "move":
			toast("toast.item_moved", {"item": I18nRef.t("item.%s.name" % item)}, "grab")
			build_tab.select_instance(inst)
	elif mode == "buy":
		build_tab._report(r, build_tab.why_not(item, room, col))
	else:
		build_tab._report(r)


# ---- atualização -----------------------------------------------------------

func refresh(force: bool = false) -> void:
	_dirty = false
	_refresh_t = 0.0
	if not has_game():
		return
	(_scrap.get_child(1) as Label).text = I18nRef.t("hud.scrap", {"n": int(game.sucata())})
	var unread: int = int(game.unread_count())
	_badge.text = "" if unread == 0 else str(unread)
	_badge.tooltip_text = I18nRef.t("ui.unread", {"n": unread})
	if not _open:
		return
	var page: Control = _pages.get(_tab)
	if page != null and page.has_method("refresh"):
		page.call("refresh", force)
	update_overlay()


func _process(delta: float) -> void:
	if not _dirty:
		return
	_refresh_t += delta
	if _refresh_t >= REFRESH_S:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		if _place_mode != "":
			cancel_placement()
		else:
			close()
		get_viewport().set_input_as_handled()


func _show_page() -> void:
	for id: String in _pages:
		(_pages[id] as Control).visible = id == _tab
	_style_tabs()


func _style_tabs() -> void:
	for id: String in _tab_buttons:
		var b: Button = _tab_buttons[id]
		var active: bool = id == _tab
		var sb: StyleBoxTexture = UiTheme.nine("tab_active" if active else "tab_normal", 4.0, 1.0)
		for st: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_color", UiTheme.AMBER3 if active else UiTheme.CONC4)
		b.add_theme_color_override("font_hover_color", UiTheme.AMBER3 if active else UiTheme.PAPER)


func _retitle_tabs() -> void:
	for id: String in _tab_buttons:
		(_tab_buttons[id] as Button).text = I18nRef.t(str(_tab_title_keys[id]))


func _place_toasts() -> void:
	# no pé da faixa (o alto fica com a barra de status e as alças da janela); aberta, abaixo da gaveta
	var top: int = (DRAWER_H if _open else 0) + maxi(2, strip_h - 24)
	_toasts.offset_top = top
	_toasts.offset_bottom = top + 20


func _window_drawer(on: bool) -> void:
	var ws: Node = get_node_or_null("/root/WindowService") if is_inside_tree() else null
	if ws != null and ws.has_method("set_drawer"):
		ws.call("set_drawer", on, DRAWER_H, MIN_W)


func _cache_names() -> void:
	if not has_game():
		return
	for d: Dictionary in game.instances():
		_names[int(d.get("id", -1))] = str(d.get("item", ""))


func _item_name(item_id: String) -> String:
	return I18nRef.t("item.%s.name" % item_id)


# ---- sinais do Game ----------------------------------------------------------

func _on_state_changed() -> void:
	_dirty = true
	var ready_now: bool = bool(game.goal_ready())
	if ready_now and not _goal_was_ready:
		var goal: String = str(game.pinned_goal())
		if goal != "":
			toast("toast.goal_ready", {"item": _item_name(goal)}, "estrela")
	_goal_was_ready = ready_now


func _on_item_placed(instance_id: int) -> void:
	_cache_names()
	var item: String = str(_names.get(instance_id, ""))
	if item != "":
		toast("toast.item_started", {"item": _item_name(item)}, "hammer")
	_dirty = true


func _on_item_finished(_instance_id: int, item_id: String) -> void:
	toast("toast.item_done", {"item": _item_name(item_id)}, "check")
	_dirty = true


func _on_item_removed(instance_id: int) -> void:
	var item: String = str(_names.get(instance_id, ""))
	_names.erase(instance_id)
	if item != "":
		toast("toast.item_removed", {"item": _item_name(item)}, "sucata")
	_dirty = true


func _on_room_dug(_room: int) -> void:
	toast("toast.dug", {}, "espaco")
	_dirty = true


func _on_antenna_changed(level: int) -> void:
	toast("toast.antenna", {"n": level}, "antena")
	_dirty = true


func _on_house_item(item_id: String) -> void:
	toast("toast.house_item", {"item": _item_name(item_id)}, "home")


func _on_welcome_dismissed(go_radio: bool) -> void:
	if go_radio:
		show_tab("radio")
	else:
		close()


func _on_setting_changed(key: String) -> void:
	if key == "text_size":
		theme = UiTheme.build()
		refresh(true)


func _on_locale_changed(_code: String) -> void:
	_retitle_tabs()
	refresh(true)
