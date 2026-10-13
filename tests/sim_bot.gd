extends RefCounted
## Bot do teste de ritmo: segue a ordem do plano "equilibrada" do oráculo (tools/sim_oracle/economia_sim.py).
## Regra do oráculo: compra o primeiro item da lista que está liberado; se falta só sucata, ESPERA.
## Diferença para o oráculo: "liberado" inclui caber na grade de colunas (item sem lugar é pulado).

## Ordem de compra do oráculo (a que ele realmente executa), adaptada à grade: a sala 1 só tem 7 colunas livres,
## então "comodo2" vem antes dos canteiros; "antena@N" = só sobe para o nível N (o oráculo tinha "antena" genérico
## no começo da lista, que só pesava depois de comodo2; aqui o lugar de cada nível é explícito).
const PLAN: Array[String] = ["vaso", "vaso", "antena@2", "moinho", "calha", "comodo2", "canteiro", "canteiro",
		"gotejador", "antena@3", "prateleira", "bateria", "antena@4", "cisterna", "estufa", "roldana", "comodo3",
		"painel", "antena@5", "bomba", "esteira"]

var sim: Sim
var plan: Array[String] = PLAN
var purchases: Array[Dictionary] = []   # {day, item, cost}
var checkins: Array[float] = [8.5, 12.5, 18.5]


func _init(s: Sim, p: Array[String] = PLAN) -> void:
	sim = s
	plan = p


## 0 = pular (travado/já tem), 1 = comprar já, 2 = esperar sucata
func _verdict(name: String) -> int:
	if name == "antena" or name.begins_with("antena@"):
		if name != "antena" and sim.antenna() + 1 != int(name.substr(7)):
			return 0
		var info := sim.antenna_info()
		if bool(info["max"]):
			return 0
		if bool(info["can"]):
			return 1
		var mk: Array = info["missing"]
		return 2 if mk.size() == 1 and mk[0] == "missing.cost" else 0
	var r := sim.can_buy(name)
	if bool(r["ok"]):
		return 1
	var mk: Array = r["missing"]
	return 2 if mk.size() == 1 and mk[0] == "missing.cost" else 0


func check_in() -> void:
	var bought := true
	while bought:
		bought = false
		for name in plan:
			var v := _verdict(name)
			if v == 0:
				continue
			if v == 2:
				return
			var cost := 0
			if name == "antena" or name.begins_with("antena@"):
				cost = int(sim.antenna_info()["next_cost"])
				if bool(sim.upgrade_antenna()["ok"]):
					purchases.append({"day": sim.t_min / 1440.0, "item": "antena%d" % sim.antenna(), "cost": cost})
					bought = true
			else:
				cost = sim.item_cost(name)
				var r := sim.buy(name, 0, -1)
				if bool(r["ok"]):
					purchases.append({"day": sim.t_min / 1440.0, "item": name, "cost": cost})
					bought = true
			if bought:
				break


## Avança passo a passo; faz check-in nos horários (como o oráculo: depois do passo que começa na hora).
func run(max_days: float, stop_at_antenna: int = 5) -> void:
	var step: float = Balance.num("time.step_min", 10.0)
	while sim.t_min < max_days * 1440.0 and sim.antenna() < stop_at_antenna:
		var before := sim.tod_hours()
		sim.advance(step)
		for c in checkins:
			if absf(before - c) < step / 120.0:
				check_in()
