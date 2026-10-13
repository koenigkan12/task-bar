extends SceneTree
## Modo de teste: F9 alterna 1x/10x/60x (selo "x10") e F10 pula 1 hora. (Apagar com scripts/debug antes do lançamento.)
## Uso: OUT_DIR=<pasta> xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/debug_speed.gd

var out_dir: String = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "user://shots"
var fails: int = 0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)
		await _frames(2)


func _initialize() -> void:
	_run.call_deferred()


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
	var dbg: DebugSpeed = null
	for c in main.get_children():
		if c is DebugSpeed:
			dbg = c
	_check(dbg != null, "modo de teste presente")
	_check(is_equal_approx(game.time_scale, 1.0) and not dbg.get("_badge").visible, "começa em 1x, sem selo")
	await _key(KEY_F9)
	_check(is_equal_approx(game.time_scale, 10.0) and dbg.get("_badge").visible and dbg.get("_badge").text == "x10", "F9: 10x e selo x10")
	var t0: float = game.sim.t_min
	game._process(30.0)   # 30 s de relógio de parede
	_check(absf(game.sim.t_min - t0 - 5.0) < 0.6, "10x: 30 s viram 5 min de jogo (%.1f)" % (game.sim.t_min - t0))
	var shot: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	shot.save_png("%s/debug_speed_x10.png" % out_dir)
	await _key(KEY_F9)
	_check(is_equal_approx(game.time_scale, 60.0) and dbg.get("_badge").text == "x60", "F9: 60x")
	await _key(KEY_F9)
	_check(is_equal_approx(game.time_scale, 1.0) and not dbg.get("_badge").visible, "F9: volta a 1x, selo some")
	var before: float = game.sim.t_min
	var harvested := {"n": 0}
	game.plot_harvested.connect(func(_p: int) -> void: harvested["n"] += 1)
	await _key(KEY_F10)
	_check(absf(game.sim.t_min - before - 60.0) < 1.5, "F10 pulou 1 hora (%.1f min)" % (game.sim.t_min - before))
	_check(harvested["n"] == 0, "pulo sem inundar sinais de colheita")
	print("fails=%d" % fails)
	quit(1 if fails > 0 else 0)
