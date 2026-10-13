extends SceneTree
## Teste headless de Settings: padrões, debounce, escrita atômica, arquivo corrompido, validação.
## godot --headless --path . --script res://tests/platform_settings.gd

const SettingsScript = preload("res://scripts/platform/settings.gd")
const P := "user://test_settings_platform.json"

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FALHOU: ", what)


func clean() -> void:
	for suffix in ["", ".tmp", ".bad"]:
		var f: String = ProjectSettings.globalize_path(P + suffix)
		if FileAccess.file_exists(P + suffix):
			DirAccess.remove_absolute(f)


func make() -> Node:
	var s: Node = SettingsScript.new()
	s.path = P
	return s


func _initialize() -> void:
	clean()
	# --- padrões do contrato
	var s: Node = make()
	root.add_child(s)
	ok(s.get_value("locale") == "auto", "locale auto")
	ok(s.get_value("audio_mode") == "ambient", "audio_mode ambient")
	ok(is_equal_approx(float(s.get_value("master_volume")), 0.8), "master_volume 0.8")
	ok(s.get_value("ui_scale") == "auto", "ui_scale auto")
	ok(s.get_value("always_on_top") == false, "always_on_top false")
	ok(s.get_value("energy_mode") == "auto", "energy_mode auto")
	ok(s.get_value("window_pos") is Dictionary and s.get_value("window_pos").is_empty(), "window_pos {}")
	ok(s.get_value("anchor") == "bottom_left", "anchor")
	ok(is_equal_approx(float(s.get_value("text_size")), 1.0), "text_size 1.0")
	ok(s.get_value("reduce_flicker") == false, "reduce_flicker")
	ok(s.get_value("first_run_done") == false, "first_run_done")
	ok(s.get_value("tray_enabled") == true, "tray_enabled true")
	ok(s.get_value("autostart_hint_seen") == false, "autostart_hint_seen")
	ok(s.get_value("sound_unlocked") == false, "sound_unlocked")
	ok(s.get_value("chave_inexistente", 42) == 42, "default do chamador")
	ok(s.get_value("chave_inexistente") == null, "null sem default")

	# --- sinal e não-gravação quando nada muda
	var seen: Array = []
	s.changed.connect(func(k: String) -> void: seen.append(k))
	s.set_value("audio_mode", "ambient")
	ok(seen.is_empty(), "sem sinal quando o valor é igual ao padrão")
	s.set_value("audio_mode", "full")
	ok(seen == ["audio_mode"], "sinal changed(audio_mode)")
	ok(s.get_value("audio_mode") == "full", "valor novo lido")

	# --- debounce: várias mudanças => 1 escrita, só depois de 0,5 s
	ok(not FileAccess.file_exists(P), "nada gravado antes do debounce")
	s.set_value("master_volume", 0.5)
	s.set_value("master_volume", 0.4)
	s.set_value("tray_enabled", false)
	ok(s.write_count == 0, "write_count 0 logo após set")
	var t0: int = Time.get_ticks_msec()
	while s.write_count == 0 and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	var dt: int = Time.get_ticks_msec() - t0
	ok(s.write_count == 1, "uma única escrita (foram %d)" % s.write_count)
	ok(dt >= 250 and dt <= 1500, "debounce ~0,5 s (levou %d ms)" % dt)
	ok(FileAccess.file_exists(P), "arquivo existe")
	ok(not FileAccess.file_exists(P + ".tmp"), "tmp sumiu (rename atômico)")

	# --- roundtrip em outra instância
	var s2: Node = make()
	root.add_child(s2)
	ok(s2.get_value("audio_mode") == "full", "roundtrip audio_mode")
	ok(is_equal_approx(float(s2.get_value("master_volume")), 0.4), "roundtrip volume")
	ok(s2.get_value("tray_enabled") == false, "roundtrip tray_enabled")

	# --- Dictionary é copiado (sem aliasing) e sobrevive ao disco
	var wp: Dictionary = {"1920x1080@0,0": {"x": 10, "y": 0}, "_last": "1920x1080@0,0"}
	s2.set_value("window_pos", wp)
	wp["_last"] = "mudou"
	ok(s2.get_value("window_pos")["_last"] == "1920x1080@0,0", "set_value copia o Dictionary")
	var got: Dictionary = s2.get_value("window_pos")
	got["x"] = 1
	ok(not s2.get_value("window_pos").has("x"), "get_value copia o Dictionary")
	ok(s2.flush(), "flush devolve true")
	var s3: Node = make()
	root.add_child(s3)
	ok(s3.get_value("window_pos")["1920x1080@0,0"]["x"] == 10, "window_pos persistiu")

	# --- ui_scale: int sobrevive ao JSON (float) e valor ruim volta ao padrão
	s3.set_value("ui_scale", 3)
	s3.flush()
	var s4: Node = make()
	ok(s4.get_value("ui_scale") is int and s4.get_value("ui_scale") == 3, "ui_scale 3 volta como int")
	s4.set_value("ui_scale", 7)
	ok(s4.get_value("ui_scale") == "auto", "ui_scale 7 invalido -> auto")
	s4.set_value("ui_scale", "auto")
	s4.set_value("audio_mode", "xyz")
	ok(s4.get_value("audio_mode") == "ambient", "audio_mode invalido -> padrao")
	s4.set_value("master_volume", 9)
	ok(is_equal_approx(float(s4.get_value("master_volume")), 1.0), "volume clamp 1")

	# --- arquivo corrompido: vai para .bad e recomeça com padrões
	var f: FileAccess = FileAccess.open(P, FileAccess.WRITE)
	f.store_string("{ isto nao eh json ,,, ")
	f.close()
	var s5: Node = make()
	ok(s5.get_value("audio_mode") == "ambient", "corrompido: padrão")
	ok(FileAccess.file_exists(P + ".bad"), "corrompido: .bad criado")
	ok(not FileAccess.file_exists(P), "corrompido: original removido")
	s5.set_value("audio_mode", "silent")
	ok(s5.flush(), "grava depois de recomeçar")
	var s6: Node = make()
	ok(s6.get_value("audio_mode") == "silent", "recomeço persiste")

	# --- JSON válido mas não é objeto; e de novo, com .bad já existente
	f = FileAccess.open(P, FileAccess.WRITE)
	f.store_string("[1, 2, 3]")
	f.close()
	var s7: Node = make()
	ok(s7.get_value("audio_mode") == "ambient", "array JSON: padrão")
	ok(FileAccess.file_exists(P + ".bad"), "array JSON: .bad atualizado")

	# --- tipo errado vira padrão, chaves extras de outros módulos ficam
	f = FileAccess.open(P, FileAccess.WRITE)
	f.store_string('{"tray_enabled": "sim", "text_size": "grande", "meu_modulo": {"a": 1}, "ui_scale": 2}')
	f.close()
	var s8: Node = make()
	ok(s8.get_value("tray_enabled") == true, "tipo errado -> padrão (bool)")
	ok(is_equal_approx(float(s8.get_value("text_size")), 1.0), "tipo errado -> padrão (float)")
	ok(s8.get_value("meu_modulo")["a"] == 1, "chave desconhecida preservada")
	ok(s8.get_value("ui_scale") == 2, "ui_scale 2")

	# --- reset_all
	s8.reset_all()
	ok(s8.get_value("ui_scale") == "auto", "reset_all")

	# --- autoload real existe no /root (headless --script) e tem a API
	var real: Node = root.get_node_or_null("Settings")
	ok(real != null and real.has_method("get_value") and real.has_method("set_value") and real.has_signal("changed"), "autoload Settings presente")

	for n in [s, s2, s3, s4, s5, s6, s7, s8]:
		n.set_process(false)
		n._dirty = false
		n.free()
	clean()
	print("platform_settings: %d verificações, %d falhas" % [checks, fails])
	quit(1 if fails > 0 else 0)
