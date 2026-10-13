extends SceneTree
## Captura a faixa com os cômodos novos (3 salas + andar de baixo) e o jogo vazio de salas.
## Uso: OUT_DIR=<pasta> xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/shot_bunker_rooms.gd

var out_dir: String = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "user://shots"

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	await _frames(8)
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name, " ", img.get_size())

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("/root/Settings").set_value("intro_seen", true)
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
	game.sim.scrap = 9999.0
	game.sim.antenna_level = 5
	game.sim.rooms_n = 3
	for it in [["canteiro", 2, 1], ["prateleira", 2, 4], ["gotejador", 2, 7], ["painel", -1, -1], ["bateria", 1, 8], ["estufa", 3, 1], ["mesinha", 3, 6], ["estante", 3, 9]]:
		var r: Dictionary = game.buy(it[0], it[1], it[2])
		print("buy ", it, " ", r.get("ok"), " ", r.get("reason", ""))
	for i in 12:
		game.debug_advance_minutes(60.0)
	guard = 0
	while (game.tod_hours() < 10.0 or game.tod_hours() > 12.0) and guard < 400:
		game.debug_advance_minutes(15.0)
		guard += 1
	game.sim.stock = 9
	game.sim.stock_value = 9.0
	main.call("_relayout")
	await _frames(40)
	await _shot("rooms_1_full")
	# escavando a sala 4 não existe; mostra a sala 2 sendo aberta numa partida nova
	game.new_game()
	main.get("_bunker").call("full_refresh")
	game.sim.scrap = 9999.0
	print("dig ", game.dig_room())
	var g2 := 0
	while g2 < 200:
		game.debug_advance_minutes(5.0)
		g2 += 1
		var jobs: Array = game.active_jobs()
		if jobs.size() > 0 and float(jobs[0]["ratio"]) > 0.5:
			break
	main.call("_relayout")
	await _frames(40)
	await _shot("rooms_2_dig")
	quit(0)
