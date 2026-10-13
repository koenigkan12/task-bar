extends Node
## AudioManager (autoload): toda a API de áudio do jogo (docs/CONTRATOS.md, seção 4.5 e 8).
##
## - Silencioso até `unlock()` (ou a primeira entrada de mouse/teclado). Nada toca em `--headless`.
## - Modos (Settings "audio_mode"): "silent" nada; "ambient" ambiente + SFX baixos, rádio só em texto
##   (a estação do bunker, ligada pelo jogador, toca); "full" tudo.
## - SFX: pool de players, recarga por nome, no máximo N vozes por nome, jitter de pitch +-3%.
## - Loops: ambiente da sala, vento, noite e UM loop por tipo de máquina (volume sobe com a quantidade).
## - Estação do bunker: station_1..3 em sequência com crossfade, só quando ligada pelo jogador.
## - Conecta-se aos sinais de `Game` que existirem (`has_signal`), então funciona com o stub atual.
## A lógica de seleção (nomes -> arquivos, modos, loops desejados) é testável sem tocar:
## ver `tests/audio_manager_test.gd` e `record_plan`.

const SFX_DIR := "res://assets/audio/sfx/"
const LOOP_DIR := "res://assets/audio/loops/"
const MUSIC_DIR := "res://assets/audio/music/"

const MODE_SILENT := "silent"
const MODE_AMBIENT := "ambient"
const MODE_FULL := "full"
const MODES: PackedStringArray = ["silent", "ambient", "full"]

const SFX_NAMES: PackedStringArray = [
	"click", "hover", "buy", "hammer_1", "hammer_2", "hammer_3", "dig", "knock", "scrap", "harvest",
	"pour", "radio_on", "tune", "blip", "error", "step_1", "step_2", "hatch_open", "page", "place", "switch"]
## amb_night é um acréscimo ao contrato (loop de noite, seção 8).
const LOOP_NAMES: PackedStringArray = [
	"amb_room", "bike", "windmill", "battery", "pump", "conveyor", "greenhouse", "solar", "drip",
	"wind_surface", "static", "amb_night"]
const MUSIC_NAMES: PackedStringArray = [
	"far", "18h", "numbers", "station_1", "station_2", "station_3", "epilogue", "her_voice"]
const STATION_TRACKS: PackedStringArray = ["station_1", "station_2", "station_3"]

## Cues do rádio (`radio.json`) -> faixa em music/. "epilogue" é um cue extra (cena da chegada).
const CUE_MUSIC := {
	"music_far": "far", "music_18h": "18h", "numbers": "numbers", "voice_her": "her_voice", "epilogue": "epilogue",
}
const CUES: PackedStringArray = ["static", "tone", "music_far", "music_18h", "numbers", "voice_her", "epilogue", "none"]
const CUE_MUSIC_DB := {"far": -10.0, "18h": -10.0, "numbers": -12.0, "epilogue": -8.0, "her_voice": -4.0}
const STATIC_CUE_SECONDS := 4.0

## Item de máquina (id do catálogo) -> loop.
const MACHINE_LOOP := {
	"bicicleta": "bike", "moinho": "windmill", "bateria": "battery", "bomba": "pump",
	"esteira": "conveyor", "roldana": "conveyor", "estufa": "greenhouse", "painel": "solar",
	"gotejador": "drip", "cisterna": "drip",
}
const MACHINE_LOOP_NAMES: PackedStringArray = [
	"bike", "windmill", "battery", "pump", "conveyor", "greenhouse", "solar", "drip"]

## Volume base de cada loop (dB). Os arquivos estão em ~-14 LUFS (máquinas) e -20..-28 (ambientes).
const LOOP_DB := {
	"amb_room": -2.0, "amb_night": -2.0, "wind_surface": -2.0, "static": -10.0,
	"bike": -14.0, "windmill": -14.0, "battery": -12.0, "pump": -14.0, "conveyor": -14.0,
	"greenhouse": -8.0, "solar": -6.0, "drip": -8.0,
}
const COUNT_STEP_DB := 4.0     # +4 dB por dobro de máquinas iguais...
const COUNT_MAX_BOOST_DB := 8.0  # ...até +8 dB
const NIGHT_ROOM_DB := -8.0
const NIGHT_MACHINE_DB := -3.0
const SILENT_DB := -60.0
const LOOP_FADE := 1.6

const SFX_BUS := {"radio_on": "Radio", "tune": "Radio", "blip": "Radio", "click": "UI", "hover": "UI",
	"buy": "UI", "error": "UI", "page": "UI", "switch": "UI"}
## Os arquivos têm todos pico -6 dBFS; o nível relativo é daqui.
const SFX_GAIN_DB := {
	"click": -12.0, "hover": -18.0, "buy": -4.0, "hammer_1": -6.0, "hammer_2": -6.0, "hammer_3": -6.0,
	"dig": -6.0, "knock": -4.0, "scrap": -6.0, "harvest": -8.0, "pour": -8.0, "radio_on": -4.0, "tune": -6.0,
	"blip": -6.0, "error": -8.0, "step_1": -12.0, "step_2": -12.0, "hatch_open": -4.0, "page": -8.0,
	"place": -6.0, "switch": -10.0,
}
const AMBIENT_MODE_SFX_DB := -4.0   # SFX do mundo ficam mais baixos no modo ambiente
const SFX_COOLDOWN := {"click": 0.03, "hover": 0.08, "harvest": 0.3, "step_1": 0.2, "step_2": 0.2, "scrap": 0.12}
const DEFAULT_COOLDOWN := 0.05
const SFX_MAX_VOICES := 2
const POOL_SIZE := 12
const PITCH_JITTER := 0.03

const STATION_DB := -12.0
const STATION_DUCK_DB := -8.0     # a estação abaixa enquanto um cue de música toca
const STATION_XFADE := 5.0

var _mode: String = MODE_AMBIENT
var _master: float = 0.8
var _unlocked: bool = false
var _station_on: bool = false
var _station_index: int = 0
var _headless: bool = false

var _settings: Node = null
var _game: Node = null

var _pool: Array[AudioStreamPlayer] = []
var _pool_name: Array[String] = []
var _last_sfx: Dictionary = {}
var _last_hammer: String = ""
var _cache: Dictionary = {}

var _loop_players: Dictionary = {}
var _loop_tweens: Dictionary = {}
var _loop_plan: Dictionary = {}

var _st_a: AudioStreamPlayer = null
var _st_b: AudioStreamPlayer = null
var _st_cur: AudioStreamPlayer = null
var _st_tween: Tween = null
var _cue_player: AudioStreamPlayer = null
var _cue_name: String = ""
var _cue_tween: Tween = null
var _static_token: int = 0

var _night_poll: float = 0.0
var _was_night: bool = false

## Para testes: registra o que TOCARIA (mesmo em headless / silencioso por modo).
var record_plan: bool = false
var plan: Array[Dictionary] = []


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
		_pool_name.append("")
	_st_a = _make_player("Radio")
	_st_b = _make_player("Radio")
	_cue_player = _make_player("Radio")
	_cue_player.finished.connect(_on_cue_finished)
	bind_settings(get_node_or_null("/root/Settings"))
	bind_game(get_node_or_null("/root/Game"))
	_apply_master()
	refresh_machine_loops()


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


# ============================================================================ API pública
func set_mode(mode: String) -> void:
	if not MODES.has(mode):
		push_warning("AudioManager: modo inválido '%s'" % mode)
		return
	if mode == _mode:
		return
	_mode = mode
	_sync_all()


func get_mode() -> String:
	return _mode


func set_master_volume(v: float) -> void:
	_master = clampf(v, 0.0, 1.0)
	_apply_master()


func get_master_volume() -> float:
	return _master


func is_unlocked() -> bool:
	return _unlocked


## Primeira interação: libera o som (padrão silencioso até lá).
func unlock() -> void:
	if _unlocked:
		return
	_unlocked = true
	if _settings != null and _settings.has_method("set_value") and _settings.has_method("get_value"):
		if not bool(_settings.call("get_value", "sound_unlocked", false)):
			_settings.call("set_value", "sound_unlocked", true)
	_sync_all()


func play_sfx(sfx_name: String, volume_db: float = 0.0) -> void:
	if not SFX_NAMES.has(sfx_name):
		push_warning("AudioManager: sfx desconhecido '%s'" % sfx_name)
		return
	if not sfx_allowed(sfx_name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var cd: float = float(SFX_COOLDOWN.get(sfx_name, DEFAULT_COOLDOWN))
	if now - float(_last_sfx.get(sfx_name, -100.0)) < cd:
		return
	if _voices_of(sfx_name) >= SFX_MAX_VOICES:
		return
	_last_sfx[sfx_name] = now
	var db := sfx_gain_db(sfx_name) + volume_db
	_record({"kind": "sfx", "name": sfx_name, "bus": sfx_bus(sfx_name), "db": db})
	if not _can_play():
		return
	var idx := _free_pool_index()
	if idx < 0:
		return
	var stream := _load_stream(SFX_DIR + sfx_name + ".ogg", false)
	if stream == null:
		return
	var p := _pool[idx]
	p.stream = stream
	p.bus = sfx_bus(sfx_name)
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER)
	_pool_name[idx] = sfx_name
	p.play()


func play_radio_cue(cue: String) -> void:
	if cue == "" or cue == "none":
		return
	if not CUES.has(cue):
		push_warning("AudioManager: cue desconhecido '%s'" % cue)
		return
	if not cue_allowed():
		return
	_record({"kind": "cue", "name": cue})
	match cue:
		"tone":
			play_sfx("blip")
		"static":
			_play_static_cue()
		_:
			_play_cue_music(String(CUE_MUSIC[cue]))


func set_station(on: bool) -> void:
	if on == _station_on:
		return
	_station_on = on
	_sync_station()


func station_next() -> void:
	_station_index = (_station_index + 1) % STATION_TRACKS.size()
	_record({"kind": "station_next", "name": STATION_TRACKS[_station_index]})
	if _station_on and station_allowed():
		_station_play(STATION_TRACKS[_station_index])
	_sync_station_plan()


func is_station_on() -> bool:
	return _station_on


func station_track() -> String:
	return STATION_TRACKS[_station_index]


## Lê `Game.instances()` e liga/desliga um loop por tipo de máquina (volume pela quantidade).
func refresh_machine_loops() -> void:
	var inst: Array = []
	var night := false
	if _game != null:
		if _game.has_method("instances"):
			var v: Variant = _game.call("instances")
			if v is Array:
				inst = v
		if _game.has_method("is_night"):
			night = bool(_game.call("is_night"))
	_was_night = night
	_set_loop_plan(compute_loops(inst, night))


# ============================================================================ regras puras (testáveis)
func sfx_bus(sfx_name: String) -> String:
	return String(SFX_BUS.get(sfx_name, "Ambient"))


func sfx_gain_db(sfx_name: String) -> float:
	var db: float = float(SFX_GAIN_DB.get(sfx_name, 0.0))
	if _mode == MODE_AMBIENT and sfx_bus(sfx_name) != "UI":
		db += AMBIENT_MODE_SFX_DB
	return db


## SFX liberado? Precisa de unlock e modo != silent; no modo ambiente o rádio fica só em texto.
func sfx_allowed(sfx_name: String) -> bool:
	if not _unlocked or _mode == MODE_SILENT:
		return false
	if _mode == MODE_AMBIENT and sfx_bus(sfx_name) == "Radio":
		return false
	return true


func cue_allowed() -> bool:
	return _unlocked and _mode == MODE_FULL


func loops_allowed() -> bool:
	return _unlocked and _mode != MODE_SILENT


func station_allowed() -> bool:
	return _unlocked and _mode != MODE_SILENT


## Loops desejados {nome: dB} só pelo estado do jogo (sem considerar modo). SILENT_DB = desligado.
func compute_loops(instances: Array, night: bool) -> Dictionary:
	var out: Dictionary = {}
	out["amb_room"] = float(LOOP_DB["amb_room"]) + (NIGHT_ROOM_DB if night else 0.0)
	out["amb_night"] = float(LOOP_DB["amb_night"]) if night else SILENT_DB
	out["wind_surface"] = float(LOOP_DB["wind_surface"]) + (-4.0 if night else 0.0)
	var counts: Dictionary = {}
	for e in instances:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		if String(d.get("state", "ready")) != "ready":
			continue
		var lp := String(MACHINE_LOOP.get(String(d.get("item", "")), ""))
		if lp != "":
			counts[lp] = int(counts.get(lp, 0)) + 1
	for lp in MACHINE_LOOP_NAMES:
		var n: int = int(counts.get(lp, 0))
		if n <= 0:
			out[lp] = SILENT_DB
		else:
			var boost := minf(COUNT_MAX_BOOST_DB, COUNT_STEP_DB * (log(float(n)) / log(2.0)))
			out[lp] = float(LOOP_DB[lp]) + boost + (NIGHT_MACHINE_DB if night else 0.0)
	return out


## Plano de loops efetivo (considera unlock e modo): tudo SILENT_DB se não pode tocar.
func loop_plan() -> Dictionary:
	return _loop_plan.duplicate()


# ============================================================================ ligações
func bind_settings(settings: Node) -> void:
	if _settings != null and _settings.has_signal("changed") and _settings.is_connected("changed", _on_setting_changed):
		_settings.disconnect("changed", _on_setting_changed)
	_settings = settings
	if _settings == null:
		return
	if _settings.has_signal("changed"):
		_settings.connect("changed", _on_setting_changed)
	if _settings.has_method("get_value"):
		var m: Variant = _settings.call("get_value", "audio_mode", MODE_AMBIENT)
		if m is String and MODES.has(m):
			_mode = m
		var v: Variant = _settings.call("get_value", "master_volume", 0.8)
		if v is float or v is int:
			_master = clampf(float(v), 0.0, 1.0)
	_apply_master()


func bind_game(game: Node) -> void:
	if _game != null:
		for pair in _signal_table():
			var sg := String(pair[0])
			var c: Callable = pair[1]
			if _game.has_signal(sg) and _game.is_connected(sg, c):
				_game.disconnect(sg, c)
	_game = game
	if _game == null:
		return
	for pair in _signal_table():
		var sg := String(pair[0])
		var c: Callable = pair[1]
		if _game.has_signal(sg) and not _game.is_connected(sg, c):
			_game.connect(sg, c)
	refresh_machine_loops()


func _signal_table() -> Array:
	return [
		["item_placed", _on_item_placed], ["item_finished", _on_item_finished],
		["item_removed", _on_item_removed], ["visit_happened", _on_visit_happened],
		["radio_line", _on_radio_line], ["antenna_changed", _on_antenna_changed],
		["arrival_started", _on_arrival_started], ["plot_harvested", _on_plot_harvested],
		["room_dug", _on_room_dug], ["welcome_back", _on_welcome_back],
		["game_loaded", _on_game_reset], ["new_game_started", _on_game_reset],
	]


func _on_setting_changed(key: String) -> void:
	if _settings == null or not _settings.has_method("get_value"):
		return
	if key == "audio_mode":
		var m: Variant = _settings.call("get_value", "audio_mode", MODE_AMBIENT)
		if m is String:
			set_mode(m)
	elif key == "master_volume":
		var v: Variant = _settings.call("get_value", "master_volume", 0.8)
		if v is float or v is int:
			set_master_volume(float(v))


# ============================================================================ reação aos sinais de Game
func _on_item_placed(_id: int) -> void:
	var hammers: Array[String] = ["hammer_1", "hammer_2", "hammer_3"]
	hammers.erase(_last_hammer)
	_last_hammer = hammers[randi() % hammers.size()]
	play_sfx(_last_hammer)
	_after(0.55, func() -> void: play_sfx("hammer_%d" % (1 + randi() % 3)))
	refresh_machine_loops()


func _on_item_finished(_id: int, _item: String) -> void:
	play_sfx("place")
	refresh_machine_loops()


func _on_item_removed(_id: int) -> void:
	refresh_machine_loops()


func _on_game_reset() -> void:
	refresh_machine_loops()


func _on_visit_happened(info: Dictionary) -> void:
	play_sfx("knock")
	if int(info.get("units", 1)) > 0 or int(info.get("scrap", 1)) > 0:
		_after(0.6, func() -> void: play_sfx("scrap"))


func _on_radio_line(line: Dictionary) -> void:
	play_radio_cue(String(line.get("cue", "none")))


func _on_antenna_changed(_level: int) -> void:
	play_sfx("tune")


func _on_arrival_started() -> void:
	play_sfx("hatch_open")
	_after(1.6, func() -> void: play_radio_cue("epilogue"))


func _on_plot_harvested(_id: int) -> void:
	play_sfx("harvest")


func _on_room_dug(_room: int) -> void:
	play_sfx("dig")


func _on_welcome_back(_summary: Dictionary) -> void:
	play_sfx("page")


func _after(seconds: float, fn: Callable) -> void:
	if is_inside_tree():
		get_tree().create_timer(seconds).timeout.connect(fn)


# ============================================================================ sincronização geral
func _sync_all() -> void:
	_apply_master()
	if not loops_allowed():
		_stop_cue()
	refresh_machine_loops()
	_sync_station()


func _apply_master() -> void:
	var i := AudioServer.get_bus_index("Master")
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(_master, 0.0001)))
	AudioServer.set_bus_mute(i, _master <= 0.001)


func _ensure_buses() -> void:
	for b in ["Radio", "Ambient", "UI"]:
		if AudioServer.get_bus_index(b) < 0:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


func _can_play() -> bool:
	return not _headless and _unlocked and _mode != MODE_SILENT


func _record(entry: Dictionary) -> void:
	if record_plan:
		plan.append(entry)
		if plan.size() > 512:
			plan.pop_front()


func _load_stream(path: String, looped: bool) -> AudioStream:
	var s: AudioStream = _cache.get(path) as AudioStream
	if s == null:
		if not ResourceLoader.exists(path):
			push_warning("AudioManager: arquivo ausente " + path)
			return null
		s = load(path) as AudioStream
		if s == null:
			return null
		_cache[path] = s
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = looped
	return s


func _voices_of(sfx_name: String) -> int:
	var n := 0
	for i in _pool.size():
		if _pool[i].playing and _pool_name[i] == sfx_name:
			n += 1
	return n


func _free_pool_index() -> int:
	for i in _pool.size():
		if not _pool[i].playing:
			return i
	return -1


# ============================================================================ loops
func _set_loop_plan(raw: Dictionary) -> void:
	var eff: Dictionary = {}
	var ok := loops_allowed()
	for k in raw.keys():
		eff[k] = float(raw[k]) if ok else SILENT_DB
	_loop_plan = eff
	if not _can_play():
		# headless/silencioso: derruba o que estiver tocando, sem criar nada novo
		for k in _loop_players.keys():
			_fade_loop(String(k), SILENT_DB)
		return
	for k in eff.keys():
		_fade_loop(String(k), float(eff[k]))


func _loop_bus(loop_name: String) -> String:
	return "Radio" if loop_name == "static" else "Ambient"


func _fade_loop(loop_name: String, target_db: float) -> void:
	var p: AudioStreamPlayer = _loop_players.get(loop_name) as AudioStreamPlayer
	if target_db <= SILENT_DB + 0.5:
		if p == null or not p.playing:
			return
	if p == null:
		p = _make_player(_loop_bus(loop_name))
		_loop_players[loop_name] = p
	if _loop_tweens.has(loop_name):
		var old: Tween = _loop_tweens[loop_name] as Tween
		if old != null and old.is_valid():
			old.kill()
	if target_db <= SILENT_DB + 0.5:
		var t := create_tween()
		t.tween_property(p, "volume_db", SILENT_DB, LOOP_FADE)
		t.tween_callback(p.stop)
		_loop_tweens[loop_name] = t
		return
	if not p.playing:
		var s := _load_stream(LOOP_DIR + loop_name + ".ogg", true)
		if s == null:
			return
		p.stream = s
		p.volume_db = SILENT_DB
		p.play(randf() * maxf(s.get_length() - 0.1, 0.0))  # desfasa os loops entre si
	var t2 := create_tween()
	t2.tween_property(p, "volume_db", target_db, LOOP_FADE)
	_loop_tweens[loop_name] = t2


# ============================================================================ cues de rádio
func _play_cue_music(track: String) -> void:
	_cue_name = track
	_record({"kind": "cue_music", "name": track, "db": float(CUE_MUSIC_DB.get(track, -10.0))})
	if not _can_play():
		return
	var s := _load_stream(MUSIC_DIR + track + ".ogg", false)
	if s == null:
		return
	_static_token += 1
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_player.stop()
	_cue_player.stream = s
	_cue_player.volume_db = SILENT_DB
	_cue_player.play()
	_cue_tween = create_tween()
	_cue_tween.tween_property(_cue_player, "volume_db", float(CUE_MUSIC_DB.get(track, -10.0)), 1.2)
	_update_station_duck()


func _play_static_cue() -> void:
	_cue_name = "static"
	_record({"kind": "cue_music", "name": "static", "db": float(LOOP_DB["static"])})
	if not _can_play():
		return
	var s := _load_stream(LOOP_DIR + "static.ogg", true)
	if s == null:
		return
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_player.stop()
	_cue_player.stream = s
	_cue_player.volume_db = SILENT_DB
	_cue_player.play(randf() * 10.0)
	_static_token += 1
	var token := _static_token
	_cue_tween = create_tween()
	_cue_tween.tween_property(_cue_player, "volume_db", float(LOOP_DB["static"]), 0.4)
	_cue_tween.tween_interval(STATIC_CUE_SECONDS)
	_cue_tween.tween_property(_cue_player, "volume_db", SILENT_DB, 0.8)
	_cue_tween.tween_callback(func() -> void:
		if token == _static_token:
			_stop_cue())
	_update_station_duck()


func _stop_cue() -> void:
	_cue_name = ""
	_static_token += 1
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	if _cue_player != null:
		_cue_player.stop()
	_update_station_duck()


func _on_cue_finished() -> void:
	_cue_name = ""
	_update_station_duck()


func current_cue() -> String:
	return _cue_name


# ============================================================================ estação do bunker
func _sync_station() -> void:
	if _station_on and station_allowed():
		if _st_cur == null or not _st_cur.playing:
			_station_play(STATION_TRACKS[_station_index])
	else:
		_station_stop()
	_sync_station_plan()


func _sync_station_plan() -> void:
	_record({"kind": "station", "on": _station_on and station_allowed(), "name": STATION_TRACKS[_station_index]})


func _station_target_db() -> float:
	return STATION_DB + (STATION_DUCK_DB if _cue_name != "" else 0.0)


func _update_station_duck() -> void:
	if _st_cur != null and _st_cur.playing:
		var t := create_tween()
		t.tween_property(_st_cur, "volume_db", _station_target_db(), 1.0)


func _station_play(track: String) -> void:
	if not _can_play():
		return
	var s := _load_stream(MUSIC_DIR + track + ".ogg", false)
	if s == null:
		return
	var nxt: AudioStreamPlayer = _st_b if _st_cur == _st_a else _st_a
	var prev: AudioStreamPlayer = _st_cur
	if _st_tween != null and _st_tween.is_valid():
		_st_tween.kill()
	nxt.stop()
	nxt.stream = s
	nxt.volume_db = SILENT_DB
	nxt.play()
	_st_cur = nxt
	_st_tween = create_tween().set_parallel(true)
	_st_tween.tween_property(nxt, "volume_db", _station_target_db(), STATION_XFADE if prev != null and prev.playing else 1.5)
	if prev != null and prev.playing:
		_st_tween.tween_property(prev, "volume_db", SILENT_DB, STATION_XFADE)
		_st_tween.chain().tween_callback(prev.stop)


func _station_stop() -> void:
	if _st_tween != null and _st_tween.is_valid():
		_st_tween.kill()
	for p in [_st_a, _st_b]:
		var pl := p as AudioStreamPlayer
		if pl != null and pl.playing:
			var t := create_tween()
			t.tween_property(pl, "volume_db", SILENT_DB, 0.8)
			t.tween_callback(pl.stop)
	_st_cur = null


# ============================================================================ processo
func _process(delta: float) -> void:
	# estação: perto do fim da faixa, emenda na próxima com crossfade
	if _st_cur != null and _st_cur.playing and _st_cur.stream != null:
		var left := _st_cur.stream.get_length() - _st_cur.get_playback_position()
		if left <= STATION_XFADE:
			_station_index = (_station_index + 1) % STATION_TRACKS.size()
			_station_play(STATION_TRACKS[_station_index])
	# dia/noite: reavalia os loops quando vira
	_night_poll += delta
	if _night_poll >= 2.0:
		_night_poll = 0.0
		if _game != null and _game.has_method("is_night"):
			var n := bool(_game.call("is_night"))
			if n != _was_night:
				refresh_machine_loops()


func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		unlock()
