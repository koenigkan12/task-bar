class_name ConfirmBox
extends Control
## Pergunta modal dentro da própria janela (sem subjanela): título, texto, Confirmar/Cancelar.
## Uso: ConfirmBox.ask(parent, "title.new.title", "title.new.text", "title.new.btn", func(): ...)

signal answered(ok: bool)

var _on_ok: Callable


static func ask(parent: Control, title_key: String, text_key: String, ok_key: String, on_ok: Callable = Callable()) -> ConfirmBox:
	var box := ConfirmBox.new()
	box._on_ok = on_ok
	parent.add_child(box)
	box._build(title_key, text_key, ok_key)
	return box


func _build(title_key: String, text_key: String, ok_key: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 10
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.INK, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	col.add_child(ScreenUtil.label(title_key, "LabelTitle"))
	var text: Label = ScreenUtil.label(text_key)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(188, 0)
	col.add_child(text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = ScreenUtil.tr_key("ui.btn.cancel")
	cancel.pressed.connect(_answer.bind(false))
	row.add_child(cancel)
	var ok := Button.new()
	ok.name = "Ok"
	ok.text = ScreenUtil.tr_key(ok_key)
	ok.pressed.connect(_answer.bind(true))
	row.add_child(ok)
	cancel.call_deferred("grab_focus")   # o padrão seguro é cancelar


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_answer(false)


func _answer(ok: bool) -> void:
	answered.emit(ok)
	if ok and _on_ok.is_valid():
		_on_ok.call()
	queue_free()
