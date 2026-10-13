extends SceneTree
## Captura uma obra em andamento: porcentagem sobre o andaime e etiqueta com o tempo que falta.
## Uso: OUT_DIR=<pasta> xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/shot_obra.gd

var out_dir: String = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "user://shots"
var fails: int = 0

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var st: Node = root.get_node("/root/Settings")
	st.set_value("intro_seen", true)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(10)
	var game: Node = root.get_node("/root/Game")
	game.new_game()
	main.call("_on_game_started", true)
	await _frames(20)
	var guard := 0
	while not game.is_awake() and guard < 100:
		game.debug_advance_minutes(30.0)
		guard += 1
	var r: Dictionary = game.buy("vaso", 1, 7)
	_check(bool(r["ok"]), "comprou o vaso")
	game.debug_advance_minutes(3.0)
	await _frames(30)
	var bunker: Node2D = main.get("_bunker")
	var o: BunkerObject = bunker.call("object_by_id", int(r["instance_id"]))
	_check(o != null and o.building, "obra em andamento")
	var c: Vector2 = o.bounds().get_center()
	root.warp_mouse(bunker.to_global(c))
	await _frames(30)
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	img.save_png("%s/obra_hover.png" % out_dir)
	var tip: PlotTip = bunker.get("_tip")
	_check(tip.get("_tip_lines").size() >= 2, "etiqueta da obra (%s)" % str(tip.get("_tip_lines")))
	# clicar na obra ajuda a martelar (clique real, com a gaveta fechada)
	var before: float = float(game.active_jobs()[0]["ratio"])
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = bunker.to_global(c)
		ev.global_position = ev.position
		root.push_input(ev)
		await _frames(3)
	var after: float = float(game.active_jobs()[0]["ratio"])
	_check(after > before, "clique na obra adianta (%.2f -> %.2f)" % [before, after])
	# com a gaveta ABERTA (onde se compra) o clique na obra também ajuda e a barra da gaveta anda
	var drawer: Node = main.get("_drawer")
	drawer.call("open", "build")
	await _frames(20)
	var ov: DrawerPlacementOverlay = drawer.get("_overlay")
	var idx := -1
	for i in ov._rects().size():
		if int(ov.targets[i]["id"]) == int(r["instance_id"]):
			idx = i
	if idx < 0:
		drawer.call("select_instance", int(r["instance_id"]))
		await _frames(5)
		for i in ov._rects().size():
			if int(ov.targets[i]["id"]) == int(r["instance_id"]):
				idx = i
	_check(idx >= 0, "obra aparece como alvo da gaveta")
	var b4: float = float(game.active_jobs()[0]["ratio"]) if not game.active_jobs().is_empty() else 1.0
	ov.pick(idx)
	await _frames(5)
	var a4: float = float(game.active_jobs()[0]["ratio"]) if not game.active_jobs().is_empty() else 1.0
	_check(a4 > b4, "clique na obra com a gaveta aberta adianta (%.2f -> %.2f)" % [b4, a4])
	print("RESULTADO: %d FALHAS" % fails)
	quit(1 if fails > 0 else 0)
