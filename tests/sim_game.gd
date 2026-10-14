extends SceneTree
## Autoload Game: ciclo de vida, save/load, catch-up offline, throttle de state_changed, linha de comando.
## godot --headless --path . --script res://tests/sim_game.gd [-- --demo | --time-scale=3]
var fails := 0
var ev: Array[String] = []


func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	await process_frame
	var g: Node = root.get_node_or_null("Game")
	check(g != null, "autoload Game existe")
	if g == null:
		quit(1)
		return
	var args: Array = Array(OS.get_cmdline_user_args()) + Array(OS.get_cmdline_args())
	if "--demo" in args:
		check(is_equal_approx(g.time_scale, 6.0), "--demo => time_scale 6")
	elif args.any(func(a: Variant) -> bool: return String(a).begins_with("--time-scale=")):
		check(is_equal_approx(g.time_scale, 3.0), "--time-scale=3 => %s" % str(g.time_scale))
	else:
		check(is_equal_approx(g.time_scale, 1.0), "padrão time_scale 1")
		_main(g)
	print("RESULTADO: %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(0 if fails == 0 else 1)


func _main(g: Node) -> void:
	var path := "user://game_test_save.json"
	g.save_path = path
	g.delete_save()
	check(not g.has_save(), "sem save no início")
	check(not g.load_game(), "load_game sem save devolve false")
	g.state_changed.connect(func() -> void: ev.append("state"))
	g.new_game_started.connect(func() -> void: ev.append("new"))
	g.game_loaded.connect(func() -> void: ev.append("loaded"))
	g.welcome_back.connect(func(s: Dictionary) -> void: ev.append("welcome:%d" % int(s["hours"])))
	g.radio_line.connect(func(_d: Dictionary) -> void: ev.append("radio"))
	g.new_game()
	check(g.in_game and "new" in ev, "new_game: in_game e sinal")
	check(g.instances().size() == 4 and g.sucata() == 6 and g.antenna() == 1, "estado inicial pela API do Game")
	check(g.catalog("plantio").size() == 4 and g.catalog("escavacao").size() == 2, "catalog filtrado")
	check(g.plots().size() == 3 and g.fixed_objects(1).size() == 4, "plots/fixos")
	check(g.journey()["items_total"] == 6 and g.house_status().size() == 6, "journey/house_status")
	check(g.is_awake() == (not g.is_night()), "is_awake/is_night coerentes")

	print("== throttle de state_changed (máx 4/s)")
	ev.clear()
	g.set_time_scale(6000.0)  # 100 min de jogo por segundo real
	for i in 20:
		g._process(0.1)  # 2 s de relógio de parede simulado
	var n_state := ev.count("state")
	check(n_state >= 1 and n_state <= 9, "state_changed %d vezes em 2 s simulados" % n_state)
	g.set_time_scale(1.0)
	check(g.stats()["time_min"] > 100.0, "relógio andou (%.0f min de jogo)" % g.stats()["time_min"])

	print("== autosave e perda de foco")
	g.buy("vaso", 1, 7)  # sem sucata: falha, só para exercitar
	g.save_game()
	check(g.has_save(), "save_game escreve")
	var ss: Dictionary = g.save_summary()
	check(ss.get("antenna", 0) == 1 and ss.get("day", 0) >= 1, "save_summary: " + str(ss))
	var before := FileAccess.get_modified_time(path)
	OS.delay_msec(1100)
	g.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(FileAccess.get_modified_time(path) > before, "perda de foco salva")
	g._save_timer = 59.95
	var m0 := FileAccess.get_modified_time(path)
	OS.delay_msec(1100)
	g._process(0.1)
	check(FileAccess.get_modified_time(path) > m0, "autosave aos 60 s")

	print("== carregar após 10 h fora")
	# hora do dia fixa (9 h): senão o resultado dependia do relógio da máquina (visitas só em certos horários)
	g.sim.start_min = fposmod(9.0 * 60.0 - g.sim.t_min - g.sim._acc, 1440.0)
	var snap: Dictionary = g.sim.to_dict()
	g.save_game()
	var txt := FileAccess.get_file_as_string(path)
	var doc: Dictionary = JSON.parse_string(txt)
	doc["saved_unix"] = Time.get_unix_time_from_system() - 10.0 * 3600.0
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "", true, true))
	f.close()
	g.sim.new_game(99, 3.0)  # bagunça o estado para provar que o load restaura
	ev.clear()
	check(g.load_game(), "load_game ok")
	var i_loaded := ev.find("loaded")
	var i_wb := ev.find("welcome:10")
	check(i_loaded >= 0 and i_wb > i_loaded, "game_loaded vem antes de welcome_back(10 h): " + str(ev))
	check(not ev.has("radio"), "falas perdidas não disparam radio_line (vão para o diário)")
	check(g.stats()["time_min"] > float(snap["t_min"]) + 9.0 * 60.0, "10 h simuladas (t %.0f -> %.0f)" % [float(snap["t_min"]), g.stats()["time_min"]])
	var has_away := false
	for e in g.diary():
		has_away = has_away or e["kind"] == "away"
	check(has_away, "diário tem entrada away")
	check(g.sucata() > 0, "sucata acumulou offline (%d)" % g.sucata())

	print("== suspensão do PC (salto grande do relógio de parede)")
	ev.clear()
	g._last_unix = Time.get_unix_time_from_system() - 5.0 * 3600.0
	g._process(0.016)
	check(ev.any(func(x: String) -> bool: return x.begins_with("welcome:")), "gap de 5 h cai no catch-up: " + str(ev))
	g._last_unix = Time.get_unix_time_from_system() + 3600.0  # relógio voltou no tempo
	var t_before: float = g.stats()["time_min"]
	g._process(0.016)
	check(g.stats()["time_min"] - t_before < 1.0, "relógio para trás é ignorado")

	print("== chegada pendente é reemitida ao carregar")
	g.sim._arrival = "pending"
	g.save_game()
	ev.clear()
	var got := [0]
	g.arrival_started.connect(func() -> void: got[0] += 1)
	check(g.load_game() and got[0] == 1, "arrival_started reemitido")
	g.finish_arrival()
	check(g.arrived(), "finish_arrival via Game")
	g.delete_save()
	check(not g.has_save(), "delete_save")
