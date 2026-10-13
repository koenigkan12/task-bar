extends SceneTree
## Teste headless de WindowService com MONITORES SIMULADOS (screens_override): layout, gaveta,
## escala, recolher, posição salva/validada, arrasto, governador de FPS, primeira interação.
## godot --headless --path . --script res://tests/platform_window.gd
## (O retângulo conferido é o estado interno `get_window_rect()`; em --headless nenhuma chamada
## nativa é feita. O teste com janela real é tests/platform_xvfb.gd.)

const WS = preload("res://scripts/platform/window_service.gd")
const TEST_SETTINGS := "user://test_settings_window.json"

var fails: int = 0
var checks: int = 0
var settings: Node


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FALHOU: ", what)


func eq(a: Variant, b: Variant, what: String) -> void:
	checks += 1
	if a != b:
		fails += 1
		print("  FALHOU: %s (obtido %s, esperado %s)" % [what, str(a), str(b)])


func mon(full: Rect2i, bar_h: int = 40) -> Dictionary:
	return {"full": full, "usable": Rect2i(full.position, Vector2i(full.size.x, full.size.y - bar_h))}


func clean_files() -> void:
	for suffix in ["", ".tmp", ".bad"]:
		if FileAccess.file_exists(TEST_SETTINGS + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS + suffix))


func make_ws(screens: Array, primary: int = 0) -> Node:
	var ws: Node = WS.new()
	ws.screens_override = screens
	ws.primary_override = primary
	root.add_child(ws)
	return ws


func press(button: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = button
	Input.parse_input_event(e)


func _initialize() -> void:
	await run()
	settings.reload("user://settings.json")
	clean_files()
	print("platform_window: %d verificações, %d falhas" % [checks, fails])
	quit(1 if fails > 0 else 0)


func run() -> void:
	await process_frame   # deixa a árvore ficar pronta (_ready dos nós adicionados)
	settings = root.get_node_or_null("Settings")
	ok(settings != null, "autoload Settings presente")
	if settings == null:
		return
	clean_files()
	settings.reload(TEST_SETTINGS)
	settings.reset_all()

	var hd: Array = [mon(Rect2i(0, 0, 1920, 1080))]

	# ------------------------------------------------------------------ startup 1080p
	var ws: Node = make_ws(hd)
	eq(ws.logical_size, Vector2i(344, 88), "tamanho lógico inicial = viewport do projeto")
	eq(ws.ui_scale, 2, "escala auto em 1080p = 2")
	eq(ws.get_window_rect(), Rect2i(0, 1040 - 176, 688, 176), "nasce no rodapé da área útil, canto esquerdo")
	var layouts: Array = []
	ws.layout_changed.connect(func(s: Vector2i, k: int) -> void: layouts.append([s, k]))

	# ------------------------------------------------------------------ gaveta cresce para cima
	ws.set_drawer(true)
	eq(ws.logical_size, Vector2i(344, 208), "gaveta: 88 + 120")
	eq(ws.get_window_rect(), Rect2i(0, 1040 - 416, 688, 416), "gaveta: borda inferior fixa, cresce para cima")
	eq(layouts.size(), 1, "layout_changed emitido uma vez")
	eq(layouts[0], [Vector2i(344, 208), 2], "layout_changed(logical, escala)")
	ok(ws.is_drawer_open(), "is_drawer_open")
	ws.set_drawer(true, 120, 344)  # igual: nada muda
	eq(layouts.size(), 1, "sem mudança, sem sinal")
	ws.set_drawer(false)
	eq(ws.get_window_rect(), Rect2i(0, 1040 - 176, 688, 176), "gaveta fechada: volta")
	eq(layouts.size(), 2, "layout_changed ao fechar")

	# faixa com 3 salas (largura 608) + gaveta: largura = max(608, 344)
	ws.set_logical_size(Vector2i(608, 88))
	eq(ws.get_window_rect().size, Vector2i(1216, 176), "3 salas x2")
	ws.set_drawer(true, 120, 344)
	eq(ws.get_window_rect().size, Vector2i(1216, 416), "gaveta com 3 salas: largura da faixa")
	eq(ws.get_window_rect().position, Vector2i(0, 1040 - 416), "esquerda e base preservadas")
	ws.set_logical_size(Vector2i(208, 88))
	eq(ws.logical_size, Vector2i(344, 208), "faixa estreita + gaveta: largura mínima da gaveta")
	ws.set_drawer(false)
	eq(ws.logical_size, Vector2i(208, 88), "sem gaveta: largura da faixa")
	ws.set_logical_size(Vector2i(344, 88))

	# ------------------------------------------------------------------ escala por configuração
	ws.set_ui_scale(3)
	eq(ws.ui_scale, 3, "escala 3")
	eq(ws.get_window_rect().size, Vector2i(344 * 3, 88 * 3), "tamanho x3")
	eq(ws.get_window_rect().end.y, 1040, "base mantida ao mudar a escala")
	ws.set_ui_scale(4)
	ws.set_drawer(true)
	eq(ws.ui_scale, 4, "escala 4 cabe (208*4=832 <= 1040)")
	ws.set_drawer(false)
	ws.set_ui_scale("auto")
	eq(ws.ui_scale, 2, "volta ao auto = 2")
	eq(settings.get_value("ui_scale"), "auto", "Settings guarda ui_scale")
	settings.set_value("ui_scale", 1)  # mudança vinda de fora (tela de opções) também reaplica
	eq(ws.ui_scale, 1, "Settings.changed(ui_scale) reaplica")
	settings.set_value("ui_scale", "auto")

	# ------------------------------------------------------------------ recolher
	var hidden_log: Array = []
	ws.hidden_changed.connect(func(h: bool) -> void: hidden_log.append(h))
	ws.set_collapsed(true)
	ok(ws.is_collapsed(), "is_collapsed")
	eq(ws.logical_size, WS.COLLAPSED_SIZE, "aba 48x16 lógicos")
	eq(ws.get_window_rect(), Rect2i(0, 1040 - 32, 96, 32), "aba no canto inferior esquerdo (x2)")
	eq(hidden_log, [true], "hidden_changed(true)")
	eq(ws.current_fps(), 2, "recolhido: 2 fps")
	var tab_layer: CanvasLayer = ws.get_node("CollapsedTab")
	ok(tab_layer.visible, "aba visível")
	ws.set_drawer(true)  # estado da gaveta muda por baixo, mas a aba continua
	eq(ws.logical_size, WS.COLLAPSED_SIZE, "recolhido ignora gaveta")
	ws.set_drawer(false)
	ws.set_collapsed(true)
	eq(hidden_log, [true], "recolher de novo não repete o sinal")
	# clique na aba restaura
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(10, 5)
	ws.get_node("CollapsedTab/Tab")._gui_input(click)
	click = click.duplicate()
	click.pressed = false
	ws.get_node("CollapsedTab/Tab")._gui_input(click)
	ok(not ws.is_collapsed(), "clicar na aba restaura")
	eq(hidden_log, [true, false], "hidden_changed(false)")
	eq(ws.get_window_rect(), Rect2i(0, 1040 - 176, 688, 176), "restaurado no mesmo canto")
	ok(not tab_layer.visible, "aba escondida")

	# ------------------------------------------------------------------ always on top (só Settings em headless)
	ws.set_always_on_top(true)
	eq(settings.get_value("always_on_top"), true, "always_on_top salvo")
	ws.set_always_on_top(false)

	# ------------------------------------------------------------------ arrasto manual
	ws.mouse_override = Vector2i(100, 1000)
	press(true)
	await process_frame   # o Input só registra o botão no próximo quadro
	ws.start_drag()
	ok(ws.is_dragging(), "is_dragging")
	eq(ws.current_fps(), 60, "arrastando: 60 fps")
	ws.mouse_override = Vector2i(400, 700)
	await process_frame
	eq(ws.get_window_rect().position, Vector2i(300, 864 - 300), "janela acompanha o mouse (+300,-300)")
	ws.mouse_override = Vector2i(-9000, 700)   # tenta jogar para fora
	await process_frame
	eq(ws.get_window_rect().position.x, -688 + 96, "arrasto para fora: sobram 96 px visíveis")
	ws.mouse_override = Vector2i(900, 100)
	await process_frame
	press(false)
	await process_frame
	await process_frame
	ok(not ws.is_dragging(), "soltar o botão termina o arrasto")
	var rr: Rect2i = ws.get_window_rect()
	ok(Rect2i(0, 0, 1920, 1040).encloses(rr), "ao soltar, assenta inteira dentro da área útil %s" % str(rr))
	var saved: Dictionary = settings.get_value("window_pos")
	ok(saved.has("1920x1080@0,0") and saved.has("_last"), "posição salva por monitor")
	# gaveta no topo da tela: cresce o que dá e empurra para dentro
	ws.set_drawer(true)
	ok(Rect2i(0, 0, 1920, 1040).encloses(ws.get_window_rect()), "gaveta aberta continua dentro da tela")
	ws.set_drawer(false)
	eq(ws.get_window_rect(), rr, "fechar a gaveta volta para onde estava (âncora preservada)")

	# ------------------------------------------------------------------ reset
	ws.reset_position()
	eq(ws.get_window_rect(), Rect2i(0, 864, 688, 176), "reset_position: rodapé do principal")
	eq(settings.get_value("window_pos")["1920x1080@0,0"], {"x": 0, "y": 0}, "reset regrava a posição")

	# ------------------------------------------------------------------ posição salva é restaurada
	var d: Dictionary = {"1920x1080@0,0": {"x": 300, "y": 0}, "_last": "1920x1080@0,0"}
	settings.set_value("window_pos", d)
	var ws2: Node = make_ws(hd)
	eq(ws2.get_window_rect(), Rect2i(300, 864, 688, 176), "posição salva válida é usada")
	ws2.free()
	# posição salva ao lado: o rodapé a 120 px do fundo
	settings.set_value("window_pos", {"1920x1080@0,0": {"x": 50, "y": 120}, "_last": "1920x1080@0,0"})
	ws2 = make_ws(hd)
	eq(ws2.get_window_rect(), Rect2i(50, 864 - 120, 688, 176), "y salvo = distância do rodapé")
	ws2.free()

	# ------------------------------------------------------------------ posição salva inválida -> reset
	settings.set_value("window_pos", {"1920x1080@0,0": {"x": 9000, "y": 0}, "_last": "1920x1080@0,0"})
	ws2 = make_ws(hd)
	eq(ws2.get_window_rect(), Rect2i(0, 864, 688, 176), "fora de todos os monitores -> reset ao rodapé")
	eq(settings.get_value("window_pos")["1920x1080@0,0"], {"x": 0, "y": 0}, "posição ruim foi regravada")
	ws2.free()
	settings.set_value("window_pos", {"1920x1080@0,0": {"x": "abc", "y": null}, "_last": "1920x1080@0,0"})
	ws2 = make_ws(hd)
	eq(ws2.get_window_rect(), Rect2i(0, 864, 688, 176), "entrada corrompida -> rodapé")
	ws2.free()
	settings.set_value("window_pos", {"1920x1080@0,0": {"x": 0, "y": 5000}, "_last": "1920x1080@0,0"})
	ws2 = make_ws(hd)
	eq(ws2.get_window_rect(), Rect2i(0, 864, 688, 176), "y absurdo (janela acima da tela) -> reset")
	ws2.free()

	# ------------------------------------------------------------------ dois monitores
	var two: Array = [mon(Rect2i(0, 0, 1920, 1080)), mon(Rect2i(1920, 0, 3840, 2160))]
	settings.set_value("window_pos", {"3840x2160@1920,0": {"x": 100, "y": 0}, "_last": "3840x2160@1920,0"})
	ws2 = make_ws(two)
	eq(ws2.ui_scale, 4, "no monitor 4K a escala auto é 4")
	eq(ws2.get_window_rect(), Rect2i(2020, 2120 - 352, 1376, 352), "restaura no 2º monitor, escala 4")
	# o 2º monitor some: a posição salva não cruza mais nada -> principal
	ws2.screens_override = [two[0]]
	ws2._sync_with_system()
	eq(ws2.get_window_rect(), Rect2i(0, 864, 688, 176), "monitor desconectado -> volta ao rodapé do principal, escala 2")
	eq(ws2.ui_scale, 2, "escala recalculada pelo novo monitor")
	# e volta
	ws2.screens_override = two
	ws2._sync_with_system()
	eq(ws2.get_window_rect(), Rect2i(0, 864, 688, 176), "monitor reconectado: continua no principal")
	# arrastar do monitor 1080p para o 4K: escala muda ao soltar
	ws2.mouse_override = Vector2i(10, 1000)
	press(true)
	await process_frame
	ws2.start_drag()
	ws2.mouse_override = Vector2i(10 + 2200, 1000 - 400)
	await process_frame
	press(false)
	await process_frame
	await process_frame
	ok(not ws2.is_dragging(), "arrasto entre monitores terminou")
	eq(ws2.ui_scale, 4, "soltou no 4K: escala 4")
	ok(Rect2i(1920, 0, 3840, 2120).encloses(ws2.get_window_rect()), "inteira no 2º monitor")
	var sv2: Dictionary = settings.get_value("window_pos")
	eq(sv2["_last"], "3840x2160@1920,0", "último monitor lembrado")
	ws2.free()

	# monitor principal não é o primeiro da lista e tem a barra em cima (usable deslocada)
	var odd: Array = [mon(Rect2i(-1920, 0, 1920, 1080)), {"full": Rect2i(0, 0, 2560, 1440), "usable": Rect2i(0, 40, 2560, 1400)}]
	settings.reset_all()
	ws2 = make_ws(odd, 1)
	eq(ws2.get_window_rect(), Rect2i(0, 1440 - 176, 688, 176), "principal = índice 1, área útil sem a barra de cima")
	eq(ws2.ui_scale, 2, "1440p -> 2")
	ws2.free()

	# tela pequena: 1366x768 -> escala 1, gaveta cabe
	var lap: Array = [mon(Rect2i(0, 0, 1366, 768))]
	ws2 = make_ws(lap)
	eq(ws2.ui_scale, 1, "notebook 768p: escala 1")
	ws2.set_ui_scale(4)
	eq(ws2.ui_scale, 3, "escala 4 pedida não cabe numa tela 768p com gaveta fechada? (88*4=352 cabe; largura 344*4=1376>1366) -> 3")
	ws2.free()
	settings.reset_all()

	# ------------------------------------------------------------------ governador de FPS
	ws = ws  # instância 1080p
	ws.note_activity()
	ws._hover = false
	ws._set_focus(true)
	ws._update_fps(true)
	eq(ws.current_fps(), 30, "foco + input recente: 30")
	ws._last_activity_ms = Time.get_ticks_msec() - 11000
	ws._update_fps()
	eq(ws.current_fps(), 12, "sem input há 11 s: 12")
	ws.note_activity()
	eq(ws.current_fps(), 30, "note_activity volta a 30")
	eq(Engine.max_fps, 30, "Engine.max_fps aplicado")
	var focus_log: Array = []
	ws.focus_changed.connect(func(f: bool) -> void: focus_log.append(f))
	ws._set_focus(false)
	eq(ws.current_fps(), 8, "sem foco e sem hover: 8")
	eq(Engine.max_fps, 8, "Engine.max_fps 8")
	ws._on_mouse_entered()
	eq(ws.current_fps(), 30, "hover sem foco: 30")
	ws._on_mouse_exited()
	eq(ws.current_fps(), 8, "saiu o mouse: 8")
	ws._set_focus(true)
	eq(focus_log, [false, true], "focus_changed")
	ws._set_focus(true)
	eq(focus_log, [false, true], "focus_changed sem repetir")
	settings.set_value("energy_mode", "low")
	ws._last_activity_ms = Time.get_ticks_msec() - 60000
	ws._update_fps()
	eq(ws.current_fps(), 2, "energy_mode=low: 2")
	settings.set_value("energy_mode", "normal")
	eq(ws.current_fps(), 12, "energy_mode=normal, ocioso: 12")
	settings.set_value("energy_mode", "auto")
	ws.set_collapsed(true)
	eq(ws.current_fps(), 2, "recolhido: 2")
	ws._on_mouse_entered()
	eq(ws.current_fps(), 12, "recolhido + hover: 12")
	ws._on_mouse_exited()
	ws.set_collapsed(false)

	# ------------------------------------------------------------------ primeira interação
	var fi: Array = []
	ws._interacted = false
	ws.first_interaction.connect(func() -> void: fi.append(1))
	eq(settings.get_value("sound_unlocked"), false, "som ainda não liberado")
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	ws._input(mm)
	eq(fi.size(), 0, "mover o mouse não conta como interação")
	var kp: InputEventKey = InputEventKey.new()
	kp.pressed = true
	kp.keycode = KEY_A
	ws._input(kp)
	ws._input(kp)
	eq(fi.size(), 1, "primeira tecla emite first_interaction uma vez")
	eq(settings.get_value("sound_unlocked"), true, "sound_unlocked = true")
	ws.mouse_override = null

	# ------------------------------------------------------------------ bandeja: textos com fallback
	eq(ws.tr_tray("ui.tray_show"), "Show", "fallback em inglês (I18n stub ou sem a chave)")
	eq(ws.tr_tray("ui.tray_quit"), "Quit", "fallback quit")
	eq(ws.tr_tray("ui.tray_inexistente"), "ui.tray_inexistente", "chave desconhecida: devolve a chave")
	ok(ws.get_node_or_null("Tray") == null, "sem bandeja em --headless / Linux")

	# ------------------------------------------------------------------ CSV tem as 5 chaves
	var f: FileAccess = FileAccess.open("res://data/i18n/strings_platform.csv", FileAccess.READ)
	ok(f != null, "strings_platform.csv existe")
	if f != null:
		var header: PackedStringArray = f.get_csv_line()
		eq(header, PackedStringArray(["key", "pt_BR", "en"]), "cabeçalho key,pt_BR,en")
		var keys: Array = []
		while not f.eof_reached():
			var row: PackedStringArray = f.get_csv_line()
			if row.size() == 3 and row[0] != "":
				keys.append(row[0])
				ok(row[1] != "" and row[2] != "", "linha completa: " + row[0])
		for k in ["ui.tray_show", "ui.tray_collapse", "ui.tray_reset", "ui.tray_top", "ui.tray_quit"]:
			ok(keys.has(k), "chave " + k)

	# ------------------------------------------------------------------ API existente no autoload real
	var real: Node = root.get_node_or_null("WindowService")
	ok(real != null, "autoload WindowService presente")
	if real != null:
		for m in ["set_logical_size", "set_drawer", "start_drag", "is_dragging", "set_always_on_top", "set_collapsed", "is_collapsed", "reset_position", "set_ui_scale", "note_activity", "quit_game"]:
			ok(real.has_method(m), "método " + m)
		for sg in ["layout_changed", "hidden_changed", "focus_changed"]:
			ok(real.has_signal(sg), "sinal " + sg)
		ok("logical_size" in real and "ui_scale" in real, "propriedades logical_size/ui_scale")

	ws.free()
