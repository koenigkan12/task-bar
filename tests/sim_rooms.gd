extends SceneTree
## Cada linha de itens no seu cômodo: plantio na horta, água e energia na oficina, transporte na escotilha,
## decoração no quarto, itens dela no quarto dela (sala 3). Saves de antes dos cômodos são reorganizados.
## godot --headless --path . --script res://tests/sim_rooms.gd
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		print("  FAIL " + msg)
		fails += 1
	else:
		print("  ok   " + msg)


## Todas as posições oferecidas para `item` caem num cômodo da função esperada?
func hints_in(s: Sim, item: String, fn: String) -> bool:
	var hs: Array[Dictionary] = s.placement_hints(item)
	if hs.is_empty():
		return false
	var cols: int = int(Balance.item(item).get("cols", 1))
	for h: Dictionary in hs:
		var ok := false
		for z: Dictionary in Balance.room_zones(int(h["room"])):
			if String(z["fn"]) == fn and int(h["col"]) >= int(z["col0"]) and int(h["col"]) + cols <= int(z["col0"]) + int(z["cols"]):
				ok = true
		if not ok:
			return false
	return true


func _init() -> void:
	Balance.load_all()
	var s := Sim.new()
	s.new_game(3, 9.0)
	s.rooms_n = 3
	s.antenna_level = 5
	s.scrap = 1.0e6

	print("== layout")
	check(Balance.room_zones(1).size() == 4, "andar de cima: 4 cômodos")
	var fns: Array[String] = []
	for z: Dictionary in Balance.room_zones(1):
		fns.append(String(z["fn"]))
	check(fns == ["escotilha", "horta", "oficina", "quarto"], "ordem: escotilha, horta, oficina, quarto " + str(fns))
	check(Balance.room_cols(1) == 29 and Balance.room_cols(2) == 8 and Balance.room_cols(3) == 8, "colunas: 29, 8, 8")

	print("== cada linha no seu cômodo")
	check(hints_in(s, "canteiro", "horta"), "canteiro só na horta")
	check(hints_in(s, "prateleira", "horta"), "prateleira só na horta (inclusive a estufa da sala 2)")
	check(hints_in(s, "estufa", "horta"), "estufa só na horta")
	check(hints_in(s, "cisterna", "oficina"), "cisterna só na oficina")
	check(hints_in(s, "bateria", "oficina"), "bateria só na oficina")
	check(hints_in(s, "calha", "escotilha"), "calha só na escotilha")
	check(hints_in(s, "esteira", "escotilha"), "esteira só na escotilha")
	check(hints_in(s, "estante", "quarto"), "estante só no quarto")
	check(hints_in(s, "cama_dela", "casa"), "cama dela só no quarto dela")
	check(not s.can_place("vaso", 1, 17), "vaso na oficina: não")
	check(not s.can_place("cisterna", 1, 8), "cisterna na horta: não")
	check(not s.can_place("estante", 1, 10), "estante na horta: não")
	check(not s.can_place("canteiro", 1, 5), "canteiro atravessando a parede da escotilha para a horta: não")
	check(not s.can_place("cama_dela", 1, 23), "cama dela no quarto comum: não")
	check(s.can_place("cama_dela", 3, 2), "cama dela na sala 3: sim")

	print("== itens dela pedem a sala 3")
	var t := Sim.new()
	t.new_game(3, 9.0)
	t.antenna_level = 5
	t.scrap = 1.0e6
	check(not bool(t.can_buy("cama_dela")["ok"]), "com 1 sala não compra a cama dela")
	t.rooms_n = 3
	check(bool(t.can_buy("cama_dela")["ok"]), "com 3 salas compra")

	print("== save antigo (cada coisa no mesmo vão) é reorganizado")
	var old := Sim.new()
	old.new_game(3, 9.0)
	old.rooms_n = 2
	old.scrap = 1.0e6
	var d: Dictionary = old.to_dict()
	d.erase("layout")
	var insts: Array = d["instances"]
	# posições do jogo antigo: vasos em 3, 4, 5; bicicleta em 6; canteiro em 7 (tudo na mesma sala)
	var k := 0
	for i in insts:
		var inst: Dictionary = i
		if String(inst["item"]) == "vaso":
			inst["col"] = 3 + k
			k += 1
		elif String(inst["item"]) == "bicicleta":
			inst["col"] = 6
	insts.append({"id": 99, "item": "canteiro", "room": 1, "col": 7, "cols": 2, "state": "ready", "crop_order": "", "paid": 30, "locked": false})
	d["next_id"] = 100
	var m := Sim.new()
	check(m.from_dict(d), "save antigo carrega")
	var bad := 0
	for inst in m.instances():
		if int(inst["cols"]) <= 0:
			continue
		var fn: String = Balance.zone_fn_of_line(String(Balance.item(String(inst["item"])).get("line", "")))
		var ok := false
		for z: Dictionary in Balance.room_zones(int(inst["room"])):
			if String(z["fn"]) == fn and int(inst["col"]) >= int(z["col0"]) and int(inst["col"]) + int(inst["cols"]) <= int(z["col0"]) + int(z["cols"]):
				ok = true
		if not ok:
			bad += 1
			print("    fora do lugar: ", inst)
	check(bad == 0, "tudo caiu no cômodo da sua função")
	check(m.plots().size() == 3, "as plantas continuam (%d)" % m.plots().size())
	check(int(m.to_dict()["layout"]) == Sim.LAYOUT_VERSION, "o save novo leva a versão da disposição")

	print("RESULTADO: %d FALHAS" % fails)
	quit(1 if fails > 0 else 0)
