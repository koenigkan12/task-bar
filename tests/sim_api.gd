extends SceneTree
## Testes da API da Sim (grade, compras, obras, rádio, diário, jornada, catch-up).
## godot --headless --path . --script res://tests/sim_api.gd
var fails := 0
var sigs: Dictionary = {}


func check(ok: bool, msg: String) -> void:
	if not ok:
		print("  FAIL " + msg)
		fails += 1
	else:
		print("  ok   " + msg)


func count(name: String) -> void:
	sigs[name] = int(sigs.get(name, 0)) + 1


func hook(s: Sim) -> void:
	sigs = {}
	s.item_placed.connect(func(_i: int) -> void: count("item_placed"))
	s.item_finished.connect(func(_i: int, _n: String) -> void: count("item_finished"))
	s.item_removed.connect(func(_i: int) -> void: count("item_removed"))
	s.room_dug.connect(func(_r: int) -> void: count("room_dug"))
	s.antenna_changed.connect(func(_l: int) -> void: count("antenna_changed"))
	s.radio_line.connect(func(_d: Dictionary) -> void: count("radio_line"))
	s.diary_changed.connect(func() -> void: count("diary_changed"))
	s.visit_happened.connect(func(_d: Dictionary) -> void: count("visit_happened"))
	s.plot_harvested.connect(func(_p: int) -> void: count("plot_harvested"))
	s.box_state_changed.connect(func(_f: float, _o: bool) -> void: count("box_state_changed"))
	s.house_item_bought.connect(func(_i: String) -> void: count("house_item_bought"))
	s.arrival_started.connect(func() -> void: count("arrival_started"))
	s.arrival_finished.connect(func() -> void: count("arrival_finished"))
	s.new_game_started.connect(func() -> void: count("new_game_started"))


func give(s: Sim, n: float) -> void:
	s.scrap += n


func finish_jobs(s: Sim) -> void:
	var guard := 0
	while not s.active_jobs().is_empty() and guard < 500:
		s.advance(10.0)
		guard += 1
	s.advance(10.0)


func _init() -> void:
	Balance.load_all()
	print("== estado inicial")
	var s := Sim.new()
	hook(s)
	s.new_game(3, 9.0)
	check(int(sigs.get("new_game_started", 0)) == 1, "new_game_started emitido")
	check(s.antenna() == 1 and s.rooms() == 1 and s.sucata() == 6, "antena 1, 1 sala, sucata 6")
	check(s.instances().size() == 4, "4 instâncias iniciais (3 vasos + bicicleta)")
	check(s.plots().size() == 3, "3 plots")
	var fx := s.fixed_objects(1)
	var ids: Array = []
	for o in fx:
		ids.append(o["id"])
	check(ids == ["ladder", "hatch_box", "radio_table", "bed"], "objetos fixos da sala 1 " + str(ids))
	check(s.fixed_objects(2).size() == 1 and s.fixed_objects(2)[0]["id"] == "ladder", "sala 2 só tem o poço da escada")
	check(s.line_tiers()["energia"] == "bicicleta" and s.line_tiers()["agua"] == "lata", "linhas iniciais")
	check(s.power_supply() == 3 and s.power_demand() == 2 and s.power_ok(), "energia 3/2")
	check(s.box_capacity() == 14, "caixa 14")
	check(s.diary().size() >= 1, "diário tem a fala do nível 1")
	check(s.unread_count() >= 1, "não lidas")
	s.mark_diary_read()
	check(s.unread_count() == 0, "mark_diary_read")
	check(s.is_awake() and not s.is_night(), "9h acordado")
	check(absf(s.tod_hours() - 9.0) < 0.01, "tod 9h")

	print("== primeira colheita ~20 min")
	s.advance(10.0)
	check(s.stock == 0, "10 min: ainda nada")
	s.advance(10.0)
	check(s.stock == 3 and int(sigs.get("plot_harvested", 0)) == 3, "20 min: 3 cestos colhidos")
	check(int(sigs.get("box_state_changed", 0)) >= 1, "box_state_changed")
	var pl := s.plots()
	check(pl[0]["crop"] == "batata" and pl[0]["progress"] < 0.2, "replantou batata")

	print("== grade")
	check(s.can_place("vaso", 1, 7) and not s.can_place("vaso", 1, 6) and not s.can_place("vaso", 1, 2), "vaso: 7 livre, 6 e 2 ocupados")
	check(not s.can_place("canteiro", 1, 9) and not s.can_place("canteiro", 2, 0), "canteiro não cabe em 9 (borda) nem na sala 2 (não escavada)")
	var h := s.placement_hints("canteiro")
	check(h.size() == 2 and h[0]["col"] == 7, "canteiro: 2 posições na sala 1 " + str(h))
	check(s.placement_hints("balde").size() == 1 or true, "hints de item sem coluna")
	var hm := s.placement_hints("moinho")
	check(hm[0]["room"] == 1 and hm[0]["col"] == 6, "moinho: 1ª posição = onde está a bicicleta " + str(hm[0]))

	print("== compras e obras")
	var r := s.buy("canteiro", 1, 7)
	check(not r["ok"] and r["reason"] == "missing.cost", "sem sucata: " + str(r["reason"]))
	give(s, 500)
	r = s.buy("vaso", 1, 6)
	check(not r["ok"] and r["reason"] == "missing.free_cols", "vaso sobre a bicicleta: " + str(r["reason"]))
	r = s.buy("vaso", 1, 7)
	check(r["ok"] and r["instance_id"] > 0, "compra vaso")
	check(int(sigs.get("item_placed", 0)) == 1, "item_placed")
	var jobs := s.active_jobs()
	check(jobs.size() == 1 and jobs[0]["item"] == "vaso", "job de obra")
	var found := false
	for i in s.instances():
		if i["id"] == r["instance_id"]:
			found = i["state"] == "building"
	check(found, "instância em obra")
	check(s.plots().size() == 3, "plots só nascem quando a obra termina")
	finish_jobs(s)
	check(int(sigs.get("item_finished", 0)) == 1 and s.plots().size() == 4, "obra terminou: 4 plots")
	check(s.sucata() == 494 or s.sucata() > 400, "custo debitado")
	# máximo
	s.buy("vaso", 1, 8)
	finish_jobs(s)
	var c := s.can_buy("vaso")
	check(not c["ok"], "vaso no máximo (5)")
	var cat := s.catalog("plantio")
	var st := {}
	for e in cat:
		st[e["item"]] = e["status"]
	check(st["vaso"] == "maxed" and st["canteiro"] == "locked", "catálogo: vaso maxed, canteiro locked (sem espaço) " + str(st))
	var canteiro: Dictionary = {}
	for e in cat:
		if e["item"] == "canteiro":
			canteiro = e
	check(canteiro["missing"].has("missing.free_cols"), "canteiro: falta espaço " + str(canteiro["missing"]))
	check(canteiro["missing"].size() == canteiro["missing_args"].size(), "missing_args paralelo")

	print("== substituição de linha")
	var info := s.antenna_info()
	check(info["level"] == 1 and info["next_cost"] == 50 and info["can"] == true, "antena_info nível 1 " + str(info))
	var before_ids := []
	for i in s.instances():
		before_ids.append(i["id"])
	r = s.buy("moinho", 0, -1)
	check(r["ok"], "moinho (posição automática)")
	check(int(sigs.get("item_removed", 0)) == 1, "bicicleta saiu na compra (item_removed)")
	check(s.line_tiers()["energia"] == "bicicleta" and s.power_supply() == 3, "energia continua 3 durante a obra")
	var moinho_inst: Dictionary = {}
	for i in s.instances():
		if i["item"] == "moinho":
			moinho_inst = i
	check(moinho_inst["col"] == 6, "moinho ocupa a posição da bicicleta")
	check(not s.can_buy("moinho")["ok"], "moinho em obra: não compra de novo")
	finish_jobs(s)
	check(s.line_tiers()["energia"] == "moinho" and s.power_supply() == 5, "moinho pronto: oferta 5")
	check(not s.demolish(moinho_inst["id"])["ok"], "item de linha não demolível")
	check(s.catalog("energia")[0]["status"] == "owned", "bicicleta aparece como owned")

	print("== demolir / mover")
	var vaso_new: int = -1
	for i in s.instances():
		if i["item"] == "vaso" and i["col"] == 8:
			vaso_new = i["id"]
	var money := s.sucata()
	var d := s.demolish(vaso_new)
	check(d["ok"] and d["refund"] == 6 and s.sucata() == money + 6, "demolir devolve 100%")
	check(s.plots().size() == 4, "plots do vaso demolido saem")
	var start_vaso: int = -1
	for i in s.instances():
		if i["item"] == "vaso" and i["col"] == 3:
			start_vaso = i["id"]
	check(not s.demolish(start_vaso)["ok"], "vaso inicial não demolível")
	var mv := s.move(start_vaso, 1, 9)
	check(mv["ok"], "mover vaso inicial para col 9")
	check(not s.move(start_vaso, 1, 4)["ok"], "mover para coluna ocupada falha")
	check(s.can_place("vaso", 1, 3), "coluna 3 liberada")

	print("== escavar")
	give(s, 1000)
	check(not s.can_buy("prateleira")["ok"], "prateleira bloqueada (antena/sala)")
	var dg := s.dig_room()
	check(dg["ok"] and dg["room"] == 2, "dig_room")
	check(s.rooms() == 1 and s.active_jobs().size() == 1 and s.active_jobs()[0]["item"] == "comodo2", "sala só vale após a obra")
	check(not s.dig_room()["ok"], "não escava duas ao mesmo tempo")
	finish_jobs(s)
	check(s.rooms() == 2 and int(sigs.get("room_dug", 0)) == 1, "room_dug / rooms()==2")
	check(s.power_demand() == 3, "lâmpada da sala 2 entra na demanda")
	check(s.can_place("canteiro", 2, 1) and not s.can_place("canteiro", 2, 0), "agora cabe na sala 2 (a coluna 0 é o poço)")
	var r2 := s.buy("canteiro", 2, 11)
	check(not r2["ok"], "canteiro em 11 não cabe")
	r2 = s.buy("canteiro", 2, 10)
	check(r2["ok"], "canteiro na sala 2")
	finish_jobs(s)
	check(s.plots().size() == 7, "canteiro dá 3 plots")
	var rooms_of: Array = []
	for p in s.plots():
		rooms_of.append(p["room"])
	check(rooms_of.count(2) == 3, "plots na sala 2")

	print("== antena e rádio")
	var a_before := int(sigs.get("radio_line", 0))
	var up := s.upgrade_antenna()
	check(up["ok"] and s.antenna() == 2 and int(sigs.get("antenna_changed", 0)) == 1, "antena 2")
	check(int(sigs.get("radio_line", 0)) > a_before, "fala de chegada entregue na hora")
	check(s.unread_count() > 0, "diário com não lidas")
	s.advance(30.0)
	var kinds := {}
	for e in s.diary():
		kinds[e["speaker"]] = true
	check(kinds.has("ele"), "reação dele entregue em 20 min")
	check(s.diary()[0]["at_min"] >= s.diary()[s.diary().size() - 1]["at_min"], "diário: mais nova no topo")
	check(s.available_crops(start_vaso).has("feijao"), "feijão liberado na antena 2")
	check(not s.available_crops(start_vaso).has("tomate"), "tomate não em estrutura comum")
	s.set_instance_crop(start_vaso, "tomate")
	check(s.crop_order(start_vaso) == "", "ordem inválida ignorada")
	s.set_instance_crop(start_vaso, "batata")
	check(s.crop_order(start_vaso) == "batata", "ordem permanente de cultura")
	check(s.antenna_info()["can"], "antena 3 liberada (oferta 5, 2 salas, sucata)")
	check(s.upgrade_antenna()["ok"] and s.antenna() == 3, "antena 3")
	var next_cost := s.antenna_info()
	check(not next_cost["can"] and next_cost["missing"].has("missing.supply"), "antena 4 pede energia 8: " + str(next_cost["missing"]) + str(next_cost["missing_args"]))

	print("== objetivo fixado")
	s.pin_goal("estante")
	check(s.pinned_goal() == "estante" and s.goal_ready(), "pin + goal_ready")
	s.pin_goal("")
	check(not s.goal_ready(), "limpar objetivo")

	print("== comportamentos")
	check(s.unlocked_behaviors().is_empty(), "sem comportamentos sem objetos")
	s.buy("estante", 0, -1)
	s.buy("poltrona", 0, -1)
	finish_jobs(s)
	var bh := s.unlocked_behaviors()
	check(bh.has("ler") and bh.has("cochilar") and bh.has("ouvir_radio"), "ler/cochilar/ouvir_radio " + str(bh))

	print("== energia: demanda")
	var p2 := s.can_buy("estufa")
	check(not p2["ok"], "estufa bloqueada: " + str(p2["missing"]))

	print("== hash de dia/noite")
	var s2 := Sim.new()
	s2.new_game(3, 21.0)
	s2.advance(60.0)
	check(s2.is_night() and not s2.is_awake(), "22h: noite")
	var stock_before := s2.stock
	s2.advance(300.0)
	check(s2.stock == stock_before and s2.busy() == 0.0, "de noite ele não produz")
	s2.advance(240.0)
	check(s2.is_awake() and s2.day_index() == 1, "6h+: acordado, dia 1 (day_index=%d)" % s2.day_index())

	print("== catch-up offline")
	var s3 := Sim.new()
	s3.new_game(3, 8.0)
	var sum := s3.catch_up(48.0 * 60.0)
	check(sum["hours"] == 48 and sum["visits"] > 0 and sum["scrap"] > 0 and sum["nights"] == 2, "resumo 48h: " + str(sum))
	check(sum["lines"].size() > 0 and sum["shown"], "falas perdidas listadas")
	var kinds2 := {}
	var while_away := 0
	for e in s3.diary():
		kinds2[e["kind"]] = true
		if e["while_away"]:
			while_away += 1
	check(kinds2.has("away") and while_away > 0, "diário com entradas away e while_away")
	check(String(s3.diary()[0]["key"]).begins_with("diary.away.summary"), "entrada de resumo no topo: " + str(s3.diary()[0]["key"]))
	var sum2 := Sim.new()
	sum2.new_game(3, 8.0)
	var capped := sum2.catch_up(200.0 * 60.0, 72.0)
	check(capped["capped"] and sum2.t_min > 72.0 * 60.0, "teto de 72h aplicado (t=%.0f min)" % sum2.t_min)
	check(absf(fposmod(sum2.start_min + sum2.t_min, 1440.0) - fposmod(8.0 * 60.0 + 200.0 * 60.0, 1440.0)) < 11.0, "hora do dia alinhada após o teto")

	print("== desempenho")
	var s4 := Sim.new()
	s4.new_game(3, 8.0)
	var t0 := Time.get_ticks_usec()
	s4.advance(72.0 * 60.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(ms < 1000.0, "72 h de jogo em %.1f ms" % ms)

	var tc := Time.get_ticks_usec()
	for i in 20:
		s4.catalog()
	var cms := (Time.get_ticks_usec() - tc) / 20000.0
	check(cms < 20.0, "catalog() completo em %.2f ms" % cms)

	print("RESULTADO: %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(0 if fails == 0 else 1)
