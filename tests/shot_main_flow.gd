extends SceneTree
## Captura o fluxo principal sob xvfb (opengl3): título -> jogo -> gaveta -> dias avançados.
## Uso: OUT_DIR=<pasta> xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/shot_main_flow.gd

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
	root.get_node("/root/Settings").set_value("intro_seen", false)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(10)
	await _shot("main_1_title")
	var game: Node = root.get_node("/root/Game")
	game.new_game()
	main.call("_on_game_started", true)
	await _frames(20)
	await _shot("main_2_intro")
	var intro: Node = main.get("_intro")
	for i in 3:
		intro.call("_next")
		await _frames(3)
	await _shot("main_2b_intro_last")
	intro.call("_next")
	await _frames(20)
	await _shot("main_2_start")
	var vaso := -1
	for it in game.instances():
		if String(it["item"]) == "vaso":
			vaso = int(it["id"])
			break
	game.help_instance(vaso)
	await _frames(10)
	await _shot("main_2c_after_click")
	game.debug_advance_minutes(60.0 * 24 * 3)
	await _frames(20)
	await _shot("main_3_day3")
	main.get("_drawer").call("open", "build")
	await _frames(20)
	await _shot("main_4_drawer")
	quit(0)
