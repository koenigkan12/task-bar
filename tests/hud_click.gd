extends SceneTree
## O texto do tutorial não pode tapar a escotilha: o clique atravessa o HUD, e o "-" recolhe o texto.
## Uso: OUT_DIR=<pasta> xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/hud_click.gd

var out_dir: String = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "user://shots"
var fails: int = 0

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1

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

func _esc() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		root.push_input(ev)
		await _frames(3)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var st: Node = root.get_node("/root/Settings")
	st.set_value("intro_seen", true)
	st.set_value("tutorial_hidden", false)
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
	game.debug_advance_minutes(45.0)
	game.sim.stock = 3
	game.sim.stock_value = 3.0
	await _frames(20)
	var hud: Control = main.get("_hud")
	var bunker: Node2D = main.get("_bunker")
	_check(hud.visible and hud.size.y > 20.0, "HUD com texto do tutorial (altura %.0f)" % hud.size.y)
	var hatch: Vector2 = bunker.to_global(Vector2(24, 24))
	_check(hud.get_global_rect().has_point(hatch) == false or not hud.call("_has_point", hatch - hud.global_position), "escotilha fora da área clicável do HUD")
	print("avail ", game.help_box_available(), " stock ", game.box_stock())
	var s0: int = int(game.sucata())
	print("hatch ", hatch, " hit ", bunker.call("get_object_at", bunker.to_local(hatch)), " hov ", root.gui_get_hovered_control())
	var cnt := {"n": 0}
	bunker.connect("hatch_clicked", func() -> void: cnt["n"] += 1)
	var drawer_open_before: bool = main.get("_drawer").is_open()
	await _click(hatch)
	print("hatch_clicked emitido ", cnt["n"], " r=", game.help_box_available())
	print("drawer open ", main.get("_drawer").is_open(), " was ", drawer_open_before)
	await _frames(5)
	_check(int(game.sucata()) > s0, "clique na escotilha troca cestos por sucata (%d -> %d)" % [s0, int(game.sucata())])
	var img0: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	img0.save_png("%s/hud_texto.png" % out_dir)
	# recolher o texto
	var tut: Label = hud.get("_tut")
	_check(tut.visible, "texto do tutorial visível")
	var row_w: float = hud.get("_row_w")
	await _click(hud.global_position + Vector2(row_w - 3.0, 6.0))
	await _frames(10)
	_check(not tut.visible, "botão recolhe o texto")
	_check(bool(st.get_value("tutorial_hidden", false)), "escolha fica salva")
	await _frames(5)
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	img.save_png("%s/hud_recolhido.png" % out_dir)
	st.set_value("tutorial_hidden", false)
	# Esc: abre as opções com a gaveta fechada e fecha de novo
	var drawer: Node = main.get("_drawer")
	_check(not drawer.is_open(), "gaveta fechada antes do Esc")
	await _esc()
	_check(drawer.is_open(), "Esc abre a gaveta (opções)")
	await _esc()
	_check(not drawer.is_open(), "Esc de novo fecha")
	print("RESULTADO: %d FALHAS" % fails)
	quit(1 if fails > 0 else 0)
