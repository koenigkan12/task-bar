class_name AutoPlayer
extends RefCounted
## Jogador automático usado nos testes e nas capturas (--demo=N): segue a meta, sobe a torre,
## põe casa quando falta cama, serraria e ferro-velho na torre 2 e escolhe o 1º do portão.


static func spot(sim: VilaSim, type: String) -> Vector2i:
	var c := Vector2i(sim.bal["map"]["hatch"][0], sim.bal["map"]["hatch"][1])
	for r in range(2, 14):
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
	if sim.tower >= 2:
		if sim._count_any("barraco") == 0:
			_try(sim, "barraco")
		if sim.beds_free() <= 0 and sim._count_any("casa") < 2:
			_try(sim, "casa")
		for tp in ["fogueira", "serraria", "ferrovelho"]:
			if sim._count_any(tp) == 0:
				_try(sim, tp)
