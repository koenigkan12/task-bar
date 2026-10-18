extends SceneTree
## Noite de ataque inteira, do aviso ao fim: começo, meio e fim.
## Roda: bash ../Ferramentas/godot.sh --headless --path . --script res://tests/raid_test.gd

var fails := 0
var closed: Array = []
var fell: Array = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FALHOU: ", msg)
	else:
		print("ok: ", msg)


func _new_sim(towers: int) -> VilaSim:
	var bal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var sim := VilaSim.new()
	var start := 1760000000.0 - fposmod(1760000000.0, 86400.0) + 7.0 * 3600.0
	sim.setup(bal, start, 0)
	sim.tower = 3
	for r in VilaSim.RES:
		sim.stock[r] = 9999.0
	for tp in ["poco", "horta", "moradia", "deposito", "moradia", "horta", "serraria", "ferrovelho"]:
		var rs := sim.build(tp, AutoPlayer.spot(sim, tp))
		if bool(rs.get("ok", false)):
			sim._finish(sim.buildings[sim.buildings.size() - 1])
	for i in towers:
		var rt := sim.build("torre_arq", AutoPlayer.spot(sim, "torre_arq"))
		if bool(rt.get("ok", false)):
			sim._finish(sim.buildings[sim.buildings.size() - 1])
	# Vai para uma noite de horda (mais zumbis).
	var df := sim.defense
	var dn := sim.day_number()
	var hd := maxi(dn, int(sim.bal["defense"]["from_day"]))
	while not bool(df.forecast(hd)["horde"]):
		hd += 1
	sim.t += float(hd - dn) * float(sim.bal["night"]["cycle_s"])
	sim.set_cycle_hour(21.5)
	sim.raid_over.connect(func(rep: Dictionary) -> void: closed.append({"rep": rep.duplicate(true), "night": sim.is_night()}))
	sim.building_fell.connect(func(id: int, ruin: bool) -> void: fell.append(id))
	return sim


func _night(sim: VilaSim) -> void:
	var t0 := sim.t
	while sim.t - t0 < float(sim.bal["night"]["cycle_s"]) * 0.4 and closed.is_empty():
		sim.advance(0.25)


func _init() -> void:
	# 1) Vila bem defendida: todos caem e o resultado sai na hora, ainda de noite.
	closed.clear()
	fell.clear()
	var a := _new_sim(5)
	_night(a)
	_check(closed.size() == 1, "a noite fecha com um resultado (%d)" % closed.size())
	if not closed.is_empty():
		var r: Dictionary = closed[0]["rep"]
		print("  defendida: vieram %d, derrubados %d, fugiram %d, caídos %d, resultado %s" % [int(r["came"]), int(r["killed"]), int(r.get("fled", -1)), (r["broke"] as Array).size() + (r["ruined"] as Array).size(), String(r.get("result", ""))])
		_check(String(r.get("result", "")) == "survived" and bool(closed[0]["night"]), "todos derrubados: 'noite sobrevivida' na hora, sem esperar o amanhecer")
		_check(int(r["killed"]) == int(r["came"]), "derrubados = os que vieram")
	# 2) Sem torres: não param em 2 prédios; destroem até morrer ou amanhecer.
	closed.clear()
	fell.clear()
	var b := _new_sim(0)
	for bb in b.buildings:
		if String(bb["type"]) == "hatch":
			b.defense._cool[int(bb["id"])] = 1e9   # sem a espingarda: ninguém atira
	_night(b)
	print("  sem defesa: caíram %d prédios" % fell.size())
	_check(fell.size() > 2, "sem defesa os zumbis não param em 2 prédios (%d)" % fell.size())
	_check(closed.size() == 1, "sem defesa a noite também fecha com um resultado")
	if not closed.is_empty():
		var r2: Dictionary = closed[0]["rep"]
		_check(String(r2.get("result", "")) == "fled" and int(r2["fled"]) > 0, "amanheceu com zumbi vivo: 'voltaram para a água' (%d)" % int(r2.get("fled", 0)))
	if fails > 0:
		printerr("FALHAS: ", fails)
	else:
		print("FALHAS: 0")
	quit(1 if fails > 0 else 0)
