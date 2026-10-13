extends SceneTree
## Teste de ritmo: bot segue o plano "equilibrada" do oráculo (adaptado à grade; ver sim_bot.gd).
## godot --headless --path . --script res://tests/sim_pace.gd
const Bot := preload("res://tests/sim_bot.gd")
const Reach := preload("res://tests/sim_reach.gd")
const U := preload("res://tests/sim_util.gd")
var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func clone(s: Sim) -> Sim:
	var c := Sim.new()
	c.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(), "", true, true)))
	return c


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(1.0, maxf(absf(a), absf(b)))


func progress_sum(s: Sim) -> float:
	var t := 0.0
	for p in s.plots():
		t += float(p["progress"])
	return t


func _init() -> void:
	Balance.load_all()
	var lo: float = Balance.num("test_targets.antenna5_day_min")
	var hi: float = Balance.num("test_targets.antenna5_day_max")
	var hint: Dictionary = Balance.val("test_targets.antenna_day_hint", {})

	print("== ritmo (começa à 0h como o oráculo, 3 check-ins/dia)")
	var s := Sim.new()
	s.new_game(7, 0.0)
	var bot := Bot.new(s)
	var t0 := Time.get_ticks_msec()
	var mid_state: Dictionary = {}
	var step := 10.0
	var reach_bad := 0
	var reach_n := 0
	var snap_day6 := false
	while s.t_min < 40.0 * 1440.0 and s.antenna() < 5:
		var before := s.tod_hours()
		s.advance(step)
		if not snap_day6 and s.t_min >= 6.0 * 1440.0:
			snap_day6 = true
			mid_state = s.to_dict()
		for c in bot.checkins:
			if absf(before - c) < step / 120.0:
				var n0 := bot.purchases.size()
				bot.check_in()
				if bot.purchases.size() > n0:
					reach_n += 1
					var r := Reach.run(s)
					if not bool(r["ok"]):
						reach_bad += 1
						print("    sem saída após ", bot.purchases[-1]["item"], ": ", r["why"])
	print("(simulado em %d ms, incluindo %d checagens de alcançabilidade)" % [Time.get_ticks_msec() - t0, reach_n])
	for p in bot.purchases:
		print("  dia %5.1f  %-12s %4d" % [p["day"], p["item"], p["cost"]])
	var d5 := s.antenna_time(5) / 1440.0 if s.antenna() >= 5 else -1.0
	check(s.antenna() == 5, "antena 5 alcançada")
	check(d5 >= lo and d5 <= hi, "antena 5 no dia %.1f dentro de [%.1f, %.1f]" % [d5, lo, hi])
	for lvl in range(2, 5):
		var dl := s.antenna_time(lvl) / 1440.0
		var h := float(hint.get(str(lvl), 0))
		check(absf(dl - h) <= maxf(1.5, h * 0.2), "marco antena %d: dia %.1f (alvo %.1f)" % [lvl, dl, h])
	var st := s.stats()
	print("  stats: visitas %d, colhidos %d, vendidos %d, perdidos %d, comidos %d, ganho %.0f, gasto %.0f" % [
			st["visits"], st["harvested"], st["sold_baskets"], st["wasted_baskets"], st["eaten"], st["scrap_earned"], st["scrap_spent"]])
	check(reach_bad == 0, "nenhuma compra do bot deixa o jogo sem saída (%d checagens)" % reach_n)
	check(int(st["wasted_baskets"]) < 20, "quase nenhum cesto perdido (%d)" % int(st["wasted_baskets"]))
	var again := Sim.new()
	again.new_game(7, 0.0)
	var bot2 := Bot.new(again)
	bot2.run(40.0)
	check(JSON.stringify(bot2.purchases) == JSON.stringify(bot.purchases), "determinismo: mesma partida, mesmas compras")

	print("== robustez do ritmo (hora de partida e cadência de check-in)")
	for tod in [6.0, 9.0, 13.0, 18.0, 21.0]:
		var sx := Sim.new()
		sx.new_game(7, tod)
		Bot.new(sx).run(40.0)
		var dx := sx.antenna_time(5) / 1440.0 if sx.antenna() >= 5 else -1.0
		check(dx >= lo - 0.5 and dx <= hi + 1.5, "partida às %2.0fh: antena 5 no dia %.1f" % [tod, dx])
	for cadence in [[18.5], [8.5, 10.5, 12.5, 14.5, 16.5, 18.5, 20.5]]:
		var sc := Sim.new()
		sc.new_game(7, 0.0)
		var bc := Bot.new(sc)
		bc.checkins.assign(cadence)
		bc.run(45.0)
		var dc := sc.antenna_time(5) / 1440.0 if sc.antenna() >= 5 else -1.0
		check(dc >= lo - 0.5 and dc <= hi + 2.5, "%d check-in(s)/dia: antena 5 no dia %.1f" % [cadence.size(), dc])

	print("== sem armadilha no começo (3 vasos + bicicleta, sem comprar nada)")
	var idle := Sim.new()
	idle.new_game(1, 9.0)
	idle.advance(20.0)
	check(idle.stock == 3, "primeira colheita em 20 min de jogo (cestos: %d)" % idle.stock)
	idle.advance(3.0 * 1440.0)
	var ist := idle.stats()
	check(float(ist["scrap_earned"]) >= 50.0, "3 dias parado rendem %.0f (>= 50: dá para a antena 2)" % float(ist["scrap_earned"]))
	check(not idle.hungry(), "não passa fome sozinho")

	print("== offline == online (3 dias a partir do dia 6)")
	var a := Sim.new()
	a.from_dict(mid_state)
	var b := Sim.new()
	b.from_dict(mid_state)
	var c := Sim.new()
	c.from_dict(mid_state)
	a.advance(72.0 * 60.0)
	for i in 72:
		b.advance(60.0)
	var sum := c.catch_up(72.0 * 60.0)
	for pair in [["avanço único", a], ["72 x 60 min", b], ["catch_up", c]]:
		var x: Sim = pair[1]
		var ok := rel(x.scrap, a.scrap) < 0.01 and rel(float(x.stock), float(a.stock)) < 0.01 \
				and rel(float(x.stats()["visits"]), float(a.stats()["visits"])) < 0.01 \
				and rel(float(x.stats()["harvested"]), float(a.stats()["harvested"])) < 0.01 \
				and rel(progress_sum(x), progress_sum(a)) < 0.01
		check(ok, "%s: sucata %.1f cestos %d colhidos %d" % [pair[0], x.scrap, x.stock, int(x.stats()["harvested"])])
	var exact := U.deep_close(a.to_dict(), b.to_dict())
	check(exact == "", "avanço único e 72x60 são idênticos " + exact)
	check(sum["visits"] >= 9 and sum["hours"] == 72 and sum["nights"] == 3, "resumo do catch_up: " + str(sum))

	print("== salvar/carregar em meio de jogo")
	var path := "user://sim_pace_test.json"
	Save.delete(path)
	var m := Sim.new()
	m.from_dict(mid_state)
	var botm := Bot.new(m)
	botm.run(10.0, 6)  # joga mais um pouco com o bot (não termina na antena 5)
	var ok_w := Save.write(m.to_dict(), 1234.0, path)
	check(ok_w and Save.exists(path), "save escrito (atômico)")
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)  # lixo de uma escrita interrompida não atrapalha
	f.store_string("{ lixo")
	f.close()
	check(Save.write(m.to_dict(), 1235.0, path), "regrava com .tmp velho no caminho")
	var rd := Save.read(path)
	check(bool(rd["ok"]) and float(rd["saved_unix"]) == 1235.0, "read ok")
	var l := Sim.new()
	check(l.from_dict(rd["sim"]), "from_dict ok")
	var dd := U.deep_close(l.to_dict(), m.to_dict(), 1e-9)
	check(dd == "", "estado carregado = estado salvo " + dd)
	m.advance(5.0 * 1440.0)
	l.advance(5.0 * 1440.0)
	var dd2 := U.deep_close(l.to_dict(), m.to_dict(), 1e-6)
	check(dd2 == "", "5 dias depois continuam iguais " + dd2)
	# o bot continua do ponto carregado e chega no mesmo dia
	var bl := Bot.new(l)
	bl.run(40.0)
	var bm := Bot.new(m)
	bm.run(40.0)
	check(absf(l.antenna_time(5) - m.antenna_time(5)) < 1.0, "antena 5 igual depois de carregar (%.2f vs %.2f dias)" % [l.antenna_time(5) / 1440.0, m.antenna_time(5) / 1440.0])
	# save corrompido: cai no .bak
	var g := FileAccess.open(path, FileAccess.WRITE)
	g.store_string("{ corrompido")
	g.close()
	check(not bool(Save.read(path)["ok"]), "save corrompido sem .bak: falha limpa (sem travar)")
	var bk := FileAccess.open(path + ".bak", FileAccess.WRITE)
	bk.store_string(JSON.stringify({"format": 1, "saved_unix": 9.0, "sim": mid_state}, "", true, true))
	bk.close()
	check(bool(Save.read(path)["ok"]), "save corrompido: usa o .bak")
	Save.delete(path)

	print("RESULTADO: %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(0 if fails == 0 else 1)
