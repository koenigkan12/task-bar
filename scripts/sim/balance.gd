class_name Balance
extends RefCounted
## Dados de balanceamento e de conteúdo (balance.json, radio.json, journey.json).
## Tudo estático: carregue uma vez com Balance.load_all(). Nunca espalhar números no código.

static var loaded: bool = false
static var data: Dictionary = {}
static var radio_lines: Array = []          # falas de data/radio.json (ordem do arquivo)
static var journey_data: Dictionary = {}    # data/journey.json
static var _radio_by_id: Dictionary = {}
static var _item_ids: Array[String] = []
static var _zones: Dictionary = {}          # room -> zonas (cache de room_zones)
static var _zone_fn: Dictionary = {}        # linha -> função do cômodo (cache)


static func load_all(path_prefix: String = "res://data/") -> bool:
	data = {}
	radio_lines = []
	journey_data = {}
	_radio_by_id = {}
	_item_ids = []
	_zones = {}
	_zone_fn = {}
	var ok := true
	var b: Variant = _read_json(path_prefix + "balance.json")
	if b is Dictionary:
		data = b
	else:
		push_error("Balance: balance.json ausente ou inválido em " + path_prefix)
		ok = false
	for k in (data.get("items", {}) as Dictionary).keys():
		_item_ids.append(String(k))
	# rádio: arquivo/campo ausente nunca quebra (só aviso)
	var r: Variant = _read_json(path_prefix + "radio.json")
	if r is Dictionary and (r as Dictionary).get("lines") is Array:
		for l in (r as Dictionary)["lines"]:
			if l is Dictionary and (l as Dictionary).has("id") and (l as Dictionary).has("text_key"):
				radio_lines.append(l)
				_radio_by_id[String((l as Dictionary)["id"])] = l
			else:
				push_warning("Balance: fala de rádio inválida ignorada")
	else:
		push_warning("Balance: radio.json ausente ou sem 'lines'; rádio vazio")
	var j: Variant = _read_json(path_prefix + "journey.json")
	if j is Dictionary:
		journey_data = j
	else:
		push_warning("Balance: journey.json ausente; jornada sem falas")
	loaded = ok
	return ok


static func ensure_loaded() -> void:
	if not loaded:
		load_all()


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var js := JSON.new()
	if js.parse(txt) != OK:
		push_error("Balance: JSON inválido em %s (linha %d): %s" % [path, js.get_error_line(), js.get_error_message()])
		return null
	return js.data


## Valor por caminho "secao.chave.sub" (chaves de dicionário; números como texto também servem).
static func val(path: String, default: Variant = null) -> Variant:
	var cur: Variant = data
	for part in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = (cur as Dictionary)[part]
		else:
			return default
	return cur


static func num(path: String, default: float = 0.0) -> float:
	var v: Variant = val(path, default)
	if v is float or v is int:
		return float(v)
	return default


static func integer(path: String, default: int = 0) -> int:
	return int(num(path, float(default)))


static func item_ids() -> Array[String]:
	return _item_ids


static func has_item(id: String) -> bool:
	return (data.get("items", {}) as Dictionary).has(id)


static func item(id: String) -> Dictionary:
	return (data.get("items", {}) as Dictionary).get(id, {}) as Dictionary


static func crop(id: String) -> Dictionary:
	return (data.get("crops", {}) as Dictionary).get(id, {}) as Dictionary


static func crop_ids() -> Array[String]:
	var out: Array[String] = []
	for k in (data.get("crops", {}) as Dictionary).keys():
		out.append(String(k))
	return out


## Itens de uma linha de serviço, em ordem de nível (índice = tier).
static func line_items(line: String) -> Array[String]:
	var out: Array[String] = []
	var arr: Variant = (data.get("lines", {}) as Dictionary).get(line, [])
	if arr is Array:
		for x in arr:
			out.append(String(x))
	return out


## Cômodos (zonas) de uma sala, da esquerda para a direita: [{id, fn, col0, cols}]. As colunas da sala
## são contadas de 0 a room_cols(room)-1 por cima de todas as zonas (o desenho põe uma parede entre elas).
static func room_zones(room: int) -> Array[Dictionary]:
	if _zones.has(room):
		return _zones[room]
	var out: Array[Dictionary] = []
	var arr: Variant = val("rooms.layout." + str(room), [])
	var c0: int = 0
	if arr is Array:
		for z in arr:
			var zd := z as Dictionary
			out.append({"id": String(zd.get("id", "")), "fn": String(zd.get("fn", "")), "col0": c0, "cols": int(zd.get("cols", 0))})
			c0 += int(zd.get("cols", 0))
	_zones[room] = out
	return out


## Colunas da sala (soma das zonas).
static func room_cols(room: int) -> int:
	var n: int = 0
	for z: Dictionary in room_zones(room):
		n += int(z["cols"])
	return n


## Função do cômodo onde os itens de uma linha de serviço podem ficar ("" = qualquer lugar).
static func zone_fn_of_line(line: String) -> String:
	if not _zone_fn.has(line):
		_zone_fn[line] = String(val("rooms.zone_fn." + line, ""))
	return _zone_fn[line]


static func house_items() -> Array[String]:
	var out: Array[String] = []
	var arr: Variant = val("journey.house_items", [])
	if arr is Array:
		for x in arr:
			out.append(String(x))
	return out


static func radio_line(id: String) -> Dictionary:
	return _radio_by_id.get(id, {}) as Dictionary


## Falas de rádio de um nível (ordem do arquivo).
static func radio_for_level(level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in radio_lines:
		if int((l as Dictionary).get("level", 0)) == level:
			out.append(l as Dictionary)
	return out


static func journey_travel() -> Array:
	var t: Variant = journey_data.get("travel", [])
	return t if t is Array else []


static func journey_on_item(item_id: String) -> Dictionary:
	var o: Variant = journey_data.get("on_item", {})
	if o is Dictionary and (o as Dictionary).get(item_id) is Dictionary:
		return (o as Dictionary)[item_id] as Dictionary
	return {}


static func journey_arrival() -> Dictionary:
	var a: Variant = journey_data.get("arrival", {})
	return a if a is Dictionary else {}


static func epilogue_notes() -> Array[String]:
	var out: Array[String] = []
	var n: Variant = journey_data.get("epilogue_notes", [])
	if n is Array:
		for x in n:
			out.append(String(x))
	return out
