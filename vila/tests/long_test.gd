extends SceneTree
## Vila do começo ao fim com o jogador automático: torre 5, a viagem e ela chegando.
## Roda: godot --headless --path . --script res://tests/long_test.gd

var fails: int = 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FALHOU: ", msg)
	else:
		print("ok: ", msg)


func _init() -> void:
	var bal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	bal["time"]["step_s"] = 2.0   # passo grosso: o teste atravessa dias de jogo
	var sim := VilaSim.new()
	var start := 1760000000.0 - fposmod(1760000000.0, 86400.0) + 7.0 * 3600.0
	sim.setup(bal, start, 0)
	var lines: Array = []
	var merchants := [0]
	var ela := [false]
	sim.radio.connect(func(l: Dictionary) -> void: lines.append(l["id"]))
	sim.merchant_arrived.connect(func() -> void: merchants[0] += 1)
	sim.ela_arrived.connect(func() -> void: ela[0] = true)
	var t_tower := {}
	var el := 0.0
	var min_stock := 1e9
	var t0 := Time.get_ticks_msec()
	while el < 30.0 * 86400.0 and not ela[0]:
		sim.advance(30.0)
		el += 30.0
		AutoPlayer.play(sim)
		if not t_tower.has(sim.tower):
			t_tower[sim.tower] = el
			var tf := FileAccess.open("user://long_t%d.json" % sim.tower, FileAccess.WRITE)
			tf.store_string(JSON.stringify(sim.to_dict()))
			tf.close()
			print("torre %d em %.1f h (dia %d) · %d pessoas · %s" % [sim.tower, el / 3600.0, sim.day_number(), sim.people.size(), str(sim.stock)])
		for r in VilaSim.RES:
			min_stock = minf(min_stock, float(sim.stock[r]))
		if int(el) % 21600 == 0:
			var g := sim.goal()
			print("  %.0f h: torre %d, %d pessoas, energia %s, meta %s, estoque %s" % [el / 3600.0, sim.tower, sim.people.size(), str(sim.power()), str(g.get("kind")), str(sim.stock)])
	var sp := "user://long_end.json"
	var f := FileAccess.open(sp, FileAccess.WRITE)
	f.store_string(JSON.stringify(sim.to_dict()))
	f.close()
	print("save do fim em ", ProjectSettings.globalize_path(sp))
	print("simulou %.1f dias em %d ms" % [el / 86400.0, Time.get_ticks_msec() - t0])
	print("falas: ", lines.size(), " ", lines)
	print("mercador veio ", merchants[0], " vezes; perks ", sim.perks)
	var cnt := {}
	for b in sim.buildings:
		cnt[b["type"]] = int(cnt.get(b["type"], 0)) + 1
	print("prédios: ", cnt)
	for p in sim.people:
		print("  ", p["name"], " ", p["story"])
	_check(sim.tower == 5, "chega na torre 5")
	_check(t_tower.has(3) and t_tower[3] < 12.0 * 3600.0, "torre 3 no primeiro meio dia")
	_check(merchants[0] > 0, "o mercador aparece")
	_check(sim._count_any("oficina") > 0 and sim._count_any("gerador") > 0, "oficina e gerador construídos")
	_check(ela[0], "ela chega")
	_check(lines.has("l2_arrival") and lines.has("t10"), "o rádio toca a torre 2 e a viagem inteira")
	_check(min_stock >= -0.001, "estoque nunca negativo (min %.2f)" % min_stock)
	_check(String(sim.goal()["kind"]) != "journey", "depois dela a meta não fala mais da viagem")
	for st in sim.bal["story_order"]:
		var found := false
		for p in sim.people:
			if String(p["story"]) == String(st):
				found = true
		_check(found, "a pessoa da história %s chegou" % st)
	var d: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var s2 := VilaSim.new()
	s2.from_dict(d, bal, 0)
	_check(s2.ela_t == sim.ela_t and s2.radio_heard.size() == sim.radio_heard.size() and s2.tower_t.size() == sim.tower_t.size(), "save/load guarda rádio, torre e final")
	print("FALHAS: ", fails)
	quit(1 if fails > 0 else 0)
