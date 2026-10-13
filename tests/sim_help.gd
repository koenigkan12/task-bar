extends SceneTree
## Ajuda manual do começo: cliques empurram o ciclo, a caixa vende na hora, some depois da antena 2, teto diário.
## godot --headless --path . --script res://tests/sim_help.gd
var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	Balance.load_all()
	var s := Sim.new()
	s.new_game()
	check(s.sucata() == 6, "começa com 6 de sucata (primeira compra imediata)")
	check(s.help_available(), "ajuda disponível na antena 1")
	var insts: Array = s.instances()
	var vaso_id := -1
	for i in insts:
		if String(i["item"]) == "vaso":
			vaso_id = int(i["id"])
			break
	check(vaso_id >= 0, "há um vaso inicial")
	# primeira colheita só com cliques (ciclo de 20 min; cada clique = 4 min)
	var hv := {"n": 0}
	s.plot_harvested.connect(func(_p: int) -> void: hv["n"] += 1)
	for k in 6:
		check(bool(s.help_instance(vaso_id)["ok"]), "clique %d aceito" % (k + 1))
		if hv["n"] > 0:
			break
	check(hv["n"] == 1, "o vaso colheu só com cliques")
	check(s.box_stock() >= 1.0, "a colheita foi para a caixa")
	var scrap0 := s.sucata()
	var r := s.help_box()
	check(bool(r["ok"]) and s.sucata() > scrap0, "clicar na caixa troca por sucata agora")
	check(String(s.help_box()["reason"]) == "empty" or String(s.help_box()["reason"]) == "cooldown", "segunda troca seguida é recusada")
	# teto diário
	var capped := false
	for k in 400:
		var rr := s.help_instance(vaso_id)
		if not bool(rr["ok"]):
			capped = String(rr["reason"]) == "cap"
			break
	check(capped, "teto diário de ajuda")
	s.debug_advance_minutes(1440.0)
	check(bool(s.help_instance(vaso_id)["ok"]), "teto reinicia no dia seguinte")
	# obra: clicar ajuda a martelar e a estimativa de tempo aparece
	var b := Sim.new()
	b.new_game()
	var bv: Dictionary = b.buy("vaso", 1, 7)
	check(bool(bv["ok"]), "compra um vaso (obra)")
	var jobs: Array = b.active_jobs()
	check(jobs.size() == 1 and float(jobs[0]["eta_min"]) > 1.0, "obra com tempo estimado (%s min)" % str(jobs[0].get("eta_min", -1)))
	var done_clicks := 0
	for k in 12:
		var rb: Dictionary = b.help_instance(int(bv["instance_id"]))
		if not bool(rb["ok"]):
			break
		done_clicks += 1
		if b.active_jobs().is_empty():
			break
	check(b.active_jobs().is_empty() and done_clicks <= 6, "a obra do vaso termina só com cliques (%d)" % done_clicks)
	var ready := false
	for i in b.instances():
		if int(i["id"]) == int(bv["instance_id"]):
			ready = String(i["state"]) == "ready"
	check(ready, "vaso pronto depois da obra")
	# a porcentagem da obra anda entre os passos de 10 min (antes ficava em 0% até o passo fechar)
	var q := Sim.new()
	q.new_game(1, 9.0)
	var qv: Dictionary = q.buy("vaso", 1, 7)
	check(float(q.active_jobs()[0]["ratio"]) == 0.0, "obra nova começa em 0%")
	q.debug_advance_minutes(4.0)
	var r4: float = float(q.active_jobs()[0]["ratio"])
	check(r4 > 0.05 and r4 < 0.95, "aos 4 min a obra já mostra andamento (%.2f)" % r4)
	var bar: float = 0.0
	for i in q.instances():
		if int(i["id"]) == int(qv["instance_id"]):
			bar = float(i["build_ratio"])
	check(absf(bar - r4) < 0.01, "o andaime mostra o mesmo valor (%.2f)" % bar)
	var eta4: float = float(q.active_jobs()[0]["eta_min"])
	q.debug_advance_minutes(3.0)
	check(float(q.active_jobs()[0]["ratio"]) > r4 and float(q.active_jobs()[0]["eta_min"]) < eta4, "andamento e tempo seguem entre os passos")
	q.debug_advance_minutes(40.0)
	check(q.active_jobs().is_empty(), "sem clicar, a obra do vaso fecha sozinha")
	# cada máquina tira um clique
	var t := Sim.new()
	t.new_game()
	check(t.help_plots_available() and t.help_box_available(), "no começo os dois cliques valem")
	t._line_ready["agua"] = "gotejador"
	check(not t.help_plots_available() and t.help_box_available(), "com o gotejador sai o clique do vaso")
	check(String(t.help_instance(vaso_id)["reason"]) == "off", "help_instance recusa depois do gotejador")
	t._line_ready["transporte"] = "calha"
	check(not t.help_available(), "com a calha não resta ajuda")
	check(String(t.help_box()["reason"]) == "off", "help_box recusa depois da calha")
	print("sim_help: ", "OK" if fails == 0 else "%d falhas" % fails)
	quit(fails)
