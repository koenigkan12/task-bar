extends SceneTree
## Aba Construir por nível de antena: cabeçalhos "Antena N", cadeado nos níveis que faltam, botão de melhorar
## visível (no topo e no cabeçalho do próximo nível) e clique na antena abrindo o menu nessa seção.
## Uso: OUT_DIR=<pasta> xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy --script res://tests/construir_antena.gd

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
	var drawer: Drawer = main.get("_drawer")
	drawer.open("build")
	await _frames(10)
	var bt: DrawerBuildTab = drawer.build_tab

	print("== lista por nível")
	var heads: Array = bt._headers.keys()
	heads.sort()
	_check(heads == [1, 2, 3, 4, 5], "cabeçalhos Antena 1..5 %s" % str(heads))
	var order: Array[String] = []
	for c in bt._list.get_children():
		order.append(String(c.name))
	_check(order.find("Item_vaso") < order.find("Item_cisterna") and order.find("Item_cisterna") < order.find("Item_bateria") and order.find("Item_bateria") < order.find("Item_painel"), "itens aparecem sob o nível que os libera")
	_check(bt.find_child("UpgradeButton", true, false) != null, "botão de melhorar existe")
	var ups: Array = bt.find_children("UpgradeButton", "Button", true, false)
	_check(ups.size() == 2, "botão no topo e no cabeçalho do próximo nível (%d)" % ups.size())
	for u: Button in ups:
		print("UP ", u.size, u.custom_minimum_size, u.size_flags_horizontal, u.get_parent().name, u.get_parent().size)
	await _shot("antena_1_menu")

	print("== com sucata o botão sobe a antena")
	game.sim.scrap = 80.0
	game.state_changed.emit()
	await _frames(10)
	var up: Button = bt.find_child("UpgradeButton", true, false)
	up.pressed.emit()
	await _frames(10)
	_check(game.antenna() == 2, "antena subiu para 2")
	var heads2: Array = bt._headers.keys()
	heads2.sort()
	_check(heads2.size() >= 4, "lista refeita com o novo nível")
	await _shot("antena_2_depois")

	print("== clique na antena abre o menu nessa seção")
	drawer.close()
	await _frames(10)
	main.call("_on_card_action", "antenna")
	await _frames(15)
	_check(drawer.is_open() and drawer.current_tab() == "build" and bt.selected_item() == DrawerBuildTab.ANTENNA, "menu abre com a antena selecionada")
	await _shot("antena_3_clique")

	print("fails=%d" % fails)
	quit(1 if fails > 0 else 0)
