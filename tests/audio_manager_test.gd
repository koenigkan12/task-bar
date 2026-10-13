# Teste lógico do AudioManager, sem tocar nada (roda em --headless).
# godot --headless --path . --script res://tests/audio_manager_test.gd
extends SceneTree

const SFX := ["click", "hover", "buy", "hammer_1", "hammer_2", "hammer_3", "dig", "knock", "scrap", "harvest",
	"pour", "radio_on", "tune", "blip", "error", "step_1", "step_2", "hatch_open", "page", "place", "switch"]
const LOOPS := ["amb_room", "bike", "windmill", "battery", "pump", "conveyor", "greenhouse", "solar", "drip",
	"wind_surface", "static"]
const MUSIC := ["far", "18h", "numbers", "station_1", "station_2", "station_3", "epilogue", "her_voice"]

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FALHOU: ", what)


func _init() -> void:
	var Mgr: GDScript = load("res://scripts/audio/audio_manager.gd")
	var Fake: GDScript = load("res://tests/audio_fake_game.gd")
	var FakeSet: GDScript = load("res://tests/audio_fake_settings.gd")

	# --- 1. nomes -> arquivos, e os arquivos carregam como áudio
	for n in SFX:
		_file_ok("res://assets/audio/sfx/%s.ogg" % n)
	for n in LOOPS + ["amb_night"]:
		_file_ok("res://assets/audio/loops/%s.ogg" % n)
	for n in MUSIC:
		_file_ok("res://assets/audio/music/%s.ogg" % n)
	var m: Node = Mgr.new()
	for n in SFX:
		ok(m.SFX_NAMES.has(n), "SFX_NAMES tem " + n)
	for n in LOOPS:
		ok(m.LOOP_NAMES.has(n), "LOOP_NAMES tem " + n)
	for n in MUSIC:
		ok(m.MUSIC_NAMES.has(n), "MUSIC_NAMES tem " + n)
	for cue in m.CUE_MUSIC.keys():
		ok(m.MUSIC_NAMES.has(m.CUE_MUSIC[cue]), "cue %s aponta para faixa existente" % cue)
	for k in m.MACHINE_LOOP.values():
		ok(m.LOOP_NAMES.has(k), "máquina -> loop existente " + k)
	for k in m.SFX_GAIN_DB.keys():
		ok(m.SFX_NAMES.has(k), "ganho definido só para sfx existente " + k)
	ok(m.PITCH_JITTER <= 0.03 + 0.0001, "jitter de pitch <= 3%")

	# --- 2. loops desejados (função pura)
	var inst: Array = [
		{"item": "bicicleta", "state": "ready"}, {"item": "bicicleta", "state": "ready"},
		{"item": "moinho", "state": "building"}, {"item": "vaso", "state": "ready"},
		{"item": "esteira", "state": "ready"}, {"item": "roldana", "state": "ready"}]
	var lp: Dictionary = m.compute_loops(inst, false)
	ok(lp["bike"] > m.LOOP_DB["bike"] and lp["bike"] <= m.LOOP_DB["bike"] + m.COUNT_MAX_BOOST_DB, "2 bicicletas: volume sobe, com teto")
	ok(lp["windmill"] <= m.SILENT_DB, "moinho em obra não toca")
	ok(lp["conveyor"] > m.LOOP_DB["conveyor"], "esteira+roldana: um loop, mais alto")
	ok(lp["pump"] <= m.SILENT_DB, "sem bomba, sem loop")
	ok(lp["amb_room"] > m.SILENT_DB and lp["wind_surface"] > m.SILENT_DB, "ambiente de sala e vento sempre")
	ok(lp["amb_night"] <= m.SILENT_DB, "dia: sem loop de noite")
	var ln: Dictionary = m.compute_loops(inst, true)
	ok(ln["amb_night"] > m.SILENT_DB and ln["amb_room"] < lp["amb_room"], "noite: loop de noite, sala mais baixa")

	# --- 3. máquina de modos (manager separado do autoload)
	var game: Node = Fake.new()
	var sets: Node = FakeSet.new()
	root.add_child(game)
	root.add_child(sets)
	root.add_child(m)
	await process_frame          # _ready roda aqui (headless: nada toca)
	m.bind_settings(sets)
	m.bind_game(game)
	m.record_plan = true
	ok(m.get_mode() == "ambient", "padrão: ambient")
	ok(not m.is_unlocked(), "começa travado")
	ok(not m.sfx_allowed("click") and not m.cue_allowed() and not m.loops_allowed(), "travado: nada liberado")
	for v in m.loop_plan().values():
		ok(float(v) <= m.SILENT_DB, "travado: loops silenciosos")
	m.play_sfx("click")
	ok(m.plan.is_empty(), "travado: play_sfx não registra")
	m.set_station(true)
	ok(m.is_station_on(), "set_station guarda a vontade do jogador")
	m.unlock()
	ok(m.is_unlocked() and sets.values["sound_unlocked"] == true, "unlock libera e grava Settings")
	ok(m.sfx_allowed("hammer_1") and m.sfx_allowed("click"), "ambient: sfx liberados")
	ok(not m.sfx_allowed("blip") and not m.sfx_allowed("tune"), "ambient: sfx de rádio bloqueados (rádio só em texto)")
	ok(not m.cue_allowed(), "ambient: cue de rádio bloqueado")
	ok(m.sfx_gain_db("hammer_1") < m.SFX_GAIN_DB["hammer_1"], "ambient: sfx do mundo mais baixos")
	ok(m.sfx_gain_db("click") == m.SFX_GAIN_DB["click"], "ambient: UI no nível normal")
	ok(float(m.loop_plan()["amb_room"]) > m.SILENT_DB, "ambient: ambiente da sala ligado")
	var st_on := false
	for e in m.plan:
		if e.get("kind") == "station" and e.get("on") == true:
			st_on = true
	ok(st_on, "estação ligada antes do unlock começa após o unlock")

	# sinais de Game -> sfx
	m.plan.clear()
	game.item_placed.emit(1)
	ok(_has(m.plan, "sfx", "hammer_1") or _has(m.plan, "sfx", "hammer_2") or _has(m.plan, "sfx", "hammer_3"), "item_placed -> martelada")
	m.plan.clear()
	game.visit_happened.emit({"units": 2, "scrap": 3, "box_after": 0})
	ok(_has(m.plan, "sfx", "knock"), "visit_happened -> knock")
	m.plan.clear()
	game.plot_harvested.emit(1)
	game.plot_harvested.emit(2)
	ok(_count(m.plan, "sfx", "harvest") == 1, "plot_harvested: recarga evita metralhadora")
	m.plan.clear()
	game.room_dug.emit(2)
	ok(_has(m.plan, "sfx", "dig"), "room_dug -> dig")
	m.plan.clear()
	game.radio_line.emit({"cue": "music_18h"})
	ok(m.plan.is_empty(), "ambient: radio_line com música não toca")
	game.antenna_changed.emit(3)
	ok(not _has(m.plan, "sfx", "tune"), "ambient: antenna_changed não toca tune (rádio)")

	# máquinas: instances() do Game falso
	game.data.append({"item": "moinho", "state": "ready"})
	game.item_finished.emit(5, "moinho")
	ok(float(m.loop_plan()["windmill"]) > m.SILENT_DB, "item_finished -> refresh liga o loop do moinho")
	game.data.clear()
	game.item_removed.emit(5)
	ok(float(m.loop_plan()["windmill"]) <= m.SILENT_DB, "item_removed -> desliga o loop")
	game.night = true
	m.refresh_machine_loops()
	ok(float(m.loop_plan()["amb_night"]) > m.SILENT_DB, "noite liga amb_night")
	game.night = false

	# modo completo
	sets.set_value("audio_mode", "full")      # via sinal changed
	ok(m.get_mode() == "full", "Settings.changed muda o modo")
	ok(m.cue_allowed() and m.sfx_allowed("blip"), "full: rádio liberado")
	ok(m.sfx_gain_db("hammer_1") == m.SFX_GAIN_DB["hammer_1"], "full: sfx no nível normal")
	m.plan.clear()
	game.radio_line.emit({"cue": "music_18h"})
	ok(_has(m.plan, "cue_music", "18h"), "full: radio_line music_18h -> 18h")
	m.plan.clear()
	m.play_radio_cue("voice_her")
	ok(_has(m.plan, "cue_music", "her_voice"), "voice_her -> her_voice")
	m.plan.clear()
	m.play_radio_cue("tone")
	ok(_has(m.plan, "sfx", "blip"), "tone -> blip")
	m.plan.clear()
	m.play_radio_cue("none")
	ok(m.plan.is_empty(), "none não toca")
	m.plan.clear()
	game.arrival_started.emit()
	ok(_has(m.plan, "sfx", "hatch_open"), "arrival_started -> hatch_open")

	# estação
	var t0: String = m.station_track()
	m.station_next()
	ok(m.station_track() != t0, "station_next troca de faixa")
	m.station_next()
	m.station_next()
	ok(m.station_track() == t0, "station_next dá a volta nas 3 faixas")
	m.set_station(false)
	ok(not m.is_station_on(), "set_station(false)")

	# silencioso
	sets.set_value("audio_mode", "silent")
	ok(m.get_mode() == "silent", "modo silent")
	ok(not m.sfx_allowed("click") and not m.cue_allowed() and not m.loops_allowed() and not m.station_allowed(), "silent: nada")
	for v in m.loop_plan().values():
		ok(float(v) <= m.SILENT_DB, "silent: loops silenciosos")
	m.plan.clear()
	m.play_sfx("click")
	game.item_placed.emit(2)
	ok(not _has(m.plan, "sfx", "click") and not _has(m.plan, "sfx", "hammer_1"), "silent: nenhum sfx")
	m.set_mode("banana")
	ok(m.get_mode() == "silent", "modo inválido é ignorado")
	m.play_sfx("nao_existe")
	ok(m.plan.is_empty(), "sfx inexistente é ignorado")

	# volume mestre
	sets.set_value("master_volume", 0.5)
	ok(absf(m.get_master_volume() - 0.5) < 0.001, "master_volume vem de Settings")
	m.set_master_volume(3.0)
	ok(m.get_master_volume() == 1.0, "master_volume clampa em 1")
	m.set_master_volume(-1.0)
	ok(m.get_master_volume() == 0.0, "master_volume clampa em 0")

	# Game "stub" (sem sinais) não dá erro
	var stub: Node = Node.new()
	root.add_child(stub)
	m.bind_game(stub)
	m.refresh_machine_loops()
	ok(true, "bind_game com stub vazio sem erro")

	print("audio_manager_test: %d checagens, %d falhas" % [checks, fails])
	quit(1 if fails > 0 else 0)


func _file_ok(path: String) -> void:
	ok(ResourceLoader.exists(path), "existe " + path)
	var s := load(path) as AudioStream
	ok(s != null and s.get_length() > 0.01, "carrega " + path)


func _has(plan: Array, kind: String, nm: String) -> bool:
	return _count(plan, kind, nm) > 0


func _count(plan: Array, kind: String, nm: String) -> int:
	var c := 0
	for e in plan:
		if e.get("kind") == kind and e.get("name") == nm:
			c += 1
	return c
