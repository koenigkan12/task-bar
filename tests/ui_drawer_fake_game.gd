extends Node
## Game falso para os testes da gaveta (só a API da seção 4.3 que a gaveta usa).
## Não é autoload: os testes criam um e passam com Drawer.bind_game().

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
signal box_state_changed(fill: float, overflow: bool)
signal welcome_back(summary: Dictionary)
signal house_item_bought(item_id: String)
signal arrival_started()
signal arrival_finished()

var in_game: bool = true
var scrap: int = 64
var level: int = 2
var n_rooms: int = 2
var contact: bool = false
var pinned: String = ""
var calls: Array = []          # registro dos comandos recebidos (para os asserts)
var _next_id: int = 10
var _inst: Array = [
	{"id": 1, "item": "vaso", "room": 1, "col": 3, "cols": 1, "state": "ready", "build_ratio": 1.0},
	{"id": 2, "item": "vaso", "room": 1, "col": 4, "cols": 1, "state": "ready", "build_ratio": 1.0},
	{"id": 3, "item": "canteiro", "room": 1, "col": 7, "cols": 2, "state": "ready", "build_ratio": 1.0},
	{"id": 4, "item": "bicicleta", "room": 1, "col": 6, "cols": 1, "state": "ready", "build_ratio": 1.0},
	{"id": 5, "item": "estante", "room": 2, "col": 2, "cols": 1, "state": "building", "build_ratio": 0.4},
]
var _crop: Dictionary = {1: "batata", 2: "feijao", 3: "batata"}
var _order: Dictionary = {}
var _diary: Array = []
var _bought_house: Dictionary = {"cama_dela": true, "cantinho": true}


func _init() -> void:
	_diary = [
		{"id": 1, "kind": "radio", "key": "radio.l1_arrival", "args": {}, "at_min": 400, "tod": 6.7, "day": 0, "read": true, "while_away": false, "speaker": "ruido", "cue": "static"},
		{"id": 2, "kind": "away", "key": "diary.away.summary", "args": {"hours": 9, "visits": 3, "scrap": 42, "nights": 1}, "at_min": 1900, "tod": 7.6, "day": 1, "read": false, "while_away": true, "speaker": "", "cue": "none"},
		{"id": 3, "kind": "radio", "key": "radio.l2_arrival", "args": {}, "at_min": 1700, "tod": 4.3, "day": 1, "read": false, "while_away": true, "speaker": "sementes", "cue": "static"},
		{"id": 4, "kind": "her", "key": "radio.l5_arrival", "args": {}, "at_min": 2300, "tod": 14.3, "day": 1, "read": false, "while_away": false, "speaker": "ela", "cue": "voice_her"},
	]


func sucata() -> int: return scrap
func antenna() -> int: return level
func rooms() -> int: return n_rooms
func tod_hours() -> float: return 14.5
func day_index() -> int: return 2
func is_awake() -> bool: return true
func is_night() -> bool: return false
func busy() -> float: return 0.62
func hungry() -> bool: return false
func power_supply() -> int: return 3
func power_demand() -> int: return 2
func power_ok() -> bool: return true
func box_stock() -> float: return 9.0
func box_capacity() -> int: return 14
func box_fill() -> float: return box_stock() / float(box_capacity())
func contact_made() -> bool: return contact
func arrived() -> bool: return false
func stats() -> Dictionary: return {"harvested": 37, "visits": 8}


func instances() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in _inst:
		out.append(d.duplicate())
	return out


func plots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pid: int = 0
	for d: Dictionary in _inst:
		if _crop.has(d["id"]):
			pid += 1
			out.append({"id": pid, "instance": d["id"], "index": 0, "room": d["room"], "crop": _crop[d["id"]], "progress": 0.5, "stage": 2, "ready": false, "greenhouse": false})
	return out


func active_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in _inst:
		if d["state"] == "building":
			out.append({"instance": d["id"], "item": d["item"], "ratio": d["build_ratio"]})
	return out


func catalog(filter: String = "") -> Array[Dictionary]:
	var rows: Array = [
		["vaso", "plantio", 6, 1, 0, "available", [], ["renda"]],
		["canteiro", "plantio", 30, 2, 1, "available", [], ["renda"]],
		["prateleira", "plantio", 110, 2, 2, "locked", [["missing.antenna", {"n": 3}]], ["renda"]],
		["gotejador", "agua", 40, 1, 1, "unaffordable", [["missing.cost", {"n": 40 - scrap}]], ["tempo"]],
		["cisterna", "agua", 150, 2, 2, "locked", [["missing.rooms", {"n": 2}]], ["tempo", "renda"]],
		["moinho", "energia", 50, 1, 1, "available", [], ["porta"]],
		["painel", "energia", 320, 0, 3, "locked", [["missing.antenna", {"n": 4}]], ["porta"]],
		["calha", "transporte", 40, 1, 1, "available", [], ["tempo", "renda"]],
		["estante", "decor", 30, 1, 1, "owned", [], ["historia"]],
		["poltrona", "decor", 40, 1, 1, "available", [], ["historia", "tempo"]],
		["cama_dela", "casa", 150, 2, 2, "locked", [["missing.item", {"item": "mesinha"}]], ["historia"]],
		["comodo3", "escavacao", 210, 0, 3, "locked", [["missing.antenna", {"n": 3}]], ["espaco"]],
	]
	var out: Array[Dictionary] = []
	for r: Array in rows:
		if filter != "" and r[1] != filter:
			continue
		var missing: Array[String] = []
		var margs: Array[Dictionary] = []
		for m: Array in r[6]:
			missing.append(m[0])
			margs.append(m[1])
		var pq: Array[String] = []
		for p: String in r[7]:
			pq.append(p)
		out.append({"item": r[0], "name_key": "item.%s.name" % r[0], "desc_key": "item.%s.desc" % r[0],
			"cost": r[2], "cols": r[3], "line": r[1], "tier": r[4], "status": r[5], "missing": missing, "missing_args": margs,
			"pra_que": pq, "post_contact": r[1] == "casa", "pinned": pinned == r[0]})
	return out


func placement_hints(item_id: String) -> Array[Dictionary]:
	calls.append(["hints", item_id])
	return [{"room": 1, "col": 5}, {"room": 2, "col": 4}, {"room": 2, "col": 9}] as Array[Dictionary]


func can_place(_item_id: String, _room: int, _col: int) -> bool: return true


func buy(item_id: String, room: int, col: int) -> Dictionary:
	calls.append(["buy", item_id, room, col])
	_next_id += 1
	_inst.append({"id": _next_id, "item": item_id, "room": room, "col": col, "cols": 1, "state": "building", "build_ratio": 0.0})
	item_placed.emit(_next_id)
	return {"ok": true, "instance_id": _next_id, "reason": ""}


func dig_room() -> Dictionary:
	calls.append(["dig"])
	return {"ok": true}


func antenna_info() -> Dictionary:
	return {"level": level, "next_cost": 110, "can": false, "missing": ["missing.supply", "missing.rooms"] as Array[String],
		"missing_args": [{"n": 5}, {"n": 2}] as Array[Dictionary], "max": level >= 5}


func upgrade_antenna() -> Dictionary:
	calls.append(["antenna"])
	return {"ok": false, "reason": "missing.cost"}


func demolish(instance_id: int) -> Dictionary:
	calls.append(["demolish", instance_id])
	if instance_id == 4:
		return {"ok": false, "refund": 0, "reason": "line_item"}
	for i in _inst.size():
		if _inst[i]["id"] == instance_id:
			_inst.remove_at(i)
			break
	item_removed.emit(instance_id)
	return {"ok": true}


func move(instance_id: int, room: int, col: int) -> Dictionary:
	calls.append(["move", instance_id, room, col])
	return {"ok": true}


func available_crops(_instance_id: int) -> Array[String]:
	return ["batata", "feijao"] as Array[String]


func set_instance_crop(instance_id: int, crop: String) -> void:
	calls.append(["crop", instance_id, crop])
	_order[instance_id] = crop
	if crop != "":
		_crop[instance_id] = crop


func crop_order(instance_id: int) -> String:
	return str(_order.get(instance_id, ""))


func pin_goal(item_id: String) -> void:
	calls.append(["pin", item_id])
	pinned = item_id


func pinned_goal() -> String: return pinned
func goal_ready() -> bool: return false


func diary() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in _diary:
		out.append(d.duplicate())
	return out


func unread_count() -> int:
	var n: int = 0
	for d: Dictionary in _diary:
		if not d["read"]:
			n += 1
	return n


func mark_diary_read() -> void:
	calls.append(["read"])
	for d: Dictionary in _diary:
		d["read"] = true
	diary_changed.emit()


func house_status() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ["cama_dela", "cantinho", "planta_dela", "cabide", "segunda_caneca", "foto_dela"]:
		out.append({"item": id, "bought": _bought_house.has(id)})
	return out


func journey() -> Dictionary:
	return {"contact_min": 9000, "arrival_due_min": 19080, "days_left": 4, "items_done": _bought_house.size(), "items_total": 6}
