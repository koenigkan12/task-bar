class_name VilaTutorial
extends Control
## Tutorial guiado (design, seção 7): a tela escurece, só o alvo fica aceso, uma seta aponta e um balão
## do rádio diz uma frase. Cada passo avança fazendo a ação; "Pular" pergunta antes. O passo fica salvo
## em Settings ("tut_step"/"tut_done"), então fechar no meio continua de onde parou.
## Depois do tutorial, dicas de uma vez só (Settings "hints_seen"): portão, torre pronta, falta de chão,
## comida ou água acabando. Mesmo balão, sem escurecer; fecham com Certo ou fazendo a coisa.

signal finished

const DIM := Color(0.02, 0.01, 0.04, 0.72)
const STEPS: Array[String] = ["joaquim", "res", "build", "pick", "place", "wait", "goal", "horta", "tower", "zoom", "end"]
## Passos em que o resto da tela fica escuro e não aceita clique (só o alvo).
const DIMMED: Array[String] = ["joaquim", "res", "build", "pick", "goal", "tower"]
## Capítulo da defesa (depois do tutorial, ou para quem já tinha feito): mostra por onde os zumbis
## chegam e faz montar a primeira torre arqueira. Fica salvo em Settings ("dtut_step"/"dtut_done").
const DSTEPS: Array[String] = ["dz_intro", "dz_build", "dz_tab", "dz_pick", "dz_place", "dz_wait"]
const DDIMMED: Array[String] = ["dz_build", "dz_tab", "dz_pick"]

var main: Node          # vila_main: _placing, _zoom_i, world, cam
var hud: VilaHud
var sim: VilaSim

var _step: int = -1
var _dstep: int = -1
var _hint: String = ""
var _dims: Array[ColorRect] = []
var _arrow: TextureRect
var _bubble: PanelContainer
var _text: Label
var _ok: Button
var _skip: Button
var _zoom0: int = 1
var _goal_hit: bool = false
var _t: float = 0.0


func setup(m: Node, h: VilaHud, s: VilaSim) -> void:
	main = m
	hud = h
	sim = s
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	for i in 4:
		var r := ColorRect.new()
		r.color = DIM
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		r.visible = false
		add_child(r)
		_dims.append(r)
	_arrow = TextureRect.new()
	_arrow.texture = UiTheme.icon("arrow_down")
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.visible = false
	add_child(_arrow)
	_bubble = PanelContainer.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bubble)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_bubble.add_child(col)
	var head := HBoxContainer.new()
	var ic := TextureRect.new()
	ic.texture = UiTheme.icon("radio")
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	head.add_child(ic)
	var who: Label = ScreenUtil.label("TUT_radio", "LabelAmber")
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	_skip = Button.new()
	_skip.theme_type_variation = "FlatButton"
	_skip.text = I18n.t("TUT_skip")
	_skip.pressed.connect(_ask_skip)
	head.add_child(_skip)
	col.add_child(head)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(150, 0)
	col.add_child(_text)
	_ok = Button.new()
	_ok.text = I18n.t("TUT_ok")
	_ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	_ok.pressed.connect(_on_ok)
	col.add_child(_ok)
	hud.goal_pressed.connect(func() -> void: _goal_hit = true)
	_bubble.visible = false


## Começa (ou continua) o tutorial. Já feito: só as dicas.
func start() -> void:
	if bool(Settings.get_value("tut_done", false)):
		_step = STEPS.size()
		return
	_go(clampi(int(Settings.get_value("tut_step", 0)), 0, STEPS.size() - 1))


func active() -> bool:
	return _step >= 0 and _step < STEPS.size()


func d_active() -> bool:
	return _dstep >= 0 and _dstep < DSTEPS.size()


## Começa o capítulo da defesa quando dá: tutorial feito, torre arqueira liberada e ainda nenhuma.
func _d_maybe_start() -> void:
	if _hint != "" or bool(Settings.get_value("dtut_done", false)) or not sim.unlocked("torre_arq"):
		return
	if _has("torre_arq"):
		Settings.set_value("dtut_done", true)
		return
	if hud.card_open() and hud._card_kind != "build":
		return
	_dgo(clampi(int(Settings.get_value("dtut_step", 0)), 0, DSTEPS.size() - 1))


func _dgo(i: int) -> void:
	_dstep = i
	if i >= DSTEPS.size():
		_dfinish()
		return
	var key := DSTEPS[i]
	Settings.set_value("dtut_step", i)
	hud.tut_only = "torre_arq" if key in ["dz_build", "dz_tab", "dz_pick"] else ""
	if key == "dz_tab" or key == "dz_pick":
		# a primeira torre tem que dar para pagar: o rádio completa o que faltar
		var cost: Dictionary = sim.level_def({"type": "torre_arq", "level": 1}).get("cost", {})
		for r in cost:
			sim.stock[r] = maxf(float(sim.stock[r]), float(cost[r]))
		if hud.card_open():
			hud._rebuild_card()
	if key == "dz_intro":   # câmera entre a vila e por onde eles chegam
		var ar: Array = sim.defense.arrivals()
		if not ar.is_empty():
			var hc := Vector2(Vector2i(sim._first("hatch")["cell"])) * 16.0
			main.cam.position = (hc + Vector2(Vector2i(ar[0]["cell"])) * 16.0) / 2.0
			main._clamp_cam()
	main.world.show_arrivals = true
	_text.text = I18n.t("TUT_" + key)
	_ok.visible = key == "dz_intro" or key == "dz_wait"
	_skip.visible = true
	_bubble.visible = true


func _dfinish() -> void:
	_dstep = DSTEPS.size()
	hud.tut_only = ""
	main.world.show_arrivals = false
	Settings.set_value("dtut_done", true)
	_bubble.visible = false
	_arrow.visible = false
	for d in _dims:
		d.visible = false


func _go(i: int) -> void:
	_step = i
	_goal_hit = false
	_zoom0 = int(main._zoom_i)
	if i >= STEPS.size():
		_finish()
		return
	Settings.set_value("tut_step", i)
	hud.tut_only = "poco" if STEPS[i] == "build" or STEPS[i] == "pick" else ""
	_text.text = I18n.t("TUT_" + STEPS[i])
	_ok.visible = STEPS[i] == "end"
	_skip.visible = true
	_bubble.visible = true


func _finish() -> void:
	hud.tut_only = ""
	Settings.set_value("tut_done", true)
	_bubble.visible = false
	_arrow.visible = false
	for d in _dims:
		d.visible = false
	finished.emit()


func _ask_skip() -> void:
	ConfirmBox.ask(self, "TUT_skip_q", "TUT_skip_text", "TUT_skip", func() -> void:
		if d_active():
			_dfinish()
			return
		_step = STEPS.size()
		_finish())


func _on_ok() -> void:
	if active():
		_go(_step + 1)
	elif d_active():
		_dgo(_dstep + 1)
	elif _hint != "":
		_close_hint()


func _process(delta: float) -> void:
	if sim == null:
		return
	_t += delta
	if active():
		var key := STEPS[_step]
		if _done(key):
			_go(_step + 1)
			return
		_layout(_target(key), DIMMED.has(key))
	elif d_active():
		var dk := DSTEPS[_dstep]
		if _done(dk):
			_dgo(_dstep + 1)
			return
		_layout(_target(dk), DDIMMED.has(dk))
	else:
		if _step >= STEPS.size():
			_d_maybe_start()
		if not d_active():
			_hints()


func _done(key: String) -> bool:
	match key:
		"joaquim":
			return hud._card_kind == "person"
		"res":
			return hud._card_kind.begins_with("res:")
		"build":
			return hud._card_kind == "build" or String(main._placing) == "poco" or _has("poco")
		"pick":
			return String(main._placing) == "poco" or _has("poco")
		"place":
			return _has("poco")
		"wait":
			return _built("poco")
		"goal":
			return _goal_hit or _has("horta")
		"horta":
			return _has("horta")
		"tower":
			return hud._card_kind == "tower"
		"zoom":
			return int(main._zoom_i) != _zoom0
		"dz_build":
			return hud._card_kind == "build" or String(main._placing) == "torre_arq" or _has("torre_arq")
		"dz_tab":
			return (hud._card_kind == "build" and hud.build_tab == "defense") or String(main._placing) == "torre_arq" or _has("torre_arq")
		"dz_pick":
			return String(main._placing) == "torre_arq" or _has("torre_arq")
		"dz_place":
			return _has("torre_arq")
		"dz_wait":
			return _built("torre_arq")
	return false


func _has(type: String) -> bool:
	return not sim._first(type).is_empty()


func _built(type: String) -> bool:
	var b := sim._first(type)
	return not b.is_empty() and String(b["state"]) == "built"


## Retângulo do alvo na tela (Rect2() = sem alvo).
func _target(key: String) -> Rect2:
	match key:
		"joaquim":
			var p: Dictionary = sim.people[0]
			var c: Vector2 = main.get_canvas_transform() * main.world._person_world(p)
			var z: float = main.cam.zoom.x
			return Rect2(c + Vector2(-8, -18) * z, Vector2(16, 20) * z)
		"res":
			return (hud._res_labels["comida"] as Control).get_parent().get_global_rect().grow(1)
		"build":
			return hud.build_btn.get_global_rect()
		"pick":
			var b: Button = hud.build_btns.get("poco")
			return b.get_global_rect() if b != null and is_instance_valid(b) and b.is_visible_in_tree() else Rect2()
		"place":
			var cell: Vector2i = AutoPlayer.spot(sim, "poco")
			var fp: Vector2i = sim._fp("poco")
			var tl: Vector2 = main.get_canvas_transform() * (Vector2(cell) * 16.0)
			return Rect2(tl, Vector2(fp) * 16.0 * main.cam.zoom.x)
		"wait":
			var s := sim._first("poco")
			if s.is_empty():
				return Rect2()
			var tl2: Vector2 = main.get_canvas_transform() * (Vector2(Vector2i(s["cell"])) * 16.0)
			return Rect2(tl2, Vector2(sim._fp("poco")) * 16.0 * main.cam.zoom.x)
		"goal":
			return hud.goal_btn.get_global_rect()
		"tower":
			return hud.tower_btn.get_global_rect()
		"dz_intro":
			var ar: Array = sim.defense.arrivals()
			if ar.is_empty():
				return Rect2()
			var ac: Vector2 = main.get_canvas_transform() * (Vector2(Vector2i(ar[0]["cell"])) * 16.0)
			var ar_r := Rect2(ac, Vector2(16, 16) * main.cam.zoom.x)
			return ar_r if get_viewport_rect().grow(-20).encloses(ar_r) else Rect2()
		"dz_build":
			return hud.build_btn.get_global_rect()
		"dz_tab":
			var tb: Variant = hud.build_tab_btns.get("defense")
			return (tb as Button).get_global_rect() if is_instance_valid(tb) and (tb as Button).is_visible_in_tree() else Rect2()
		"dz_pick":
			var bt: Variant = hud.build_btns.get("torre_arq")
			return (bt as Button).get_global_rect() if is_instance_valid(bt) and (bt as Button).is_visible_in_tree() else Rect2()
		"dz_wait":
			var ta := sim._first("torre_arq")
			if ta.is_empty():
				return Rect2()
			var tl3: Vector2 = main.get_canvas_transform() * (Vector2(Vector2i(ta["cell"])) * 16.0)
			return Rect2(tl3, Vector2(sim._fp("torre_arq")) * 16.0 * main.cam.zoom.x)
	return Rect2()


## Escurece em volta do alvo (4 faixas), põe a seta em cima dele e o balão perto.
func _layout(r: Rect2, dim: bool) -> void:
	var vs := get_viewport_rect().size
	var has_t := r.size != Vector2.ZERO
	var show_dim := dim and has_t
	if show_dim:
		var hole := r.grow(2)
		_set_dim(0, Rect2(0, 0, vs.x, hole.position.y))
		_set_dim(1, Rect2(0, hole.end.y, vs.x, vs.y - hole.end.y))
		_set_dim(2, Rect2(0, hole.position.y, hole.position.x, hole.size.y))
		_set_dim(3, Rect2(hole.end.x, hole.position.y, vs.x - hole.end.x, hole.size.y))
	for d in _dims:
		d.visible = show_dim
	_arrow.visible = has_t
	_bubble.size = Vector2.ZERO
	var bs := _bubble.get_combined_minimum_size()
	if has_t:
		var bob := roundf(sin(_t * 6.0) * 1.5)
		var below := r.position.y < vs.y * 0.45
		if below:
			_arrow.texture = UiTheme.icon("arrow_up")
			_arrow.position = Vector2(roundf(r.get_center().x - 4), r.end.y + 1 + bob)
		else:
			_arrow.texture = UiTheme.icon("arrow_down")
			_arrow.position = Vector2(roundf(r.get_center().x - 4), r.position.y - 9 - bob)
		var bx := clampf(r.get_center().x - bs.x / 2.0, 2.0, vs.x - bs.x - 2.0)
		var by := r.end.y + 12.0 if below else r.position.y - bs.y - 12.0
		var pos := Vector2(roundf(bx), roundf(clampf(by, 16.0, vs.y - bs.y - 18.0)))
		# Não cobre o cartão aberto (menu Construir, torre): vai para o lado esquerdo dele.
		var card: Rect2 = hud._card.get_global_rect() if hud.card_open() else Rect2()
		if card.size != Vector2.ZERO and Rect2(pos, bs).intersects(card):
			pos = Vector2(maxf(2.0, card.position.x - bs.x - 4.0), roundf(clampf(r.get_center().y - bs.y / 2.0, 16.0, vs.y - bs.y - 18.0)))
		_bubble.position = pos
	else:
		_bubble.position = Vector2(roundf((vs.x - bs.x) / 2.0), 18)


func _set_dim(i: int, r: Rect2) -> void:
	_dims[i].position = r.position
	_dims[i].size = Vector2(maxf(r.size.x, 0.0), maxf(r.size.y, 0.0))


# ================================================================ dicas de uma vez só
func _hints() -> void:
	if _hint != "":
		if _hint_done(_hint):
			_close_hint()
		else:
			_layout(_hint_target(_hint), false)
		return
	var seen: Array = Settings.get_value("hints_seen", [])
	var g := sim.goal()
	var want := ""
	if not sim.gate_group.is_empty():
		want = "gate"
	elif String(g.get("kind", "")) == "tower" and (g.get("missing", {}) as Dictionary).is_empty():
		want = "tower_ready"
	elif String(g.get("kind", "")) == "space":
		want = "space"
	elif String(g.get("kind", "")) == "short":
		want = "short"
	if want == "" or seen.has(want) or hud.card_open():
		return
	_hint = want
	_text.text = I18n.t("HINT_" + want)
	_ok.visible = true
	_skip.visible = false
	_bubble.visible = true


func _hint_done(key: String) -> bool:
	match key:
		"gate":
			return hud._card_kind == "gate"
		"tower_ready":
			return hud._card_kind == "tower"
		"space":
			return not sim.marked.is_empty()
	return false


func _hint_target(key: String) -> Rect2:
	match key:
		"gate":
			return main.world.boat_screen_rect()
		"tower_ready":
			return hud.tower_btn.get_global_rect()
		"short":
			return hud.goal_btn.get_global_rect()
	return Rect2()


func _close_hint() -> void:
	var seen: Array = Settings.get_value("hints_seen", [])
	if not seen.has(_hint):
		seen.append(_hint)
	Settings.set_value("hints_seen", seen)
	_hint = ""
	_bubble.visible = false
	_arrow.visible = false
