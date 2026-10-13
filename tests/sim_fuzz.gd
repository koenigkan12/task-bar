extends SceneTree
## Jogo aleatório: invariantes + alcançabilidade (nenhuma compra deixa o jogo sem saída).
## godot --headless --path . --script res://tests/sim_fuzz.gd
const Reach := preload("res://tests/sim_reach.gd")
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		if fails <= 8:
			print("  FAIL " + msg.left(250))


func invariants(s: Sim, tag: String) -> void:
	check(s.sucata() >= 0 and s.scrap > -0.001, tag + ": sucata >= 0")
	check(s.stock >= 0, tag + ": estoque >= 0")
	check(s.power_ok(), tag + ": energia ok (oferta %d demanda %d)" % [s.power_supply(), s.power_demand()])
	# grade sem sobreposição
	var seen := {}
	for o in s.fixed_objects(1):
		for k in range(int(o["col"]), int(o["col"]) + int(o["cols"])):
			seen["1:%d" % k] = true
	for i in s.instances():
		if int(i["cols"]) <= 0:
			continue
		check(int(i["room"]) >= 1 and int(i["room"]) <= s.rooms() and int(i["col"]) >= 0 and int(i["col"]) + int(i["cols"]) <= 12, tag + ": dentro da sala")
		for k in range(int(i["col"]), int(i["col"]) + int(i["cols"])):
			var key := "%d:%d" % [i["room"], k]
			check(not seen.has(key), tag + ": sem sobreposição em " + key)
			seen[key] = true
	var np := 0
	for i in s.instances():
		if i["state"] == "ready":
			np += int(Balance.item(i["item"]).get("plots", 0))
	check(s.plots().size() == np, tag + ": plots (%d) = soma dos prontos (%d)" % [s.plots().size(), np])


func random_action(s: Sim, rng: RandomNumberGenerator) -> void:
	var roll := rng.randi() % 10
	if roll < 6:
		var cand: Array = []
		for e in s.catalog():
			if String(e["status"]) == "available":
				cand.append(e)
		if not cand.is_empty():
			var e: Dictionary = cand[rng.randi() % cand.size()]
			var hints := s.placement_hints(String(e["item"]))
			if hints.is_empty():
				s.buy(String(e["item"]), 0, -1)
			else:
				var h: Dictionary = hints[rng.randi() % hints.size()]
				s.buy(String(e["item"]), int(h["room"]), int(h["col"]))
	elif roll == 6:
		if bool(s.antenna_info()["can"]):
			s.upgrade_antenna()
	elif roll == 7:
		s.dig_room()
	elif roll == 8:
		var ins := s.instances()
		var inst: Dictionary = ins[rng.randi() % ins.size()]
		if rng.randi() % 2 == 0:
			s.demolish(int(inst["id"]))
		else:
			var hh := s.placement_hints(String(inst["item"]))
			if not hh.is_empty() and int(inst["cols"]) > 0:
				var h2: Dictionary = hh[rng.randi() % hh.size()]
				s.move(int(inst["id"]), int(h2["room"]), int(h2["col"]))
	else:
		var ins2 := s.instances()
		var inst2: Dictionary = ins2[rng.randi() % ins2.size()]
		var crops := s.available_crops(int(inst2["id"]))
		if not crops.is_empty():
			s.set_instance_crop(int(inst2["id"]), crops[rng.randi() % crops.size()] if rng.randi() % 3 > 0 else "")


func _init() -> void:
	Balance.load_all()
	var games := 24
	var checks := 0
	for g in games:
		var s := Sim.new()
		s.new_game(100 + g, float(g % 24))
		var rng := RandomNumberGenerator.new()
		rng.seed = 5000 + g
		# jogador aleatório: o dinheiro entra "de graça" de vez em quando para cobrir caminhos que a economia só alcançaria tarde
		for day in 30:
			for tick in 3:
				s.advance(480.0)
				if g % 2 == 0:
					s.scrap += float(rng.randi() % 120)
				for k in 1 + rng.randi() % 3:
					random_action(s, rng)
				invariants(s, "g%d d%d" % [g, day])
			if day % 5 == 4:
				var r := Reach.run(s)
				checks += 1
				check(bool(r["ok"]), "g%d dia %d iters=%d rp=%d sem saída? %s" % [g, day, r["iters"], r["repacks"], str(r["why"])])
				if not bool(r["ok"]):
					break
	print("(%d jogos aleatórios, %d checagens de alcançabilidade)" % [games, checks])
	print("RESULTADO: %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(0 if fails == 0 else 1)
