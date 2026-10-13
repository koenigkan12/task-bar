extends SceneTree
## Rádio, diário, jornada pós-contato, chegada e epílogo; cobertura das chaves i18n.
## godot --headless --path . --script res://tests/sim_story.gd
const Bot := preload("res://tests/sim_bot.gd")
const U := preload("res://tests/sim_util.gd")
var fails := 0
var sig: Dictionary = {}
var keys: Dictionary = {}


func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func load_keys() -> void:
	for f in ["strings_story", "strings_items", "strings_ui"]:
		var fa := FileAccess.open("res://data/i18n/%s.csv" % f, FileAccess.READ)
		if fa == null:
			continue
		while not fa.eof_reached():
			var ln := fa.get_line()
			var i := ln.find(",")
			if i > 0:
				keys[ln.substr(0, i)] = true


func _init() -> void:
	Balance.load_all()
	load_keys()
	var s := Sim.new()
	s.radio_line.connect(func(d: Dictionary) -> void: sig["radio_line"] = int(sig.get("radio_line", 0)) + 1; sig["last_kind_" + String(d["kind"])] = true)
	s.house_item_bought.connect(func(_i: String) -> void: sig["house"] = int(sig.get("house", 0)) + 1)
	s.arrival_started.connect(func() -> void: sig["arrival_started"] = int(sig.get("arrival_started", 0)) + 1)
	s.arrival_finished.connect(func() -> void: sig["arrival_finished"] = int(sig.get("arrival_finished", 0)) + 1)
	s.new_game(11, 6.0)
	var plan: Array[String] = Bot.PLAN.duplicate()
	plan.append("mesinha")  # a segunda caneca pede a mesinha
	plan.append_array(Balance.house_items())
	var bot := Bot.new(s, plan)
	print("== até o contato")
	bot.run(40.0)
	check(s.antenna() == 5 and s.contact_made(), "contato feito (antena 5)")
	var j := s.journey()
	check(j["contact_min"] >= 0.0 and j["items_total"] == 6 and j["items_done"] == 0, "journey(): " + str(j))
	check(absf(float(j["arrival_due_min"]) - float(j["contact_min"]) - 7.0 * 1440.0) < 0.01, "chegada prevista = contato + 7 dias")
	check(not s.arrived() and not s.arrival_pending(), "ainda não chegou")
	# diário contém a fala dela
	var her := 0
	for e in s.diary():
		if e["kind"] == "her":
			her += 1
	check(her >= 1, "fala dela (antena 5) no diário (kind her)")
	check(s.diary().size() >= 10, "diário com %d entradas" % s.diary().size())

	print("== casa")
	var day0 := s.t_min
	var guard := 0
	while not s.arrival_pending() and guard < 20 * 1440 / 10:
		for c in bot.checkins:
			pass
		var before := s.tod_hours()
		s.advance(10.0)
		for c in bot.checkins:
			if absf(before - c) < 10.0 / 120.0:
				bot.check_in()
		guard += 1
	check(int(sig.get("house", 0)) == 6, "house_item_bought x6")
	check(sig.has("last_kind_item"), "falas on_item entregues")
	check(s.arrival_pending() and int(sig.get("arrival_started", 0)) == 1, "arrival_started uma vez")
	var due := float(s.journey()["arrival_due_min"])
	check(s.t_min >= due - 0.01, "chegada só depois do prazo (t=%.2f d, prazo %.2f d)" % [s.t_min / 1440.0, due / 1440.0])
	var hs := s.house_status()
	var allb := true
	for h in hs:
		allb = allb and bool(h["bought"])
	check(allb and hs.size() == 6, "house_status: tudo comprado")
	check(s.journey()["items_done"] == 6 and s.journey()["days_left"] == 0.0, "journey: 6/6, 0 dias")
	var travel_keys := 0
	var travel_total := Balance.journey_travel().size()
	for e in s.diary():
		if String(e["key"]).begins_with("journey.t"):
			travel_keys += 1
	check(travel_keys >= 5 and travel_keys <= travel_total, "falas de viagem entregues em ordem (%d de %d)" % [travel_keys, travel_total])
	var lastday := -1
	var ordered := true
	var trav: Array = []
	for e in s.diary():
		if String(e["key"]).begins_with("journey.t") and not String(e["key"]).begins_with("journey.on"):
			trav.append(e)
	trav.reverse()
	for e in trav:
		ordered = ordered and int(e["day"]) >= lastday
		lastday = int(e["day"])
	check(ordered, "viagem em ordem cronológica")
	s.advance(600.0)
	check(int(sig.get("arrival_started", 0)) == 1, "não repete arrival_started")

	print("== salvar no meio da cena e carregar")
	var d1 := s.to_dict()
	var s2 := Sim.new()
	check(s2.from_dict(JSON.parse_string(JSON.stringify(d1, "", true, true))) and s2.arrival_pending(), "chegada pendente sobrevive ao save")
	var dd := U.deep_close(s2.to_dict(), d1)
	check(dd == "", "to_dict igual após JSON " + dd)

	print("== chegada e epílogo")
	s.finish_arrival()
	check(s.arrived() and int(sig.get("arrival_finished", 0)) == 1, "arrived() e arrival_finished")
	s.finish_arrival()
	check(int(sig.get("arrival_finished", 0)) == 1, "finish_arrival não repete")
	var notes_before := 0
	for e in s.diary():
		if e["kind"] == "note":
			notes_before += 1
	s.advance(3.0 * 1440.0)
	var notes: Array = []
	for e in s.diary():
		if e["kind"] == "note":
			notes.append(e)
	var n_new := notes.size() - notes_before
	check(n_new >= 5 and n_new <= 7, "bilhetes: %d em 3 dias (2/dia)" % n_new)
	var ok_keys := true
	for e in notes:
		ok_keys = ok_keys and Balance.epilogue_notes().has(String(e["key"]))
	check(ok_keys, "bilhetes vêm de epilogue_notes")
	check(s.diary()[0]["kind"] in ["note", "radio", "her"], "topo do diário")

	print("== chaves i18n")
	var missing: Array[String] = []
	for l in Balance.radio_lines:
		if not keys.has(String(l["text_key"])):
			missing.append(String(l["text_key"]))
	for t in Balance.journey_travel():
		if not keys.has(String(t["text_key"])):
			missing.append(String(t["text_key"]))
	for it in Balance.house_items():
		var oi := Balance.journey_on_item(it)
		if oi.is_empty() or not keys.has(String(oi["text_key"])):
			missing.append("on_item " + it)
	for n in Balance.epilogue_notes():
		if not keys.has(n):
			missing.append(n)
	var al := Balance.journey_arrival()
	if not keys.has(String(al.get("text_key", ""))):
		missing.append("journey.arrival")
	check(missing.is_empty(), "chaves de história presentes " + str(missing))
	var miss2: Array[String] = []
	for id in Balance.item_ids():
		for suf in [".name", ".desc"]:
			if Balance.item(id).get("start_tool", false) and false:
				continue
			if not keys.has("item." + id + suf):
				miss2.append("item." + id + suf)
	for id in ["comodo2", "comodo3"]:
		for suf in [".name", ".desc"]:
			if not keys.has("item." + id + suf):
				miss2.append("item." + id + suf)
	for c in Balance.crop_ids():
		if not keys.has("crop." + c + ".name"):
			miss2.append("crop." + c + ".name")
	for k in ["missing.antenna", "missing.rooms", "missing.supply", "missing.cost", "missing.free_cols", "missing.item", "missing.max",
			"diary.away.summary", "diary.away.summary.v1", "diary.away.summary.n1", "diary.away.summary.n0", "diary.away.summary.v1n1",
			"diary.away.summary.v1n0", "diary.away.line", "diary.away.line.night", "diary.away.slept"]:
		if not keys.has(k):
			miss2.append(k)
	for p in ["renda", "tempo", "espaco", "porta", "historia"]:
		if not keys.has("pra_que." + p):
			miss2.append("pra_que." + p)
	check(miss2.is_empty(), "chaves de itens/ui presentes " + str(miss2))
	print("RESULTADO: %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(0 if fails == 0 else 1)
