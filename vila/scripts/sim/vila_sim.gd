class_name VilaSim
extends RefCounted
## Simulação da vila: mapa em grade, prédios, obras, pessoas autônomas, torre, chegadas e noite.
## Não sabe nada de cena: a vista lê o estado (buildings, people, stock...) e escuta os sinais.
## O tempo é o relógio real: `t` é o horário unix (s) que a simulação já alcançou.
## Online e offline usam o mesmo código (`advance`); offline só muda o passo e a fração de produção.

signal changed                                     # algo que a interface mostra mudou
signal building_done(id: int)                      # obra ou melhoria terminou
signal tower_up(level: int)
signal person_joined(id: int)
signal group_arrived                               # um grupo de 3 chegou ao portão
signal harvested(id: int, res: String, amount: int) # alguém entregou no depósito (para o "+N")

const RES: Array[String] = ["comida", "agua", "madeira", "sucata"]
const T_GROUND := 0
const T_TREE := 1
const T_RUBBLE := 2
const T_ROAD := 3
const T_STUMP := 4

var bal: Dictionary = {}
var t: float = 0.0
var tz_bias_s: int = 0
var start_t: float = 0.0       # quando a vila começou (para o "Dia N")          # fuso local em segundos (a vista põe o do sistema; os testes fixam)
var stock: Dictionary = {}
var tower: int = 1
var w: int = 40
var h: int = 30
var terrain: PackedByteArray = PackedByteArray()
var occ: PackedInt32Array = PackedInt32Array()       # id do prédio em cada célula, -1 livre
var regrow: Dictionary = {}       # célula (Vector2i) -> t em que a árvore volta
var rubble: Dictionary = {}       # célula -> sucata que resta
var marked: Dictionary = {}       # entulho marcado para limpar primeiro
var buildings: Array[Dictionary] = []
var people: Array[Dictionary] = []
var gate_group: Array[Dictionary] = []   # candidatos esperando no portão
var stats: Dictionary = {"commons_in_row": 0, "joined": 0, "built": 0}
var offline: bool = false        # durante o alcance offline: produção e consumo pela fração
var _next_id: int = 1
var _astar: AStarGrid2D
var _rng := RandomNumberGenerator.new()
var _group_ready_t: float = -1.0
var _story_done: Dictionary = {}
var _rethink_acc: float = 0.0
var _fdirty: bool = true            # terreno mudou: refaz a lista de árvores e entulhos
var _fcache: Dictionary = {}


# ================================================================ criação
func setup(balance: Dictionary, now_unix: float, tz_bias: int = 0) -> void:
	bal = balance
	t = now_unix
	start_t = now_unix
	tz_bias_s = tz_bias
	var m: Dictionary = bal["map"]
	w = int(m["w"])
	h = int(m["h"])
	_rng.seed = int(m["seed"])
	stock = {}
	for r in RES:
		stock[r] = float(bal["start"]["stock"].get(r, 0))
	_gen_map()
	_place_fixed("hatch", _v(m["hatch"]))
	_place_fixed("torre", _v(m["tower"]))
	# A barraca do Joaquim: uma moradia nível 1 como qualquer outra (dá para melhorar no lugar).
	_place_fixed("moradia", _v(m["tent"]))
	_rebuild_astar()
	var hatch: Dictionary = _first("hatch")
	_add_person("Joaquim", 0, [], _door(hatch), "joaquim")


func _v(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


func _gen_map() -> void:
	terrain.resize(w * h)
	occ.resize(w * h)
	occ.fill(-1)
	var m: Dictionary = bal["map"]
	var c := center()
	var r1: float = open_radius(1)
	var rmax: float = open_radius(tower_max())
	var noise := FastNoiseLite.new()
	noise.seed = int(m["seed"])
	noise.frequency = 0.18
	for y in h:
		for x in w:
			var i := y * w + x
			var d := Vector2(x, y).distance_to(c) + noise.get_noise_2d(x, y) * 1.2
			var k := T_GROUND
			var r := _rng.randf()
			if d <= r1:
				k = T_GROUND
			elif d <= rmax + 1.5:
				# Anel de entulho e mato: é o que a vila precisa abrir para crescer (nada de chão livre aqui).
				k = T_RUBBLE if r < 0.72 else T_TREE
			else:
				k = T_TREE if r < 0.7 else T_RUBBLE
			terrain[i] = k
			if k == T_RUBBLE:
				rubble[Vector2i(x, y)] = int(bal["rubble_amount"])


func _place_fixed(type: String, cell: Vector2i) -> void:
	var fp := _fp(type)
	for dy in fp.y:
		for dx in fp.x:
			var c := cell + Vector2i(dx, dy)
			if terrain[_i(c)] != T_ROAD:
				terrain[_i(c)] = T_GROUND
				_fdirty = true
			rubble.erase(c)
	# Limpa a frente (porta) para dar para chegar.
	var door := cell + Vector2i(fp.x / 2, fp.y)
	if _inside(door) and terrain[_i(door)] != T_ROAD:
		terrain[_i(door)] = T_GROUND
		_fdirty = true
	var b := {"id": _next_id, "type": type, "cell": cell, "level": 1, "state": "built",
			"progress": 0.0, "total": 0.0, "workers": [], "builder": -1, "acc": 0.0}
	_next_id += 1
	buildings.append(b)
	if not bool(def(type).get("walkable", false)):
		_mark(b, true)


## Centro da clareira (as áreas abertas pela torre são círculos em volta dele).
func center() -> Vector2:
	return Vector2(_v(bal["map"]["center"]))


func open_radius(level: int) -> float:
	return float(bal["map"]["open_radius"].get(str(level), 4.0))


## A torre subiu: o entulho dentro do novo raio vira chão (a sucata vai para o depósito, até o limite).
## Na torre 2 a estrada aparece e o portão é montado na ponta dela.
func _open_area(level: int) -> void:
	var c := center()
	var rad := open_radius(level)
	var gained := 0
	for y in h:
		for x in w:
			var cell := Vector2i(x, y)
			if terrain[_i(cell)] == T_RUBBLE and Vector2(cell).distance_to(c) <= rad:
				gained += int(rubble.get(cell, 0))
				rubble.erase(cell)
				marked.erase(cell)
				terrain[_i(cell)] = T_GROUND
				_fdirty = true
	if level == int(bal["arrivals"]["story_tower"]) and _first("gate").is_empty():
		var row: int = int(bal["map"]["road_row"])
		for x in range(int(c.x), w):
			var rc := Vector2i(x, row)
			if occ[_i(rc)] < 0:
				rubble.erase(rc)
				marked.erase(rc)
				regrow.erase(rc)
				terrain[_i(rc)] = T_ROAD
				_fdirty = true
		_place_fixed("gate", _v(bal["map"]["gate"]))
	stock["sucata"] = minf(cap("sucata"), float(stock["sucata"]) + float(gained) * float(bal.get("open_scrap_share", 0.5)))
	_rebuild_astar()


## Marca (ou desmarca) um entulho para limpar primeiro. Quem cata sucata vai nos marcados antes.
func toggle_mark(cell: Vector2i) -> bool:
	if terrain_at(cell) != T_RUBBLE:
		return false
	if marked.has(cell):
		marked.erase(cell)
	else:
		marked[cell] = true
	changed.emit()
	return marked.has(cell)


# ================================================================ consultas
func _i(c: Vector2i) -> int:
	return c.y * w + c.x


func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func _fp(type: String) -> Vector2i:
	return _v(bal["buildings"][type]["fp"])


func def(type: String) -> Dictionary:
	return bal["buildings"].get(type, {})


func level_def(b: Dictionary, level: int = -1) -> Dictionary:
	var lv: Array = def(String(b["type"])).get("levels", [])
	var n: int = (int(b["level"]) if level < 0 else level) - 1
	if n < 0 or n >= lv.size():
		return {}
	return lv[n]


func by_id(id: int) -> Dictionary:
	for b in buildings:
		if int(b["id"]) == id:
			return b
	return {}


func person(id: int) -> Dictionary:
	for p in people:
		if int(p["id"]) == id:
			return p
	return {}


func _first(type: String) -> Dictionary:
	for b in buildings:
		if String(b["type"]) == type:
			return b
	return {}


func building_at(c: Vector2i) -> Dictionary:
	if not _inside(c):
		return {}
	var id: int = occ[_i(c)]
	return by_id(id) if id >= 0 else {}


func terrain_at(c: Vector2i) -> int:
	return terrain[_i(c)] if _inside(c) else T_TREE


## Célula na frente do prédio (embaixo do meio): onde as pessoas param para trabalhar ou entregar.
func _door(b: Dictionary) -> Vector2i:
	var fp := _fp(String(b["type"]))
	return Vector2i(b["cell"]) + Vector2i(fp.x / 2, fp.y)


func is_night() -> bool:
	var hour := local_hour()
	var a: float = float(bal["time"]["night_from_h"])
	var z: float = float(bal["time"]["night_to_h"])
	return hour >= a or hour < z


func local_hour() -> float:
	var s: float = fposmod(t + float(tz_bias_s), 86400.0)
	return s / 3600.0


## Dia 1 é o dia (local) em que a vila começou.
func day_number() -> int:
	var d0 := floorf((start_t + float(tz_bias_s)) / 86400.0)
	return int(floorf((t + float(tz_bias_s)) / 86400.0) - d0) + 1


func cap(res: String) -> float:
	var c: float = float(bal["storage"]["hatch_cap"])
	for b in buildings:
		if String(b["type"]) == "deposito" and String(b["state"]) != "site":
			c += float(level_def(b).get("cap", 0))
	return c


func beds_total() -> int:
	var n := 0
	for b in buildings:
		# Moradia em melhoria continua com as camas do nível atual (ninguém fica sem cama).
		if String(b["state"]) == "site":
			continue
		n += int(level_def(b).get("beds", def(String(b["type"])).get("beds", 0)))
	return n


func beds_free() -> int:
	return beds_total() - people.size()


## Prédio pronto e não está em melhoria.
func _working(b: Dictionary) -> bool:
	return String(b["state"]) == "built"


func unlocked(type: String, level: int = 1) -> bool:
	var d := def(type)
	if d.is_empty() or bool(d.get("fixed", false)):
		return false
	var lv: Array = d.get("levels", [])
	if level > lv.size():
		return false
	var need: int = int((lv[level - 1] as Dictionary).get("tower", d.get("tower", 1)))
	return tower >= need


func can_afford(cost: Dictionary) -> bool:
	for r in cost:
		if float(stock.get(r, 0.0)) + 1e-6 < float(cost[r]):
			return false
	return true


func missing(cost: Dictionary) -> Dictionary:
	var out := {}
	for r in cost:
		var m: float = float(cost[r]) - float(stock.get(r, 0.0))
		if m > 1e-6:
			out[r] = int(ceil(m))
	return out


func can_place(type: String, cell: Vector2i) -> bool:
	var fp := _fp(type)
	for dy in fp.y:
		for dx in fp.x:
			var c := cell + Vector2i(dx, dy)
			if not _inside(c) or occ[_i(c)] >= 0:
				return false
			var k := terrain[_i(c)]
			if k != T_GROUND and k != T_STUMP:
				return false
	var door := cell + Vector2i(fp.x / 2, fp.y)
	if not _inside(door) or occ[_i(door)] >= 0 or terrain[_i(door)] == T_TREE or terrain[_i(door)] == T_RUBBLE:
		return false
	return true


func tower_next() -> Dictionary:
	return bal["tower"].get(str(tower + 1), {})


func tower_building() -> Dictionary:
	return _first("torre")


func tower_max() -> int:
	return int(bal.get("prototype_max_tower", 3))


# ================================================================ comandos do jogador
## Começa uma obra. Paga na hora (como o Clash); cancelar devolve tudo.
func build(type: String, cell: Vector2i) -> Dictionary:
	if not unlocked(type):
		return {"ok": false, "reason": "locked"}
	var lv: Dictionary = (def(type)["levels"] as Array)[0]
	if not can_afford(lv["cost"]):
		return {"ok": false, "reason": "cost"}
	if not can_place(type, cell):
		return {"ok": false, "reason": "place"}
	_pay(lv["cost"])
	var b := {"id": _next_id, "type": type, "cell": cell, "level": 1, "state": "site",
			"progress": 0.0, "total": float(lv["time_s"]), "workers": [], "builder": -1, "acc": 0.0,
			"queued_t": t}
	_next_id += 1
	buildings.append(b)
	_mark(b, true)
	for dy in _fp(type).y:
		for dx in _fp(type).x:
			var c := cell + Vector2i(dx, dy)
			terrain[_i(c)] = T_GROUND
			_fdirty = true
	_rebuild_astar()
	changed.emit()
	return {"ok": true, "id": int(b["id"])}


func upgrade(id: int) -> Dictionary:
	var b := by_id(id)
	if b.is_empty() or not _working(b):
		return {"ok": false, "reason": "busy"}
	var nl: int = int(b["level"]) + 1
	if not unlocked(String(b["type"]), nl):
		return {"ok": false, "reason": "locked"}
	var lv := level_def(b, nl)
	if not can_afford(lv["cost"]):
		return {"ok": false, "reason": "cost"}
	_pay(lv["cost"])
	_release_workers(b)
	b["state"] = "upgrade"
	b["progress"] = 0.0
	b["total"] = float(lv["time_s"])
	b["queued_t"] = t
	changed.emit()
	return {"ok": true}


func tower_upgrade() -> Dictionary:
	var b := tower_building()
	if String(b["state"]) != "built":
		return {"ok": false, "reason": "busy"}
	if tower >= tower_max():
		return {"ok": false, "reason": "max"}
	var nx := tower_next()
	if not can_afford(nx["cost"]):
		return {"ok": false, "reason": "cost"}
	_pay(nx["cost"])
	b["state"] = "upgrade"
	b["progress"] = 0.0
	b["total"] = float(nx["time_s"])
	b["queued_t"] = t
	changed.emit()
	return {"ok": true}


## Cancela uma obra (nova ou melhoria) e devolve o que custou.
func cancel(id: int) -> Dictionary:
	var b := by_id(id)
	if b.is_empty() or String(b["state"]) == "built":
		return {"ok": false}
	var cost: Dictionary
	if String(b["type"]) == "torre":
		cost = bal["tower"][str(tower + 1)]["cost"]
	elif String(b["state"]) == "upgrade":
		cost = level_def(b, int(b["level"]) + 1)["cost"]
	else:
		cost = level_def(b, 1)["cost"]
	for r in cost:
		stock[r] = float(stock[r]) + float(cost[r])
	_release_builder(b)
	if String(b["state"]) == "site":
		_mark(b, false)
		buildings.erase(b)
		_rebuild_astar()
	else:
		b["state"] = "built"
	changed.emit()
	return {"ok": true}


## Escolhe um dos 3 do portão (índice) ou ninguém (-1).
func choose(index: int) -> void:
	if gate_group.is_empty():
		return
	if index >= 0 and index < gate_group.size() and beds_free() > 0:
		var c: Dictionary = gate_group[index]
		var from := _v(bal["arrivals"]["walk_in_from"])
		var p := _add_person(String(c["name"]), int(c["look"]), c["passives"], from, "", int(c["bio"]))
		var br: Dictionary = c.get("brings", {})
		for r in br:
			stock[r] = minf(cap(r), float(stock[r]) + float(br[r]))
		person_joined.emit(int(p["id"]))
	gate_group.clear()
	_group_ready_t = t + float(bal["arrivals"]["group_cooldown_s"])
	changed.emit()


func _pay(cost: Dictionary) -> void:
	for r in cost:
		stock[r] = float(stock[r]) - float(cost[r])


func _mark(b: Dictionary, on: bool) -> void:
	var fp := _fp(String(b["type"]))
	for dy in fp.y:
		for dx in fp.x:
			occ[_i(Vector2i(b["cell"]) + Vector2i(dx, dy))] = int(b["id"]) if on else -1


# ================================================================ caminhos
func _rebuild_astar() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, w, h)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			var k := terrain[_i(c)]
			if occ[_i(c)] >= 0 or k == T_TREE or k == T_RUBBLE:
				_astar.set_point_solid(c, true)


func _path(from: Vector2, to: Vector2i) -> PackedVector2Array:
	var a := Vector2i(floori(from.x + 0.5), floori(from.y + 0.5))
	a = Vector2i(clampi(a.x, 0, w - 1), clampi(a.y, 0, h - 1))
	var solid_a := _astar.is_point_solid(a)
	var solid_b := _astar.is_point_solid(to)
	_astar.set_point_solid(a, false)
	_astar.set_point_solid(to, false)
	var pts := _astar.get_point_path(a, to, true)
	_astar.set_point_solid(a, solid_a)
	_astar.set_point_solid(to, solid_b)
	return pts


# ================================================================ pessoas
func _add_person(nm: String, look: int, passives: Array, at: Vector2i, story: String = "", bio: int = -1) -> Dictionary:
	var p := {"id": _next_id, "name": nm, "look": look, "passives": passives.duplicate(true),
			"pos": Vector2(at), "path": PackedVector2Array(), "job": {}, "phase": "idle",
			"carry_res": "", "carry": 0.0, "work_t": 0.0, "hungry": false, "thirsty": false,
			"eat_acc": 0.0, "drink_acc": 0.0, "facing": Vector2.DOWN, "moving": false,
			"story": story, "bio": bio, "asleep": false, "target_cell": Vector2i(-1, -1)}
	_next_id += 1
	people.append(p)
	stats["joined"] = int(stats["joined"]) + 1
	return p


func bonus(p: Dictionary, job: String) -> float:
	var m := 1.0
	for ps in p["passives"]:
		var pd: Dictionary = bal["passives"].get(String(ps["id"]), {})
		if String(pd.get("job", "")) == job:
			m += float(bal["rarity"][String(ps["rar"])]["bonus"])
	return m


func _speed(p: Dictionary) -> float:
	var s: float = float(bal["people"]["speed_tiles_s"]) * bonus(p, "walk")
	return s * (float(bal["people"]["hungry_speed"]) if (p["hungry"] or p["thirsty"]) else 1.0)


func _work_mult(p: Dictionary) -> float:
	return float(bal["people"]["hungry_speed"]) if (p["hungry"] or p["thirsty"]) else 1.0


## O que mais falta, de 0 a ~2. Comida e água pesam pelo consumo; madeira e sucata pela próxima meta.
func urgency(res: String) -> float:
	var s: float = float(stock[res])
	if s >= cap(res) - 0.5:
		return 0.0
	var want: float
	if res == "comida" or res == "agua":
		want = 10.0 + float(people.size()) * 8.0
		if res == "agua" and _count("horta") > 0:
			want += 6.0
	else:
		want = 15.0
		var nx := tower_next()
		if not nx.is_empty() and tower < tower_max():
			want = maxf(want, float(nx["cost"].get(res, 0)))
	want = minf(want, cap(res))
	var u: float = clampf((want - s) / maxf(1.0, want), 0.0, 1.0)
	if res == "comida" or res == "agua":
		u = u * 1.5 + (0.6 if s < 4.0 else 0.0)
	return u + 0.08   # nunca zero: estoque abaixo do limite ainda vale alguma coisa


func _count(type: String) -> int:
	var n := 0
	for b in buildings:
		if String(b["type"]) == type and _working(b):
			n += 1
	return n


func _assigned_to(res: String, except: Dictionary) -> int:
	var n := 0
	for p in people:
		if p == except:
			continue
		var j: Dictionary = p["job"]
		if String(j.get("res", "")) == res:
			n += 1
	return n


## Escolhe o próximo trabalho: obra sem construtor primeiro, depois o recurso que mais falta.
func _pick_job(p: Dictionary) -> Dictionary:
	if is_night():
		return {"kind": "sleep"}
	# Obras em ordem de chegada: uma pessoa por obra.
	var sites: Array[Dictionary] = []
	for b in buildings:
		if String(b["state"]) != "built" and int(b["builder"]) < 0:
			sites.append(b)
	sites.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return float(a["queued_t"]) < float(c["queued_t"]))
	if not sites.is_empty():
		# Se a pessoa está num trabalho de recurso que está faltando muito e há mais gente, deixa outra pegar.
		return {"kind": "build", "b": int(sites[0]["id"])}
	var best := {}
	var best_v := 0.0
	# Entulho marcado pelo jogador: limpar vale a pena mesmo com sucata sobrando (é o espaço que importa).
	if not marked.is_empty() and _nearest_forage("sucata", p["pos"]) != Vector2i(-1, -1):
		var assigned := _assigned_to("sucata", p)
		if assigned < maxi(1, people.size() / 2):
			best = {"kind": "forage", "res": "sucata", "clear": true}
			best_v = 0.6 * float(bal["forage"]["sucata"]["yield"]) / (float(bal["forage"]["sucata"]["work_s"]) + 8.0) / 3.0
	for res in RES:
		var u := urgency(res) / (1.0 + float(_assigned_to(res, p)))
		if u <= 0.0:
			continue
		# Prédio com vaga livre
		for b in buildings:
			if not _working(b) or String(def(String(b["type"])).get("res", "")) != res:
				continue
			var lv := level_def(b)
			if (b["workers"] as Array).size() >= int(lv.get("slots", 0)):
				continue
			var rate: float = 1.0 / float(lv["rate_s"])
			var v: float = u * rate * bonus(p, res)
			if v > best_v:
				best_v = v
				best = {"kind": "work", "b": int(b["id"]), "res": res}
		# Coleta à mão (madeira nas árvores, sucata no entulho)
		if res == "madeira" or res == "sucata":
			var f: Dictionary = bal["forage"][res]
			var rate_f: float = float(f["yield"]) / (float(f["work_s"]) + 8.0) / 3.0
			var v2: float = u * rate_f * bonus(p, res)
			if v2 > best_v and _nearest_forage(res, p["pos"]) != Vector2i(-1, -1):
				best_v = v2
				best = {"kind": "forage", "res": res}
	if best.is_empty():
		return {"kind": "idle"}
	return best


func _forage_cells(kind: int) -> Array:
	if _fdirty:
		_fdirty = false
		_fcache = {T_TREE: [], T_RUBBLE: []}
		for i in terrain.size():
			var k: int = terrain[i]
			if k == T_TREE or k == T_RUBBLE:
				(_fcache[k] as Array).append(Vector2i(i % w, i / w))
	return _fcache.get(kind, [])


func _nearest_forage(res: String, from: Vector2) -> Vector2i:
	var kind := T_TREE if res == "madeira" else T_RUBBLE
	var best := Vector2i(-1, -1)
	var bd := 1e9
	var taken := {}
	for q in people:
		if q["target_cell"] != Vector2i(-1, -1):
			taken[q["target_cell"]] = true
	if res == "sucata":
		for c0 in marked:
			if taken.has(c0) or terrain[_i(c0)] != T_RUBBLE or not _reachable_neighbor(c0):
				continue
			var d0 := from.distance_squared_to(Vector2(c0))
			if d0 < bd:
				bd = d0
				best = c0
		if best != Vector2i(-1, -1):
			return best
	for c in _forage_cells(kind):
		if taken.has(c):
			continue
		var d := from.distance_squared_to(Vector2(c))
		if d >= bd or not _reachable_neighbor(c):
			continue
		bd = d
		best = c
	return best


func _reachable_neighbor(c: Vector2i) -> bool:
	for o in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
		var n: Vector2i = c + o
		if _inside(n) and not _astar.is_point_solid(n):
			return true
	return false


func _free_neighbor(c: Vector2i, from: Vector2) -> Vector2i:
	var best := c
	var bd := 1e9
	for o in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
		var n: Vector2i = c + o
		if _inside(n) and not _astar.is_point_solid(n):
			var d := from.distance_squared_to(Vector2(n))
			if d < bd:
				bd = d
				best = n
	return best


func _storage_door(from: Vector2, res: String) -> Dictionary:
	var best := {}
	var bd := 1e9
	for b in buildings:
		var d0 := def(String(b["type"]))
		if not bool(d0.get("storage", false)) or not _working(b):
			continue
		var d := from.distance_squared_to(Vector2(_door(b)))
		if d < bd:
			bd = d
			best = b
	return best


func _release_workers(b: Dictionary) -> void:
	for pid in (b["workers"] as Array).duplicate():
		var p := person(int(pid))
		if not p.is_empty():
			_set_job(p, {"kind": "idle"})
	b["workers"] = []


func _release_builder(b: Dictionary) -> void:
	var p := person(int(b["builder"]))
	b["builder"] = -1
	if not p.is_empty():
		_set_job(p, {"kind": "idle"})


func _set_job(p: Dictionary, job: Dictionary) -> void:
	var old: Dictionary = p["job"]
	if String(old.get("kind", "")) == "work":
		var ob := by_id(int(old["b"]))
		if not ob.is_empty():
			(ob["workers"] as Array).erase(int(p["id"]))
	elif String(old.get("kind", "")) == "build":
		var ob2 := by_id(int(old["b"]))
		if not ob2.is_empty() and int(ob2["builder"]) == int(p["id"]):
			ob2["builder"] = -1
	p["target_cell"] = Vector2i(-1, -1)
	p["job"] = job
	p["path"] = PackedVector2Array()
	p["work_t"] = 0.0
	p["asleep"] = false
	var k := String(job.get("kind", "idle"))
	match k:
		"work":
			var b := by_id(int(job["b"]))
			(b["workers"] as Array).append(int(p["id"]))
			_go(p, _door(b))
			p["phase"] = "to_work"
		"build":
			var b2 := by_id(int(job["b"]))
			b2["builder"] = int(p["id"])
			_go(p, _door(b2))
			p["phase"] = "to_build"
		"forage":
			var c := _nearest_forage(String(job["res"]), p["pos"])
			p["target_cell"] = c
			_go(p, _free_neighbor(c, p["pos"]))
			p["phase"] = "to_forage"
		"sleep":
			_go(p, _bed_door(p))
			p["phase"] = "to_bed"
		_:
			p["phase"] = "idle"


func _bed_door(p: Dictionary) -> Vector2i:
	# Joaquim dorme no bunker; os outros na casa/barraco mais perto (camas não são nominais no protótipo).
	var best := _door(_first("hatch"))
	var bd := 1e9
	for b in buildings:
		var tp := String(b["type"])
		if tp == "moradia" and String(b["state"]) != "site":
			var d := Vector2(p["pos"]).distance_squared_to(Vector2(_door(b)))
			if d < bd:
				bd = d
				best = _door(b)
	return best


func _go(p: Dictionary, cell: Vector2i) -> void:
	var path := _path(p["pos"], cell)
	if path.size() > 0:
		path.remove_at(0)
	p["path"] = path


## Anda `dist` tiles pelo caminho. Devolve true quando chegou.
func _walk(p: Dictionary, dt: float) -> bool:
	var path: PackedVector2Array = p["path"]
	var dist := _speed(p) * dt
	var pos: Vector2 = p["pos"]
	p["moving"] = path.size() > 0
	while dist > 0.0 and path.size() > 0:
		var tgt := path[0]
		var d := pos.distance_to(tgt)
		if d <= dist:
			if d > 0.001:
				p["facing"] = (tgt - pos).normalized()
			pos = tgt
			dist -= d
			path.remove_at(0)
		else:
			p["facing"] = (tgt - pos).normalized()
			pos += (tgt - pos) / d * dist
			dist = 0.0
	p["pos"] = pos
	p["path"] = path
	return path.size() == 0


# ================================================================ passo
func advance(seconds: float) -> void:
	var step: float = float(bal["time"]["offline_step_s"] if offline else bal["time"]["step_s"])
	var left := seconds
	while left > 1e-6:
		# Noite com todo mundo dormindo: nada anda, pula direto para a manhã.
		if is_night() and _all_asleep():
			var to_morning := _secs_to_morning()
			var jump := minf(left, to_morning)
			if jump > step:
				t += jump - 0.01
				left -= jump - 0.01
				_regrow()
				continue
		var dt := minf(step, left)
		_step(dt)
		left -= dt


func _all_asleep() -> bool:
	for p in people:
		if not p["asleep"]:
			return false
	return true


func _secs_to_morning() -> float:
	var hr := local_hour()
	var z: float = float(bal["time"]["night_to_h"])
	var dh: float = z - hr if hr < z else 24.0 - hr + z
	return dh * 3600.0


func _step(dt: float) -> void:
	t += dt
	var night := is_night()
	_needs(dt, night)
	_regrow()
	_arrivals()
	_rethink_acc += dt
	var rethink := _rethink_acc >= float(bal["people"]["rethink_s"])
	if rethink:
		_rethink_acc = 0.0
	for p in people:
		_person_step(p, dt, night, rethink)


func _prod_frac() -> float:
	return float(bal["time"]["offline_fraction"]) if offline else 1.0


func _needs(dt: float, night: bool) -> void:
	if night:
		return
	var eat_s: float = float(bal["people"]["eat_every_s"])
	var drink_s: float = float(bal["people"]["drink_every_s"])
	var f := _prod_frac()
	for p in people:
		var em := 1.0 / bonus(p, "eat")
		p["eat_acc"] = float(p["eat_acc"]) + dt * f * em / eat_s
		p["drink_acc"] = float(p["drink_acc"]) + dt * f / drink_s
		while float(p["eat_acc"]) >= 1.0:
			p["eat_acc"] = float(p["eat_acc"]) - 1.0
			if float(stock["comida"]) >= 1.0:
				stock["comida"] = float(stock["comida"]) - 1.0
				p["hungry"] = false
			else:
				p["hungry"] = true
		while float(p["drink_acc"]) >= 1.0:
			p["drink_acc"] = float(p["drink_acc"]) - 1.0
			if float(stock["agua"]) >= 1.0:
				stock["agua"] = float(stock["agua"]) - 1.0
				p["thirsty"] = false
			else:
				p["thirsty"] = true
		# Comeu assim que chegou comida: a fome some sem esperar a próxima refeição.
		if p["hungry"] and float(stock["comida"]) >= 1.0:
			stock["comida"] = float(stock["comida"]) - 1.0
			p["hungry"] = false
		if p["thirsty"] and float(stock["agua"]) >= 1.0:
			stock["agua"] = float(stock["agua"]) - 1.0
			p["thirsty"] = false


func _regrow() -> void:
	if regrow.is_empty():
		return
	for c in regrow.keys():
		if t >= float(regrow[c]) and occ[_i(c)] < 0:
			var busy := false
			for p in people:
				if Vector2i(Vector2(p["pos"]).round()) == c:
					busy = true
			if not busy:
				terrain[_i(c)] = T_TREE
				_fdirty = true
				regrow.erase(c)
				_astar.set_point_solid(c, true)


func _arrivals() -> void:
	if tower < int(bal["arrivals"]["story_tower"]) or beds_free() <= 0:
		return
	var story: String = String(bal["arrivals"]["story_first"])
	if not _story_done.has(story):
		_story_done[story] = true
		var sd: Dictionary = bal["story_people"][story]
		var from := _v(bal["arrivals"]["walk_in_from"])
		var p := _add_person(tr_name(story), int(sd["look"]), sd["passives"], from, story)
		person_joined.emit(int(p["id"]))
		_group_ready_t = t + float(bal["arrivals"]["first_group_delay_s"])
		changed.emit()
		return
	if gate_group.is_empty() and _group_ready_t >= 0.0 and t >= _group_ready_t:
		_make_group()
		group_arrived.emit()
		changed.emit()
	elif _group_ready_t < 0.0:
		_group_ready_t = t + float(bal["arrivals"]["first_group_delay_s"])


## Nome das pessoas da história vem do I18n na vista; aqui fica a chave.
func tr_name(story: String) -> String:
	return "@" + story


func _make_group() -> void:
	gate_group.clear()
	var names: Array = (bal["names"] as Array).duplicate()
	for p in people:
		names.erase(String(p["name"]))
	var ids: Array = bal["passives"].keys()
	for k in 3:
		var nm: String = String(names[_rng.randi_range(0, names.size() - 1)]) if not names.is_empty() else "?"
		names.erase(nm)
		var passives: Array = []
		var n := 2 if _rng.randf() < float(bal["arrivals"]["two_passives_chance"]) else 1
		var used := {}
		for i in n:
			var pid: String = String(ids[_rng.randi_range(0, ids.size() - 1)])
			while used.has(pid):
				pid = String(ids[_rng.randi_range(0, ids.size() - 1)])
			used[pid] = true
			passives.append({"id": pid, "rar": _roll_rarity()})
		var brings := {}
		if _rng.randf() < float(bal["arrivals"]["brings_chance"]):
			var amt: Array = bal["arrivals"]["brings_amount"]
			brings[RES[_rng.randi_range(0, RES.size() - 1)]] = _rng.randi_range(int(amt[0]), int(amt[1]))
		gate_group.append({"name": nm, "look": _rng.randi_range(1, 5), "passives": passives,
				"brings": brings, "bio": _rng.randi_range(0, int(bal["bios"]) - 1)})


func _roll_rarity() -> String:
	var pity: int = int(bal["arrivals"]["pity_after_commons"])
	var r: String
	if int(stats["commons_in_row"]) >= pity:
		r = "rara" if _rng.randf() < 0.83 else "excelente"
	else:
		var total := 0.0
		for k in bal["rarity"]:
			total += float(bal["rarity"][k]["weight"])
		var x := _rng.randf() * total
		r = "comum"
		for k in ["excelente", "rara", "comum"]:
			x -= float(bal["rarity"][k]["weight"])
			if x <= 0.0:
				r = k
				break
	stats["commons_in_row"] = int(stats["commons_in_row"]) + 1 if r == "comum" else 0
	return r


func _person_step(p: Dictionary, dt: float, night: bool, rethink: bool) -> void:
	var job: Dictionary = p["job"]
	var kind := String(job.get("kind", "idle"))
	# Noite: larga tudo e vai dormir (a carga volta com ele de manhã).
	if night and kind != "sleep":
		_set_job(p, {"kind": "sleep"})
		kind = "sleep"
	elif not night and kind == "sleep":
		_set_job(p, {"kind": "idle"})
		kind = "idle"
	if kind == "idle":
		p["moving"] = false
		if rethink or p["phase"] == "idle":
			var nj := _pick_job(p)
			if String(nj["kind"]) != "idle":
				_set_job(p, nj)
			else:
				p["phase"] = "waiting"
				_wander(p, dt)
		else:
			_wander(p, dt)
		return
	match kind:
		"sleep":
			if _walk(p, dt):
				p["asleep"] = true
		"build":
			_do_build(p, dt)
		"work":
			_do_work(p, dt)
		"forage":
			_do_forage(p, dt)


func _wander(p: Dictionary, dt: float) -> void:
	_walk(p, dt)


func _do_build(p: Dictionary, dt: float) -> void:
	var b := by_id(int(p["job"]["b"]))
	if b.is_empty() or String(b["state"]) == "built":
		_set_job(p, {"kind": "idle"})
		return
	if p["phase"] == "to_build":
		if _walk(p, dt):
			p["phase"] = "building"
		return
	p["moving"] = false
	p["facing"] = Vector2.UP
	b["progress"] = float(b["progress"]) + dt * bonus(p, "build") * _work_mult(p)
	if float(b["progress"]) >= float(b["total"]):
		_finish(b)
		_set_job(p, {"kind": "idle"})


func _finish(b: Dictionary) -> void:
	b["builder"] = -1
	var tp := String(b["type"])
	if tp == "torre":
		tower += 1
		b["state"] = "built"
		_open_area(tower)
		tower_up.emit(tower)
	elif String(b["state"]) == "upgrade":
		b["level"] = int(b["level"]) + 1
		b["state"] = "built"
	else:
		b["state"] = "built"
	stats["built"] = int(stats["built"]) + 1
	building_done.emit(int(b["id"]))
	changed.emit()


func _do_work(p: Dictionary, dt: float) -> void:
	var b := by_id(int(p["job"]["b"]))
	var res := String(p["job"]["res"])
	if b.is_empty() or not _working(b):
		_set_job(p, {"kind": "idle"})
		return
	match String(p["phase"]):
		"to_work":
			if _walk(p, dt):
				p["phase"] = "working"
		"working":
			p["moving"] = false
			p["facing"] = Vector2.UP
			var lv := level_def(b)
			var m := bonus(p, res) * _work_mult(p) * _prod_frac()
			if res == "comida":
				var need_w: float = float(bal["horta_water_per_food"])
				if float(stock["agua"]) < need_w:
					m *= float(bal["no_water_horta_speed"])
			var gain := dt * m / float(lv["rate_s"])
			if res == "comida" and float(stock["agua"]) >= float(bal["horta_water_per_food"]) * gain:
				stock["agua"] = float(stock["agua"]) - float(bal["horta_water_per_food"]) * gain
			p["carry_res"] = res
			p["carry"] = float(p["carry"]) + gain
			if float(p["carry"]) >= float(bal["people"]["carry"]):
				_to_storage(p)
		"to_store":
			if _walk(p, dt):
				_deliver(p)
				if urgency(res) <= 0.0 or (p["hungry"] and false):
					_set_job(p, {"kind": "idle"})
					return
				# Repensa: pode haver algo mais urgente (obra nova, outro recurso faltando).
				var nj := _pick_job(p)
				if String(nj.get("kind", "")) != "work" or int(nj.get("b", -1)) != int(b["id"]):
					if String(nj.get("kind", "")) != "idle":
						_set_job(p, nj)
						return
				_go(p, _door(b))
				p["phase"] = "to_work"


func _do_forage(p: Dictionary, dt: float) -> void:
	var res := String(p["job"]["res"])
	var f: Dictionary = bal["forage"][res]
	var c: Vector2i = p["target_cell"]
	match String(p["phase"]):
		"to_forage":
			var kind := T_TREE if res == "madeira" else T_RUBBLE
			if c == Vector2i(-1, -1) or terrain[_i(c)] != kind:
				_set_job(p, {"kind": "idle"})
				return
			if _walk(p, dt):
				p["phase"] = "foraging"
				p["work_t"] = 0.0
				p["facing"] = (Vector2(c) - Vector2(p["pos"])).normalized()
		"foraging":
			p["moving"] = false
			p["work_t"] = float(p["work_t"]) + dt * bonus(p, res) * _work_mult(p) * _prod_frac()
			if float(p["work_t"]) >= float(f["work_s"]):
				var y: float = float(f["yield"])
				if res == "madeira":
					terrain[_i(c)] = T_STUMP
					_fdirty = true
					regrow[c] = t + float(f["regrow_s"])
					_astar.set_point_solid(c, false)
				else:
					var left: int = int(rubble.get(c, 0)) - int(y)
					if left <= 0:
						rubble.erase(c)
						marked.erase(c)
						terrain[_i(c)] = T_GROUND
						_fdirty = true
						_astar.set_point_solid(c, false)
					else:
						rubble[c] = left
				p["target_cell"] = Vector2i(-1, -1)
				p["carry_res"] = res
				p["carry"] = float(p["carry"]) + y
				changed.emit()
				_to_storage(p)
		"to_store":
			if _walk(p, dt):
				_deliver(p)
				_set_job(p, {"kind": "idle"})
				p["phase"] = "idle"


func _to_storage(p: Dictionary) -> void:
	var s := _storage_door(p["pos"], String(p["carry_res"]))
	if s.is_empty():
		return
	_go(p, _door(s))
	p["phase"] = "to_store"


func _deliver(p: Dictionary) -> void:
	var res := String(p["carry_res"])
	if res == "":
		return
	var room: float = cap(res) - float(stock[res])
	var amt: float = minf(float(p["carry"]), maxf(0.0, room))
	stock[res] = float(stock[res]) + amt
	p["carry"] = 0.0
	p["carry_res"] = ""
	if amt >= 0.5:
		harvested.emit(int(p["id"]), res, int(round(amt)))
	changed.emit()


# ================================================================ resumo para a interface
## Saldo aproximado por minuto (produção estimada pelas vagas ocupadas menos consumo).
func balance_per_min(res: String) -> float:
	var prod := 0.0
	for p in people:
		var j: Dictionary = p["job"]
		if String(j.get("res", "")) != res:
			continue
		if String(j["kind"]) == "work":
			var b := by_id(int(j["b"]))
			if not b.is_empty():
				prod += 60.0 / float(level_def(b)["rate_s"]) * bonus(p, res) * 0.75
		elif String(j["kind"]) == "forage":
			var f: Dictionary = bal["forage"][res]
			prod += 60.0 * float(f["yield"]) / (float(f["work_s"]) + 10.0) * bonus(p, res)
	var use := 0.0
	if res == "comida":
		for p in people:
			use += 60.0 / float(bal["people"]["eat_every_s"]) / bonus(p, "eat")
	elif res == "agua":
		use = 60.0 / float(bal["people"]["drink_every_s"]) * float(people.size())
		for p in people:
			if String(p["job"].get("res", "")) == "comida" and String(p["job"].get("kind", "")) == "work":
				use += 60.0 / 45.0 * float(bal["horta_water_per_food"])
	return prod - use


func doing(p: Dictionary) -> String:
	var j: Dictionary = p["job"]
	var k := String(j.get("kind", "idle"))
	if k == "sleep":
		return "sleep" if p["asleep"] else "to_bed"
	if k == "build":
		var b := by_id(int(j["b"]))
		return "build:" + (String(b.get("type", "")) if not b.is_empty() else "")
	if k == "work":
		var b2 := by_id(int(j["b"]))
		return ("carry:" if String(p["phase"]) == "to_store" else "work:") + String(b2.get("type", ""))
	if k == "forage":
		return ("carry:" if String(p["phase"]) == "to_store" else "forage:") + String(j["res"])
	return "idle"


## Uma meta curta para a barra de baixo: o que a torre pede, ou a primeira coisa básica que falta.
func goal() -> Dictionary:
	for type in ["poco", "horta", "deposito"]:
		if _count_any(type) == 0:
			return {"kind": "build", "type": type}
	# Gente parada e comida ou água acabando: falta vaga de trabalho, não gente.
	var idle := 0
	for p in people:
		if String(p["job"].get("kind", "idle")) == "idle":
			idle += 1
	if not is_night():
		for pair in [["comida", "horta"], ["agua", "poco"]]:
			if idle > 0 and urgency(pair[0]) > 0.6:
				return {"kind": "more", "type": pair[1], "res": pair[0], "idle": idle}
			if float(stock[pair[0]]) <= 3.0 and balance_per_min(pair[0]) < 0.0:
				return {"kind": "short", "type": pair[1], "res": pair[0]}
	if tower >= 2 and beds_free() <= 0 and _count_any("moradia") < 6:
		return {"kind": "beds"}
	# A próxima torre pede mais do que cabe: falta melhorar o depósito.
	if tower < tower_max() and String(tower_building()["state"]) == "built":
		var nxc: Dictionary = tower_next()["cost"]
		for r in nxc:
			if float(nxc[r]) > cap(r):
				return {"kind": "storage", "res": r, "need": int(nxc[r]), "cap": int(cap(r))}
	if _free_build_cells() < 6 and tower < tower_max() and String(tower_building()["state"]) == "built":
		var nx0 := tower_next()
		if not can_afford(nx0["cost"]):
			return {"kind": "space"}
	if tower < tower_max():
		var tb := tower_building()
		if String(tb["state"]) != "built":
			return {"kind": "tower_wait", "level": tower + 1}
		var nx := tower_next()
		return {"kind": "tower", "level": tower + 1, "missing": missing(nx["cost"])}
	return {"kind": "done"}


## Quantas células livres de construção restam (para avisar que falta chão).
func _free_build_cells() -> int:
	var n := 0
	for i in terrain.size():
		if occ[i] < 0 and (terrain[i] == T_GROUND or terrain[i] == T_STUMP):
			n += 1
	return n


func _count_any(type: String) -> int:
	var n := 0
	for b in buildings:
		if String(b["type"]) == type:
			n += 1
	return n


# ================================================================ save
func to_dict() -> Dictionary:
	var bs: Array = []
	for b in buildings:
		bs.append({"id": b["id"], "type": b["type"], "cell": [b["cell"].x, b["cell"].y], "level": b["level"],
				"state": b["state"], "progress": b["progress"], "total": b["total"], "queued_t": b.get("queued_t", 0.0)})
	var ps: Array = []
	for p in people:
		ps.append({"id": p["id"], "name": p["name"], "look": p["look"], "passives": p["passives"],
				"pos": [p["pos"].x, p["pos"].y], "story": p["story"], "bio": p["bio"],
				"eat_acc": p["eat_acc"], "drink_acc": p["drink_acc"],
				"carry_res": p["carry_res"], "carry": p["carry"]})
	var rg: Array = []
	for c in regrow:
		rg.append([c.x, c.y, regrow[c]])
	var rb: Array = []
	for c in rubble:
		rb.append([c.x, c.y, rubble[c]])
	return {"v": 1, "t": t, "start_t": start_t, "stock": stock, "tower": tower, "terrain": Marshalls.raw_to_base64(terrain),
			"buildings": bs, "people": ps, "regrow": rg, "rubble": rb, "gate": gate_group,
			"marked": marked.keys().map(func(c: Vector2i) -> Array: return [c.x, c.y]),
			"stats": stats, "next_id": _next_id, "group_t": _group_ready_t, "story": _story_done.keys(),
			"rng": _rng.state}


func from_dict(d: Dictionary, balance: Dictionary, tz_bias: int = 0) -> void:
	bal = balance
	tz_bias_s = tz_bias
	var m: Dictionary = bal["map"]
	w = int(m["w"])
	h = int(m["h"])
	t = float(d["t"])
	start_t = float(d.get("start_t", t))
	stock = {}
	for r in RES:
		stock[r] = float(d["stock"].get(r, 0.0))
	tower = int(d["tower"])
	terrain = Marshalls.base64_to_raw(String(d["terrain"]))
	_fdirty = true
	occ = PackedInt32Array()
	occ.resize(w * h)
	occ.fill(-1)
	buildings.clear()
	for e in d["buildings"]:
		var b := {"id": int(e["id"]), "type": String(e["type"]), "cell": Vector2i(int(e["cell"][0]), int(e["cell"][1])),
				"level": int(e["level"]), "state": String(e["state"]), "progress": float(e["progress"]),
				"total": float(e["total"]), "workers": [], "builder": -1, "acc": 0.0, "queued_t": float(e.get("queued_t", 0.0))}
		buildings.append(b)
		if not bool(def(String(b["type"])).get("walkable", false)):
			_mark(b, true)
	people.clear()
	for e in d["people"]:
		var p := _add_person(String(e["name"]), int(e["look"]), e["passives"], Vector2i.ZERO, String(e["story"]), int(e["bio"]))
		p["id"] = int(e["id"])
		p["pos"] = Vector2(float(e["pos"][0]), float(e["pos"][1]))
		p["eat_acc"] = float(e["eat_acc"])
		p["drink_acc"] = float(e["drink_acc"])
		p["carry_res"] = String(e.get("carry_res", ""))
		p["carry"] = float(e.get("carry", 0.0))
	regrow.clear()
	for e in d["regrow"]:
		regrow[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	rubble.clear()
	for e in d["rubble"]:
		rubble[Vector2i(int(e[0]), int(e[1]))] = int(e[2])
	marked.clear()
	for e in d.get("marked", []):
		marked[Vector2i(int(e[0]), int(e[1]))] = true
	gate_group.clear()
	for g in d["gate"]:
		gate_group.append(g)
	stats = d["stats"]
	_next_id = int(d["next_id"])
	_group_ready_t = float(d["group_t"])
	_story_done.clear()
	for s in d["story"]:
		_story_done[String(s)] = true
	_rng.state = int(d["rng"])
	_rebuild_astar()
	# Quem estava carregando entrega no depósito ao voltar (não se perde nada).
	for p in people:
		if String(p["carry_res"]) != "":
			_deliver(p)


## Alcança o relógio depois de um tempo fechado. Devolve o que mudou, para o resumo.
func catch_up(now_unix: float) -> Dictionary:
	var elapsed: float = now_unix - t
	var tb: Dictionary = bal["time"]
	if elapsed < float(tb["offline_min_s"]):
		if elapsed > 0.0:
			advance(elapsed)
		return {}
	elapsed = minf(elapsed, float(tb["offline_cap_h"]) * 3600.0)
	var before := stock.duplicate()
	var built0: int = int(stats["built"])
	var joined0: int = int(stats["joined"])
	offline = true
	advance(elapsed)
	offline = false
	t = maxf(t, now_unix)
	var delta := {}
	for r in RES:
		delta[r] = int(round(float(stock[r]) - float(before[r])))
	return {"seconds": elapsed, "delta": delta, "built": int(stats["built"]) - built0,
			"joined": int(stats["joined"]) - joined0, "group": not gate_group.is_empty()}
