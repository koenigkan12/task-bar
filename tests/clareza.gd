extends SceneTree
## Interface de clareza: barra de uma linha, cartões ao clicar (Joaquim, caixa, gerador, antena),
## contorno + etiqueta no hover, relógio único e seta do tutorial. Captura PNGs em OUT_DIR.
## Uso: OUT_DIR=<pasta> xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/clareza.gd

var out_dir: String = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "user://shots"
var fails: int = 0
var main: Node
var game: Node
var bunker: BunkerView


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
	root.get_texture().get_image().save_png("%s/clareza_%s.png" % [out_dir, name])


func _initialize() -> void:
	_run.call_deferred()


func _hover(local: Vector2) -> void:
	root.warp_mouse(bunker.to_global(local))
	var ev := InputEventMouseMotion.new()
	ev.position = bunker.to_global(local)
	ev.global_position = ev.position
	root.push_input(ev)
	await _frames(4)


func _click(local: Vector2) -> void:
	await _hover(local)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = bunker.to_global(local)
		ev.global_position = ev.position
		root.push_input(ev)
		await _frames(3)


func _run() -> void:
	var st: Node = root.get_node("/root/Settings")
	st.set_value("intro_seen", true)
	st.set_value("tutorial", {})
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
	var card: InfoCard = main.get("_card")
	var hud: StatusHud = main.get("_hud")
	var tip: PlotTip = bunker.get("_tip")

	# barra de cima: uma linha, sem fração, com a palavra "sucata"
	_check(hud._scrap.text.ends_with("sucata"), "barra: '%s'" % hud._scrap.text)
	_check(not hud._goal.text.contains("/"), "meta sem fração: '%s'" % hud._goal.text)
	_check(hud._tut.text == "1/4 Clique num vaso", "tutorial de uma linha: '%s'" % hud._tut.text)
	_check(bunker.tutorial_key == "tut.1", "a cena sabe o passo do tutorial")
	await _shot("1_inicio")

	# hover num vaso: contorno + etiqueta curta
	var pot: BunkerObject = null
	for it in game.instances():
		if String(it["item"]) == "vaso":
			pot = bunker.object_by_id(int(it["id"]))
			break
	_check(pot != null, "há um vaso")
	await _hover(pot.bounds().get_center())
	_check(tip.hover_lines().size() >= 2 and tip.hover_rect().size != Vector2.ZERO, "hover do vaso: %s" % str(tip.hover_lines()))
	await _shot("2_hover_vaso")

	# retratinho do Joaquim na barra: clicar abre o cartão dele
	await _click(bunker.to_local(hud.global_position + Vector2(6, 5)))
	_check(card.is_open() and card.kind == "man", "clique no retrato do Joaquim abre o cartão")
	await _shot("2b_retrato")
	card.close()
	await _frames(2)

	# Joaquim: congela num lugar livre; hover mostra "Joaquim · ..."; clique abre o cartão
	bunker.man.cinematic = true
	bunker.man.position = Vector2(150, BunkerGeo.FEET_Y)
	await _frames(3)
	var mc: Vector2 = bunker.man.body_rect().get_center()
	_check(String(bunker.get_object_at(mc).get("kind", "")) == "man", "a posição livre acerta o Joaquim (%s)" % str(bunker.get_object_at(mc)))
	await _hover(mc)
	_check(tip.hover_lines().size() == 1 and String(tip.hover_lines()[0]).begins_with("Joaquim"), "hover do Joaquim: %s" % str(tip.hover_lines()))
	await _click(mc)
	_check(card.is_open() and card.kind == "man", "clique no Joaquim abre o cartão")
	var rows: Array = card._rows(game)
	_check(String(rows[0]["text"]) == "Joaquim", "cartão tem o nome")
	await _shot("3_cartao_joaquim")

	# um clique fora fecha o cartão
	await _click(Vector2(170, 40))
	_check(not card.is_open(), "clique fora fecha o cartão")

	# caixa vazia: cartão com botão desligado; com cestos: botão Vender [cesto]N -> [sucata]N
	var box_c: Vector2 = bunker.rect_of({"kind": "box"}).get_center()
	game.sim.stock = 0
	game.sim.stock_value = 0.0
	await _click(box_c)
	_check(card.is_open() and card.kind == "box", "clique na caixa abre o cartão dela")
	var has_sell := false
	for r in card._rows(game):
		has_sell = has_sell or String(r["t"]) == "sell"
	_check(not has_sell, "caixa vazia não oferece vender")
	game.sim.stock = 4
	game.sim.stock_value = 4.0
	game.sim._last_visit_abs = -1.0e9
	await _frames(20)
	var sale: Dictionary = game.box_sale()
	_check(int(sale["units"]) == 4 and int(sale["scrap"]) == 4, "box_sale: %s" % str(sale))
	has_sell = false
	for r in card._rows(game):
		has_sell = has_sell or String(r["t"]) == "sell"
	_check(has_sell, "com cestos o cartão oferece vender")
	await _shot("4_cartao_caixa")
	var scrap0: int = game.sucata()
	card.action.emit("sell")
	await _frames(3)
	_check(not card.is_open(), "vender fecha o cartão")
	_check(bunker.orders.size() == 1 and String(bunker.orders[0]["kind"]) == "box", "vender vira ordem da caixa")
	bunker.man.cinematic = false
	Engine.time_scale = 6.0
	var n := 0
	while not bunker.orders.is_empty() and n < 3000:
		await process_frame
		n += 1
	Engine.time_scale = 1.0
	_check(game.sucata() > scrap0, "a sucata sobe quando ele leva (%d -> %d)" % [scrap0, game.sucata()])

	# espera da caixa: hover cinza com relógio
	game.sim.stock = 3
	game.sim.stock_value = 3.0
	await _frames(30)
	await _hover(box_c)
	_check(String(game.help_box_check()) == "cooldown", "caixa em espera (%s)" % game.help_box_check())
	_check(tip.hover_grey(), "contorno cinza na espera")
	await _shot("5_caixa_espera")

	# caixa cheia: selo vermelho em cima
	game.sim._last_visit_abs = -1.0e9
	game.sim.stock = game.box_capacity() + 2
	game.sim.stock_value = float(game.sim.stock)
	await _frames(30)
	_check(bool(tip._box.get("full", false)), "caixa cheia liga o selo")
	await _hover(Vector2(150, 100))
	await _shot("6_caixa_cheia")
	game.sim.stock = 0
	game.sim.stock_value = 0.0

	# gerador: cartão de energia
	var gen_id := -1
	for it in game.instances():
		if bunker.is_generator(String(it["item"])):
			gen_id = int(it["id"])
	_check(gen_id >= 0, "há um gerador")
	var gen: BunkerObject = bunker.object_by_id(gen_id)
	bunker.man.cinematic = true
	bunker.man.position = Vector2(40, BunkerGeo.FEET_Y)
	await _click(gen.bounds().get_center())
	_check(card.is_open() and card.kind == "gen", "clique no gerador abre o cartão de energia")
	var gr: Array = card._rows(game)
	_check(String(gr[1]["text"]).begins_with("Sobra") or String(gr[1]["text"]).begins_with("Falta"), "sobra/falta: %s" % str(gr[1]["text"]))
	await _shot("7_cartao_gerador")

	# antena
	card.close()
	var ar: Rect2 = bunker.rect_of({"kind": "antenna"})
	var ant := Vector2(ar.get_center().x, ar.end.y - 3.0)   # a ponta de cima fica sob a barra de status
	await _click(ant)
	_check(card.is_open() and card.kind == "antenna", "clique na antena abre o cartão")
	await _shot("8_cartao_antena")
	card.close()
	bunker.man.cinematic = false

	# obra: relógio sempre visível, com tempo; planta pronta: check
	var r: Dictionary = game.buy("vaso", 1, 7)
	game.debug_advance_minutes(3.0)
	await _frames(30)
	_check(not tip._jobs.is_empty(), "obra em curso")
	await _shot("9_obra_relogio")
	print("RESULTADO: %d FALHAS" % fails)
	quit(1 if fails > 0 else 0)
