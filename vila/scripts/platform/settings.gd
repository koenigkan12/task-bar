extends Node
## Autoload `Settings`: opções do jogador em user://settings.json.
## Escrita com atraso (debounce 0,5 s) e atômica (tmp + rename). Tolera arquivo corrompido.
## Contrato: docs/CONTRATOS.md, seção 4.1.

signal changed(key: String)

const DEBOUNCE_S: float = 0.5
const AUDIO_MODES: Array[String] = ["silent", "ambient", "full"]
const ENERGY_MODES: Array[String] = ["auto", "low", "normal"]

## Padrões de todas as chaves conhecidas (outros módulos podem guardar chaves extras).
const DEFAULTS: Dictionary = {
	"locale": "auto",
	"audio_mode": "ambient",
	"master_volume": 0.8,
	"ui_scale": "auto",
	"always_on_top": true,
	"energy_mode": "auto",
	"window_pos": {},
	"anchor": "bottom_left",
	"text_size": 1.0,
	"reduce_flicker": false,
	"first_run_done": false,
	"tray_enabled": true,
	"autostart_hint_seen": false,
	"sound_unlocked": false,
}

## Caminho do arquivo (variável para os testes usarem outro).
var path: String = "user://settings.json"

var _data: Dictionary = {}
var _loaded: bool = false
var _dirty: bool = false
var _wait_left: float = 0.0
## Quantas escritas reais já aconteceram (útil nos testes de debounce).
var write_count: int = 0


func _ready() -> void:
	_ensure_loaded()
	set_process(_dirty)


func _process(delta: float) -> void:
	if not _dirty:
		set_process(false)
		return
	_wait_left -= delta
	if _wait_left <= 0.0:
		flush()


func _notification(what: int) -> void:
	# Fechar a janela ou sair: não perder a última mudança.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _loaded and _dirty:
			flush()


func _exit_tree() -> void:
	if _loaded and _dirty:
		flush()


## Valor da chave; se não existir, o padrão do contrato; se não houver, `default`.
func get_value(key: String, default: Variant = null) -> Variant:
	_ensure_loaded()
	if _data.has(key):
		return _copy(_data[key])
	if DEFAULTS.has(key):
		return _copy(DEFAULTS[key])
	return default


func has_value(key: String) -> bool:
	_ensure_loaded()
	return _data.has(key)


func set_value(key: String, value: Variant) -> void:
	_ensure_loaded()
	var v: Variant = _copy(value)
	if DEFAULTS.has(key):
		v = _sanitize(key, v)
	if _same(get_value(key), v):
		return  # nada mudou: sem sinal e sem gravar
	_data[key] = v
	_mark_dirty()
	changed.emit(key)


## Recarrega do disco (opcionalmente de outro caminho; usado nos testes).
func reload(new_path: String = "") -> void:
	if new_path != "":
		path = new_path
	_loaded = false
	_dirty = false
	_ensure_loaded()


## Volta tudo ao padrão (e grava).
func reset_all() -> void:
	_ensure_loaded()
	var keys: Array = _data.keys()
	_data = {}
	_mark_dirty()
	for k in keys:
		changed.emit(String(k))


## Grava agora (sem esperar o debounce). Devolve true se gravou.
func flush() -> bool:
	_ensure_loaded()
	_dirty = false
	_wait_left = 0.0
	return _write_atomic()


# ---------------------------------------------------------------------------
# Carregar

func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_data = {}
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_quarantine("não abriu (erro %d)" % FileAccess.get_open_error())
		return
	var text: String = f.get_as_text()
	f.close()
	var json: JSON = JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		_quarantine("JSON inválido")
		return
	var raw: Dictionary = json.data
	for k in raw.keys():
		var key: String = String(k)
		var v: Variant = raw[k]
		if DEFAULTS.has(key):
			v = _sanitize(key, v)
		_data[key] = v


## Arquivo corrompido: guarda como .bad e recomeça do zero.
func _quarantine(reason: String) -> void:
	var bad: String = path + ".bad"
	if FileAccess.file_exists(bad):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bad))
	var err: int = DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(bad))
	push_warning("Settings: %s; arquivo movido para .bad (rename=%d)" % [reason, err])
	_data = {}


# ---------------------------------------------------------------------------
# Gravar

func _mark_dirty() -> void:
	_dirty = true
	_wait_left = DEBOUNCE_S
	if is_inside_tree():
		set_process(true)


func _write_atomic() -> bool:
	var text: String = JSON.stringify(_data, "\t", true)
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	f.close()
	var abs_tmp: String = ProjectSettings.globalize_path(tmp)
	var abs_final: String = ProjectSettings.globalize_path(path)
	var err: int = DirAccess.rename_absolute(abs_tmp, abs_final)
	if err != OK:
		# Windows antigo não troca por cima de arquivo existente: apaga e tenta de novo.
		DirAccess.remove_absolute(abs_final)
		err = DirAccess.rename_absolute(abs_tmp, abs_final)
	if err != OK:
		# Último recurso: grava direto.
		var f2: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f2 == null:
			return false
		f2.store_string(text)
		f2.close()
		DirAccess.remove_absolute(abs_tmp)
	write_count += 1
	return true


# ---------------------------------------------------------------------------
# Validação (valor ruim vira o padrão; nunca erro)

func _sanitize(key: String, v: Variant) -> Variant:
	var def: Variant = DEFAULTS[key]
	match key:
		"ui_scale":
			if v is String and v == "auto":
				return "auto"
			if (v is float or v is int) and float(v) == floor(float(v)) and int(v) >= 1 and int(v) <= 4:
				return int(v)
			return def
		"audio_mode":
			return v if (v is String and AUDIO_MODES.has(v)) else def
		"energy_mode":
			return v if (v is String and ENERGY_MODES.has(v)) else def
		"master_volume":
			return clampf(float(v), 0.0, 1.0) if (v is float or v is int) else def
		"text_size":
			return clampf(float(v), 0.5, 3.0) if (v is float or v is int) else def
	# Demais chaves: tipo tem que bater com o padrão (int e float se misturam).
	var td: int = typeof(def)
	var tv: int = typeof(v)
	if td == tv:
		return v
	if td == TYPE_FLOAT and tv == TYPE_INT:
		return float(v)
	if td == TYPE_INT and tv == TYPE_FLOAT and float(v) == floor(float(v)):
		return int(v)
	return _copy(def)


func _copy(v: Variant) -> Variant:
	if v is Dictionary or v is Array:
		return v.duplicate(true)
	return v


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		# 2 e 2.0 contam como iguais
		if (a is int or a is float) and (b is int or b is float):
			return is_equal_approx(float(a), float(b))
		return false
	return a == b
