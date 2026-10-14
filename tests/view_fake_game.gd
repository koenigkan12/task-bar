extends Node
## Game falso SÓ para os testes da cena (tests/view_*). Segue a API da CONTRATOS 4.3 com estado
## editável; não substitui o autoload Game.

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
signal new_game_started()
signal game_loaded()

var s: Dictionary = {
	"rooms": 1, "antenna": 1, "sucata": 0, "tod": 10.0, "day": 0, "busy": 0.5, "hungry": false,
	"power_ok": true, "box_fill": 0.0, "unread": 0, "goal_ready": false, "pinned": "",
	"arrived": false, "contact": false, "behaviors": [],
	"tiers": {"plantio": "vaso", "agua": "lata", "energia": "bicicleta", "transporte": "balde"},
}
var inst: Array[Dictionary] = []
var plot_list: Array[Dictionary] = []
var jobs: Array[Dictionary] = []
var finish_calls: int = 0
var _items: Dictionary = {}
var _next_id: int = 1
var _next_plot: int = 1


func _init() -> void:
	var bal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	_items = bal["items"]


func add(item: String, room: int, col: int, crop: String = "batata", stages: Array = [], state: String = "ready", ratio: float = 1.0) -> int:
	var id := _next_id
	_next_id += 1
	var it: Dictionary = _items.get(item, {})
	inst.append({"id": id, "item": item, "room": room, "col": col, "cols": int(it.get("cols", 1)), "state": state, "build_ratio": ratio})
	for k in int(it.get("plots", 0)):
		var st: int = stages[k] if k < stages.size() else 2
		plot_list.append({"id": _next_plot, "instance": id, "index": k, "room": room, "crop": crop,
			"progress": [0.1, 0.4, 0.7, 0.97][st], "stage": st, "ready": st == 3, "greenhouse": item == "estufa"})
		_next_plot += 1
	if state == "building":
		jobs.append({"instance": id, "item": item, "ratio": ratio})
	return id


func rooms() -> int: return s["rooms"]
func antenna() -> int: return s["antenna"]
func sucata() -> int: return s["sucata"]
func tod_hours() -> float: return s["tod"]
func day_index() -> int: return s["day"]
func is_awake() -> bool: return s["tod"] >= 6.0 and s["tod"] < 22.0
func is_night() -> bool: return not is_awake()
func busy() -> float: return s["busy"]
func hungry() -> bool: return s["hungry"]
func power_supply() -> int: return 3
func power_demand() -> int: return 2
func power_ok() -> bool: return s["power_ok"]
func box_stock() -> float: return s["box_fill"] * 14.0
func box_capacity() -> int: return 14
func box_fill() -> float: return s["box_fill"]
func contact_made() -> bool: return s["contact"]
func arrived() -> bool: return s["arrived"]
func unread_count() -> int: return s["unread"]
func goal_ready() -> bool: return s["goal_ready"]
func pinned_goal() -> String: return s["pinned"]
func instances() -> Array[Dictionary]: return inst
func plots() -> Array[Dictionary]: return plot_list
func active_jobs() -> Array[Dictionary]: return jobs
func unlocked_behaviors() -> Array[String]:
	var out: Array[String] = []
	out.assign(s["behaviors"])
	return out
func line_tiers() -> Dictionary: return s["tiers"]
func fixed_objects(room: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if room == 1:
		out.assign([{"id": "ladder", "col": 0, "cols": 1}, {"id": "hatch_box", "col": 1, "cols": 1},
			{"id": "radio_table", "col": 2, "cols": 1}, {"id": "bed", "col": 27, "cols": 2}])
	return out
func catalog(_f: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: String in _items:
		out.append({"item": k, "line": _items[k].get("line", "")})
	return out
func finish_arrival() -> void:
	finish_calls += 1
	s["arrived"] = true
	arrival_finished.emit()
