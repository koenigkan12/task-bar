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
		"tower":
			if sim.can_afford(sim.tower_next()["cost"]):
				sim.tower_upgrade()
				return
		"storage":
			var dep := sim._first("deposito")
			if dep.is_empty():
				_try(sim, "deposito")
			elif String(dep["state"]) == "built":
				sim.upgrade(int(dep["id"]))
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
