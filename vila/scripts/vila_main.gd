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
var _tut: VilaTutorial
var _ending: EndingScreen
var _pending_welcome: Dictionary = {}
var _catch_label: Label
var _tut_layer: CanvasLayer
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
	_layer.layer = 2   # a camada 1 é dos vaga-lumes (por cima do mundo, fora do escuro da noite)
	add_child(_layer)
	Game.sim_replaced.connect(_bind_sim)
	AudioManager.set_station(true)
	WindowService.layout_changed.connect(func(_l: Vector2i, _s: int) -> void: _clamp_cam())
	Game.arrival_started.connect(func() -> void:
		get_tree().create_timer(6.0).timeout.connect(_show_ending))
	Game.welcome_back.connect(func(s: Dictionary) -> void:
		if hud != null:
			hud.show_welcome(s)
		else:
			_pending_welcome = s)
	Game.catch_up_progress.connect(_on_catch_up)
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
	if _tut_layer != null:
		_tut_layer.queue_free()
		_tut_layer = null
		_tut = null
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
	sim.radio.connect(func(l: Dictionary) -> void:
		if hud != null and not sim.offline:
			hud.quiet = _tut != null and _tut.active()
			hud.on_radio(l))
	sim.merchant_arrived.connect(func() -> void:
		if hud != null and not sim.offline:
			hud.toast(I18n.t("UI_MERCHANT_HERE")))
	sim.merchant_left.connect(func(sold: Dictionary) -> void:
		if hud != null and not sim.offline and not sold.is_empty():
			var p := 0
			for r in sold:
				p += int(sold[r])
			hud.toast(hud.fmt("UI_MERCHANT_SOLD", {"p": p})))
	_tut_layer = CanvasLayer.new()
	_tut_layer.layer = 5
	add_child(_tut_layer)
	_tut = VilaTutorial.new()
	_tut_layer.add_child(_tut)
	_tut.setup(self, hud, sim)
	# Capturas e testes jogam sem tutorial (--notut, ou quando o jogo andou sozinho com --demo).
	if not (Game.args.has("notut") or Game.args.has("demo")):
		_tut.start()


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
	if not _pending_welcome.is_empty():
		hud.show_welcome(_pending_welcome)
		_pending_welcome = {}
	_open_test_card()
	if sim.ela_t >= 0.0 and not bool(Settings.get_value("ending_seen", false)):
		_show_ending.call_deferred()


## Voltando depois de um tempo fechado: aviso no meio da tela enquanto a vila alcança o relógio.
func _on_catch_up(frac: float) -> void:
	if frac >= 1.0:
		if _catch_label != null:
			_catch_label.queue_free()
			_catch_label = null
		return
	if _catch_label == null:
		_catch_label = Label.new()
		_catch_label.theme = UiTheme.build()
		_catch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_catch_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_catch_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.04, 0.07, 0.75)
		_catch_label.add_theme_stylebox_override("normal", bg)
		_catch_label.mouse_filter = Control.MOUSE_FILTER_STOP
		var cl := CanvasLayer.new()
		cl.layer = 30
		add_child(cl)
		cl.add_child(_catch_label)
		_catch_label.tree_exited.connect(cl.queue_free)
	_catch_label.text = I18n.t("UI_CATCHING_UP", {"p": int(frac * 100.0)})


## O final: ela entrou pelo portão. Véu escuro com as páginas da chegada; depois a vila continua.
func _show_ending() -> void:
	if _ending != null:
		return
	if hud != null:
		hud.close_card()
	var el := CanvasLayer.new()
	el.layer = 20
	add_child(el)
	_ending = EndingScreen.new()
	el.add_child(_ending)
	_ending.finished.connect(func(_k: String) -> void:
		Settings.set_value("ending_seen", true)
		el.queue_free()
		_ending = null)
	AudioManager.play_radio_cue("epilogue")
	_ending.play_arrival([
		[["VEND_knock"], 3.5, "LabelMuted"],
		[["journey.arrival"], 4.0, ""],
		[["VEND_light"], 3.5, "LabelMuted"],
		[["ending.title"], 3.5, "LabelTitle"],
		[["ending.line.1", "ending.line.2"], 4.0, ""],
	])


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
			if Game.args.has("cell"):   # --cell=dx,dy: desloca do lugar livre (para ver célula bloqueada)
				var cs := String(Game.args["cell"]).split(",")
				_test_cell += Vector2i(int(cs[0]), int(cs[1]))
		"options": _show_options()
		"merchant":
			if not sim.merchant_here():
				sim._merchant_arrive(sim.t + 1800.0)
			hud.show_merchant()
			var pr := sim._first("praca")
			if not pr.is_empty():
				cam.position = Vector2(Vector2i(pr["cell"])) * 16.0 + Vector2(90, 24)
				_clamp_cam()
		"radio": hud.show_radio()
		"tired":   # capturas: todo mundo com 2 noites viradas
			for p in sim.people:
				p["tired"] = 2
			hud.show_person(int(sim.people[0]["id"]))
		"manage": hud.set_manage(true)
		"ending": _show_ending()
		var o:
			# --open=b:deposito abre o cartão do primeiro prédio desse tipo.
			if String(o).begins_with("b:"):
				var fb := sim._first(String(o).trim_prefix("b:"))
				if not fb.is_empty():
					hud.show_building(int(fb["id"]))
	# Capturas: mouse parado num ponto (--hover=x,y em pixels lógicos), para ver a explicação.
	if Game.args.has("hover"):
		var hv := String(Game.args["hover"]).split(",")
		var at := Vector2(float(hv[0]), float(hv[1]))
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			get_viewport().warp_mouse(at)
			var mm := InputEventMouseMotion.new()
			mm.position = at
			mm.global_position = at
			Input.parse_input_event(mm))
	# Capturas: janela maior que o padrão (--winpx=1500x700, em pixels de tela).
	if Game.args.has("winpx"):
		var wp := String(Game.args["winpx"]).split("x")
		WindowService._user_px = Vector2i(int(wp[0]), int(wp[1]))
		WindowService._apply_layout(true)


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


var _tip_text: String = ""
var _tip_t: float = 0.0


func _tip_under(n: Node, mp: Vector2) -> Control:
	for ch in n.get_children():
		var f := _tip_under(ch, mp)
		if f != null:
			return f
	if n is Control and (n as Control).is_visible_in_tree() and (n as Control).tooltip_text != "" and (n as Control).get_global_rect().has_point(mp):
		return n as Control
	return null


func _update_hover() -> void:
	var mp := get_viewport().get_mouse_position()
	# Botões, ícones e chips: a explicação vem do tooltip_text do controle debaixo do mouse
	# (desenhada pelo próprio jogo; a dica nativa do Godot não aparece na janela sem borda).
	var hc := get_viewport().gui_get_hovered_control()
	# O cartão é refeito a cada 0,2 s e o Godot perde o controle debaixo do mouse parado:
	# procura no próprio cartão quem tem explicação naquele ponto.
	if (hc == null or not is_instance_valid(hc)) and hud.card_open():
		hc = _tip_under(hud._card, mp)
	if hc != null:
		var tip := ""
		var n: Node = hc
		while n is Control:
			if (n as Control).tooltip_text != "":
				tip = (n as Control).tooltip_text
				break
			n = n.get_parent()
		if tip != "":
			_tip_t += get_process_delta_time()
			if _tip_text != tip:   # o cartão é refeito a cada 0,2 s: compara o texto, não o nó
				_tip_text = tip
				_tip_t = 0.0
			hud.show_tip(tip if _tip_t >= 0.25 else "", mp)
			world.hover_cell = Vector2i(-1, -1)
			return
	_tip_text = ""
	if _test_cell.x < 0 and (hud.mouse_over_ui(mp) or hc != null or _options != null):
		world.hover_cell = Vector2i(-1, -1)
		if _placing == "":
			hud.show_tip("", mp)
		return
	var wp := _screen_to_world(mp)
	var c := world.cell_at(wp) if _test_cell.x < 0 else _test_cell
	world.hover_cell = c
	world.ghost_cell = c
	if _placing != "":
		# Diz na hora por que não dá para pôr ali.
		var why := sim.place_reason(_placing, c) if c.x >= 0 else "out"
		hud.show_tip(I18n.t("UI_PLACE_" + why) if why != "" else "", mp, true)
		return
	if _dragging:
		hud.show_tip("", mp)
		return
	var pid := world.person_at(wp)
	if pid >= 0:
		var p := sim.person(pid)
		var pe := sim.eta(p)
		hud.show_tip(hud.pname(p) + " · " + hud._doing_text(p) + ((" · " + VilaHud.fmt_clock(pe)) if pe >= 0.0 else ""), mp)
		return
	if sim.terrain_at(c) == VilaSim.T_RUBBLE:
		hud.show_tip(I18n.t("B_entulho") + " · " + I18n.t("UI_CLEAR"), mp)
		return
	if sim.terrain_at(c) == VilaSim.T_TREE:
		hud.show_tip(I18n.t("B_arvore") + " · " + I18n.t("UI_CUT"), mp)
		return
	var b := sim.building_at(c)
	if not b.is_empty():
		var t := hud.bname(String(b["type"]), int(b["level"]))
		if String(b["state"]) != "built":
			t += " · " + VilaHud.fmt_clock(sim.site_eta(b))
		if I18n.has_key("BD_" + String(b["type"])):
			t += "\n" + I18n.t("BD_" + String(b["type"]))
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
		var tp := _placing
		var r := sim.build(_placing, c)
		if bool(r["ok"]):
			_stop_placing()
			# Diz o que acontece agora: quem vai construir, ou que está esperando alguém livre.
			var who := ""
			for p in sim.people:
				if String(p["job"].get("kind", "")) == "idle" and not p["asleep"]:
					who = hud.pname(p)
					break
			if sim.is_night():
				hud.toast(hud.fmt("UI_SITE_NIGHT", {"b": hud.bname(tp)}))
			elif who != "":
				hud.toast(hud.fmt("UI_SITE_WHO", {"b": hud.bname(tp), "name": who}))
			else:
				hud.toast(hud.fmt("UI_SITE_NEXT", {"b": hud.bname(tp)}))
		elif String(r["reason"]) == "place":
			var why := sim.place_reason(tp, c)
			hud.toast(I18n.t("UI_PLACE_" + why) if why != "" else I18n.t("UI_NO_SPACE"))
		else:
			hud.toast(I18n.t("UI_MISSING").format({"list": ""}).strip_edges())
			_stop_placing()
		return
	if world.merchant_rect().has_point(wp):
		hud.show_merchant()
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
	if k == VilaSim.T_RUBBLE or k == VilaSim.T_TREE:
		hud.show_rubble(c)
	elif k == VilaSim.T_GROUND or k == VilaSim.T_STUMP:
		hud.show_build_menu()
