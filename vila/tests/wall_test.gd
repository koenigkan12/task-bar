extends SceneTree
## Cerca: os zumbis não atravessam muro em pé; com a vila fechada, quebram o muro antes de qualquer prédio.
## Roda: bash ../Ferramentas/godot.sh --headless --path . --script res://tests/wall_test.gd

var fails := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FALHOU: ", msg)
	else:
		print("ok: ", msg)


func _new_sim() -> VilaSim:
	var bal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var sim := VilaSim.new()
	var start := 1760000000.0 - fposmod(1760000000.0, 86400.0) + 7.0 * 3600.0
	sim.setup(bal, start, 0)
	sim.tower = 3
	for r in VilaSim.RES:
		sim.stock[r] = 9999.0
	for tp in ["poco", "horta", "moradia", "deposito"]:
		var rs := sim.build(tp, AutoPlayer.spot(sim, tp))
		if bool(rs.get("ok", false)):
			sim._finish(sim.buildings[sim.buildings.size() - 1])
	return sim


## Caixa que cobre todos os prédios que apanham, com 2 de folga.
func _box(sim: VilaSim) -> Rect2i:
	var r := Rect2i()
	var first := true
	for b in sim.buildings:
		if not sim.defense.attackable(b):
			continue
		var fp := sim._fp(String(b["type"]))
		var br := Rect2i(Vector2i(b["cell"]), fp)
		r = br if first else r.merge(br)
		first = false
	return r.grow(2)


func _ring(sim: VilaSim, r: Rect2i) -> int:
	var n := 0
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
			if not edge or not sim._inside(Vector2i(x, y)):
				continue
			var c := Vector2i(x, y)
			if sim.building_at(c).is_empty() and sim.terrain_at(c) != VilaSim.T_WATER:
				# Chão ocupado por árvore/entulho: limpa para o muro caber (o teste quer o anel fechado).
				sim.terrain[sim._i(c)] = VilaSim.T_GROUND
				var rs := sim.build("muro", c)
				if bool(rs.get("ok", false)):
					n += 1
				else:
					print("  muro não coube em ", c, " ", rs)
	sim._rebuild_astar()
	return n


func _run(sim: VilaSim, secs: float, label: String) -> Dictionary:
	var df := sim.defense
	df.report = {"broke": [], "ruined": [], "walls": 0, "came": 0}
	var spots := df._spawn_spots(2, 3)
	for i in 6:
		df._spawn("fraco", spots[i % spots.size()])
	var crossed := 0
	var first_hit := ""
	var hp0 := {}
	for b in sim.buildings:
		hp0[int(b["id"])] = df.hp(b)
	var t := 0.0
	while t < secs and not df.zombies.is_empty():
		df.step(0.1, true)
		t += 0.1
		for z in df.zombies:
			var c := Vector2i(Vector2(z["pos"]).round())
			var wb := sim.building_at(c)
			if not wb.is_empty() and String(wb["type"]) == "muro" and df.hp(wb) > 0.0:
				crossed += 1
		if first_hit == "":
			for b in sim.buildings:
				if df.hp(b) < float(hp0[int(b["id"])]) or bool(b.get("broken", false)):
					first_hit = String(b["type"])
					break
	print("  [%s] %.0f s, zumbis vivos %d, muros caídos %d, primeiro a apanhar: %s" % [label, t, df.zombies.size(), int(df.report.get("walls", 0)), first_hit])
	return {"crossed": crossed, "first": first_hit}


func _init() -> void:
	# 1) Vila fechada por um anel de muro.
	var sim := _new_sim()
	var n := _ring(sim, _box(sim))
	print("  anel com %d muros" % n)
	var r := _run(sim, 90.0, "anel")
	_check(int(r["crossed"]) == 0, "zumbi nunca fica em cima de muro em pé (%d vezes)" % int(r["crossed"]))
	_check(String(r["first"]) == "muro", "vila fechada: o primeiro a apanhar é o muro (foi %s)" % String(r["first"]))
	# 2) Anel em losango (só quinas na diagonal): antes o zumbi passava espremido entre duas quinas.
	var sim2 := _new_sim()
	var bx := _box(sim2)
	var ctr := bx.get_center()
	var rad := maxi(bx.size.x, bx.size.y) / 2 + bx.size.x / 2 + 1
	var n2 := 0
	for dx in range(-rad, rad + 1):
		for sgn in [-1, 1]:
			var c := ctr + Vector2i(dx, sgn * (rad - absi(dx)))
			if sim2._inside(c) and sim2.building_at(c).is_empty() and sim2.terrain_at(c) != VilaSim.T_WATER:
				sim2.terrain[sim2._i(c)] = VilaSim.T_GROUND
				if bool(sim2.build("muro", c).get("ok", false)):
					n2 += 1
	sim2._rebuild_astar()
	print("  losango com %d muros" % n2)
	var r2 := _run(sim2, 90.0, "losango")
	_check(String(r2["first"]) == "muro" or String(r2["first"]) == "", "losango: não passa pela quina, quebra o muro antes (foi %s)" % String(r2["first"]))
	# 3) Muro na frente de verdade: quanto tempo a cerca de arame segura 3 zumbis fracos.
	var sim3 := _new_sim()
	var wc := Vector2i(-1, -1)
	for b in sim3.buildings:
		if String(b["type"]) == "moradia":
			wc = Vector2i(b["cell"]) + Vector2i(0, -2)
	var df3 := sim3.defense
	df3.report = {"broke": [], "ruined": [], "walls": 0}
	sim3.terrain[sim3._i(wc)] = VilaSim.T_GROUND
	sim3.build("muro", wc)
	var wall := sim3.building_at(wc)
	var tt := 0.0
	while df3.hp(wall) > 0.0 and tt < 300.0:
		for k in 3:
			df3.hit_building(wall, float(df3.zstats("fraco")["dmg"]) * 0.1 / float(df3.zstats("fraco")["hit_s"]))
		tt += 0.1
	print("  cerca de arame segura 3 zumbis fracos por %.0f s" % tt)
	_check(tt >= 15.0, "cerca de arame segura 3 zumbis por pelo menos 15 s (%.0f s)" % tt)
	# 4) Consertar todos os muros de uma vez (como o "subir todos").
	var sim4 := _new_sim()
	_ring(sim4, _box(sim4))
	var hurt := 0
	for b in sim4.buildings:
		if String(b["type"]) == "muro" and hurt < 5:
			sim4.defense.hit_building(b, 999.0 if hurt % 2 == 0 else 10.0)
			hurt += 1
	var wf := sim4.walls_to_fix()
	_check((wf["ids"] as Array).size() == 5 and not (wf["cost"] as Dictionary).is_empty(), "lista os 5 muros com estrago e o custo total")
	var rr := sim4.repair_all_walls()
	var obras := 0
	for b in sim4.buildings:
		if bool(b.get("repair", false)):
			obras += 1
	_check(bool(rr["ok"]) and obras == 5, "consertar todos vira 5 obras de conserto (%d)" % obras)
	for b in sim4.buildings:
		if bool(b.get("repair", false)):
			sim4._finish(b)
	_check((sim4.walls_to_fix()["ids"] as Array).is_empty(), "terminadas as obras, os muros ficam inteiros")
	# Amanhecer com o jogo aberto: muro caído continua caído.
	var w0: Dictionary = {}
	for b in sim4.buildings:
		if String(b["type"]) == "muro":
			w0 = b
			break
	sim4.defense.hit_building(w0, 9999.0)
	sim4.defense.report = {"broke": [], "ruined": [], "walls": 1, "came": 0, "horde": false, "killed": 0}
	sim4.defense.night_end()
	_check(sim4.defense.hp(w0) == 0.0, "amanhecer aberto não conserta muro sozinho")
	if fails > 0:
		printerr("FALHAS: ", fails)
	else:
		print("FALHAS: 0")
	quit(1 if fails > 0 else 0)
