class_name DrawerBuildTab
extends HBoxContainer
## Aba Construir: catálogo por linha (esquerda) e detalhe do que está escolhido (direita).
## Detalhe de item: "pra quê?", requisitos que faltam, comprar (modo de posicionar) e fixar objetivo.
## Detalhe de objeto já construído (clicado na faixa): cultura do vaso, mover, desmontar.
## Detalhe da antena: antenna_info() e melhorar.

const FILTERS: Array[String] = ["", "plantio", "agua", "energia", "transporte", "decor", "casa", "escavacao"]
const ANTENNA: String = "__antenna"

var drawer: Drawer
var _filter: int = 0
var _sel_item: String = ""          # item do catálogo ou ANTENNA
var _sel_inst: int = -1             # objeto escolhido na faixa
var _confirm_demolish: bool = false
var _list_sig: String = ""
var _detail_sig: String = ""
var _catalog: Array = []

var _filter_label: Label
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
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 0)
	left.add_child(frow)
	var prev: Button = DrawerUi.icon_button("arrow_up")
	prev.icon = _rotated_arrow(true)
	prev.pressed.connect(func() -> void: cycle_filter(-1))
	frow.add_child(prev)
	_filter_label = DrawerUi.label("", "LabelAmber")
	_filter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_filter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(_filter_label)
	var nxt: Button = DrawerUi.icon_button("arrow_down")
	nxt.icon = _rotated_arrow(false)
	nxt.pressed.connect(func() -> void: cycle_filter(1))
	frow.add_child(nxt)
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


func cycle_filter(step: int) -> void:
	var n: int = FILTERS.size()
	for _i in n:
		_filter = (_filter + step + n) % n
		if _filter_visible(FILTERS[_filter]):
			break
	refresh(true)


func set_filter(line: String) -> void:
	_filter = maxi(0, FILTERS.find(line))
	refresh(true)


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
	_report(drawer.game.upgrade_antenna())
	refresh(true)


func press_crop(crop: String) -> void:
	drawer.game.set_instance_crop(_sel_inst, crop)
	refresh(true)


# ---- lista ------------------------------------------------------------------

func _filter_visible(line: String) -> bool:
	# a casa dela só aparece depois do contato (não estragar a história)
	return line != "casa" or bool(drawer.game.contact_made())


func _refresh_list(force: bool) -> void:
	var g: Node = drawer.game
	if not _filter_visible(FILTERS[_filter]):
		_filter = 0
	var line: String = FILTERS[_filter]
	_catalog = g.catalog(line)
	var contact: bool = bool(g.contact_made())
	var ant: Dictionary = g.antenna_info()
	var sig: String = "%s|%s|%s|%s|%s" % [line, str(_catalog), str(ant), _sel_item, I18nRef.locale()]
	if sig == _list_sig and not force:
		return
	_list_sig = sig
	_filter_label.text = I18nRef.t("tab.filter.all") if line == "" else I18nRef.t("line." + line)
	var keep_scroll: int = _list_scroll.scroll_vertical
	DrawerUi.clear(_list)
	if line == "":
		_add_antenna_row(ant)
	var last_line: String = ""
	for e: Dictionary in _catalog:
		var l: String = str(e.get("line", ""))
		if l == "casa" and not contact:
			continue
		if line == "" and l != last_line:
			var h: Label = DrawerUi.label(I18nRef.t("line." + l), "LabelMuted")
			h.add_theme_font_size_override("font_size", UiTheme.font_size(UiTheme.SIZE_SMALL))
			_list.add_child(h)
			last_line = l
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


func _add_antenna_row(ant: Dictionary) -> void:
	var parts: Array = _row(_sel_item == ANTENNA)
	var b: Button = parts[0]
	var h: HBoxContainer = parts[1]
	h.add_child(DrawerUi.icon("antena"))
	var name_l: Label = DrawerUi.fill_label(I18nRef.t("ui.antenna", {"n": int(ant.get("level", 1))}))
	h.add_child(name_l)
	if not bool(ant.get("max", false)):
		var c: Label = DrawerUi.label(str(int(ant.get("next_cost", 0))), "LabelAmber" if bool(ant.get("can", false)) else "LabelMuted")
		h.add_child(c)
	b.pressed.connect(select_item.bind(ANTENNA))


func _add_item_row(e: Dictionary) -> void:
	var id: String = str(e.get("item", ""))
	var parts: Array = _row(_sel_item == id)
	var b: Button = parts[0]
	var h: HBoxContainer = parts[1]
	var status: String = str(e.get("status", "available"))
	var ic: String = ""
	if bool(e.get("pinned", false)):
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
	if status != "owned" and status != "maxed":
		var c: Label = DrawerUi.label(str(int(e.get("cost", 0))), "LabelAmber" if status == "available" else "LabelMuted")
		h.add_child(c)
	b.pressed.connect(select_item.bind(id))


# ---- detalhe ----------------------------------------------------------------

func _refresh_detail(force: bool) -> void:
	var g: Node = drawer.game
	var sig: String = "%s|%s|%s|%s|%s|%s|%s" % [_sel_item, _sel_inst, _confirm_demolish, drawer.placement_mode(), str(_entry(_sel_item)), str(g.sucata()), I18nRef.locale()]
	if _sel_inst >= 0:
		sig += str(_instance(_sel_inst)) + str(g.plots())
	elif _sel_item == ANTENNA:
		sig += str(g.antenna_info())
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
		_detail_empty()


func _detail_empty() -> void:
	_detail.add_child(DrawerUi.label(I18nRef.t("hint.build"), "LabelSmall", true))
	_detail.add_child(DrawerUi.label(I18nRef.t("drawer.build.select_hint"), "LabelSmall", true))
	_goal_line()


func _goal_line() -> void:
	var goal: String = str(drawer.game.pinned_goal())
	if goal == "":
		return
	var e: Dictionary = _entry_any(goal)
	var h: HBoxContainer = DrawerUi.icon_text("estrela", I18nRef.t("goal.pinned", {"item": I18nRef.t("item.%s.name" % goal)}))
	_detail.add_child(h)
	if not e.is_empty():
		var have: int = int(drawer.game.sucata())
		var need: int = int(e.get("cost", 0))
		var txt: String = I18nRef.t("goal.ready") if bool(drawer.game.goal_ready()) else I18nRef.t("goal.progress", {"have": mini(have, need), "need": need})
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
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 5)
	h.add_theme_constant_override("v_separation", 0)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for tag in tags:
		var it: HBoxContainer = DrawerUi.icon_text(DrawerUi.pra_que_icon(str(tag)), I18nRef.t("pra_que." + str(tag)))
		it.tooltip_text = I18nRef.t("pra_que.%s.help" % str(tag))
		it.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(it)
	_detail.add_child(h)


func _missing(lines: Array) -> void:
	for m in lines:
		var row: HBoxContainer = DrawerUi.icon_text("lock", str(m))
		(row.get_child(1) as Label).add_theme_color_override("font_color", UiTheme.RUST3)
		_detail.add_child(row)


func _detail_item() -> void:
	var e: Dictionary = _entry(_sel_item)
	var status: String = str(e.get("status", "available"))
	var cost: int = int(e.get("cost", 0))
	_title(I18nRef.t(str(e.get("name_key", ""))), str(cost) if status != "owned" and status != "maxed" else "", "sucata" if status != "owned" and status != "maxed" else "check")
	_detail.add_child(DrawerUi.label(I18nRef.t(str(e.get("desc_key", ""))), "LabelSmall", true))
	_missing(e.get("missing", []))
	_tags(e.get("pra_que", []))
	var meta: PackedStringArray = PackedStringArray()
	var cols: int = int(e.get("cols", 0))
	var line: String = str(e.get("line", ""))
	if line != "escavacao":
		if cols <= 0:
			meta.append(I18nRef.t("buy.cols.none"))
		elif cols == 1:
			meta.append(I18nRef.t("buy.cols.one"))
		else:
			meta.append(I18nRef.t("buy.cols", {"n": cols}))
	if bool(e.get("post_contact", false)) and not bool(drawer.game.contact_made()):
		meta.append(I18nRef.t("buy.post_contact"))
	if meta.size() > 0:
		_detail.add_child(DrawerUi.label(" · ".join(meta), "LabelMuted"))
	if line in ["agua", "energia", "transporte"] and int(e.get("tier", 0)) > 0:
		_detail.add_child(DrawerUi.label(I18nRef.t("buy.replaces"), "LabelMuted"))
	# botões
	var can: bool = status == "available"
	if status != "owned" and status != "maxed":
		var verb: String = I18nRef.t("ui.btn.dig") if line == "escavacao" else I18nRef.t("drawer.btn.buy_for", {"n": cost})
		var b: Button = DrawerUi.button(verb, "hammer" if line != "escavacao" else "")
		b.disabled = not can
		b.pressed.connect(press_buy)
		b.name = "BuyButton"
		_actions.add_child(b)
	var pinned: bool = str(drawer.game.pinned_goal()) == _sel_item
	if status != "owned" and status != "maxed" and (pinned or not can):
		var p: Button = DrawerUi.button(I18nRef.t("goal.btn.clear") if pinned else I18nRef.t("goal.btn.pin"), "estrela")
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
	_missing(ant.get("missing", []))
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
	# cultura (ordem permanente da estrutura)
	var crop: String = ""
	for p: Dictionary in g.plots():
		if int(p.get("instance", -1)) == _sel_inst:
			crop = str(p.get("crop", ""))
			break
	var crops: Array = g.available_crops(_sel_inst) if crop != "" else []
	if crop != "":
		_detail.add_child(DrawerUi.icon_text("crop_" + crop, I18nRef.t("crop.current", {"crop": I18nRef.t("crop.%s.name" % crop)}), ""))
		if crops.size() > 1:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 2)
			for c in crops:
				var cb: Button = DrawerUi.button(I18nRef.t("crop.%s.name" % str(c)), "crop_" + str(c))
				cb.disabled = str(c) == crop
				cb.tooltip_text = I18nRef.t("crop.pick.help")
				cb.pressed.connect(press_crop.bind(str(c)))
				row.add_child(cb)
			_detail.add_child(row)
			_detail.add_child(DrawerUi.label(I18nRef.t("hint.planting"), "LabelMuted", true))
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


func _report(r: Dictionary) -> void:
	if bool(r.get("ok", false)):
		return
	var reason: String = str(r.get("reason", ""))
	if reason != "" and I18nRef.has_key(reason):
		drawer.toast(reason)
	else:
		drawer.toast("drawer.toast.cant")


static func _rotated_arrow(left: bool) -> Texture2D:
	# setas esquerda/direita a partir de arrow_up (o manifest só tem cima/baixo)
	var src: Texture2D = UiTheme.icon("arrow_up")
	if src == null:
		return null
	var img: Image = src.get_image()
	img.rotate_90(COUNTERCLOCKWISE if left else CLOCKWISE)
	return ImageTexture.create_from_image(img)
