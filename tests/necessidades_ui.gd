extends SceneTree
## Barra com "Dia N", raio de energia e moldura do retrato; cartão do Joaquim com 3 medidores;
## gerador piscando quando falta energia; tela de fim com o diário. Gera capturas.
## Uso: OUT_DIR=<pasta> xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/necessidades_ui.gd

var out_dir: String = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "user://shots"
var fails: int = 0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1


func _shot(name: String) -> void:
	await _frames(8)
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	img.save_png("%s/%s.png" % [out_dir, name])


func _click(pos: Vector2) -> void:
	root.warp_mouse(pos)
	await _frames(3)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev)
		await _frames(2)


func _initialize() -> void:
	_run.call_deferred()


func _gauges(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is NeedGauge:
			out.append(c)
		out.append_array(_gauges(c))
	return out


func _run() -> void:
	var st: Node = root.get_node("/root/Settings")
	st.set_value("intro_seen", true)
	st.set_value("tutorial_hidden", true)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(10)
	var game: Node = root.get_node("/root/Game")
	game.new_game()
	main.call("_on_game_started", true)
	await _frames(20)
	var hud: StatusHud = main.get("_hud")
	var card: InfoCard = main.get("_card")
	var bunker: BunkerView = main.get("_bunker")

	print("== barra")
	await _frames(5)
	_check(String(hud.get("_day").text) == "Dia 1", "barra mostra o dia: " + String(hud.get("_day").text))
	_check(String(hud.get("_pow").text) == "2/3", "barra mostra a energia: " + String(hud.get("_pow").text))
	_check(String(hud.get("_need_state")) == "ok", "moldura normal")
	await _shot("necessidades_1_barra")

	print("== clique no raio abre o gerador")
	var er: Rect2 = hud.energy_rect()
	await _click(er.get_center())
	await _frames(6)
	_check(card.is_open() and card.kind == "gen", "clique no raio abre o cartão do gerador")
	await _shot("necessidades_2_gerador")
	card.close()

	print("== clique no retrato abre o cartão com 3 medidores")
	await _click(hud.face_rect().get_center())
	await _frames(6)
	_check(card.is_open() and card.kind == "man", "clique no retrato abre o cartão do Joaquim")
	_check(_gauges(card).size() == 3, "3 medidores redondos")
	_check(card.size.y <= 100.0, "cartão normal é baixo (altura %.0f)" % card.size.y)
	await _shot("necessidades_3_cartao_ok")
	card.close()

	print("== comida baixa: moldura âmbar; sem comida: vermelha e o prazo corre")
	game.sim._food = 0.4
	game.sim.state_changed.emit()
	game.state_changed.emit()
	await _frames(6)
	_check(String(hud.get("_need_state")) == "warn", "moldura âmbar")
	game.sim._plots = []
	game.sim._food = 0.05
	game.sim._missed_meals = 1
	game.state_changed.emit()
	await _frames(6)
	_check(String(hud.get("_need_state")) == "bad", "moldura vermelha")
	_check(game.sim.death_left_min("food") >= 0.0, "viu o aviso: prazo armado")
	await _click(hud.face_rect().get_center())
	await _frames(6)
	_check(card.size.y <= 122.0 and card.position.y >= 0.0, "cartão vermelho cabe na faixa (altura %.0f)" % card.size.y)
	await _shot("necessidades_4_cartao_vermelho")
	card.close()

	print("== sem energia: raio vermelho piscando e gerador em destaque")
	game.sim._missed_meals = 0
	game.sim._food = 1.0
	game.sim.rooms_n = 3
	game.sim.antenna_level = 5
	game.state_changed.emit()
	await _frames(10)
	_check(String(hud.get("_power_state")) == "bad", "raio vermelho: " + String(hud.get("_pow").text))
	var bike: BunkerObject = bunker.find_item("bicicleta")
	await _frames(40)
	_check(bike != null and bike.get("_glow_icon") != null and (bike.get("_glow_icon") as Sprite2D).visible, "bicicleta com o raio em cima")
	await _shot("necessidades_5_sem_energia")
	await _click(hud.energy_rect().get_center())
	await _frames(6)
	await _shot("necessidades_6_gerador_falta")
	card.close()

	print("== morte")
	game.sim._dead = true
	game.sim._death_days = 7
	game.died.emit(7)
	await _frames(40)
	var ending: Control = main.get("_ending")
	_check(ending != null and String(ending.get("kind")) == "death", "tela de fim aparece")
	await _frames(40)
	await _shot("necessidades_7_fim")
	ending.call("_finish", "diary")
	await _frames(40)
	_check(main.get("_ending") == null and main.get("_drawer").is_open(), "Ler o diário abre a gaveta")
	main.get("_drawer").close()
	await _frames(30)
	_check(main.get("_ending") != null, "fechar a gaveta traz a tela de fim de volta")

	print("fails=%d" % fails)
	quit(1 if fails > 0 else 0)
