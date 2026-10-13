extends SceneTree
## Run completa de ponta a ponta com a cena real (xvfb + opengl3): bot joga até a antena 5, compra a casa dela,
## espera a chegada, passa a cena do final e confere o epílogo. Salva capturas em OUT_DIR.
## xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/e2e_full_run.gd

const Bot := preload("res://tests/sim_bot.gd")
var out_dir: String = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "user://shots"
var fails: int = 0

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	await _frames(10)
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])

func _check(c: bool, msg: String) -> void:
	print(("  ok   " if c else "  FALHOU: ") + msg)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game: Node = root.get_node("/root/Game")
	game.delete_save()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	game.new_game()
	main.call("_on_game_started", true)
	await _frames(10)
	var bot = Bot.new(game.sim)
	bot.run(40.0, 5)
	game.state_changed.emit()
	await _frames(20)
	_check(game.antenna() == 5, "antena 5 no dia %.1f" % (game.sim.t_min / 1440.0))
	await _shot("e2e_1_antena5")
	# casa dela: tenta comprar o que faltar a cada dia (a sucata chega com o tempo)
	var flags := {"arrival": false}
	game.arrival_started.connect(func() -> void: flags["arrival"] = true)
	for d in 40:
		if game.can_buy("mesinha")["ok"]:
			var mh: Array = game.placement_hints("mesinha")
			if not mh.is_empty():
				game.buy("mesinha", int(mh[0]["room"]), int(mh[0]["col"]))
		for h in game.house_status():
			var item: String = h["item"]
			if bool(h["bought"]):
				continue
			var hints: Array = game.placement_hints(item)
			if hints.is_empty():
				game.buy(item, 0, -1)
			else:
				for p in hints:
					if bool(game.buy(item, int(p["room"]), int(p["col"]))["ok"]):
						break
		game.debug_advance_minutes(1440.0)
		await _frames(2)
		if flags["arrival"] or game.arrived():
			break
	var left: Array = []
	for h in game.house_status():
		if not bool(h["bought"]):
			left.append(h["item"])
	print("  casa: faltam ", left, " jornada ", game.journey())
	_check(flags["arrival"] or game.arrived(), "chegada disparou (dias %.1f)" % (game.sim.t_min / 1440.0))
	await _shot("e2e_2_arrival_start")
	# deixa a cena do final rodar (acelerada)
	var bunker: Node = main.get("_bunker")
	bunker.set("cinematic_speed", 8.0)
	for i in 900:
		await process_frame
		if main.get("_ending") != null:
			break
	_check(main.get("_ending") != null, "tela do final apareceu")
	await _shot("e2e_3_ending")
	var ending: Node = main.get("_ending")
	if ending != null:
		for i in 40:
			ending.call("skip_to_end")
			await _frames(3)
	await _shot("e2e_4_ending_end")
	for i in 3:
		var e: Node = main.get("_ending")
		if e != null:
			e.emit_signal("finished", "arrival" if i == 0 else "next_day")
			await _frames(5)
	await _frames(30)
	_check(game.arrived(), "modo epílogo (arrived)")
	_check(main.get("_ending") == null, "final fechado")
	game.debug_advance_minutes(1440.0 * 2)
	await _frames(20)
	await _shot("e2e_5_epilogue")
	_check(game.diary().size() > 10, "diário com %d entradas" % game.diary().size())
	print("e2e_full_run: ", "OK" if fails == 0 else "%d falhas" % fails)
	quit(fails)
