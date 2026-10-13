class_name DrawerBuildTab
extends HBoxContainer
## Aba Construir: catálogo numa lista só, por nível de antena (esquerda), e detalhe do que está escolhido (direita).
## Cada nível tem um cabeçalho "Antena N" com os itens que ele libera; os níveis que faltam ficam em cinza com
## cadeado e o do próximo nível leva o botão de melhorar a antena (que também fica fixo no topo da lista).
## Detalhe de item: "pra quê?", requisitos que faltam, comprar (modo de posicionar) e fixar objetivo.
## Detalhe de objeto já construído (clicado na faixa): cultura do vaso, mover, desmontar.
## Detalhe da antena: antenna_info() e melhorar.

const ANTENNA: String = "__antenna"
const MAX_LEVEL: int = 5

var drawer: Drawer
var _sel_item: String = ""          # item do catálogo ou ANTENNA
var _sel_inst: int = -1             # objeto escolhido na faixa
var _confirm_demolish: bool = false
var _list_sig: String = ""
var _detail_sig: String = ""
var _catalog: Array = []

var _top: HBoxContainer              # antena atual + botão de melhorar, sempre à vista
var _headers: Dictionary = {}        # nível -> cabeçalho na lista (para rolar até ele)
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _detail: VBoxContainer
var _detail_scroll: ScrollContainer
var _actions: HBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 4)
	# esquerda: filtro por linha + lista
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 132
	left.add_theme_constant_override("separation", 1)
	add_child(left)
	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 2)
	left.add_child(_top)
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_list_scroll.add_child(_list)
	# separador fino
	var sep := ColorRect.new()
	sep.color = UiTheme.DARK3
	sep.custom_minimum_size.x = 1
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sep)
	# direita: detalhe rolável + botões fixos embaixo
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 2)
	add_child(right)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 1)
	_detail_scroll.add_child(_detail)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 3)
	right.add_child(_actions)


# ---- API usada pela gaveta e pelos testes ---------------------------------

func refresh(force: bool = false) -> void:
	if not drawer.has_game():
		return
	_refresh_list(force)
	_refresh_detail(force)


## Vai para o primeiro item ainda não comprado da linha (o cartão do gerador usa isto).
func focus_line(line: String) -> void:
	for e: Dictionary in _catalog:
		if str(e.get("line", "")) == line and str(e.get("status", "")) not in ["owned", "maxed"]:
			select_item(str(e.get("item", "")))
			_scroll_to_item(str(e.get("item", "")))
			return


## Seleciona a antena e rola a lista até o cabeçalho do próximo nível (clique na antena do cenário).
func focus_antenna() -> void:
	select_item(ANTENNA)
	var lvl: int = int(drawer.game.antenna_info().get("level", 1)) + 1
	call_deferred("_scroll_to_header", mini(lvl, MAX_LEVEL))


func select_item(item_id: String) -> void:
	_sel_item = item_id
	_sel_inst = -1
	_confirm_demolish = false
	drawer.cancel_placement()
	refresh(true)
	drawer.update_overlay()


func select_instance(instance_id: int) -> void:
	_sel_inst = instance_id
	_sel_item = ""
	_confirm_demolish = false
	refresh(true)
	drawer.update_overlay()


func selected_instance() -> int:
	return _sel_inst


func selected_item() -> String:
	return _sel_item


## Botão principal do detalhe do item (comprar / escavar).
func press_buy() -> void:
	var e: Dictionary = _entry(_sel_item)
	if e.is_empty():
		return
	var g: Node = drawer.game
	var line: String = str(e.get("line", ""))
	var r: Dictionary
	if line == "escavacao" or _sel_item.begins_with("comodo"):
		r = g.dig_room()
	elif int(e.get("cols", 0)) <= 0:
		r = g.buy(_sel_item, 0, -1)
		if not bool(r.get("ok", false)):
			_report(r, why_not(_sel_item))
			refresh(true)
			return
	else:
		var hints: Array = g.placement_hints(_sel_item)
		if hints.is_empty():
			drawer.toast("ui.place.invalid")
			return
		drawer.start_placement("buy", _sel_item, -1, hints, int(e.get("cols", 1)))
		refresh(true)
		return
	_report(r)
	refresh(true)


func press_move() -> void:
	var inst: Dictionary = _instance(_sel_inst)
	if inst.is_empty():
		return
	var hints: Array = drawer.game.placement_hints(str(inst["item"]))
	if hints.is_empty():
		drawer.toast("ui.place.invalid")
		return
	drawer.start_placement("move", str(inst["item"]), _sel_inst, hints, int(inst.get("cols", 1)))
	refresh(true)


func press_demolish(confirmed: bool) -> void:
	if not confirmed:
		_confirm_demolish = true
		refresh(true)
		return
	_confirm_demolish = false
	var id: int = _sel_inst
	var r: Dictionary = drawer.game.demolish(id)
	if bool(r.get("ok", false)):
		_sel_inst = -1
	else:
		_report(r)
	refresh(true)
	drawer.update_overlay()


func press_pin() -> void:
	var g: Node = drawer.game
	g.pin_goal("" if str(g.pinned_goal()) == _sel_item else _sel_item)
	refresh(true)


func press_antenna() -> void:
	var r: Dictionary = drawer.game.upgrade_antenna()
	_report(r, drawer.game.antenna_info() if not bool(r.get("ok", false)) else {})
	refresh(true)


func press_crop(crop: String) -> void:
	drawer.game.set_instance_crop(_sel_inst, crop)
	refresh(true)


# ---- lista ------------------------------------------------------------------

var _suggested: String = ""
var _auto_picked: bool = false


func _refresh_list(force: bool) -> void:
	var g: Node = drawer.game
	var sg: Dictionary = Guide.next_goal(g)
	_suggested = "" if sg.is_empty() else String(sg["id"])
	_catalog = g.catalog("")
	var contact: bool = bool(g.contact_made())
	var ant: Dictionary = g.antenna_info()
	var sig: String = "%s|%s|%s|%s|%s|%s" % [str(_catalog), str(ant), _sel_item, I18nRef.locale(), _suggested, contact]
	if sig == _list_sig and not force:
		return
	_list_sig = sig
	_refresh_top(ant)
	var keep_scroll: int = _list_scroll.scroll_vertical
	DrawerUi.clear(_list)
	_headers.clear()
	var cur: int = int(ant.get("level", 1))
	for lvl in range(1, MAX_LEVEL + 1):
		var items: Array = []
		for e: Dictionary in _catalog:
			if int(e.get("antenna", 1)) != lvl or (str(e.get("line", "")) == "casa" and not contact):
				continue
			items.append(e)
		if items.is_empty() and lvl != cur + 1:
			continue
		_add_level_header(lvl, cur, ant)
		for e: Dictionary in items:
			_add_item_row(e)
	if _list.get_child_count() == 0:
		_list.add_child(DrawerUi.label(I18nRef.t("ui.empty"), "LabelMuted"))
	_list_scroll.set_deferred("scroll_vertical", keep_scroll)


func _row(selected: bool) -> Array:
	var b := Button.new()
	b.theme_type_variation = "FlatButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 14)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if selected:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.DARK3
		for st: String in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 1
	h.offset_right = -2
	h.add_theme_constant_override("separation", 2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	_list.add_child(b)
	return [b, h]


## Botão "[seta] Melhorar 50": cinza quando ainda não dá, mas sempre clicável (o aviso diz o que falta).
func _upgrade_button(ant: Dictionary, with_icon: bool = true) -> Button:
	var can: bool = bool(ant.get("can", false))
	var b: Button = DrawerUi.button("%s %d" % [I18nRef.t("build.upgrade"), int(ant.get("next_cost", 0))], "arrow_up" if with_icon else "")
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.custom_minimum_size = Vector2(0, 13)
	if not can:
		b.modulate = Color(1, 1, 1, 0.75)
	b.pressed.connect(press_antenna)
	b.name = "UpgradeButton"
	return b


## Linha fixa no topo: a antena de agora e, se ainda sobe, o botão de melhorar (o mais importante da aba).
func _refresh_top(ant: Dictionary) -> void:
	DrawerUi.clear(_top)
	_top.add_child(DrawerUi.icon("antena"))
	_top.add_child(DrawerUi.fill_label(I18nRef.t("ui.antenna", {"n": int(ant.get("level", 1))}), "LabelAmber"))
	if bool(ant.get("max", false)):
		_top.add_child(DrawerUi.icon("check"))
	else:
		if _suggested == "antenna":
			_top.add_child(DrawerUi.icon("estrela"))
		_top.add_child(_upgrade_button(ant))


## Cabeçalho de um nível: "Antena N" + o que ele é. Passado = ✓; próximo = botão de melhorar; adiante = cadeado e cinza.
func _add_level_header(lvl: int, cur: int, ant: Dictionary) -> void:
	var parts: Array = _row(lvl == cur + 1 and _sel_item == ANTENNA)
	var b: Button = parts[0]
	var h: HBoxContainer = parts[1]
	b.custom_minimum_size = Vector2(0, 15)
	var future: bool = lvl > cur
	h.add_child(DrawerUi.icon("antena" if not future else ("antena" if lvl == cur + 1 else "lock")))
	h.add_child(DrawerUi.fill_label(I18nRef.t("ui.antenna", {"n": lvl}), "LabelAmber" if lvl <= cur + 1 else "LabelMuted"))
	if lvl <= cur:
		h.add_child(DrawerUi.icon("check"))
	elif lvl == cur + 1 and not bool(ant.get("max", false)):
		h.add_child(_upgrade_button(ant, false))
	b.pressed.connect(select_item.bind(ANTENNA))
	_headers[lvl] = b


func _scroll_to_header(lvl: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var hd: Control = _headers.get(lvl)
	if hd != null and is_instance_valid(hd):
		_list_scroll.scroll_vertical = maxi(0, int(hd.position.y) - 1)


func _scroll_to_item(id: String) -> void:
	await get_tree().process_frame
	for c: Node in _list.get_children():
		if c is Button and (c as Button).name == "Item_" + id:
			_list_scroll.scroll_vertical = maxi(0, int((c as Control).position.y) - 16)
			return


func _add_item_row(e: Dictionary) -> void:
	var id: String = str(e.get("item", ""))
	var parts: Array = _row(_sel_item == id)
	var b: Button = parts[0]
	b.name = "Item_" + id
	var h: HBoxContainer = parts[1]
	var status: String = str(e.get("status", "available"))
	var ic: String = ""
	if bool(e.get("pinned", false)) or _suggested == id:
		ic = "estrela"
	elif status == "locked":
		ic = "lock"
	elif status == "owned" or status == "maxed":
		ic = "check"
	if ic != "":
		h.add_child(DrawerUi.icon(ic))
	else:
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(8, 8)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sp)
	var name_l: Label = DrawerUi.fill_label(I18nRef.t(str(e.get("name_key", "item.%s.name" % id))), "LabelMuted" if status == "locked" else "")
	h.add_child(name_l)
	if status == "locked":
		pass   # cinza e cadeado bastam: o que falta aparece ao escolher o item (e a antena está no cabeçalho do nível)
	elif status != "owned" and status != "maxed":
		h.add_child(DrawerUi.icon_text("sucata", str(int(e.get("cost", 0))), "LabelAmber" if status == "available" else "LabelMuted"))
	b.pressed.connect(select_item.bind(id))


# ---- detalhe ----------------------------------------------------------------

func _refresh_detail(force: bool) -> void:
	var g: Node = drawer.game
	var sig: String = "%s|%s|%s|%s|%s|%s|%s" % [_sel_item, _sel_inst, _confirm_demolish, drawer.placement_mode(), str(_entry(_sel_item)), str(g.sucata()), I18nRef.locale()]
	if _sel_inst >= 0:
		sig += str(_instance(_sel_inst)) + str(g.plots())
	elif _sel_item == ANTENNA:
		sig += str(g.antenna_info())
	if _sel_inst >= 0 and drawer.game.has_method("crop_order"):
		sig += str(drawer.game.crop_order(_sel_inst))
	if sig == _detail_sig and not force:
		return
	_detail_sig = sig
	DrawerUi.clear(_detail)
	DrawerUi.clear(_actions)
	if drawer.placement_mode() != "":
		_detail_placing()
	elif _sel_inst >= 0 and not _instance(_sel_inst).is_empty():
		_detail_instance()
	elif _sel_item == ANTENNA:
		_detail_antenna()
	elif not _entry(_sel_item).is_empty():
		_detail_item()
	else:
		_sel_inst = -1
		var sg: Dictionary = Guide.next_goal(g)
		if not _auto_picked and not sg.is_empty():
			# abre já na próxima meta sugerida (o jogador não precisa descobrir o que comprar)
			_auto_picked = true
			_sel_item = ANTENNA if bool(sg["antenna"]) else String(sg["id"])
			_refresh_detail(true)
			return
		_detail_empty()


func _detail_empty() -> void:
	_detail.add_child(DrawerUi.label(I18nRef.t("hint.build"), "LabelSmall", true))
	_goal_line()


func _goal_line() -> void:
	var g: Dictionary = Guide.next_goal(drawer.game)
	if g.is_empty():
		return
	_detail.add_child(DrawerUi.icon_text("estrela", Guide.goal_name(g)))
	var have: int = int(g["have"])
	var need: int = int(g["cost"])
	var txt: String = I18nRef.t("goal.ready") if bool(g["ready"]) else I18nRef.t("hud.missing", {"n": maxi(0, need - have)})
	_detail.add_child(DrawerUi.label(txt, "LabelAmber"))


func _title(text: String, right_text: String = "", right_icon: String = "") -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	var t: Label = DrawerUi.fill_label(text, "LabelAmber")
	h.add_child(t)
	if right_icon != "":
		h.add_child(DrawerUi.icon(right_icon))
	if right_text != "":
		h.add_child(DrawerUi.label(right_text))
	_detail.add_child(h)


func _tags(tags: Array) -> void:
	if tags.is_empty():
		return
	var tag: String = str(tags[0])   # uma etiqueta só: a principal
	var it: HBoxContainer = DrawerUi.icon_text(DrawerUi.pra_que_icon(tag), I18nRef.t("pra_que." + tag))
	(it.get_child(1) as Label).add_theme_color_override("font_color", UiTheme.LEAF2)
	it.tooltip_text = I18nRef.t("pra_que.%s.help" % tag)
	it.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail.add_child(it)


## Requisitos que faltam: `missing` são chaves i18n e `missing_args` os argumentos (seção 4.3).
func _missing(src: Dictionary) -> void:
	var keys: Array = src.get("missing", [])
	var args: Array = src.get("missing_args", [])
	for i in keys.size():
		var row: HBoxContainer = DrawerUi.icon_text("lock", missing_text(str(keys[i]), args[i] if i < args.size() else {}))
		(row.get_child(1) as Label).add_theme_color_override("font_color", UiTheme.RUST3)
		_detail.add_child(row)


## Traduz uma chave de requisito; `{item}` chega como id e vira o nome do item.
## Motivo curto para a lista ("antena 3", "energia 2").
static func missing_short(key: String, args: Variant) -> String:
	var a: Dictionary = (args as Dictionary).duplicate() if args is Dictionary else {}
	if a.has("item"):
		a["item"] = I18nRef.t("item.%s.name" % str(a["item"]))
	var sk: String = "missing.short." + key.trim_prefix("missing.")
	return I18nRef.t(sk, a) if I18nRef.has_key(sk) else missing_text(key, args)


static func missing_text(key: String, args: Variant) -> String:
	var a: Dictionary = (args as Dictionary).duplicate() if args is Dictionary else {}
	if a.has("item"):
		a["item"] = I18nRef.t("item.%s.name" % str(a["item"]))
	return I18nRef.t(key, a) if I18nRef.has_key(key) else key


func _detail_item() -> void:
	var e: Dictionary = _entry(_sel_item)
	var status: String = str(e.get("status", "available"))
	var cost: int = int(e.get("cost", 0))
	var open: bool = status != "owned" and status != "maxed"
	_title(I18nRef.t(str(e.get("name_key", ""))), "", "" if open else "check")
	_detail.add_child(DrawerUi.label(I18nRef.t(str(e.get("desc_key", ""))), "LabelSmall", true))
	_tags(e.get("pra_que", []))
	var line: String = str(e.get("line", ""))
	var have: int = int(drawer.game.sucata())
	if open and cost > 0:
		var cr := HBoxContainer.new()
		cr.add_theme_constant_override("separation", 3)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.add_child(DrawerUi.icon_text("sucata", I18nRef.t("buy.have", {"cost": cost, "have": have}), "LabelSmall"))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.0
		bar.value = clampf(float(have) / float(cost), 0.0, 1.0)
		bar.custom_minimum_size = Vector2(0, 4)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.add_child(bar)
		_detail.add_child(cr)
	var only_cost: bool = status != "available" and str((e.get("missing", []) as Array)[0] if not (e.get("missing", []) as Array).is_empty() else "") == "missing.cost"
	if not only_cost:
		_missing(e)
	if bool(e.get("post_contact", false)) and not bool(drawer.game.contact_made()):
		_detail.add_child(DrawerUi.label(I18nRef.t("buy.post_contact"), "LabelMuted"))
	if line in ["agua", "energia", "transporte"] and int(e.get("tier", 0)) > 0:
		_detail.add_child(DrawerUi.label(I18nRef.t("buy.replaces"), "LabelMuted"))
	# botões: comprar (ou o que falta) e "Meta"
	var can: bool = status == "available"
	if open:
		var verb: String = I18nRef.t("ui.btn.dig") if line == "escavacao" else I18nRef.t("drawer.btn.buy_for", {"n": cost})
		if not can:
			var miss: Array = e.get("missing", [])
			verb = I18nRef.t("hud.short", {"n": maxi(0, cost - have)}) if only_cost or miss.is_empty() \
					else missing_short(str(miss[0]), (e.get("missing_args", []) as Array)[0] if not (e.get("missing_args", []) as Array).is_empty() else {})
		var b: Button = DrawerUi.button(verb, "sucata" if not can else ("hammer" if line != "escavacao" else ""))
		b.disabled = not can
		b.pressed.connect(press_buy)
		b.name = "BuyButton"
		_actions.add_child(b)
	var pinned: bool = str(drawer.game.pinned_goal()) == _sel_item
	if open and (pinned or not can):
		var p: Button = DrawerUi.button(I18nRef.t("goal.btn.pin"), "estrela")
		p.toggle_mode = true
		p.set_pressed_no_signal(pinned)
		p.tooltip_text = I18nRef.t("hint.goal")
		p.pressed.connect(press_pin)
		p.name = "PinButton"
		_actions.add_child(p)


func _detail_antenna() -> void:
	var ant: Dictionary = drawer.game.antenna_info()
	var lvl: int = int(ant.get("level", 1))
	_title(I18nRef.t("ui.antenna", {"n": lvl}), "", "antena")
	_detail.add_child(DrawerUi.label(I18nRef.t("antenna.%d.name" % lvl), "LabelSmall", true))
	if bool(ant.get("max", false)):
		_detail.add_child(DrawerUi.label(I18nRef.t("ui.antenna.max"), "LabelAmber"))
		return
	_detail.add_child(DrawerUi.icon_text("arrow_up", I18nRef.t("drawer.antenna.next", {"name": I18nRef.t("antenna.%d.name" % (lvl + 1))})))
	_missing(ant)
	var b: Button = DrawerUi.button(I18nRef.t("ui.antenna.cost", {"n": int(ant.get("next_cost", 0))}), "antena")
	b.disabled = not bool(ant.get("can", false))
	b.pressed.connect(press_antenna)
	b.name = "AntennaButton"
	_actions.add_child(b)


func _detail_instance() -> void:
	var g: Node = drawer.game
	var inst: Dictionary = _instance(_sel_inst)
	var item: String = str(inst.get("item", ""))
	_title(I18nRef.t("item.%s.name" % item), I18nRef.t("room.name", {"n": int(inst.get("room", 1))}))
	if str(inst.get("state", "ready")) == "building":
		_detail.add_child(DrawerUi.label(I18nRef.t("ui.building"), "LabelSmall"))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(60, 6)
		bar.max_value = 1.0
		bar.step = 0.0
		bar.value = float(inst.get("build_ratio", 0.0))
		_detail.add_child(bar)
	# cultura (ordem permanente da estrutura; "" = automático, o padrão)
	var crop: String = ""
	for p: Dictionary in g.plots():
		if int(p.get("instance", -1)) == _sel_inst:
			crop = str(p.get("crop", ""))
			break
	if crop != "":
		var order: String = str(g.crop_order(_sel_inst)) if g.has_method("crop_order") else crop
		_detail.add_child(DrawerUi.icon_text("crop_" + crop, I18nRef.t("crop.current", {"crop": I18nRef.t("crop.%s.name" % crop)}), ""))
		var crops: Array = g.available_crops(_sel_inst)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var auto_b: Button = DrawerUi.button(I18nRef.t("drawer.crop.auto"))
		auto_b.toggle_mode = true
		auto_b.set_pressed_no_signal(order == "")
		auto_b.tooltip_text = I18nRef.t("drawer.crop.auto.help")
		auto_b.pressed.connect(press_crop.bind(""))
		row.add_child(auto_b)
		for c in crops:
			var cb: Button = DrawerUi.button("", "crop_" + str(c))
			cb.toggle_mode = true
			cb.set_pressed_no_signal(str(c) == order)
			cb.tooltip_text = I18nRef.t("crop.%s.name" % str(c))
			cb.pressed.connect(press_crop.bind(str(c)))
			cb.name = "Crop_" + str(c)
			row.add_child(cb)
		_detail.add_child(row)
		_detail.add_child(DrawerUi.label(I18nRef.t("crop.pick.help"), "LabelMuted", true))
	if _confirm_demolish:
		_detail.add_child(DrawerUi.label(I18nRef.t("ui.demolish.confirm"), "", true))
		var yes: Button = DrawerUi.button(I18nRef.t("ui.btn.yes"))
		yes.pressed.connect(press_demolish.bind(true))
		yes.name = "ConfirmYes"
		_actions.add_child(yes)
		var no: Button = DrawerUi.button(I18nRef.t("ui.btn.no"))
		no.pressed.connect(func() -> void:
			_confirm_demolish = false
			refresh(true))
		_actions.add_child(no)
		return
	var e: Dictionary = _entry_any(item)
	if not e.is_empty() and int(e.get("cost", 0)) > 0:
		_detail.add_child(DrawerUi.label(I18nRef.t("buy.refund", {"n": int(e.get("cost", 0))}), "LabelMuted"))
	var mv: Button = DrawerUi.button(I18nRef.t("ui.btn.move"), "grab")
	mv.tooltip_text = I18nRef.t("hint.move")
	mv.pressed.connect(press_move)
	mv.name = "MoveButton"
	_actions.add_child(mv)
	var dm: Button = DrawerUi.button(I18nRef.t("ui.btn.demolish"), "close")
	dm.tooltip_text = I18nRef.t("hint.demolish")
	dm.pressed.connect(press_demolish.bind(false))
	dm.name = "DemolishButton"
	_actions.add_child(dm)


func _detail_placing() -> void:
	var item: String = drawer.placing_item()
	_title(I18nRef.t("item.%s.name" % item))
	_detail.add_child(DrawerUi.icon_text("arrow_down", I18nRef.t("ui.place.pick"), ""))
	var pe: Dictionary = _entry_any(item)
	var cols: int = int(pe.get("cols", 0))
	if cols == 1:
		_detail.add_child(DrawerUi.label(I18nRef.t("buy.cols.one"), "LabelMuted"))
	elif cols > 1:
		_detail.add_child(DrawerUi.label(I18nRef.t("buy.cols", {"n": cols}), "LabelMuted"))
	_detail.add_child(DrawerUi.label(I18nRef.t("drawer.place.help"), "LabelSmall", true))
	var c: Button = DrawerUi.button(I18nRef.t("ui.btn.cancel"), "close")
	c.pressed.connect(drawer.cancel_placement)
	c.name = "CancelButton"
	_actions.add_child(c)


# ---- auxiliares -------------------------------------------------------------

func _entry(id: String) -> Dictionary:
	for e: Dictionary in _catalog:
		if str(e.get("item", "")) == id:
			return e
	return {}


## Procura no catálogo completo (o filtro atual pode esconder o item).
func _entry_any(id: String) -> Dictionary:
	var e: Dictionary = _entry(id)
	if not e.is_empty():
		return e
	for x: Dictionary in drawer.game.catalog(""):
		if str(x.get("item", "")) == id:
			return x
	return {}


func _instance(id: int) -> Dictionary:
	if id < 0:
		return {}
	for d: Dictionary in drawer.game.instances():
		if int(d.get("id", -1)) == id:
			return d
	return {}


## Falha de um comando vira um aviso curto. `why` (resultado de can_buy/antenna_info) traz
## a 1ª chave que falta com os argumentos; sem isso, usa o `reason` do comando.
func _report(r: Dictionary, why: Dictionary = {}) -> void:
	if bool(r.get("ok", false)):
		return
	var keys: Array = why.get("missing", [])
	var args: Array = why.get("missing_args", [])
	var reason: String = str(r.get("reason", ""))
	if not keys.is_empty():
		drawer.toast(missing_text(str(keys[0]), args[0] if not args.is_empty() else {}), {}, "lock")
	elif reason != "" and I18nRef.has_key("drawer.cant." + reason):
		drawer.toast("drawer.cant." + reason, {}, "lock")
	elif reason.begins_with("missing.") and I18nRef.has_key(reason):
		drawer.toast(missing_text(reason, {}), {}, "lock")
	else:
		drawer.toast("drawer.toast.cant", {}, "lock")


## Motivo detalhado de não poder comprar (para o aviso).
func why_not(item_id: String, room: int = 0, col: int = -1) -> Dictionary:
	var g: Node = drawer.game
	return g.can_buy(item_id, room, col) if g.has_method("can_buy") else {}


static func _rotated_arrow(left: bool) -> Texture2D:
	# setas esquerda/direita a partir de arrow_up (o manifest só tem cima/baixo); a aba Rádio também usa
	var src: Texture2D = UiTheme.icon("arrow_up")
	if src == null:
		return null
	var img: Image = src.get_image()
	img.rotate_90(COUNTERCLOCKWISE if left else CLOCKWISE)
	return ImageTexture.create_from_image(img)
