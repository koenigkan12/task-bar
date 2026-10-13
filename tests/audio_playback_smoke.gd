# Fumaça de reprodução REAL (não headless): xvfb-run -a godot --path . --audio-driver Dummy --rendering-driver opengl3 --script res://tests/audio_playback_smoke.gd
# Verifica que players/loops/estação/cue realmente começam, sem erros de script. (Não dá para "ouvir".)
extends SceneTree

var fails: int = 0

func ok(c: bool, w: String) -> void:
	if not c:
		fails += 1
		print("FALHOU: ", w)

func _init() -> void:
	var Mgr: GDScript = load("res://scripts/audio/audio_manager.gd")
	var Fake: GDScript = load("res://tests/audio_fake_game.gd")
	var game: Node = Fake.new()
	root.add_child(game)
	var m: Node = Mgr.new()
	root.add_child(m)
	await process_frame
	m.bind_game(game)
	print("display=", DisplayServer.get_name(), " buses=", AudioServer.bus_count)
	ok(AudioServer.get_bus_index("Radio") >= 0 and AudioServer.get_bus_index("Ambient") >= 0 and AudioServer.get_bus_index("UI") >= 0, "buses existem")
	m.set_mode("full")
	m.play_sfx("click")
	await process_frame
	ok(m._voices_of("click") == 0, "travado: nada toca antes do unlock")
	m.unlock()
	game.data.append({"item": "bicicleta", "state": "ready"})
	game.data.append({"item": "painel", "state": "ready"})
	m.refresh_machine_loops()
	m.play_sfx("hammer_1")
	m.play_sfx("click")
	await create_timer(0.15).timeout
	ok(m._voices_of("hammer_1") == 1, "hammer_1 tocando")
	await create_timer(0.85).timeout
	for nm in ["amb_room", "wind_surface", "bike", "solar"]:
		var p: AudioStreamPlayer = m._loop_players.get(nm)
		ok(p != null and p.playing, "loop tocando: " + nm)
		if p != null:
			print("  ", nm, " vol=", snappedf(p.volume_db, 0.1), " pos=", snappedf(p.get_playback_position(), 0.1), " loop=", (p.stream as AudioStreamOggVorbis).loop)
	ok(not m._loop_players.has("pump"), "pump não criado")
	await create_timer(1.8).timeout
	var bike: AudioStreamPlayer = m._loop_players["bike"]
	ok(bike.volume_db > -20.0, "bike chegou ao volume alvo (%.1f)" % bike.volume_db)
	# desliga a bicicleta
	game.data.remove_at(0)
	m.refresh_machine_loops()
	await create_timer(2.0).timeout
	ok(not bike.playing, "bike parou depois de removida")
	# estação
	m.set_station(true)
	await create_timer(0.5).timeout
	ok(m._st_cur != null and m._st_cur.playing, "estação tocando")
	var first: AudioStreamPlayer = m._st_cur
	m.station_next()
	await create_timer(0.3).timeout
	ok(m._st_cur != first and m._st_cur.playing and first.playing, "crossfade: as duas faixas tocam juntas")
	await create_timer(5.5).timeout
	ok(not first.playing, "faixa anterior parou depois do crossfade")
	# fim de faixa -> avança sozinho
	var cur: AudioStreamPlayer = m._st_cur
	var idx_before: int = m._station_index
	cur.seek(cur.stream.get_length() - 3.0)
	await create_timer(0.5).timeout
	ok(m._station_index != idx_before and m._st_cur != cur, "estação avança sozinha no fim da faixa")
	# cue
	m.play_radio_cue("music_18h")
	await create_timer(0.5).timeout
	ok(m._cue_player.playing and m.current_cue() == "18h", "cue music_18h tocando")
	m.play_radio_cue("static")
	await create_timer(0.5).timeout
	ok(m._cue_player.playing and m.current_cue() == "static", "cue static tocando")
	# silent derruba tudo
	m.set_mode("silent")
	await create_timer(2.5).timeout
	var any := false
	for k in m._loop_players.keys():
		if (m._loop_players[k] as AudioStreamPlayer).playing:
			any = true
	ok(not any, "silent: loops parados")
	ok(not m._st_a.playing and not m._st_b.playing, "silent: estação parada")
	ok(not m._cue_player.playing, "silent: cue parado")
	print("audio_playback_smoke: falhas=", fails)
	quit(1 if fails > 0 else 0)
