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
	_check(not sim._first("gate").is_empty(), "começa com o porto")
	var wat := 0
	for i in sim.terrain.size():
		if sim.terrain[i] == VilaSim.T_WATER:
			wat += 1
	_check(wat > 0 and sim.terrain_at(Vector2i(0, 0)) == VilaSim.T_WATER and not sim.cell_ok(Vector2i(0, 0)), "ilha: água em volta, não se constrói nela")
	var gd := sim._door(sim._first("gate"))
	_check(sim.terrain_at(gd) != VilaSim.T_WATER, "o porto tem saída por terra")
	# Quem chega pelo bote precisa conseguir andar do píer até a vila (antes ficava preso na mata).
	var from := Vector2i(int(sim.bal["arrivals"]["walk_in_from"][0]), int(sim.bal["arrivals"]["walk_in_from"][1]))
	var hd := sim._door(sim._first("hatch"))
	var pth := sim._path(Vector2(from), hd)
	_check(pth.size() > 2 and Vector2i(pth[pth.size() - 1]) == hd, "porto: tem caminho a pé do píer até a escotilha")
	# Nada que dê para construir fecha o caminho do porto.
	var sc := VilaSim.new()
	sc.setup(bal, start, 0)
	sc.stock["madeira"] = 999.0
	sc.stock["sucata"] = 999.0
	var cut_seen := false
	for i in range(1, pth.size() - 1):
		var pc := Vector2i(pth[i])
		for ty in ["poco", "deposito", "moradia"]:
			var why := sc.place_reason(ty, pc)
			cut_seen = cut_seen or why == "cuts"
			if why == "" and sc.unlocked(ty) and not sc.at_limit(ty):
				sc.build(ty, pc)
	sc._rebuild_astar()
	_check(not sc._path(Vector2(from), hd).is_empty(), "porto: construir na trilha nunca fecha o caminho%s" % (" (bloqueou %s)" % "cuts" if cut_seen else ""))
	# Corredor: prédio grande não cola em outro (uma célula livre em volta).
	var tent: Dictionary = sc._first("moradia")
	_check(sc.place_reason("poco", Vector2i(tent["cell"]) + Vector2i(-2, 0)) == "tight", "prédio colado em outro não pode (corredor de 1 célula)")
	_check(sc.place_reason("deco_vaso", Vector2i(tent["cell"]) + Vector2i(-1, 0)) != "tight", "enfeite pode encostar")
	# Sem caminho até o alvo: não trabalha de longe, larga a tarefa.
	var sw := VilaSim.new()
	sw.setup(bal, start, 0)
	var jw: Dictionary = sw.people[0]
	jw["pos"] = Vector2(hd)
	var tgt := hd + Vector2i(5, 0)
	for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1)]:
		sw._astar.set_point_solid(tgt + o, true)
	sw._set_job(jw, {"kind": "move", "cell": tgt})
	var walked := false
	for k in 40:
		if String(jw["job"].get("kind", "idle")) == "idle":
			break
		walked = sw._walk(jw, 0.1) or walked
	_check(not walked and Vector2(jw["pos"]).distance_to(Vector2(tgt)) > 1.0 and String(jw["job"].get("kind", "idle")) == "idle", "sem caminho: não chega de longe e larga a tarefa")
	# Ilhado pela mata (como no porto): abre trilha até a escotilha.
	var sr := VilaSim.new()
	sr.setup(bal, start, 0)
	var jr: Dictionary = sr.people[0]
	var at := hd + Vector2i(0, 4)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cc := at + Vector2i(dx, dy)
			if (absi(dx) == 2 or absi(dy) == 2) and sr.terrain_at(cc) != VilaSim.T_WATER and sr.building_at(cc).is_empty():
				sr.terrain[sr._i(cc)] = VilaSim.T_TREE
	sr._rebuild_astar()
	jr["pos"] = Vector2(at)
	sr._set_job(jr, {"kind": "move", "cell": hd})
	_check(not (jr["path"] as PackedVector2Array).is_empty(), "cercado pela mata: abre trilha e sai andando")
	_check(sim._count_any("moradia") == 1 and sim.beds_total() == 1, "começa com uma barraca de uma cama")
	_check(sim.home_of(sim.people[0]) == int(sim._first("moradia")["id"]), "Joaquim dorme na barraca")
	var free0 := sim._free_build_cells()
	print("chão livre no começo: ", free0)
	_check(free0 >= 100 and free0 <= 200, "clareira do começo cabe o que a torre 1 libera (100 a 200 células livres)")
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
	_check(not sim.gate_group.is_empty() or sim.people.size() > 1, "na torre 2 o bote traz gente ao porto")
	_check(t_ari > 0.0, "seu Ari chega depois da torre 2")
	var homes_ok := true
	for b in sim.buildings:
		if String(b["type"]) == "moradia" and sim.residents(b).size() > sim._beds_of(b):
			homes_ok = false
	var housed := 0
	for p in sim.people:
		if sim.home_of(p) >= 0:
			housed += 1
	_check(homes_ok and housed == mini(sim.people.size(), sim.beds_total()), "cada moradia tem no máximo as camas dela, e toda cama livre tem dono")
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
	# Névoa de pólen: avisada de dia, ninguém vira a noite, sem cama acorda cansado, e a horta rende mais depois.
	var fz := VilaSim.new()
	fz.setup(bal, start, 0)
	fz.set_cycle_hour(17.0)
	fz.fog_next = true
	var nobed: Dictionary = fz._add_person("Sem Cama", 0, [], Vector2i(fz.bal["map"]["hatch"][0], fz.bal["map"]["hatch"][1]) + Vector2i(0, 2))
	fz._assign_homes()
	var fm0 := fz.food_mult()
	var guard := 0
	while not fz.is_night() and guard < 2000:
		fz.advance(5.0)
		guard += 1
	fz.advance(5.0)
	fz.set_work_tonight(true)
	_check(fz.fog_now and not fz.work_tonight, "névoa: chega com a noite e ninguém vira a noite")
	guard = 0
	while fz.is_night() and guard < 4000:
		fz.advance(5.0)
		guard += 1
	fz.advance(5.0)
	_check(not fz.fog_now and int(nobed["tired"]) >= 1 and fz.home_of(nobed) < 0, "névoa: quem dormiu sem cama acorda cansado")
	_check(fz.food_mult() > fm0, "névoa: depois dela a horta rende mais")
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
	_test_rarity()
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
	# Quem é bom em água fica no poço (com comida em dia); com comida acabando, vai para a comida.
	var old_pas: Array = jo["passives"]
	jo["passives"] = [{"id": "agua", "rar": "rara"}]
	sim.stock["comida"] = 40.0
	sim.stock["agua"] = 10.0
	sim._m_urg.clear()
	var pj := sim._pick_job(jo)
	_check(String(pj.get("res", "")) == "agua" and String(pj.get("why", "")) == "skill", "habilidade: bom em água prefere o poço (%s)" % str(pj))
	# Obra nova: vai quem é bom de obra; o bom em água fica no poço.
	var bq: Dictionary = sim._add_person("Teste", 0, [{"id": "obra", "rar": "rara"}], Vector2i(cell) + Vector2i(0, 3))
	var c2 := AutoPlayer.spot(sim, "poco")
	sim.stock["madeira"] = 50.0
	sim.stock["sucata"] = 50.0
	sim.build("poco", c2)
	sim._m_urg.clear()
	var pj_w := sim._pick_job(jo)
	var pj_b := sim._pick_job(bq)
	_check(String(pj_b.get("kind", "")) == "build" and String(pj_w.get("kind", "")) != "build", "obra: vai quem é bom de obra, o da água fica (%s / %s)" % [str(pj_b), str(pj_w)])
	sim.demolish(-1)
	for b2 in sim.buildings.duplicate():
		if String(b2["state"]) == "site":
			sim._mark(b2, false)
			sim.buildings.erase(b2)
	sim.people.erase(bq)
	sim._invalidate()
	sim._rebuild_astar()
	jo["passives"] = old_pas
	sim.stock["comida"] = 0.0
	sim.stock["agua"] = 0.0
	sim._m_urg.clear()
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
	# Até 3 na mesma obra: o segundo mandado vira ajudante e a obra anda mais rápido.
	for r3 in VilaSim.RES:
		sim.stock[r3] = 0.0
	sim.stock["madeira"] = 50.0
	sim.stock["sucata"] = 50.0
	var hc := Vector2i(-1, -1)
	for y in sim.h:
		for x in sim.w:
			if hc.x < 0 and sim.can_place("deposito", Vector2i(x, y)):
				hc = Vector2i(x, y)
	sim.build("deposito", hc)
	var site := sim.building_at(hc)
	var other := sim._add_person("Teste", 1, [], Vector2i(jo["pos"]))
	sim.order(int(jo["id"]), hc)
	var eta1 := sim.site_eta(site)
	var oh := sim.order(int(other["id"]), hc)
	_check(bool(oh["ok"]) and (site["helpers"] as Array).has(int(other["id"])) and int(site["builder"]) == int(jo["id"]), "obra: segundo mandado entra como ajudante")
	_check(sim.site_eta(site) < eta1 * 0.6, "obra: com ajudante a obra termina mais cedo")
	sim.advance(120.0)
	_check(String(site["state"]) == "built" and (site["helpers"] as Array).is_empty(), "obra: pronta e ajudantes liberados")
	# Torre 2: serraria e ferro-velho também aceitam a ordem.
	sim.tower = 2
	sim._open_area(2)
	for tp in ["serraria", "ferrovelho"]:
		for r2 in VilaSim.RES:
			sim.stock[r2] = 0.0
		sim.stock["madeira"] = 60.0
		sim.stock["sucata"] = 60.0
		var bc := Vector2i(-1, -1)
		for y in sim.h:
			for x in sim.w:
				if bc.x < 0 and sim.can_place(tp, Vector2i(x, y)):
					bc = Vector2i(x, y)
		var rb: Dictionary = sim.build(tp, bc)
		var bb := sim.building_at(bc)
		if bool(rb["ok"]):
			sim._finish(bb)
		sim.stock["madeira"] = 0.0
		sim.stock["sucata"] = 0.0
		o = sim.order(int(jo["id"]), bc + Vector2i(1, 0))
		_check(bool(rb["ok"]) and bool(o["ok"]) and String(jo["job"]["kind"]) == "work" and int(jo["job"]["b"]) == int(bb["id"]), "ordens: clique direito em %s manda trabalhar lá" % tp)
	sim.set_cycle_hour(23.0)
	o = sim.order(int(jo["id"]), cell)
	_check(not bool(o["ok"]) and String(o["reason"]) == "night", "ordens: de noite diz que todo mundo dorme")


## Raro é ocasião, não regra; e ninguém no portão é só pior que os outros.
func _test_rarity() -> void:
	var sim := VilaSim.new()
	var start := 1760000000.0 - fposmod(1760000000.0, 86400.0) + 7.0 * 3600.0
	sim.setup(_bal(), start, 0)
	sim.tower = 2   # referência: antena 2 tem os pesos do balance sem multiplicar
	var groups := 2000
	var with_rare := 0
	var with_exc := 0
	var fair := true
	for g in groups:
		sim._make_group()
		var gr := false
		var ge := false
		for c in sim.gate_group:
			var power := 0
			var exc := false
			for ps in c["passives"]:
				power += {"comum": 1, "rara": 2, "excelente": 3}[String(ps["rar"])]
				exc = exc or String(ps["rar"]) == "excelente"
				gr = gr or String(ps["rar"]) != "comum"
			ge = ge or exc
			var nb: int = (c["brings"] as Dictionary).size()
			if (power == 1 and nb != 2) or (power == 2 and nb != 1) or (power >= 3 and nb != 0) or (exc != (float(c["eat_mult"]) > 1.0)):
				fair = false
		with_rare += 1 if gr else 0
		with_exc += 1 if ge else 0
	var fr := float(with_rare) / groups
	var fe := float(with_exc) / groups
	print("grupos com raro ou melhor: %.0f%%, com excelente: %.0f%%" % [fr * 100.0, fe * 100.0])
	_check(fr > 0.25 and fr < 0.5, "raridade: raro ou melhor em menos da metade dos grupos (era ~75%)")
	_check(fe < 0.12, "raridade: excelente em menos de 12% dos grupos")
	_check(fair, "raridade: fraco traz recursos, forte não traz, excelente come mais")
	# A antena melhora quem chega: na 5 vem mais raro que na 1.
	var rare_at := {}
	for tw in [1, 5]:
		sim.tower = tw
		var n := 0
		for g in 1500:
			sim._make_group()
			for c in sim.gate_group:
				for ps in c["passives"]:
					if String(ps["rar"]) != "comum":
						n += 1
		rare_at[tw] = n
	print("passivas raras ou melhores em 1500 grupos: antena 1 = %d, antena 5 = %d" % [rare_at[1], rare_at[5]])
	_check(int(rare_at[5]) > int(rare_at[1]) * 2, "raridade: antena 5 traz bem mais raro que a antena 1")
	# Chega gente desde a antena 1, com espera menor a cada nível.
	sim.tower = 1
	var cd1 := sim.group_cooldown()
	sim.tower = 5
	_check(sim.group_cooldown() < cd1, "porto: antena mais alta encurta a espera entre grupos")
	var s1 := VilaSim.new()
	s1.setup(_bal(), start, 0)
	s1.set_cycle_hour(8.0)
	s1._first("moradia")["level"] = 2   # sobra cama já na antena 1
	s1._invalidate()
	s1.advance(240.0)
	_check(s1.tower == 1 and s1.beds_free() > 0 and not s1.gate_group.is_empty(), "porto: com cama livre chega gente já na antena 1")
	# Escolher sozinho: com cama livre, o grupo entra sem esperar o jogador.
	sim.auto_pick = true
	sim.tower = 2
	sim._make_group()
	var pick := sim.best_pick()
	var nm := String(sim.gate_group[pick]["name"])
	sim.stock["madeira"] = 0.0
	for b in sim.buildings:
		if String(b["type"]) == "moradia":
			b["level"] = 3
	sim._invalidate()
	for k in 5:   # pessoas da história chegam antes, uma por vez
		if not sim.gate_group.is_empty():
			sim._arrivals()
	var joined := false
	for p in sim.people:
		joined = joined or String(p["name"]) == nm
	_check(sim.gate_group.is_empty() and joined, "portão: escolher sozinho põe quem mais ajuda pra dentro")
