extends Node
## Autoload `Game`: dono de uma Sim, relógio de parede, catch-up offline, autosave e repasse de sinais.
## API = a da Sim (docs/CONTRATOS.md 4.3). Linha de comando: --demo (time_scale 6), --time-scale=<x>.

signal state_changed()
signal item_placed(instance_id: int)
signal item_finished(instance_id: int, item_id: String)
signal item_removed(instance_id: int)
signal room_dug(room: int)
signal antenna_changed(level: int)
signal radio_line(line: Dictionary)
signal diary_changed()
signal visit_happened(info: Dictionary)
signal plot_harvested(plot_id: int)
signal helped(instance_id: int)
signal box_state_changed(fill: float, overflow: bool)
signal welcome_back(summary: Dictionary)
signal house_item_bought(item_id: String)
signal arrival_started()
signal arrival_finished()
signal new_game_started()
signal game_loaded()

const AUTOSAVE_S := 60.0
const STATE_INTERVAL_S := 0.25
const SUSPEND_GAP_S := 120.0

var sim: Sim
var in_game: bool = false
var time_scale: float = 1.0
var save_path: String = Save.DEFAULT_PATH

var _dirty: bool = false
var _state_timer: float = 0.0
var _save_timer: float = 0.0
var _last_unix: float = 0.0


func _init() -> void:
	# a Sim existe desde o _init: a API do Game funciona mesmo antes do _ready de quem chama
	Balance.load_all()
	sim = Sim.new()
	_connect_sim()


func _ready() -> void:
	time_scale = Balance.num("time.time_scale", 1.0)
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--demo":
			time_scale = 6.0
		elif a.begins_with("--time-scale="):
			var x := a.substr(13).to_float()
			if x > 0.0:
				time_scale = x
	_last_unix = Time.get_unix_time_from_system()


func _connect_sim() -> void:
	sim.state_changed.connect(func() -> void: _dirty = true)
	sim.item_placed.connect(func(i: int) -> void: item_placed.emit(i))
	sim.item_finished.connect(func(i: int, it: String) -> void: item_finished.emit(i, it))
	sim.item_removed.connect(func(i: int) -> void: item_removed.emit(i))
	sim.room_dug.connect(func(r: int) -> void: room_dug.emit(r))
	sim.antenna_changed.connect(func(l: int) -> void: antenna_changed.emit(l))
	sim.radio_line.connect(func(d: Dictionary) -> void: radio_line.emit(d))
	sim.diary_changed.connect(func() -> void: diary_changed.emit())
	sim.visit_happened.connect(func(d: Dictionary) -> void: visit_happened.emit(d))
	sim.plot_harvested.connect(func(p: int) -> void: plot_harvested.emit(p))
	sim.helped.connect(func(i: int) -> void: helped.emit(i))
	sim.box_state_changed.connect(func(f: float, o: bool) -> void: box_state_changed.emit(f, o))
	sim.house_item_bought.connect(func(i: String) -> void: house_item_bought.emit(i))
	sim.arrival_started.connect(func() -> void: arrival_started.emit())
	sim.arrival_finished.connect(func() -> void: arrival_finished.emit())


# ================================================================ relógio de parede
func _process(delta: float) -> void:
	if not in_game:
		return
	var now := Time.get_unix_time_from_system()
	var gap := now - _last_unix
	_last_unix = now
	if gap > SUSPEND_GAP_S and gap > delta * 4.0 + 5.0:
		# suspensão/hibernação: mesmo caminho do offline
		var summary := sim.catch_up((gap - delta) / 60.0 * Balance.num("time.time_scale", 1.0))
		_after_catch_up(summary)
	sim.advance(delta * time_scale / 60.0)
	_state_timer += delta
	if _dirty and _state_timer >= STATE_INTERVAL_S:
		_dirty = false
		_state_timer = 0.0
		state_changed.emit()
	_save_timer += delta
	if _save_timer >= AUTOSAVE_S:
		save_game()


func _after_catch_up(summary: Dictionary) -> void:
	_dirty = true
	if bool(summary.get("shown", false)):
		welcome_back.emit(summary)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_EXIT_TREE:
		if in_game:
			save_game()


# ================================================================ ciclo de vida
func has_save() -> bool:
	return Save.exists(save_path)


func new_game() -> void:
	var t := Time.get_time_dict_from_system()
	var tod: float = float(t["hour"]) + float(t["minute"]) / 60.0
	var wake: float = Balance.num("time.awake_from_min", 360.0) / 60.0
	var sleep_h: float = Balance.num("time.awake_to_min", 1320.0) / 60.0
	if tod < wake or tod > sleep_h - 1.0:
		tod = -1.0  # de noite: a Sim usa a hora de partida padrão (manhã)
	sim.new_game(int(Time.get_ticks_usec()) ^ int(Time.get_unix_time_from_system()), tod)
	in_game = true
	_last_unix = Time.get_unix_time_from_system()
	_save_timer = 0.0
	_dirty = true
	new_game_started.emit()


func load_game() -> bool:
	var r := Save.read(save_path)
	if not bool(r["ok"]) or not sim.from_dict(r["sim"] as Dictionary):
		return false
	var now := Time.get_unix_time_from_system()
	var elapsed_s := maxf(0.0, now - float(r["saved_unix"]))  # relógio que voltou no tempo: ignora
	var summary := sim.catch_up(elapsed_s / 60.0 * Balance.num("time.time_scale", 1.0))
	in_game = true
	_last_unix = now
	_save_timer = 0.0
	_dirty = true
	game_loaded.emit()
	if bool(summary.get("shown", false)):
		welcome_back.emit(summary)
	if sim.arrival_pending():
		arrival_started.emit()  # o final ficou pendente (ou chegou enquanto estava fora)
	return true


## Resumo do save sem carregá-lo (título): {day, antenna}; vazio se não há save.
func save_summary() -> Dictionary:
	var r := Save.read(save_path)
	if not bool(r["ok"]):
		return {}
	var d: Dictionary = r["sim"]
	return {"day": int(floorf((float(d.get("start_min", 0.0)) + float(d.get("t_min", 0.0))) / 1440.0)) + 1,
			"antenna": int(d.get("antenna", 1))}


func save_game() -> void:
	if sim == null:
		return
	Save.write(sim.to_dict(), Time.get_unix_time_from_system(), save_path)
	_save_timer = 0.0


func delete_save() -> void:
	Save.delete(save_path)


func set_time_scale(x: float) -> void:
	time_scale = maxf(0.0, x)


func finish_arrival() -> void:
	sim.finish_arrival()


# ================================================================ consultas (delegam à Sim)
func sucata() -> int: return sim.sucata()
func antenna() -> int: return sim.antenna()
func rooms() -> int: return sim.rooms()
func tod_hours() -> float: return sim.tod_hours()
func day_index() -> int: return sim.day_index()
func is_awake() -> bool: return sim.is_awake()
func is_night() -> bool: return sim.is_night()
func busy() -> float: return sim.busy()
func hungry() -> bool: return sim.hungry()
func power_supply() -> int: return sim.power_supply()
func power_demand() -> int: return sim.power_demand()
func power_ok() -> bool: return sim.power_ok()
func box_stock() -> float: return sim.box_stock()
func box_capacity() -> int: return sim.box_capacity()
func box_fill() -> float: return sim.box_fill()
func contact_made() -> bool: return sim.contact_made()
func arrived() -> bool: return sim.arrived()
func stats() -> Dictionary: return sim.stats()

func instances() -> Array[Dictionary]: return sim.instances()
func fixed_objects(room: int) -> Array[Dictionary]: return sim.fixed_objects(room)
func plots() -> Array[Dictionary]: return sim.plots()
func help_available() -> bool: return sim.help_available()
func help_plots_available() -> bool: return sim.help_plots_available()
func help_box_available() -> bool: return sim.help_box_available()
func help_instance(instance_id: int) -> Dictionary: return sim.help_instance(instance_id)
func help_box_check() -> String: return sim.help_box_check()
func box_sale() -> Dictionary: return sim.box_sale()
func help_box_wait() -> Dictionary: return sim.help_box_wait()
func help_box() -> Dictionary: return sim.help_box()
func active_jobs() -> Array[Dictionary]: return sim.active_jobs()
func unlocked_behaviors() -> Array[String]: return sim.unlocked_behaviors()
func line_tiers() -> Dictionary: return sim.line_tiers()

func catalog(filter: String = "") -> Array[Dictionary]: return sim.catalog(filter)
func can_place(item_id: String, room: int, col: int) -> bool: return sim.can_place(item_id, room, col)
func placement_hints(item_id: String) -> Array[Dictionary]: return sim.placement_hints(item_id)
func can_buy(item_id: String, room: int = 0, col: int = -1) -> Dictionary: return sim.can_buy(item_id, room, col)
func buy(item_id: String, room: int, col: int) -> Dictionary: return sim.buy(item_id, room, col)
func dig_room() -> Dictionary: return sim.dig_room()
func antenna_info() -> Dictionary: return sim.antenna_info()
func upgrade_antenna() -> Dictionary: return sim.upgrade_antenna()
func demolish(instance_id: int) -> Dictionary: return sim.demolish(instance_id)
func move(instance_id: int, room: int, col: int) -> Dictionary: return sim.move(instance_id, room, col)
func available_crops(instance_id: int) -> Array[String]: return sim.available_crops(instance_id)
func crop_order(instance_id: int) -> String: return sim.crop_order(instance_id)
func set_instance_crop(instance_id: int, crop: String) -> void: sim.set_instance_crop(instance_id, crop)
func pin_goal(item_id: String) -> void: sim.pin_goal(item_id)
func pinned_goal() -> String: return sim.pinned_goal()
func goal_ready() -> bool: return sim.goal_ready()
func diary() -> Array[Dictionary]: return sim.diary()
func unread_count() -> int: return sim.unread_count()
func mark_diary_read() -> void: sim.mark_diary_read()
func house_status() -> Array[Dictionary]: return sim.house_status()
func journey() -> Dictionary: return sim.journey()
func arrival_line() -> Dictionary: return sim.arrival_line()
func debug_advance_minutes(m: float) -> void: sim.debug_advance_minutes(m)
