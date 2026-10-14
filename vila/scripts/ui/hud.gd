class_name VilaHud
extends Control
## Interface da vila numa tela lógica de 320×200: barra de recursos em cima, meta embaixo,
## zoom, selo do portão, cartões (prédio, torre, pessoa, portão), menu de construir e avisos.
## Todo texto passa por tr() (CSV em data/i18n). Cor nunca é o único sinal: falta vem com ícone.

signal build_chosen(type: String)
signal zoom_step(dir: int)
signal quit_pressed
signal window_drag(delta: Vector2i)

const ART := "res://assets/art/"
const ICON := {"comida": 0, "agua": 1, "madeira": 2, "sucata": 3, "pessoa": 4, "cama": 5, "relogio": 6,
		"torre": 7, "martelo": 8, "seta": 9, "cadeado": 10, "check": 11, "estrela": 12, "sol": 13, "lua": 14, "alerta": 15}
const C_TEXT := Color(0.93, 0.88, 0.9)
const C_MUTED := Color(0.62, 0.55, 0.62)
const C_WARN := Color(1.0, 0.55, 0.35)
const C_GOOD := Color(0.5, 0.92, 0.85)
const C_AMBER := Color(1.0, 0.8, 0.42)
const RAR_COLOR := {"comum": Color(0.78, 0.74, 0.78), "rara": Color(0.45, 0.85, 1.0), "excelente": Color(1.0, 0.62, 0.95)}

var sim: VilaSim
var _font: Font
var _icons: Texture2D
var _res_labels: Dictionary = {}
var _res_warn: Dictionary = {}
var _people_label: Label
var _clock_label: Label
var _clock_icon: TextureRect
var _goal_btn: Button
var _gate_btn: Button
var _card: PanelContainer
var _card_box: VBoxContainer
var _card_kind: String = ""
var _card_id: int = -1
var _toast: Label
var _toast_t: float = 0.0
var _tip: Label
var _refresh_acc: float = 0.0
var _drag_from: Vector2i = Vector2i(-1, -1)


func setup(s: VilaSim) -> void:
	sim = s
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/fonts/DotGothic16-Regular.ttf")
	_icons = load(ART + "icons.png")
	theme = _make_theme()
	_build_top()
	_build_bottom()
	_card = PanelContainer.new()
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 2)
	_card.add_child(_card_box)
	_toast = Label.new()
	_toast.visible = false
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_stylebox_override("normal", _panel_box())
	_toast.position = Vector2(60, 20)
	_toast.size = Vector2(200, 14)
	add_child(_toast)
	_tip = Label.new()
	_tip.visible = false
	_tip.add_theme_stylebox_override("normal", _panel_box())
	_tip.add_theme_color_override("font_color", C_TEXT)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tip)
	refresh()


# ================================================================ tema e peças
func _panel_box() -> StyleBox:
	var t: Texture2D = load(ART + "ui_panel.png")
	if t == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.09, 0.075, 0.1, 0.92)
		f.border_color = Color(0.36, 0.29, 0.37)
		f.set_border_width_all(1)
		f.set_content_margin_all(3)
		return f
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.set_texture_margin_all(4)
	sb.set_content_margin_all(3)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func _button_box(state: int) -> StyleBox:
	var t: Texture2D = load(ART + ("ui_button_off.png" if state == 3 else "ui_button.png"))
	var sb := StyleBoxTexture.new()
	sb.texture = t
	if state < 3:
		sb.region_rect = Rect2(state * 16, 0, 16, 16)
	sb.set_texture_margin_all(4)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = _font
	th.default_font_size = 8
	th.set_color("font_color", "Label", C_TEXT)
	th.set_color("font_color", "Button", C_TEXT)
	th.set_color("font_hover_color", "Button", Color(1, 0.92, 0.75))
	th.set_color("font_pressed_color", "Button", Color(1, 0.92, 0.75))
	th.set_color("font_disabled_color", "Button", C_MUTED)
	th.set_stylebox("panel", "PanelContainer", _panel_box())
	th.set_stylebox("normal", "Button", _button_box(0))
	th.set_stylebox("hover", "Button", _button_box(1))
	th.set_stylebox("pressed", "Button", _button_box(2))
	th.set_stylebox("disabled", "Button", _button_box(3))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_constant("h_separation", "Button", 2)
	th.set_constant("separation", "HBoxContainer", 2)
	th.set_constant("separation", "VBoxContainer", 1)
	return th


func icon(name: String) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = _icons
	a.region = Rect2(ICON.get(name, 15) * 8, 0, 8, 8)
	return a


func _icon_rect(name: String) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(name)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.custom_minimum_size = Vector2(8, 10)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _label(text: String, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrap(text: String, color: Color = C_TEXT, width: float = 138.0) -> Label:
	var l := _label(text, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


func _row(parts: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p in parts:
		h.add_child(p)
	return h


static func fmt_time(sec: float) -> String:
	var s := int(ceil(sec))
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dmin" % int(ceil(s / 60.0))
	return "%dh%02d" % [s / 3600, (s % 3600) / 60]


func fmt(key: String, args: Dictionary = {}) -> String:
	return tr(key).format(args)


func bname(type: String) -> String:
	return tr("B_" + type)


func pname(p: Dictionary) -> String:
	var n := String(p.get("name", ""))
	return tr("P_" + n.substr(1)) if n.begins_with("@") else n


## Custo em ícones; o que falta fica laranja com o ícone de alerta (cor + ícone).
func _cost_row(cost: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in VilaSim.RES:
		if not cost.has(r):
			continue
		var short := float(sim.stock[r]) + 1e-6 < float(cost[r])
		h.add_child(_icon_rect(r))
		h.add_child(_label(str(int(cost[r])), C_WARN if short else C_TEXT))
		if short:
			h.add_child(_icon_rect("alerta"))
	return h


# ================================================================ barra de cima e de baixo
func _build_top() -> void:
	var bar := PanelContainer.new()
	bar.position = Vector2(0, 0)
	bar.size = Vector2(320, 14)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_bar_input)
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	bar.add_child(h)
	for r in VilaSim.RES:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 1)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = tr("RES_" + r)
		chip.add_child(_icon_rect(r))
		var l := _label("0")
		chip.add_child(l)
		var warn := _icon_rect("alerta")
		warn.visible = false
		chip.add_child(warn)
		_res_labels[r] = l
		_res_warn[r] = warn
		h.add_child(chip)
	h.add_child(_icon_rect("pessoa"))
	_people_label = _label("1/1")
	h.add_child(_people_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	_clock_icon = _icon_rect("sol")
	h.add_child(_clock_icon)
	_clock_label = _label("")
	h.add_child(_clock_label)
	var x := Button.new()
	x.text = "x"
	x.tooltip_text = tr("UI_CLOSE")
	x.custom_minimum_size = Vector2(10, 10)
	x.pressed.connect(func() -> void: quit_pressed.emit())
	h.add_child(x)


## Arrastar a barra de cima move a janela (ela não tem borda).
func _on_bar_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag_from = DisplayServer.mouse_get_position() if ev.pressed else Vector2i(-1, -1)
	elif ev is InputEventMouseMotion and _drag_from.x >= 0:
		var now := DisplayServer.mouse_get_position()
		window_drag.emit(now - _drag_from)
		_drag_from = now


func _build_bottom() -> void:
	_goal_btn = Button.new()
	_goal_btn.icon = icon("estrela")
	_goal_btn.position = Vector2(2, 184)
	_goal_btn.size = Vector2(10, 14)
	_goal_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_goal_btn.pressed.connect(_on_goal)
	add_child(_goal_btn)
	var zm := Button.new()
	zm.text = "-"
	zm.position = Vector2(286, 185)
	zm.custom_minimum_size = Vector2(14, 13)
	zm.add_theme_constant_override("h_separation", 0)
	zm.tooltip_text = tr("TIP_ZOOM")
	zm.pressed.connect(func() -> void: zoom_step.emit(-1))
	add_child(zm)
	var zp := Button.new()
	zp.text = "+"
	zp.position = Vector2(302, 185)
	zp.custom_minimum_size = Vector2(14, 13)
	zp.tooltip_text = tr("TIP_ZOOM")
	zp.pressed.connect(func() -> void: zoom_step.emit(1))
	add_child(zp)
	_gate_btn = Button.new()
	_gate_btn.icon = icon("pessoa")
	_gate_btn.position = Vector2(2, 17)
	_gate_btn.visible = false
	_gate_btn.pressed.connect(show_gate)
	add_child(_gate_btn)


func _goal_text() -> String:
	var g := sim.goal()
	match String(g["kind"]):
		"build":
			return fmt("GOAL_build", {"b": bname(g["type"])})
		"more":
			return fmt("GOAL_more", {"n": g["idle"], "b": bname(g["type"])})
		"short":
			return fmt("GOAL_short", {"r": tr("RES_" + String(g["res"])), "b": bname(g["type"])})
		"beds":
			return tr("GOAL_beds")
		"tower_wait":
			return fmt("GOAL_tower_wait", {"n": g["level"]})
		"tower":
			var miss: Dictionary = g["missing"]
			if miss.is_empty():
				return fmt("GOAL_tower_ready", {"n": g["level"]})
			var parts: Array[String] = []
			for r in miss:
				parts.append("%d %s" % [miss[r], tr("RES_" + r)])
			return fmt("GOAL_tower", {"n": g["level"]}) + " · " + fmt("UI_MISSING", {"list": ", ".join(parts)})
	return tr("GOAL_done")


func _on_goal() -> void:
	var g := sim.goal()
	match String(g["kind"]):
		"build", "more", "short":
			build_chosen.emit(String(g["type"]))
		"beds":
			show_build_menu()
		"tower", "tower_wait", "done":
			show_tower()


# ================================================================ atualização
func _process(delta: float) -> void:
	if sim == null:
		return
	_refresh_acc += delta
	if _refresh_acc >= 0.2:
		_refresh_acc = 0.0
		refresh()
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false


func refresh() -> void:
	for r in VilaSim.RES:
		var v := int(floor(float(sim.stock[r])))
		var cap := int(sim.cap(r))
		var l: Label = _res_labels[r]
		l.text = str(v)
		var low := v <= 2 and (r == "comida" or r == "agua")
		var full := v >= cap
		l.add_theme_color_override("font_color", C_WARN if low else (C_AMBER if full else C_TEXT))
		(_res_warn[r] as Control).visible = low
		var bpm := sim.balance_per_min(r)
		l.get_parent().tooltip_text = "%s %d/%d · %+.1f/min" % [tr("RES_" + r), v, cap, bpm] + ((" · " + tr("UI_FULL")) if full else "")
	_people_label.text = "%d/%d" % [sim.people.size(), sim.beds_total()]
	var hr := sim.local_hour()
	_clock_label.text = "%s %02d:%02d" % [fmt("UI_DAY", {"n": sim.day_number()}), int(hr), int(fposmod(hr * 60.0, 60.0))]
	_clock_icon.texture = icon("lua" if sim.is_night() else "sol")
	_goal_btn.text = _goal_text()
	_goal_btn.size = Vector2(10, 14)
	_gate_btn.visible = not sim.gate_group.is_empty()
	_gate_btn.text = fmt("UI_GATE_BADGE", {"n": sim.gate_group.size()})
	_gate_btn.size = Vector2(10, 14)
	if _card.visible:
		_rebuild_card()


func toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = 3.0
	_toast.size = Vector2(0, 14)
	_toast.position = Vector2(160 - _toast.get_minimum_size().x / 2.0, 18)


func show_tip(text: String, at: Vector2) -> void:
	if text == "":
		_tip.visible = false
		return
	_tip.text = text
	_tip.visible = true
	_tip.size = Vector2.ZERO
	var s := _tip.get_minimum_size()
	_tip.position = Vector2(clampf(at.x + 8.0, 0.0, 320.0 - s.x), clampf(at.y + 10.0, 16.0, 182.0 - s.y))


func card_open() -> bool:
	return _card.visible


func close_card() -> void:
	_card.visible = false
	_card_kind = ""


func mouse_over_ui(pos: Vector2) -> bool:
	for c in get_children():
		if c is Control and (c as Control).visible and (c as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			if (c as Control).get_global_rect().has_point(pos):
				return true
	if _goal_btn.get_global_rect().has_point(pos) or (_gate_btn.visible and _gate_btn.get_global_rect().has_point(pos)):
		return true
	return pos.y < 14 or (pos.x > 280 and pos.y > 182)


# ================================================================ cartões
func _open(kind: String, id: int = -1) -> void:
	_card_kind = kind
	_card_id = id
	_card.visible = true
	_rebuild_card()


func show_building(id: int) -> void:
	var b := sim.by_id(id)
	if b.is_empty():
		return
	if String(b["type"]) == "torre":
		show_tower()
	elif String(b["type"]) == "gate":
		show_gate()
	else:
		_open("building", id)


func show_tower() -> void:
	_open("tower")


func show_person(id: int) -> void:
	_open("person", id)


func show_gate() -> void:
	_open("gate")


func show_build_menu() -> void:
	_open("build")


func show_welcome(summary: Dictionary) -> void:
	_card_kind = "welcome"
	_card.visible = true
	_clear_card()
	_header("relogio", fmt("UI_WELCOME_BACK", {"t": fmt_time(float(summary["seconds"]))}))
	var d: Dictionary = summary["delta"]
	for r in VilaSim.RES:
		var v: int = int(d.get(r, 0))
		if v != 0:
			_card_box.add_child(_row([_icon_rect(r), _label("%+d %s" % [v, tr("RES_" + r)], C_GOOD if v > 0 else C_WARN)]))
	if int(summary.get("built", 0)) > 0:
		_card_box.add_child(_row([_icon_rect("martelo"), _label(fmt("UI_DONE", {"b": str(summary["built"])}))]))
	if bool(summary.get("group", false)):
		_card_box.add_child(_row([_icon_rect("pessoa"), _label(fmt("UI_GATE_BADGE", {"n": sim.gate_group.size()}))]))
	var ok := Button.new()
	ok.text = tr("UI_OK")
	ok.pressed.connect(close_card)
	_card_box.add_child(ok)
	_place_card()


func _clear_card() -> void:
	for c in _card_box.get_children():
		_card_box.remove_child(c)
		c.queue_free()


func _header(ic: String, title: String, sub: String = "") -> void:
	var h := _row([_icon_rect(ic), _label(title, C_AMBER)])
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var x := Button.new()
	x.text = "x"
	x.custom_minimum_size = Vector2(10, 10)
	x.pressed.connect(close_card)
	h.add_child(x)
	_card_box.add_child(h)
	if sub != "":
		_card_box.add_child(_wrap(sub, C_MUTED))


func _place_card() -> void:
	_card.size = Vector2.ZERO
	await get_tree().process_frame
	if not is_instance_valid(_card):
		return
	_card.size = Vector2.ZERO
	var s := _card.get_combined_minimum_size()
	_card.size = s
	if _card_kind == "gate":
		_card.position = Vector2(roundf(160.0 - s.x / 2.0), 17)
	else:
		_card.position = Vector2(320.0 - s.x - 2.0, 17)


func _rebuild_card() -> void:
	if not _card.visible:
		return
	match _card_kind:
		"building":
			_card_building()
		"tower":
			_card_tower()
		"person":
			_card_person()
		"gate":
			_card_gate()
		"build":
			_card_build()
		_:
			return
	_place_card()


func _card_building() -> void:
	var b := sim.by_id(_card_id)
	if b.is_empty():
		close_card()
		return
	_clear_card()
	var tp := String(b["type"])
	var d := sim.def(tp)
	var title := bname(tp)
	if d.has("levels") and (d["levels"] as Array).size() > 1:
		title += " · " + fmt("UI_LEVEL", {"n": b["level"]})
	_header("martelo", title, tr("BD_" + tp))
	var st := String(b["state"])
	if st != "built":
		_progress_lines(b)
		return
	var lv := sim.level_def(b)
	if lv.has("slots"):
		var ws: Array = b["workers"]
		var names: Array[String] = []
		for pid in ws:
			names.append(pname(sim.person(int(pid))))
		_card_box.add_child(_row([_icon_rect("pessoa"), _label(fmt("UI_WORKERS", {"a": ws.size(), "b": lv["slots"]}) + ((" " + ", ".join(names)) if not names.is_empty() else ""))]))
		_card_box.add_child(_row([_icon_rect(String(d["res"])), _label(fmt("UI_RATE", {"n": "%.1f" % (60.0 / float(lv["rate_s"]))}))]))
	if lv.has("beds") or tp == "hatch":
		_card_box.add_child(_row([_icon_rect("cama"), _label(fmt("UI_BEDS", {"n": int(lv.get("beds", d.get("beds", 0)))}))]))
	if lv.has("cap") or tp == "hatch":
		_card_box.add_child(_row([_icon_rect("check"), _label(fmt("UI_CAP", {"n": int(lv.get("cap", sim.bal["storage"]["hatch_cap"]))}))]))
	var nl: int = int(b["level"]) + 1
	var levels: Array = d.get("levels", [])
	if nl <= levels.size():
		var nd: Dictionary = levels[nl - 1]
		var need_t: int = int(nd.get("tower", d.get("tower", 1)))
		if sim.tower < need_t:
			_card_box.add_child(_row([_icon_rect("cadeado"), _label(fmt("UI_UPGRADE_TO", {"n": nl}) + " · " + fmt("UI_LOCKED_TOWER", {"n": need_t}), C_MUTED)]))
		else:
			_card_box.add_child(_row([_label(fmt("UI_UPGRADE_TO", {"n": nl}), C_MUTED)]))
			_card_box.add_child(_row([_cost_row(nd["cost"]), _icon_rect("relogio"), _label(fmt_time(float(nd["time_s"])))]))
			var up := Button.new()
			up.text = tr("UI_UPGRADE")
			up.icon = icon("seta")
			up.disabled = not sim.can_afford(nd["cost"])
			up.pressed.connect(func() -> void:
				var r := sim.upgrade(_card_id)
				if not bool(r["ok"]):
					toast(tr("UI_MISSING").format({"list": ""}))
				_rebuild_card())
			_card_box.add_child(up)


func _progress_lines(b: Dictionary) -> void:
	var left := float(b["total"]) - float(b["progress"])
	var lbl := tr("UI_UPGRADING") if String(b["state"]) == "upgrade" else tr("UI_BUILDING")
	_card_box.add_child(_row([_icon_rect("relogio"), _label("%s · %s" % [lbl, fmt_time(left)])]))
	if int(b["builder"]) < 0:
		_card_box.add_child(_row([_icon_rect("alerta"), _label(tr("UI_WAITING_BUILDER"), C_WARN)]))
	else:
		_card_box.add_child(_row([_icon_rect("pessoa"), _label(pname(sim.person(int(b["builder"]))))]))
	var c := Button.new()
	c.text = tr("UI_CANCEL")
	c.pressed.connect(func() -> void:
		sim.cancel(int(b["id"]))
		close_card())
	_card_box.add_child(c)


func _card_tower() -> void:
	var b := sim.tower_building()
	_clear_card()
	_header("torre", bname("torre") + " · " + fmt("UI_LEVEL", {"n": sim.tower}))
	if String(b["state"]) != "built":
		_progress_lines(b)
		return
	if sim.tower >= sim.tower_max():
		_card_box.add_child(_wrap(tr("UI_TOWER_PROTO"), C_MUTED))
		return
	var n := sim.tower + 1
	_card_box.add_child(_label(fmt("UI_TOWER_NEXT", {"n": n}), C_MUTED))
	var unl: Array = sim.bal["tower_unlocks"].get(str(n), [])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	for u in unl:
		var s := String(u)
		var txt: String
		if "@" in s:
			var parts := s.split("@")
			txt = "%s %s" % [bname(parts[0]), fmt("UI_LEVEL", {"n": parts[1]})]
		else:
			txt = bname(s)
		var soon: bool = not sim.bal["buildings"].has(s.split("@")[0])
		grid.add_child(_row([_icon_rect("cadeado" if soon else "seta"), _label(txt + ((" (" + tr("UI_SOON") + ")") if soon else ""), C_MUTED if soon else C_TEXT)]))
	_card_box.add_child(grid)
	var nx := sim.tower_next()
	_card_box.add_child(_row([_cost_row(nx["cost"]), _icon_rect("relogio"), _label(fmt_time(float(nx["time_s"])))]))
	var up := Button.new()
	up.text = tr("UI_TOWER_UP")
	up.icon = icon("seta")
	up.disabled = not sim.can_afford(nx["cost"])
	up.pressed.connect(func() -> void:
		sim.tower_upgrade()
		_rebuild_card())
	_card_box.add_child(up)


func _passive_lines(passives: Array, box: Container, width: float = 92.0) -> void:
	if passives.is_empty():
		box.add_child(_wrap(tr("UI_NO_PASSIVES"), C_MUTED, width))
	for ps in passives:
		var rar := String(ps["rar"])
		var pct := int(round(float(sim.bal["rarity"][rar]["bonus"]) * 100.0))
		# raridade: cor E palavra (cor não é o único sinal)
		var txt := "%s %s: %s" % [tr("PAS_" + String(ps["id"])), tr("RAR_" + rar), fmt("PASD_" + String(ps["id"]), {"p": pct})]
		box.add_child(_wrap(txt, RAR_COLOR[rar], width))


func _card_person() -> void:
	var p := sim.person(_card_id)
	if p.is_empty():
		close_card()
		return
	_clear_card()
	var story := String(p["story"])
	var bio := tr("PB_" + story) if story != "" else (tr("BIO_%d" % int(p["bio"])) if int(p["bio"]) >= 0 else "")
	_header("pessoa", pname(p), "\"" + bio + "\"" if bio != "" else "")
	_card_box.add_child(_row([_icon_rect("relogio"), _label(_doing_text(p))]))
	if p["hungry"]:
		_card_box.add_child(_row([_icon_rect("comida"), _icon_rect("alerta"), _label(tr("UI_HUNGRY"), C_WARN)]))
	if p["thirsty"]:
		_card_box.add_child(_row([_icon_rect("agua"), _icon_rect("alerta"), _label(tr("UI_THIRSTY"), C_WARN)]))
	var box := VBoxContainer.new()
	_passive_lines(p["passives"], box, 138.0)
	_card_box.add_child(box)


func _doing_text(p: Dictionary) -> String:
	var d := sim.doing(p)
	var parts := d.split(":")
	match parts[0]:
		"build":
			return fmt("DO_build", {"b": bname(parts[1])})
		"work":
			return fmt("DO_work", {"b": bname(parts[1])})
		"carry":
			return tr("DO_carry")
		"forage":
			return tr("DO_forage_" + parts[1])
		"sleep":
			return tr("DO_sleep")
		"to_bed":
			return tr("DO_to_bed")
	return tr("DO_idle")


func _card_gate() -> void:
	_clear_card()
	if sim.gate_group.is_empty():
		close_card()
		return
	var free := sim.beds_free()
	_header("pessoa", tr("UI_GATE_TITLE"))
	var top := _row([_label(fmt("UI_GATE_PICK" if free == 1 else "UI_GATE_PICK_N", {"n": free}) if free > 0 else "", C_MUTED)])
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var none := Button.new()
	none.text = tr("UI_GATE_NONE")
	none.pressed.connect(func() -> void:
		sim.choose(-1)
		close_card())
	top.add_child(none)
	_card_box.add_child(top)
	if free <= 0:
		_card_box.add_child(_row([_icon_rect("cama"), _icon_rect("alerta"), _label(tr("UI_GATE_NOBED"), C_WARN)]))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 3)
	for i in sim.gate_group.size():
		var c: Dictionary = sim.gate_group[i]
		var pc := PanelContainer.new()
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(96, 0)
		pc.add_child(v)
		var face := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = load(ART + "person_%d.png" % int(c["look"]))
		at.region = Rect2(0, 0, 16, 16)
		face.texture = at
		face.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		face.custom_minimum_size = Vector2(16, 16)
		v.add_child(_row([face, _label(String(c["name"]), C_AMBER)]))
		v.add_child(_wrap("\"" + tr("BIO_%d" % int(c["bio"])) + "\"", C_MUTED, 92))
		v.add_child(HSeparator.new())
		_passive_lines(c["passives"], v)
		var br: Dictionary = c.get("brings", {})
		for r in br:
			v.add_child(_row([_icon_rect(r), _label(fmt("UI_BRINGS", {"n": br[r], "r": tr("RES_" + r)}), C_GOOD)]))
		var pick := Button.new()
		pick.text = tr("UI_CHOOSE")
		pick.disabled = free <= 0
		var idx := i
		pick.pressed.connect(func() -> void:
			var nm := String(c["name"])
			sim.choose(idx)
			toast(fmt("UI_JOINED", {"name": nm}))
			close_card())
		v.add_child(pick)
		cols.add_child(pc)
	_card_box.add_child(cols)


func _card_build() -> void:
	_clear_card()
	_header("martelo", tr("UI_BUILD"))
	var locked: Array[String] = []
	for tp in sim.bal["build_order"]:
		var type := String(tp)
		if not sim.unlocked(type):
			locked.append(type)
			continue
		var lv: Dictionary = sim.def(type)["levels"][0]
		var btn := Button.new()
		btn.text = bname(type)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(62, 12)
		btn.disabled = not sim.can_afford(lv["cost"])
		btn.tooltip_text = tr("BD_" + type)
		btn.pressed.connect(func() -> void:
			close_card()
			build_chosen.emit(type))
		var row := _row([btn, _cost_row(lv["cost"]), _icon_rect("relogio"), _label(fmt_time(float(lv["time_s"])), C_MUTED)])
		_card_box.add_child(row)
	for type in locked:
		var need: int = int(sim.def(type).get("tower", 1))
		_card_box.add_child(_row([_icon_rect("cadeado"), _label("%s · %s" % [bname(type), fmt("UI_LOCKED_TOWER", {"n": need})], C_MUTED)]))
