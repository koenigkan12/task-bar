extends SceneTree
## Cena do bunker ligada ao Game REAL (autoload): novo jogo, avanço de tempo, compra, obra,
## escavação e volta de ausência. Com vídeo, também grava capturas (--out=<pasta>).
##   godot --headless --path . --script res://tests/view_real_game.gd
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --script res://tests/view_real_game.gd -- --out=<pasta>

const BunkerScene := preload("res://scenes/bunker/bunker.tscn")

var _fail: int = 0
var _ok: int = 0
var _out: String = ""


func _check(cond: bool, what: String) -> void:
	if cond:
		_ok += 1
	else:
		_fail += 1
		print("FALHOU: ", what)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_run.call_deferred()


func _shot(v: BunkerView, name: String) -> void:
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_texture().get_image().save_png(_out.path_join("real_%s.png" % name))


func _ready_items(g: Node) -> int:
	return g.instances().filter(func(d: Dictionary) -> bool: return BunkerArt.has(String(d["item"]))).size()


func _run() -> void:
	var g: Node = root.get_node("Game")
	g.save_path = "user://view_real_test_save.json"
	g.delete_save()
	g.set_time_scale(0.0)
	g.new_game()
	root.content_scale_size = Vector2i(608, 88)
	root.size = Vector2i(1216, 176)
	var v: BunkerView = BunkerScene.instantiate()
	v.view_width = 608
	root.add_child(v)
	await create_timer(0.6).timeout
	_check(v.link.game == g, "a cena pega o autoload Game")
	_check(v._inst.size() == _ready_items(g), "um objeto por instância visível (%d)" % v._inst.size())
	var crops := 0
	for o: BunkerObject in v._inst.values():
		crops += o._crops.size()
	_check(crops == g.plots().size(), "uma planta por plot (%d)" % crops)
	_check(v.fixed_foot("hatch_box") != null and v.fixed_foot("bed") != null, "objetos fixos")
	await _shot(v, "inicio")

	# dois dias de jogo: colheitas, visitas, sucata
	g.debug_advance_minutes(2 * 24 * 60.0)
	await create_timer(0.6).timeout
	_check(g.sucata() > 0, "sucata depois de 2 dias (%d)" % g.sucata())
	_check(v._scrap.visible, "pilha de sucata aparece")
	var tod: float = g.tod_hours()
	_check(v.man.mode == ("night" if g.is_night() else v.man.mode), "modo do homem segue a hora (%.1f h)" % tod)

	# compra: vira obra com andaime; termina e vira objeto pronto
	var hints: Array = g.placement_hints("canteiro")
	if g.sucata() < 30:
		g.debug_advance_minutes(24 * 60.0)
	var r: Dictionary = g.buy("canteiro", int(hints[0]["room"]), int(hints[0]["col"])) if not hints.is_empty() else {"ok": false}
	_check(bool(r.get("ok", false)), "compra do canteiro (%s)" % str(r))
	if r.get("ok", false):
		await create_timer(0.4).timeout
		var o: BunkerObject = v.object_by_id(int(r["instance_id"]))
		_check(o != null and o.building, "canteiro em obra")
		await create_timer(1.2).timeout
		_check(v.man.mode == "build", "homem vai martelar")
		await _shot(v, "obra")
		g.debug_advance_minutes(120.0)
		await create_timer(0.4).timeout
		_check(o != null and is_instance_valid(o) and not o.building, "obra terminou")

	# escavação: a sala nova aparece aos poucos
	for i in 6:
		if g.sucata() >= 60:
			break
		g.debug_advance_minutes(24 * 60.0)
	var d: Dictionary = g.dig_room()
	_check(bool(d.get("ok", false)), "escavação começou (%s)" % str(d))
	if d.get("ok", false):
		g.debug_advance_minutes(5.0)
		await create_timer(0.4).timeout
		_check(v._terrain.dig_room == 2, "terreno mostra a escavação")
		await _shot(v, "escavando")
		g.debug_advance_minutes(24 * 60.0)
		await create_timer(0.4).timeout
		_check(v._rooms == 2 and v._terrain.n_rooms == 2, "sala 2 escavada")
		await _shot(v, "duas_salas")

	# volta de ausência: catch-up sem sinais finos + welcome_back => a cena relê o mundo
	var before := v._inst.size()
	g.welcome_back.emit({"hours": 1})
	await create_timer(0.3).timeout
	_check(v._inst.size() == _ready_items(g) and v._inst.size() >= before, "welcome_back relê o mundo")

	v.queue_free()
	g.delete_save()
	await process_frame
	print("view_real_game: %d ok, %d falhas" % [_ok, _fail])
	quit(1 if _fail > 0 else 0)
