class_name Guide
extends RefCounted
## Próxima meta sugerida (o jogador não precisa pensar "o que compro agora?").
## Ordem em data/balance.json -> guide.order. Entradas: "item", "item:N" (até ter N), "antena@N".
## Usa só a API pública de Game (por nó), para funcionar com stubs.


## Devolve {} se não há meta. Campos: id, antenna(bool), name_key, cost, have, ready.
static func next_goal(game: Object) -> Dictionary:
	if game == null or not game.has_method("sucata") or not game.has_method("can_buy") or not game.has_method("catalog"):
		return {}
	var have: int = int(game.call("sucata"))
	var pinned: String = String(game.call("pinned_goal")) if game.has_method("pinned_goal") else ""
	if pinned != "":
		var g: Dictionary = _resolve(game, pinned, have)
		if not g.is_empty() and int(g["verdict"]) != 0:
			return g
	var order: Array = Balance.val("guide.order", []) as Array
	for entry in order:
		var g: Dictionary = _resolve(game, String(entry), have)
		if not g.is_empty() and int(g["verdict"]) != 0:
			return g
	return {}


## verdict: 0 pular, 1 pode comprar já, 2 só falta sucata.
static func _resolve(game: Object, entry: String, have: int) -> Dictionary:
	if entry == "antena" or entry == "antenna" or entry.begins_with("antena@"):
		var info: Dictionary = game.call("antenna_info")
		if bool(info.get("max", false)):
			return {}
		var lvl: int = int(info.get("level", 1)) + 1
		if entry.begins_with("antena@") and int(entry.substr(7)) != lvl:
			return {}
		var miss: Array = info.get("missing", [])
		var v: int = 1 if bool(info.get("can", false)) else (2 if miss.size() == 1 and miss[0] == "missing.cost" else 0)
		return {"id": "antenna", "antenna": true, "name_key": "antenna.%d.name" % lvl, "cost": int(info.get("next_cost", 0)),
				"have": have, "ready": v == 1, "verdict": v}
	var item: String = entry
	var until: int = -1
	if entry.contains(":"):
		item = entry.get_slice(":", 0)
		until = int(entry.get_slice(":", 1))
	if until >= 0 and _owned(game, item) >= until:
		return {}
	var r: Dictionary = game.call("can_buy", item)
	var cost: int = 0
	for c in game.call("catalog", ""):
		if String(c["item"]) == item:
			cost = int(c["cost"])
			if String(c["status"]) == "owned" or String(c["status"]) == "maxed":
				return {}
			break
	var miss2: Array = r.get("missing", [])
	var v2: int = 1 if bool(r.get("ok", false)) else (2 if miss2.size() == 1 and miss2[0] == "missing.cost" else 0)
	return {"id": item, "antenna": false, "name_key": "item.%s.name" % item, "cost": cost,
			"have": have, "ready": v2 == 1, "verdict": v2}


static func _owned(game: Object, item: String) -> int:
	var n: int = 0
	for i in game.call("instances"):
		if String(i["item"]) == item:
			n += 1
	return n
