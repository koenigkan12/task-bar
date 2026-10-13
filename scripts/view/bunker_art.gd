class_name BunkerArt
extends RefCounted
## Junta todos os assets/art/manifest_*.json (CONTRATOS 7) e serve texturas e quadros.
## Um nome sem PNG importado (ex.: man_* antes da arte chegar) responde has() == false.

const ART_DIR := "res://assets/art/"

static var _info: Dictionary = {}
static var _tex: Dictionary = {}
static var _loaded: bool = false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var d := DirAccess.open(ART_DIR)
	if d == null:
		push_warning("BunkerArt: pasta de arte não encontrada")
		return
	var files: Array[String] = []
	for f in d.get_files():
		if f.begins_with("manifest_") and f.ends_with(".json"):
			files.append(f)
	files.sort()
	for f in files:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ART_DIR + f))
		if data is Dictionary:
			for k: String in data:
				_info[k] = data[k]


## Relê os manifestos (útil depois de uma arte nova ser importada).
static func reload() -> void:
	_loaded = false
	_info.clear()
	_tex.clear()
	ensure()


static func has(n: String) -> bool:
	ensure()
	return _info.has(n) and texture(n) != null


static func info(n: String) -> Dictionary:
	ensure()
	return _info.get(n, {})


static func texture(n: String) -> Texture2D:
	ensure()
	if _tex.has(n):
		return _tex[n]
	var i: Dictionary = _info.get(n, {})
	var t: Texture2D = null
	if i.has("file"):
		var path: String = ART_DIR + String(i["file"])
		if ResourceLoader.exists(path):
			t = load(path) as Texture2D
	_tex[n] = t
	return t


static func frame_size(n: String) -> Vector2:
	var i := info(n)
	return Vector2(float(i.get("frame_w", 0)), float(i.get("frame_h", 0)))


static func frames(n: String) -> int:
	return maxi(1, int(info(n).get("frames", 1)))


static func fps(n: String) -> float:
	return float(info(n).get("fps", 0))


static func anchor(n: String) -> Vector2:
	var a: Array = info(n).get("anchor", [0, 0])
	return Vector2(float(a[0]), float(a[1]))


static func region(n: String, frame: int) -> Rect2:
	var s := frame_size(n)
	return Rect2(Vector2(s.x * clampi(frame, 0, frames(n) - 1), 0), s)


## Posições (x, y) dos pés das plantas, relativas ao canto sup. esq. do sprite.
static func plots(n: String) -> Array:
	return info(n).get("plots", [])
