class_name StatusHud
extends Control
## Faixa de status sempre visível, de uma linha só:
## Linha 1: "[rosto] (maçã) 80 (gota) 90 (lua) 70 | Dia 3 | [raio] 2/3". Linha 2: "[sucata] 12 sucata | [estrela] Gotejador".
## Os três medidores redondos (comida, água, sono) ficam sempre visíveis ao lado do rosto, com a porcentagem;
## o aro e o número ficam amarelos abaixo de 50% e vermelhos abaixo de 10%.
## O rosto tem moldura (normal, âmbar, vermelha piscando) = a pior das necessidades; clicar abre o cartão dele.
## O raio mostra quanta energia ele usa do que tem; vermelho e piscando quando falta; clicar abre o gerador.
## Meta pronta: "[check] Comprar Gotejador". Sem barra de progresso: o que falta fica só no hover
## ("Faltam 28 sucata"), junto com a explicação do item. Clicar na linha de cima abre a gaveta
## em Construir. O tutorial é uma linha curta abaixo (a seta e o contorno ficam no objeto, ver PlotTip);
## só a linha de cima recebe clique: o resto deixa passar, para a escotilha continuar clicável.

signal clicked()
## Clicou no retratinho do Joaquim: a Main abre o cartão dele.
signal man_clicked()
## Clicou no raio de energia: a Main abre o cartão do gerador em cima dele.
signal energy_clicked()

const BACK_ALPHA: float = 0.6
const TIP_W: int = 150
const FACE: Rect2 = Rect2(10, 2, 12, 12)   # rosto no quadro do homem parado
const FRAME: int = 14                       # lado do retrato com a moldura
const BLINK_S: float = 0.5
## A linha de baixo (sucata e meta) começa à direita da escotilha e da antena, que ficam clicáveis logo abaixo da faixa.
const ROW2_X: int = 72
const NEEDS: Array[String] = ["food", "water", "sleep"]

var steps: FirstSteps

var _col: VBoxContainer
var _row1: HBoxContainer
var _row2: HBoxContainer
var _face: TextureRect
var _needs_box: HBoxContainer
var _gauges: Dictionary = {}   # need -> NeedGauge
var _pcts: Dictionary = {}     # need -> Label
var _day: Label
var _pow_box: HBoxContainer
var _pow_icon: TextureRect
var _pow: Label
var _need_state: String = "ok"
var _power_state: String = "ok"
var _blink: float = 0.0
var _tip_pow: String = ""
var _scrap_icon: TextureRect
var _scrap: Label
var _goal_icon: TextureRect
var _sep: ColorRect
var _goal: Label
var _tut: Label
var _tip: PanelContainer
var _tip_label: Label
var _row_w: float = 0.0
var _row_h: float = 10.0
var _row2_w: float = 0.0
var _row2_h: float = 10.0
var _goal_x: float = 0.0
var _ready_state: bool = false
var _tip_text: String = ""
var _pulse: float = 0.0
var _tut_key: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	theme = UiTheme.build()
	_build()
	steps = FirstSteps.new()
	add_child(steps)
	steps.changed.connect(refresh)
	ScreenUtil.connect_to("Game", "state_changed", refresh)
	ScreenUtil.connect_to("Game", "visit_happened", func(_i: Dictionary) -> void: refresh())
	ScreenUtil.connect_to("I18n", "locale_changed", func(_c: String) -> void: refresh())
	mouse_exited.connect(_hide_tip)
	refresh()


func _build() -> void:
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 1)
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.position = Vector2(2, 0)
	add_child(_col)
	_row1 = HBoxContainer.new()
	_row1.add_theme_constant_override("separation", 2)
	_row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(_row1)
	_face = TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = BunkerArt.texture("man_idle")
	at.region = FACE
	_face.texture = at
	_face.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_face.custom_minimum_size = Vector2(FRAME, FRAME)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row1.add_child(_face)
	_needs_box = HBoxContainer.new()
	_needs_box.add_theme_constant_override("separation", 3)
	_needs_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row1.add_child(_needs_box)
	for n in NEEDS:
		var one := HBoxContainer.new()
		one.add_theme_constant_override("separation", 1)
		one.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := NeedGauge.new()
		g.need = n
		one.add_child(g)
		var l := _label()
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		one.add_child(l)
		_needs_box.add_child(one)
		_gauges[n] = g
		_pcts[n] = l
	_row1.add_child(_new_sep())
	_day = _label()
	_row1.add_child(_day)
	_row1.add_child(_new_sep())
	_pow_box = HBoxContainer.new()
	_pow_box.add_theme_constant_override("separation", 1)
	_pow_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pow_icon = _icon("energia")
	_pow_box.add_child(_pow_icon)
	_pow = _label()
	_pow_box.add_child(_pow)
	_row1.add_child(_pow_box)
	_row2 = HBoxContainer.new()
	_row2.add_theme_constant_override("separation", 2)
	_row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(_row2)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(ROW2_X - 4, 0)
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row2.add_child(indent)
	_scrap_icon = _icon("sucata")
	_row2.add_child(_scrap_icon)
	_scrap = _label()
	_row2.add_child(_scrap)
	_sep = _new_sep()
	_row2.add_child(_sep)
	_goal_icon = _icon("estrela")
	_row2.add_child(_goal_icon)
	_goal = _label()
	_row2.add_child(_goal)
	_tut = _label()
	_tut.add_theme_color_override("font_color", UiTheme.AMBER3)
	_col.add_child(_tut)
	_tip = PanelContainer.new()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.z_index = 10
	add_child(_tip)
	_tip_label = _label()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(TIP_W, 0)
	_tip.add_child(_tip_label)


func _new_sep() -> ColorRect:
	var sep := ColorRect.new()
	sep.color = UiTheme.CONC2
	sep.custom_minimum_size = Vector2(1, 8)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


func _icon(name: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = UiTheme.icon(name)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _label() -> Label:
	var l := Label.new()
	l.theme_type_variation = "LabelSmall"
	l.add_theme_color_override("font_color", UiTheme.PAPER)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func refresh() -> void:
	var game: Node = ScreenUtil.node("Game")
	if game == null or not game.has_method("sucata"):
		return
	_scrap.text = ScreenUtil.tr_key("hud.scrap", {"n": int(game.call("sucata"))})
	_refresh_vitals(game)
	var g: Dictionary = Guide.next_goal(game)
	_tip_text = ""
	if g.is_empty():
		_goal_icon.visible = false
		_sep.visible = false
		_goal.text = ""
	else:
		_goal_icon.visible = true
		_sep.visible = true
		_ready_state = bool(g["ready"])
		var name: String = Guide.goal_name(g)
		var desc: String = Guide.goal_desc(g)
		if _ready_state:
			_goal.text = ScreenUtil.tr_key("hud.ready", {"name": name})
			_goal.add_theme_color_override("font_color", UiTheme.SIGNAL)
			_goal_icon.texture = UiTheme.icon("check")
			_tip_text = _join([desc, ScreenUtil.tr_key("hud.tip.ready")])
		else:
			var cost: int = int(g["cost"])
			var left: int = maxi(0, cost - int(g["have"]))
			_goal.text = name
			_goal.add_theme_color_override("font_color", UiTheme.AMBER3)
			_goal_icon.texture = UiTheme.icon("estrela")
			_tip_text = _join([desc, ScreenUtil.tr_key("hud.tip.saving", {"n": left, "cost": cost})])
	_tut_key = steps.current_key() if steps != null else ""
	_tut.visible = _tut_key != ""
	if _tut_key != "":
		_tut.text = ScreenUtil.tr_key(_tut_key)
	set_process(_tut_key == "tut.4" or _need_state == "bad" or _power_state == "bad")
	call_deferred("_layout")


## Dia, energia e a moldura do retrato (a pior necessidade). O vermelho visível também arma o prazo da morte.
func _refresh_vitals(game: Node) -> void:
	_day.text = ScreenUtil.tr_key("ui.day", {"n": int(game.call("day_index")) + 1})
	var have: int = int(game.call("power_supply"))
	var use: int = int(game.call("power_demand"))
	_pow.text = "%d/%d" % [use, have]
	_power_state = "bad" if use > have else ("warn" if use == have else "ok")
	var col: Color = {"bad": UiTheme.TOMATO, "warn": UiTheme.AMBER3, "ok": UiTheme.PAPER}[_power_state]
	_pow.add_theme_color_override("font_color", col)
	_pow_icon.modulate = col if _power_state != "ok" else Color.WHITE
	var tiers: Dictionary = {}
	if game.has_method("line_tiers"):
		tiers = game.call("line_tiers") as Dictionary
	_tip_pow = _join([ScreenUtil.tr_key("hud.energy.lack" if _power_state == "bad" else "hud.energy.ok", {"use": use, "have": have}),
		ScreenUtil.tr_key("hud.energy.bike") if String(tiers.get("energia", "bicicleta")) == "bicicleta" else "",
		ScreenUtil.tr_key("hud.energy.click")])
	_need_state = String(game.call("worst_need_state"))
	for n: String in NEEDS:
		var st: String = String(game.call("need_state", n))
		var g: NeedGauge = _gauges[n]
		g.level = float(game.call("need_level", n))
		g.state = st
		var pl: Label = _pcts[n]
		pl.text = str(int(roundf(g.level * 100.0)))
		pl.add_theme_color_override("font_color", {"ok": UiTheme.PAPER, "warn": UiTheme.AMBER3, "bad": UiTheme.TOMATO}[st])
	if _need_state == "bad" and is_visible_in_tree():
		game.call("ack_warning")


func _join(lines: Array) -> String:
	var out: Array[String] = []
	for l in lines:
		if String(l) != "":
			out.append(String(l))
	return "\n".join(out)


func _layout() -> void:
	_row_h = _row1.get_combined_minimum_size().y
	_row_w = 2.0 + _row1.get_combined_minimum_size().x + 4.0
	_row2_h = _row2.get_combined_minimum_size().y
	_row2_w = 2.0 + _row2.get_combined_minimum_size().x + 4.0
	# posição da meta na linha (calculada pelos mínimos: o contêiner só se ajeita no quadro seguinte)
	_goal_x = _x_of(_goal_icon, _row2) - 3.0
	custom_minimum_size = Vector2(maxf(_row_w, _row2_w), _col.get_combined_minimum_size().y)
	size = custom_minimum_size
	queue_redraw()


## Posição x (no HUD) de um filho da linha, somando os mínimos dos que vêm antes: o contêiner só se ajeita no quadro seguinte.
func _x_of(node: Control, row: HBoxContainer = null) -> float:
	var x: float = 2.0
	for c: Node in (row if row != null else _row1).get_children():
		var ctl := c as Control
		if ctl == null or not ctl.visible:
			continue
		if ctl == node:
			return x
		x += ctl.get_combined_minimum_size().x + 2.0
	return x


## Retângulo do raio de energia (coordenadas do pai), onde o cartão do gerador se ancora.
func energy_rect() -> Rect2:
	return Rect2(position + Vector2(_x_of(_pow_box), 0), Vector2(_pow_box.get_combined_minimum_size().x, _row_h))


func _draw() -> void:
	var back := Color(UiTheme.INK, BACK_ALPHA)
	draw_rect(Rect2(0, 0, _row_w, _row_h), back)
	# moldura do retrato: a pior necessidade (vermelho pisca)
	var frame: Color = {"ok": UiTheme.CONC1, "warn": UiTheme.AMBER2, "bad": UiTheme.TOMATO}[_need_state]
	if _need_state == "bad" and fmod(_blink, BLINK_S * 2.0) >= BLINK_S:
		frame = UiTheme.CONC1
	draw_rect(Rect2(2.5, 0.5, FRAME - 1.0, _row_h - 1.0), frame, false, 1.0)
	var y2: float = _row_h + 1.0
	draw_rect(Rect2(ROW2_X - 2, y2, _row2_w - ROW2_X + 2, _row2_h), back)
	var y: float = y2 + _row2_h + 1.0
	if _tut.visible:
		var t: Vector2 = _tut.get_combined_minimum_size()
		draw_rect(Rect2(1, y, t.x + 3.0, t.y), back)
	if _tut_key == "tut.4" and _goal_icon.visible and fmod(_pulse, 0.8) < 0.5:
		draw_rect(Rect2(_goal_x - 2.0, y2, _row2_w - _goal_x + 1.0, _row2_h), UiTheme.AMBER3, false, 1.0)


func _process(delta: float) -> void:
	_pulse += delta
	_blink += delta
	if _power_state == "bad":
		var on: bool = fmod(_blink, BLINK_S * 2.0) < BLINK_S
		_pow_icon.modulate = UiTheme.TOMATO if on else Color(UiTheme.TOMATO, 0.25)
		_pow.add_theme_color_override("font_color", UiTheme.TOMATO if on else UiTheme.CONC2)
	queue_redraw()


## Só a linha de cima recebe clique; o resto deixa passar (a escotilha fica clicável).
func _has_point(point: Vector2) -> bool:
	if point.y < 0.0 or point.x < 0.0:
		return false
	if point.y < _row_h:
		return point.x < _row_w
	return point.y < _row_h + 1.0 + _row2_h and point.x >= ROW2_X - 2 and point.x < _row2_w


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		if mm.position.y < _row_h and _in_energy(mm.position.x) and _tip_pow != "":
			_show_tip(_tip_pow)
		elif mm.position.y >= _row_h and _tip_text != "" and mm.position.x >= _goal_x:
			_show_tip(_tip_text)
		else:
			_hide_tip()
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.position.y >= _row_h:
		clicked.emit()   # sucata e meta: abre o Construir
	elif _in_energy(mb.position.x):
		energy_clicked.emit()
	else:
		man_clicked.emit()   # retrato, medidores e dia
	accept_event()


## Retângulo do retratinho (coordenadas do pai), onde o cartão do Joaquim se ancora.
func face_rect() -> Rect2:
	return Rect2(position + Vector2(2, 0), Vector2(_face.get_combined_minimum_size().x, _row_h))


func _in_energy(x: float) -> bool:
	var x0: float = _x_of(_pow_box)
	return x >= x0 - 3.0 and x < x0 + _pow_box.get_combined_minimum_size().x + 3.0


func _show_tip(text: String) -> void:
	_tip_label.text = text
	_tip.visible = true
	_tip.size = Vector2.ZERO
	_tip.position = Vector2(2, _col.get_combined_minimum_size().y + 3)


func _hide_tip() -> void:
	_tip.visible = false


func tip_visible() -> bool:
	return _tip.visible
