class_name VilaDefense
extends RefCounted
## Defesa da vila (estilo Clash of Clans): zumbis vêm à noite pelas praias, as defesas lutam
## sozinhas (ninguém da vila pega em arma). Toda noite uns poucos; a cada `horde_every` dias uma
## horda; a cada `boss_every`, horda com chefe. Com o jogo fechado a noite é resolvida na conta,
## com teto de estrago (balance defense.offline). Tudo em células (Vector2 em unidades de tile).

var sim: VilaSim
var zombies: Array[Dictionary] = []   # {id, kind, pos, hp, max, path, tgt, hit_t, repath_t, atk, facing}
var pending: Array[Dictionary] = []   # {kind, cell, at}: quem ainda vai sair da água esta noite
var fx: Array[Dictionary] = []        # só desenho: tiros, explosões, zumbi caindo {kind, a, b, t, life}
var tonight: Dictionary = {}          # {n, horde, boss, day}
var report: Dictionary = {}           # o que aconteceu na noite atual
var last_report: Dictionary = {}      # a noite que passou (o cartão da manhã mostra)
var _zgrid: AStarGrid2D
var _zdirty := true
var _next := 1
var _cool: Dictionary = {}            # id do prédio de defesa -> segundos até o próximo tiro
var _warned_day := -1
var offline_lost: Dictionary = {}     # recursos que os zumbis levaram nesta volta fechada (teto: offline.loot_max)
var _loot_base: Dictionary = {}       # estoque no começo da volta (o teto é uma fração dele)
var owed_horde := false               # horda que caiu com o jogo fechado: vem na próxima noite aberta
var owed_boss := 0


func _init(s: VilaSim) -> void:
	sim = s


func D() -> Dictionary:
	return sim.bal["defense"]


func dirty() -> void:
	_zdirty = true


# ================================================================ previsão
## Quantos vêm na noite do dia `day` (a mesma conta para o aviso e para a noite).
func forecast(day: int) -> Dictionary:
	var d := D()
	if day < int(d["from_day"]):
		return {"n": 0, "horde": false, "boss": 0, "day": day}
	var horde := day % int(d["horde_every"]) == 0
	var boss := 0
	if day % int(d["boss_every"]) == 0:
		boss = int(d["boss"]["base"]) + day / int(d["boss"]["per_days"])
	# Horda e chefão que caíram com o jogo fechado esperam a próxima noite com você olhando.
	if not sim.offline and (owed_horde or owed_boss > 0) and day >= sim.day_number() - 1:
		horde = true
		boss = maxi(boss, owed_boss)
	var n: int
	if horde:
		var hd: Dictionary = d["horde"]
		n = int(float(hd["base"]) + float(hd["per_day"]) * day + float(hd["per_tower"]) * (sim.tower - 1))
	else:
		var dd: Dictionary = d["daily"]
		var h := absi((day * 2654435761) % 1000)
		n = int(dd["base"]) + h % (int(dd["rand"]) + 1) + day / int(dd["per_days"])
	return {"n": n, "horde": horde, "boss": boss, "day": day}


## A noite que vem (ou a de agora, se já é noite).
func next_night() -> Dictionary:
	var day := sim.day_number()
	if sim.is_night() and sim.local_hour() < float(sim.bal["time"]["night_to_h"]):
		day -= 1   # madrugada: a noite começou no dia anterior
	return tonight if sim.is_night() and not tonight.is_empty() else forecast(day)


func zstats(kind: String) -> Dictionary:
	var z: Dictionary = D()["zombies"][kind]
	var k := 1.0 + float(D()["scale_per_day"]) * float(sim.day_number())
	return {"hp": float(z["hp"]) * k, "speed": float(z["speed"]), "dmg": float(z["dmg"]) * k,
			"hit_s": float(z["hit_s"]), "wall_mult": float(z.get("wall_mult", 1.0))}


## Alcance de tiro (ou de luz) de um prédio desse tipo nesse nível; 0 = não atira.
func range_of(type: String, level: int) -> float:
	if type == "hatch":
		return float(D()["hatch_gun"]["range"])
	var lvs: Array = sim.def(type).get("levels", [])
	if lvs.is_empty() or String(sim.def(type).get("defense", "")) == "":
		return 0.0
	var lv: Dictionary = lvs[clampi(level, 1, lvs.size()) - 1]
	return float(lv.get("range", lv.get("radius", 0.0)))


## Dia da próxima noite com zumbi (de hoje até 10 dias à frente); -1 se nenhuma.
func raid_day() -> int:
	var d := sim.day_number()
	for i in 11:
		var f := forecast(d + i)
		if int(f["n"]) + int(f["boss"]) > 0:
			return d + i
	return -1


var _arr_key := ""
var _arr: Array = []

## Por onde eles chegam na próxima noite com zumbi: [{cell, path}] (o caminho até o primeiro prédio
## que eles vão atacar). É a mesma conta da noite, então o que o mapa mostra é o que vai acontecer.
func arrivals() -> Array:
	var d := raid_day()
	if d < 0:
		return []
	var key := "%d|%d|%d|%d" % [d, sim.buildings.size(), sim.tower, 1 if _zdirty else 0]
	if key == _arr_key:
		return _arr
	if _zdirty:
		_rebuild_grid()
	_arr_key = "%d|%d|%d|0" % [d, sim.buildings.size(), sim.tower]
	_arr = []
	for sp in _spawn_spots(2 if bool(forecast(d)["horde"]) else 1, d):
		var fake := {"pos": Vector2(sp), "kind": "fraco"}
		var b := _pick_target(fake)
		var path := PackedVector2Array()
		if not b.is_empty():
			var g := _goal_cell(fake, b)
			if g.x >= 0:
				path = _to_path(_no_corner_cut(_zgrid.get_id_path(sp, g)))
		_arr.append({"cell": sp, "path": path})
	return _arr


# ================================================================ noite
func night_start() -> void:
	var day := sim.day_number()
	tonight = forecast(day)
	if sim.offline and (bool(tonight["horde"]) or int(tonight["boss"]) > 0):
		owed_horde = owed_horde or bool(tonight["horde"])
		owed_boss = maxi(owed_boss, int(tonight["boss"]))
		var dd: Dictionary = D()["daily"]
		tonight = {"n": int(dd["base"]) + day / int(dd["per_days"]), "horde": false, "boss": 0, "day": day}
	elif not sim.offline and int(tonight["n"]) > 0:
		owed_horde = false
		owed_boss = 0
	report = {"day": day, "came": int(tonight["n"]) + int(tonight["boss"]), "killed": 0, "broke": [], "ruined": [],
			"walls": 0, "horde": bool(tonight["horde"]), "boss": int(tonight["boss"]), "mines": 0, "offline": sim.offline}
	pending.clear()
	if int(report["came"]) == 0:
		return
	if sim.offline:
		_resolve_offline()
		return
	var spots := _spawn_spots(2 if bool(tonight["horde"]) else 1, day)
	if spots.is_empty():
		return
	var kinds: Array[String] = []
	for i in int(tonight["n"]):
		kinds.append("horda" if bool(tonight["horde"]) else "fraco")
	for i in int(tonight["boss"]):
		kinds.append("chefe")
	# A horda da noite sai toda junta logo no começo (dividida entre os lados), com meio segundo
	# entre um e outro só para não nascerem empilhados. Depois que morrem, nada até a próxima noite.
	for i in kinds.size():
		var at := sim.t + 3.0 + float(i / spots.size()) * 0.5
		var sp: Vector2i = spots[i % spots.size()]
		pending.append({"kind": kinds[i], "cell": sp, "at": at})


func _night_len() -> float:
	var tb: Dictionary = sim.bal["time"]
	var hrs := fposmod(float(tb["night_to_h"]) - float(tb["night_from_h"]), 24.0)
	return hrs / 24.0 * float(sim.bal["night"]["cycle_s"])


## Amanheceu: quem sobrou foge do sol; os muros se consertam sozinhos se der (como no Clash);
## a sequência de noites sem perder prédio conta para o recorde.
func night_end() -> void:
	for z in zombies:
		fx.append({"kind": "flee", "a": z["pos"], "b": z["pos"], "t": 0.0, "life": 1.2, "boss": String(z["kind"]) == "chefe"})
	zombies.clear()
	pending.clear()
	if report.is_empty():
		return
	report["walls_fixed"] = _repair_walls()
	var lost: int = (report["broke"] as Array).size() + (report["ruined"] as Array).size()
	var st := sim.stats
	if int(report["came"]) > 0:
		st["nights_def"] = int(st.get("nights_def", 0)) + 1
		st["z_killed"] = int(st.get("z_killed", 0)) + int(report["killed"])
		st["streak"] = 0 if lost > 0 else int(st.get("streak", 0)) + 1
		st["best_streak"] = maxi(int(st.get("best_streak", 0)), int(st["streak"]))
		if bool(report["horde"]):
			st["hordes"] = int(st.get("hordes", 0)) + 1
	last_report = report
	report = {}
	tonight = {}
	if int(last_report["came"]) > 0:
		sim.raid_over.emit(last_report)


## Aviso no fim da tarde (balance defense.warn_h); horda avisa já na tarde anterior.
func warn_step() -> void:
	var hr := sim.local_hour()
	var day := sim.day_number()
	if sim.is_night() or hr < float(D()["warn_h"]) or _warned_day == day:
		return
	_warned_day = day
	var f := forecast(day)
	var nxt := forecast(day + 1)
	if int(f["n"]) + int(f["boss"]) > 0 or bool(nxt["horde"]):
		sim.raid_warning.emit(f, nxt)


# ================================================================ passo
func step(dt: float, night: bool) -> void:
	if not fx.is_empty():
		for e in fx:
			e["t"] = float(e["t"]) + dt
		fx = fx.filter(func(e: Dictionary) -> bool: return float(e["t"]) < float(e["life"]))
	if not sim.offline:
		warn_step()
	if not pending.is_empty():
		var due: Array[Dictionary] = []
		for pd in pending:
			if sim.t >= float(pd["at"]):
				due.append(pd)
		for pd in due:
			pending.erase(pd)
			_spawn(String(pd["kind"]), pd["cell"])
	if zombies.is_empty():
		return
	if _zdirty:
		_rebuild_grid()
	_towers(dt, night)
	for z in zombies.duplicate():
		_zombie_step(z, dt)
	_mines()
	_hurt_people(dt)
	# Já levaram o máximo da noite: voltam para a água (antes ficavam batendo num prédio que não caía,
	# parados no mapa sem nada acontecer).
	if _lost_tonight() >= int(D()["max_lost_night"]) and not report.is_empty():
		retreat()
		return
	var dead: Array[Dictionary] = []
	for z in zombies:
		if float(z["hp"]) <= 0.0:
			dead.append(z)
	for z in dead:
		zombies.erase(z)
		report["killed"] = int(report.get("killed", 0)) + 1
		fx.append({"kind": "zdie", "a": z["pos"], "b": z["pos"], "t": 0.0, "life": 1.0, "boss": String(z["kind"]) == "chefe", "facing": z["facing"]})


## Meta durante o ataque: quantos, o prédio que mais apanha e se alguma defesa alcança ele.
func raid_goal() -> Dictionary:
	var hits := {}
	for z in zombies:
		var id := int(z.get("atk", -1))
		if id < 0:
			id = int(z.get("tgt", -1))
		if id >= 0:
			hits[id] = int(hits.get(id, 0)) + 1
	var best := -1
	for id in hits:
		if best < 0 or int(hits[id]) > int(hits[best]):
			best = int(id)
	var b := sim.by_id(best)
	if b.is_empty() or String(b["type"]) == "muro":
		return {"kind": "raid", "n": zombies.size(), "id": -1, "type": "", "covered": false}
	return {"kind": "raid", "n": zombies.size(), "id": best, "type": String(b["type"]), "covered": covered(center_of(b))}


## Alguma defesa funcionando alcança este ponto (casas)?
func covered(at: Vector2) -> bool:
	for d in sim.buildings:
		var tp := String(d["type"])
		var r := range_of(tp, int(d["level"]))
		if r <= 0.0 or String(sim.def(tp).get("defense", "")) == "light":
			continue
		if tp != "hatch" and not sim._working(d):
			continue
		# Choque sem energia não atira (mesma regra de _towers): não conta como defesa.
		if String(sim.def(tp).get("defense", "")) == "shock" and sim.power_frac() <= 0.0:
			continue
		if center_of(d).distance_to(at) <= r:
			return true
	return false


## Antes da noite (da hora do aviso até o primeiro sair da água): quantos, de que lado e em quanto tempo.
func raid_soon() -> Dictionary:
	var day := sim.day_number()
	var night := sim.is_night()
	if not zombies.is_empty():
		return {}
	var left := 0.0
	var n := 0
	if night:
		if pending.is_empty():
			return {}
		left = 1e9
		for pd in pending:
			left = minf(left, float(pd["at"]) - sim.t)
		n = pending.size()
	else:
		if sim.local_hour() < float(D()["warn_h"]):
			return {}
		var f := forecast(day)
		n = int(f["n"]) + int(f["boss"])
		if n <= 0:
			return {}
		var tb: Dictionary = sim.bal["time"]
		left = fposmod(float(tb["night_from_h"]) - sim.local_hour(), 24.0) / 24.0 * float(sim.bal["night"]["cycle_s"])
	var dirs: Array[String] = []
	var hc := Vector2(Vector2i(sim._first("hatch").get("cell", Vector2i.ZERO)))
	for a in arrivals():
		var v := Vector2(Vector2i(a["cell"])) - hc
		var d := ("e" if v.x > 0 else "w") if absf(v.x) > absf(v.y) else ("s" if v.y > 0 else "n")
		if not dirs.has(d):
			dirs.append(d)
	return {"n": n, "left_s": maxf(0.0, left), "dirs": dirs}


## Os zumbis desistem da noite e voltam para a água (os que ainda iam sair também não saem).
func retreat() -> void:
	for z in zombies:
		fx.append({"kind": "flee", "a": z["pos"], "b": z["pos"], "t": 0.0, "life": 1.2, "boss": String(z["kind"]) == "chefe"})
	zombies.clear()
	pending.clear()
	report["retreat"] = true
	sim.raid_retreat.emit(report)


func _spawn(kind: String, cell: Vector2i) -> void:
	var s := zstats(kind)
	var jitter := Vector2(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))
	zombies.append({"id": _next, "kind": kind, "pos": Vector2(cell) + jitter, "hp": s["hp"], "max": s["hp"],
			"path": PackedVector2Array(), "tgt": -1, "hit_t": 0.0, "repath_t": 0.0, "atk": -1, "facing": 1.0})
	_next += 1


## Pontos de chegada: chão na beira da água, longe do porto e fora da área da vila.
func _spawn_spots(n_sides: int, day: int) -> Array[Vector2i]:
	var cands: Array[Vector2i] = []
	var gate: Dictionary = sim._first("gate")
	var gc: Vector2i = gate.get("cell", Vector2i(-99, -99))
	var hd := sim._hatch_door()
	for y in sim.h:
		for x in sim.w:
			var c := Vector2i(x, y)
			var k := sim.terrain_at(c)
			if k != VilaSim.T_GROUND and k != VilaSim.T_STUMP:
				continue
			if sim.occ[sim._i(c)] >= 0 or Vector2(c).distance_to(Vector2(gc)) < 8.0:
				continue
			var shore := false
			for o in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
				if sim.terrain_at(c + o) == VilaSim.T_WATER:
					shore = true
			if shore and Vector2(c).distance_to(Vector2(hd)) > 6.0:
				cands.append(c)
	if cands.is_empty():
		return []
	var out: Array[Vector2i] = []
	var r := RandomNumberGenerator.new()
	r.seed = day * 7919 + 0x51ed   # pelo dia: o mapa mostra de dia por onde eles vão chegar
	var first: Vector2i = cands[r.randi_range(0, cands.size() - 1)]
	out.append(first)
	if n_sides > 1:   # o segundo lado: o ponto da beira mais longe do primeiro
		var far := first
		var fd := 0.0
		for c in cands:
			var d := Vector2(c).distance_to(Vector2(first))
			if d > fd:
				fd = d
				far = c
		out.append(far)
	return out


# ================================================================ caminho dos zumbis
## Grade própria: muro em pé não é parede, é caminho caro (eles preferem dar a volta; se não tem
## volta, quebram o muro). Prédio bloqueia; mata e entulho só atrasam; mina e praça deixam passar.
func _rebuild_grid() -> void:
	_zdirty = false
	_zgrid = AStarGrid2D.new()
	_zgrid.region = Rect2i(0, 0, sim.w, sim.h)
	_zgrid.cell_size = Vector2(1, 1)
	_zgrid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_zgrid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_zgrid.update()
	var ww := float(D()["wall_weight"])
	for y in sim.h:
		for x in sim.w:
			var c := Vector2i(x, y)
			var k := sim.terrain_at(c)
			if k == VilaSim.T_WATER:
				_zgrid.set_point_solid(c, true)
				continue
			if k == VilaSim.T_TREE or k == VilaSim.T_RUBBLE:
				# Mata e entulho atrasam mas não param (antes, quem nascia atrás da mata ficava preso).
				_zgrid.set_point_weight_scale(c, float(D().get("forest_weight", 6.0)))
				continue
			var o := sim.occ[sim._i(c)]
			if o < 0:
				continue
			var b := sim.by_id(o)
			var tp := String(b.get("type", ""))
			if tp == "muro":
				var wh := hp(b)
				if wh > 0.0:
					_zgrid.set_point_weight_scale(c, 1.0 + wh * ww)
			elif tp == "mina" or bool(sim.def(tp).get("open", false)):
				pass
			else:
				_zgrid.set_point_solid(c, true)


## Prédio que pode apanhar: não é antena, bunker, porto, muro nem mina; pronto ou em obra de melhoria.
func attackable(b: Dictionary) -> bool:
	var tp := String(b["type"])
	if tp in ["torre", "hatch", "gate", "muro", "mina"] or bool(sim.def(tp).get("fixed", false)):
		return false
	if bool(sim.def(tp).get("deco", false)) or bool(b.get("ruin", false)):
		return false
	return String(b["state"]) != "site"


func center_of(b: Dictionary) -> Vector2:
	var fp := sim._fp(String(b["type"]))
	return Vector2(Vector2i(b["cell"])) + Vector2(fp) / 2.0 - Vector2(0.5, 0.5)


## O zumbi encosta no prédio (célula vizinha da pegada, contando diagonal).
func _touching(c: Vector2i, b: Dictionary) -> bool:
	var fp := sim._fp(String(b["type"]))
	var bc: Vector2i = b["cell"]
	return c.x >= bc.x - 1 and c.x <= bc.x + fp.x and c.y >= bc.y - 1 and c.y <= bc.y + fp.y \
			and not (c.x >= bc.x and c.x < bc.x + fp.x and c.y >= bc.y and c.y < bc.y + fp.y)


func _pick_target(z: Dictionary) -> Dictionary:
	var best := {}
	var bd := 1e9
	var best_b := {}
	var bdb := 1e9
	for b in sim.buildings:
		if not attackable(b):
			continue
		var d: float = Vector2(z["pos"]).distance_squared_to(center_of(b))
		if bool(b.get("broken", false)):
			if d < bdb:
				bdb = d
				best_b = b
		elif d < bd:
			bd = d
			best = b
	# Prédio inteiro primeiro; o chefe termina o que começou (avariado vira ruína).
	if best.is_empty() or (String(z["kind"]) == "chefe" and not best_b.is_empty() and bdb < bd * 0.5):
		return best_b
	return best


func _goal_cell(z: Dictionary, b: Dictionary) -> Vector2i:
	var fp := sim._fp(String(b["type"]))
	var bc: Vector2i = b["cell"]
	var best := Vector2i(-1, -1)
	var bd := 1e9
	for y in range(bc.y - 1, bc.y + fp.y + 1):
		for x in range(bc.x - 1, bc.x + fp.x + 1):
			var c := Vector2i(x, y)
			if not sim._inside(c) or _zgrid.is_point_solid(c) or not _touching(c, b):
				continue
			var d: float = Vector2(c).distance_squared_to(z["pos"])
			if d < bd:
				bd = d
				best = c
	return best


func _repath(z: Dictionary) -> void:
	z["repath_t"] = 2.5
	var b := _pick_target(z)
	z["tgt"] = int(b.get("id", -1))
	z["path"] = PackedVector2Array()
	if b.is_empty():
		return
	var g := _goal_cell(z, b)
	if g.x < 0:
		return
	var from := Vector2i(Vector2(z["pos"]).round())
	if not sim._inside(from):
		return
	if _zgrid.is_point_solid(from):
		_zgrid.set_point_solid(from, false)
		var ids := _zgrid.get_id_path(from, g)
		_zgrid.set_point_solid(from, true)
		z["path"] = _to_path(_no_corner_cut(ids))
	else:
		z["path"] = _to_path(_no_corner_cut(_zgrid.get_id_path(from, g)))


func _wall_up(c: Vector2i) -> bool:
	var b := sim.building_at(c)
	return not b.is_empty() and String(b["type"]) == "muro" and hp(b) > 0.0


## Passo na diagonal entre dois muros em pé (a quina de uma cerca em escada) não existe: o zumbi
## tem que entrar num dos dois, e aí para e quebra.
func _no_corner_cut(ids: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in ids.size():
		if i > 0:
			var a := ids[i - 1]
			var b := ids[i]
			if a.x != b.x and a.y != b.y:
				var c1 := Vector2i(b.x, a.y)
				var c2 := Vector2i(a.x, b.y)
				if _wall_up(c1) and _wall_up(c2):
					out.append(c1)
		out.append(ids[i])
	return out


func _to_path(ids: Array[Vector2i]) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, ids.size()):
		out.append(Vector2(ids[i]))
	return out


func _zombie_step(z: Dictionary, dt: float) -> void:
	var s := zstats(String(z["kind"]))
	z["hit_t"] = maxf(0.0, float(z["hit_t"]) - dt)
	z["repath_t"] = float(z["repath_t"]) - dt
	var tb := sim.by_id(int(z["tgt"]))
	if tb.is_empty() or not attackable(tb) or (bool(tb.get("broken", false)) and String(z["kind"]) != "chefe" and z["repath_t"] <= 0.0) \
			or ((z["path"] as PackedVector2Array).is_empty() and float(z["repath_t"]) <= 0.0 and int(z["atk"]) < 0):
		_repath(z)
		tb = sim.by_id(int(z["tgt"]))
	var cell := Vector2i(Vector2(z["pos"]).round())
	# Encostou no alvo: bate.
	if not tb.is_empty() and _touching(cell, tb):
		z["atk"] = int(tb["id"])
		var dir: float = center_of(tb).x - float(Vector2(z["pos"]).x)
		if absf(dir) > 0.1:
			z["facing"] = signf(dir)
		if float(z["hit_t"]) <= 0.0:
			z["hit_t"] = float(s["hit_s"])
			hit_building(tb, float(s["dmg"]), z["pos"])
		return
	z["atk"] = -1
	var path: PackedVector2Array = z["path"]
	if path.is_empty():
		# Sem caminho (cercado de prédio): anda reto até o alvo em vez de ficar parado no mapa.
		if tb.is_empty():
			return
		var tgt := center_of(tb)
		var p0: Vector2 = z["pos"]
		if p0.distance_to(tgt) > 0.6:
			var st := float(s["speed"]) * dt
			var np := p0 + (tgt - p0).normalized() * minf(st, p0.distance_to(tgt))
			var ahead := sim.building_at(Vector2i((p0 + (tgt - p0).normalized() * 0.6).round()))
			if not ahead.is_empty() and String(ahead["type"]) == "muro" and hp(ahead) > 0.0:
				# Muro na frente: para e quebra (nunca passa por cima).
				z["atk"] = int(ahead["id"])
				if float(z["hit_t"]) <= 0.0:
					z["hit_t"] = float(s["hit_s"])
					hit_building(ahead, float(s["dmg"]) * float(s["wall_mult"]), z["pos"])
				return
			z["pos"] = np
			if absf(tgt.x - p0.x) > 0.05:
				z["facing"] = signf(tgt.x - p0.x)
		return
	var nxt: Vector2 = path[0]
	var nc := Vector2i(nxt)
	# Muro em pé no caminho: para e quebra.
	var wb := sim.building_at(nc)
	if not wb.is_empty() and String(wb["type"]) == "muro" and hp(wb) > 0.0:
		z["atk"] = int(wb["id"])
		if float(z["hit_t"]) <= 0.0:
			z["hit_t"] = float(s["hit_s"])
			hit_building(wb, float(s["dmg"]) * float(s["wall_mult"]), z["pos"])
		return
	var pos: Vector2 = z["pos"]
	var step := float(s["speed"]) * dt
	var d := pos.distance_to(nxt)
	if absf(nxt.x - pos.x) > 0.05:
		z["facing"] = signf(nxt.x - pos.x)
	if d <= step:
		z["pos"] = nxt
		path.remove_at(0)
		z["path"] = path
	else:
		z["pos"] = pos + (nxt - pos) / d * step


# ================================================================ dano
func max_hp(b: Dictionary) -> float:
	var lv := sim.level_def(b)
	if lv.has("hp"):
		return float(lv["hp"])
	var bh: Dictionary = D()["building_hp"]
	var fp := sim._fp(String(b["type"]))
	return float(bh["base"]) + float(bh["per_level"]) * int(b["level"]) + float(bh["per_tile"]) * fp.x * fp.y


func hp(b: Dictionary) -> float:
	return float(b.get("hp", max_hp(b)))


func _lost_tonight() -> int:
	return (report.get("broke", []) as Array).size() + (report.get("ruined", []) as Array).size()


func hit_building(b: Dictionary, dmg: float, from: Vector2 = Vector2(-99, -99)) -> void:
	var h := hp(b) - dmg
	if from.x > -90.0:   # pancada: faísca no ponto onde o zumbi bate (o jogador vê que está apanhando)
		fx.append({"kind": "hit", "a": from, "b": from.lerp(center_of(b), 0.45), "t": 0.0, "life": 0.35, "id": int(b["id"])})
	var tp := String(b["type"])
	# Teto por noite (defense.max_lost_night): passado dele, o prédio aguenta no fio.
	var capped := _lost_tonight() >= int(D()["max_lost_night"])
	if tp == "muro":
		b["hp"] = maxf(0.0, h)
		if h <= 0.0:
			report["walls"] = int(report.get("walls", 0)) + 1
			_zdirty = true
			fx.append({"kind": "breach", "a": center_of(b), "b": center_of(b), "t": 0.0, "life": 1.2, "id": int(b["id"])})
		return
	if bool(b.get("broken", false)):
		# Já avariado: o que passa disso vira ruína.
		if capped:
			return
		b["wreck"] = float(b.get("wreck", 0.0)) + dmg
		if float(b["wreck"]) >= max_hp(b):
			_ruin(b)
		return
	if capped:
		b["hp"] = maxf(1.0, h)
		return
	b["hp"] = maxf(0.0, h)
	if h <= 0.0:
		_break(b)


func _break(b: Dictionary) -> void:
	b["broken"] = true
	b["hp"] = 0.0
	b["wreck"] = 0.0
	sim._release_workers(b)
	sim._invalidate()
	(report["broke"] as Array).append(int(b["id"]))
	sim.changed.emit()


func _ruin(b: Dictionary) -> void:
	b["ruin"] = true
	(report["broke"] as Array).erase(int(b["id"]))
	(report["ruined"] as Array).append(int(b["id"]))
	sim._invalidate()
	sim.changed.emit()


## Muros: no amanhecer voltam inteiros pagando o conserto, se o estoque der (fechado, de graça).
func _repair_walls() -> int:
	var n := 0
	for b in sim.buildings:
		if String(b["type"]) != "muro":
			continue
		var mh := max_hp(b)
		var h := hp(b)
		if h >= mh:
			continue
		# Com o jogo fechado a base volta inteira de graça (como no Clash): o custo da noite é só o
		# que os zumbis levaram, com teto.
		var cost := repair_cost(b) if not sim.offline else {}
		if sim.can_afford(cost):
			sim._pay(cost)
			b["hp"] = mh
			n += 1
	if n > 0:
		_zdirty = true
	return n


## Conserto: fração do custo do nível atual, proporcional ao estrago.
func repair_cost(b: Dictionary) -> Dictionary:
	var frac := float(D()["repair_frac"]) * (1.0 - hp(b) / maxf(1.0, max_hp(b)))
	if bool(b.get("broken", false)):
		frac = float(D()["repair_frac"])
	var cost: Dictionary = sim.level_def(b)["cost"]
	var out := {}
	for r in cost:
		var v := int(ceil(float(cost[r]) * frac))
		if v > 0:
			out[r] = v
	return out


func rebuild_cost(b: Dictionary) -> Dictionary:
	var cost: Dictionary = sim.level_def(b)["cost"]
	var out := {}
	for r in cost:
		out[r] = int(ceil(float(cost[r]) * float(D()["rebuild_frac"])))
	return out


# ================================================================ defesas
func _towers(dt: float, night: bool) -> void:
	var pf := sim.power_frac()
	for b in sim.buildings:
		var tp := String(b["type"])
		var kind := String(sim.def(tp).get("defense", ""))
		if kind == "" or kind == "light" or not sim._working(b):
			continue
		if kind == "shock" and pf <= 0.0:
			continue
		var lv := gun(b)
		var id := int(b["id"])
		var cd := float(_cool.get(id, 0.0)) - dt * _rate_mult(b)
		if cd > 0.0:
			_cool[id] = cd
			continue
		var c := center_of(b)
		var rng := float(lv["range"])
		var tgt := {}
		var td := 1e9
		for z in zombies:
			if float(z["hp"]) <= 0.0:
				continue
			var d := c.distance_to(z["pos"])
			if d <= rng and d < td:
				td = d
				tgt = z
		if tgt.is_empty():
			_cool[id] = 0.0
			continue
		_cool[id] = float(lv["rate_s"])
		var dmg := float(lv["dmg"]) * _dmg_mult(b, night)
		var from := c + Vector2(0, -1.2)
		match kind:
			"arrow":
				tgt["hp"] = float(tgt["hp"]) - dmg
				fx.append({"kind": "arrow", "a": from, "b": tgt["pos"], "t": 0.0, "life": 0.25})
			"cannon":
				var at: Vector2 = tgt["pos"]
				var sp := float(lv["splash"])
				for z in zombies:
					if Vector2(z["pos"]).distance_to(at) <= sp:
						z["hp"] = float(z["hp"]) - dmg
				fx.append({"kind": "ball", "a": c + Vector2(0, -0.6), "b": at, "t": 0.0, "life": 0.45})
				fx.append({"kind": "boom", "a": at, "b": at, "t": -0.35, "life": 0.55, "r": sp})
			"shock":
				var hit := [tgt]
				var last: Dictionary = tgt
				for i in int(lv["chain"]) - 1:
					var nb := {}
					var nd := 1e9
					for z in zombies:
						if hit.has(z):
							continue
						var d2 := Vector2(z["pos"]).distance_to(last["pos"])
						if d2 <= 2.5 and d2 < nd:
							nd = d2
							nb = z
					if nb.is_empty():
						break
					hit.append(nb)
					last = nb
				var prev := from
				for z in hit:
					z["hp"] = float(z["hp"]) - dmg
					fx.append({"kind": "zap", "a": prev, "b": z["pos"], "t": 0.0, "life": 0.3})
					prev = z["pos"]


## Números da arma: o nível do prédio; a escotilha tem a espingarda do Joaquim (defense.hatch_gun).
func gun(b: Dictionary) -> Dictionary:
	if String(b["type"]) == "hatch":
		return D()["hatch_gun"]
	return sim.level_def(b)


## Holofote perto: as torres batem mais forte de noite.
func _dmg_mult(b: Dictionary, night: bool) -> float:
	if not night:
		return 1.0
	var m := 1.0
	var c := center_of(b)
	for h in sim.buildings:
		if String(sim.def(String(h["type"])).get("defense", "")) != "light" or not sim._working(h) or sim.power_frac() <= 0.0:
			continue
		var lv := sim.level_def(h)
		if center_of(h).distance_to(c) <= float(lv["radius"]):
			m = maxf(m, 1.0 + float(lv["buff"]))
	return m


## Vigia dentro da torre: atira mais rápido.
func _rate_mult(b: Dictionary) -> float:
	var g := sim.person(int(b.get("guard", -1)))
	if g.is_empty():
		return 1.0
	# O mesmo % que o cartão da pessoa mostra no passivo (15/30/50% pela raridade).
	return sim.bonus(g, "guard")


func _mines() -> void:
	for b in sim.buildings.duplicate():
		if String(b["type"]) != "mina" or String(b["state"]) != "built":
			continue
		var c := Vector2(Vector2i(b["cell"]))
		var trig := false
		for z in zombies:
			if Vector2(z["pos"]).distance_to(c) < 0.7:
				trig = true
		if not trig:
			continue
		var lv := sim.level_def(b)
		for z in zombies:
			if Vector2(z["pos"]).distance_to(c) <= float(lv["splash"]):
				z["hp"] = float(z["hp"]) - float(lv["dmg"])
		fx.append({"kind": "boom", "a": c, "b": c, "t": 0.0, "life": 0.7, "r": float(lv["splash"])})
		report["mines"] = int(report.get("mines", 0)) + 1
		sim._remove_building(b)


## Quem está fora de casa à noite perto de zumbi se machuca (com o jogo aberto; offline não).
func _hurt_people(dt: float) -> void:
	var dmg := float(D()["people_dmg"])
	for p in sim.people:
		if p["asleep"] or String(p["job"].get("kind", "")) == "guard":
			continue
		for z in zombies:
			if Vector2(z["pos"]).distance_to(p["pos"]) < 0.9:
				var was := sim.health_state(p)
				p["health"] = maxf(1.0 if not sim._can_leave(p) else 0.0, float(p["health"]) - dmg * dt)
				p["bitten_t"] = sim.t
				p["why"] = "bite"
				if not report.is_empty():
					var bit: Array = report.get("bitten", [])
					if not bit.has(int(p["id"])):
						bit.append(int(p["id"]))
						fx.append({"kind": "bite", "a": p["pos"], "b": p["pos"], "t": 0.0, "life": 0.8})
					report["bitten"] = bit
				if (was == "ok" or was == "weak") and sim.health_state(p) == "sick":
					sim.person_sick.emit(int(p["id"]))
				break


# ================================================================ offline
## Noite com o jogo fechado: conta de força. Ataque = vida dos zumbis × dano; defesa = o que as
## torres derrubam numa janela de luta + muros + minas. Estrago com teto (defense.offline).
func _resolve_offline() -> void:
	var od: Dictionary = D()["offline"]
	var attack := 0.0
	var n := int(tonight["n"])
	var hz := zstats("horda" if bool(tonight["horde"]) else "fraco")
	attack += float(hz["hp"]) * n
	if int(tonight["boss"]) > 0:
		attack += float(zstats("chefe")["hp"]) * int(tonight["boss"])
	var defense := 0.0
	var fight := float(od["fight_s"])
	for b in sim.buildings:
		var kind := String(sim.def(String(b["type"])).get("defense", ""))
		if kind == "" or kind == "light" or not sim._working(b):
			continue
		if kind == "shock" and sim.power_frac() <= 0.0:
			continue
		var lv := gun(b)
		var dps := float(lv["dmg"]) / float(lv["rate_s"]) * _rate_mult(b)
		if kind == "cannon":
			dps *= float(od["splash_k"])
		elif kind == "shock":
			dps *= float(lv["chain"]) * 0.6
		defense += dps * fight * _dmg_mult(b, true)
	var walls := 0.0
	for b in sim.buildings:
		if String(b["type"]) == "muro":
			walls += hp(b)
	defense += walls * float(od["wall_k"])
	for b in sim.buildings.duplicate():
		if String(b["type"]) == "mina" and attack > defense:
			defense += float(sim.level_def(b)["dmg"]) * 2.0
			report["mines"] = int(report.get("mines", 0)) + 1
			sim._remove_building(b)
	var came := n + int(tonight["boss"])
	if defense >= attack:
		report["killed"] = came
		_chip_walls(attack * float(od["wall_chip"]))
		return
	report["killed"] = int(floor(float(came) * defense / maxf(1.0, attack)))
	_chip_walls(walls)
	# Como o ataque do Clash: nada quebra; os zumbis levam um pouco do estoque, com teto por volta.
	var lf := float(od["loot_frac"]) * minf(1.0, (attack - defense) / maxf(1.0, attack))
	for r in ["comida", "agua", "madeira", "sucata"]:
		var room := float(od["loot_max"]) * float(_loot_base.get(r, 0.0)) - float(offline_lost.get(r, 0.0))
		var take := minf(room, float(sim.stock[r]) * lf)
		if take >= 1.0:
			take = floorf(take)
			sim.stock[r] = float(sim.stock[r]) - take
			offline_lost[r] = float(offline_lost.get(r, 0.0)) + take


## Começo de uma volta fechada: zera o que foi levado e guarda a base do teto.
func offline_start() -> void:
	offline_lost = {}
	_loot_base = sim.stock.duplicate()


func _chip_walls(amount: float) -> void:
	for b in sim.buildings:
		if amount <= 0.0:
			return
		if String(b["type"]) != "muro":
			continue
		var h := hp(b)
		var take := minf(h, amount)
		b["hp"] = h - take
		amount -= take
		if h - take <= 0.0:
			report["walls"] = int(report.get("walls", 0)) + 1
	_zdirty = true


# ================================================================ save
func to_dict() -> Dictionary:
	var zs: Array = []
	for z in zombies:
		zs.append({"kind": z["kind"], "pos": [Vector2(z["pos"]).x, Vector2(z["pos"]).y], "hp": z["hp"], "max": z["max"]})
	var ps: Array = []
	for pd in pending:
		ps.append({"kind": pd["kind"], "cell": [Vector2i(pd["cell"]).x, Vector2i(pd["cell"]).y], "at": pd["at"]})
	return {"zombies": zs, "pending": ps, "tonight": tonight, "report": report, "last": last_report, "warned": _warned_day,
			"owed_horde": owed_horde, "owed_boss": owed_boss}


func from_dict(d: Dictionary) -> void:
	zombies.clear()
	pending.clear()
	owed_horde = bool(d.get("owed_horde", false))
	owed_boss = int(d.get("owed_boss", 0))
	for e in d.get("zombies", []):
		zombies.append({"id": _next, "kind": String(e["kind"]), "pos": Vector2(float(e["pos"][0]), float(e["pos"][1])),
				"hp": float(e["hp"]), "max": float(e["max"]), "path": PackedVector2Array(), "tgt": -1, "hit_t": 0.0,
				"repath_t": 0.0, "atk": -1, "facing": 1.0})
		_next += 1
	for e in d.get("pending", []):
		pending.append({"kind": String(e["kind"]), "cell": Vector2i(int(e["cell"][0]), int(e["cell"][1])), "at": float(e["at"])})
	tonight = d.get("tonight", {})
	report = d.get("report", {})
	for k in ["broke", "ruined"]:
		if report.has(k):
			var arr: Array = []
			for v in report[k]:
				arr.append(int(v))
			report[k] = arr
	last_report = d.get("last", {})
	_warned_day = int(d.get("warned", -1))
	_zdirty = true
