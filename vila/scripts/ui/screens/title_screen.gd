class_name TitleScreen
extends Control
## Tela de título por cima da vila (a vila salva fica parada ao fundo, escurecida):
## Continuar / Novo jogo (confirma se há save) / Opções / Sair.
## Chama Game.load_game()/new_game() e avisa o fluxo por sinais; Opções só emite o pedido.

signal game_started(is_new: bool)
signal options_requested()
signal quit_requested()

var _buttons: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ScreenUtil.connect_to("I18n", "locale_changed", _on_locale_changed)
	ScreenUtil.connect_to("Settings", "changed", _on_setting_changed)
	_build()


func _exit_tree() -> void:
	ScreenUtil.disconnect_from("I18n", "locale_changed", _on_locale_changed)
	ScreenUtil.disconnect_from("Settings", "changed", _on_setting_changed)


## Foco no primeiro botão (teclado/controle).
func focus_first() -> void:
	if _buttons != null and _buttons.get_child_count() > 0:
		(_buttons.get_child(0) as Control).grab_focus()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	theme = UiTheme.build()
	# Faixa escura à esquerda, a vila aparece à direita.
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.INK, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var side := PanelContainer.new()
	side.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	side.offset_left = 8
	side.offset_top = 8
	side.offset_bottom = -8
	side.offset_right = 150
	add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	side.add_child(col)
	var name_lbl: Label = ScreenUtil.label("title.name", "LabelTitle")
	name_lbl.name = "TitleName"
	col.add_child(name_lbl)
	var sub: Label = ScreenUtil.label("title.subtitle", "LabelSmall")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(130, 0)
	col.add_child(sub)
	var info: String = _save_info()
	if info != "":
		var info_lbl := Label.new()
		info_lbl.name = "SaveInfo"
		info_lbl.text = info
		info_lbl.theme_type_variation = "LabelAmber"
		col.add_child(info_lbl)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	_buttons = VBoxContainer.new()
	_buttons.name = "Buttons"
	_buttons.add_theme_constant_override("separation", 3)
	col.add_child(_buttons)
	var has_save: bool = bool(ScreenUtil.call_on("Game", "has_save", [], false))
	if has_save:
		_add_button("Continue", "title.btn.continue", _on_continue)
	_add_button("New", "title.btn.new", _on_new)
	_add_button("Options", "title.btn.options", func() -> void: options_requested.emit())
	_add_button("Quit", "title.btn.quit", _on_quit)


func _add_button(node_name: String, key: String, cb: Callable) -> void:
	var b := Button.new()
	b.name = node_name
	b.text = ScreenUtil.tr_key(key)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	_buttons.add_child(b)


func _save_info() -> String:
	# Resumo opcional do save sem carregar (Game.save_summary() -> {day, antenna}), se existir.
	var s: Variant = ScreenUtil.call_on("Game", "save_summary", [], null)
	if s is Dictionary and (s as Dictionary).has("day"):
		var d: Dictionary = s
		return ScreenUtil.tr_key("title.save_info", {"day": int(d.get("day", 0)) + 1, "antenna": int(d.get("antenna", 1))})
	return ""


func _on_continue() -> void:
	_unlock_sound()
	if bool(ScreenUtil.call_on("Game", "load_game", [], false)):
		game_started.emit(false)
	else:
		_start_new()


func _on_new() -> void:
	_unlock_sound()
	if bool(ScreenUtil.call_on("Game", "has_save", [], false)):
		ConfirmBox.ask(self, "title.new.title", "title.new.text", "title.new.btn", _start_new)
	else:
		_start_new()


func _start_new() -> void:
	ScreenUtil.call_on("Game", "new_game")
	game_started.emit(true)


func _on_quit() -> void:
	quit_requested.emit()
	if ScreenUtil.node("WindowService") != null and ScreenUtil.node("WindowService").has_method("quit_game"):
		ScreenUtil.call_on("WindowService", "quit_game")
	else:
		get_tree().quit()


func _unlock_sound() -> void:
	# Primeira interação libera o som (contrato 4.5).
	ScreenUtil.call_on("AudioManager", "unlock")


func _on_locale_changed(_code: String) -> void:
	call_deferred("_build")


func _on_setting_changed(key: String) -> void:
	if key == "text_size":
		call_deferred("_build")
