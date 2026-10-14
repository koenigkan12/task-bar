class_name AutoPlayer
extends RefCounted
## Jogador automático usado nos testes e nas capturas (--demo=N): segue a meta, sobe a torre,
## põe casa quando falta cama, serraria e ferro-velho na torre 2 e escolhe o 1º do portão.


static func spot(sim: VilaSim, type: String) -> Vector2i:
	var c := Vector2i(sim.bal["map"]["hatch"][0], sim.bal["map"]["hatch"][1])
	for r in range(1, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := c + Vector2i(dx, dy)
				if sim.can_place(type, cell):
					return cell
	return Vector2i(-1, -1)


static func _try(sim: VilaSim, type: String) -> void:
	if sim.can_afford(sim.def(type)["levels"][0]["cost"]):
		sim.build(type, spot(sim, type))


static func play(sim: VilaSim) -> void:
	if sim._count_any("fogueira") == 0:
		_try(sim, "fogueira")
	if not sim.gate_group.is_empty() and sim.beds_free() > 0:
		sim.choose(0)
	var g := sim.goal()
	match String(g["kind"]):
		"build", "more", "short":
			_try(sim, String(g["type"]))
			return
		"power":
			_try(sim, "painel" if sim.unlocked("painel") and sim.can_afford(sim.def("painel")["levels"][0]["cost"]) else "gerador")
			return
		"tower":
			if sim.can_afford(sim.tower_next()["cost"]):
				sim.tower_upgrade()
				return
		"storage":
			var dep := sim._first("deposito")
			if dep.is_empty():
				_try(sim, "deposito")
			elif String(dep["state"]) == "built":
				for d in sim.buildings:
					if String(d["type"]) == "deposito" and String(d["state"]) == "built" and sim.unlocked("deposito", int(d["level"]) + 1):
						if bool(sim.upgrade(int(d["id"]))["ok"]):
							break
				if String(dep["state"]) == "built" and sim._count_any("deposito") < 3:
					_try(sim, "deposito")
			return
	# Pouco chão: marca o entulho mais perto do centro.
	if sim._free_build_cells() < 10 and sim.marked.size() < 2:
		var best := Vector2i(-1, -1)
		var bd := 1e9
		for c in sim.rubble:
			var d := Vector2(c).distance_to(sim.center())
			if d < bd and not sim.marked.has(c):
				bd = d
				best = c
		if best.x >= 0:
			sim.toggle_mark(best)
	if sim.tower >= 2 and sim.beds_free() <= 0:
		var up := false
		for b in sim.buildings:
			if String(b["type"]) == "moradia" and String(b["state"]) == "built" and sim.unlocked("moradia", int(b["level"]) + 1):
				if bool(sim.upgrade(int(b["id"]))["ok"]):
					up = true
					break
		if not up and sim._count_any("moradia") < 4:
			_try(sim, "moradia")
	if sim.tower >= 2:
		for tp in ["serraria", "ferrovelho"]:
			if sim._count_any(tp) == 0:
				_try(sim, tp)
	# Torre 3 em diante: praça (mercador), gerador antes da oficina, galinheiro; na 4, cozinha, painel e estufa.
	var later := [["praca", 3], ["gerador", 3], ["oficina", 3], ["galinheiro", 3], ["cozinha", 4], ["painel", 4], ["estufa", 4]]
	for e in later:
		if sim.tower >= int(e[1]) and sim._count_any(String(e[0])) == 0 and sim.unlocked(String(e[0])):
			var pw: Dictionary = sim.power()
			if String(e[0]) in ["oficina", "estufa"] and float(pw["out"]) - float(pw["use"]) < 2.0:
				continue
			_try(sim, String(e[0]))
			break
	if sim.tower >= 4:
		for tp in ["oficina", "galinheiro", "poco", "horta"]:
			for b in sim.buildings:
				if String(b["type"]) == tp and String(b["state"]) == "built" and sim.unlocked(tp, int(b["level"]) + 1):
					sim.upgrade(int(b["id"]))
					break
	# Mercador: vende madeira sobrando e compra peças quando a sucata está alta.
	if sim.merchant_here():
		if float(sim.stock["madeira"]) > sim.cap("madeira") * 0.9:
			sim.sell_lot("madeira")
		var offers: Array = sim.merchant["offers"]
		for i in offers.size():
			if String(offers[i]) in ["pecas_lote", "sementes", "carrinho"] and not (sim.merchant["bought"] as Array).has(i):
				sim.buy_offer(i)
		sim.fulfill_request()
