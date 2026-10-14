class_name I18nCsv
extends RefCounted
## Parser de CSV puro (sem nós), usado pelo autoload I18n e pelos testes.
## Aspas CSV padrão (""), vírgula e quebra de linha dentro de aspas, BOM tolerado.


## Quebra o texto em linhas de campos. Linhas totalmente vazias são ignoradas.
static func parse(text: String) -> Array:
	var rows: Array = []
	if text.begins_with("﻿"):
		text = text.substr(1)
	var row := PackedStringArray()
	var field := ""
	var in_quotes := false
	var quoted := false  # o campo atual começou com aspas
	var n: int = text.length()
	var i: int = 0
	while i < n:
		var c: String = text[i]
		if in_quotes:
			if c == "\"":
				if i + 1 < n and text[i + 1] == "\"":
					field += "\""
					i += 1
				else:
					in_quotes = false
			else:
				field += c
		elif c == "\"" and field == "" and not quoted:
			in_quotes = true
			quoted = true
		elif c == ",":
			row.append(field)
			field = ""
			quoted = false
		elif c == "\n" or c == "\r":
			if c == "\r" and i + 1 < n and text[i + 1] == "\n":
				i += 1
			_end_row(rows, row, field, quoted)
			row = PackedStringArray()
			field = ""
			quoted = false
		else:
			field += c
		i += 1
	if field != "" or quoted or row.size() > 0:
		_end_row(rows, row, field, quoted)
	return rows


static func _end_row(rows: Array, row: PackedStringArray, field: String, quoted: bool) -> void:
	if row.size() == 0 and field == "" and not quoted:
		return  # linha em branco
	row.append(field)
	rows.append(row)


## Transforma as linhas em {coluna: {chave: texto}}. A primeira linha é o cabeçalho
## ("key,pt_BR,en"). Linhas com chave começando em "#" são comentários.
## `\n` literal vira quebra de linha. Chaves repetidas entram em `dups` (se passado).
static func to_tables(rows: Array, dups: Array = []) -> Dictionary:
	var tables: Dictionary = {}
	if rows.is_empty():
		return tables
	var header: PackedStringArray = rows[0]
	for c in range(1, header.size()):
		var name: String = header[c].strip_edges()
		if name != "":
			tables[name] = {}
	for r in range(1, rows.size()):
		var row: PackedStringArray = rows[r]
		var key: String = row[0].strip_edges()
		if key == "" or key.begins_with("#"):
			continue
		for c in range(1, header.size()):
			var name: String = header[c].strip_edges()
			if name == "":
				continue
			var value: String = row[c] if c < row.size() else ""
			var tbl: Dictionary = tables[name]
			if c == 1 and tbl.has(key):
				dups.append(key)
			tbl[key] = value.replace("\\n", "\n")
	return tables
