extends SceneTree
## Capturas da cena do bunker em estados fixos (CONTRATOS 11: tests/shot_*). Precisa de vídeo:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --script res://tests/view_shots.gd -- --out=<pasta>
## Grava <pasta>/view_<cena>.png em tamanho lógico (amplie para olhar).

const FakeGame := preload("res://tests/view_fake_game.gd")
const BunkerScene := preload("res://scenes/bunker/bunker.tscn")

var _out: String = "user://view_shots"


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _shot(name: String, w: int, setup: Callable, wait: float = 2.0, after: Callable = Callable()) -> void:
	root.content_scale_size = Vector2i(w, 88)
	root.size = Vector2i(w * 2, 88 * 2)
	var g: Node = FakeGame.new()
	root.add_child(g)
	setup.call(g)
	var v: BunkerView = BunkerScene.instantiate()
	v.game = g
	v.view_width = w
	root.add_child(v)
	v.man.seed_rng(7)
	if after.is_valid():
		after.call(g, v)
	await create_timer(wait).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _out.path_join("view_%s.png" % name)
	img.save_png(path)
	print("captura: ", path, " ", img.get_size(), " homem=", v.man.anim, "/", v.man.activity)
	v.queue_free()
	g.queue_free()
	await process_frame


func _run() -> void:
	# 1. começo: uma sala, 3 vasos e a bicicleta, manhã
	await _shot("inicio", 344, func(g: Node) -> void:
		g.s["tod"] = 9.5
		g.add("vaso", 1, 3, "batata", [1])
		g.add("vaso", 1, 4, "batata", [2])
		g.add("vaso", 1, 5, "batata", [3])
		g.add("bicicleta", 1, 6), 3.0)
	# 2. noite: dormindo, lâmpada apagada, estrelas
	await _shot("noite", 344, func(g: Node) -> void:
		g.s["tod"] = 2.0
		g.add("vaso", 1, 3, "batata", [1])
		g.add("canteiro", 1, 4, "feijao", [0, 1, 2])
		g.add("moinho", 1, 7), 3.0)
	# 3. três salas no fim da tarde, obra em andamento, caixa transbordando (sinal)
	await _shot("tres_salas", 608, func(g: Node) -> void:
		g.s.merge({"rooms": 3, "antenna": 4, "tod": 18.2, "sucata": 180, "box_fill": 1.3, "busy": 0.2,
			"behaviors": ["ler", "cochilar", "ouvir_radio", "escrever", "olhar_foto"],
			"tiers": {"plantio": "estufa", "agua": "cisterna", "energia": "bateria", "transporte": "calha"}}, true)
		g.add("canteiro", 1, 3, "feijao", [3, 2, 1])
		g.add("calha", 1, 5)
		g.add("estante", 1, 6)
		g.add("poltrona", 1, 7)
		g.add("mesinha", 1, 8)
		g.add("foto", 1, 9)
		g.add("prateleira", 2, 0, "feijao", [0, 1, 2, 3, 2])
		g.add("cisterna", 2, 3)
		g.add("bateria", 2, 6)
		g.add("estufa", 2, 9, "tomate", [1, 2, 3, 3, 2, 1])
		g.add("canteiro", 3, 0, "batata", [2, 2, 3])
		g.add("roldana", 3, 4, "batata", [], "building", 0.55)
		g.add("painel", 0, -1), 3.0)
	# 4. escavando a sala 2, sem energia (lâmpada piscando), faminto
	await _shot("escavando", 408, func(g: Node) -> void:
		g.s.merge({"tod": 13.0, "power_ok": false, "hungry": true, "sucata": 20}, true)
		g.add("vaso", 1, 3, "batata", [2])
		g.add("vaso", 1, 4, "batata", [1])
		g.add("bicicleta", 1, 6)
		g.jobs.append({"instance": -1, "item": "comodo2", "ratio": 0.45}), 4.0)
	# 5. rádio com fala nova (sinal) e objetivo pago
	await _shot("radio", 344, func(g: Node) -> void:
		g.s.merge({"tod": 16.0, "unread": 2, "antenna": 2, "sucata": 60}, true)
		g.add("vaso", 1, 3, "batata", [3])
		g.add("gotejador", 1, 4)
		g.add("vaso", 1, 5, "feijao", [2])
		g.add("moinho", 1, 6), 1.5)
	# 6. cena do final: luz descendo, ele olhando para cima
	await _shot("chegada", 608, func(g: Node) -> void:
		g.s.merge({"rooms": 3, "antenna": 5, "tod": 11.0, "contact": true,
			"tiers": {"plantio": "estufa", "agua": "bomba", "energia": "painel", "transporte": "esteira"}}, true)
		g.add("mesinha", 1, 3)
		g.add("poltrona", 1, 4)
		g.add("cama_dela", 1, 8)
		g.add("cantinho", 2, 0)
		g.add("planta_dela", 2, 2)
		g.add("cabide", 2, 3)
		g.add("foto_dela", 2, 4)
		g.add("esteira", 2, 6)
		g.add("bomba", 2, 8)
		g.add("estufa", 3, 0, "tomate", [3, 3, 2, 3, 2, 3])
		g.add("painel", 0, -1),
		4.6, func(g: Node, v: BunkerView) -> void:
			v.man.position.x = 60.0
			g.arrival_started.emit())
	# 7. epílogo de manhã: duas canecas, casa pronta
	await _shot("epilogo", 608, func(g: Node) -> void:
		g.s.merge({"rooms": 3, "antenna": 5, "tod": 7.0, "arrived": true, "contact": true,
			"behaviors": ["ler", "cochilar", "ouvir_radio", "escrever", "olhar_foto"]}, true)
		g.add("mesinha", 1, 3)
		g.add("poltrona", 1, 4)
		g.add("estante", 1, 5)
		g.add("cama_dela", 1, 8)
		g.add("cantinho", 2, 0)
		g.add("planta_dela", 2, 2)
		g.add("cabide", 2, 3)
		g.add("foto_dela", 2, 4)
		g.add("estufa", 3, 0, "tomate", [3, 2, 2, 3, 1, 3])
		g.add("painel", 0, -1), 2.0)
	quit(0)
