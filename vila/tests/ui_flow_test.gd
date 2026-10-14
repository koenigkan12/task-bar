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
	for i in 30:
		await process_frame
	print("FALHAS: ", fails)
	quit(1 if fails > 0 else 0)
