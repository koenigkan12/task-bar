extends SceneTree
# Teste lógico das telas (título, opções, alça/recolher, final, dicas) com autoloads falsos.
# godot --headless --path . --script res://tests/ui_screens_flow.gd

const Fakes = preload("res://tests/ui_screens_fakes.gd")

var _fails: int = 0
var f: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	f = Fakes.install(self)
	var i18n: Node = root.get_node("I18n")
	i18n.call("set_locale", "pt_BR")
	var host := Control.new()
	host.size = Vector2(344, 208)
	root.add_child(host)
	await _title(host)
	await _options(host)
	await _handle(host)
	await _ending(host)
	await _hints(host)
	print("ui_screens_flow: %s" % ("OK" if _fails == 0 else "%d falhas" % _fails))
	quit(1 if _fails > 0 else 0)


func _title(host: Control) -> void:
	var game: Node = f["Game"]
	var t: TitleScreen = (load("res://scenes/ui/title.tscn") as PackedScene).instantiate()
	t.use_live_bunker = false
	host.add_child(t)
	await process_frame
	var btns: Node = t.find_child("Buttons", true, false)
	_ok(btns.get_child_count() == 3 and btns.get_child(0).name == "New", "sem save: Novo/Opções/Sair")
	var started: Array = []
	t.game_started.connect(func(is_new: bool) -> void: started.append(is_new))
	(btns.get_node("New") as Button).pressed.emit()
	_ok(game.calls.has("new_game") and started == [true], "Novo jogo sem save começa direto")
	t.queue_free()
	await process_frame

	game.calls.clear()
	t = (load("res://scenes/ui/title.tscn") as PackedScene).instantiate()
	t.use_live_bunker = false
	host.add_child(t)
	await process_frame
	btns = t.find_child("Buttons", true, false)
	_ok(btns.get_child(0).name == "Continue", "com save: Continuar primeiro")
	_ok(t.find_child("SaveInfo", true, false) != null, "resumo do save")
	(btns.get_node("New") as Button).pressed.emit()
	await process_frame
	var box: ConfirmBox = _find(t, ConfirmBox)
	_ok(box != null and not game.calls.has("new_game"), "Novo jogo com save pede confirmação")
	(box.find_child("Cancel", true, false) as Button).pressed.emit()
	_ok(not game.calls.has("new_game"), "Cancelar não apaga")
	(btns.get_node("Continue") as Button).pressed.emit()
	_ok(game.calls.has("load_game"), "Continuar carrega")
	_ok((f["AudioManager"].calls as Array).has(["unlock"]), "primeira interação libera o som")
	t.queue_free()
	await process_frame


func _options(host: Control) -> void:
	var st: Node = f["Settings"]
	var o: OptionsScreen = (load("res://scenes/ui/options.tscn") as PackedScene).instantiate()
	host.add_child(o)
	await process_frame
	var audio: OptionButton = o.find_child("Audio", true, false)
	audio.select(2)
	audio.item_selected.emit(2)
	_ok(st.data.get("audio_mode") == "full" and (f["AudioManager"].calls as Array).has(["set_mode", "full"]), "modo de áudio grava e aplica")
	var scale: OptionButton = o.find_child("Scale", true, false)
	scale.item_selected.emit(2)
	_ok(st.data.get("ui_scale") == 2 and (f["WindowService"].calls as Array).has(["set_ui_scale", 2]), "escala grava e aplica")
	var top: CheckButton = o.find_child("OnTop", true, false)
	top.button_pressed = true
	_ok(st.data.get("always_on_top") == true, "sempre por cima")
	var vol: HSlider = o.find_child("Volume", true, false)
	vol.value = 0.5
	_ok(is_equal_approx(float(st.data.get("master_volume", 0)), 0.5), "volume")
	var ts: OptionButton = o.find_child("TextSize", true, false)
	ts.item_selected.emit(2)
	await process_frame
	await process_frame
	_ok(o.theme != null and o.theme.default_font_size == 20, "texto enorme refaz o tema (20)")
	st.set_value("text_size", 1.0)
	var lang: OptionButton = o.find_child("Language", true, false)
	lang.item_selected.emit(2)
	await process_frame
	await process_frame
	var back: Button = o.find_child("Back", true, false)
	_ok(back != null and back.text == "Back", "idioma en refaz textos (%s)" % (back.text if back else "?"))
	root.get_node("I18n").call("set_locale", "pt_BR")
	await process_frame
	await process_frame
	(o.find_child("Erase", true, false) as Button).pressed.emit()
	await process_frame
	var box: ConfirmBox = _find(o, ConfirmBox)
	_ok(box != null, "apagar pede confirmação")
	(box.find_child("Ok", true, false) as Button).pressed.emit()
	_ok((f["Game"].calls as Array).has("delete_save"), "apagar chama delete_save")
	o.queue_free()
	await process_frame


func _handle(host: Control) -> void:
	var game: Node = f["Game"]
	var win: Node = f["WindowService"]
	var st: Node = f["Settings"]
	var h: WindowHandle = (load("res://scenes/ui/handle.tscn") as PackedScene).instantiate()
	host.add_child(h)
	await process_frame
	_ok(h.size.x <= 50 and h.size.y <= 13, "alça pequena (%s)" % h.size)
	var tab_layer: CanvasLayer = h.find_child("TabLayer", true, false)
	_ok(not tab_layer.visible, "aba escondida ao abrir")
	(h.find_child("Collapse", true, false) as Button).pressed.emit()
	_ok(win.collapsed and tab_layer.visible and h.collapsed, "recolher chama WindowService e mostra a aba")
	var light: ColorRect = h.find_child("Light", true, false)
	_ok(light.color == UiTheme.DARK3, "sem atenção: luz apagada")
	game.unread = 2
	game.radio_line.emit({})
	_ok(h.has_attention(), "fala nova acende a luz")
	game.unread = 0
	game.state_changed.emit()
	_ok(not h.has_attention() and light.color == UiTheme.DARK3, "lida: apaga")
	var tab: Control = h.find_child("Tab", true, false)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	tab.gui_input.emit(down)
	var up: InputEventMouseButton = down.duplicate()
	up.pressed = false
	tab.gui_input.emit(up)
	_ok(not win.collapsed and not tab_layer.visible, "clique na aba restaura")
	win.set_collapsed(true)
	_ok(h.collapsed and tab_layer.visible, "recolher pela bandeja sincroniza a aba")
	win.set_collapsed(false)
	(h.find_child("Grab", true, false) as Button).button_down.emit()
	_ok((win.calls as Array).has(["start_drag"]), "alça arrasta")
	st.set_value("audio_mode", "silent")
	(h.find_child("Sound", true, false) as Button).pressed.emit()
	_ok(st.data.get("audio_mode") != "silent" and st.data.get("sound_unlocked") == true, "botão de som liga")
	(h.find_child("Sound", true, false) as Button).pressed.emit()
	_ok(st.data.get("audio_mode") == "silent", "botão de som desliga")
	var opened: Array = []
	h.drawer_toggled.connect(func(o: bool) -> void: opened.append(o))
	(h.find_child("Drawer", true, false) as Button).pressed.emit()
	_ok(opened == [true], "botão da gaveta emite")
	h.queue_free()
	await process_frame


func _ending(host: Control) -> void:
	var e: EndingScreen = (load("res://scenes/ui/ending.tscn") as PackedScene).instantiate()
	host.add_child(e)
	await process_frame
	_ok(not e.visible, "final começa escondido")
	var out: Array = []
	e.finished.connect(func(k: String) -> void: out.append(k))
	e.play_arrival()
	_ok(e.visible, "chegada aparece")
	e.skip_to_end()
	var btn: Button = e.find_child("arrival", true, false)
	_ok(btn != null, "botão Seguir no fim da chegada")
	btn.pressed.emit()
	await create_timer(1.0).timeout
	_ok(out == ["arrival"] and not e.visible, "fim da chegada emite finished")
	e.show_next_day()
	(e.find_child("next_day", true, false) as Button).pressed.emit()
	await create_timer(1.0).timeout
	_ok(out.has("next_day"), "próximo dia")
	e.queue_free()


func _hints(host: Control) -> void:
	var st: Node = f["Settings"]
	var hl := HintLayer.new()
	host.add_child(hl)
	await process_frame
	f["Game"].new_game_started.emit()
	await process_frame
	await process_frame
	_ok(hl.current_id() == "first_run", "novo jogo mostra first_run (%s)" % hl.current_id())
	_ok((st.data.get("hints_seen", []) as Array).has("first_run"), "marca como vista")
	_ok(not HintLayer.request("first_run"), "não repete")
	_ok(HintLayer.request("build"), "gaveta pede dica nova")
	hl.dismiss()
	hl.queue_free()


func _find(n: Node, klass: Variant) -> Node:
	for c in n.get_children():
		if is_instance_of(c, klass):
			return c
		var r: Node = _find(c, klass)
		if r != null:
			return r
	return null


func _ok(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		push_error("FALHOU: " + what)
	else:
		print("  ok: " + what)
