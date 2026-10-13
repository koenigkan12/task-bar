class_name StatusHud
extends Control
## Faixa de status sempre visível, de uma linha só: "[sucata] 12 sucata | [estrela] Gotejador".
## Meta pronta: "[check] Comprar Gotejador". Sem barra de progresso: o que falta fica só no hover
## ("Faltam 28 sucata"), junto com a explicação do item. Clicar na linha de cima abre a gaveta
## em Construir. O tutorial é uma linha curta abaixo (a seta e o contorno ficam no objeto, ver PlotTip);
## só a linha de cima recebe clique: o resto deixa passar, para a escotilha continuar clicável.

signal clicked()
## Clicou no retratinho do Joaquim: a Main abre o cartão dele.
signal man_clicked()

const BACK_ALPHA: float = 0.6
const TIP_W: int = 150
const FACE: Rect2 = Rect2(10, 2, 12, 12)   # rosto no quadro do homem parado

var steps: FirstSteps

var _col: VBoxContainer
var _row1: HBoxContainer
var _face: TextureRect
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
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row1.add_child(_face)
	_scrap_icon = _icon("sucata")
	_row1.add_child(_scrap_icon)
	_scrap = _label()
	_row1.add_child(_scrap)
	_sep = ColorRect.new()
	var sep: ColorRect = _sep
	sep.color = UiTheme.CONC2
	sep.custom_minimum_size = Vector2(1, 8)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row1.add_child(sep)
	_goal_icon = _icon("estrela")
	_row1.add_child(_goal_icon)
	_goal = _label()
	_row1.add_child(_goal)
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
	set_process(_tut_key == "tut.4")
	call_deferred("_layout")


func _join(lines: Array) -> String:
	var out: Array[String] = []
	for l in lines:
		if String(l) != "":
			out.append(String(l))
	return "\n".join(out)


func _layout() -> void:
	_row_h = _row1.get_combined_minimum_size().y
	_row_w = 2.0 + _row1.get_combined_minimum_size().x + 4.0
	# posição da meta na linha (calculada pelos mínimos: o contêiner só se ajeita no quadro seguinte)
	_goal_x = 2.0 + _face.get_combined_minimum_size().x + 2.0 + _scrap_icon.get_combined_minimum_size().x + _scrap.get_combined_minimum_size().x + 1.0 + 4.0 * 2.0
	custom_minimum_size = Vector2(_row_w, _col.get_combined_minimum_size().y)
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	var back := Color(UiTheme.INK, BACK_ALPHA)
	draw_rect(Rect2(0, 0, _row_w, _row_h), back)
	var y: float = _row_h + 1.0
	if _tut.visible:
		var t: Vector2 = _tut.get_combined_minimum_size()
		draw_rect(Rect2(1, y, t.x + 3.0, t.y), back)
	if _tut_key == "tut.4" and _goal_icon.visible and fmod(_pulse, 0.8) < 0.5:
		draw_rect(Rect2(_goal_x - 2.0, 0, _row_w - _goal_x + 1.0, _row_h), UiTheme.AMBER3, false, 1.0)


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


## Só a linha de cima recebe clique; o resto deixa passar (a escotilha fica clicável).
func _has_point(point: Vector2) -> bool:
	return point.y >= 0.0 and point.y < _row_h and point.x >= 0.0 and point.x < _row_w


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _tip_text != "" and mm.position.x >= _goal_x:
			_show_tip()
		else:
			_hide_tip()
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.position.x < 2.0 + _face.get_combined_minimum_size().x + 1.0:
		man_clicked.emit()
	else:
		clicked.emit()
	accept_event()


## Retângulo do retratinho (coordenadas do pai), onde o cartão do Joaquim se ancora.
func face_rect() -> Rect2:
	return Rect2(position + Vector2(2, 0), Vector2(_face.get_combined_minimum_size().x, _row_h))


func _show_tip() -> void:
	_tip_label.text = _tip_text
	_tip.visible = true
	_tip.size = Vector2.ZERO
	_tip.position = Vector2(2, _col.get_combined_minimum_size().y + 3)


func _hide_tip() -> void:
	_tip.visible = false


func tip_visible() -> bool:
	return _tip.visible
