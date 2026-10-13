class_name HintLayer
extends Control
## Dicas de primeiro uso (hint.*), sem tutorial: um balão discreto por vez no canto de cima,
## some sozinho (ou com um clique) e nunca repete (Settings "hints_seen").
## Gatilhos automáticos: novo jogo (drag, hide), welcome_back (offline),
## primeira fala (radio), caixa transbordando (box), falta de energia (power).
## Os demais (build, planting, goal, demolish, move, pra_que, dig) a gaveta pede:
##   HintLayer.request("build")

const GROUP: String = "hint_layer"
const SEEN_KEY: String = "hints_seen"
const MIN_SECONDS: float = 5.0
const PER_CHAR: float = 0.06
const GAP: float = 1.0

## false = guarda na fila e não mostra (ex.: com a tela de título aberta).
var enabled: bool = true:
	set(v):
		enabled = v
		if v and _current == null:
			_gap = 0.0

var _queue: Array[String] = []
var _current: PanelContainer = null
var _left: float = 0.0
var _gap: float = 0.0


## Pede uma dica a quem estiver na árvore. Devolve false se já vista ou sem HintLayer.
static func request(id: String) -> bool:
	var loop: MainLoop = Engine.get_main_loop()
	if not loop is SceneTree:
		return false
	var layer: Node = (loop as SceneTree).get_first_node_in_group(GROUP)
	if layer is HintLayer:
		return (layer as HintLayer).show_hint(id)
	return false


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 5
	theme = UiTheme.build()
	ScreenUtil.connect_to("Game", "new_game_started", _on_new_game)
	ScreenUtil.connect_to("Game", "welcome_back", _on_welcome_back)
	ScreenUtil.connect_to("Game", "radio_line", _on_radio_line)
	ScreenUtil.connect_to("Game", "box_state_changed", _on_box_state)
	ScreenUtil.connect_to("Game", "state_changed", _on_state_changed)


## Enfileira a dica `id` (sem o prefixo "hint."). Já vista ou já na fila -> false.
func show_hint(id: String, force: bool = false) -> bool:
	id = id.trim_prefix("hint.")
	if not force and (was_seen(id) or _queue.has(id)):
		return false
	_queue.append(id)
	return true


func was_seen(id: String) -> bool:
	return _seen().has(id.trim_prefix("hint."))


## Esquece as dicas vistas (Opções > apagar progresso pode chamar).
func reset_seen() -> void:
	ScreenUtil.set_setting(SEEN_KEY, [])


func dismiss() -> void:
	if _current != null:
		_current.queue_free()
		_current = null
		_gap = GAP


func current_id() -> String:
	return str(_current.get_meta("hint_id")) if _current != null else ""


func _process(delta: float) -> void:
	if _current != null:
		_left -= delta
		if _left <= 0.0:
			dismiss()
		return
	if _gap > 0.0:
		_gap -= delta
		return
	if enabled and not _queue.is_empty():
		_show(_queue.pop_front())


func _show(id: String) -> void:
	_mark_seen(id)
	var text: String = ScreenUtil.tr_key("hint." + id)
	var panel := PanelContainer.new()
	panel.name = "Hint"
	panel.set_meta("hint_id", id)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.position = Vector2(4, 3)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	panel.add_child(row)
	var ico := TextureRect.new()
	ico.texture = UiTheme.icon("book")
	ico.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ico)
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "LabelSmall"
	l.add_theme_color_override("font_color", UiTheme.PAPER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(220.0, maxf(100.0, size.x - 30.0)), 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			dismiss())
	add_child(panel)
	_current = panel
	_left = maxf(MIN_SECONDS, text.length() * PER_CHAR + 3.0)
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.3)


func _seen() -> Array:
	var v: Variant = ScreenUtil.setting(SEEN_KEY, [])
	return v if v is Array else []


func _mark_seen(id: String) -> void:
	var s: Array = _seen().duplicate()
	if not s.has(id):
		s.append(id)
		ScreenUtil.set_setting(SEEN_KEY, s)


func _on_new_game() -> void:
	show_hint("drag")
	show_hint("hide")


func _on_welcome_back(_summary: Dictionary) -> void:
	show_hint("offline")


func _on_radio_line(_line: Dictionary) -> void:
	show_hint("radio")


func _on_box_state(_fill: float, overflow: bool) -> void:
	if overflow:
		show_hint("box")


func _on_state_changed() -> void:
	if not bool(ScreenUtil.call_on("Game", "power_ok", [], true)):
		show_hint("power")
