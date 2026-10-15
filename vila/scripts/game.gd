extends Node
## Autoload `Game`: dono da simulação da vila. Carrega/salva, anda o relógio, alcança o tempo fechado
## e repassa os acontecimentos como sinais (o AudioManager e a alça da janela escutam pelo nome).
## As telas do bunker (título, Opções) falam com ele por has_save/load_game/new_game/delete_save.
## Argumentos de teste (depois de "--"): --fresh começa do zero e pula o título; --hour=H começa na
## hora H; --speed=N acelera o relógio; --demo=MIN joga sozinho N minutos antes de mostrar.

signal sim_replaced                         # outra simulação no lugar (título, novo jogo, carregar)
signal game_loaded
signal new_game_started
signal welcome_back(summary: Dictionary)
signal state_changed
# Nomes que o AudioManager e a WindowHandle já conhecem do jogo do bunker:
signal item_placed(id: int)                 # obra ou melhoria começou
signal item_finished(id: int, item: String) # obra ou melhoria terminou
signal antenna_changed(level: int)          # a torre subiu
signal visit_happened(info: Dictionary)     # gente chegou ao portão
signal plot_harvested(id: int)              # alguém entregou comida no depósito
signal radio_line(line: Dictionary)
signal catch_up_progress(frac: float)       # alcançando o tempo fechado (0..1); 1 = terminou
signal arrival_started                      # ela chegou com a vila aberta (o AudioManager toca o epílogo)

const SAVE := "user://vila.json"
const SAVE_BAK := "user://vila.json.bak"   # o save anterior: se o atual estragar, volta dele
const SAVE_TMP := "user://vila.json.tmp"

## Prédio -> "item" que o AudioManager sabe tocar em loop (MACHINE_LOOP).
const LOOP_ITEM := {"poco": "bomba", "serraria": "esteira", "ferrovelho": "roldana", "horta": "gotejador"}

var sim: VilaSim
var bal: Dictionary
var args: Dictionary = {}
var tz: int = 0
var in_game: bool = false     # false no título: o relógio não anda e nada é salvo
var _speed: float = 1.0
var _clock_offset: float = 0.0
var _save_acc: float = 0.0
var _from_save: bool = false
var catching_up: bool = false


func _ready() -> void:
	bal = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	args = _parse_args()
	_speed = float(args.get("speed", "1"))
	tz = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	if args.has("hour"):
		var now := now_unix()
		var day0 := now - fposmod(now + tz, 86400.0)
		_clock_offset = day0 + float(args["hour"]) * 3600.0 - now
	prepare_title()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


func now_unix() -> float:
	return Time.get_unix_time_from_system() + _clock_offset


## Sessão de teste (relógio mexido): não grava por cima do save de verdade.
func is_test_session() -> bool:
	return _speed != 1.0 or _clock_offset != 0.0 or args.has("fresh") or args.has("demo")


# ================================================================ API das telas
func has_save() -> bool:
	return not args.has("fresh") and (FileAccess.file_exists(SAVE) or FileAccess.file_exists(SAVE_BAK))


## Lê o save; se estiver estragado (arquivo cortado, JSON quebrado), tenta a cópia anterior.
func _read_save() -> Dictionary:
	for path in [SAVE, SAVE_BAK]:
		if not FileAccess.file_exists(path):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and int((d as Dictionary).get("v", 0)) == 2:
			if path == SAVE_BAK:
				push_warning("save principal estragado; usando a cópia anterior")
			return d
	return {}


## Resumo do save para o título: {day, antenna}. O título soma 1 ao dia.
func save_summary() -> Dictionary:
	if not has_save() or sim == null or not _from_save:
		return {}
	return {"day": sim.day_number() - 1, "antenna": sim.tower}


## Título: mostra a vila salva parada ao fundo (ou a barraca de um jogo novo).
func prepare_title() -> void:
	in_game = false
	_from_save = false
	if has_save():
		var d := _read_save()
		if not d.is_empty():
			_set_sim(VilaSim.new())
			sim.from_dict(d, bal, tz)
			_from_save = true
	if not _from_save:
		_set_sim(VilaSim.new())
		sim.setup(bal, now_unix(), tz)
	if args.has("hour"):   # testes e capturas: a vila começa nessa hora
		sim.set_cycle_hour(float(args["hour"]))
	sim_replaced.emit()


func load_game() -> bool:
	if not _from_save:
		return false
	in_game = true
	game_loaded.emit()
	_catch_up_async()
	return true


## Alcança o tempo fechado aos pedaços, sem travar a janela: ~1 h de vila por quadro.
func _catch_up_async() -> void:
	if catching_up:
		return
	var ctx := sim.catch_up_start(now_unix())
	if ctx.is_empty():
		return
	catching_up = true
	var s0 := sim
	catch_up_progress.emit(0.0)
	while true:
		var done := sim.catch_up_chunk(ctx, 3600.0)
		catch_up_progress.emit(1.0 - float(ctx["left"]) / maxf(1.0, float(ctx["seconds"])))
		if done:
			break
		await get_tree().process_frame
		if sim != s0:   # trocou de jogo no meio (título, novo jogo)
			catching_up = false
			return
	var summary := sim.catch_up_finish(ctx, now_unix())
	catching_up = false
	catch_up_progress.emit(1.0)
	welcome_back.emit(summary)


func new_game() -> void:
	_set_sim(VilaSim.new())
	sim.setup(bal, now_unix(), tz)
	if args.has("hour"):
		sim.set_cycle_hour(float(args["hour"]))
	_from_save = false
	if args.has("demo"):
		var mins := float(args["demo"])
		var el := 0.0
		while el < mins * 60.0:
			sim.advance(5.0)
			el += 5.0
			AutoPlayer.play(sim)
		_clock_offset += sim.t - now_unix()
	in_game = true
	sim_replaced.emit()
	new_game_started.emit()
	save_game()


func save_game() -> void:
	if sim == null or not in_game or is_test_session():
		return
	# Grava num arquivo à parte e só troca quando terminou: se o PC desligar no meio, o save
	# de antes continua inteiro. O anterior vira a cópia de segurança.
	var txt := JSON.stringify(sim.to_dict())
	var f := FileAccess.open(SAVE_TMP, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(txt)
	f.close()
	var dir := DirAccess.open("user://")
	if FileAccess.file_exists(SAVE):
		dir.rename(SAVE.trim_prefix("user://"), SAVE_BAK.trim_prefix("user://"))
	dir.rename(SAVE_TMP.trim_prefix("user://"), SAVE.trim_prefix("user://"))


func delete_save() -> void:
	for path in [SAVE, SAVE_BAK, SAVE_TMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_from_save = false


## Prédios prontos como "instâncias" para os loops do AudioManager.
func instances() -> Array:
	var out: Array = []
	if sim == null or not in_game:
		return out
	for b in sim.buildings:
		var item := String(LOOP_ITEM.get(String(b["type"]), ""))
		if item != "":
			out.append({"id": b["id"], "item": item, "state": "ready" if String(b["state"]) == "built" else "site"})
	return out


## Para a luz da aba recolhida: a torre pode subir.
func goal_ready() -> bool:
	if sim == null or not in_game:
		return false
	var g := sim.goal()
	return String(g.get("kind", "")) == "tower" and (g.get("missing", {}) as Dictionary).is_empty()


## Para a luz da aba recolhida: gente esperando no portão.
func unread_count() -> int:
	return 1 if sim != null and in_game and not sim.gate_group.is_empty() else 0


func is_night() -> bool:
	return sim != null and sim.is_night()


# ================================================================ relógio
func _process(delta: float) -> void:
	if sim == null or not in_game or catching_up:
		return
	if _speed != 1.0:
		_clock_offset += delta * (_speed - 1.0)
	var gap := now_unix() - sim.t
	if gap > 120.0:
		_catch_up_async()
	elif gap > 0.0:
		sim.advance(gap)
	_save_acc += delta
	if _save_acc >= float(bal["time"]["save_every_s"]):
		_save_acc = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _set_sim(s: VilaSim) -> void:
	sim = s
	sim.site_started.connect(func(id: int) -> void: item_placed.emit(id))
	sim.building_done.connect(func(id: int) -> void:
		var b := sim.by_id(id)
		item_finished.emit(id, String(LOOP_ITEM.get(String(b.get("type", "")), String(b.get("type", ""))))))
	sim.tower_up.connect(func(n: int) -> void: antenna_changed.emit(n))
	sim.group_arrived.connect(func() -> void: visit_happened.emit({"units": 0, "scrap": 0}))
	sim.person_joined.connect(func(_id: int) -> void: visit_happened.emit({"units": 0, "scrap": 0}))
	sim.harvested.connect(func(id: int, res: String, _n: int) -> void:
		if res == "comida":
			plot_harvested.emit(id))
	sim.changed.connect(func() -> void: state_changed.emit())
	sim.radio.connect(func(l: Dictionary) -> void:
		if not sim.offline and in_game:
			radio_line.emit(l))
	sim.ela_arrived.connect(func() -> void:
		if not sim.offline and in_game:
			arrival_started.emit())
