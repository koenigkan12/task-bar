extends SceneTree
## Captura o feedback do plantio: barras de progresso, etiqueta no hover e "+1 cesto".
## Uso: OUT_DIR=<pasta> xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/shot_plot_tip.gd

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
	game.debug_advance_minutes(8.0)
	await _frames(30)
	var bunker: Node2D = main.get("_bunker")
	var plots: Array = game.plots()
	print("plots ", plots.size(), " ", plots[0] if plots.size() > 0 else {})
	var pos: Vector2 = bunker.call("plot_pos", plots[0])
	root.warp_mouse(bunker.to_global(pos) + Vector2(0, -6))
	await _frames(30)
	await _shot("plot_1_hover")
	game.debug_advance_minutes(5.0)
	await _frames(10)
	await _shot("plot_1b_mid")
	game.debug_advance_minutes(6.0)
	await _frames(30)
	await _shot("plot_2_later")
	guard = 0
	var stock0: int = int(game.box_stock())
	while int(game.box_stock()) == stock0 and guard < 600:
		game.debug_advance_minutes(1.0)
		guard += 1
	await _frames(6)
	print("colheu depois de ", guard, " min; cesto ", game.box_stock())
	await _shot("plot_3_pop")
	quit(0)
