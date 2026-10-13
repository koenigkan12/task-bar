class_name IntroScreen
extends Control
## Introdução de 4 páginas no primeiro jogo (porquê, o que ele faz, o que você faz, o que fazer agora).
## Ocupa só a parte de cima (a área da gaveta); a faixa do bunker continua rodando embaixo.

signal finished()

const PAGES: Array[String] = ["intro.1", "intro.2", "intro.3", "intro.4"]
const SIZE := Vector2(344, 120)

var _page: int = 0
var _text: Label
var _btn: Button
var _dots: Label


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.build()
	var back := PanelContainer.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	back.add_child(box)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.add_theme_color_override("font_color", UiTheme.PAPER)
	box.add_child(_text)
	var row := HBoxContainer.new()
	box.add_child(row)
	_dots = Label.new()
	_dots.theme_type_variation = "LabelMuted"
	_dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_dots)
	_btn = Button.new()
	_btn.pressed.connect(_next)
	row.add_child(_btn)
	_show()
	_btn.grab_focus()


func _show() -> void:
	_text.text = ScreenUtil.tr_key(PAGES[_page])
	_dots.text = " ".join(range(PAGES.size()).map(func(i: int) -> String: return "●" if i == _page else "○"))
	_btn.text = ScreenUtil.tr_key("intro.start" if _page == PAGES.size() - 1 else "intro.next")


func _next() -> void:
	if _page >= PAGES.size() - 1:
		finished.emit()
		return
	_page += 1
	_show()
