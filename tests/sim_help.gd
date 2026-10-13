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
