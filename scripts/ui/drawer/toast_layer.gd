class_name DrawerToastLayer
extends VBoxContainer
## Avisos curtos (texto + ícone), um por vez, sem som. Aparecem no céu da faixa,
## no canto direito, e somem sozinhos. Repetidos em sequência viram um só.

const SHOW_S: float = 3.0
const FADE_S: float = 0.25
const MAX_QUEUE: int = 4

var _queue: Array[Dictionary] = []
var _current: Control = null
var _current_text: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN


func push(text: String, icon_name: String = "") -> void:
	if text == _current_text or (not _queue.is_empty() and _queue.back()["text"] == text):
		return
	_queue.append({"text": text, "icon": icon_name})
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()
	if _current == null:
		_next()


func current_text() -> String:
	return _current_text


func pending() -> int:
	return _queue.size()


func clear_all() -> void:
	_queue.clear()
	if _current != null:
		_current.queue_free()
	_current = null
	_current_text = ""


func _next() -> void:
	if _queue.is_empty():
		_current = null
		_current_text = ""
		return
	var t: Dictionary = _queue.pop_front()
	_current_text = str(t["text"])
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.nine("panel_9s", 4.0, 1.0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.add_child(DrawerUi.icon_text(str(t["icon"]), _current_text, "LabelSmall"))
	p.modulate.a = 0.0
	add_child(p)
	_current = p
	if not is_inside_tree():
		return
	var tw: Tween = create_tween()
	tw.tween_property(p, "modulate:a", 1.0, FADE_S)
	tw.tween_interval(SHOW_S)
	tw.tween_property(p, "modulate:a", 0.0, FADE_S)
	tw.tween_callback(_done.bind(p))


func _done(p: Control) -> void:
	if p == _current:
		p.queue_free()
		_next()
