class_name StatusHud
extends Control
## Faixa de status sempre visível: sucata e a próxima meta ("o que faço agora?").
## Clicar na linha de cima abre a gaveta na aba Construir. O texto do tutorial fica à direita da
## escotilha, deixa os cliques passarem e pode ser recolhido no botão "−" / "?".

signal clicked()

const BACK_ALPHA: float = 0.6
const TUT_X: int = 40     ## o texto do tutorial começa depois da escotilha (x 8..40)
const TUT_W: int = 150

var _toggle: Label
var _row_w: float = 0.0
var _row_h: float = 12.0
var _tut_h: float = 0.0
var _tut_hidden: bool = false
var _scrap_icon: TextureRect
var _scrap: Label
var _stock_icon: TextureRect
var _stock: Label
var _goal_icon: TextureRect
var _goal: Label
var _last_text: String = ""
var _tut: Label
var _col: VBoxContainer
var steps: FirstSteps
var _ready_state: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	theme = UiTheme.build()
	_tut_hidden = bool(ScreenUtil.setting("tutorial_hidden", false))
	_build()
	steps = FirstSteps.new()
	add_child(steps)
	steps.changed.connect(refresh)
	ScreenUtil.connect_to("Game", "state_changed", refresh)
	ScreenUtil.connect_to("Game", "visit_happened", func(_i: Dictionary) -> void: refresh())
	ScreenUtil.connect_to("I18n", "locale_changed", func(_c: String) -> void: refresh())
	refresh()


func _build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.position = Vector2(2, 0)
	add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	_tut = _label()
	_tut.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tut.custom_minimum_size = Vector2(TUT_W - 6, 0)
	_tut.size = Vector2(TUT_W - 6, 0)
	_tut.add_theme_color_override("font_color", UiTheme.AMBER3)
	add_child(_tut)
	_col = col
	_scrap_icon = _icon("sucata")
	row.add_child(_scrap_icon)
	_scrap = _label()
	row.add_child(_scrap)
	_stock_icon = _icon("cesto")
	row.add_child(_stock_icon)
	_stock = _label()
	row.add_child(_stock)
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(3, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sep)
	_goal_icon = _icon("arrow_up")
	row.add_child(_goal_icon)
	_goal = _label()
	row.add_child(_goal)
	_toggle = _label()
	_toggle.add_theme_color_override("font_color", UiTheme.AMBER3)
	row.add_child(_toggle)


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
	_scrap.text = str(int(game.call("sucata")))
	_stock.text = str(int(game.call("box_stock")))
	var g: Dictionary = Guide.next_goal(game)
	var text: String
	if g.is_empty():
		_goal_icon.visible = false
		_goal.text = ""
		text = ""
	else:
		var name: String = ScreenUtil.tr_key(String(g["name_key"]))
		_goal_icon.visible = true
		_ready_state = bool(g["ready"])
		if _ready_state:
			_goal.text = ScreenUtil.tr_key("hud.ready", {"name": name})
			_goal.add_theme_color_override("font_color", UiTheme.SIGNAL)
			_goal_icon.texture = UiTheme.icon("check")
		else:
			_goal.text = ScreenUtil.tr_key("hud.goal", {"name": name, "have": int(g["have"]), "cost": int(g["cost"])})
			_goal.add_theme_color_override("font_color", UiTheme.PAPER)
			_goal_icon.texture = UiTheme.icon("arrow_up")
		text = _goal.text
	_last_text = text
	await get_tree().process_frame
	var tut_key: String = steps.current_key() if steps != null else ""
	_toggle.visible = tut_key != ""
	_toggle.text = "?" if _tut_hidden else "-"
	_tut.visible = tut_key != "" and not _tut_hidden
	if tut_key != "":
		_tut.text = ScreenUtil.tr_key(tut_key)
	await get_tree().process_frame
	_row_w = 6.0 + _scrap_icon.size.x + _scrap.size.x + _stock_icon.size.x + _stock.size.x + 9.0
	if _goal_icon.visible:
		_row_w += _goal_icon.size.x + _goal.size.x + 2.0
	if _toggle.visible:
		_row_w += _toggle.size.x + 3.0
	_row_h = 12.0
	_tut_h = (_tut.size.y + 2.0) if _tut.visible else 0.0
	_tut.position = Vector2(TUT_X + 3, _row_h + 1)
	custom_minimum_size = Vector2(maxf(_row_w, TUT_X + TUT_W if _tut.visible else 0.0), _row_h + _tut_h)
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	var back := Color(UiTheme.INK, BACK_ALPHA)
	draw_rect(Rect2(0, 0, _row_w, _row_h), back)
	if _tut.visible:
		draw_rect(Rect2(TUT_X, _row_h, TUT_W, _tut_h), back)


## Só a linha de cima recebe clique; o texto do tutorial deixa passar (a escotilha fica clicável).
func _has_point(point: Vector2) -> bool:
	return point.y >= 0.0 and point.y < _row_h and point.x >= 0.0 and point.x < _row_w


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _toggle.visible and mb.position.x >= _row_w - _toggle.size.x - 5.0:
		_tut_hidden = not _tut_hidden
		ScreenUtil.set_setting("tutorial_hidden", _tut_hidden)
		refresh()
	else:
		clicked.emit()
	accept_event()
