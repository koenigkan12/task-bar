extends SceneTree
## Teste da cena do bunker sem vídeo: sinais de atenção, clique (get_object_at), cérebro do homem,
## stub sem métodos e a cena do final chamando Game.finish_arrival() uma vez.
## Rodar: godot --headless --path . --script res://tests/view_logic_test.gd

const FakeGame := preload("res://tests/view_fake_game.gd")
const BunkerScene := preload("res://scenes/bunker/bunker.tscn")

var _fail: int = 0
var _ok: int = 0


func _check(cond: bool, what: String) -> void:
	if cond:
		_ok += 1
	else:
		_fail += 1
		print("FALHOU: ", what)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_attention()
	_test_geo()
	await _test_stub()
	await _test_clicks()
	await _test_man()
	await _test_arrival()
	print("view_logic_test: %d ok, %d falhas" % [_ok, _fail])
	quit(1 if _fail > 0 else 0)


func _test_attention() -> void:
	var a := BunkerAttention.new()
	a.update_conditions({"radio": true, "box": true, "power": false, "goal": false})
	_check(a.current == "radio", "primeiro sinal pulsa")
	a.tick(1.0)
	_check(a.current == "radio", "só um pulsando por vez")
	a.tick(BunkerAttention.PULSE_SEC)
	_check(a.current == "box", "depois de 10 s passa para o próximo")
	a.hover("box")
	_check(a.current == "", "hover para o pulso")
	a.tick(BunkerAttention.PULSE_SEC * 3)
	_check(a.current == "", "não volta sem evento novo")
	a.update_conditions({"radio": true, "box": true})
	_check(a.current == "", "condição que continua de pé não é evento")
	a.notify("radio")
	_check(a.current == "radio", "fala nova do rádio volta a pulsar")
	a.update_conditions({"radio": false})
	_check(a.current == "", "condição caiu: para")
	a.notify("radio")
	_check(a.current == "", "evento sem condição não pulsa")


func _test_geo() -> void:
	_check(BunkerGeo.strip_width(1) == 208 and BunkerGeo.strip_width(3) == 608, "W(n)")
	_check(BunkerGeo.room_col_at(Vector2(9, 70), 1) == Vector2i(1, 0), "coluna 0 da sala 1")
	_check(BunkerGeo.room_col_at(Vector2(210, 70), 2) == Vector2i(2, 0), "sala 2 começa em 208")
	_check(BunkerGeo.room_col_at(Vector2(203, 70), 2) == Vector2i(-1, -1), "divisória não é coluna")
	_check(BunkerGeo.block_foot(1, 10, 2) == Vector2(184, 80), "pés da cama")


func _make(setup: Callable) -> Array:
	var g: Node = FakeGame.new()
	root.add_child(g)
	setup.call(g)
	var v: BunkerView = BunkerScene.instantiate()
	v.game = g
	v.view_width = 608
	root.add_child(v)
	v.man.seed_rng(3)
	await process_frame
	return [g, v]


func _free(pair: Array) -> void:
	pair[1].queue_free()
	pair[0].queue_free()
	await process_frame


func _test_stub() -> void:
	# Game ainda stub: a cena abre com o estado inicial do balance.json
	var stub := Node.new()
	root.add_child(stub)
	var v: BunkerView = BunkerScene.instantiate()
	v.game = stub
	root.add_child(v)
	await create_timer(0.5).timeout
	_check(v.find_item("bicicleta") != null, "stub: bicicleta inicial aparece")
	_check(v.fixed_foot("radio_table") != null, "stub: rádio fixo aparece")
	v.queue_free()
	stub.queue_free()
	await process_frame


func _test_clicks() -> void:
	var ids := {}
	var p := await _make(func(g: Node) -> void:
		g.s["rooms"] = 2
		ids["vaso"] = g.add("vaso", 1, 3)
		ids["estufa"] = g.add("estufa", 2, 4, "tomate", [3, 3, 3, 1, 1, 1])
		ids["painel"] = g.add("painel", 0, -1))
	var v: BunkerView = p[1]
	_check(v.get_object_at(Vector2(46, 72)).get("kind") == "radio", "clique no rádio")
	_check(v.get_object_at(Vector2(32, 72)).get("kind") == "box", "clique na caixa")
	_check(v.get_object_at(Vector2(20, 26)).get("kind") == "hatch", "clique na escotilha")
	var hit := v.get_object_at(Vector2(64, 74))
	_check(hit.get("kind") == "instance" and hit.get("id") == ids["vaso"], "clique no vaso")
	hit = v.get_object_at(Vector2(BunkerGeo.col_x(2, 5), 60))
	_check(hit.get("kind") == "instance" and hit.get("id") == ids["estufa"], "clique na estufa")
	hit = v.get_object_at(Vector2(88, 20))
	_check(hit.get("kind") == "instance" and hit.get("item") == "painel", "clique no painel solar")
	hit = v.get_object_at(Vector2(BunkerGeo.col_x(2, 11) + 4, 70))
	_check(hit.get("kind") == "room" and hit.get("room") == 2 and hit.get("col") == 11, "coluna livre")
	_check(v.get_object_at(Vector2(204, 70)).is_empty(), "divisória: nada")
	var est: BunkerObject = v.object_by_id(ids["estufa"])
	_check(est._crops.size() == 6, "estufa com 6 plantas")
	# sinais de atenção vindos do estado
	p[0].s["unread"] = 1
	p[0].s["box_fill"] = 1.5
	await create_timer(0.4).timeout
	_check(v.attention.current == "radio" and v._radio_glow.visible, "rádio pulsa com fala nova")
	_check(v.attention_rect("radio").has_area(), "retângulo do rádio")
	await _free(p)


func _test_man() -> void:
	var p := await _make(func(g: Node) -> void:
		g.s["tod"] = 23.0)
	var v: BunkerView = p[1]
	await create_timer(1.2).timeout
	_check(v.man.activity == "sleep" or v.man.anim == "man_walk", "noite: vai dormir")
	var g: Node = p[0]
	g.s["tod"] = 10.0
	g.add("roldana", 1, 5, "", [], "building", 0.3)
	await create_timer(1.3).timeout
	var cur: Dictionary = v.man._cur
	var q: Array = v.man._queue
	var plan_has_hammer := String(cur.get("anim", "")) == "man_hammer" or q.any(func(s: Dictionary) -> bool: return s.get("anim", "") == "man_hammer")
	_check(v.man.mode == "build" and plan_has_hammer, "obra: martela")
	g.jobs.clear()
	g.inst[-1]["state"] = "ready"
	g.s["busy"] = 1.0
	g.add("vaso", 1, 3, "batata", [3])
	await create_timer(1.3).timeout
	_check(v.man.mode == "day", "obra acabou: volta ao dia")
	await _free(p)


func _test_arrival() -> void:
	var p := await _make(func(g: Node) -> void:
		g.s.merge({"rooms": 3, "antenna": 5, "contact": true}, true)
		g.add("mesinha", 1, 3))
	var v: BunkerView = p[1]
	var g: Node = p[0]
	v.cinematic_speed = 10.0
	v.man.position.x = 40.0
	var flags := {"cut": false, "done": false}
	v.arrival_cut.connect(func() -> void: flags["cut"] = true)
	v.arrival_scene_finished.connect(func() -> void: flags["done"] = true)
	g.arrival_started.emit()
	g.arrival_started.emit()   # repetido não reinicia
	await create_timer(0.35).timeout
	_check(v.arrival_running() and v.man.cinematic, "final: cena rodando")
	var t := 0.0
	while not flags["done"] and t < 10.0:
		await create_timer(0.1).timeout
		t += 0.1
	_check(flags["cut"] and flags["done"], "final: corte e fim da cena")
	_check(g.finish_calls == 1, "final: finish_arrival chamado uma vez")
	_check(not v.man.cinematic, "final: homem volta a decidir")
	await create_timer(0.3).timeout
	_check(v._caneca != null and v._caneca.frame == 1, "epílogo: duas canecas")
	await _free(p)
