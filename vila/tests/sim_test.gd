extends SceneTree
## Teste da simulação da vila: um jogador automático começa de dia e segue a meta.
## Roda: bash ../Ferramentas/godot.sh --headless --path . --script res://tests/sim_test.gd

var fails: int = 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FALHOU: ", msg)
	else:
		print("ok: ", msg)


func _bal() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))


func _auto(sim: VilaSim) -> void:
	AutoPlayer.play(sim)


func _init() -> void:
	var bal := _bal()
	var sim := VilaSim.new()
	var start := 1760000000.0 - fposmod(1760000000.0, 86400.0) + 7.0 * 3600.0   # 7h UTC
	sim.setup(bal, start, 0)
	_check(sim.people.size() == 1, "começa só com o Joaquim")
	_check(sim._first("gate").is_empty(), "começa sem estrada nem portão")
	_check(sim._count_any("moradia") == 1 and sim.beds_total() == 1, "começa com uma barraca de uma cama")
	var free0 := sim._free_build_cells()
	print("chão livre no começo: ", free0)
	_check(free0 >= 60 and free0 <= 110, "clareira do começo cabe o que a torre 1 libera (60 a 110 células livres)")
	_check(not sim.is_night(), "começa de dia")
	var t_tower2 := -1.0
	var t_ari := -1.0
	var t_group := -1.0
	var min_stock := 1e9
	var elapsed := 0.0
	while elapsed < 3.0 * 3600.0:
		sim.advance(5.0)
		elapsed += 5.0
		if t_group < 0.0 and not sim.gate_group.is_empty():
			t_group = elapsed
		_auto(sim)
		for r in VilaSim.RES:
			min_stock = minf(min_stock, float(sim.stock[r]))
		if t_tower2 < 0.0 and sim.tower >= 2:
			t_tower2 = elapsed
		if t_ari < 0.0 and sim.people.size() >= 2:
			t_ari = elapsed
		if t_group < 0.0 and not sim.gate_group.is_empty():
			t_group = elapsed
	print("chão livre depois: ", sim._free_build_cells(), " · marcados: ", sim.marked.size())
	print("torre 2 em %.1f min, 2ª pessoa em %.1f min, 1º grupo em %.1f min" % [t_tower2 / 60.0, t_ari / 60.0, t_group / 60.0])
	print("depois de 3 h: torre %d, %d pessoas, %d prédios, estoque %s" % [sim.tower, sim.people.size(), sim.buildings.size(), str(sim.stock)])
	for p in sim.people:
		print("  ", p["name"], " -> ", sim.doing(p), " ", p["passives"])
	_check(t_tower2 > 0.0 and t_tower2 < 30.0 * 60.0, "torre 2 em menos de 30 min")
	_check(not sim._first("gate").is_empty(), "a estrada e o portão aparecem na torre 2")
	_check(t_ari > 0.0, "seu Ari chega depois da torre 2")
	_check(t_group > 0.0, "chega um grupo de 3 no portão")
	_check(sim.people.size() >= 3, "pelo menos 3 pessoas em 3 h")
	_check(min_stock >= -0.001, "estoque nunca negativo (min %.2f)" % min_stock)
	# Dia e noite da vila: ciclo próprio, noite = 25%; virar a noite cansa; 2 noites de descanso por noite virada.
	var nb: Dictionary = bal["night"]
	var cyc := float(nb["cycle_s"])
	var night_s := 0.0
	var probe := VilaSim.new()
	probe.setup(bal, start, 0)
	for i in 240:
		probe.t += cyc / 240.0
		if probe.is_night():
			night_s += cyc / 240.0
	_check(absf(night_s / cyc - 0.25) < 0.02, "noite ocupa 25%% do ciclo (%.0f%%)" % (night_s / cyc * 100.0))
	var jq: Dictionary = sim.people[0]
	jq["tired"] = 0
	jq["rest"] = 0.0
	sim.set_cycle_hour(23.0)
	sim.set_work_tonight(true)
	sim.advance(cyc * 0.25)   # passa a noite inteira trabalhando
	_check(int(jq["tired"]) == 1 and not sim.work_tonight, "virar a noite cansa 1 e só vale para aquela noite")
	_check(absf(sim.rest_mult(jq) - (1.0 - float(nb["tired_penalty"]))) < 0.001, "cansado produz 10% a menos")
	sim.advance(cyc)
	_check(int(jq["tired"]) == 1, "1 noite de descanso ainda não recupera")
	sim.advance(cyc)
	_check(int(jq["tired"]) == 0 and sim.rest_mult(jq) == 1.0, "2 noites de descanso recuperam a produção normal")
	# Desmontar: libera o chão, devolve metade e não deixa mexer no bunker nem na torre.
	var pc: Dictionary = sim._first("poco")
	var cell0: Vector2i = pc["cell"]
	var n_b: int = sim.buildings.size()
	_check(bool(sim.demolish(int(pc["id"]))["ok"]) and sim.buildings.size() == n_b - 1 and sim.building_at(cell0).is_empty(), "desmontar tira o prédio e libera o chão")
	_check(not bool(sim.demolish(int(sim._first("hatch")["id"]))["ok"]) and not bool(sim.demolish(int(sim.tower_building()["id"]))["ok"]), "bunker e torre não desmontam")
	# Save e load
	var d := sim.to_dict()
	var txt := JSON.stringify(d)
	var sim2 := VilaSim.new()
	sim2.from_dict(JSON.parse_string(txt), bal, 0)
	_check(sim2.people.size() == sim.people.size() and sim2.buildings.size() == sim.buildings.size(), "save/load mantém pessoas e prédios")
	_check(sim2.tower == sim.tower, "save/load mantém a torre")
	# Offline de 8 h a partir do fim da tarde: atravessa a noite e rende só uma fração.
	var before: Dictionary = sim2.stock.duplicate()
	var t0 := Time.get_ticks_msec()
	var res := sim2.catch_up(sim2.t + 8.0 * 3600.0)
	print("offline 8 h: ", res, " em ", Time.get_ticks_msec() - t0, " ms")
	_check(not res.is_empty(), "offline devolve resumo")
	var t1 := Time.get_ticks_msec()
	sim2.catch_up(sim2.t + 72.0 * 3600.0)
	print("offline 72 h em ", Time.get_ticks_msec() - t1, " ms")
	# A vila do teste chega a ~24 pessoas em 3 h (o jogador automático põe casa e corta árvore);
	# o tempo cresce com a gente. No jogo isso roda em pedaços, com o aviso "Recuperando o tempo".
	_check(Time.get_ticks_msec() - t1 < 16000, "offline de 72 h em menos de 16 s (%d pessoas)" % sim2.people.size())
	for r in VilaSim.RES:
		_check(float(sim2.stock[r]) <= sim2.cap(r) + 0.01, "offline respeita o depósito (%s)" % r)
	# Mandar cortar uma árvore: alguém vai lá e ela não volta.
	var cut := VilaSim.new()
	cut.setup(bal, start, 0)
	var tree := Vector2i(-1, -1)
	var bd := 1e9
	for c in cut._forage_cells(VilaSim.T_TREE):
		var dd := Vector2(c).distance_to(cut.center())
		if dd < bd and cut._reachable_neighbor(c):
			bd = dd
			tree = c
	_check(cut.toggle_mark(tree), "dá para marcar uma árvore")
	var waited := 0.0
	while waited < 600.0 and cut.terrain_at(tree) == VilaSim.T_TREE:
		cut.advance(5.0)
		waited += 5.0
	_check(cut.terrain_at(tree) == VilaSim.T_STUMP and not cut.regrow.has(tree), "a árvore marcada é cortada em %ds e não volta" % int(waited))
	# Limite estilo Clash: 2 hortas na torre 1, +1 por nível; fogueira só uma.
	var lim := VilaSim.new()
	lim.setup(bal, start, 0)
	for r in VilaSim.RES:
		lim.stock[r] = 200.0
	for i in 4:
		lim.build("horta", AutoPlayer.spot(lim, "horta"))
	_check(lim._count_any("horta") == 2, "torre 1 deixa ter só 2 hortas")
	_check(String(lim.build("horta", AutoPlayer.spot(lim, "horta"))["reason"]) == "limit", "a 3ª horta é recusada pelo limite")
	lim.tower = 2
	_check(lim.limit("horta") == 3 and not lim.at_limit("horta"), "torre 2 libera a 3ª horta")
	lim.build("fogueira", AutoPlayer.spot(lim, "fogueira"))
	_check(lim.at_limit("fogueira") and lim.limit("fogueira") == 1, "fogueira só uma")
	# Relógio mostrado no padrão dos jogos: dia das 6h às 19h, noite das 19h às 6h; 21h é noite.
	var clk := VilaSim.new()
	clk.setup(bal, start, 0)
	var dark_ok := true
	var prev := -1.0
	var jumps := 0
	for i in 480:
		clk.t += cyc / 480.0
		var dh := clk.display_hour()
		if (dh >= 18.0 or dh < 6.0) != clk.is_night() and absf(dh - 18.0) > 0.05 and absf(dh - 6.0) > 0.05:
			dark_ok = false
		if prev >= 0.0 and fposmod(dh - prev, 24.0) > 0.5:
			jumps += 1
		prev = dh
	_check(dark_ok and jumps == 0, "relógio: noite das 18h às 6h, sem pulos (%d)" % jumps)
	# Várias noites: o dia avança 1 a cada amanhecer e nunca volta.
	var dn := VilaSim.new()
	dn.setup(bal, start, 0)
	var d_first := dn.day_number()
	var d_prev := d_first
	var back := false
	for i in 4 * 96:
		dn.t += cyc / 96.0
		var dd := dn.day_number()
		if dd < d_prev:
			back = true
		d_prev = dd
	_check(d_first == 1 and d_prev == 5 and not back, "4 ciclos depois é o dia 5, sem voltar (%d)" % d_prev)
	# A noite para tudo.
	var night := VilaSim.new()
	night.setup(bal, start, 0)
	night.set_cycle_hour(23.0)
	_check(night.is_night(), "23h na vila é noite")
	night.stock["madeira"] = 50.0
	night.build("poco", AutoPlayer.spot(night, "poco"))
	night.advance(float(bal["night"]["cycle_s"]) * 4.5 / 24.0)   # até perto das 4h, ainda noite
	var pb: Dictionary = night.buildings[night.buildings.size() - 1]
	_check(String(pb["state"]) == "site" and float(pb["progress"]) == 0.0, "obra não anda de noite")
	_test_orders()
	print("FALHAS: ", fails)
	quit(1 if fails > 0 else 0)


## Clique direito: mandar alguém trabalhar num prédio, cortar uma árvore, ir até um lugar.
func _test_orders() -> void:
	var sim := VilaSim.new()
	var start := 1760000000.0 - fposmod(1760000000.0, 86400.0) + 7.0 * 3600.0
	sim.setup(_bal(), start, 0)
	sim.set_cycle_hour(10.0)
	for r in VilaSim.RES:
		sim.stock[r] = 0.0
	sim.stock["madeira"] = 50.0
	sim.stock["sucata"] = 50.0
	var cell := Vector2i(-1, -1)
	for y in sim.h:
		for x in sim.w:
			if cell.x < 0 and sim.can_place("poco", Vector2i(x, y)):
				cell = Vector2i(x, y)
	var r: Dictionary = sim.build("poco", cell)
	_check(bool(r["ok"]), "ordens: poço posto")
	var poco := sim.building_at(cell)
	sim._finish(poco)
	var jo: Dictionary = sim.people[0]
	sim._set_job(jo, {"kind": "idle"})
	var o := sim.order(int(jo["id"]), cell)
	_check(bool(o["ok"]) and String(jo["job"]["kind"]) == "work" and bool(jo["job"]["manual"]), "ordens: clique direito no poço manda trabalhar lá")
	sim.marked[Vector2i(0, 0)] = true   # ordem automática que antes roubava a pessoa
	sim.advance(60.0)
	_check(String(jo["job"].get("kind", "")) == "work" and int(jo["job"].get("b", -1)) == int(poco["id"]), "ordens: continua no poço depois de 1 min")
	sim.marked.clear()
	var tree := Vector2i(-1, -1)
	var bd := 1e9
	for y in sim.h:
		for x in sim.w:
			var c := Vector2i(x, y)
			if sim.terrain_at(c) == VilaSim.T_TREE and sim._reachable_neighbor(c):
				var d := Vector2(c).distance_squared_to(Vector2(jo["pos"]))
				if d < bd:
					bd = d
					tree = c
	sim.stock["madeira"] = 0.0
	o = sim.order(int(jo["id"]), tree)
	_check(bool(o["ok"]) and String(jo["job"]["kind"]) == "forage" and jo["target_cell"] == tree, "ordens: clique direito na árvore manda cortar aquela árvore")
	sim.advance(40.0)
	_check(sim.terrain_at(tree) != VilaSim.T_TREE, "ordens: a árvore foi cortada")
	var ground := Vector2i(-1, -1)
	for y in sim.h:
		for x in sim.w:
			var g := Vector2i(x, y)
			if ground.x < 0 and sim.terrain_at(g) == VilaSim.T_GROUND and sim.building_at(g).is_empty() and not sim._astar.is_point_solid(g):
				ground = g
	o = sim.order(int(jo["id"]), ground)
	_check(bool(o["ok"]) and String(jo["job"]["kind"]) == "move", "ordens: clique direito no chão só move")
	sim.advance(30.0)
	_check(Vector2(jo["pos"]).distance_to(Vector2(ground)) < 0.6 or String(jo["job"].get("kind", "")) != "move", "ordens: chegou onde clicou")
	sim.set_cycle_hour(23.0)
	o = sim.order(int(jo["id"]), cell)
	_check(not bool(o["ok"]) and String(o["reason"]) == "night", "ordens: de noite diz que todo mundo dorme")
