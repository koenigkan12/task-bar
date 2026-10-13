extends SceneTree
## Faixa fixa em 2 andares (136 px) com rolagem vertical: roda e arrastar movem a vista, a câmera segue o
## Joaquim e volta depois de uns segundos, o indicador de andares aparece só quando há o que rolar, e a
## camada de posicionar acompanha a rolagem. Captura PNGs em OUT_DIR.
## Uso: OUT_DIR=<pasta> xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/rolagem.gd

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
	root.get_texture().get_image().save_png("%s/rolagem_%s.png" % [out_dir, name])


func _initialize() -> void:
	_run.call_deferred()


func _wheel(at: Vector2, up: bool) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev)
	await _frames(2)


func _mouse(at: Vector2, pressed: bool, button: bool) -> void:
	root.warp_mouse(at)
	if button:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev)
	else:
		var mv := InputEventMouseMotion.new()
		mv.position = at
		mv.global_position = at
		root.push_input(mv)
	await _frames(2)


func _until(cond: Callable, max_frames: int = 600) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()


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
	var floors: FloorIndicator = main.get("_floors")
	var view: Control = main.get("_view")

	# 1 sala: 2 andares na vertical (nada para rolar), mas os cômodos são mais largos que a janela
	_check(main.call("_strip_h") == BunkerGeo.H, "janela de %d px de altura" % int(main.call("_strip_h")))
	_check(absf(view.size.x - BunkerGeo.WIN_W) < 0.5, "janela de %d px de largura" % int(view.size.x))
	_check(bunker.max_scroll() == 0.0, "1 sala: nada para rolar na vertical")
	_check(bunker.max_scroll_x() == float(BunkerGeo.strip_width(1) - BunkerGeo.WIN_W), "1 sala: rola %d px para os lados" % int(bunker.max_scroll_x()))
	await _frames(3)
	_check(floors.visible, "o mapinha aparece porque dá para rolar para os lados")
	var side: Vector2 = view.global_position + Vector2(100, 70)
	bunker.man.cinematic = true
	bunker.man.position.x = 40.0
	bunker.snap_scroll()
	await _wheel(side, false)
	_check(bunker.scroll_x == BunkerView.WHEEL_STEP and bunker.scroll_y == 0.0, "sem andar para rolar, a roda anda para os lados (%d)" % int(bunker.scroll_x))
	await _wheel(side, true)
	_check(bunker.scroll_x == 0.0, "roda para cima volta")
	bunker.pan_xy(Vector2(1000.0, 0.0))
	await _frames(2)
	_check(bunker.scroll_x == bunker.max_scroll_x(), "para no fim do bunker (%d)" % int(bunker.scroll_x))
	await _shot("0_direita")
	bunker._pan_pause = 0.05
	var back0: bool = await _until(func() -> bool: return absf(bunker.scroll_x - bunker.follow_target_x()) < 1.0)
	_check(back0 and bunker.scroll_x < 40.0, "a câmera volta para ele (%d)" % int(bunker.scroll_x))

	# 3 salas: o mundo cresce, a janela não
	game.sim.scrap = 9999.0
	game.sim.antenna_level = 5
	game.sim.rooms_n = 3
	for it in ["canteiro", "estufa", "mesinha"]:
		game.buy(it, -1, -1)
	for i in 12:
		game.debug_advance_minutes(60.0)
	main.call("_relayout")
	bunker.full_refresh()
	await _frames(20)
	_check(main.call("_strip_h") == BunkerGeo.H, "3 salas: a janela continua com %d px" % BunkerGeo.H)
	_check(bunker.world_height() == BunkerGeo.height(3), "mundo de %d px" % bunker.world_height())
	_check(absf(view.size.y - BunkerGeo.H) < 0.5, "a área recortada tem %d px" % int(view.size.y))
	_check(floors.visible, "mapinha visível")
	_check(bunker.max_scroll() == float(BunkerGeo.height(3) - BunkerGeo.H), "rola até %d" % int(bunker.max_scroll()))

	# começa em cima (ele está no andar A)
	bunker.man.cinematic = true
	bunker.man.position.y = float(BunkerGeo.FEET_Y)
	bunker.snap_scroll()
	await _frames(3)
	_check(bunker.scroll_y == 0.0, "começa no topo")
	await _shot("1_topo")

	# roda para baixo: desce 24 px por clique e segura a câmera
	var mid: Vector2 = view.global_position + Vector2(100, 70)
	await _wheel(mid, false)
	_check(bunker.scroll_y == BunkerView.WHEEL_STEP, "roda desce %d" % int(bunker.scroll_y))
	_check(absf(bunker.position.y + BunkerView.WHEEL_STEP) < 0.5, "a cena subiu %d" % int(-bunker.position.y))
	for i in 10:
		await _wheel(mid, false)
	_check(bunker.scroll_y == bunker.max_scroll(), "para no fim (%d)" % int(bunker.scroll_y))
	_check(bunker.is_panning(), "a câmera espera depois de rolar à mão")
	await _shot("2_fundo")
	await _wheel(mid, true)
	_check(bunker.scroll_y == bunker.max_scroll() - BunkerView.WHEEL_STEP, "roda para cima sobe")

	# roda fora da faixa não rola
	var before: float = bunker.scroll_y
	await _wheel(Vector2(100, -50), false)
	_check(bunker.scroll_y == before, "roda fora da faixa não mexe")

	# cliques na cena acertam o objeto certo mesmo rolada
	var cell: Vector2 = bunker.get_local_mouse_position()
	_check(bunker.get_object_at(Vector2(100, 200)).get("kind", "") != "", "pontos do mundo abaixo da janela são alcançáveis")

	# arrastar o chão vazio
	bunker.pan_by(-1000.0)
	await _frames(2)
	_check(bunker.scroll_y == 0.0, "pan_by sobe até o topo")
	var empty: Vector2 = view.global_position + Vector2(10, 128)
	await _mouse(empty, true, true)
	await _mouse(empty + Vector2(0, -2), false, false)
	_check(bunker.scroll_y == 0.0, "mexida pequena não vira arrasto")
	await _mouse(empty + Vector2(0, -30), false, false)
	_check(bunker.scroll_y > 20.0, "arrastar para cima desce a vista (%d)" % int(bunker.scroll_y))
	await _mouse(empty + Vector2(0, -30), false, true)
	var after_drag: float = bunker.scroll_y

	# câmera: espera ~4 s e volta sozinha para onde ele está
	_check(bunker.is_panning(), "depois do arrasto ela continua esperando")
	await _frames(30)
	_check(absf(bunker.scroll_y - after_drag) < 0.5, "enquanto espera não se mexe")
	bunker._pan_pause = 0.05
	var back: bool = await _until(func() -> bool: return absf(bunker.scroll_y - bunker.follow_target()) < 1.0)
	_check(back and bunker.scroll_y < 1.0, "volta a seguir o Joaquim (%d)" % int(bunker.scroll_y))

	# ele desce para o andar C: a câmera desce junto
	bunker.man._feet_y = float(BunkerGeo.feet_y(2))
	bunker.man._plan_y = bunker.man._feet_y
	bunker.man.position.y = bunker.man._feet_y
	var follow: bool = await _until(func() -> bool: return bunker.follow_target() > 40.0 and absf(bunker.scroll_y - bunker.follow_target()) < 1.0)
	_check(follow and bunker.scroll_y > 40.0, "a câmera acompanha o andar C (%d)" % int(bunker.scroll_y))
	await _shot("3_andar_c")

	# indicador: clique numa célula leva a vista até lá
	var fc: Vector2 = floors.global_position + Vector2(FloorIndicator.PAD, FloorIndicator.PAD) + Vector2(60.0, 50.0) * FloorIndicator.SCALE
	await _mouse(fc, true, true)
	await _mouse(fc, false, true)
	_check(bunker.scroll_y == 0.0 and bunker.scroll_x == 0.0, "clicar no mapinha leva a vista até lá (%d, %d)" % [int(bunker.scroll_x), int(bunker.scroll_y)])
	await _shot("4_indicador")

	# camada de posicionar: retângulos do mundo descontam a rolagem
	var drawer: Drawer = main.get("_drawer")
	drawer.open("build")
	await _frames(10)
	var ov: DrawerPlacementOverlay = drawer.overlay()
	var r: Rect2 = BunkerGeo.block_rect(3, 2, 2)
	ov.show_hints([{"room": 3, "col": 2}], 2)
	ov.set_scroll(0.0, 0.0)
	_check(ov.index_at(r.get_center()) == 0, "sem rolagem, o ponto do mundo acerta a posição")
	ov.set_scroll(0.0, 100.0)
	_check(ov.index_at(r.get_center()) == -1 and ov.index_at(r.get_center() - Vector2(0, 100)) == 0, "com rolagem 100, o clique desconta")
	ov.clear()
	ov.set_scroll(0.0, 0.0)
	# começar a posicionar numa sala fora da janela: a câmera vai até lá
	bunker.pan_by(-1000.0)
	await _frames(2)
	drawer.start_placement("place", "estufa", -1, [{"room": 3, "col": 2}], 2)
	await _frames(3)
	var rect: Rect2 = BunkerGeo.block_rect(3, 2, 2)
	_check(rect.position.y >= bunker.scroll_y and rect.end.y <= bunker.scroll_y + BunkerGeo.H, "a câmera mostra onde dá para pôr (rolagem %d)" % int(bunker.scroll_y))
	_check(absf(drawer.overlay().scroll_y - bunker.scroll_y) < 1.0, "a camada de posicionar acompanha")
	await _shot("5_posicionar")
	drawer.cancel_placement()

	print("RESULTADO: %d FALHAS" % fails)
	quit(1 if fails > 0 else 0)
