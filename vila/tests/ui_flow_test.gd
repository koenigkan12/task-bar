extends SceneTree
## Fluxo da interface com a cena de verdade: clicar no chão abre Construir, escolher o poço
## entra em posicionamento, clicar põe a obra, clicar na torre abre o cartão dela.
## Roda: godot --headless --path . --script res://tests/ui_flow_test.gd -- --fresh --hour=10

var fails := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FALHOU: ", msg)
	else:
		print("ok: ", msg)


func _initialize() -> void:
	var main: Node = load("res://scenes/vila.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var sim = main.sim
	var hud = main.hud   # sem tipo: o hud usa autoloads que só existem com a árvore rodando
	var free: Vector2i = AutoPlayer.spot(sim, "poco")
	var scr: Vector2 = main.get_canvas_transform() * (Vector2(free) * 16.0 + Vector2(8, 8))
	main._click(scr)
	_check(hud.card_open() and hud._card_kind == "build", "clicar no chão abre Construir")
	hud.build_chosen.emit("poco")
	_check(main._placing == "poco", "escolher o poço entra em posicionamento")
	var n0: int = sim.buildings.size()
	main._click(scr)
	_check(sim.buildings.size() == n0 + 1 and main._placing == "", "clicar põe a obra")
	_check(hud._card_kind == "build", "depois de pôr, continua no modo construção")
	# Modo construção: clicar numa barraca pega ela; clicar num lugar livre larga lá.
	var tent: Dictionary = sim._first("moradia")
	var tent_c0: Vector2i = tent["cell"]
	main._click(main.get_canvas_transform() * (Vector2(tent_c0) * 16.0 + Vector2(8, 8)))
	_check(int(main._moving) == int(tent["id"]), "modo construção: clicar no prédio pega ele")
	var dest: Vector2i = AutoPlayer.spot(sim, "moradia")
	main._click(main.get_canvas_transform() * (Vector2(dest) * 16.0 + Vector2(8, 8)))
	_check(Vector2i(tent["cell"]) == dest and int(main._moving) < 0 and hud._card_kind == "build", "modo construção: larga no lugar novo e volta para o modo")
	hud.close_card()
	var tb: Dictionary = sim.tower_building()
	var tscr: Vector2 = main.get_canvas_transform() * (Vector2(Vector2i(tb["cell"])) * 16.0 + Vector2(8, 8))
	main._click(tscr)
	_check(hud._card_kind == "tower", "clicar na torre abre o cartão da torre")
	var jq: Dictionary = sim.people[0]
	main._click(main.get_canvas_transform() * main.world._person_world(jq) + Vector2(0, -6) * main.cam.zoom)
	_check(hud._card_kind == "person", "clicar no Joaquim abre o cartão dele")
	# Clique de verdade (apertar, cartão se atualiza, soltar) num botão do menu Construir.
	hud.show_build_menu()
	await process_frame
	await process_frame
	var bb: Button = hud.build_btns["horta"]
	var at: Vector2 = bb.get_global_rect().get_center()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = at
	ev.global_position = at
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	hud.refresh()
	await process_frame
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	await process_frame
	_check(main._placing == "horta", "clique com o cartão se atualizando no meio ainda vale")
	# X do cartão: mouse parado em cima por um tempo (o cartão se atualiza) e um clique fecha.
	hud.show_tower()
	for i in 5:
		await process_frame
	var xb: Button = null
	for c in hud._card_box.get_child(0).get_children():
		if c is Button and (c as Button).text == "x":
			xb = c
	var xp: Vector2 = xb.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = xp
	mv.global_position = xp
	Input.parse_input_event(mv)
	for i in 3:
		hud.refresh()
		await process_frame
	var dn := InputEventMouseButton.new()
	dn.button_index = MOUSE_BUTTON_LEFT
	dn.position = xp
	dn.global_position = xp
	dn.pressed = true
	Input.parse_input_event(dn)
	await process_frame
	var up2 := dn.duplicate() as InputEventMouseButton
	up2.pressed = false
	Input.parse_input_event(up2)
	await process_frame
	await process_frame
	_check(not hud.card_open(), "um clique no X fecha o cartão")
	# Cartão de prédio parado: as atualizações não podem trocar os nós nem mudar o tamanho (piscava).
	var mv2 := InputEventMouseMotion.new()
	mv2.position = Vector2(5, 120)
	mv2.global_position = mv2.position
	Input.parse_input_event(mv2)
	hud.show_building(int(sim._first("moradia")["id"]))
	for i in 4:
		await process_frame
	var box0: Node = hud._card_box
	var size0: Vector2 = hud._card.size
	var same := true
	for i in 12:
		hud.refresh()
		await process_frame
		if hud._card.size != size0 or hud._card_box != box0:
			same = false
	_check(same, "cartão de prédio parado não pisca nem muda de tamanho (%s)" % str(size0))
	var btm: Control = box0.get_child(box0.get_child_count() - 1)
	_check(hud._card.get_global_rect().encloses(btm.get_global_rect()), "o último botão do cartão cabe dentro dele")
	for i in 30:
		await process_frame
	# Portão com o grupo mais comprido (2 habilidades e "traz" em todos): os três "Escolher" cabem na tela.
	sim.gate_group.clear()
	for nm in ["Lúcia", "Jonas", "Edu"]:
		sim.gate_group.append({"name": nm, "look": 1, "bio": 1, "brings": {"agua": 7},
				"passives": [{"id": "horta", "rar": "rara"}, {"id": "pernas", "rar": "excelente"}]})
	hud.show_gate()
	for i in 4:
		await process_frame
	var vp: Rect2 = hud.get_viewport_rect()
	var area := Rect2(0, 16, vp.size.x, vp.size.y - 32)
	_check(area.encloses(hud._card.get_global_rect()), "cartão do portão fica entre as barras (%s)" % str(hud._card.get_global_rect()))
	var picks := 0
	var stack: Array = [hud._card_box]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Button and (n as Button).text == root.get_node("I18n").t("UI_CHOOSE") and hud._card.get_global_rect().encloses((n as Button).get_global_rect()):
			picks += 1
	_check(picks == 3, "os três botões Escolher aparecem inteiros (%d)" % picks)
	# Dica da barra de cima: estoque/limite e ritmo por minuto, sem precisar clicar.
	var tip: Control = hud._res_chips["comida"]._make_custom_tooltip("")
	var txt := ""
	var st2: Array = [tip]
	while not st2.is_empty():
		var n2: Node = st2.pop_back()
		st2.append_array(n2.get_children())
		if n2 is Label:
			txt += (n2 as Label).text + " "
	_check(txt.contains("/%d" % int(sim.cap("comida"))) and txt.contains("/min"), "dica da comida mostra estoque/limite e ritmo (%s)" % txt)
	tip.free()
	print("FALHAS: ", fails)
	quit(1 if fails > 0 else 0)
