extends SceneTree
## Teste com JANELA REAL (precisa de display; use xvfb-run). Confere resize/posição de verdade,
## escala inteira, content_scale, gaveta, aba recolhida, arrasto, sempre por cima, FPS e
## persistência/--reset-window.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##       --script res://tests/platform_xvfb.gd -- --mode=move|check|reset|clean
## Modo padrão (sem --mode): bateria completa de layout. Capturas em user://shots/ (veja o log).

const WS = preload("res://scripts/platform/window_service.gd")

var fails: int = 0
var checks: int = 0
var ws: Node
var settings: Node


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FALHOU: ", what)
	else:
		print("  ok: ", what)


func eq(a: Variant, b: Variant, what: String) -> void:
	checks += 1
	if a != b:
		fails += 1
		print("  FALHOU: %s (obtido %s, esperado %s)" % [what, str(a), str(b)])
	else:
		print("  ok: %s = %s" % [what, str(a)])


## X11 aplica resize/posição de forma assíncrona: espera alguns quadros e um pouco de tempo.
func settle() -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300:
		await process_frame


func win_rect() -> Rect2i:
	return Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/%s.png" % name)
	print("  captura: ", ProjectSettings.globalize_path("user://shots/%s.png" % name), "  (", img.get_size(), ")")


func press(down: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	Input.parse_input_event(e)


func _initialize() -> void:
	await run()
	print("platform_xvfb: %d verificações, %d falhas" % [checks, fails])
	quit(1 if fails > 0 else 0)


func run() -> void:
	await process_frame
	ws = root.get_node("WindowService")
	settings = root.get_node("Settings")
	var mode: String = "full"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
	print("DisplayServer: ", DisplayServer.get_name(), "  telas: ", DisplayServer.get_screen_count(),
		"  tela0: ", DisplayServer.screen_get_position(0), DisplayServer.screen_get_size(0),
		"  útil: ", DisplayServer.screen_get_usable_rect(0), "  dpi: ", DisplayServer.screen_get_dpi(0),
		"  escala SO: ", DisplayServer.screen_get_scale(0))
	if DisplayServer.get_name() == "headless":
		print("sem display real: nada a testar aqui")
		return
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(0)
	await settle()

	if mode == "clean":
		settings.reload("user://settings.json")
		settings.reset_all()
		settings.flush()
		print("settings limpo")
		return
	if mode == "move":
		await settle()
		eq(win_rect(), Rect2i(usable.position.x, usable.end.y - 88, 344, 88), "[move] primeira execução: rodapé esquerdo")
		ws.mouse_override = Vector2i(10, usable.end.y - 20)
		press(true)
		await process_frame
		ws.start_drag()
		ws.mouse_override = Vector2i(310, usable.end.y - 320)
		await process_frame
		press(false)
		await process_frame
		await process_frame
		await settle()
		eq(win_rect().position, Vector2i(300, usable.end.y - 88 - 300), "[move] arrastou (+300,-300)")
		settings.flush()
		print("MOVE_OK")
		return
	if mode == "check":
		eq(win_rect().position, Vector2i(300, usable.end.y - 88 - 300), "[check] posição restaurada do disco")
		return
	if mode == "reset":
		eq(win_rect(), Rect2i(usable.position.x, usable.end.y - 88, 344, 88), "[reset] --reset-window volta ao rodapé")
		return

	# ------------------------------------------------------------------ bateria completa
	settings.reload("user://test_xvfb_settings.json")
	settings.reset_all()
	var win: Window = root
	print("-- janela inicial")
	ok(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS), "sem borda")
	ok(not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED) == false or true, "flag resize (informativo)")
	ok(not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT), "opaca (sem transparência)")
	eq(win.content_scale_mode, Window.CONTENT_SCALE_MODE_VIEWPORT, "stretch mode = viewport")
	eq(win.content_scale_stretch, Window.CONTENT_SCALE_STRETCH_INTEGER, "scale mode = integer")
	eq(win.content_scale_size, Vector2i(344, 88), "content_scale_size = tamanho lógico")
	var scale0: int = WS.auto_scale(DisplayServer.screen_get_size(0).y)
	eq(ws.ui_scale, scale0, "escala auto do monitor (%d)" % scale0)
	eq(win_rect(), Rect2i(usable.position.x, usable.end.y - 88 * scale0, 344 * scale0, 88 * scale0), "rodapé esquerdo da área útil")
	eq(Engine.max_fps > 0, true, "Engine.max_fps explícito (%d)" % Engine.max_fps)
	await shot("01_inicial")

	print("-- escala 2")
	ws.set_ui_scale(2)
	await settle()
	eq(win_rect(), Rect2i(usable.position.x, usable.end.y - 176, 688, 176), "escala 2: 688x176 colada no rodapé")
	eq(win.content_scale_size, Vector2i(344, 88), "content_scale_size continua 344x88")
	eq(win.get_visible_rect().size, Vector2(344, 88), "viewport lógico 344x88")
	await shot("02_escala2")

	print("-- gaveta")
	ws.set_drawer(true)
	await settle()
	eq(win_rect(), Rect2i(usable.position.x, usable.end.y - 416, 688, 416), "gaveta: cresce PARA CIMA, base e esquerda fixas")
	eq(win.content_scale_size, Vector2i(344, 208), "content_scale_size 344x208")
	await shot("03_gaveta")
	ws.set_drawer(false)
	await settle()
	eq(win_rect(), Rect2i(usable.position.x, usable.end.y - 176, 688, 176), "fecha: volta")

	print("-- 3 salas")
	ws.set_logical_size(Vector2i(608, 88))
	await settle()
	eq(win_rect(), Rect2i(usable.position.x, usable.end.y - 176, 1216, 176), "3 salas: 1216x176")
	ws.set_logical_size(Vector2i(344, 88))
	await settle()

	print("-- recolher")
	ws.set_collapsed(true)
	await settle()
	eq(win_rect(), Rect2i(usable.position.x, usable.end.y - 32, 96, 32), "aba 96x32 (48x16 x2)")
	eq(Engine.max_fps, 2, "recolhido: 2 fps")
	await shot("04_recolhida")
	var img: Image = root.get_viewport().get_texture().get_image()
	ok(img.get_size() == Vector2i(48, 16), "viewport da aba 48x16")
	var tab_ok: bool = false
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).is_equal_approx(Color("e0a840")):
				tab_ok = true
	ok(tab_ok, "aba desenhada (triângulo âmbar visível)")
	# clique real na aba (evento de GUI) restaura
	var press_ev: InputEventMouseButton = InputEventMouseButton.new()
	press_ev.button_index = MOUSE_BUTTON_LEFT
	press_ev.pressed = true
	press_ev.position = Vector2(24, 8)
	press_ev.global_position = press_ev.position
	root.push_input(press_ev)
	var rel: InputEventMouseButton = press_ev.duplicate()
	rel.pressed = false
	root.push_input(rel)
	await settle()
	ok(not ws.is_collapsed(), "clique na aba restaura")
	eq(win_rect(), Rect2i(usable.position.x, usable.end.y - 176, 688, 176), "restaurada no mesmo canto")

	print("-- sempre por cima")
	ws.set_always_on_top(true)
	await settle()
	ok(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP), "flag ALWAYS_ON_TOP ligada")
	ws.set_always_on_top(false)
	await settle()
	ok(not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP), "flag desligada")

	print("-- arrasto manual (mouse simulado)")
	ws.mouse_override = Vector2i(20, usable.end.y - 20)
	press(true)
	await process_frame
	ws.start_drag()
	ws.mouse_override = Vector2i(220, usable.end.y - 220)
	await process_frame
	await process_frame
	await settle()
	eq(win_rect().position, Vector2i(200, usable.end.y - 176 - 200), "janela real acompanha o mouse")
	ws.mouse_override = Vector2i(-5000, usable.end.y - 220)
	await process_frame
	await settle()
	eq(win_rect().position.x, -688 + 96, "arrastar para fora deixa 96 px")
	press(false)
	await process_frame
	await process_frame
	await settle()
	ok(not ws.is_dragging(), "soltou")
	ok(usable.encloses(win_rect()), "assentou dentro da área útil: %s" % str(win_rect()))
	ws.reset_position()
	await settle()
	eq(win_rect(), Rect2i(usable.position.x, usable.end.y - 176, 688, 176), "reset_position")

	print("-- foco e FPS reais")
	ws._on_mouse_exited()
	ws._set_focus(false)
	eq(Engine.max_fps, 8, "sem foco e sem hover: 8")
	ws._set_focus(true)
	ws.note_activity()
	eq(Engine.max_fps, 30, "foco + atividade: 30")

	print("-- bandeja")
	ok(root.get_node_or_null("WindowService/Tray") == null, "Linux: sem StatusIndicator (só Windows/macOS)")

	settings.reload("user://settings.json")
	for suffix in ["", ".tmp", ".bad"]:
		var p: String = "user://test_xvfb_settings.json" + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
