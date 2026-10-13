extends SceneTree
## Cliques são ordens: o homem vai até o alvo e só então a ajuda vale (regar, martelar, levar à caixa).
## Uso: xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/orders.gd

var fails: int = 0

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1

func _until(cond: Callable, max_frames: int = 1500) -> bool:
	var n := 0
	while not cond.call() and n < max_frames:
		await process_frame
		n += 1
	return cond.call()

func _initialize() -> void:
	_run.call_deferred()

func _progress_of(game: Node, inst: int) -> float:
	var best := 0.0
	for p: Dictionary in game.plots():
		if int(p["instance"]) == inst:
			best = maxf(best, float(p["progress"]))
	return best

func _run() -> void:
	root.get_node("/root/Settings").set_value("intro_seen", true)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(10)
	var game: Node = root.get_node("/root/Game")
	game.new_game()
	game.sim.new_game(7, 9.0)   # 9h da manhã: acordado e com o dia pela frente
	main.call("_on_game_started", true)
	await _frames(20)
	var bunker: BunkerView = main.get("_bunker")
	var man: BunkerMan = bunker.man
	Engine.time_scale = 6.0
	var pots: Array = game.instances().filter(func(i: Dictionary) -> bool: return String(i["item"]) == "vaso")
	var pot: int = int(pots[0]["id"])

	# 1) clique num vaso: vira ordem, nada acontece na hora
	var p0: float = _progress_of(game, pot)
	var why: String = bunker.give_order("instance", pot)
	_check(why == "" and bunker.orders.size() == 1, "clique no vaso vira ordem (%s)" % why)
	_check(is_equal_approx(_progress_of(game, pot), p0), "a planta não cresce na hora")
	_check(String(bunker.orders[0]["kind"]) == "tend", "ordem do vaso é cuidar")
	var ok1: bool = await _until(func() -> bool: return bunker.orders.is_empty())
	_check(ok1, "ele cumpre a ordem")
	_check(_progress_of(game, pot) > p0, "e só então a planta cresce (%.2f -> %.2f)" % [p0, _progress_of(game, pot)])

	# 1b) com a gaveta aberta o clique no vaso também vira ordem; ao cumprir sai o "+N%" em cima dele
	var drawer: Node = main.get("_drawer")
	drawer.call("open", "build")
	await _frames(10)
	drawer.call("_on_instance_picked", pot)
	await _frames(3)
	_check(bunker.orders.size() == 1 and String(bunker.orders[0]["kind"]) == "tend", "gaveta aberta: clique no vaso vira ordem")
	var popped := {"n": 0}
	var ok1b: bool = await _until(func() -> bool:
		popped["n"] = maxi(popped["n"], bunker._tip._pops.size())
		return bunker.orders.is_empty(), 3000)
	_check(ok1b and popped["n"] > 0, "aparece o +N%% quando ele ajuda (%d)" % popped["n"])
	drawer.call("close")
	await _frames(10)

	# 2) obra: ele larga o que fazia e vem martelar; cliques repetidos viram fila (máximo 4)
	var r: Dictionary = game.buy("vaso", 1, 7)
	var site: int = int(r["instance_id"])
	game.debug_advance_minutes(1.0)
	await _frames(40)
	_check(man.mode == "build", "com obra e sem ordem ele martela sozinho (%s)" % man.mode)
	var before: float = float(game.active_jobs()[0]["ratio"])
	_check(bunker.give_order("instance", site) == "", "clique na obra vira ordem")
	await _frames(4)
	_check(man.mode == "order", "a ordem tira ele do trabalho de antes (%s)" % man.mode)
	for k in 6:
		bunker.give_order("instance", pot)
	_check(bunker.orders.size() == 4, "a fila tem no máximo 4 (%d)" % bunker.orders.size())
	_check(bunker.give_order("instance", pot) == "full", "quinto pedido é recusado")
	await _frames(15)
	var out: String = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.get_texture().get_image().save_png("%s/ordens_fila.png" % out)
	var ok2: bool = await _until(func() -> bool: return bunker.orders.is_empty(), 3000)
	_check(ok2, "ele esvazia a fila")
	await _frames(100)
	_check(man.mode != "order", "sem ordens ele volta ao que fazia (%s)" % man.mode)
	var shown: float = float(game.active_jobs()[0]["ratio"]) if not game.active_jobs().is_empty() else 1.0
	_check(shown > before, "a obra andou com a ajuda (%.2f -> %.2f)" % [before, shown])

	# 3) caixa: ele leva os cestos e só então vira sucata
	game.debug_advance_minutes(240.0)
	await _frames(10)
	var scrap0: int = game.sucata()
	var stock: float = game.box_stock()
	var why_box: String = bunker.give_order("box")
	if stock <= 0.0:
		_check(why_box == "empty", "caixa vazia recusa (%s)" % why_box)
	else:
		_check(why_box == "" or why_box == "cooldown", "pedido da caixa (%s)" % why_box)
		if why_box == "":
			_check(game.sucata() == scrap0, "sucata não muda na hora")
			var ok3: bool = await _until(func() -> bool: return bunker.orders.is_empty(), 3000)
			_check(ok3 and game.sucata() > scrap0, "ele leva e a sucata sobe (%d -> %d)" % [scrap0, game.sucata()])

	# 3b) a despensa mostra o estoque (mochila): sem cestos nada, com cestos aparecem
	game.sim.stock = 0
	game.sim.stock_value = 0.0
	await _until(func() -> bool: return bunker._pantry.shown_slots() == 0, 600)
	_check(bunker._pantry.shown_slots() == 0, "despensa vazia sem cestos")
	game.sim.stock = 8
	game.sim.stock_value = 8.0
	await _until(func() -> bool: return bunker._pantry.shown_slots() > 0, 600)
	_check(bunker._pantry.shown_slots() > 0, "cestos aparecem nas prateleiras (%d)" % bunker._pantry.shown_slots())

	# 3c) ele está lá embaixo e mandam regar um vaso: tem que subir a escada e fazer
	man.interrupt()
	man._feet_y = float(BunkerGeo.FEET_Y_B)
	man.position = Vector2(bunker.pantry_x(), float(BunkerGeo.FEET_Y_B))
	var p1: float = _progress_of(game, pot)
	_check(bunker.give_order("instance", pot) == "", "pedido com ele no andar de baixo")
	var seen := {"ladder": false, "up": false}
	var ok4: bool = await _until(func() -> bool:
		if man.position.x < 24.0 and man.position.y > BunkerGeo.FEET_Y + 4.0 and man.position.y < BunkerGeo.FEET_Y_B - 4.0:
			seen["ladder"] = true
		return bunker.orders.is_empty(), 3000)
	_check(ok4 and seen["ladder"], "ele sobe pela escada para atender")
	_check(_progress_of(game, pot) > p1 or p1 > 0.5, "e a planta é cuidada em cima")
	_check(absf(man.feet_y() - float(BunkerGeo.FEET_Y)) < 0.5, "ele termina no andar do vaso")

	# 3d) levar à caixa passa pela despensa (desce) e entrega na escotilha (sobe)
	game.debug_advance_minutes(60.0)
	var sc1: int = game.sucata()
	var why3: String = bunker.give_order("box")
	if why3 == "":
		var low := {"min": 0.0}
		var ok5: bool = await _until(func() -> bool:
			low["min"] = maxf(low["min"], man.position.y)
			return bunker.orders.is_empty(), 4000)
		_check(ok5 and low["min"] > float(BunkerGeo.FEET_Y_B) - 2.0, "ele desce até a despensa para pegar os cestos")
		_check(game.sucata() > sc1, "e a sucata sobe quando ele entrega (%d -> %d)" % [sc1, game.sucata()])
	else:
		print("  (pedido da caixa: %s, pulado)" % why3)

	# 3e) cavar uma sala: a faixa cresce um andar e ele desce até lá
	game.sim.scrap = 500.0
	var dig: Dictionary = game.dig_room()
	_check(bool(dig["ok"]), "escavar a sala 2")
	main.call("_relayout")
	await _frames(10)
	_check(main.call("_strip_h") == BunkerGeo.H, "a janela continua com 2 andares (%d)" % int(main.call("_strip_h")))
	_check(bunker.world_height() == BunkerGeo.height(2), "o mundo ganhou o andar da sala nova (%d)" % bunker.world_height())
	var ok6: bool = await _until(func() -> bool: return absf(man.feet_y() - float(BunkerGeo.feet_y(2))) < 0.5, 4000)
	_check(ok6, "ele desce até o andar da escavação")
	var ok7: bool = await _until(func() -> bool: return absf(bunker.scroll_y - bunker.follow_target()) < 1.0, 4000)
	_check(ok7 and bunker.scroll_y > 40.0, "a câmera desce com ele (rolagem %.0f)" % bunker.scroll_y)

	# 4) dormindo ele não atende
	var g2 := 0
	while game.is_awake() and g2 < 200:
		game.debug_advance_minutes(30.0)
		g2 += 1
	_check(bunker.give_order("instance", pot) == "asleep", "dormindo: pedido recusado")
	Engine.time_scale = 1.0
	print("RESULTADO: %d FALHAS" % fails)
	quit(1 if fails > 0 else 0)
