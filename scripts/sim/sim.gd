class_name Sim
extends RefCounted
## Toda a lógica do bunker: sem nós, sem relógio de parede, determinística.
## `advance(game_minutes)` avança em passos de balance.time.step_min. Modelo e números: ver
## docs/CONTRATOS.md (4.3) e tools/sim_oracle/economia_sim.py (o oráculo). Números só em data/balance.json.
##
## Convenções que o contrato deixava em aberto (decididas aqui):
##  - `t_min` = minutos de jogo desde o início; `start_min` = hora do dia (min) em que o jogo começou.
##    Tempo absoluto = start_min + t_min (dia de calendário = floor(abs / 1440)).
##  - Compra de item: cria instância "building" + job de obra; o efeito (plots, energia, água, caixa)
##    só vale quando o job termina. Antena: efeito imediato (a voz chega na hora), a mão de obra é
##    consumida num job escondido. Escavar: job; a sala vale quando termina (room_dug).
##  - Substituição de linha: a instância antiga some NA COMPRA (item_removed, sem reembolso), mas o nível
##    de serviço da linha só sobe quando a nova termina (nunca falta água/energia durante a obra).
##  - Itens de linha (água/energia/transporte), plots iniciais e itens da casa não podem ser demolidos
##    (só substituídos/movidos). Os demais: demolir devolve 100% do que foi pago.
##  - `missing` = chaves i18n; os argumentos ({n}, {item}) vão num array paralelo `missing_args`.
##  - Escavação aparece no catálogo como itens "comodo2"/"comodo3" (line "escavacao").

signal state_changed()
signal item_placed(instance_id: int)
signal item_finished(instance_id: int, item_id: String)
signal item_removed(instance_id: int)
signal room_dug(room: int)
signal antenna_changed(level: int)
signal radio_line(line: Dictionary)
signal diary_changed()
signal visit_happened(info: Dictionary)
signal plot_harvested(plot_id: int)
signal helped(instance_id: int)   # clique de ajuda aceito (a cena faz uma faísca)
signal box_state_changed(fill: float, overflow: bool)
signal welcome_back(summary: Dictionary)
signal house_item_bought(item_id: String)
signal arrival_started()
signal arrival_finished()
signal new_game_started()
signal game_loaded()

const FORMAT_VERSION := 1
const SERVICE_LINES: Array[String] = ["agua", "energia", "transporte"]
const MAX_DIARY := 600
## Folga de fim de obra (min): evita a convergência assintótica quando ele está sobrecarregado (f < 1).
const JOB_EPS_MIN := 0.1

# ---------------------------------------------------------------- estado (tudo salvo)
var seed_value: int = 0
var rng := RandomNumberGenerator.new()
var t_min: float = 0.0
var start_min: float = 0.0
var _acc: float = 0.0
var scrap: float = 0.0
var stock: int = 0                 # cestos na caixa
var stock_value: float = 0.0       # soma do preço dos cestos na caixa
var antenna_level: int = 1
var rooms_n: int = 1
## Versão da disposição dos cômodos nos saves (2 = cada linha de itens no seu cômodo).
const LAYOUT_VERSION: int = 2
var _instances: Array = []         # Array[Dictionary]
var _plots: Array = []
var _jobs: Array = []
var _next_id: int = 1
var _next_plot_id: int = 1
var _next_job_id: int = 1
var _line_ready: Dictionary = {}   # linha -> item pronto ("agua": "lata", ...)
var _missed_meals: int = 0
var _busy: float = 0.0
var _labor_f: float = 1.0   ## fração do trabalho que o homem dá conta (para estimar a colheita)
var _diary: Array = []             # do mais antigo para o mais novo
var _next_diary_id: int = 1
var _pending: Array = []           # falas agendadas {src, id, due(abs), kind}
var _antenna_t: Dictionary = {}    # nível -> t_min em que chegou
var contact_min: float = -1.0
var _help_day: int = -1           # dia em que `_help_used` vale
var _help_used: float = 0.0       # minutos de ciclo ajudados hoje
var _last_visit_abs: float = -1.0e9
var _arrival: String = "none"      # "none" | "pending" | "done"
var _house_bought: Dictionary = {}
var _epi_next: int = 0
var _pinned: String = ""
var _stats: Dictionary = {}

# ---------------------------------------------------------------- estado transitório
var _muted: bool = false           # catch-up: sem sinais finos
var _away: bool = false
var _away_lines: Array[String] = []
var _away_events: Array[Dictionary] = []
var _order_cache: Array = []
var _order_dirty: bool = true
var _box_q: int = -1
var _step: float = 10.0
var _wake: float = 360.0
var _sleep: float = 1320.0
var _price_scale: float = 1.0


func _init() -> void:
	Balance.ensure_loaded()
	_cache()
	_reset_state()


func _cache() -> void:
	_step = maxf(1.0, Balance.num("time.step_min", 10.0))
	_wake = Balance.num("time.awake_from_min", 360.0)
	_sleep = Balance.num("time.awake_to_min", 1320.0)
	_price_scale = Balance.num("time.price_scale", 1.0)


func _reset_state() -> void:
	t_min = 0.0
	_acc = 0.0
	scrap = 0.0
	stock = 0
	stock_value = 0.0
	antenna_level = 1
	rooms_n = 1
	_instances = []
	_plots = []
	_jobs = []
	_next_id = 1
	_next_plot_id = 1
	_next_job_id = 1
	_line_ready = {"agua": "lata", "energia": "bicicleta", "transporte": "balde"}
	_missed_meals = 0
	_busy = 0.0
	_diary = []
	_next_diary_id = 1
	_pending = []
	_antenna_t = {}
	contact_min = -1.0
	_arrival = "none"
	_house_bought = {}
	_epi_next = 0
	_pinned = ""
	_order_dirty = true
	_box_q = -1
	_stats = {"visits": 0, "harvested": 0, "scrap_earned": 0.0, "scrap_spent": 0.0,
			"sold_baskets": 0, "wasted_baskets": 0, "eaten": 0, "nights": 0, "bought": 0}


# ================================================================ ciclo de vida
## Começa um jogo novo. `start_tod_hours` < 0 usa balance.start.fallback_tod_hours (o Game passa a hora real).
func new_game(seed_v: int = 1, start_tod_hours: float = -1.0) -> void:
	_cache()
	_reset_state()
	seed_value = seed_v
	rng.seed = seed_v
	if start_tod_hours < 0.0:
		start_tod_hours = Balance.num("start.fallback_tod_hours", 9.0)
	start_min = fposmod(start_tod_hours * 60.0, 1440.0)
	scrap = Balance.num("start.sucata", 0.0)
	antenna_level = Balance.integer("start.antenna", 1)
	rooms_n = Balance.integer("start.rooms", 1)
	for o in Balance.val("start.owned", []):
		var d: Dictionary = o
		var iid := String(d["item"])
		var def := _def(iid)
		var inst := _make_instance(iid, int(d.get("room", 1)), int(d.get("col", -1)), "ready")
		inst["paid"] = 0
		inst["locked"] = String(def.get("line", "")) == "plantio"
		_instances.append(inst)
		_on_ready(inst, true)
	_antenna_t[antenna_level] = 0.0
	_on_antenna_reached(antenna_level, true)
	state_changed.emit()
	new_game_started.emit()


func _make_instance(item_id: String, room: int, col: int, state: String) -> Dictionary:
	var def := _def(item_id)
	var inst := {"id": _next_id, "item": item_id, "room": room, "col": col, "cols": int(def.get("cols", 0)),
			"state": state, "crop_order": "", "paid": 0, "locked": false}
	_next_id += 1
	return inst


# ================================================================ relógio
func advance(game_minutes: float) -> void:
	if game_minutes <= 0.0:
		return
	_acc += game_minutes
	var steps := 0
	while _acc >= _step - 1e-6:
		_acc -= _step
		_do_step()
		steps += 1
	if _acc < 0.0:
		_acc = 0.0
	if steps > 0 and not _muted:
		state_changed.emit()


func debug_advance_minutes(m: float) -> void:
	advance(m)


func set_time_scale(_x: float) -> void:
	pass  # a escala de tempo mora no Game; a Sim só recebe minutos


## Salta o relógio sem simular (usado quando a ausência passou do teto offline: mantém a hora do dia alinhada).
func skip_clock(minutes: float) -> void:
	if minutes > 0.0:
		t_min += minutes


func _crosses(a: float, b: float, slot_min: float) -> bool:
	var d: float = floorf(a / 1440.0)
	var s0: float = d * 1440.0 + slot_min
	if s0 >= a and s0 < b:
		return true
	var s1: float = s0 + 1440.0
	return s1 >= a and s1 < b


func _do_step() -> void:
	var a: float = start_min + t_min
	var b: float = a + _step
	var tod: float = fposmod(a + _step * 0.5, 1440.0)
	var awake: bool = tod >= _wake and tod < _sleep
	if _crosses(a, b, _wake):
		_stats["nights"] = int(_stats["nights"]) + 1
	if awake:
		_eat(a, b)
		_work_step()
		_visits(a, b)
	else:
		_busy = 0.0
	t_min += _step
	_deliver_due(b)
	if _arrival == "done":
		_epilogue(a, b)
	_check_journey()


# ---------------------------------------------------------------- comida
func _meal_slots() -> Array[float]:
	var n: int = maxi(0, Balance.integer("economy.eat_per_day", 3))
	var out: Array[float] = []
	var hours: Variant = Balance.val("economy.meal_hours", [])
	if hours is Array and (hours as Array).size() >= n:
		for i in n:
			out.append(float((hours as Array)[i]) * 60.0)
	else:
		var len_: float = _sleep - _wake
		for i in n:
			out.append(_wake + (float(i) + 0.5) * len_ / float(n))
	return out


func _eat(a: float, b: float) -> void:
	var meal := false
	for slot in _meal_slots():
		if _crosses(a, b, slot):
			meal = true
			break
	if meal:
		if stock >= 1:
			_eat_one()
		else:
			_missed_meals = mini(_missed_meals + 1, 4)
	elif _missed_meals > 0 and stock >= 1:
		_eat_one()


func _eat_one() -> void:
	var avg: float = stock_value / float(stock) if stock > 0 else 0.0
	stock -= 1
	stock_value = maxf(0.0, stock_value - avg)
	if stock == 0:
		stock_value = 0.0
	_missed_meals = 0
	_stats["eaten"] = int(_stats["eaten"]) + 1
	_box_signal()


func _speed() -> float:
	var floor_v: float = Balance.num("economy.hunger_speed_floor", 0.6)
	return maxf(floor_v, 1.0 - float(_missed_meals) * (1.0 - floor_v) * 0.5)


# ---------------------------------------------------------------- trabalho e produção
func _ordered_plots() -> Array:
	if _order_dirty:
		var arr: Array = _plots.duplicate()
		arr.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return _plot_key(x) < _plot_key(y))
		_order_cache = arr
		_order_dirty = false
	return _order_cache


func _plot_key(p: Dictionary) -> int:
	return int(p["tier"]) * 1000000 + int(p["inst"]) * 100 + int(p["index"])


## Ciclo de crescimento (o primeiro ciclo dos plots iniciais é o curto do tutorial).
func _cycle_of(p: Dictionary) -> float:
	if bool(p.get("first", false)):
		return maxf(1.0, Balance.num("start.first_cycle_min", 20.0))
	return _base_cycle(p)


## Ciclo normal da cultura: é ele que define a carga de trabalho (o tutorial não pesa no tempo dele).
func _base_cycle(p: Dictionary) -> float:
	return maxf(1.0, float(Balance.crop(String(p["crop"])).get("cycle_min", 120.0)))


func _room_factor(room: int) -> float:
	var arr: Variant = Balance.val("economy.carry_room_factor", [1.0])
	if arr is Array and (arr as Array).size() > 0:
		var idx: int = clampi(room - 1, 0, (arr as Array).size() - 1)
		return float((arr as Array)[idx])
	return 1.0


func _work_step() -> void:
	var order: Array = _ordered_plots()
	var n: int = order.size()
	var auto_n: int = Balance.integer("auto_water_plots." + String(_line_ready["agua"]), 0)
	var carry: float = Balance.num("carry_min." + String(_line_ready["transporte"]), 0.0)
	var plant: float = Balance.num("economy.plant_harvest_min", 3.0)
	var water: float = Balance.num("economy.water_min", 5.0)
	var rates := PackedFloat64Array()
	rates.resize(n)
	var demand := 0.0
	for i in n:
		var p: Dictionary = order[i]
		rates[i] = _step / _cycle_of(p)
		var task: float = plant + carry * _room_factor(int(p["room"]))
		if i >= auto_n:
			task += water
		demand += _step / _base_cycle(p) * task
	if String(_line_ready["energia"]) == "bicicleta":
		demand += _step * Balance.num("economy.pedal_fraction", 0.25)
	var rem := 0.0
	for j in _jobs:
		rem += float(j["total"]) - float(j["done"])
	var obra: float = minf(rem, _step * Balance.num("economy.build_labor_share", 0.7))
	var total: float = demand + obra
	var cap: float = _step * _speed()
	var f: float = 1.0 if total <= cap else cap / total
	_busy = minf(1.0, total / _step)
	_labor_f = f
	if obra > 0.0:
		_spend_labor(obra * f)
	for i in n:
		var p: Dictionary = order[i]
		p["progress"] = float(p["progress"]) + rates[i] * f
		if float(p["progress"]) >= 1.0 - 1e-9:
			_harvest(p)
	_cap_box()


func _harvest(p: Dictionary) -> void:
	var crop_id: String = String(p["crop"])
	stock += 1
	stock_value += float(Balance.crop(crop_id).get("price", 1.0))
	_stats["harvested"] = int(_stats["harvested"]) + 1
	p["progress"] = maxf(0.0, float(p["progress"]) - 1.0)
	p["first"] = false
	var inst := _inst_by_id(int(p["inst"]))
	p["crop"] = _resolve_crop(String(inst.get("item", "")), String(inst.get("crop_order", "")))
	if not _muted:
		plot_harvested.emit(int(p["id"]))


func _cap_box() -> void:
	var limit: int = int(floorf(float(box_capacity()) * Balance.num("economy.box_overflow_factor", 2.0)))
	if stock > limit:
		var before := stock
		stock = limit
		stock_value *= float(limit) / float(before)
		_stats["wasted_baskets"] = int(_stats["wasted_baskets"]) + (before - limit)
	_box_signal()


func _box_signal() -> void:
	var fill: float = box_fill()
	var q: int = int(fill * 6.0) + (1000 if fill > 1.0 else 0)
	if q != _box_q:
		_box_q = q
		if not _muted:
			box_state_changed.emit(fill, fill > 1.0)


# ---------------------------------------------------------------- obras
func _spend_labor(amount: float) -> void:
	var left := amount
	while left > 1e-9 and not _jobs.is_empty():
		var j: Dictionary = _jobs[0]
		var need: float = float(j["total"]) - float(j["done"])
		var use: float = minf(need, left)
		j["done"] = float(j["done"]) + use
		left -= use
		if float(j["done"]) >= float(j["total"]) - JOB_EPS_MIN:
			_jobs.remove_at(0)
			_complete_job(j)
		else:
			break


func _complete_job(j: Dictionary) -> void:
	match String(j["kind"]):
		"build":
			var inst := _inst_by_id(int(j["instance"]))
			if not inst.is_empty():
				inst["state"] = "ready"
				_on_ready(inst, false)
		"dig":
			rooms_n = maxi(rooms_n, int(j["room"]))
			if not _muted:
				room_dug.emit(rooms_n)
		_:
			pass


func _on_ready(inst: Dictionary, silent: bool) -> void:
	var def := _def(String(inst["item"]))
	var line: String = String(def.get("line", ""))
	if line == "plantio":
		var n: int = int(def.get("plots", 1))
		var first: bool = silent and Balance.num("start.first_cycle_min", 0.0) > 0.0
		for k in n:
			var order := String(inst.get("crop_order", ""))
			_plots.append({"id": _next_plot_id, "inst": int(inst["id"]), "index": k, "room": int(inst["room"]),
					"tier": int(def.get("tier", 0)), "gh": bool(def.get("greenhouse", false)),
					"crop": _resolve_crop(String(inst["item"]), order), "progress": 0.0, "first": first})
			_next_plot_id += 1
		_order_dirty = true
	elif bool(def.get("replaces_line", false)):
		_line_ready[line] = String(inst["item"])
	if not silent and not _muted:
		item_finished.emit(int(inst["id"]), String(inst["item"]))


# ---------------------------------------------------------------- caixa da escotilha
func _visit_slots() -> Array[float]:
	var n: int = Balance.integer("visits_per_day." + str(antenna_level), 3)
	var out: Array[float] = []
	if n <= 0:
		return out
	var interval: float = (_sleep - _wake) / float(n)
	for k in n:
		out.append(_wake + float(k) * interval)
	return out


func _visits(a: float, b: float) -> void:
	for slot in _visit_slots():
		if _crosses(a, b, slot):
			_do_visit()


func _do_visit() -> void:
	_stats["visits"] = int(_stats["visits"]) + 1
	_last_visit_abs = abs_min()
	var units: int = mini(stock, box_capacity())
	if units <= 0:
		return
	var avg: float = stock_value / float(stock)
	var gain: float = float(units) * avg
	scrap += gain
	stock -= units
	stock_value = maxf(0.0, stock_value - gain)
	if stock == 0:
		stock_value = 0.0
	_stats["scrap_earned"] = float(_stats["scrap_earned"]) + gain
	_stats["sold_baskets"] = int(_stats["sold_baskets"]) + units
	_box_signal()
	if not _muted:
		visit_happened.emit({"units": units, "scrap": int(roundf(gain)), "box_after": float(stock)})


# ---------------------------------------------------------------- ajuda manual (cliques do começo)
## Enquanto a antena for baixa o jogador pode ajudar: clicar numa estrutura de plantio empurra o ciclo dela
## e clicar na caixa troca a colheita por sucata agora. Cada máquina tira a necessidade; passando de
## o gotejador/calha cada clique some (o jogo já anda sozinho). Sem punição se não clicar.
func help_available() -> bool:
	return help_plots_available() or help_box_available()


## Regar com a lata é manual: o gotejador (e acima) tira esse clique.
func help_plots_available() -> bool:
	return String(_line_ready["agua"]) == "lata"


## Levar no balde é manual: a calha (e acima) tira esse clique.
func help_box_available() -> bool:
	return String(_line_ready["transporte"]) == "balde"


func _help_budget() -> float:
	var d: int = day_index()
	if d != _help_day:
		_help_day = d
		_help_used = 0.0
	return maxf(0.0, Balance.num("help.day_cap_min", 300.0) - _help_used)


func help_instance(instance_id: int) -> Dictionary:
	if not help_available():
		return {"ok": false, "reason": "off"}
	var inst: Dictionary = _inst_by_id(instance_id)
	if inst.is_empty():
		return {"ok": false, "reason": "none"}
	if String(inst.get("state", "ready")) == "building":
		return _help_build(instance_id)
	if not help_plots_available():
		return {"ok": false, "reason": "off"}
	var click: float = Balance.num("help.click_min", 4.0)
	var n: int = 0
	var gain: float = 0.0
	for p in _plots:
		if int(p["inst"]) != instance_id:
			continue
		var budget: float = _help_budget()
		if budget <= 0.0:
			return {"ok": false, "reason": "cap"}
		var use: float = minf(click, budget)
		_help_used += use
		p["progress"] = float(p["progress"]) + use / _cycle_of(p)
		gain = maxf(gain, use / _cycle_of(p))
		if float(p["progress"]) >= 1.0 - 1e-9:
			_harvest(p)
		n += 1
	if n == 0:
		return {"ok": false, "reason": "none"}
	if not _muted:
		helped.emit(instance_id)
		state_changed.emit()
	return {"ok": true, "plots": n, "gain": int(roundf(gain * 100.0))}


## Clicar numa obra ajuda a martelar: adianta `help.build_click_min` de trabalho da obra.
func _help_build(instance_id: int) -> Dictionary:
	var budget: float = _help_budget()
	if budget <= 0.0:
		return {"ok": false, "reason": "cap"}
	for j in _jobs:
		if int(j["instance"]) == instance_id and String(j["kind"]) == "build":
			var use: float = minf(Balance.num("help.build_click_min", 1.5), budget)
			use = minf(use, float(j["total"]) - float(j["done"]))
			_help_used += use
			j["done"] = float(j["done"]) + use
			if float(j["done"]) >= float(j["total"]) - JOB_EPS_MIN:
				_jobs.erase(j)
				_complete_job(j)
			if not _muted:
				helped.emit(instance_id)
				state_changed.emit()
			return {"ok": true, "plots": 0, "build": true, "gain": int(roundf(use / maxf(0.001, float(j["total"])) * 100.0))}
	return {"ok": false, "reason": "none"}


## Dá para trocar a caixa agora? "ok" | "off" | "empty" | "cooldown" (a cena confere antes de mandar ele).
func help_box_check() -> String:
	if not help_box_available():
		return "off"
	if stock <= 0:
		return "empty"
	if abs_min() - _last_visit_abs < Balance.num("help.box_cooldown_min", 10.0):
		return "cooldown"
	return "ok"


## O que a próxima troca rende: {units, scrap} (a cena mostra "[cesto]4 -> [sucata]4" no botão Vender).
func box_sale() -> Dictionary:
	var units: int = mini(stock, box_capacity())
	var avg: float = stock_value / float(stock) if stock > 0 else 0.0
	return {"units": units, "scrap": int(roundf(float(units) * avg))}


## Espera até o comprador poder trocar de novo: {left, total} em minutos de jogo (left 0 = já pode).
func help_box_wait() -> Dictionary:
	var total: float = Balance.num("help.box_cooldown_min", 10.0)
	return {"left": clampf(total - (abs_min() - _last_visit_abs), 0.0, total), "total": total}


func help_box() -> Dictionary:
	var why: String = help_box_check()
	if why != "ok":
		return {"ok": false, "reason": why}
	var before: float = scrap
	_do_visit()
	return {"ok": true, "scrap": int(roundf(scrap - before))}


# ================================================================ consultas de estado
func sucata() -> int:
	return int(floorf(scrap + 1e-6))


func antenna() -> int:
	return antenna_level


func rooms() -> int:
	return rooms_n


func abs_min() -> float:
	return start_min + t_min


func tod_hours() -> float:
	return fposmod(start_min + t_min + _acc, 1440.0) / 60.0


func day_index() -> int:
	return int(floorf((start_min + t_min) / 1440.0))


func is_awake() -> bool:
	var tod: float = fposmod(start_min + t_min + _acc, 1440.0)
	return tod >= _wake and tod < _sleep


func is_night() -> bool:
	return not is_awake()


func busy() -> float:
	return _busy


func hungry() -> bool:
	return _missed_meals > 0


func power_supply() -> int:
	return Balance.integer("power_supply." + String(_line_ready["energia"]), 0)


func power_demand() -> int:
	var d: int = Balance.integer("radio_power_demand." + str(antenna_level), 0)
	var lamps: int = rooms_n
	for j in _jobs:
		if String(j["kind"]) == "dig":
			lamps += 1
	d += lamps * Balance.integer("lamp_power_per_room", 1)
	for inst in _instances:
		d += int(_def(String(inst["item"])).get("power", 0))
	return d


func power_ok() -> bool:
	return power_supply() >= power_demand()


func box_stock() -> float:
	return float(stock)


func box_capacity() -> int:
	return Balance.integer("box_capacity." + String(_line_ready["transporte"]), 0)


func box_fill() -> float:
	var c: int = box_capacity()
	return float(stock) / float(c) if c > 0 else 0.0


func contact_made() -> bool:
	return contact_min >= 0.0


func arrived() -> bool:
	return _arrival == "done"


func arrival_pending() -> bool:
	return _arrival == "pending"


func antenna_time(level: int) -> float:
	return float(_antenna_t.get(level, -1.0))


func stats() -> Dictionary:
	var s: Dictionary = _stats.duplicate()
	s["time_min"] = t_min
	s["days"] = t_min / 1440.0
	s["antenna_t"] = _antenna_t.duplicate()
	s["scrap"] = scrap
	return s


# ================================================================ mundo (para a cena)
func instances() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for inst in _instances:
		var ratio := 1.0
		if String(inst["state"]) == "building":
			ratio = 0.0
			var shown := _jobs_shown()
			for k in _jobs.size():
				var j: Dictionary = _jobs[k]
				if int(j["instance"]) == int(inst["id"]):
					ratio = shown[k] / maxf(0.001, float(j["total"]))
		out.append({"id": int(inst["id"]), "item": String(inst["item"]), "room": int(inst["room"]),
				"col": int(inst["col"]), "cols": int(inst["cols"]), "state": String(inst["state"]),
				"build_ratio": ratio})
	return out


func fixed_objects(room: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var arr: Variant = Balance.val("rooms.fixed." + str(room), [])
	if arr is Array:
		for o in arr:
			out.append({"id": String(o["id"]), "col": int(o["col"]), "cols": int(o["cols"])})
	return out


func plots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _plots:
		var prog: float = float(p["progress"])
		out.append({"id": int(p["id"]), "instance": int(p["inst"]), "index": int(p["index"]),
				"room": int(p["room"]), "crop": String(p["crop"]), "progress": prog,
				"stage": mini(3, int(prog * 4.0)), "ready": prog >= 0.95, "greenhouse": bool(p["gh"]),
				"eta_min": _clock_eta((1.0 - prog) * _cycle_of(p) / maxf(0.05, _labor_f))})
	return out


## Converte minutos de trabalho acordado em minutos de relógio (conta as noites de sono no meio).
func _clock_eta(work_min: float) -> float:
	var awake_len: float = maxf(1.0, _sleep - _wake)
	var sleep_len: float = 1440.0 - awake_len
	var tod: float = fposmod(start_min + t_min + _acc, 1440.0)
	var asleep: bool = tod < _wake or tod >= _sleep
	var wait := 0.0
	var left_today := 0.0
	if tod < _wake:
		wait = _wake - tod
	elif tod >= _sleep:
		wait = 1440.0 - tod + _wake
	else:
		left_today = _sleep - tod
	if asleep:
		return wait + work_min + maxf(0.0, ceilf(work_min / awake_len - 1e-9) - 1.0) * sleep_len
	if work_min <= left_today:
		return work_min
	return work_min + ceilf((work_min - left_today) / awake_len - 1e-9) * sleep_len


func active_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var queued := 0.0   # trabalho que falta nas obras à frente na fila (elas andam uma de cada vez)
	var rate: float = maxf(0.05, Balance.num("economy.build_labor_share", 0.7) * maxf(0.05, _labor_f))
	var shown := _jobs_shown()
	for k in _jobs.size():
		var j: Dictionary = _jobs[k]
		var left: float = float(j["total"]) - shown[k]
		if not bool(j.get("hidden", false)):
			out.append({"instance": int(j["instance"]), "item": String(j["item"]),
					"ratio": shown[k] / maxf(0.001, float(j["total"])),
					"eta_min": _clock_eta((queued + left) / rate)})
		queued += left
	return out


## Trabalho já feito em cada obra para mostrar na tela. A Sim só gasta trabalho a cada passo de
## `time.step_min` (10 min), então a porcentagem ficava parada em 0% até o passo fechar; aqui soma-se a
## parte do passo em andamento (só acordado), na ordem da fila, e o valor bate com o real no fim do passo.
func _jobs_shown() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var rem := 0.0
	for j in _jobs:
		out.append(float(j["done"]))
		rem += float(j["total"]) - float(j["done"])
	if _jobs.is_empty() or not is_awake():
		return out
	var pend: float = minf(rem, _step * Balance.num("economy.build_labor_share", 0.7)) * _labor_f \
			* clampf(_acc / _step, 0.0, 1.0)
	for k in _jobs.size():
		var use: float = minf(pend, float(_jobs[k]["total"]) - float(_jobs[k]["done"]))
		out[k] += use
		pend -= use
		if pend <= 1e-9:
			break
	return out


func unlocked_behaviors() -> Array[String]:
	var out: Array[String] = []
	var b: Variant = Balance.val("behaviors", {})
	if b is Dictionary:
		for k in (b as Dictionary).keys():
			var need: String = String(((b as Dictionary)[k] as Dictionary).get("needs", ""))
			if need == "" or _has_ready(need):
				out.append(String(k))
	return out


func line_tiers() -> Dictionary:
	var top := 0
	for inst in _instances:
		if String(inst["state"]) != "ready":
			continue
		var d := _def(String(inst["item"]))
		if String(d.get("line", "")) == "plantio":
			top = maxi(top, int(d.get("tier", 0)))
	return {"plantio": top, "agua": String(_line_ready["agua"]), "energia": String(_line_ready["energia"]),
			"transporte": String(_line_ready["transporte"])}


func available_crops(instance_id: int) -> Array[String]:
	var inst := _inst_by_id(instance_id)
	var out: Array[String] = []
	if inst.is_empty() or String(_def(String(inst["item"])).get("line", "")) != "plantio":
		return out
	return _crops_for(String(inst["item"]))


func crop_order(instance_id: int) -> String:
	return String(_inst_by_id(instance_id).get("crop_order", ""))


## Ordem permanente de cultura da estrutura. "" = automático (a melhor liberada).
## Vale na próxima replantada de cada plot (nada se perde no meio do ciclo).
func set_instance_crop(instance_id: int, crop: String) -> void:
	var inst := _inst_by_id(instance_id)
	if inst.is_empty():
		return
	if crop != "" and not _crops_for(String(inst["item"])).has(crop):
		return
	inst["crop_order"] = crop
	if not _muted:
		state_changed.emit()


func _crops_for(item_id: String) -> Array[String]:
	var gh: bool = bool(Balance.item(item_id).get("greenhouse", false))
	var out: Array[String] = []
	for c in Balance.crop_ids():
		var cd := Balance.crop(c)
		if antenna_level >= int(cd.get("requires_antenna", 1)) and (gh or not bool(cd.get("greenhouse_only", false))):
			out.append(c)
	return out


func _resolve_crop(item_id: String, order: String) -> String:
	var av := _crops_for(item_id)
	if order != "" and av.has(order):
		return order
	var best := String(Balance.val("start.default_crop", "batata"))
	var best_v := -1.0
	for c in av:
		var cd := Balance.crop(c)
		var v: float = float(cd.get("price", 1.0)) / maxf(1.0, float(cd.get("cycle_min", 120.0)))
		if v > best_v:
			best_v = v
			best = c
	return best


# ================================================================ definições de itens
func _def(item_id: String) -> Dictionary:
	if Balance.has_item(item_id):
		return Balance.item(item_id)
	if item_id.begins_with("comodo"):
		var room: int = int(item_id.substr(6))
		var req: Dictionary = (Balance.val("rooms.dig_requires." + str(room), {}) as Dictionary).duplicate()
		req["rooms"] = room - 1
		return {"line": "escavacao", "tier": room - 2, "cost": Balance.num("rooms.dig_cost." + str(room), 0.0),
				"cols": 0, "max": 1, "requires": req, "power": Balance.integer("lamp_power_per_room", 1),
				"pra_que": ["espaco"], "dig_room": room}
	return {}


func item_cost(item_id: String) -> int:
	return int(roundf(float(_def(item_id).get("cost", 0)) * _price_scale))


func _antenna_cost(level: int) -> int:
	return int(roundf(Balance.num("antenna.cost." + str(level), 0.0) * _price_scale))


func _build_min(cost: int) -> float:
	return Balance.num("economy.build_base_min", 6.0) + float(cost) / maxf(1.0, Balance.num("economy.build_cost_divisor", 20.0))


func _inst_by_id(id: int) -> Dictionary:
	for inst in _instances:
		if int(inst["id"]) == id:
			return inst
	return {}


func _count_item(item_id: String) -> int:
	var n := 0
	for inst in _instances:
		if String(inst["item"]) == item_id:
			n += 1
	return n


func _has_ready(item_id: String) -> bool:
	for inst in _instances:
		if String(inst["item"]) == item_id and String(inst["state"]) == "ready":
			return true
	return false


func _line_cur_tier(line: String) -> int:
	var top := 0
	for inst in _instances:
		var d := _def(String(inst["item"]))
		if String(d.get("line", "")) == line and bool(d.get("replaces_line", false)):
			top = maxi(top, int(d.get("tier", 0)))
	return top


## Instância (qualquer estado) que ocupa a linha de serviço, ou {}.
func _line_instance(line: String) -> Dictionary:
	for inst in _instances:
		var d := _def(String(inst["item"]))
		if String(d.get("line", "")) == line and bool(d.get("replaces_line", false)):
			return inst
	return {}


# ================================================================ grade
func _occupied(room: int, ignore_id: int) -> PackedByteArray:
	var cols: int = Balance.room_cols(room)
	var occ := PackedByteArray()
	occ.resize(cols)
	for o in fixed_objects(room):
		for c in range(int(o["col"]), mini(cols, int(o["col"]) + int(o["cols"]))):
			occ[c] = 1
	for inst in _instances:
		if int(inst["id"]) == ignore_id or int(inst["room"]) != room or int(inst["cols"]) <= 0 or int(inst["col"]) < 0:
			continue
		for c in range(int(inst["col"]), mini(cols, int(inst["col"]) + int(inst["cols"]))):
			occ[c] = 1
	return occ


## Cada linha de serviço tem o seu cômodo (plantio na horta, água e energia na oficina...): o bloco inteiro
## tem de caber dentro de um cômodo da função certa.
func _zone_allows(item_id: String, room: int, col: int, cols_need: int) -> bool:
	var fn: String = Balance.zone_fn_of_line(String(_def(item_id).get("line", "")))
	if fn == "":
		return true
	for z: Dictionary in Balance.room_zones(room):
		if String(z["fn"]) == fn and col >= int(z["col0"]) and col + cols_need <= int(z["col0"]) + int(z["cols"]):
			return true
	return false


func _fits(item_id: String, room: int, col: int, ignore_id: int) -> bool:
	var cols_need: int = int(_def(item_id).get("cols", 0))
	if cols_need <= 0:
		return true
	var ncols: int = Balance.room_cols(room)
	if room < 1 or room > rooms_n or col < 0 or col + cols_need > ncols:
		return false
	if not _zone_allows(item_id, room, col, cols_need):
		return false
	var occ := _occupied(room, ignore_id)
	for c in range(col, col + cols_need):
		if occ[c] != 0:
			return false
	return true


func _replace_ignore(item_id: String) -> int:
	var d := _def(item_id)
	if bool(d.get("replaces_line", false)):
		var old := _line_instance(String(d.get("line", "")))
		if not old.is_empty():
			return int(old["id"])
	return -1


func can_place(item_id: String, room: int, col: int) -> bool:
	if not Balance.has_item(item_id):
		return false
	return _fits(item_id, room, col, _replace_ignore(item_id))


func placement_hints(item_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := _def(item_id)
	if d.is_empty():
		return out
	var cols_need: int = int(d.get("cols", 0))
	if cols_need <= 0:
		out.append({"room": 0, "col": -1})
		return out
	var ignore := _replace_ignore(item_id)
	var seen := {}
	if ignore >= 0:  # posições que cobrem a instância antiga vêm primeiro
		var old := _inst_by_id(ignore)
		var oroom: int = int(old["room"])
		var oncols: int = Balance.room_cols(oroom)
		for c in range(maxi(0, int(old["col"]) - cols_need + 1), mini(oncols - cols_need, int(old["col"]) + int(old["cols"]) - 1) + 1):
			if _fits(item_id, oroom, c, ignore):
				out.append({"room": oroom, "col": c})
				seen[oroom * 100 + c] = true
	for r in range(1, rooms_n + 1):
		for c in range(0, Balance.room_cols(r) - cols_need + 1):
			if not seen.has(r * 100 + c) and _fits(item_id, r, c, ignore):
				out.append({"room": r, "col": c})
	return out


# ================================================================ avaliação de compra
## Resultado: {owned, maxed, keys[], args[], cost_short, space}. `keys` = requisitos estruturais faltantes.
func _eval(item_id: String) -> Dictionary:
	var d := _def(item_id)
	var keys: Array[String] = []
	var args: Array[Dictionary] = []
	var res := {"owned": false, "maxed": false, "keys": keys, "args": args, "cost_short": false, "space": true, "cost": 0}
	if d.is_empty():
		keys.append("missing.item")
		args.append({"item": item_id})
		return res
	var line: String = String(d.get("line", ""))
	var cost: int = item_cost(item_id)
	res["cost"] = cost
	# ferramentas de partida (lata, balde): sempre "já tem"
	if bool(d.get("start_tool", false)):
		res["owned"] = true
		keys.append("missing.max")
		args.append({})
		return res
	# máximo / já possui
	if d.has("max") and _count_item(item_id) >= int(d["max"]):
		if int(d["max"]) == 1:
			res["owned"] = true
		else:
			res["maxed"] = true
		keys.append("missing.max")
		args.append({})
		return res
	if line == "escavacao":
		var room: int = int(d["dig_room"])
		if rooms_n >= room:
			res["owned"] = true
			keys.append("missing.max")
			args.append({})
			return res
		for j in _jobs:
			if String(j["kind"]) == "dig":
				keys.append("missing.item")
				args.append({"item": "comodo" + str(int(j["room"]))})
				return res
	elif bool(d.get("replaces_line", false)):
		var tier: int = int(d.get("tier", 0))
		var cur: int = _line_cur_tier(line)
		if tier <= cur:
			res["owned"] = true
			keys.append("missing.max")
			args.append({})
			return res
		if tier > cur + 1:
			keys.append("missing.item")
			args.append({"item": Balance.line_items(line)[cur + 1]})
		else:
			var li := _line_instance(line)
			if not li.is_empty() and String(li["state"]) == "building":
				keys.append("missing.item")
				args.append({"item": String(li["item"])})
	var req: Dictionary = d.get("requires", {}) as Dictionary
	if req.has("antenna") and antenna_level < int(req["antenna"]):
		keys.append("missing.antenna")
		args.append({"n": int(req["antenna"])})
	if req.has("rooms") and rooms_n < int(req["rooms"]):
		keys.append("missing.rooms")
		args.append({"n": int(req["rooms"])})
	if req.has("supply_min") and power_supply() < int(req["supply_min"]):
		keys.append("missing.supply")
		args.append({"n": int(req["supply_min"])})
	if req.has("items"):
		for it in req["items"]:
			if not _has_ready(String(it)):
				keys.append("missing.item")
				args.append({"item": String(it)})
	var need: int = int(d.get("power", 0))
	if need > 0 and power_supply() < power_demand() + need:
		keys.append("missing.supply")
		args.append({"n": power_demand() + need})
	if scrap + 1e-6 < float(cost):
		res["cost_short"] = true
	if int(d.get("cols", 0)) > 0 and line != "escavacao":
		res["space"] = not placement_hints(item_id).is_empty()
	return res


func _compose_missing(ev: Dictionary, item_id: String) -> Dictionary:
	var keys: Array[String] = (ev["keys"] as Array[String]).duplicate()
	var args: Array[Dictionary] = (ev["args"] as Array[Dictionary]).duplicate()
	if bool(ev["cost_short"]):
		keys.append("missing.cost")
		args.append({"n": int(ev["cost"])})
	if not bool(ev["space"]):
		keys.append("missing.free_cols")
		args.append({"n": int(_def(item_id).get("cols", 1))})
	return {"keys": keys, "args": args}


func catalog(filter: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if filter != "escavacao":
		for id in Balance.item_ids():
			var line: String = String(Balance.item(id).get("line", ""))
			if filter == "" or filter == line:
				out.append(_catalog_entry(id))
	if filter == "" or filter == "escavacao":
		for r in range(2, Balance.integer("rooms.count_max", 3) + 1):
			out.append(_catalog_entry("comodo" + str(r)))
	return out


func _catalog_entry(id: String) -> Dictionary:
	var d := _def(id)
	var ev := _eval(id)
	var m := _compose_missing(ev, id)
	var status := "available"
	if bool(ev["owned"]):
		status = "owned"
	elif bool(ev["maxed"]):
		status = "maxed"
	elif (ev["keys"] as Array).size() > 0 or not bool(ev["space"]):
		status = "locked"
	elif bool(ev["cost_short"]):
		status = "unaffordable"
	if status == "owned" or status == "maxed":
		m = {"keys": [] as Array[String], "args": [] as Array[Dictionary]}
	return {"item": id, "name_key": "item." + id + ".name", "desc_key": "item." + id + ".desc",
			"cost": int(ev["cost"]), "cols": int(d.get("cols", 0)), "line": String(d.get("line", "")),
			"tier": int(d.get("tier", 0)), "status": status, "missing": m["keys"], "missing_args": m["args"],
			"pra_que": _str_array(d.get("pra_que", [])), "post_contact": bool(d.get("post_contact", false)),
			"pinned": _pinned == id}


func _str_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for x in v:
			out.append(String(x))
	return out


## `room`=0 / `col`=-1: "em qualquer lugar" (basta existir uma posição válida).
func can_buy(item_id: String, room: int = 0, col: int = -1) -> Dictionary:
	var ev := _eval(item_id)
	var m := _compose_missing(ev, item_id)
	var keys: Array[String] = m["keys"]
	var args: Array[Dictionary] = m["args"]
	var d := _def(item_id)
	if (ev["keys"] as Array).is_empty() and bool(ev["space"]) and col >= 0 and int(d.get("cols", 0)) > 0 \
			and String(d.get("line", "")) != "escavacao" and not can_place(item_id, room, col):
		keys.append("missing.free_cols")
		args.append({"n": int(d.get("cols", 1))})
	return {"ok": keys.is_empty() and not bool(ev["owned"]) and not bool(ev["maxed"]), "missing": keys, "missing_args": args}


## Se `col` < 0 e o item ocupa colunas, usa a primeira posição sugerida.
func buy(item_id: String, room: int, col: int) -> Dictionary:
	var d := _def(item_id)
	if String(d.get("line", "")) == "escavacao":
		return dig_room()
	var chk := can_buy(item_id, room, col)
	if not bool(chk["ok"]):
		var mk: Array = chk["missing"]
		return {"ok": false, "instance_id": -1, "reason": String(mk[0]) if mk.size() > 0 else "invalid"}
	var cols_need: int = int(d.get("cols", 0))
	if cols_need > 0 and col < 0:
		var h := placement_hints(item_id)
		room = int(h[0]["room"])
		col = int(h[0]["col"])
	var cost: int = item_cost(item_id)
	scrap -= float(cost)
	_stats["scrap_spent"] = float(_stats["scrap_spent"]) + float(cost)
	_stats["bought"] = int(_stats["bought"]) + 1
	if bool(d.get("replaces_line", false)):
		var old := _line_instance(String(d.get("line", "")))
		if not old.is_empty():
			_remove_instance(int(old["id"]))
	var inst: Dictionary
	if cols_need <= 0:
		inst = _make_instance(item_id, 0, -1, "building")
		var base := String(d.get("overlay_on", ""))
		if base != "":
			for o in _instances:
				if String(o["item"]) == base:
					inst["room"] = int(o["room"])
					inst["col"] = int(o["col"])
	else:
		inst = _make_instance(item_id, room, col, "building")
	inst["paid"] = cost
	_instances.append(inst)
	_jobs.append({"id": _next_job_id, "kind": "build", "instance": int(inst["id"]), "item": item_id,
			"total": _build_min(cost), "done": 0.0, "hidden": false, "room": 0})
	_next_job_id += 1
	if not _muted:
		item_placed.emit(int(inst["id"]))
	if bool(d.get("house", false)):
		_house_bought[item_id] = true
		var oi := Balance.journey_on_item(item_id)
		if not oi.is_empty():
			_deliver_line({"id": "on_" + item_id, "speaker": "ela", "text_key": String(oi.get("text_key", "")),
					"cue": String(oi.get("cue", "static"))}, "item", 5, abs_min())
		if not _muted:
			house_item_bought.emit(item_id)
	if not _muted:
		state_changed.emit()
	return {"ok": true, "instance_id": int(inst["id"]), "reason": ""}


func dig_room() -> Dictionary:
	var room: int = rooms_n + 1
	var id := "comodo" + str(room)
	if room > Balance.integer("rooms.count_max", 3):
		return {"ok": false, "reason": "missing.max", "room": 0}
	var chk := can_buy(id)
	if not bool(chk["ok"]):
		var mk: Array = chk["missing"]
		return {"ok": false, "reason": String(mk[0]) if mk.size() > 0 else "invalid", "room": room}
	var cost: int = item_cost(id)
	scrap -= float(cost)
	_stats["scrap_spent"] = float(_stats["scrap_spent"]) + float(cost)
	_stats["bought"] = int(_stats["bought"]) + 1
	_jobs.append({"id": _next_job_id, "kind": "dig", "instance": -room, "item": id,
			"total": _build_min(cost), "done": 0.0, "hidden": false, "room": room})
	_next_job_id += 1
	if not _muted:
		state_changed.emit()
	return {"ok": true, "reason": "", "room": room}


func antenna_info() -> Dictionary:
	var lvl: int = antenna_level
	if lvl >= 5:
		return {"level": lvl, "next_cost": 0, "can": false, "missing": [] as Array[String],
				"missing_args": [] as Array[Dictionary], "max": true}
	var nxt: int = lvl + 1
	var keys: Array[String] = []
	var args: Array[Dictionary] = []
	var req: Dictionary = Balance.val("antenna.requires." + str(nxt), {}) as Dictionary
	var cost: int = _antenna_cost(nxt)
	var demand_new: int = power_demand() - Balance.integer("radio_power_demand." + str(lvl), 0) \
			+ Balance.integer("radio_power_demand." + str(nxt), 0)
	var need_supply: int = maxi(int(req.get("supply_min", 0)), demand_new + Balance.integer("antenna.headroom_needed", 1))
	if power_supply() < need_supply:
		keys.append("missing.supply")
		args.append({"n": need_supply})
	if rooms_n < int(req.get("rooms", 1)):
		keys.append("missing.rooms")
		args.append({"n": int(req.get("rooms", 1))})
	if scrap + 1e-6 < float(cost):
		keys.append("missing.cost")
		args.append({"n": cost})
	return {"level": lvl, "next_cost": cost, "can": keys.is_empty(), "missing": keys, "missing_args": args, "max": false}


func upgrade_antenna() -> Dictionary:
	var info := antenna_info()
	if not bool(info["can"]):
		var mk: Array = info["missing"]
		return {"ok": false, "reason": String(mk[0]) if mk.size() > 0 else "missing.max"}
	var cost: int = int(info["next_cost"])
	scrap -= float(cost)
	_stats["scrap_spent"] = float(_stats["scrap_spent"]) + float(cost)
	_stats["bought"] = int(_stats["bought"]) + 1
	antenna_level += 1
	_antenna_t[antenna_level] = t_min
	_jobs.append({"id": _next_job_id, "kind": "antenna", "instance": 0, "item": "antena",
			"total": _build_min(cost), "done": 0.0, "hidden": true, "room": 0})
	_next_job_id += 1
	if not _muted:
		antenna_changed.emit(antenna_level)
	_on_antenna_reached(antenna_level, false)
	if not _muted:
		state_changed.emit()
	return {"ok": true, "reason": ""}


func demolish(instance_id: int) -> Dictionary:
	var inst := _inst_by_id(instance_id)
	if inst.is_empty():
		return {"ok": false, "refund": 0, "reason": "not_found"}
	var d := _def(String(inst["item"]))
	if bool(d.get("replaces_line", false)):
		return {"ok": false, "refund": 0, "reason": "line_item"}
	if bool(inst.get("locked", false)):
		return {"ok": false, "refund": 0, "reason": "locked"}
	if bool(d.get("house", false)):
		return {"ok": false, "refund": 0, "reason": "house"}
	# a caneca extra depende da mesinha: não deixa a mesinha ir embora com ela comprada
	if String(inst["item"]) == "mesinha" and _count_item("segunda_caneca") > 0:
		return {"ok": false, "refund": 0, "reason": "has_overlay"}
	var refund: int = int(roundf(float(inst.get("paid", 0)) * Balance.num("economy.demolish_refund", 1.0)))
	scrap += float(refund)
	_remove_instance(instance_id)
	if not _muted:
		state_changed.emit()
	return {"ok": true, "refund": refund, "reason": ""}


func _remove_instance(id: int) -> void:
	for i in _instances.size():
		if int(_instances[i]["id"]) == id:
			_instances.remove_at(i)
			break
	var kept: Array = []
	for p in _plots:
		if int(p["inst"]) != id:
			kept.append(p)
	_plots = kept
	var kj: Array = []
	for j in _jobs:
		if int(j["instance"]) != id:
			kj.append(j)
	_jobs = kj
	_order_dirty = true
	if not _muted:
		item_removed.emit(id)


func move(instance_id: int, room: int, col: int) -> Dictionary:
	var inst := _inst_by_id(instance_id)
	if inst.is_empty():
		return {"ok": false, "reason": "not_found"}
	if int(inst["cols"]) <= 0:
		return {"ok": false, "reason": "fixed"}
	if not _fits(String(inst["item"]), room, col, instance_id):
		return {"ok": false, "reason": "missing.free_cols"}
	inst["room"] = room
	inst["col"] = col
	for p in _plots:
		if int(p["inst"]) == instance_id:
			p["room"] = room
	if not _muted:
		state_changed.emit()
	return {"ok": true, "reason": ""}


func pin_goal(item_id: String) -> void:
	_pinned = item_id
	if not _muted:
		state_changed.emit()


func pinned_goal() -> String:
	return _pinned


func goal_ready() -> bool:
	if _pinned == "":
		return false
	if _pinned == "antena" or _pinned == "antenna":
		return bool(antenna_info()["can"])
	return bool(can_buy(_pinned)["ok"])


# ================================================================ rádio, diário, jornada
## Agenda/entrega as falas de um nível (chamado ao chegar no nível; no nível 1, no início do jogo).
func _on_antenna_reached(level: int, _initial: bool) -> void:
	var now: float = abs_min()
	var day: int = int(floorf(now / 1440.0))
	var delay: float = Balance.num("journey.reaction_delay_min", 20.0)
	var late := 0
	for l in Balance.radio_for_level(level):
		var kind: String = String(l.get("kind", "program"))
		match kind:
			"arrival":
				_deliver_line(l, "arrival", level, now)
			"reaction":
				_schedule("radio", String(l["id"]), "reaction", now + delay)
			_:  # program | ambient
				var off: int = int(l.get("day_offset", 0))
				var due: float
				if l.get("hour") == null:
					due = now + float(off) * 1440.0 + 60.0
				else:
					due = float(day + off) * 1440.0 + float(l["hour"]) * 60.0
					if due <= now:
						# hora de hoje que já passou: entrega atrasada, logo depois da reação (sem duplicar)
						due = now + delay + 1.0 + float(late)
						late += 1
				_schedule("radio", String(l["id"]), "program", due)
	if level >= 5:
		contact_min = t_min
		var contact_day: int = day
		for tr in Balance.journey_travel():
			var td: Dictionary = tr
			if not td.has("id") or not td.has("text_key"):
				push_warning("Sim: viagem sem id/text_key ignorada")
				continue
			var hour: float = float(td.get("hour", 12.0)) if td.get("hour") != null else 12.0
			var due2: float = float(contact_day + int(td.get("day_offset", 1))) * 1440.0 + hour * 60.0
			_schedule("travel", String(td["id"]), "travel", maxf(due2, now + 1.0))


func _schedule(src: String, id: String, kind: String, due: float) -> void:
	var entry := {"src": src, "id": id, "kind": kind, "due": due}
	var i := _pending.size()
	while i > 0 and float(_pending[i - 1]["due"]) > due:
		i -= 1
	_pending.insert(i, entry)


func _deliver_due(abs_now: float) -> void:
	while not _pending.is_empty() and float(_pending[0]["due"]) <= abs_now + 1e-6:
		var e: Dictionary = _pending[0]
		_pending.remove_at(0)
		var line: Dictionary
		var level := 0
		if String(e["src"]) == "travel":
			for tr in Balance.journey_travel():
				if String((tr as Dictionary).get("id", "")) == String(e["id"]):
					line = {"id": String(e["id"]), "speaker": "ela", "text_key": String(tr["text_key"]),
							"cue": String(tr.get("cue", "static"))}
			level = 5
		else:
			var src_line := Balance.radio_line(String(e["id"]))
			if not src_line.is_empty():
				line = src_line
				level = int(src_line.get("level", 0))
		if line.is_empty():
			continue
		_deliver_line(line, String(e["kind"]), level, float(e["due"]))


func _deliver_line(line: Dictionary, kind: String, level: int, at_abs: float) -> void:
	var speaker: String = String(line.get("speaker", "ruido"))
	var at_min: float = at_abs - start_min
	var info := {"id": String(line.get("id", "")), "speaker": speaker, "text_key": String(line.get("text_key", "")),
			"cue": String(line.get("cue", "none")), "kind": kind, "level": level, "at_min": at_min}
	if String(info["text_key"]) == "":
		return
	_add_diary("her" if speaker == "ela" else "radio", String(info["text_key"]), {}, speaker, String(info["cue"]), at_min)
	if _away:
		_away_lines.append(String(info["text_key"]))
		_away_events.append({"at_min": at_min, "speaker": speaker})
	if not _muted:
		radio_line.emit(info)


func _add_diary(kind: String, key: String, args: Dictionary, speaker: String, cue: String, at_min: float) -> void:
	var ab: float = start_min + at_min
	_diary.append({"id": _next_diary_id, "kind": kind, "key": key, "args": args, "at_min": at_min,
			"tod": fposmod(ab, 1440.0) / 60.0, "day": int(floorf(ab / 1440.0)), "read": false,
			"while_away": _away, "speaker": speaker, "cue": cue})
	_next_diary_id += 1
	if _diary.size() > MAX_DIARY:
		for i in _diary.size():
			if bool(_diary[i]["read"]):
				_diary.remove_at(i)
				break
	if not _muted:
		diary_changed.emit()


func diary() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(_diary.size() - 1, -1, -1):
		out.append((_diary[i] as Dictionary).duplicate())
	return out


func unread_count() -> int:
	var n := 0
	for e in _diary:
		if not bool(e["read"]):
			n += 1
	return n


func mark_diary_read() -> void:
	var changed := false
	for e in _diary:
		if not bool(e["read"]):
			e["read"] = true
			changed = true
	if changed and not _muted:
		diary_changed.emit()


func house_status() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in Balance.house_items():
		out.append({"item": it, "bought": _house_bought.has(it)})
	return out


func _house_done() -> bool:
	for it in Balance.house_items():
		if not _house_bought.has(it) or not _has_ready(it):
			return false
	return true


func journey() -> Dictionary:
	var st := house_status()
	var done := 0
	for s in st:
		if bool(s["bought"]):
			done += 1
	var days := Balance.num("journey.arrival_min_days_after_contact", 7.0)
	var due := -1.0
	var left := -1.0
	if contact_min >= 0.0:
		due = contact_min + days * 1440.0
		left = maxf(0.0, (due - t_min) / 1440.0)
	return {"contact_min": contact_min, "arrival_due_min": due, "days_left": left,
			"items_done": done, "items_total": st.size()}


func arrival_line() -> Dictionary:
	return Balance.journey_arrival()


func _check_journey() -> void:
	if _arrival != "none" or contact_min < 0.0:
		return
	var days := Balance.num("journey.arrival_min_days_after_contact", 7.0)
	if t_min < contact_min + days * 1440.0 or not _house_done():
		return
	_arrival = "pending"
	var al := Balance.journey_arrival()
	if not al.is_empty() and String(al.get("text_key", "")) != "":
		_add_diary("system", String(al["text_key"]), {}, "ela", String(al.get("cue", "none")), t_min)
	if not _muted:
		arrival_started.emit()


## A cena do final chama ao terminar: vira o modo epílogo.
func finish_arrival() -> void:
	if _arrival != "pending":
		return
	_arrival = "done"
	if not _muted:
		arrival_finished.emit()
		state_changed.emit()


func _epilogue(a: float, b: float) -> void:
	var notes := Balance.epilogue_notes()
	var n: int = Balance.integer("journey.epilogue_notes_per_day", 2)
	if notes.is_empty() or n <= 0:
		return
	var len_: float = _sleep - _wake
	for k in n:
		var slot: float = _wake + (float(k) + 0.5) * len_ / float(n)
		if _crosses(a, b, slot):
			if _epi_next >= notes.size():
				_epi_next = 0
			_add_diary("note", notes[_epi_next], {}, "", "none", t_min)
			_epi_next += 1


# ================================================================ offline
## Mesmo código do online: avança `elapsed_min` (limitado a offline_cap_hours) sem sinais finos.
## Devolve {hours, visits, scrap, harvested, nights, lines, capped, shown}; o Game emite welcome_back.
func catch_up(elapsed_min: float, cap_hours: float = -1.0) -> Dictionary:
	if cap_hours < 0.0:
		cap_hours = Balance.num("time.offline_cap_hours", 72.0)
	elapsed_min = maxf(0.0, elapsed_min)
	var sim_min: float = minf(elapsed_min, cap_hours * 60.0)
	var v0: int = int(_stats["visits"])
	var s0: float = float(_stats["scrap_earned"])
	var h0: int = int(_stats["harvested"])
	var n0: int = int(_stats["nights"])
	_away = true
	_muted = true
	_away_lines = []
	_away_events = []
	advance(sim_min)
	var rest: float = elapsed_min - sim_min
	if rest > 0.0:
		skip_clock(fposmod(rest, 1440.0))
	_muted = false
	_away = false
	var summary := {"hours": int(roundf(elapsed_min / 60.0)), "visits": int(_stats["visits"]) - v0,
			"scrap": int(roundf(float(_stats["scrap_earned"]) - s0)), "harvested": int(_stats["harvested"]) - h0,
			"nights": int(_stats["nights"]) - n0, "lines": _away_lines.duplicate(),
			"capped": elapsed_min > cap_hours * 60.0, "shown": false}
	var thr: float = Balance.num("time.away_summary_min_min", 30.0)
	if elapsed_min >= thr:
		summary["shown"] = true
		_away = true  # as entradas de ausência também levam while_away
		for ev in _away_events:  # uma entrada `away` por fala perdida (as falas em si seguem no diário, com while_away)
			var tod_h: float = fposmod(start_min + float(ev["at_min"]), 1440.0) / 60.0
			var key := "diary.away.line.night" if tod_h < _wake / 60.0 else "diary.away.line"
			_add_diary("away", key, {"hour": int(floorf(tod_h)), "speaker": String(ev["speaker"])}, String(ev["speaker"]), "none", float(ev["at_min"]))
		if int(summary["nights"]) > 0:
			_add_diary("away", "diary.away.slept", {}, "", "none", t_min)
		var suffix := ""
		if int(summary["visits"]) == 1:
			suffix += "v1"
		if int(summary["nights"]) == 1:
			suffix += "n1"
		elif int(summary["nights"]) == 0:
			suffix += "n0"
		_add_diary("away", "diary.away.summary" + ("." + suffix if suffix != "" else ""), {"hours": summary["hours"],
				"visits": summary["visits"], "scrap": summary["scrap"], "nights": summary["nights"]}, "", "none", t_min)
		_away = false
	_away_lines = []
	_away_events = []
	diary_changed.emit()
	state_changed.emit()
	return summary


# ================================================================ save/load
func to_dict() -> Dictionary:
	return {"format": FORMAT_VERSION, "seed": seed_value, "rng_state": str(rng.state), "t_min": t_min,
			"start_min": start_min, "acc": _acc, "scrap": scrap, "stock": stock, "stock_value": stock_value,
			"antenna": antenna_level, "rooms": rooms_n, "layout": LAYOUT_VERSION, "instances": _instances.duplicate(true),
			"plots": _plots.duplicate(true), "jobs": _jobs.duplicate(true), "next_id": _next_id,
			"next_plot_id": _next_plot_id, "next_job_id": _next_job_id, "line_ready": _line_ready.duplicate(),
			"missed_meals": _missed_meals, "busy": _busy, "diary": _diary.duplicate(true),
			"next_diary_id": _next_diary_id, "pending": _pending.duplicate(true),
			"antenna_t": _antenna_t.duplicate(), "contact_min": contact_min, "arrival": _arrival,
			"house_bought": _house_bought.duplicate(), "epi_next": _epi_next, "pinned": _pinned,
			"stats": _stats.duplicate(true)}


func from_dict(d: Dictionary) -> bool:
	if d.is_empty() or not d.has("t_min"):
		return false
	_cache()
	_reset_state()
	seed_value = int(d.get("seed", 1))
	rng.seed = seed_value
	if d.has("rng_state"):
		rng.state = String(d["rng_state"]).to_int()
	t_min = float(d["t_min"])
	start_min = float(d.get("start_min", 0.0))
	_acc = float(d.get("acc", 0.0))
	scrap = float(d.get("scrap", 0.0))
	stock = int(d.get("stock", 0))
	stock_value = float(d.get("stock_value", 0.0))
	antenna_level = clampi(int(d.get("antenna", 1)), 1, 5)
	rooms_n = clampi(int(d.get("rooms", 1)), 1, 3)
	_instances = []
	for i in d.get("instances", []):
		var x: Dictionary = i
		_instances.append({"id": int(x["id"]), "item": String(x["item"]), "room": int(x["room"]), "col": int(x["col"]),
				"cols": int(x["cols"]), "state": String(x["state"]), "crop_order": String(x.get("crop_order", "")),
				"paid": int(x.get("paid", 0)), "locked": bool(x.get("locked", false))})
	_plots = []
	for p in d.get("plots", []):
		var y: Dictionary = p
		_plots.append({"id": int(y["id"]), "inst": int(y["inst"]), "index": int(y["index"]), "room": int(y["room"]),
				"tier": int(y["tier"]), "gh": bool(y["gh"]), "crop": String(y["crop"]),
				"progress": float(y["progress"]), "first": bool(y.get("first", false))})
	_jobs = []
	for j in d.get("jobs", []):
		var z: Dictionary = j
		_jobs.append({"id": int(z["id"]), "kind": String(z["kind"]), "instance": int(z["instance"]),
				"item": String(z["item"]), "total": float(z["total"]), "done": float(z["done"]),
				"hidden": bool(z.get("hidden", false)), "room": int(z.get("room", 0))})
	_next_id = int(d.get("next_id", 1))
	_next_plot_id = int(d.get("next_plot_id", 1))
	_next_job_id = int(d.get("next_job_id", 1))
	var lr: Dictionary = d.get("line_ready", {}) as Dictionary
	for k in lr.keys():
		_line_ready[String(k)] = String(lr[k])
	_missed_meals = int(d.get("missed_meals", 0))
	_busy = float(d.get("busy", 0.0))
	_diary = []
	for e in d.get("diary", []):
		var q: Dictionary = e
		_diary.append({"id": int(q["id"]), "kind": String(q["kind"]), "key": String(q["key"]),
				"args": (q.get("args", {}) as Dictionary).duplicate(), "at_min": float(q["at_min"]),
				"tod": float(q["tod"]), "day": int(q["day"]), "read": bool(q["read"]),
				"while_away": bool(q.get("while_away", false)), "speaker": String(q.get("speaker", "")),
				"cue": String(q.get("cue", "none"))})
	_next_diary_id = int(d.get("next_diary_id", 1))
	_pending = []
	for e in d.get("pending", []):
		var w: Dictionary = e
		_pending.append({"src": String(w["src"]), "id": String(w["id"]), "kind": String(w["kind"]), "due": float(w["due"])})
	_antenna_t = {}
	var at: Dictionary = d.get("antenna_t", {}) as Dictionary
	for k in at.keys():
		_antenna_t[int(k)] = float(at[k])
	contact_min = float(d.get("contact_min", -1.0))
	_arrival = String(d.get("arrival", "none"))
	_house_bought = {}
	for k in (d.get("house_bought", {}) as Dictionary).keys():
		_house_bought[String(k)] = true
	_epi_next = int(d.get("epi_next", 0))
	_pinned = String(d.get("pinned", ""))
	var st: Dictionary = d.get("stats", {}) as Dictionary
	for k in st.keys():
		if k == "antenna_t":
			continue
		_stats[String(k)] = st[k]
	for k in ["visits", "harvested", "sold_baskets", "wasted_baskets", "eaten", "nights", "bought"]:
		_stats[k] = int(_stats.get(k, 0))
	_stats["scrap_earned"] = float(_stats.get("scrap_earned", 0.0))
	_stats["scrap_spent"] = float(_stats.get("scrap_spent", 0.0))
	if int(d.get("layout", 1)) < LAYOUT_VERSION:
		_migrate_layout()
	_order_dirty = true
	_box_q = -1
	_box_signal()
	return true


## Save de antes dos cômodos (cada linha no seu): reorganiza o que tem coluna, as peças maiores primeiro,
## no primeiro lugar que a regra de cômodos aceita (quem não couber em lugar nenhum fica onde estava).
func _migrate_layout() -> void:
	var items: Array = []
	for inst in _instances:
		if int(inst["cols"]) > 0:
			items.append(inst)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["cols"]) > int(b["cols"]) or (int(a["cols"]) == int(b["cols"]) and int(a["id"]) < int(b["id"])))
	var old: Dictionary = {}
	for inst in items:
		old[int(inst["id"])] = [int(inst["room"]), int(inst["col"])]
		inst["col"] = -1000   # sai da grade enquanto se reorganiza
	for inst in items:
		var placed := false
		for r in range(1, rooms_n + 1):
			for c in range(0, Balance.room_cols(r) - int(inst["cols"]) + 1):
				if _fits(String(inst["item"]), r, c, int(inst["id"])):
					inst["room"] = r
					inst["col"] = c
					placed = true
					break
			if placed:
				break
		if not placed:
			inst["room"] = int((old[int(inst["id"])] as Array)[0])
			inst["col"] = int((old[int(inst["id"])] as Array)[1])
		for p in _plots:
			if int(p["inst"]) == int(inst["id"]):
				p["room"] = int(inst["room"])
