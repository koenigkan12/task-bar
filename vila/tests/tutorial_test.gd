extends SceneTree
## Tutorial do começo ao fim com a cena de verdade: cada ação faz o passo andar.
## Roda: godot --headless --path . --script res://tests/tutorial_test.gd -- --fresh --hour=10

var fails := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FALHOU: ", msg)
	else:
		print("ok: ", msg)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	await process_frame
	root.get_node("Settings").set_value("tut_done", false)
	root.get_node("Settings").set_value("tut_step", 0)
	root.get_node("Settings").set_value("dtut_done", false)
	root.get_node("Settings").set_value("dtut_step", 0)
	var main: Node = load("res://scenes/vila.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	var tut = main._tut
	var hud = main.hud
	var sim = main.sim
	_check(tut.active() and tut._step == 0, "começa no passo do Joaquim")
	hud.show_person(int(sim.people[0]["id"]))
	await _frames(2)
	_check(tut._step == 1, "clicar no Joaquim passa para os recursos")
	hud.show_res("comida")
	await _frames(2)
	_check(tut._step == 2, "abrir a comida passa para Construir")
	hud.build_btn.pressed.emit()
	await _frames(2)
	_check(tut._step == 3, "Construir passa para escolher o barril")
	_check(hud.build_btns.has("horta") and hud.build_btns["horta"].disabled, "só o barril fica liberado")
	hud.build_btns["poco"].pressed.emit()
	await _frames(2)
	_check(tut._step == 4 and main._placing == "poco", "escolher o barril entra em posicionamento")
	var cell: Vector2i = AutoPlayer.spot(sim, "poco")
	main._click(main.get_canvas_transform() * (Vector2(cell) * 16.0 + Vector2(8, 8)))
	await _frames(2)
	_check(tut._step == 5, "pôr a obra passa para esperar")
	var el := 0.0
	while el < 300.0 and tut._step == 5:
		sim.advance(1.0)
		el += 1.0
		await process_frame
	_check(tut._step == 6, "barril pronto passa para a meta (%ds)" % int(el))
	hud.goal_btn.pressed.emit()
	await _frames(2)
	_check(tut._step == 7 and main._placing == "horta", "a meta entra em posicionamento da horta")
	var hc: Vector2i = AutoPlayer.spot(sim, "horta")
	main._click(main.get_canvas_transform() * (Vector2(hc) * 16.0 + Vector2(8, 8)))
	await _frames(2)
	_check(tut._step == 8, "pôr a horta passa para a torre")
	hud.tower_btn.pressed.emit()
	await _frames(2)
	_check(tut._step == 9, "Torre passa para o zoom")
	main._set_zoom(0, Vector2(100, 100))
	await _frames(2)
	_check(tut._step == 10, "zoom passa para o fim")
	tut._ok.pressed.emit()
	await _frames(2)
	_check(not tut.active() and bool(root.get_node("Settings").get_value("tut_done", false)), "Certo termina o tutorial")
	# Capítulo da defesa: por onde chegam, Construir, aba Defesa, torre arqueira, pôr e esperar.
	hud.close_card()   # começa quando não tem cartão aberto (o da torre ficou do passo anterior)
	await _frames(3)
	_check(tut.d_active() and tut._dstep == 0 and main.world.show_arrivals, "depois do tutorial vem o capítulo da defesa")
	_check(not sim.defense.arrivals().is_empty(), "o mapa sabe por onde os zumbis chegam")
	tut._ok.pressed.emit()
	await _frames(2)
	_check(tut._dstep == 1, "Certo passa para Construir")
	hud.build_btn.pressed.emit()
	await _frames(2)
	_check(tut._dstep == 2, "Construir passa para a aba Defesa")
	hud.build_tab_btns["defense"].pressed.emit()
	await _frames(2)
	_check(tut._dstep == 3, "aba Defesa passa para a torre arqueira")
	_check(hud.build_btns.has("torre_arq") and not hud.build_btns["torre_arq"].disabled, "torre arqueira liberada para pagar")
	hud.build_btns["torre_arq"].pressed.emit()
	await _frames(2)
	_check(tut._dstep == 4 and main._placing == "torre_arq", "escolher a torre entra em posicionamento")
	var tcell: Vector2i = AutoPlayer.spot(sim, "torre_arq")
	main._click(main.get_canvas_transform() * (Vector2(tcell) * 16.0 + Vector2(8, 8)))
	await _frames(2)
	_check(tut._dstep == 5, "pôr a torre passa para esperar")
	tut._ok.pressed.emit()
	await _frames(2)
	_check(not tut.d_active() and bool(root.get_node("Settings").get_value("dtut_done", false)) and not main.world.show_arrivals, "Certo termina o capítulo da defesa")
	print("FALHAS: ", fails)
	quit(1 if fails > 0 else 0)
