extends SceneTree
## Cômodos na faixa (placas, paredes), botão X da janela (pergunta "Sair?" antes de fechar) e a barra de cima
## sem a linha de progresso. Captura PNGs em OUT_DIR.
## Uso: OUT_DIR=<pasta> xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/comodos.gd

var out_dir: String = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "user://shots"
var fails: int = 0
var main: Node
var game: Node
var bunker: BunkerView
var quits: int = 0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1


func _shot(name: String) -> void:
	await _frames(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.get_texture().get_image().save_png("%s/comodos_%s.png" % [out_dir, name])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var st: Node = root.get_node("/root/Settings")
	st.set_value("intro_seen", true)
	st.set_value("tutorial", {})
	st.set_value("room_plates", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(10)
	game = root.get_node("/root/Game")
	game.new_game()
	main.call("_on_game_started", true)
	await _frames(20)
	var guard := 0
	while not game.is_awake() and guard < 100:
		game.debug_advance_minutes(30.0)
		guard += 1
	await _frames(10)
	bunker = main.get("_bunker")
	var hud: StatusHud = main.get("_hud")
	var handle: WindowHandle = main.get("_handle")

	print("== placas")
	var names: Array[String] = []
	for p: Dictionary in bunker.plates().plates():
		names.append(String(p["text"]))
	_check(names == ["Escotilha", "Horta", "Oficina", "Quarto", "Despensa"], "placas: %s" % str(names))
	_check(bunker.plates().is_on(), "placas ligadas por padrão")
	st.set_value("room_plates", false)
	await _frames(3)
	_check(not bunker.plates().is_on(), "Opções desligam as placas")
	st.set_value("room_plates", true)
	await _frames(3)
	_check(bunker.plates().is_on(), "e ligam de novo")

	print("== o que está em cada cômodo")
	var in_horta := 0
	var horta: Dictionary = {}
	for z: Dictionary in BunkerGeo.zones(1):
		if String(z["fn"]) == "horta":
			horta = z
	for it in game.instances():
		if String(it["item"]) == "vaso":
			var o: BunkerObject = bunker.object_by_id(int(it["id"]))
			if o != null and o.position.x >= float(horta["x0"]) and o.position.x < float(horta["x1"]):
				in_horta += 1
	_check(in_horta == 3, "os 3 vasos do começo estão na horta (%d)" % in_horta)
	var bike: BunkerObject = bunker.find_item("bicicleta")
	var oficina: Dictionary = {}
	for z: Dictionary in BunkerGeo.zones(1):
		if String(z["fn"]) == "oficina":
			oficina = z
	_check(bike != null and bike.position.x >= float(oficina["x0"]) and bike.position.x < float(oficina["x1"]), "a bicicleta está na oficina")
	var bed_foot: Variant = bunker.fixed_foot("bed")
	var quarto: Dictionary = {}
	for z: Dictionary in BunkerGeo.zones(1):
		if String(z["fn"]) == "quarto":
			quarto = z
	_check(bed_foot != null and (bed_foot as Vector2).x >= float(quarto["x0"]) and (bed_foot as Vector2).x < float(quarto["x1"]), "a cama está no quarto")

	print("== câmera acompanha ele de um cômodo a outro")
	bunker.man.cinematic = true
	bunker.man.position.x = float(oficina["x0"]) + 40.0
	bunker._pan_pause = 0.0
	var ok: bool = false
	for i in 300:
		await process_frame
		if absf(bunker.scroll_x - bunker.follow_target_x()) < 1.0 and bunker.scroll_x > 0.0:
			ok = true
			break
	_check(ok, "a vista anda para a direita junto com ele (%d)" % int(bunker.scroll_x))
	var rel: float = bunker.man.position.x - bunker.scroll_x
	_check(rel >= 0.0 and rel <= float(bunker.view_width), "ele fica dentro da janela (x %d)" % int(rel))
	await _shot("1_oficina")

	print("== barra de cima sem a linha de progresso")
	_check(hud.get("_bar") == null, "sem barra de progresso na barra de cima")

	print("== botão X")
	var close_btn: Button = handle.get("_close_btn")
	_check(close_btn != null and close_btn.is_visible_in_tree(), "o X aparece na alça")
	for c in handle.quit_requested.get_connections():
		handle.quit_requested.disconnect(c["callable"])
	handle.quit_requested.connect(func() -> void: quits += 1)
	close_btn.pressed.emit()
	await _frames(2)
	_check(handle.is_asking_quit() and quits == 0, "1º clique só pergunta 'Sair?' (%s)" % close_btn.text)
	await _shot("2_sair")
	handle._process(3.5)
	_check(not handle.is_asking_quit() and close_btn.text == "", "sem resposta, a pergunta some")
	close_btn.pressed.emit()
	close_btn.pressed.emit()
	await _frames(2)
	_check(quits == 1 and not handle.is_asking_quit(), "2º clique fecha (pede para sair uma vez)")
	_check(handle.position.x + handle.size.x <= float(BunkerGeo.WIN_W) + 0.5, "a alça fica dentro da janela (%s)" % str(handle.position))

	print("RESULTADO: %d FALHAS" % fails)
	quit(1 if fails > 0 else 0)
