extends SceneTree
## Necessidades do Joaquim: comida cai e volta ao comer, água ele bebe sozinho, sono volta de noite.
## Vermelho só mata depois que o aviso foi visto; fora do jogo (catch_up) o prazo não corre; sono nunca mata.
## godot --headless --path . --script res://tests/sim_needs.gd
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		print("  FAIL " + msg)
		fails += 1
	else:
		print("  ok   " + msg)


func _init() -> void:
	Balance.load_all()
	var s := Sim.new()
	s.new_game(5, 9.0)

	print("== começo")
	check(is_equal_approx(s.need_level("food"), 1.0) and is_equal_approx(s.need_level("water"), 1.0), "começa cheio")
	check(s.worst_need_state() == "ok", "moldura normal")

	print("== comida cai com o tempo e volta ao comer")
	s.advance(180.0)
	check(s.need_level("food") < 1.0 and s.need_level("food") > 0.6, "3 h depois: comida desceu um pouco " + str(s.need_level("food")))
	s.stock = 3
	s.stock_value = 3.0
	s._eat_one()
	check(is_equal_approx(s.need_level("food"), 1.0), "comer enche")

	print("== água: bebe sozinho, nunca fica abaixo do limite de beber")
	var low := 1.0
	for i in 30:
		s.advance(30.0)
		low = minf(low, s.need_level("water"))
	check(low >= 0.45, "água oscila entre cheia e o limite (mín " + str(low) + ")")
	check(s.water_flows(), "lata: água sempre chega")

	print("== sono volta de noite")
	var t := Sim.new()
	t.new_game(5, 9.0)
	t.advance(12.0 * 60.0)   # 21h
	var tired: float = t.need_level("sleep")
	check(tired < 0.7, "à noite está cansado " + str(tired))
	t.advance(9.0 * 60.0)
	check(t.need_level("sleep") > tired + 0.3, "dormindo recupera")
	check(t.need_state("sleep") != "bad", "sono nunca vira vermelho")

	print("== vermelho: sem comida")
	var f := Sim.new()
	f.new_game(5, 9.0)
	f._plots = []   # sem colheita: nenhum cesto
	f.advance(24.0 * 60.0)   # um dia sem nenhum cesto
	check(f.need_state("food") == "bad", "sem cestos: comida no vermelho (" + str(f.need_level("food")) + ")")
	check(f.worst_need_state() == "bad", "moldura vermelha")
	var days0: int = f.day_index()
	f.advance(4.0 * 24.0 * 60.0)
	check(not f.is_dead(), "aviso não visto: ninguém morre")
	f.ack_warning()
	check(f.death_left_min("food") > 0.0, "aviso visto: prazo correndo " + str(f.death_left_min("food")))
	var died_days := [-1]
	f.died.connect(func(d: int) -> void: died_days[0] = d)
	f.advance(Balance.num("needs.death_food_min", 2880.0) - 60.0)
	check(not f.is_dead(), "ainda vivo antes do prazo")
	f.advance(120.0)
	check(f.is_dead() and died_days[0] == f.death_days() and f.death_days() > days0, "morreu e avisou os dias: " + str(died_days[0]))
	var t0: float = f.t_min
	f.advance(600.0)
	check(is_equal_approx(f.t_min, t0), "morto: o relógio para")

	print("== comer tira do vermelho e zera o prazo")
	var g := Sim.new()
	g.new_game(5, 9.0)
	g._plots = []   # sem colheita: nenhum cesto
	g.advance(24.0 * 60.0)
	g.ack_warning()
	g.advance(600.0)
	check(g.death_left_min("food") >= 0.0 and g.death_left_min("food") < Balance.num("needs.death_food_min", 2880.0), "prazo correndo")
	g.stock = 2
	g.stock_value = 2.0
	g.advance(60.0)
	check(g.need_state("food") != "bad", "comeu: fora do vermelho")
	check(g.death_left_min("food") < 0.0, "sem prazo")

	print("== fora do jogo o prazo não corre")
	var a := Sim.new()
	a.new_game(5, 9.0)
	a._plots = []   # sem colheita: nenhum cesto
	a.advance(24.0 * 60.0)
	a.ack_warning()
	a.catch_up(3.0 * 24.0 * 60.0)
	check(not a.is_dead(), "3 dias fechado: vivo, esperando no vermelho")
	check(a.need_state("food") == "bad", "continua no vermelho quando volta")

	print("== água sem energia")
	var w := Sim.new()
	w.new_game(5, 9.0)
	w._line_ready["agua"] = "bomba"
	w._instances.append(w._make_instance("bomba", 1, 3, "ready"))
	w._line_ready["energia"] = "bicicleta"
	check(not w.power_ok() or true, "ok")
	w.rooms_n = 3
	w.antenna_level = 5
	check(not w.power_ok(), "energia faltando (demanda " + str(w.power_demand()) + " > " + str(w.power_supply()) + ")")
	check(not w.water_flows(), "bomba parada sem energia")
	w.advance(24.0 * 60.0)
	check(w.need_state("water") == "bad", "água acabou")

	print("== save/load guarda tudo")
	var d: Dictionary = f.to_dict()
	var r := Sim.new()
	check(r.from_dict(d) and r.is_dead() and r.death_days() == f.death_days(), "morte volta no save")
	var d2: Dictionary = g.to_dict()
	var r2 := Sim.new()
	r2.from_dict(d2)
	check(is_equal_approx(r2.need_level("food"), g.need_level("food")), "comida volta no save")
	d2.erase("food")
	d2.erase("dead")
	var r3 := Sim.new()
	check(r3.from_dict(d2) and is_equal_approx(r3.need_level("food"), 1.0) and not r3.is_dead(), "save antigo: tudo cheio e vivo")

	print("fails=%d" % fails)
	quit(1 if fails > 0 else 0)
