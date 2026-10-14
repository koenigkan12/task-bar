extends Node
## Autoload I18n: todos os textos do jogo (PT-BR e EN) vêm de data/i18n/strings_*.csv.
## Uso: I18n.t("item.vaso.name"), I18n.t("toast.item_done", {"item": nome}).

signal locale_changed(code: String)

const DIR: String = "res://data/i18n/"
const INDEX_PATH: String = "res://data/i18n/_index.json"
const DEFAULT_LOCALE: String = "pt_BR"

## Idioma atual: "pt_BR" | "en" (nunca "auto"; "auto" é resolvido).
var locale: String = DEFAULT_LOCALE

var _tables: Dictionary = {}     # coluna (pt_BR, en) -> {chave: texto}
var _warned: Dictionary = {}     # chaves já avisadas (um aviso só por chave)
var _files: PackedStringArray = PackedStringArray()


func _ready() -> void:
	reload()
	var settings: Node = _settings()
	if settings != null and settings.has_signal("changed"):
		settings.connect("changed", _on_setting_changed)
	_apply_locale(resolve_locale(_setting_locale()), false)


## Traduz a chave. Chave ausente devolve a própria chave (e avisa uma vez).
func t(key: String, args: Dictionary = {}) -> String:
	var text: String = _lookup(key)
	if text == "":
		_warn_once("missing:" + key, "I18n: chave ausente '%s'" % key)
		return key
	return substitute(text, args)


func has_key(key: String) -> bool:
	return _lookup(key) != ""


## Troca o idioma ("auto", "pt_BR", "en", "pt", "en_US"...). Persiste em Settings.
func set_locale(code: String) -> void:
	var settings: Node = _settings()
	if settings != null and settings.has_method("set_value"):
		settings.call("set_value", "locale", code)
	_apply_locale(resolve_locale(code), true)


## Idiomas que existem nos CSV carregados.
func available_locales() -> PackedStringArray:
	return PackedStringArray(_tables.keys())


## Relê todos os CSV (índice se existir; também varre a pasta quando possível).
func reload() -> void:
	_tables.clear()
	_files = _list_csv_files()
	for file_name in _files:
		if not FileAccess.file_exists(DIR + file_name):
			continue
		var text: String = FileAccess.get_file_as_string(DIR + file_name)
		if text == "":
			push_warning("I18n: não consegui ler %s%s" % [DIR, file_name])
			continue
		load_csv_text(text, file_name)


## Mistura o conteúdo de um CSV nas tabelas (usado por reload e pelos testes).
func load_csv_text(text: String, source: String = "") -> void:
	var dups: Array = []
	var tables: Dictionary = I18nCsv.to_tables(I18nCsv.parse(text), dups)
	for key in dups:
		_warn_once("dup:" + str(key), "I18n: chave repetida '%s' (%s)" % [key, source])
	for col in tables:
		if not _tables.has(col):
			_tables[col] = {}
		(_tables[col] as Dictionary).merge(tables[col], true)


## "auto"/vazio usa o idioma do sistema; pt* vira pt_BR; resto vira en.
## `os_lang` existe só para teste (padrão: OS.get_locale_language()).
func resolve_locale(code: String, os_lang: String = "") -> String:
	var c: String = code.strip_edges().replace("-", "_")
	if c == "" or c.to_lower() == "auto":
		c = os_lang if os_lang != "" else OS.get_locale_language()
	if _tables.has(c):
		return c
	if c.to_lower().begins_with("pt"):
		return "pt_BR"
	return "en"


static func substitute(text: String, args: Dictionary) -> String:
	if args.is_empty() or text.find("{") == -1:
		return text
	for k in args:
		var v: Variant = args[k]
		var s: String
		if v is float and is_equal_approx(v, roundf(v)):
			s = str(int(v))
		else:
			s = str(v)
		text = text.replace("{" + str(k) + "}", s)
	return text


# ---- interno -------------------------------------------------------------

func _lookup(key: String) -> String:
	var tbl: Variant = _tables.get(locale)
	if tbl != null:
		var v: String = (tbl as Dictionary).get(key, "")
		if v != "":
			return v
	if locale != DEFAULT_LOCALE:
		var base: Variant = _tables.get(DEFAULT_LOCALE)
		if base != null:
			var v2: String = (base as Dictionary).get(key, "")
			if v2 != "":
				_warn_once("fallback:" + key, "I18n: '%s' sem tradução em %s, usando %s" % [key, locale, DEFAULT_LOCALE])
				return v2
	return ""


func _apply_locale(code: String, announce: bool) -> void:
	if code == locale:
		return
	locale = code
	if announce:
		locale_changed.emit(locale)


func _settings() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Settings")


func _setting_locale() -> String:
	var settings: Node = _settings()
	if settings != null and settings.has_method("get_value"):
		return str(settings.call("get_value", "locale", "auto"))
	return "auto"


func _on_setting_changed(key: String) -> void:
	if key == "locale":
		_apply_locale(resolve_locale(_setting_locale()), true)


func _list_csv_files() -> PackedStringArray:
	var found: Dictionary = {}
	# 1) índice (funciona em build exportado, onde DirAccess pode não listar)
	if FileAccess.file_exists(INDEX_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
		if parsed is Dictionary and (parsed as Dictionary).get("files") is Array:
			for f in (parsed as Dictionary)["files"]:
				found[str(f)] = true
	# 2) varredura (pega CSV novo se o índice estiver velho)
	var dir: DirAccess = DirAccess.open(DIR)
	if dir != null:
		for f in dir.get_files():
			var name: String = f.trim_suffix(".import").trim_suffix(".remap")
			if name.begins_with("strings_") and name.ends_with(".csv"):
				found[name] = true
	var out: Array = found.keys()
	out.sort()
	return PackedStringArray(out)


func _warn_once(token: String, message: String) -> void:
	if _warned.has(token):
		return
	_warned[token] = true
	push_warning(message)
