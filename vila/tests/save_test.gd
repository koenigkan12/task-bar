extends SceneTree
## Save com cópia de segurança: grava, estraga o principal e confere que volta da cópia.
## Roda: godot --headless --path . --script res://tests/save_test.gd

var fails := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FALHOU: ", msg)
	else:
		print("ok: ", msg)


func _initialize() -> void:
	await process_frame
	var game: Node = root.get_node("Game")
	game.args = {}
	game.delete_save()
	game.prepare_title()
	game.in_game = true
	game.sim.stock["madeira"] = 7.0
	game.save_game()
	game.sim.stock["madeira"] = 9.0
	game.save_game()
	_check(FileAccess.file_exists("user://vila.json") and FileAccess.file_exists("user://vila.json.bak"), "salvar deixa o save e a cópia anterior")
	_check(not FileAccess.file_exists("user://vila.json.tmp"), "não sobra arquivo temporário")
	var f := FileAccess.open("user://vila.json", FileAccess.WRITE)
	f.store_string("{\"v\": 1, \"buildi")   # save cortado no meio
	f.close()
	game.prepare_title()
	_check(game._from_save and int(game.sim.stock["madeira"]) == 7, "save estragado volta da cópia (madeira %s)" % str(game.sim.stock["madeira"]))
	game.delete_save()
	_check(not game.has_save(), "jogo novo apaga save e cópia")
	print("FALHAS: ", fails)
	quit(1 if fails > 0 else 0)
