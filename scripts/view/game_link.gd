class_name GameLink
extends RefCounted
## Acesso tolerante ao Game (CONTRATOS 4.3). Enquanto o Game for stub, cada consulta devolve um
## padrão tirado de data/balance.json (estado inicial), para a cena abrir e ser testável.

const BALANCE_PATH := "res://data/balance.json"

var game: Object
var _bal: Dictionary = {}


func _init(g: Object = null) -> void:
	game = g
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BALANCE_PATH))
	_bal = data if data is Dictionary else {}


func has(m: String) -> bool:
	return game != null and is_instance_valid(game) and game.has_method(m)


func q(m: String, default: Variant = null, args: Array = []) -> Variant:
	if has(m):
		return game.callv(m, args)
	return default


## Liga um sinal do Game se ele existir.
func connect_signal(sig: String, c: Callable) -> void:
	if game != null and game.has_signal(sig) and not game.is_connected(sig, c):
		game.connect(sig, c)


func balance() -> Dictionary:
	return _bal


# --- consultas tipadas ---

func rooms() -> int:
	return clampi(int(q("rooms", 1)), 1, BunkerGeo.MAX_ROOMS)


func antenna() -> int:
	return clampi(int(q("antenna", 1)), 1, 5)


func sucata() -> int:
	return int(q("sucata", 0))


func tod_hours() -> float:
	return float(q("tod_hours", 10.0))


func is_awake() -> bool:
	return bool(q("is_awake", true))


func is_night() -> bool:
	return bool(q("is_night", false))


func busy() -> float:
	return clampf(float(q("busy", 0.5)), 0.0, 1.0)


func hungry() -> bool:
	return bool(q("hungry", false))


func power_ok() -> bool:
	return bool(q("power_ok", true))


func box_fill() -> float:
	return float(q("box_fill", 0.0))


func unread_count() -> int:
	return int(q("unread_count", 0))


func goal_ready() -> bool:
	return bool(q("goal_ready", false))


func pinned_goal() -> String:
	return String(q("pinned_goal", ""))


func contact_made() -> bool:
	return bool(q("contact_made", false))


func arrived() -> bool:
	return bool(q("arrived", false))


func day_index() -> int:
	return int(q("day_index", 0))


func instances() -> Array:
	if has("instances"):
		return game.call("instances")
	var out: Array = []
	var items: Dictionary = _bal.get("items", {})
	var start: Dictionary = _bal.get("start", {})
	var i := 1
	for o: Dictionary in start.get("owned", []):
		var it: Dictionary = items.get(o["item"], {})
		out.append({"id": i, "item": o["item"], "room": int(o["room"]), "col": int(o["col"]),
			"cols": int(it.get("cols", 1)), "state": "ready", "build_ratio": 1.0})
		i += 1
	return out


func fixed_objects(room: int) -> Array:
	if has("fixed_objects"):
		return game.call("fixed_objects", room)
	var fixed: Dictionary = _bal.get("rooms", {}).get("fixed", {})
	return fixed.get(str(room), [])


func plots() -> Array:
	if has("plots"):
		return game.call("plots")
	var out: Array = []
	var crop := String(_bal.get("start", {}).get("default_crop", "batata"))
	var pid := 1
	for inst: Dictionary in instances():
		var n := int(_bal.get("items", {}).get(inst["item"], {}).get("plots", 0))
		for k in n:
			out.append({"id": pid, "instance": inst["id"], "index": k, "room": inst["room"], "crop": crop,
				"progress": 0.3, "stage": 1, "ready": false, "greenhouse": false})
			pid += 1
	return out


func active_jobs() -> Array:
	return q("active_jobs", [])


func unlocked_behaviors() -> Array:
	return q("unlocked_behaviors", [])


func line_tiers() -> Dictionary:
	return q("line_tiers", {"plantio": "vaso", "agua": "lata", "energia": "bicicleta", "transporte": "balde"})


func catalog() -> Array:
	return q("catalog", [], [""])


func finish_arrival() -> void:
	if has("finish_arrival"):
		game.call("finish_arrival")
