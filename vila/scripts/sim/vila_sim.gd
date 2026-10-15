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
signal site_started(id: int)                       # obra nova, melhoria ou torre começou (som de martelo)
signal fog_started                                 # noite de névoa de pólen começou
signal fog_ended                                   # amanheceu depois da névoa (hortas rendem mais)
signal merchant_arrived                            # o mercador chegou à praça
signal merchant_left(sold: Dictionary)             # foi embora (o que vendeu sozinho, se a venda automática estava ligada)
signal radio(line: Dictionary)                     # uma fala do rádio chegou: {id, speaker, text_key, cue, kind}
signal ela_arrived                                 # ela entrou pelo portão (o final)

const RES: Array[String] = ["comida", "agua", "madeira", "sucata", "pecas"]
const T_GROUND := 0
const T_TREE := 1
const T_RUBBLE := 2
const T_ROAD := 3
const T_STUMP := 4
const T_WATER := 5     # rio em volta da ilha (balance map.island: '.' = água)

var bal: Dictionary = {}
var t: float = 0.0
var tz_bias_s: int = 0
var cycle_t0: float = 0.0       # relógio da vila: instante em que o ciclo marcou 0h (balance "night.cycle_s")
var work_tonight: bool = false  # "virar a noite": vale só para a noite atual
var fog_next: bool = false      # a próxima noite vem com névoa de pólen (avisado durante o dia)
var fog_now: bool = false       # esta noite tem névoa: ninguém sai, quem dorme sem cama passa mal
var fog_bonus_until: float = 0.0   # depois da névoa o pólen aduba a terra: hortas rendem mais até aqui
var _was_night: bool = false
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
var _m_builders := -1     # cache por passo: quantos bons de obra estão livres
var _day_flow := {}       # ritmo de cada recurso no último trecho de dia (de noite ninguém trabalha nem come)
var _day_flow_t := 0.0
var _reach_main := {}   # células alcançáveis a pé da escotilha (cache; vazio = refazer)
var _rng := RandomNumberGenerator.new()
var _group_ready_t: float = -1.0
var _story_done: Dictionary = {}
var tower_t: Dictionary = {}       # nível da torre -> quando chegou (o rádio conta os dias a partir daí)
var perks: Dictionary = {}         # melhorias compradas do mercador: id -> quantas
var merchant: Dictionary = {}      # visita atual: {key, until, prices, offers, bought, request}; vazio = longe
var auto_pick: bool = false        # o portão escolhe sozinho quem entra (melhor para o que falta)
var auto_sell: bool = true         # o mercador vende a sobra sozinho quando ninguém está olhando
var radio_heard: Array = []        # ids das falas do rádio já ouvidas, em ordem (o caderno do rádio)
var ela_t: float = -1.0            # quando ela chegou (fim); -1 = ainda não
var _merchant_key: int = -1
var _lines: Array = []             # falas do rádio e da viagem com a hora em que tocam (refeito quando a torre sobe)
var _lines_dirty: bool = true
var _line_i: int = 0
var _m_power: Dictionary = {}
var _rethink_acc: float = 0.0
var _m_cap: Dictionary = {}
var _m_urg: Dictionary = {}
var _m_beds: int = -1
var _id_index: Dictionary = {}
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
	# O porto: é por ele que o bote traz quem chega (existe desde o começo).
	_place_fixed("gate", _v(m["gate"]))
	_carve_trail(_door(_first("gate")), _door(_first("hatch")))
	_rebuild_astar()
	var hatch: Dictionary = _first("hatch")
	_add_person("Joaquim", 0, [], _door(hatch), "joaquim")
	tower_t = {1: t}
	set_cycle_hour(float(bal["night"]["start_hour"]))
	_was_night = is_night()


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
	var clump := FastNoiseLite.new()
	clump.seed = int(m["seed"]) + 11
	clump.frequency = 0.12
	for y in h:
		for x in w:
			var i := y * w + x
			var d := Vector2(x, y).distance_to(c) + noise.get_noise_2d(x, y) * 1.2
			var k := T_GROUND
			var r := _rng.randf()
			var trees := clump.get_noise_2d(x, y) > 0.18   # árvores em bosques, não espalhadas
			if not _island(x, y):
				k = T_WATER
			elif d <= r1:
				k = T_GROUND
			elif d <= rmax + 1.5:
				# Em volta da clareira: chão com alguns montes de entulho e um ou outro bosque.
				if trees and d > r1 + 1.5:
					k = T_TREE
				elif r < float(m.get("ring_rubble", 0.16)):
					k = T_RUBBLE
			elif _shore(x, y) and r < float(m.get("shore_rubble", 0.0)):
				k = T_RUBBLE   # o que o rio trouxe e largou na beira
			else:
				if trees or r < 0.06:
					k = T_TREE
				elif r < 0.06 + float(m.get("outer_rubble", 0.05)):
					k = T_RUBBLE
			terrain[i] = k
			if k == T_RUBBLE:
				rubble[Vector2i(x, y)] = int(bal["rubble_amount"])


func _shore(x: int, y: int) -> bool:
	return not _island(x - 1, y) or not _island(x + 1, y) or not _island(x, y - 1) or not _island(x, y + 1)


## Trilha do porto até a clareira: o caminho mais curto por terra vira chão (árvore e entulho no meio
## saem). Sem ela, quem chegava pelo bote ficava preso no píer cercado de mata.
func _carve_trail(from: Vector2i, to: Vector2i) -> void:
	var ag := AStarGrid2D.new()
	ag.region = Rect2i(0, 0, w, h)
	ag.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	ag.update()
	for y in h:
		for x in w:
			var k := terrain[y * w + x]
			var o := occ[y * w + x]
			if k == T_WATER or (o >= 0 and not bool(def(String(by_id(o).get("type", ""))).get("walkable", false))):
				ag.set_point_solid(Vector2i(x, y), true)
			elif k == T_TREE or k == T_RUBBLE:
				ag.set_point_weight_scale(Vector2i(x, y), 4.0)   # contorna a mata quando dá
	for c in ag.get_id_path(from, to):
		var k := terrain[_i(c)]
		if k == T_TREE or k == T_RUBBLE:
			terrain[_i(c)] = T_GROUND
			rubble.erase(c)
			_fdirty = true


## Terra ou água pela máscara da ilha (sem máscara: tudo terra).
func _island(x: int, y: int) -> bool:
	var rows: Array = bal["map"].get("island", [])
	if rows.is_empty():
		return true
	if y < 0 or y >= rows.size() or x < 0 or x >= String(rows[y]).length():
		return false
	return String(rows[y])[x] == "#"


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
	if _inside(door) and terrain[_i(door)] != T_ROAD and terrain[_i(door)] != T_WATER:
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
	stock["sucata"] = minf(cap("sucata"), float(stock["sucata"]) + float(gained) * float(bal.get("open_scrap_share", 0.5)))
	_rebuild_astar()


## Marca (ou desmarca) um entulho para limpar primeiro. Quem cata sucata vai nos marcados antes.
## Vale para entulho (limpar) e para árvore (cortar). Marcado vira ordem: alguém livre vai lá primeiro.
func toggle_mark(cell: Vector2i) -> bool:
	if terrain_at(cell) != T_RUBBLE and terrain_at(cell) != T_TREE:
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
	if _id_index.size() != buildings.size():
		_id_index.clear()
		for b in buildings:
			_id_index[int(b["id"])] = b
	return _id_index.get(id, {})


## Memória por passo (limite do depósito, camas, urgência): o offline chama isso milhares de vezes.
## Limpa a cada passo e sempre que um prédio muda.
func _invalidate() -> void:
	_m_cap.clear()
	_m_urg.clear()
	_m_beds = -1
	_m_power.clear()
	_id_index.clear()


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
	return terrain[_i(c)] if _inside(c) else T_WATER


## Célula na frente do prédio (embaixo do meio): onde as pessoas param para trabalhar ou entregar.
## Se a da frente estiver tomada (outro prédio, árvore, entulho), usa a mais perto dela em volta.
func _door(b: Dictionary) -> Vector2i:
	var d := door_for(String(b["type"]), Vector2i(b["cell"]))
	return d if d.x >= 0 else Vector2i(b["cell"]) + Vector2i(_fp(String(b["type"])).x / 2, _fp(String(b["type"])).y)


## Porta de um prédio do tipo `type` posto em `cell`: a da frente, ou a célula livre mais perto
## dela em volta do prédio; (-1, -1) se ele ficaria todo cercado.
func door_for(type: String, cell: Vector2i) -> Vector2i:
	var fp := _fp(type)
	var pref := cell + Vector2i(fp.x / 2, fp.y)
	if _walkable_door(pref, cell, fp):
		return pref
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for y in range(cell.y - 1, cell.y + fp.y + 1):
		for x in range(cell.x - 1, cell.x + fp.x + 1):
			var c := Vector2i(x, y)
			var inner := x >= cell.x and x < cell.x + fp.x and y >= cell.y and y < cell.y + fp.y
			var corner := (x == cell.x - 1 or x == cell.x + fp.x) and (y == cell.y - 1 or y == cell.y + fp.y)
			if inner or corner or not _walkable_door(c, cell, fp):
				continue
			var dd := (c - pref).length_squared()
			if dd < bd:
				bd = dd
				best = c
	return best


func _walkable_door(c: Vector2i, cell: Vector2i, fp: Vector2i) -> bool:
	if not _inside(c):
		return false
	var o := occ[_i(c)]
	# a célula do próprio prédio (quando ele já existe) não conta como livre
	if o >= 0:
		return false
	var k := terrain[_i(c)]
	return k != T_TREE and k != T_RUBBLE and k != T_WATER


## Motivo de não dar para construir ali ("" = pode): o primeiro problema achado, para o jogo dizer
## na hora junto do cursor. out = fora da área limpa, tree, rubble, busy = outro prédio, road, closed = sem lado livre.
func place_reason(type: String, cell: Vector2i) -> String:
	var fp := _fp(type)
	for dy in fp.y:
		for dx in fp.x:
			var c := cell + Vector2i(dx, dy)
			if not _inside(c) or not in_zone(c):
				return "out"
			if occ[_i(c)] >= 0:
				return "busy"
			var k := terrain[_i(c)]
			if k == T_TREE:
				return "tree"
			if k == T_RUBBLE:
				return "rubble"
			if k == T_WATER:
				return "out"
			if k != T_GROUND and k != T_STUMP:
				return "road"
	if door_for(type, cell).x < 0:
		return "closed"
	if _too_tight(type, cell):
		return "tight"
	if _cuts_port(type, cell):
		return "cuts"
	return ""


## Prédio grande precisa de uma célula livre em volta (corredor para o pessoal passar e a vila
## respirar). Fogueira, enfeites e a praça (que se anda por cima) não contam.
func _spaced(type: String) -> bool:
	var d := def(type)
	return _fp(type) != Vector2i(1, 1) and not bool(d.get("open", false)) and not bool(d.get("walkable", false)) and not bool(d.get("deco", false))


func _too_tight(type: String, cell: Vector2i) -> bool:
	if not _spaced(type):
		return false
	var fp := _fp(type)
	for dy in range(-1, fp.y + 1):
		for dx in range(-1, fp.x + 1):
			var c := cell + Vector2i(dx, dy)
			if not _inside(c) or occ[_i(c)] < 0:
				continue
			var ob := by_id(occ[_i(c)])
			if not ob.is_empty() and _spaced(String(ob["type"])):
				return true
	return false


func _hatch_door() -> Vector2i:
	var hb := _first("hatch")
	return Vector2i(-1, -1) if hb.is_empty() else _door(hb)


## O prédio ali deixaria alguém sem chegar (o porto, a porta de outro prédio ou a dele mesmo)?
## Conta só o que hoje dá para alcançar a partir da escotilha.
func _cuts_port(type: String, cell: Vector2i) -> bool:
	if _first("hatch").is_empty() or _astar == null or bool(def(type).get("open", false)):
		return false
	var doors0: Array[Vector2i] = []
	for b in buildings:
		doors0.append(_door(b))
	var reach0 := _reach(_hatch_door())
	var fp := _fp(type)
	var was: Array[Vector2i] = []
	for dy in fp.y:
		for dx in fp.x:
			var c := cell + Vector2i(dx, dy)
			if _inside(c) and occ[_i(c)] < 0:
				occ[_i(c)] = 1 << 30   # ocupado de mentira, só para a conta
				was.append(c)
				if not _astar.is_point_solid(c):
					_astar.set_point_solid(c, true)
	var reach1 := _reach(_hatch_door())
	var cut := not reach1.has(door_for(type, cell))
	for i in buildings.size():
		if cut:
			break
		if reach0.has(doors0[i]) and not reach1.has(_door(buildings[i])):
			cut = true
	for c in was:
		occ[_i(c)] = -1
		var k := terrain[_i(c)]
		_astar.set_point_solid(c, k == T_TREE or k == T_RUBBLE or k == T_WATER)
	return cut


## Células que dá para alcançar a pé a partir de `from` (4 vizinhos, como o A* anda).
func _reach(from: Vector2i) -> Dictionary:
	var seen := {}
	if not _inside(from):
		return seen
	seen[from] = true
	var q: Array[Vector2i] = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for o in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if _inside(n) and not seen.has(n) and not _astar.is_point_solid(n):
				seen[n] = true
				q.append(n)
	return seen


## Por que cada célula da pegada não serve (para o fantasma pintar só a que bloqueia).
func cell_ok(c: Vector2i) -> bool:
	if not _inside(c) or occ[_i(c)] >= 0 or not in_zone(c):
		return false
	var k := terrain[_i(c)]
	return k == T_GROUND or k == T_STUMP


func is_night() -> bool:
	var hour := local_hour()
	var a: float = float(bal["time"]["night_from_h"])
	var z: float = float(bal["time"]["night_to_h"])
	return hour >= a or hour < z


## Hora mostrada no relógio (0 a 24), no padrão dos jogos: dia das 6h às 19h (com o entardecer
## no fim) e noite das 19h às 6h. A duração real de cada período não muda: o dia ocupa os mesmos
## 75% do ciclo e a noite os 25%; só as horas da noite passam mais rápido no relógio.
func display_hour() -> float:
	var h := local_hour()
	var tb: Dictionary = bal["time"]
	var a: float = float(tb["night_from_h"])
	var z: float = float(tb["night_to_h"])
	var d0: float = float(tb.get("show_day_from_h", 6))
	var n0: float = float(tb.get("show_night_from_h", 19))
	if not is_night():
		return d0 + fposmod(h - z, 24.0) / fposmod(a - z, 24.0) * (n0 - d0)
	return fposmod(n0 + fposmod(h - a, 24.0) / fposmod(z - a, 24.0) * fposmod(d0 - n0, 24.0), 24.0)


## Hora interna da vila (0 a 24). Não é o relógio do PC: um dia da vila dura balance "night.cycle_s".
func local_hour() -> float:
	return fposmod((t - cycle_t0) / float(bal["night"]["cycle_s"]) * 24.0, 24.0)


## Acerta o relógio da vila para marcar `hour` agora.
func set_cycle_hour(hour: float) -> void:
	cycle_t0 = t - hour / 24.0 * float(bal["night"]["cycle_s"])
	_was_night = is_night()


## Fração da produção: 1 com o sono em dia; cada noite virada que falta descansar tira um tanto.
func rest_mult(p: Dictionary) -> float:
	var nb: Dictionary = bal["night"]
	var tired := int(p.get("tired", 0))
	if tired <= 0:
		return 1.0
	return maxf(float(nb["tired_min_mult"]), 1.0 - float(nb["tired_penalty"]) * tired)


## Liga ou desliga "virar a noite". Ligando de noite, quem estava dormindo levanta.
func set_work_tonight(on: bool) -> void:
	if on and fog_now:
		return   # névoa de pólen: ninguém sai
	work_tonight = on
	if on:
		for p in people:
			if p["asleep"] or String(p["job"].get("kind", "")) == "sleep":
				p["asleep"] = false
				_set_job(p, {"kind": "idle"})
	changed.emit()


## A noite acabou: quem virou a noite cansa mais; quem dormiu descansa (sem cama, metade).
func _night_end() -> void:
	var nb: Dictionary = bal["night"]
	for i in people.size():
		var p: Dictionary = people[i]
		if work_tonight:
			p["tired"] = int(p["tired"]) + 1
			p["rest"] = 0.0
		elif fog_now and home_of(p) < 0:
			p["tired"] = int(p["tired"]) + int(bal["fog"]["no_bed_tired"])   # dormiu no pólen
			p["rest"] = 0.0
		elif int(p["tired"]) > 0:
			p["rest"] = float(p["rest"]) + (1.0 if home_of(p) >= 0 else float(nb["no_bed_rest"]))
			if float(p["rest"]) >= float(nb["rest_nights_per_tired"]) - 0.001:
				p["rest"] = 0.0
				p["tired"] = int(p["tired"]) - 1
	work_tonight = false
	for b in buildings:   # casa com gente dormindo é casa cuidada
		if String(b["type"]) == "moradia" and not residents(b).is_empty():
			b["care_t"] = t
	if fog_now:
		fog_now = false
		fog_bonus_until = t + float(bal["fog"]["bonus_s"])
		fog_ended.emit()
	var fb: Dictionary = bal["fog"]
	fog_next = day_number() + 1 >= int(fb["from_day"]) and _rng.randf() < float(fb["chance"])


## Começo da noite: se era noite de névoa, ela chega (e cancela o "virar a noite").
func _night_start() -> void:
	if not fog_next:
		return
	fog_next = false
	fog_now = true
	work_tonight = false
	fog_started.emit()


## A mata volta: prédio que ninguém usa há um tempo (balance "vines_after_s") fica tomado de
## trepadeira. Só aparência; some quando alguém volta a usar.
func overgrown(b: Dictionary) -> bool:
	var tp := String(b["type"])
	var d := def(tp)
	if String(b["state"]) != "built" or bool(d.get("fixed", false)) or bool(d.get("deco", false)) \
			or bool(d.get("open", false)) or tp == "torre" or tp == "fogueira":
		return false
	return t - float(b.get("care_t", t)) > float(bal.get("vines_after_s", 1500))


## Dias da vila (ciclo de ~25 min), virando a cada amanhecer. Antes contava dias de verdade do
## relógio do PC: depois de várias noites na vila continuava "Dia 1".
func day_number() -> int:
	var cs := float(bal["night"]["cycle_s"])
	var dawn := float(bal["time"]["night_to_h"]) / 24.0 * cs
	var k0 := floorf((start_t - cycle_t0 - dawn) / cs)
	return maxi(1, int(floorf((t - cycle_t0 - dawn) / cs) - k0) + 1)


func cap(res: String) -> float:
	if _m_cap.has(res):
		return _m_cap[res]
	var c: float = float(bal["storage"]["hatch_cap"])
	for b in buildings:
		if String(b["type"]) == "deposito" and String(b["state"]) != "site":
			c += float(level_def(b).get("cap", 0))
	_m_cap[res] = c
	return c


func beds_total() -> int:
	if _m_beds >= 0:
		return _m_beds
	var n := 0
	for b in buildings:
		# Moradia em melhoria continua com as camas do nível atual (ninguém fica sem cama).
		if String(b["state"]) == "site":
			continue
		n += int(level_def(b).get("beds", def(String(b["type"])).get("beds", 0)))
	_m_beds = n
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


## Quantos desse prédio a vila pode ter agora (como o Clash): -1 é sem limite.
## No balance.json, "limit" é um número fixo ou {"base", "per_tower"}, que cresce a cada nível da torre.
func limit(type: String) -> int:
	var l: Variant = def(type).get("limit", -1)
	if l is Dictionary:
		return int(l["base"]) + int(l.get("per_tower", 0)) * (tower - 1)
	return int(l)


func at_limit(type: String) -> bool:
	var l := limit(type)
	return l >= 0 and _count_any(type) >= l


func can_afford(cost: Dictionary) -> bool:
	for r in cost:
		if float(stock.get(r, 0.0)) + 1e-6 < float(cost[r]):
			return false
	return true


## Segundos que faltam para a pessoa terminar o que está fazendo agora (carga, coleta ou obra);
## -1 se não está numa atividade com fim. Usa a velocidade de agora (bônus, energia, offline).
func eta(p: Dictionary) -> float:
	var job: Dictionary = p["job"]
	var res := String(job.get("res", ""))
	match String(p["phase"]):
		"working":
			var b := by_id(int(job.get("b", -1)))
			if b.is_empty():
				return -1.0
			var m := bonus(p, res) * _work_mult(p) * _prod_frac()
			if float(def(String(b["type"])).get("power_use", 0)) > 0.0:
				m *= power_frac()
			if m <= 0.0:
				return -1.0
			var left := maxf(0.0, work_trip(b) - float(p["carry"]))
			return left * float(level_def(b)["rate_s"]) / m
		"foraging":
			var f: Dictionary = bal["forage"].get(res, {})
			var m2 := bonus(p, res) * _work_mult(p) * _prod_frac()
			if f.is_empty() or m2 <= 0.0:
				return -1.0
			return maxf(0.0, float(f["work_s"]) - float(p["work_t"])) / m2
		"building":
			var bb := by_id(int(job.get("b", -1)))
			if bb.is_empty():
				return -1.0
			return site_eta(bb)
	return -1.0


## Segundos que faltam para a obra ficar pronta: na velocidade de quem constrói, ou na normal se
## ainda espera alguém.
func site_eta(b: Dictionary) -> float:
	var left := maxf(0.0, float(b["total"]) - float(b["progress"]))
	var m := 0.0
	for bid in [int(b["builder"])] + (b.get("helpers", []) as Array):
		var p := person(int(bid))
		if not p.is_empty():
			m += bonus(p, "build") * _work_mult(p)
	return left / m if m > 0.0 else left


func missing(cost: Dictionary) -> Dictionary:
	var out := {}
	for r in cost:
		var m: float = float(cost[r]) - float(stock.get(r, 0.0))
		if m > 1e-6:
			out[r] = int(ceil(m))
	return out


## A área da vila: só se constrói dentro do raio que a torre alcança.
func in_zone(c: Vector2i) -> bool:
	return Vector2(c).distance_to(center()) <= open_radius(tower) and terrain_at(c) != T_WATER


func can_place(type: String, cell: Vector2i) -> bool:
	var fp := _fp(type)
	for dy in fp.y:
		for dx in fp.x:
			if not cell_ok(cell + Vector2i(dx, dy)):
				return false
	return door_for(type, cell).x >= 0 and not _too_tight(type, cell) and not _cuts_port(type, cell)


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
	if at_limit(type):
		return {"ok": false, "reason": "limit"}
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
	_invalidate()
	_rebuild_astar()
	changed.emit()
	site_started.emit(int(b["id"]))
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
	_invalidate()
	changed.emit()
	site_started.emit(int(b["id"]))
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
	_invalidate()
	changed.emit()
	site_started.emit(int(b["id"]))
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
		_invalidate()
		_rebuild_astar()
	else:
		b["state"] = "built"
	changed.emit()
	return {"ok": true}


## Dá para desmontar? Só prédio pronto, que não seja fixo (bunker, torre, estrada).
func can_demolish(b: Dictionary) -> bool:
	if b.is_empty() or String(b["state"]) != "built":
		return false
	var tp := String(b["type"])
	if bool(def(tp).get("fixed", false)) or tp == "torre" or tp == "hatch" or tp == "gate":
		return false
	return not (tp == "praca" and merchant_here())


## Desmonta um prédio pronto: devolve parte do que custou (balance "demolish_refund") e libera o chão.
## Quem trabalhava nele fica livre. É a saída quando o chão acaba.
func demolish(id: int) -> Dictionary:
	var b := by_id(id)
	if not can_demolish(b):
		return {"ok": false}
	var f := float(bal["demolish_refund"])
	var cost: Dictionary = level_def(b, 1)["cost"]
	for r in cost:
		stock[r] = minf(cap(r), float(stock[r]) + floorf(float(cost[r]) * f))
	for p in people:
		var j: Dictionary = p["job"]
		if int(j.get("b", -1)) == id:
			_set_job(p, {"kind": "idle"})
	_mark(b, false)
	buildings.erase(b)
	_invalidate()
	_rebuild_astar()
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
		p["eat_mult"] = float(c.get("eat_mult", 1.0))
		var br: Dictionary = c.get("brings", {})
		for r in br:
			stock[r] = minf(cap(r), float(stock[r]) + float(br[r]))
		person_joined.emit(int(p["id"]))
	gate_group.clear()
	_group_ready_t = t + group_cooldown()
	changed.emit()


## Quem do portão mais ajuda agora: passiva no recurso que mais falta pesa mais; o que a pessoa
## traz conta um pouco; comer mais conta contra.
func best_pick() -> int:
	var best := 0
	var bv := -1e9
	for i in gate_group.size():
		var c: Dictionary = gate_group[i]
		var v := 0.0
		for ps in c["passives"]:
			var job := String(bal["passives"].get(String(ps["id"]), {}).get("job", ""))
			var b := float(bal["rarity"][String(ps["rar"])]["bonus"])
			v += b * (1.0 + 2.0 * urgency(job)) if job in RES else b
		for r in c.get("brings", {}):
			v += float(c["brings"][r]) * 0.01 * (1.0 + urgency(r))
		v -= (float(c.get("eat_mult", 1.0)) - 1.0) * (0.5 + urgency("comida"))
		if v > bv:
			bv = v
			best = i
	return best


## Espera até o próximo grupo no porto (menor a cada nível da antena). A fogueira acesa é vista de longe: com ela pronta, a espera cai.
func group_cooldown() -> float:
	var by: Dictionary = bal["arrivals"].get("group_cooldown_by_tower", {})
	var cd := float(by.get(str(tower), bal["arrivals"]["group_cooldown_s"]))
	var f := _first("fogueira")
	if not f.is_empty() and String(f["state"]) == "built":
		cd *= float(bal["arrivals"]["fire_cooldown_mult"])
	return cd


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
	_invalidate()
	_reach_main = {}
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
			var o := occ[_i(c)]
			if (o >= 0 and not bool(def(String(by_id(o).get("type", ""))).get("open", false))) or k == T_TREE or k == T_RUBBLE or k == T_WATER:
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
	if not pts.is_empty() and Vector2i(pts[pts.size() - 1]) != to:
		pts = PackedVector2Array()   # só um pedaço do caminho: não serve (antes ela "chegava" de longe)
	if pts.is_empty() and solid_a and a != to:
		# Parada em célula ocupada (ergueram uma obra onde ela estava): sai pela célula livre
		# mais perto que tenha caminho até o alvo.
		var best := PackedVector2Array()
		for r in range(1, 4):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var n := a + Vector2i(dx, dy)
					if maxi(absi(dx), absi(dy)) != r or not _inside(n) or _astar.is_point_solid(n):
						continue
					var sub := _path(Vector2(n), to)
					if not sub.is_empty() and (best.is_empty() or sub.size() + r < best.size()):
						best = sub
						best.insert(0, Vector2(a))
			if not best.is_empty():
				return best
	return pts


# ================================================================ pessoas
func _add_person(nm: String, look: int, passives: Array, at: Vector2i, story: String = "", bio: int = -1) -> Dictionary:
	var p := {"id": _next_id, "name": nm, "look": look, "passives": passives.duplicate(true),
			"pos": Vector2(at), "path": PackedVector2Array(), "job": {}, "phase": "idle",
			"carry_res": "", "carry": 0.0, "work_t": 0.0, "hungry": false, "thirsty": false,
			"eat_acc": 0.0, "drink_acc": 0.0, "facing": Vector2.DOWN, "moving": false,
			"story": story, "bio": bio, "asleep": false, "home": -1, "target_cell": Vector2i(-1, -1),
			"tired": 0, "rest": 0.0}
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
	var s: float = float(bal["people"]["speed_tiles_s"]) * bonus(p, "walk") * (1.0 + perk_bonus("carrinho"))
	# Cansado anda mais devagar (só perde, o bônus de sono em dia não acelera o passo).
	return s * (float(bal["people"]["hungry_speed"]) if (p["hungry"] or p["thirsty"]) else 1.0) * minf(1.0, rest_mult(p))


## Energia: oferta dos geradores e painéis prontos contra o gasto dos prédios elétricos prontos.
func power() -> Dictionary:
	if not _m_power.is_empty():
		return _m_power
	var out := 0.0
	var use := 0.0
	for b in buildings:
		if not _working(b):
			continue
		var d := def(String(b["type"]))
		out += float(d.get("power_out", 0))
		use += float(d.get("power_use", 0))
	_m_power = {"out": out, "use": use}
	return _m_power


## Quanto os prédios elétricos rendem (1 = energia sobrando; menos = falta, todos andam mais devagar).
func power_frac() -> float:
	var pw := power()
	if float(pw["use"]) <= 0.0:
		return 1.0
	return clampf(float(pw["out"]) / float(pw["use"]), 0.0, 1.0)


## Melhoria comprada do mercador (soma por quantas foram compradas).
func perk_bonus(id: String) -> float:
	return float(bal["merchant"]["perks"].get(id, 0.0)) * float(perks.get(id, 0))


## Comida rende mais com cozinha pronta e com as sementes do mercador.
func food_mult() -> float:
	var m := 1.0 + perk_bonus("sementes")
	if t < fog_bonus_until:
		m += float(bal["fog"]["food_bonus"])
	for b in buildings:
		if _working(b):
			m += float(level_def(b).get("food_bonus", def(String(b["type"])).get("food_bonus", 0.0)))
	return m


func _work_mult(p: Dictionary) -> float:
	return (float(bal["people"]["hungry_speed"]) if (p["hungry"] or p["thirsty"]) else 1.0) * rest_mult(p)


## O que mais falta, de 0 a ~2. Comida e água pesam pelo consumo; madeira e sucata pela próxima meta.
func urgency(res: String) -> float:
	if _m_urg.has(res):
		return _m_urg[res]
	var u := _urgency(res)
	_m_urg[res] = u
	return u


func _urgency(res: String) -> float:
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
	if is_night() and not work_tonight:
		return {"kind": "sleep"}
	# Obras em ordem de chegada: uma pessoa por obra.
	var sites: Array[Dictionary] = []
	for b in buildings:
		if String(b["state"]) != "built" and int(b["builder"]) < 0:
			sites.append(b)
	sites.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return float(a["queued_t"]) < float(c["queued_t"]))
	if not sites.is_empty():
		# Quem é bom de obra vai para a obra; os outros só pegam se não tem construtor bom livre
		# para cada obra, ou se a obra já espera há muito tempo.
		var mine := bonus(p, "build") > 1.0
		if _m_builders < 0:   # construtores bons livres (conta uma vez por passo)
			_m_builders = 0
			for q in people:
				if bonus(q, "build") > 1.0 and String(q["job"].get("kind", "")) != "build" \
						and not bool(q["job"].get("manual", false)) and not q["asleep"]:
					_m_builders += 1
		var builders := _m_builders
		var wait: float = float(bal["people"].get("site_wait_s", 90.0))
		if mine or sites.size() > builders or t - float(sites[0]["queued_t"]) > wait:
			return {"kind": "build", "b": int(sites[0]["id"]), "why": "skill" if mine else "build"}
	var best := {}
	var best_v := 0.0
	# Entulho ou árvore marcados pelo jogador são ordem: vão na frente de tudo menos obra
	# (até metade da vila ao mesmo tempo, para o resto não parar).
	if not marked.is_empty():
		for mres in ["sucata", "madeira"]:
			if _has_forage(mres, true) and _assigned_to(mres, p) < maxi(1, people.size() / 2):
				return {"kind": "forage", "res": mres, "clear": true, "why": "marked"}
	# Cada um prefere o que sabe fazer bem (passiva daquele recurso), enquanto ainda cabe no estoque;
	# só larga quando comida ou água estão acabando de verdade.
	var pref: float = float(bal["people"].get("skill_pref", 3.0))
	for res in RES:
		var u := urgency(res) / (1.0 + float(_assigned_to(res, p)))
		if u <= 0.0:
			continue
		var skilled := bonus(p, res) > 1.0
		var crit := (res == "comida" or res == "agua") and float(stock[res]) < float(bal["people"].get("critical_stock", 6.0))
		if skilled:
			u *= pref
		if crit:
			u *= pref * 1.5
		var why := "need" if crit else ("skill" if skilled else ("need" if urgency(res) >= 0.6 else "free"))
		# Prédio com vaga livre
		for b in buildings:
			if not _working(b) or String(def(String(b["type"])).get("res", "")) != res:
				continue
			var lv := level_def(b)
			if (b["workers"] as Array).size() >= int(lv.get("slots", 0)):
				continue
			var inp: Dictionary = lv.get("input", {})
			var short_inp := false
			for r in inp:
				if float(stock[r]) < float(inp[r]) * 2.0:
					short_inp = true
			if short_inp or (float(def(String(b["type"])).get("power_use", 0)) > 0.0 and power_frac() <= 0.0):
				continue
			var rate: float = 1.0 / float(lv["rate_s"])
			var v: float = u * rate * bonus(p, res)
			if v > best_v:
				best_v = v
				best = {"kind": "work", "b": int(b["id"]), "res": res, "why": why}
		# Coleta à mão (madeira nas árvores, sucata no entulho)
		if res == "madeira" or res == "sucata":
			var f: Dictionary = bal["forage"][res]
			var rate_f: float = float(f["yield"]) / (float(f["work_s"]) + 8.0) / 3.0
			var v2: float = u * rate_f * bonus(p, res)
			if v2 > best_v and _has_forage(res):
				best_v = v2
				best = {"kind": "forage", "res": res, "why": why}
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
	if true:
		for c0 in marked:
			if taken.has(c0) or terrain[_i(c0)] != kind or not _reachable_neighbor(c0):
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


## Só "existe algo para coletar?" (o _pick_job não precisa do mais perto; isso pesa no offline).
func _has_forage(res: String, only_marked: bool = false) -> bool:
	var taken := {}
	for q in people:
		if q["target_cell"] != Vector2i(-1, -1):
			taken[q["target_cell"]] = true
	var kind := T_TREE if res == "madeira" else T_RUBBLE
	for c0 in marked:
		if not taken.has(c0) and terrain[_i(c0)] == kind and _reachable_neighbor(c0):
			return true
	if only_marked:
		return false
	for c in _forage_cells(T_TREE if res == "madeira" else T_RUBBLE):
		if not taken.has(c) and _reachable_neighbor(c):
			return true
	return false


func _reachable_neighbor(c: Vector2i) -> bool:
	var rm := main_reach()
	for o in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
		var n: Vector2i = c + o
		if rm.has(n):
			return true
	return false


func main_reach() -> Dictionary:
	if _reach_main.is_empty():
		_reach_main = _reach(_hatch_door())
	return _reach_main


func _free_neighbor(c: Vector2i, from: Vector2) -> Vector2i:
	var best := c
	var bd := 1e9
	for o in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
		var n: Vector2i = c + o
		if main_reach().has(n):
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
	for hid in (b.get("helpers", []) as Array).duplicate():
		var h := person(int(hid))
		if not h.is_empty():
			_set_job(h, {"kind": "idle"})
	b["helpers"] = []
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
		if not ob2.is_empty():
			(ob2.get("helpers", []) as Array).erase(int(p["id"]))
	p["target_cell"] = Vector2i(-1, -1)
	p["job"] = job
	p["path"] = PackedVector2Array()
	p.erase("goal")
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
			# Ajudante (mandado pelo jogador) soma na obra sem tirar quem já constrói.
			if bool(job.get("helper", false)):
				if not b2.has("helpers"):
					b2["helpers"] = []
				(b2["helpers"] as Array).append(int(p["id"]))
			else:
				b2["builder"] = int(p["id"])
			_go(p, _door(b2))
			p["phase"] = "to_build"
		"forage":
			var c: Vector2i = job["cell"] if job.has("cell") else _nearest_forage(String(job["res"]), p["pos"])
			p["target_cell"] = c
			_go(p, _free_neighbor(c, p["pos"]))
			p["phase"] = "to_forage"
		"sleep":
			_go(p, _bed_door(p))
			p["phase"] = "to_bed"
		"move":
			_go(p, job["cell"])
			p["phase"] = "to_spot"
		_:
			p["phase"] = "idle"


func _bed_door(p: Dictionary) -> Vector2i:
	# Cada um dorme na moradia que é dele (home_of). Sem cama: perto da fogueira, ou na escotilha.
	var hb := by_id(home_of(p))
	if not hb.is_empty():
		return _door(hb)
	var fire := _first("fogueira")
	return _door(fire if not fire.is_empty() and String(fire["state"]) == "built" else _first("hatch"))


func _beds_of(b: Dictionary) -> int:
	return int(level_def(b).get("beds", def(String(b["type"])).get("beds", 0)))


## Moradia (id) onde a pessoa dorme; -1 = sem cama. A cama é da pessoa: fica a mesma de uma noite para
## a outra enquanto a casa existir; quem não tem ganha a vaga livre mais perto de onde está.
func home_of(p: Dictionary) -> int:
	_assign_homes()
	return int(p.get("home", -1))


## Quem dorme nesta moradia (nomes na ordem de chegada).
func residents(b: Dictionary) -> Array:
	_assign_homes()
	var out: Array = []
	for p in people:
		if int(p.get("home", -1)) == int(b["id"]):
			out.append(p)
	return out


func _assign_homes() -> void:
	var used := {}
	for p in people:
		var hb := by_id(int(p.get("home", -1)))
		var ok := not hb.is_empty() and String(hb["type"]) == "moradia" and String(hb["state"]) != "site"
		if ok and int(used.get(int(hb["id"]), 0)) < _beds_of(hb):
			used[int(hb["id"])] = int(used.get(int(hb["id"]), 0)) + 1
		else:
			p["home"] = -1
	for p in people:
		if int(p["home"]) >= 0:
			continue
		var bd := 1e9
		for b in buildings:
			if String(b["type"]) != "moradia" or String(b["state"]) == "site":
				continue
			if int(used.get(int(b["id"]), 0)) >= _beds_of(b):
				continue
			var d := Vector2(p["pos"]).distance_squared_to(Vector2(_door(b)))
			if d < bd:
				bd = d
				p["home"] = int(b["id"])
		if int(p["home"]) >= 0:
			used[int(p["home"])] = int(used.get(int(p["home"]), 0)) + 1


func _go(p: Dictionary, cell: Vector2i) -> void:
	var path := _path(p["pos"], cell)
	if path.is_empty() and Vector2(p["pos"]).distance_to(Vector2(cell)) > 1.0 and _hatch_door().x >= 0:
		# Sem caminho: se nem até a escotilha ela chega, está ilhada pela mata (quem desce do bote
		# num porto cercado). Abre uma trilha até a escotilha e tenta de novo.
		var at := Vector2i(Vector2(p["pos"]).round())
		if _path(p["pos"], _hatch_door()).is_empty():
			_carve_trail(at, _hatch_door())
			_rebuild_astar()
			path = _path(p["pos"], cell)
	if path.size() > 0:
		path.remove_at(0)
	p["path"] = path
	p["goal"] = Vector2(cell)
	p["stuck_t"] = 0.0


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
	if path.is_empty() and p.has("goal") and pos.distance_to(Vector2(p["goal"])) > 1.0:
		# Não tem caminho até o alvo (cercado por prédio ou mata): não faz o trabalho de longe.
		# Espera um pouco (pode abrir) e depois larga a tarefa para escolher outra.
		p["moving"] = false
		p["stuck_t"] = float(p.get("stuck_t", 0.0)) + dt
		if float(p["stuck_t"]) >= 3.0:
			_set_job(p, {"kind": "idle"})
			p["phase"] = "idle"
		return false
	return path.size() == 0


# ================================================================ passo
func advance(seconds: float) -> void:
	var step: float = float(bal["time"]["offline_step_s"] if offline else bal["time"]["step_s"])
	var left := seconds
	while left > 1e-6:
		# Noite com todo mundo dormindo: nada anda, pula direto para a manhã.
		# Offline ninguém vê a caminhada até a cama: dormem direto, e a noite pode ser pulada.
		if offline and is_night() and not work_tonight and not _all_asleep():
			for p in people:
				if not p["asleep"]:
					_set_job(p, {"kind": "sleep"})
					p["pos"] = Vector2(_bed_door(p))
					p["path"] = PackedVector2Array()
					p["asleep"] = true
		if is_night() and not work_tonight and _all_asleep():
			var to_morning := _secs_to_morning()
			var jump := minf(left, to_morning)
			if jump > step:
				t += jump - 0.01
				left -= jump - 0.01
				_regrow()
				_radio_step()
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
	return dh / 24.0 * float(bal["night"]["cycle_s"])


func _step(dt: float) -> void:
	t += dt
	_m_urg.clear()   # o estoque muda a cada passo; limite e camas só mudam com prédio (_invalidate)
	_m_builders = -1
	var night := is_night()
	if _was_night and not night:
		_night_end()
	elif night and not _was_night:
		_night_start()
	_was_night = night
	night = night and not work_tonight   # virando a noite: todo mundo segue como se fosse dia
	if not night:
		_day_flow_t -= dt
		if _day_flow_t <= 0.0:
			_day_flow_t = 5.0
			for r in RES:
				_day_flow[r] = rate_now(r)
	_needs(dt, night)
	_regrow()
	_arrivals()
	_merchant_step()
	_radio_step()
	_rethink_acc += dt
	# Offline o passo é longo: repensar a cada passo pesa e não muda quase nada no resultado.
	var rethink_s: float = float(bal["people"]["rethink_s"])
	if offline:
		rethink_s = maxf(rethink_s, float(bal["time"].get("offline_rethink_s", 30.0)))
	var rethink := _rethink_acc >= rethink_s
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
		var em := float(p.get("eat_mult", 1.0)) / bonus(p, "eat")
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
				# Árvore que fecharia um caminho (porto, porta de prédio) espera mais um pouco.
				var doors0: Array[Vector2i] = [_hatch_door()]
				for b in buildings:
					doors0.append(_door(b))
				var r0 := main_reach()
				_astar.set_point_solid(c, true)
				_reach_main = {}
				var r1 := main_reach()
				var cut := false
				for d in doors0:
					if r0.has(d) and not r1.has(d) and d != c:
						cut = true
				if cut or r0.has(c) and doors0.has(c):
					_astar.set_point_solid(c, false)
					_reach_main = r0
					regrow[c] = t + 120.0
					continue
				terrain[_i(c)] = T_TREE
				_fdirty = true
				regrow.erase(c)


## Quem chega pelo porto. Grupos vêm desde a antena 1, sempre que sobra cama; a antena só encurta a
## espera (group_cooldown). As vozes do rádio continuam presas ao nível da antena de cada uma.
func _arrivals() -> void:
	# Pessoas da história (vozes do rádio): chegam sozinhas, fora do sorteio, quando a condição fecha,
	# e sempre entram (mesmo sem cama livre: dormem perto da fogueira até sobrar uma).
	for sid in bal.get("story_order", []):
		var story := String(sid)
		if _story_done.has(story) or not _story_ready(story):
			continue
		_story_done[story] = true
		var sd: Dictionary = bal["story_people"][story]
		var from := _v(bal["arrivals"]["walk_in_from"])
		var p := _add_person(tr_name(story), int(sd["look"]), sd["passives"], from, story)
		person_joined.emit(int(p["id"]))
		if _group_ready_t < 0.0 or _group_ready_t < t + float(bal["arrivals"]["first_group_delay_s"]):
			_group_ready_t = t + float(bal["arrivals"]["first_group_delay_s"])
		changed.emit()
		return
	if auto_pick and not gate_group.is_empty() and beds_free() > 0:
		choose(best_pick())
		return
	if beds_free() <= 0 or not gate_group.is_empty():
		return
	if _group_ready_t >= 0.0 and t >= _group_ready_t:
		_make_group()
		group_arrived.emit()
		changed.emit()
	elif _group_ready_t < 0.0:
		_group_ready_t = t + float(bal["arrivals"]["first_group_delay_s"])


## A condição de uma pessoa da história (balance.json, story_people): torre, prédios, níveis, estoque, gente.
func _story_ready(story: String) -> bool:
	var sd: Dictionary = bal["story_people"].get(story, {})
	if sd.is_empty() or tower < int(sd.get("tower", 99)):
		return false
	var mc: Dictionary = sd.get("min_count", {})
	for tp in mc:
		if _count(String(tp)) < int(mc[tp]):
			return false
	var ml: Dictionary = sd.get("min_level", {})
	for tp in ml:
		var ok := false
		for b in buildings:
			if String(b["type"]) == String(tp) and int(b["level"]) >= int(ml[tp]) and _working(b):
				ok = true
		if not ok:
			return false
	var ms: Dictionary = sd.get("min_stock", {})
	for r in ms:
		if float(stock[r]) < float(ms[r]):
			return false
	if people.size() < int(sd.get("min_people", 0)):
		return false
	if int(stats["built"]) < int(sd.get("min_built", 0)):
		return false
	return true


# ================================================================ rádio e viagem
## As falas do rádio (data/radio.json) contam a partir de quando cada nível da torre chegou:
## chegada e reação na hora, programas no dia/hora marcados. Na torre 5 ela diz que vem; a viagem
## (data/journey.json) anda em dias encurtados (ending.journey_day_scale) e termina com ela no portão.
func _load_lines() -> void:
	_lines_dirty = false
	_line_i = 0
	_lines = []
	var rd: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/radio.json"))
	if rd is Dictionary:
		for l in (rd as Dictionary)["lines"]:
			var lv := int(l["level"])
			if not tower_t.has(lv):
				continue
			var t0 := float(tower_t[lv])
			var due := t0
			if String(l["kind"]) == "reaction":
				due = t0 + 4.0
			elif l["hour"] != null:
				due = day_start(t0) + int(l["day_offset"]) * 86400.0 + float(l["hour"]) * 3600.0
				while due < t0:
					due += 86400.0
			_lines.append({"id": String(l["id"]), "speaker": String(l["speaker"]), "text_key": String(l["text_key"]),
					"cue": String(l["cue"]), "kind": String(l["kind"]), "due": due})
	var last5 := tower_max()
	if tower_t.has(last5):
		var jd: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/journey.json"))
		if jd is Dictionary:
			var sc: float = float(bal["ending"]["journey_day_scale"])
			var base := float(tower_t[last5])
			var prev := base
			for l in (jd as Dictionary)["travel"]:
				var day := day_start(base + int(l["day_offset"]) * 86400.0 * sc)
				var due := day + float(l["hour"]) * 3600.0
				while due <= prev:
					due += 86400.0 * sc
				prev = due
				_lines.append({"id": String(l["id"]), "speaker": "ela", "text_key": String(l["text_key"]),
						"cue": String(l["cue"]), "kind": "journey", "due": due})
			var arr: Dictionary = (jd as Dictionary)["arrival"]
			_lines.append({"id": "arrival", "speaker": "ela", "text_key": String(arr["text_key"]), "cue": String(arr["cue"]),
					"kind": "arrival_ela", "due": prev + float(bal["ending"].get("arrival_after_h", 3.0)) * 3600.0})
	_lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["due"]) < float(b["due"]))


func _radio_step() -> void:
	if _lines_dirty:
		_load_lines()
	# As falas estão em ordem de hora: só olha a partir da próxima ainda não tocada.
	while _line_i < _lines.size() and float(_lines[_line_i]["due"]) <= t:
		var l: Dictionary = _lines[_line_i]
		_line_i += 1
		if radio_heard.has(l["id"]):
			continue
		radio_heard.append(l["id"])
		if String(l["kind"]) == "arrival_ela":
			_ela_arrives()
		radio.emit(l)


func _ela_arrives() -> void:
	if ela_t >= 0.0:
		return
	ela_t = t
	var from := _v(bal["arrivals"]["walk_in_from"])
	var p := _add_person(tr_name("ela"), int(bal["ending"].get("look", 6)), [], from, "ela")
	person_joined.emit(int(p["id"]))
	ela_arrived.emit()
	changed.emit()


## Fala já ouvida (ou ainda não) pelo id, para o caderno do rádio.
func line(id: String) -> Dictionary:
	if _lines_dirty:
		_load_lines()
	for l in _lines:
		if String(l["id"]) == id:
			return l
	return {}


## Quanto falta para ela chegar (segundos), -1 se a viagem não começou ou se ela já chegou.
func journey_left() -> float:
	if ela_t >= 0.0 or not tower_t.has(tower_max()):
		return -1.0
	var l := line("arrival")
	return maxf(0.0, float(l.get("due", t)) - t)


# ================================================================ mercador
## Começo do dia local (meia-noite) do instante `at`.
func day_start(at: float) -> float:
	return at - fposmod(at + float(tz_bias_s), 86400.0)


## O mercador vem à praça em horas fixas (a partir da torre 3, com a praça pronta) e fica um tempo.
func _merchant_step() -> void:
	if not merchant.is_empty():
		if t >= float(merchant["until"]):
			_merchant_leave()
		return
	var md: Dictionary = bal["merchant"]
	if tower < int(md["tower"]) or _count("praca") == 0:
		return
	var d0 := day_start(t)
	var hours: Array = md["hours"]
	for i in hours.size():
		var start := d0 + float(hours[i]) * 3600.0
		var key := int(d0 / 86400.0) * 10 + i
		if t >= start and t < start + float(md["stay_s"]) and key != _merchant_key:
			_merchant_key = key
			_merchant_arrive(start + float(md["stay_s"]))
			return


func _merchant_arrive(until: float) -> void:
	var md: Dictionary = bal["merchant"]
	var prices := {}
	for r in md["price"]:
		prices[r] = float(md["price"][r]) * (1.0 + _rng.randf_range(-1.0, 1.0) * float(md["price_spread"]))
	var pool: Array = []
	for id in md["offers"]:
		var o: Dictionary = md["offers"][id]
		if o.has("perk") and int(perks.get(String(o["perk"]), 0)) >= int(o.get("max", 1)):
			continue
		pool.append(String(id))
	var offers: Array = []
	for k in mini(3, pool.size()):
		var i := _rng.randi_range(0, pool.size() - 1)
		offers.append(pool[i])
		pool.remove_at(i)
	var req := {}
	if _rng.randf() < float(md["request_chance"]):
		var keys: Array = md["request"].keys()
		var r := String(keys[_rng.randi_range(0, keys.size() - 1)])
		var rg: Array = md["request"][r]
		var n := _rng.randi_range(int(rg[0]), int(rg[1]))
		req = {"res": r, "n": n, "pay": int(ceil(n * float(prices.get(r, 1.0)) * float(md["request_pay_mult"])))}
	merchant = {"until": until, "prices": prices, "offers": offers, "bought": [], "request": req}
	merchant_arrived.emit()
	changed.emit()


func _merchant_leave() -> void:
	var sold := {}
	if auto_sell:
		var above: float = float(bal["merchant"]["auto_sell_above"])
		for r in merchant["prices"]:
			var extra := int(floor(float(stock[r]) - cap(r) * above))
			if extra > 0:
				var got := _sell(r, extra)
				if got > 0:
					sold[r] = extra
	merchant = {}
	merchant_left.emit(sold)
	changed.emit()


func merchant_here() -> bool:
	return not merchant.is_empty()


## Preço de um lote (o mercador paga em sucata).
func lot_price(res: String) -> int:
	if merchant.is_empty():
		return 0
	return int(floor(float(merchant["prices"].get(res, 0.0)) * float(bal["merchant"]["lot"])))


func _sell(res: String, n: int) -> int:
	var got := int(floor(float(merchant["prices"].get(res, 0.0)) * n))
	stock[res] = float(stock[res]) - n
	stock["sucata"] = minf(cap("sucata"), float(stock["sucata"]) + got)
	return got


## Vende um lote de `res`. Devolve {ok, got}.
func sell_lot(res: String) -> Dictionary:
	var n: int = int(bal["merchant"]["lot"])
	if merchant.is_empty() or not merchant["prices"].has(res):
		return {"ok": false, "reason": "away"}
	if float(stock[res]) < n:
		return {"ok": false, "reason": "cost"}
	if float(stock["sucata"]) >= cap("sucata"):
		return {"ok": false, "reason": "full"}
	var got := _sell(res, n)
	changed.emit()
	return {"ok": true, "got": got}


func offer_def(id: String) -> Dictionary:
	return bal["merchant"]["offers"].get(id, {})


## Compra a oferta de índice `i` (cada uma só uma vez por visita).
func buy_offer(i: int) -> Dictionary:
	if merchant.is_empty() or i < 0 or i >= (merchant["offers"] as Array).size():
		return {"ok": false, "reason": "away"}
	if (merchant["bought"] as Array).has(i):
		return {"ok": false, "reason": "sold"}
	var id := String(merchant["offers"][i])
	var o := offer_def(id)
	if bool(o.get("needs_group", false)) and gate_group.is_empty():
		return {"ok": false, "reason": "no_group"}
	if not can_afford(o["cost"]):
		return {"ok": false, "reason": "cost"}
	_pay(o["cost"])
	var gives: Dictionary = o.get("gives", {})
	for r in gives:
		stock[r] = minf(cap(r), float(stock[r]) + float(gives[r]))
	if o.has("perk"):
		perks[String(o["perk"])] = int(perks.get(String(o["perk"]), 0)) + 1
	if id == "rumor":
		_make_group()
		group_arrived.emit()
	(merchant["bought"] as Array).append(i)
	_invalidate()
	changed.emit()
	return {"ok": true}


## Entrega o pedido do mercador (paga o dobro, sem prazo nem castigo).
func fulfill_request() -> Dictionary:
	if merchant.is_empty() or (merchant["request"] as Dictionary).is_empty():
		return {"ok": false, "reason": "away"}
	var rq: Dictionary = merchant["request"]
	if float(stock[String(rq["res"])]) < float(rq["n"]):
		return {"ok": false, "reason": "cost"}
	stock[String(rq["res"])] = float(stock[String(rq["res"])]) - float(rq["n"])
	stock["sucata"] = minf(cap("sucata"), float(stock["sucata"]) + float(rq["pay"]))
	merchant["request"] = {}
	changed.emit()
	return {"ok": true}


## Nome das pessoas da história vem do I18n na vista; aqui fica a chave.
func tr_name(story: String) -> String:
	return "@" + story


func _make_group() -> void:
	gate_group.clear()
	var names: Array = (bal["names"] as Array).duplicate()
	for p in people:
		names.erase(String(p["name"]))
	var ids: Array = bal["passives"].keys()
	# Falas sem repetir dentro do mesmo grupo.
	var bios: Array = range(int(bal["bios"]))
	for k in 3:
		# Acabaram os nomes livres (vila enorme): repete um da lista, mas nunca aparece "?".
		if names.is_empty():
			names = (bal["names"] as Array).duplicate()
		var nm: String = String(names[_rng.randi_range(0, names.size() - 1)])
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
		# Ninguém é só pior: quem tem passiva fraca chega trazendo recursos; o excelente chega sem nada
		# e come mais.
		var ar: Dictionary = bal["arrivals"]
		var power := 0
		var exc := false
		for ps in passives:
			power += int(ar["power_points"][String(ps["rar"])])
			exc = exc or String(ps["rar"]) == "excelente"
		var brings := {}
		var pool: Array = ["comida", "agua", "madeira", "sucata"]   # peças não: atalho grande demais
		for amt in ar["brings_by_power"].get(str(power), []):
			var r: String = pool.pop_at(_rng.randi_range(0, pool.size() - 1))
			brings[r] = _rng.randi_range(int(amt[0]), int(amt[1]))
		gate_group.append({"name": nm, "look": _rng.randi_range(1, 5), "passives": passives,
				"brings": brings, "eat_mult": float(ar["excelente_eat_mult"]) if exc else 1.0, "bio": bios.pop_at(_rng.randi_range(0, bios.size() - 1)) if not bios.is_empty() else 0})


func _roll_rarity() -> String:
	var pity: int = int(bal["arrivals"]["pity_after_commons"])
	var r: String
	if int(stats["commons_in_row"]) >= pity:
		r = "rara" if _rng.randf() < 0.83 else "excelente"
	else:
		# Antena mais alta alcança mais longe: mais chance de raro e excelente (comum fica igual).
		var mult: Dictionary = bal["arrivals"].get("rarity_mult_by_tower", {}).get(str(tower), {})
		var wt := {}
		var total := 0.0
		for k in bal["rarity"]:
			wt[k] = float(bal["rarity"][k]["weight"]) * float(mult.get(k, 1.0))
			total += float(wt[k])
		var x := _rng.randf() * total
		r = "comum"
		for k in ["excelente", "rara", "comum"]:
			x -= float(wt[k])
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
	# Trabalhando há tempo: obra nova, ordem do jogador ou depósito cheio fazem largar e repensar
	# (antes a pessoa ficava parada no poço até encher a carga, sem nada mudar na tela).
	if rethink and (kind == "work" or kind == "forage") and String(p["phase"]) in ["working", "foraging", "to_work", "to_forage"]:
		var res := String(job.get("res", ""))
		var full := res != "" and float(stock[res]) >= cap(res) - 0.01
		if full:
			_set_job(p, {"kind": "idle"})
			return
		if not bool(job.get("clear", false)) and not bool(job.get("manual", false)) and _has_order():
			var nj := _pick_job(p)
			if String(nj["kind"]) == "build" or bool(nj.get("clear", false)):
				_set_job(p, nj)
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
		"move":
			# Foi até onde o jogador clicou: espera um pouco ali e depois volta a decidir sozinho.
			if String(p["phase"]) == "to_spot":
				if _walk(p, dt):
					p["phase"] = "hold"
					p["work_t"] = 0.0
			else:
				p["moving"] = false
				p["work_t"] = float(p["work_t"]) + dt
				if float(p["work_t"]) >= float(bal["people"].get("move_hold_s", 10.0)):
					_set_job(p, {"kind": "idle"})


## Ordem do jogador (clique direito com a pessoa selecionada): trabalhar no prédio, construir a obra,
## cortar a árvore / catar o entulho, ou só ir até a célula. Devolve {ok, kind, reason, res}.
## Se o prédio estiver cheio, troca alguém que foi por conta própria (nunca quem o jogador mandou).
func order(pid: int, c: Vector2i) -> Dictionary:
	var p := person(pid)
	if p.is_empty():
		return {"ok": false, "reason": "gone"}
	if is_night() and not work_tonight:
		return {"ok": false, "reason": "night"}
	# Carga na mão vai para o estoque na hora: senão a madeira que levava viraria água no poço.
	if float(p["carry"]) > 0.0:
		_deliver(p)
	var b := building_at(c)
	if not b.is_empty():
		var bid := int(b["id"])
		if String(b["state"]) != "built":
			# Até 3 na mesma obra: quem chega depois do construtor entra como ajudante.
			var helpers: Array = b.get("helpers", [])
			if int(b["builder"]) == pid or helpers.has(pid):
				p["job"]["manual"] = true
			elif int(b["builder"]) < 0 or person(int(b["builder"])).is_empty():
				_set_job(p, {"kind": "build", "b": bid, "manual": true})
			elif helpers.size() < int(bal["people"].get("max_builders", 3)) - 1:
				_set_job(p, {"kind": "build", "b": bid, "manual": true, "helper": true})
			else:
				return {"ok": false, "reason": "full"}
			return {"ok": true, "kind": "build"}
		var d := def(String(b["type"]))
		var lv := level_def(b)
		var res := String(d.get("res", ""))
		if res == "" or int(lv.get("slots", 0)) <= 0:
			_set_job(p, {"kind": "move", "cell": _door(b), "manual": true})
			return {"ok": true, "kind": "move", "reason": "no_work"}
		if (b["workers"] as Array).has(pid):
			p["job"]["manual"] = true
			return {"ok": true, "kind": "work"}
		if float(d.get("power_use", 0)) > 0.0 and power_frac() <= 0.0:
			return {"ok": false, "reason": "power"}
		var inp: Dictionary = lv.get("input", {})
		for r in inp:
			if float(stock[r]) < float(inp[r]):
				return {"ok": false, "reason": "input", "res": r}
		if float(stock[res]) >= cap(res) - 0.01:
			return {"ok": false, "reason": "store_full", "res": res}
		var ws: Array = b["workers"]
		if ws.size() >= int(lv["slots"]):
			var swap := {}
			for w in ws:
				var q := person(int(w))
				if not q.is_empty() and not bool(q["job"].get("manual", false)):
					swap = q
					break
			if swap.is_empty():
				return {"ok": false, "reason": "full"}
			_set_job(swap, {"kind": "idle"})
		_set_job(p, {"kind": "work", "b": bid, "res": res, "manual": true})
		return {"ok": true, "kind": "work"}
	var k := terrain_at(c)
	if k == T_TREE or k == T_RUBBLE:
		var fres := "madeira" if k == T_TREE else "sucata"
		if not _reachable_neighbor(c):
			return {"ok": false, "reason": "blocked"}
		if float(stock[fres]) >= cap(fres) - 0.01:
			return {"ok": false, "reason": "store_full", "res": fres}
		for q in people:
			if q != p and q["target_cell"] == c:
				_set_job(q, {"kind": "idle"})
		_set_job(p, {"kind": "forage", "res": fres, "cell": c, "manual": true})
		return {"ok": true, "kind": "forage", "res": fres}
	if not _inside(c) or _astar.is_point_solid(c):
		return {"ok": false, "reason": "blocked"}
	_set_job(p, {"kind": "move", "cell": c, "manual": true})
	return {"ok": true, "kind": "move"}


## Tem obra esperando alguém ou coisa marcada pelo jogador?
func _has_order() -> bool:
	for b in buildings:
		if String(b["state"]) != "built" and int(b["builder"]) < 0:
			return true
	if not marked.is_empty():
		for mres in ["sucata", "madeira"]:
			if _has_forage(mres, true):
				return true
	return false


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
	b["care_t"] = t
	b["builder"] = -1
	b["helpers"] = []
	var tp := String(b["type"])
	if tp == "torre":
		tower += 1
		tower_t[tower] = t
		_lines_dirty = true
		b["state"] = "built"
		_open_area(tower)
		tower_up.emit(tower)
	elif String(b["state"]) == "upgrade":
		b["level"] = int(b["level"]) + 1
		b["state"] = "built"
	else:
		b["state"] = "built"
	stats["built"] = int(stats["built"]) + 1
	_invalidate()
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
			b["care_t"] = t
			var lv := level_def(b)
			var d := def(String(b["type"]))
			var m := bonus(p, res) * _work_mult(p) * _prod_frac()
			var wet := res == "comida" and not bool(lv.get("no_water", false))
			if wet:
				var need_w: float = float(bal["horta_water_per_food"])
				if float(stock["agua"]) < need_w:
					m *= float(bal["no_water_horta_speed"])
			if float(d.get("power_use", 0)) > 0.0:
				m *= power_frac()
			var gain := dt * m / float(lv["rate_s"])
			if wet and float(stock["agua"]) >= float(bal["horta_water_per_food"]) * gain:
				stock["agua"] = float(stock["agua"]) - float(bal["horta_water_per_food"]) * gain
			# Matéria-prima (a oficina gasta sucata para fazer peças): faltando, anda bem devagar.
			var inp: Dictionary = lv.get("input", {})
			var has_inp := true
			for r in inp:
				if float(stock[r]) < float(inp[r]) * gain:
					has_inp = false
			if not has_inp:
				# Sem matéria-prima: larga a vaga (vai catar sucata, por exemplo) e volta depois.
				if float(p["carry"]) > 0.0:
					_to_storage(p)
				else:
					_set_job(p, {"kind": "idle"})
				return
			for r in inp:
				stock[r] = float(stock[r]) - float(inp[r]) * gain
			if res == "comida":
				gain *= food_mult()
			p["carry_res"] = res
			p["carry"] = float(p["carry"]) + gain
			if float(p["carry"]) >= work_trip(b) - 1e-6:
				_to_storage(p)
		"to_store":
			if _walk(p, dt):
				_deliver(p)
				if urgency(res) <= 0.0 or (p["hungry"] and false):
					_set_job(p, {"kind": "idle"})
					return
				# Repensa: pode haver algo mais urgente (obra nova, outro recurso faltando).
				# Quem o jogador mandou para cá continua aqui.
				var nj: Dictionary = p["job"] if bool(p["job"].get("manual", false)) else _pick_job(p)
				if String(nj.get("kind", "")) != "work" or int(nj.get("b", -1)) != int(b["id"]):
					if String(nj.get("kind", "")) != "idle":
						_set_job(p, nj)
						return
				_go(p, _door(b))
				p["phase"] = "to_work"


## Quanto a pessoa junta antes de levar ao depósito: prédio lento leva 1 por vez (assim ela vai e
## volta e dá para ver que está trabalhando); prédio rápido enche a carga inteira.
func work_trip(b: Dictionary) -> float:
	var lv := level_def(b)
	var cmax: float = float(bal["people"]["carry"])
	if offline:
		return cmax   # ninguém está olhando: carga cheia, menos caminhada para simular
	return clampf(floor(cmax * 12.0 / maxf(1.0, float(lv.get("rate_s", 10.0)))), 1.0, cmax)


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
					# Árvore que o jogador mandou cortar não volta (ele quer o chão).
					if marked.has(c):
						marked.erase(c)
					else:
						regrow[c] = t + float(f["regrow_s"])
					_astar.set_point_solid(c, false)
					_reach_main = {}
				else:
					var left: int = int(rubble.get(c, 0)) - int(y)
					if left <= 0:
						rubble.erase(c)
						marked.erase(c)
						terrain[_i(c)] = T_GROUND
						_fdirty = true
						_astar.set_point_solid(c, false)
						_reach_main = {}
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
				# Mandado pelo jogador: segue coletando o mesmo recurso (a árvore ou entulho mais perto).
				if bool(p["job"].get("manual", false)) and _has_forage(res) and float(stock[res]) < cap(res) - 0.01:
					_set_job(p, {"kind": "forage", "res": res, "manual": true})
				else:
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
	var sb := _storage_door(p["pos"], res)
	if not sb.is_empty():
		sb["care_t"] = t
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
	var f := flow_per_min(res)
	return float(f["prod"]) - float(f["use"])


## Quanto entra (quem está produzindo agora) e quanto sai por minuto (bocas, horta bebendo água).
## Ritmo para mostrar: de dia o de agora; de noite (todo mundo dormindo, nada entra nem sai) o do
## último trecho de dia, marcado com night = true.
func rate(res: String) -> Dictionary:
	if is_night() and not work_tonight:
		var d: Dictionary = _day_flow.get(res, rate_now(res)).duplicate()
		d["night"] = true
		return d
	return rate_now(res)


## Ritmo agora, com quantas pessoas produzem (workers) e quantas consomem (eaters).
func rate_now(res: String) -> Dictionary:
	var fl := flow_per_min(res)
	var wk := 0
	for p in people:
		var j: Dictionary = p["job"]
		if String(j.get("res", "")) == res and String(j.get("kind", "")) in ["work", "forage"]:
			wk += 1
	fl["workers"] = wk
	fl["eaters"] = people.size() if res == "comida" or res == "agua" else 0
	fl["night"] = false
	return fl


func flow_per_min(res: String) -> Dictionary:
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
	return {"prod": prod, "use": use}


## Por que a pessoa está nessa tarefa: build, marked, skill, need, free, order ("" = sem motivo).
func why(p: Dictionary) -> String:
	var j: Dictionary = p["job"]
	if bool(j.get("manual", false)):
		return "order"
	return String(j.get("why", ""))


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
	if k == "move":
		return "move"
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
			var want := ""
			if idle > 0 and urgency(pair[0]) > 0.6:
				want = "more"
			elif float(stock[pair[0]]) <= 3.0 and balance_per_min(pair[0]) < 0.0:
				want = "short"
			if want == "":
				continue
			# No limite: melhorar um que já existe; se nem isso der, a torre é que libera mais.
			if at_limit(pair[1]):
				var ub := _upgradable(pair[1])
				if not ub.is_empty():
					return {"kind": "improve", "type": pair[1], "id": int(ub["id"]), "res": pair[0]}
				continue
			if want == "more":
				return {"kind": "more", "type": pair[1], "res": pair[0], "idle": idle}
			return {"kind": "short", "type": pair[1], "res": pair[0]}
	var pw := power()
	if float(pw["use"]) > float(pw["out"]):
		return {"kind": "power", "out": float(pw["out"]), "use": float(pw["use"])}
	# A próxima torre pede mais do que cabe: falta melhorar o depósito.
	if tower < tower_max() and String(tower_building()["state"]) == "built":
		var nxc: Dictionary = tower_next()["cost"]
		for r in nxc:
			if float(nxc[r]) > cap(r):
				return {"kind": "storage", "res": r, "need": int(nxc[r]), "cap": int(cap(r))}
	# Torre pronta para subir vem antes de pedir mais camas.
	if tower < tower_max() and String(tower_building()["state"]) == "built" and can_afford(tower_next()["cost"]):
		return {"kind": "tower", "level": tower + 1, "missing": {}}
	if tower >= tower_max() and String(tower_building()["state"]) == "built" and ela_t < 0.0:
		return {"kind": "journey", "left_s": journey_left()}
	# A torre pede peças e ainda não tem oficina: isso vem antes de mais camas.
	if tower < tower_max() and String(tower_building()["state"]) == "built":
		var mt: Dictionary = missing(tower_next()["cost"])
		if mt.has("pecas") and _count_any("oficina") == 0 and unlocked("oficina"):
			# Sem lugar onde ela caiba: primeiro abrir chão.
			return {"kind": "build", "type": "oficina"} if has_spot("oficina") else {"kind": "space"}
	if tower >= 2 and beds_free() <= 0 and _count_any("moradia") < 6:
		# Só pede cama quando dá para fazer: melhorar uma barraca ou ter chão para outra.
		if _can_add_beds():
			return {"kind": "beds"}
		if _free_build_cells() < 6:
			return {"kind": "space"}
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
	if ela_t < 0.0:
		return {"kind": "journey", "left_s": journey_left()}
	return {"kind": "done"}


## O prédio desse tipo, pronto, de nível mais baixo que a torre já deixa melhorar ({} se nenhum).
func _upgradable(type: String) -> Dictionary:
	var best := {}
	for b in buildings:
		if String(b["type"]) == type and _working(b) and unlocked(type, int(b["level"]) + 1):
			if best.is_empty() or int(b["level"]) < int(best["level"]):
				best = b
	return best


## Existe algum lugar na área onde esse prédio caberia agora?
func has_spot(type: String) -> bool:
	for i in terrain.size():
		var c := Vector2i(i % w, i / w)
		if occ[i] < 0 and in_zone(c) and can_place(type, c):
			return true
	return false


func _can_add_beds() -> bool:
	for b in buildings:
		if String(b["type"]) == "moradia" and String(b["state"]) == "built" and unlocked("moradia", int(b["level"]) + 1):
			return true
	var fp := _fp("moradia")
	return _free_build_cells() >= fp.x * fp.y


## Quantas células livres de construção restam (para avisar que falta chão).
func _free_build_cells() -> int:
	var n := 0
	for i in terrain.size():
		if occ[i] < 0 and (terrain[i] == T_GROUND or terrain[i] == T_STUMP) and in_zone(Vector2i(i % w, i / w)):
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
				"state": b["state"], "progress": b["progress"], "total": b["total"], "queued_t": b.get("queued_t", 0.0),
				"care_t": b.get("care_t", t)})
	var ps: Array = []
	for p in people:
		ps.append({"id": p["id"], "name": p["name"], "look": p["look"], "passives": p["passives"],
				"pos": [p["pos"].x, p["pos"].y], "story": p["story"], "bio": p["bio"],
				"eat_acc": p["eat_acc"], "drink_acc": p["drink_acc"],
				"carry_res": p["carry_res"], "carry": p["carry"], "tired": p["tired"], "rest": p["rest"],
				"eat_mult": p.get("eat_mult", 1.0), "home": p.get("home", -1)})
	var rg: Array = []
	for c in regrow:
		rg.append([c.x, c.y, regrow[c]])
	var rb: Array = []
	for c in rubble:
		rb.append([c.x, c.y, rubble[c]])
	return {"v": 2, "t": t, "start_t": start_t, "stock": stock, "tower": tower, "terrain": Marshalls.raw_to_base64(terrain),
			"buildings": bs, "people": ps, "regrow": rg, "rubble": rb, "gate": gate_group,
			"marked": marked.keys().map(func(c: Vector2i) -> Array: return [c.x, c.y]),
			"stats": stats, "next_id": _next_id, "group_t": _group_ready_t, "story": _story_done.keys(),
			"rng": _rng.state, "tower_t": tower_t, "perks": perks, "merchant": merchant, "auto_sell": auto_sell, "auto_pick": auto_pick,
			"radio": radio_heard, "ela_t": ela_t, "merchant_key": _merchant_key,
			"cycle_t0": cycle_t0, "work_tonight": work_tonight, "fog_next": fog_next, "fog_now": fog_now,
			"fog_bonus_until": fog_bonus_until}


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
				"total": float(e["total"]), "workers": [], "builder": -1, "acc": 0.0, "queued_t": float(e.get("queued_t", 0.0)),
				"care_t": float(e.get("care_t", d["t"]))}
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
		p["tired"] = int(e.get("tired", 0))
		p["rest"] = float(e.get("rest", 0.0))
		p["eat_mult"] = float(e.get("eat_mult", 1.0))
		p["home"] = int(e.get("home", -1))
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
	tower_t = {}
	var tt: Dictionary = d.get("tower_t", {"1": start_t})
	for k in tt:
		tower_t[int(k)] = float(tt[k])
	perks = {}
	var pk: Dictionary = d.get("perks", {})
	for k in pk:
		perks[String(k)] = int(pk[k])
	merchant = d.get("merchant", {})
	if not merchant.is_empty():
		var bought: Array = []
		for i in merchant.get("bought", []):
			bought.append(int(i))
		merchant["bought"] = bought
		merchant["until"] = float(merchant["until"])
	auto_sell = bool(d.get("auto_sell", true))
	auto_pick = bool(d.get("auto_pick", false))
	radio_heard = (d.get("radio", []) as Array).duplicate()
	ela_t = float(d.get("ela_t", -1.0))
	_merchant_key = int(d.get("merchant_key", -1))
	if d.has("cycle_t0"):
		cycle_t0 = float(d["cycle_t0"])
	else:
		set_cycle_hour(float(bal["night"]["start_hour"]))   # save antigo: começa de manhã
	work_tonight = bool(d.get("work_tonight", false))
	fog_next = bool(d.get("fog_next", false))
	fog_now = bool(d.get("fog_now", false))
	fog_bonus_until = float(d.get("fog_bonus_until", 0.0))
	_was_night = is_night()
	_lines_dirty = true
	_invalidate()
	# Saves de antes da trilha: abre o caminho do porto (quem já chegou fica livre para sair).
	if not _first("gate").is_empty():
		_carve_trail(_door(_first("gate")), _door(_first("hatch")))
	_rebuild_astar()
	# Quem estava carregando entrega no depósito ao voltar (não se perde nada).
	for p in people:
		if String(p["carry_res"]) != "":
			_deliver(p)


## Alcança o relógio depois de um tempo fechado. Devolve o que mudou, para o resumo.
func catch_up(now_unix: float) -> Dictionary:
	var ctx := catch_up_start(now_unix)
	if ctx.is_empty():
		return {}
	advance(float(ctx["left"]))
	return catch_up_finish(ctx, now_unix)


## Em pedaços (o jogo anda alguns minutos de simulação por quadro e mostra o progresso):
## catch_up_start -> catch_up_chunk até devolver true -> catch_up_finish.
func catch_up_start(now_unix: float) -> Dictionary:
	var elapsed: float = now_unix - t
	var tb: Dictionary = bal["time"]
	if elapsed < float(tb["offline_min_s"]):
		if elapsed > 0.0:
			advance(elapsed)
		return {}
	elapsed = minf(elapsed, float(tb["offline_cap_h"]) * 3600.0)
	offline = true
	return {"seconds": elapsed, "left": elapsed, "before": stock.duplicate(), "built0": int(stats["built"]),
			"joined0": int(stats["joined"]), "radio0": radio_heard.size()}


func catch_up_chunk(ctx: Dictionary, seconds: float) -> bool:
	var d := minf(seconds, float(ctx["left"]))
	offline = true
	advance(d)
	ctx["left"] = float(ctx["left"]) - d
	return float(ctx["left"]) <= 0.0


func catch_up_finish(ctx: Dictionary, now_unix: float) -> Dictionary:
	offline = false
	t = maxf(t, now_unix)
	var delta := {}
	for r in RES:
		delta[r] = int(round(float(stock[r]) - float(ctx["before"][r])))
	return {"seconds": float(ctx["seconds"]), "delta": delta, "built": int(stats["built"]) - int(ctx["built0"]),
			"joined": int(stats["joined"]) - int(ctx["joined0"]), "group": not gate_group.is_empty(),
			"radio": radio_heard.size() - int(ctx["radio0"])}
