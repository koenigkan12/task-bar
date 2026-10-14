extends Node2D
## Entrada do protótipo da vila: carrega/salva, alcança o tempo fechado, liga a simulação à vista
## e à interface, câmera com zoom em degraus e arrastar, cliques no mundo e a janela de canto.
## Argumentos de teste (depois de "--"): --speed=N acelera o relógio; --fresh começa do zero;
## --hour=H começa na hora H; --shot=caminho.png tira uma captura e sai.

const SAVE := "user://vila.json"
const ZOOMS: Array[float] = [0.5, 1.0, 2.0]

var sim: VilaSim
var world: WorldView
var hud: VilaHud
var cam: Camera2D
var _bal: Dictionary
var _zoom_i: int = 1
var _press_pos: Vector2 = Vector2(-1, -1)
var _dragging: bool = false
var _placing: String = ""
var _save_acc: float = 0.0
var _speed: float = 1.0
var _clock_offset: float = 0.0     # só para testes (--hour)
var _shot: String = ""
var _shot_t: float = -1.0
var _test_cell: Vector2i = Vector2i(-1, -1)   # só para capturas: onde o fantasma aparece


func _ready() -> void:
	_bal = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	TranslationServer.set_locale("pt_BR")
	var args := _args()
	_speed = float(args.get("speed", "1"))
	_shot = String(args.get("shot", ""))
	var tz := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var now := _now()
	if args.has("hour"):
		var day0 := now - fposmod(now + tz, 86400.0)
		_clock_offset = day0 + float(args["hour"]) * 3600.0 - now
		now = _now()
	sim = VilaSim.new()
	var summary := {}
	if not args.has("fresh") and FileAccess.file_exists(SAVE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if d is Dictionary and int((d as Dictionary).get("v", 0)) == 1:
			sim.from_dict(d, _bal, tz)
			summary = sim.catch_up(now)
		else:
			sim.setup(_bal, now, tz)
	else:
		sim.setup(_bal, now, tz)
	if args.has("demo"):
		# Só para capturas: joga sozinho N minutos de jogo antes de mostrar.
		var mins := float(args["demo"])
		var el := 0.0
		while el < mins * 60.0:
			sim.advance(5.0)
			el += 5.0
			AutoPlayer.play(sim)
		_clock_offset += sim.t - now
	world = WorldView.new()
	add_child(world)
	world.setup(sim)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	var hatch := sim._first("hatch")
	cam.position = Vector2(Vector2i(hatch["cell"])) * 16.0 + Vector2(40, 8)
	_apply_zoom()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = VilaHud.new()
	layer.add_child(hud)
	hud.setup(sim)
	hud.build_chosen.connect(_start_placing)
	hud.zoom_step.connect(func(d: int) -> void: _set_zoom(_zoom_i + d, get_viewport().get_visible_rect().size / 2.0))
	hud.quit_pressed.connect(_quit)
	hud.window_drag.connect(func(d: Vector2i) -> void:
		var win := get_window()
		win.position += d)
	sim.tower_up.connect(func(n: int) -> void: hud.toast(hud.fmt("UI_TOWER_DONE", {"n": n})))
	sim.person_joined.connect(func(id: int) -> void: hud.toast(hud.fmt("UI_JOINED", {"name": hud.pname(sim.person(id))})))
	sim.building_done.connect(func(id: int) -> void:
		var b := sim.by_id(id)
		if not b.is_empty() and String(b["type"]) != "torre":
			hud.toast(hud.fmt("UI_DONE", {"b": hud.bname(String(b["type"]), int(b["level"]))})))
	sim.group_arrived.connect(func() -> void: hud.toast(hud.fmt("UI_GATE_BADGE", {"n": sim.gate_group.size()})))
	if not summary.is_empty():
		hud.show_welcome(summary)
	match String(args.get("open", "")):   # só para capturas
		"build": hud.show_build_menu()
		"tower": hud.show_tower()
		"gate":
			if sim.gate_group.is_empty():
				sim._make_group()
			hud.show_gate()
		"person": hud.show_person(int(sim.people[sim.people.size() - 1]["id"]))
		"place":
			_start_placing("horta")
			_test_cell = AutoPlayer.spot(sim, "horta")
	_place_window()
	if _shot != "":
		_shot_t = float(args.get("shot_after", "2.0"))


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


func _now() -> float:
	return Time.get_unix_time_from_system() + _clock_offset


## Janela de canto: grudada acima da barra de tarefas, à direita.
func _place_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	var scr := win.current_screen
	var r := DisplayServer.screen_get_usable_rect(scr)
	# Escala inteira maior que couber na tela (3× numa tela comum, 2× numa pequena).
	var base := Vector2i(384, 216)
	var k := clampi(mini((r.size.x - 16) / base.x, (r.size.y - 16) / base.y), 1, 3)
	win.size = base * k
	win.position = r.position + r.size - win.size - Vector2i(8, 8)


func _process(delta: float) -> void:
	if _speed != 1.0:
		_clock_offset += delta * (_speed - 1.0)
	var gap := _now() - sim.t
	if gap > 120.0:
		var s := sim.catch_up(_now())
		if not s.is_empty():
			hud.show_welcome(s)
	elif gap > 0.0:
		sim.advance(gap)
	_save_acc += delta
	if _save_acc >= float(_bal["time"]["save_every_s"]):
		_save_acc = 0.0
		_save()
	_update_hover()
	if _shot_t >= 0.0:
		_shot_t -= delta
		if _shot_t < 0.0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_shot)
			get_tree().quit()


func _save() -> void:
	if _speed != 1.0 or _clock_offset != 0.0:
		return   # sessões de teste não sobrescrevem o save de verdade
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(sim.to_dict()))


func _quit() -> void:
	_save()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()


# ================================================================ câmera
func _apply_zoom() -> void:
	var z := ZOOMS[_zoom_i]
	cam.zoom = Vector2(z, z)
	_clamp_cam()


func _set_zoom(i: int, screen_at: Vector2) -> void:
	i = clampi(i, 0, ZOOMS.size() - 1)
	if i == _zoom_i:
		return
	var before := _screen_to_world(screen_at)
	_zoom_i = i
	_apply_zoom()
	var after := _screen_to_world(screen_at)
	cam.position += before - after
	_clamp_cam()


func _clamp_cam() -> void:
	var view := get_viewport().get_visible_rect().size / cam.zoom
	var ws := world.world_size()
	var half := view / 2.0
	cam.position.x = clampf(cam.position.x, half.x, maxf(half.x, ws.x - half.x)) if view.x < ws.x else ws.x / 2.0
	cam.position.y = clampf(cam.position.y, half.y - 14.0 / cam.zoom.y, maxf(half.y, ws.y - half.y + 16.0 / cam.zoom.y)) if view.y < ws.y else ws.y / 2.0
	cam.position = cam.position.round()


func _screen_to_world(p: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * p


# ================================================================ entrada
func _start_placing(type: String) -> void:
	_placing = type
	world.ghost_type = type
	hud.close_card()
	hud.toast(tr("UI_PLACE"))


func _stop_placing() -> void:
	_placing = ""
	world.ghost_type = ""


func _update_hover() -> void:
	var mp := get_viewport().get_mouse_position()
	if _test_cell.x < 0 and hud.mouse_over_ui(mp):
		world.hover_cell = Vector2i(-1, -1)
		if _placing == "":
			hud.show_tip("", mp)
		return
	var wp := _screen_to_world(mp)
	var c := world.cell_at(wp) if _test_cell.x < 0 else _test_cell
	world.hover_cell = c
	world.ghost_cell = c
	if _placing != "" or _dragging:
		hud.show_tip("", mp)
		return
	var pid := world.person_at(wp)
	if pid >= 0:
		var p := sim.person(pid)
		hud.show_tip(hud.pname(p) + " · " + hud._doing_text(p), mp)
		return
	if sim.terrain_at(c) == VilaSim.T_RUBBLE:
		hud.show_tip(tr("B_entulho") + " · " + tr("UI_CLEAR"), mp)
		return
	var b := sim.building_at(c)
	if not b.is_empty():
		var t := hud.bname(String(b["type"]), int(b["level"]))
		if String(b["state"]) != "built":
			t += " · " + VilaHud.fmt_time(float(b["total"]) - float(b["progress"]))
		hud.show_tip(t, mp)
		return
	hud.show_tip("", mp)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom_i + 1, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom_i - 1, mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_stop_placing()
			hud.close_card()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				if hud.mouse_over_ui(mb.position):
					return
				_press_pos = mb.position
				_dragging = false
			else:
				if _press_pos.x >= 0.0 and not _dragging and mb.button_index == MOUSE_BUTTON_LEFT:
					_click(mb.position)
				_press_pos = Vector2(-1, -1)
				_dragging = false
	elif ev is InputEventMouseMotion and _press_pos.x >= 0.0:
		var mm := ev as InputEventMouseMotion
		if _dragging or mm.position.distance_to(_press_pos) > 3.0:
			_dragging = true
			cam.position -= mm.relative / cam.zoom
			_clamp_cam()
	elif ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_stop_placing()
		hud.close_card()


func _click(screen: Vector2) -> void:
	var wp := _screen_to_world(screen)
	var c := world.cell_at(wp)
	if _placing != "":
		var r := sim.build(_placing, c)
		if bool(r["ok"]):
			_stop_placing()
		elif String(r["reason"]) == "place":
			hud.toast(tr("UI_NO_SPACE"))
		else:
			hud.toast(tr("UI_MISSING").format({"list": ""}).strip_edges())
			_stop_placing()
		return
	var pid := world.person_at(wp)
	if pid >= 0:
		hud.show_person(pid)
		return
	var b := sim.building_at(c)
	if not b.is_empty():
		hud.show_building(int(b["id"]))
		return
	var gate := sim._first("gate")
	if not gate.is_empty() and Rect2i(Vector2i(gate["cell"]) - Vector2i(0, 1), Vector2i(3, 3)).has_point(c):
		if not sim.gate_group.is_empty():
			hud.show_gate()
		return
	if hud.card_open():
		hud.close_card()
		return
	var k := sim.terrain_at(c)
	if k == VilaSim.T_RUBBLE:
		hud.show_rubble(c)
	elif k == VilaSim.T_GROUND or k == VilaSim.T_STUMP:
		hud.show_build_menu()
