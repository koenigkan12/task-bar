class_name EndingScreen
extends Control
## Sobreposição do final, sem tutorial nem pop-up: cobre a janela (faixa ou gaveta) com um véu
## escuro e mostra o texto em páginas curtas. Clique (ou Enter/Espaço) adianta a página.
## play_arrival(): batidas, luz, "Vai demorar, ela disse." ... créditos -> finished("arrival")
## show_next_day(): "Na manhã seguinte" + 3 linhas -> finished("next_day")
## show_demo_end(): fim da demonstração -> finished("demo_continue") ou finished("demo_quit")
## show_death(dias): "Joaquim não aguentou." + dias vividos -> finished("restart") ou finished("diary")
## Não chama Game.finish_arrival(): quem integra decide quando (contrato 5.2).

signal finished(kind: String)

const FADE: float = 0.6

## Páginas da chegada: [chaves, segundos parada]. Variação "LabelTitle" para títulos.
const ARRIVAL_PAGES: Array = [
	[["ending.knock"], 3.5, "LabelMuted"],
	[["ending.light"], 3.5, "LabelMuted"],
	[["ending.title"], 3.5, "LabelTitle"],
	[["ending.line.1", "ending.line.2"], 4.0, ""],
]

var kind: String = ""
var _veil: ColorRect
var _box: VBoxContainer
var _pages: Array = []
var _page: int = -1
var _wait: float = 0.0
var _final_buttons: Array = []   # [[chave, tipo de saída]]
var _final_title: String = ""
var _final_lines: Array = []
var _final_args: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.build()
	_veil = ColorRect.new()
	_veil.color = Color(UiTheme.INK, 0.88)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_box = VBoxContainer.new()
	_box.name = "Text"
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 1)
	center.add_child(_box)
	if kind == "":
		visible = false


func play_arrival() -> void:
	kind = "arrival"
	_pages = ARRIVAL_PAGES.duplicate(true)
	_final_title = ""
	_final_lines = ["ending.credits"]
	_final_buttons = [["screens.ending.next", "arrival"]]
	_start()


func show_next_day() -> void:
	kind = "next_day"
	_pages = []
	_final_title = "ending.nextday.title"
	_final_lines = ["ending.nextday.line.1", "ending.nextday.line.2", "ending.nextday.line.3"]
	_final_buttons = [["ending.continue", "next_day"]]
	_start()


func show_demo_end() -> void:
	kind = "demo"
	_pages = []
	_final_title = "ending.demo.title"
	_final_lines = ["ending.demo.line", "ending.demo.wish"]
	_final_buttons = [["title.btn.quit", "demo_quit"], ["ending.continue", "demo_continue"]]
	_start()


func show_death(days: int) -> void:
	kind = "death"
	_pages = []
	_final_title = "ending.death.title"
	_final_args = {"n": days}
	_final_lines = ["ending.death.line.one" if days <= 1 else "ending.death.line"]
	_final_buttons = [["ending.death.diary", "diary"], ["ending.death.restart", "restart"]]
	_start()


## Pula direto para a última página (teste e captura).
func skip_to_end() -> void:
	_page = _pages.size() - 1
	_next_page()


func _start() -> void:
	visible = true
	_page = -1
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE)
	_next_page()


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_next_page()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _wait > 0.0:
		accept_event()
		_next_page()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and _wait > 0.0 and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_next_page()


func _next_page() -> void:
	_page += 1
	_clear()
	if _page < _pages.size():
		var p: Array = _pages[_page]
		for key: String in p[0]:
			_add_line(key, str(p[2]))
		_wait = float(p[1])
		_fade_in_box()
		return
	_wait = 0.0
	if _final_title != "":
		_add_line(_final_title, "LabelTitle")
	for key: String in _final_lines:
		_add_line(key, "LabelSmall" if kind == "arrival" else "")
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(row)
	var first: Button = null
	for b: Array in _final_buttons:
		var btn := Button.new()
		btn.text = ScreenUtil.tr_key(str(b[0]))
		btn.name = str(b[1])
		btn.pressed.connect(_finish.bind(str(b[1])))
		row.add_child(btn)
		first = btn
	if first != null:
		first.call_deferred("grab_focus")
	_fade_in_box()


func _add_line(key: String, variation: String) -> void:
	var l: Label = ScreenUtil.label(key, variation, _final_args)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(size.x - 16.0, 300.0) if size.x > 32.0 else 300.0, 0)
	_box.add_child(l)


func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


func _fade_in_box() -> void:
	_box.modulate.a = 0.0
	create_tween().tween_property(_box, "modulate:a", 1.0, FADE)


func _finish(exit_kind: String) -> void:
	_wait = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE)
	tw.tween_callback(func() -> void:
		visible = false
		finished.emit(exit_kind))
	if exit_kind == "demo_quit":
		ScreenUtil.call_on("WindowService", "quit_game")
