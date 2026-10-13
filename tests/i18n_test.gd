extends SceneTree
## Teste do módulo I18N: parser CSV, placeholders, locale e dados reais.
## Rodar: godot --headless --path . --script res://tests/i18n_test.gd

var _fail: int = 0
var _ok: int = 0


func _check(cond: bool, what: String) -> void:
	if cond:
		_ok += 1
	else:
		_fail += 1
		print("FALHOU: ", what)


func _init() -> void:
	_test_parser()
	_test_tables()
	_test_i18n_logic()
	_test_real_data()
	print("i18n_test: %d ok, %d falhas" % [_ok, _fail])
	quit(1 if _fail > 0 else 0)


func _test_parser() -> void:
	var r: Array = I18nCsv.parse("a,b,c\n1,2,3\n")
	_check(r.size() == 2 and r[1][2] == "3", "csv simples")
	r = I18nCsv.parse("k,\"Oi, mundo\",x\n")
	_check(r[0][1] == "Oi, mundo" and r[0].size() == 3, "vírgula dentro de aspas")
	r = I18nCsv.parse("k,\"Ele disse \"\"oi\"\"\",x\n")
	_check(r[0][1] == "Ele disse \"oi\"", "aspas escapadas")
	r = I18nCsv.parse("k,\"linha 1\nlinha 2\",fim\nk2,a,b\n")
	_check(r.size() == 2 and r[0][1] == "linha 1\nlinha 2" and r[0][2] == "fim", "campo multilinha")
	r = I18nCsv.parse("﻿key,pt_BR,en\nk,a,b")
	_check(r[0][0] == "key" and r.size() == 2 and r[1][2] == "b", "BOM e sem quebra final")
	r = I18nCsv.parse("k,a,b\r\nj,c,d\r\n")
	_check(r.size() == 2 and r[1][2] == "d" and r[0][2] == "b", "CRLF")
	r = I18nCsv.parse("k,,b\n\n\nj,\"\",\n")
	_check(r.size() == 2 and r[0][1] == "" and r[1].size() == 3 and r[1][2] == "", "campos vazios e linhas em branco")
	r = I18nCsv.parse("k,\"a\r\nb\",x\n")
	_check(r[0][1] == "a\r\nb", "CRLF dentro de aspas é preservado")
	r = I18nCsv.parse("k,tubo de 5\" de largura,x\n")
	_check(r[0][1] == "tubo de 5\" de largura", "aspa solta no meio de campo sem aspas")
	r = I18nCsv.parse("k,\"a,b\",\"\"\"\"\n")
	_check(r[0][1] == "a,b" and r[0][2] == "\"", "campo só com aspa escapada")
	_check(I18nCsv.parse("").is_empty(), "texto vazio")


func _test_tables() -> void:
	var dups: Array = []
	var rows: Array = I18nCsv.parse("key,pt_BR,en\n# comentário,x,y\na,Olá\\nmundo,Hello\nb,só pt\na,repetida,again\n")
	var t: Dictionary = I18nCsv.to_tables(rows, dups)
	_check(t.has("pt_BR") and t.has("en"), "colunas de idioma")
	_check(t["pt_BR"]["a"] == "repetida", "chave repetida: a última vence")
	_check(dups == ["a"], "chave repetida é reportada")
	_check(not t["pt_BR"].has("# comentário"), "comentário ignorado")
	var t2: Dictionary = I18nCsv.to_tables(I18nCsv.parse("key,pt_BR,en\na,Olá\\nmundo,Hello\n"))
	_check(t2["pt_BR"]["a"] == "Olá\nmundo", "\\n literal vira quebra de linha")
	_check(t["en"]["b"] == "", "coluna ausente vira vazio")


func _new_i18n() -> Node:
	var script: GDScript = load("res://scripts/i18n/i18n.gd")
	var node: Node = script.new()
	return node


func _test_i18n_logic() -> void:
	var i: Node = _new_i18n()
	i.load_csv_text("key,pt_BR,en\nhello,Olá {nome}!,Hello {nome}!\nonly_pt,Só em português,\ncount,{n} cestos,{n} baskets\ntwo,{a} e {b},{a} and {b}\nbr,Linha1\\nLinha2,Line1\\nLine2\n", "teste")
	_check(i.locale == "pt_BR", "locale padrão pt_BR")
	_check(i.t("hello", {"nome": "Zé"}) == "Olá Zé!", "placeholder por dicionário")
	_check(i.t("hello") == "Olá {nome}!", "placeholder sem args fica como está")
	_check(i.t("count", {"n": 3.0}) == "3 cestos", "float inteiro sem .0")
	_check(i.t("count", {"n": 2.5}) == "2.5 cestos", "float fracionário")
	_check(i.t("two", {"a": "x", "b": 7}) == "x e 7", "vários placeholders")
	_check(i.t("br") == "Linha1\nLinha2", "quebra literal")
	_check(i.t("nao_existe") == "nao_existe", "chave ausente devolve a chave")
	_check(not i.has_key("nao_existe") and i.has_key("hello"), "has_key")
	var seen: Array = []
	i.locale_changed.connect(func(c: String) -> void: seen.append(c))
	i.set_locale("en")
	_check(i.locale == "en" and seen == ["en"], "set_locale en emite sinal")
	_check(i.t("hello", {"nome": "Joe"}) == "Hello Joe!", "tradução em en")
	_check(i.t("only_pt") == "Só em português", "en vazio cai para pt_BR")
	i.set_locale("en_US")
	_check(i.locale == "en" and seen.size() == 1, "en_US = en, sem sinal repetido")
	i.set_locale("pt")
	_check(i.locale == "pt_BR" and seen == ["en", "pt_BR"], "pt vira pt_BR")
	_check(i.resolve_locale("auto", "pt") == "pt_BR", "auto + sistema pt")
	_check(i.resolve_locale("auto", "pt_PT") == "pt_BR", "auto + sistema pt_PT")
	_check(i.resolve_locale("auto", "de") == "en", "auto + idioma desconhecido = en")
	_check(i.resolve_locale("", "fr") == "en", "vazio = auto")
	_check(i.resolve_locale("pt-BR") == "pt_BR", "hífen aceito")
	i.free()


func _read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _test_real_data() -> void:
	var i: Node = _new_i18n()
	i.reload()
	var index: Variant = _read_json("res://data/i18n/_index.json")
	_check(index is Dictionary and "strings_items.csv" in index["files"] and "strings_ui.csv" in index["files"], "índice lista os CSV")
	var bal: Dictionary = _read_json("res://data/balance.json")
	for id in bal["items"]:
		for field in ["name", "desc"]:
			var k: String = "item.%s.%s" % [id, field]
			_check(i.has_key(k), "existe " + k)
	for c in bal["crops"]:
		_check(i.has_key("crop.%s.name" % c), "crop " + c)
	for l in ["plantio", "agua", "energia", "transporte", "decor", "casa", "escavacao"]:
		_check(i.has_key("line." + l), "line " + l)
	for n in range(1, 6):
		_check(i.has_key("antenna.%d.name" % n), "antenna %d" % n)
	for b in bal["behaviors"]:
		_check(i.has_key("behavior." + b), "behavior " + b)
	for f in ["ladder", "hatch_box", "radio_table", "bed"]:
		_check(i.has_key("fixed." + f), "fixed " + f)
	for x in ["renda", "tempo", "espaco", "porta", "historia"]:
		_check(i.has_key("pra_que." + x) and i.has_key("pra_que.%s.help" % x), "pra_que " + x)
	# PT e EN completos, descrições curtas, botões e abas curtos
	var langs: Array = ["pt_BR", "en"]
	var ui_count: int = 0
	for lang in langs:
		i.set_locale(lang)
		for id in bal["items"]:
			var d: String = i.t("item.%s.desc" % id)
			var nm: String = i.t("item.%s.name" % id)
			_check(d.length() <= 60, "desc <= 60 (%s/%s): %d" % [lang, id, d.length()])
			_check(d.to_lower().find(nm.to_lower()) == -1, "desc não repete o nome (%s/%s)" % [lang, id])
	var ui_text: String = FileAccess.get_file_as_string("res://data/i18n/strings_ui.csv")
	var tables: Dictionary = I18nCsv.to_tables(I18nCsv.parse(ui_text))
	ui_count = (tables["pt_BR"] as Dictionary).size()
	_check(ui_count >= 120, "strings_ui tem >= 120 chaves (%d)" % ui_count)
	for lang in langs:
		var tb: Dictionary = tables[lang]
		for k in tb:
			_check(tb[k] != "", "UI vazio %s/%s" % [lang, k])
			if k.ends_with(".btn") or k.begins_with("ui.btn.") or k.contains(".btn.") or k.begins_with("tab."):
				_check((tb[k] as String).length() <= 14, "botão/aba <= 14 (%s/%s)" % [lang, k])
	i.free()
