extends RefCounted
## Alcançabilidade: a partir de um estado qualquer, com sucata infinita e podendo reorganizar a grade (mover é
## grátis), dá para comprar TUDO, chegar à antena 5, escavar 3 salas e levar a casa ao ponto da chegada dela?

## Reorganiza todas as instâncias com colunas (first-fit, as maiores primeiro), como o jogador faria com "mover".
static func repack(c: Sim) -> void:
	var ncols: int = Balance.integer("rooms.cols", 12)
	var occ: Array = [null]
	for r in range(1, c.rooms_n + 1):
		var a := PackedByteArray()
		a.resize(ncols)
		for o in c.fixed_objects(r):
			for k in range(int(o["col"]), int(o["col"]) + int(o["cols"])):
				a[k] = 1
		occ.append(a)
	var items: Array = []
	for inst in c._instances:
		if int(inst["cols"]) > 0:
			items.append(inst)
	items.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["cols"]) > int(y["cols"]))
	for inst in items:
		var placed := false
		for r in range(1, c.rooms_n + 1):
			var a: PackedByteArray = occ[r]
			for col in range(0, ncols - int(inst["cols"]) + 1):
				var free := true
				for k in range(col, col + int(inst["cols"])):
					if a[k] != 0:
						free = false
				if free:
					for k in range(col, col + int(inst["cols"])):
						a[k] = 1
					inst["room"] = r
					inst["col"] = col
					for p in c._plots:
						if int(p["inst"]) == int(inst["id"]):
							p["room"] = r
					placed = true
					break
			if placed:
				break
		if not placed:
			push_warning("repack: não coube " + String(inst["item"]))


## Devolve {ok, why}. Não altera `src` (trabalha numa cópia).
static func run(src: Sim) -> Dictionary:
	var c := Sim.new()
	c.from_dict(src.to_dict())
	var guard := 0
	var repacks := 0
	while guard < 400:
		guard += 1
		c.scrap = 1.0e7
		if not c._jobs.is_empty():
			c.advance(120.0)
			continue
		var progress := false
		if bool(c.antenna_info()["can"]):
			progress = bool(c.upgrade_antenna()["ok"])
		if not progress and bool(c.dig_room()["ok"]):
			progress = true
		if not progress:
			for e in c.catalog():
				if String(e["status"]) == "available":
					if bool(c.buy(String(e["item"]), 0, -1)["ok"]):
						progress = true
						break
		if not progress:
			var blocked_by_space := false
			for e in c.catalog():
				if String(e["status"]) == "locked" and (e["missing"] as Array).has("missing.free_cols"):
					blocked_by_space = true
			if blocked_by_space and repacks < 6:
				repacks += 1
				repack(c)
				continue
			break
	if guard >= 400:
		print("DEBUG jobs=", c._jobs, " busy=", c.busy(), " t=", c.t_min, " tod=", c.tod_hours(), " hungry=", c.hungry(), " plots=", c.plots().size())
	var why: Array[String] = []
	if c.antenna() != 5:
		why.append("antena %d" % c.antenna())
	if c.rooms() != 3:
		why.append("salas %d" % c.rooms())
	for e in c.catalog():
		var s := String(e["status"])
		if s != "owned" and s != "maxed":
			why.append("%s(%s %s)" % [e["item"], s, str(e["missing"])])
	c.advance(9.0 * 1440.0)  # passa o prazo mínimo de chegada
	if not (c.arrival_pending() or c.arrived()):
		why.append("chegada não disparou (contact %s)" % str(c.contact_min))
	return {"ok": why.is_empty(), "why": why, "iters": guard, "repacks": repacks}
