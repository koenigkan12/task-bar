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
	_check(free0 >= 14 and free0 <= 60, "clareira pequena no começo (14 a 60 células livres)")
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
	_check(Time.get_ticks_msec() - t1 < 15000, "offline de 72 h em menos de 15 s")
	for r in VilaSim.RES:
		_check(float(sim2.stock[r]) <= sim2.cap(r) + 0.01, "offline respeita o depósito (%s)" % r)
	# A noite para tudo.
	var night := VilaSim.new()
	night.setup(bal, start - 7.0 * 3600.0 + 23.0 * 3600.0, 0)
	_check(night.is_night(), "23h é noite")
	night.stock["madeira"] = 50.0
	night.build("poco", AutoPlayer.spot(night, "poco"))
	night.advance(600.0)
	var pb: Dictionary = night.buildings[night.buildings.size() - 1]
	_check(String(pb["state"]) == "site" and float(pb["progress"]) == 0.0, "obra não anda de noite")
	print("FALHAS: ", fails)
	quit(1 if fails > 0 else 0)
