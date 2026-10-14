class_name InfoCard
extends PanelContainer
## Cartãozinho que abre ao clicar no próprio objeto (Joaquim, caixa da escotilha, gerador, antena).
## Substitui a aba Estado: cada informação mora no objeto dela, curta, com a ação do lado.
## Fecha com Esc, com um clique fora ou ao abrir outro cartão. Só lê o Game; as ações saem por sinal.
##   open_for("man"|"box"|"gen"|"antenna", alvo: Rect2 em coordenadas de tela, janela: Vector2, id: int = -1)

## Ação pedida no cartão: "sell" (vender), "gens" (ver geradores), "antenna" (melhorar a antena).
signal action(kind: String)
signal closed()

const W: int = 92
const W_MAN: int = 124
const GAUGE: int = 14          # diâmetro do medidor redondo
const NEEDS: Array[String] = ["food", "water", "sleep"]
const REFRESH_S: float = 0.25
const SQ_MAX: int = 8

var kind: String = ""
var instance_id: int = -1

var _target: Rect2 = Rect2()
var _bounds: Vector2 = Vector2(208, 136)
var _col: VBoxContainer
var _sig: String = ""
var _t: float = 0.0


func _init() -> void:
	theme = UiTheme.build()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 20
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 2)
	_col.custom_minimum_size = Vector2(W, 0)
	add_child(_col)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= REFRESH_S:
		_t = 0.0
		refresh()


## Abre (ou troca) o cartão. `target` é o retângulo do objeto na tela; o cartão fica em cima dele, ou embaixo
## quando não há espaço.
func open_for(k: String, target: Rect2, window: Vector2, id: int = -1) -> void:
	kind = k
	instance_id = id
	_target = target
	_bounds = window
	_sig = ""
	_col.custom_minimum_size = Vector2(W_MAN if k == "man" else W, 0)
	visible = true
	refresh(true)


func close() -> void:
	if not visible:
		return
	visible = false
	kind = ""
	closed.emit()


func is_open() -> bool:
	return visible


func refresh(force: bool = false) -> void:
	var g: Node = ScreenUtil.node("Game")
	if g == null or not g.has_method("catalog") or kind == "":
		return
	var rows: Array = _rows(g)
	var sig: String = str(rows) + str(I18nRef.locale())
	if sig == _sig and not force:
		return
	_sig = sig
	DrawerUi.clear(_col)
	for r in rows:
		_col.add_child(_make(r))
	size = Vector2.ZERO
	call_deferred("_place")


# ---- conteúdo (uma lista de linhas descritivas: facilita comparar e testar) -------------------------

func _rows(g: Node) -> Array:
	match kind:
		"man":
			return _rows_man(g)
		"box":
			return _rows_box(g)
		"gen":
			return _rows_gen(g)
		"antenna":
			return _rows_antenna(g)
	return []


## Chave status.* do que ele está fazendo agora.
static func doing_key(g: Node) -> String:
	if not bool(g.is_awake()) or bool(g.is_night()):
		return "status.sleeping"
	var jobs: Array = g.active_jobs()
	if not jobs.is_empty():
		return "status.digging" if str((jobs[0] as Dictionary).get("item", "")).begins_with("comodo") else "status.building"
	if bool(g.hungry()):
		return "status.hungry"
	if g.has_method("need_state") and String(g.need_state("water")) == "bad":
		return "status.thirsty"
	if not bool(g.power_ok()):
		return "status.no_power"
	if float(g.busy()) >= 0.5:
		return "status.working"
	return "status.resting"


func _rows_man(g: Node) -> Array:
	var key: String = doing_key(g)
	var icon: String = {"status.sleeping": "tempo", "status.building": "hammer", "status.digging": "hammer",
		"status.hungry": "cesto", "status.thirsty": "energia", "status.no_power": "energia"}.get(key, "home")
	var rows: Array = [{"t": "title", "text": "%s · %s" % [ScreenUtil.tr_key("man.name"), DrawerUi.clock(float(g.tod_hours()))]},
		{"t": "icon", "icon": icon, "text": ScreenUtil.tr_key("card.now", {"s": ScreenUtil.tr_key(key)}),
			"tone": "bad" if key in ["status.hungry", "status.thirsty", "status.no_power"] else ""}]
	if key == "status.sleeping":
		rows.append({"t": "muted", "text": ScreenUtil.tr_key("card.wakes", {"h": int(Balance.num("time.awake_from_min", 360.0) / 60.0)})})
	if g.has_method("need_level"):
		for n in NEEDS:
			var st: String = String(g.need_state(n))
			var hint: String = "" if st == "ok" else ScreenUtil.tr_key("need.%s.%s" % [n, st])   # bem: só o medidor (o cartão é baixo)
			if st == "bad" and n != "sleep" and g.has_method("death_left_min"):
				var left: float = float(g.death_left_min(n))
				if left >= 0.0:
					hint += " " + ScreenUtil.tr_key("need.left", {"t": ClockText.of(left)})
			rows.append({"t": "need", "need": n, "pct": int(roundf(float(g.need_level(n)) * 100.0)), "state": st, "hint": hint})
	return rows


func _rows_box(g: Node) -> Array:
	var stock: int = int(g.box_stock())
	var cap: int = int(g.box_capacity())
	var rows: Array = [{"t": "title", "text": ScreenUtil.tr_key("ui.box")},
		{"t": "cell", "icon": "cesto", "n": stock, "fill": clampf(float(g.box_fill()), 0.0, 1.0), "full": float(g.box_fill()) >= 1.0},
		{"t": "muted", "text": ScreenUtil.tr_key("card.box.cap", {"n": cap})}]
	if not bool(g.help_box_available()):
		rows.append({"t": "small", "text": ScreenUtil.tr_key("card.box.auto")})
		return rows
	var why: String = String(g.help_box_check())
	var sale: Dictionary = g.box_sale()
	match why:
		"ok":
			rows.append({"t": "sell", "baskets": int(sale["units"]), "scrap": int(sale["scrap"])})
		"cooldown":
			var w: Dictionary = g.help_box_wait()
			rows.append({"t": "btn_off", "text": ScreenUtil.tr_key("card.box.wait", {"t": ClockText.of(float(w["left"]))})})
		"empty":
			rows.append({"t": "btn_off", "text": ScreenUtil.tr_key("card.box.empty")})
		_:
			rows.append({"t": "btn_off", "text": ScreenUtil.tr_key("card.box.off")})
	if not bool(g.is_awake()) or bool(g.is_night()):
		rows[rows.size() - 1] = {"t": "btn_off", "text": ScreenUtil.tr_key("status.sleeping")}
	return rows


func _rows_gen(g: Node) -> Array:
	var supply: int = int(g.power_supply())
	var need: int = int(g.power_demand())
	var rows: Array = [{"t": "title", "text": ScreenUtil.tr_key("line.energia")}]
	if supply >= need:
		rows.append({"t": "icon", "icon": "check", "text": ScreenUtil.tr_key("card.gen.ok", {"n": supply - need}), "tone": "good"})
	else:
		rows.append({"t": "icon", "icon": "energia", "text": ScreenUtil.tr_key("card.gen.lack", {"n": need - supply}), "tone": "bad"})
	rows.append({"t": "squares", "used": mini(need, supply), "free": maxi(0, supply - need), "lack": maxi(0, need - supply)})
	rows.append({"t": "muted", "text": ScreenUtil.tr_key("card.gen.use", {"use": need, "have": supply})})
	if bool(g.has_method("line_tiers")) and String((g.line_tiers() as Dictionary).get("energia", "bicicleta")) == "bicicleta":
		rows.append({"t": "small", "text": ScreenUtil.tr_key("card.gen.bike")})
	else:
		rows.append({"t": "small", "text": ScreenUtil.tr_key("card.gen.self")})
	if supply < need:
		rows.append({"t": "btn", "text": ScreenUtil.tr_key("card.gen.btn"), "act": "gens", "icon": "hammer"})
	return rows


func _rows_antenna(g: Node) -> Array:
	var info: Dictionary = g.antenna_info()
	var lvl: int = int(g.antenna())
	var rows: Array = [{"t": "title", "text": ScreenUtil.tr_key("ui.antenna", {"n": lvl})}]
	if bool(info.get("max", false)):
		rows.append({"t": "muted", "text": ScreenUtil.tr_key("card.antenna.max")})
	else:
		rows.append({"t": "cost", "text": str(int(info.get("next_cost", 0))), "can": bool(info.get("can", false))})
		rows.append({"t": "btn", "text": ScreenUtil.tr_key("card.antenna.btn"), "act": "antenna", "icon": "antena"})
	if bool(g.contact_made()):
		rows.append(_journey_row(g))
	return rows


## Jornada da casa dela (depois do contato): quanto falta para ela chegar.
func _journey_row(g: Node) -> Dictionary:
	if bool(g.arrived()):
		return {"t": "small", "text": ScreenUtil.tr_key("drawer.journey.home")}
	var j: Dictionary = g.journey()
	var left: int = ceili(float(j.get("days_left", 0)))
	return {"t": "small", "text": ScreenUtil.tr_key("drawer.journey.days", {"n": left}) if left > 0 else ScreenUtil.tr_key("drawer.journey.soon")}


# ---- montagem dos controles -------------------------------------------------------------------------

func _make(r: Dictionary) -> Control:
	match String(r["t"]):
		"title":
			return DrawerUi.label(String(r["text"]), "LabelTitle")
		"muted":
			return DrawerUi.label(String(r["text"]), "LabelMuted")
		"small":
			return DrawerUi.label(String(r["text"]), "LabelSmall")
		"icon":
			var h: HBoxContainer = DrawerUi.icon_text(String(r["icon"]), String(r["text"]), "LabelSmall")
			var tone: String = String(r.get("tone", ""))
			if tone != "":
				(h.get_child(1) as Label).add_theme_color_override("font_color", UiTheme.SIGNAL if tone == "good" else UiTheme.RUST3)
			return h
		"cost":
			return DrawerUi.icon_text("sucata", String(r["text"]), "LabelAmber" if bool(r["can"]) else "LabelMuted")
		"cell":
			return _cell(r)
		"squares":
			return _squares(r)
		"need":
			return _need_row(r)
		"sell":
			return _sell_button(int(r["baskets"]), int(r["scrap"]))
		"btn_off":
			var b: Button = DrawerUi.button(String(r["text"]))
			b.disabled = true
			return b
		"btn":
			var b2: Button = DrawerUi.button(String(r["text"]), String(r.get("icon", "")))
			b2.pressed.connect(func() -> void: action.emit(String(r["act"])))
			return b2
	return Control.new()


## Célula da caixa (estilo Rusty): ícone do cesto, quantidade e barrinha de cheio (vermelha quando cheia).
func _cell(r: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(DrawerUi.icon("cesto"))
	var n: Label = DrawerUi.colored(str(int(r["n"])), UiTheme.RUST3 if bool(r["full"]) else UiTheme.PAPER, "LabelSmall")
	h.add_child(n)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = float(r["fill"])
	bar.custom_minimum_size = Vector2(40, 4)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	return h


## Necessidade: medidor redondo (nível = líquido que sobe, aro = estado) + "Comida 25%" e o que fazer.
func _need_row(r: Dictionary) -> Control:
	var n: String = String(r["need"])
	var st: String = String(r["state"])
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gauge := NeedGauge.new()
	gauge.level = float(r["pct"]) / 100.0
	gauge.state = st
	gauge.need = n
	h.add_child(gauge)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: Color = {"ok": UiTheme.PAPER, "warn": UiTheme.AMBER3, "bad": UiTheme.TOMATO}[st]
	v.add_child(DrawerUi.colored("%s %d%%" % [ScreenUtil.tr_key("need." + n), int(r["pct"])], col, "LabelSmall"))
	if String(r["hint"]) != "":
		var hint: Label = DrawerUi.label(String(r["hint"]), "LabelMuted")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(W_MAN - GAUGE - 3, 0)
		v.add_child(hint)
	h.add_child(v)
	return h


## Quadradinhos de energia: usados (amarelo), livres (verde), faltando (vermelho).
func _squares(r: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left: int = SQ_MAX
	for part: Array in [["used", UiTheme.AMBER2], ["free", UiTheme.SIGNAL], ["lack", UiTheme.TOMATO]]:
		for i in int(r[part[0]]):
			if left <= 0:
				break
			left -= 1
			var c := ColorRect.new()
			c.color = part[1]
			c.custom_minimum_size = Vector2(6, 3)
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(c)
	return h


## Botão "Vender [cesto]4 -> [sucata]4".
func _sell_button(baskets: int, scrap: int) -> Control:
	var b: Button = DrawerUi.button("")
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(DrawerUi.colored(ScreenUtil.tr_key("card.box.sell"), UiTheme.PAPER))
	inner.add_child(DrawerUi.icon("cesto"))
	inner.add_child(DrawerUi.colored(str(baskets), UiTheme.PAPER))
	inner.add_child(DrawerUi.colored("->", UiTheme.CONC4))
	inner.add_child(DrawerUi.icon("sucata"))
	inner.add_child(DrawerUi.colored(str(scrap), UiTheme.AMBER4))
	var m: Vector2 = inner.get_combined_minimum_size()
	b.custom_minimum_size = Vector2(m.x + 10.0, m.y + 2.0)
	inner.position = Vector2(5, 1)
	b.add_child(inner)
	b.pressed.connect(func() -> void: action.emit("sell"))
	return b


func _place() -> void:
	if not visible:
		return
	var sz: Vector2 = get_combined_minimum_size()
	size = sz
	var x: float = _target.get_center().x - sz.x * 0.5
	var y: float = _target.position.y - sz.y - 3.0
	if y < 1.0:
		y = _target.end.y + 3.0
	if y + sz.y > _bounds.y - 1.0:
		y = maxf(1.0, _bounds.y - sz.y - 1.0)
	x = clampf(x, 1.0, maxf(1.0, _bounds.x - sz.x - 1.0))
	position = Vector2(x, y).round()
