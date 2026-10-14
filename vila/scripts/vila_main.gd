extends Node2D
## Fluxo da vila: título (a vila parada ao fundo) -> jogo. Liga a simulação do autoload Game à vista
## e à interface: câmera com zoom em degraus e arrastar, cliques no mundo, Opções por cima.
## A janela (tamanho, posição, aba recolhida, bandeja) é do WindowService; o save, do Game.
## Argumentos de teste ficam no Game; aqui só: --open=build|tower|gate|person|place abre um cartão,
## --shot=caminho.png tira uma captura e sai, --shot_after=s espera antes.

const ZOOMS: Array[float] = [0.5, 1.0, 2.0]

var sim: VilaSim
var world: WorldView
var hud: VilaHud
var cam: Camera2D
var _layer: CanvasLayer
var _title: TitleScreen
var _options: OptionsScreen
var _zoom_i: int = 1
var _press_pos: Vector2 = Vector2(-1, -1)
var _dragging: bool = false
var _placing: String = ""
var _shot: String = ""
var _shot_t: float = -1.0
var _test_cell: Vector2i = Vector2i(-1, -1)   # só para capturas: onde o fantasma aparece


func _ready() -> void:
	world = WorldView.new()
	add_child(world)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	_layer = CanvasLayer.new()
	add_child(_layer)
	Game.sim_replaced.connect(_bind_sim)
	AudioManager.set_station(true)
	Game.welcome_back.connect(func(s: Dictionary) -> void:
		if hud != null:
			hud.show_welcome(s))
	var args: Dictionary = Game.args
	_shot = String(args.get("shot", ""))
	_bind_sim()
	if args.has("fresh") or args.has("play"):
		if not (args.has("play") and Game.load_game()):
			Game.new_game()
		_enter_game()
	else:
		_show_title()
	if _shot != "":
		_shot_t = float(args.get("shot_after", "2.0"))


## Outra simulação no lugar (título, novo jogo): refaz a vista e a interface.
func _bind_sim() -> void:
	sim = Game.sim
	_stop_placing()
	world.setup(sim)
	var hatch := sim._first("hatch")
	cam.position = Vector2(Vector2i(hatch["cell"])) * 16.0 + Vector2(40, 8)
	_apply_zoom()
	if hud != null:
		hud.queue_free()
		hud = null
	if Game.in_game:
		_make_hud()


func _make_hud() -> void:
	hud = VilaHud.new()
	_layer.add_child(hud)
	hud.setup(sim)
	hud.build_chosen.connect(_start_placing)
	hud.zoom_step.connect(func(d: int) -> void: _set_zoom(_zoom_i + d, get_viewport().get_visible_rect().size / 2.0))
	hud.quit_pressed.connect(func() -> void: WindowService.quit_game())
	hud.options_pressed.connect(_show_options)
	sim.tower_up.connect(func(n: int) -> void: hud.toast(hud.fmt("UI_TOWER_DONE", {"n": n})))
	sim.person_joined.connect(func(id: int) -> void: hud.toast(hud.fmt("UI_JOINED", {"name": hud.pname(sim.person(id))})))
	sim.building_done.connect(func(id: int) -> void:
		var b := sim.by_id(id)
		if not b.is_empty() and String(b["type"]) != "torre":
			hud.toast(hud.fmt("UI_DONE", {"b": hud.bname(String(b["type"]), int(b["level"]))})))
	sim.group_arrived.connect(func() -> void: hud.toast(hud.fmt("UI_GATE_BADGE", {"n": sim.gate_group.size()})))


# ================================================================ telas
func _show_title() -> void:
	cam.position.x -= 72.0   # a vila aparece à direita do painel do título
	_clamp_cam()
	_title = TitleScreen.new()
	_title.game_started.connect(func(_is_new: bool) -> void: _enter_game())
	_title.options_requested.connect(_show_options)
	_layer.add_child(_title)
	_title.focus_first()


func _enter_game() -> void:
	if _title != null:
		_title.queue_free()
		_title = null
	if hud == null:
		_make_hud()
	var hatch := sim._first("hatch")
	cam.position = Vector2(Vector2i(hatch["cell"])) * 16.0 + Vector2(40, 8)
	_clamp_cam()
	_open_test_card()


func _show_options() -> void:
	if _options != null:
		return
	_options = OptionsScreen.new()
	_options.closed.connect(_close_options)
	_options.progress_erased.connect(func() -> void:
		_close_options()
		get_tree().reload_current_scene())
	var top := CanvasLayer.new()
	top.layer = 10
	add_child(top)
	top.add_child(_options)
	_options.focus_first()


func _close_options() -> void:
	if _options == null:
		return
	_options.get_parent().queue_free()
	_options = null
	if _title != null:
		_title.focus_first()


func _open_test_card() -> void:
	match String(Game.args.get("open", "")):   # só para capturas
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
		"options": _show_options()


## Clique em botão da interface: som de clique (o AudioManager só toca depois do primeiro clique).
func _input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var over := get_viewport().gui_get_hovered_control()
		if over is BaseButton:
			AudioManager.play_sfx("click")


func _process(delta: float) -> void:
	if hud != null:
		_update_hover()
	if _shot_t >= 0.0:
		_shot_t -= delta
		if _shot_t < 0.0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_shot)
			get_tree().quit()


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
	hud.toast(I18n.t("UI_PLACE"))


func _stop_placing() -> void:
	_placing = ""
	if world != null:
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
		hud.show_tip(I18n.t("B_entulho") + " · " + I18n.t("UI_CLEAR"), mp)
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
	if hud == null or _options != null:
		return
	if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE and _placing == "" and not hud.card_open():
		_show_options()
		return
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
			hud.toast(I18n.t("UI_NO_SPACE"))
		else:
			hud.toast(I18n.t("UI_MISSING").format({"list": ""}).strip_edges())
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
