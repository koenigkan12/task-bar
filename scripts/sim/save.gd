class_name Save
extends RefCounted
## Save em JSON, atômico: escreve .tmp, move o antigo para .bak, renomeia o .tmp, apaga o .bak.
## Se o principal estiver ausente/corrompido, a leitura tenta o .bak.

const VERSION := 1
const DEFAULT_PATH := "user://save.json"


static func exists(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


static func write(sim_dict: Dictionary, saved_unix: float, path: String = DEFAULT_PATH) -> bool:
	var doc := {"format": VERSION, "saved_unix": saved_unix, "sim": sim_dict}
	var txt := JSON.stringify(doc, "", true, true)
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Save: não consegui abrir " + tmp)
		return false
	f.store_string(txt)
	f.flush()
	f.close()
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		if DirAccess.rename_absolute(path, bak) != OK:
			push_warning("Save: não consegui mover o save antigo")
			return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_warning("Save: não consegui renomear o save novo")
		return false
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	return true


## {ok, sim: Dictionary, saved_unix: float}
static func read(path: String = DEFAULT_PATH) -> Dictionary:
	for p in [path, path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var js := JSON.new()  # parse() não imprime erro de engine em arquivo corrompido
		if js.parse(txt) != OK:
			continue
		var parsed: Variant = js.data
		if parsed is Dictionary:
			var doc := migrate(parsed as Dictionary)
			if doc.has("sim") and doc["sim"] is Dictionary:
				return {"ok": true, "sim": doc["sim"], "saved_unix": float(doc.get("saved_unix", 0.0))}
	return {"ok": false, "sim": {}, "saved_unix": 0.0}


## Migração trivial por versão: hoje só existe o formato 1 (aceita save sem "format" como v1).
static func migrate(doc: Dictionary) -> Dictionary:
	var v: int = int(doc.get("format", 1))
	if v > VERSION:
		push_warning("Save: formato %d mais novo que o suportado (%d); tentando ler assim mesmo" % [v, VERSION])
	# if v < 2: ... (futuras migrações entram aqui, uma por versão)
	doc["format"] = VERSION
	return doc


static func delete(path: String = DEFAULT_PATH) -> void:
	for p in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
