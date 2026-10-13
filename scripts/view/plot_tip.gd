class_name PlotTip
extends Node2D
## Camada de clareza sobre o corte do bunker (só lê `view.link`; não mexe na economia):
##  - hover em tudo que é clicável: contorno de 1 px + etiqueta curta (cinza quando não dá para usar agora);
##  - um relógio só para tudo que leva tempo: círculo que enche + contagem ("1h48", "45min").
##    Sempre visível só na obra/escavação em curso; planta no hover (check verde quando pronta);
##    espera da caixa no hover;
##  - selo de cestos em cima da caixa só quando ela está cheia;
##  - seta e contorno do tutorial no objeto certo;
##  - plaquinhas numeradas das ordens na fila e o "+N%" / "+1 cesto" que flutua.

const POP_SEC: float = 1.4
const REFRESH_SEC: float = 0.2
const CLOCK_R: float = 4.5

var view: BunkerView

var _plots: Array = []
var _jobs: Array = []   # obras (Game.active_jobs): instance, item, ratio, eta_min
var _t: float = 0.0
var _pulse: float = 0.0
var _pops: Array = []   # {pos: Vector2, t: float}
var _hover: Dictionary = {}   # {rect, lines, pos, grey, clock: {ratio, text, pos}}
var _box: Dictionary = {}     # {full, stock, wait_left, wait_total}


func _ready() -> void:
	z_index = 9


func pop(pos: Vector2, text: String = "") -> void:
	_pops.append({"pos": pos, "t": 0.0, "text": text})


## Linhas da etiqueta sob o mouse (para testes).
func hover_lines() -> PackedStringArray:
	return PackedStringArray(_hover.get("lines", PackedStringArray()))


func hover_rect() -> Rect2:
	return _hover.get("rect", Rect2())


func hover_grey() -> bool:
	return bool(_hover.get("grey", false))


func _process(delta: float) -> void:
	_t += delta
	_pulse += delta
	if _t >= REFRESH_SEC:
		_t = 0.0
		_plots = view.link.plots()
		_jobs = view.link.active_jobs()
		_refresh_box()
	for i in range(_pops.size() - 1, -1, -1):
		_pops[i]["t"] = float(_pops[i]["t"]) + delta
		if float(_pops[i]["t"]) >= POP_SEC:
			_pops.remove_at(i)
	_update_hover()
	queue_redraw()


func _refresh_box() -> void:
	var cap: int = view.link.box_capacity()
	var w: Dictionary = view.link.q("help_box_wait", {"left": 0.0, "total": 1.0}) as Dictionary
	_box = {"full": cap > 0 and view.link.box_fill() >= 1.0, "stock": view.link.box_stock(),
			"left": float(w.get("left", 0.0)), "total": maxf(1.0, float(w.get("total", 1.0))),
			"why": String(view.link.q("help_box_check", "off"))}


# ---------------------------------------------------------------- hover

func _update_hover() -> void:
	_hover = {}
	if view == null or view.is_arrival_running() or not view.hover_enabled:
		return
	var m: Vector2 = view.get_local_mouse_position()
	var hit: Dictionary = view.get_object_at(m)
	var rect: Rect2 = view.rect_of(hit)
	if rect.size == Vector2.ZERO:
		return
	var lines := PackedStringArray()
	var grey := false
	var pos: Vector2 = Vector2(rect.get_center().x, rect.position.y)
	var clock: Dictionary = {}
	match String(hit["kind"]):
		"man":
			var act: String = String(view.man.activity)
			var key: String = "act." + act
			lines.append(ScreenUtil.tr_key("hover.man", {"act": ScreenUtil.tr_key(key if I18nRef.has_key(key) else "act.idle")}))
		"hatch", "box":
			grey = _hover_box(lines, clock, rect)
		"radio":
			lines.append(ScreenUtil.tr_key("tab.radio"))
			var n: int = view.link.unread_count()
			if n > 0:
				lines.append(ScreenUtil.tr_key("hover.radio_new", {"n": n}))
		"antenna":
			lines.append(ScreenUtil.tr_key("ui.antenna", {"n": view.link.antenna()}))
		"instance":
			pos = _hover_instance(hit, rect, lines, m, clock)
	if lines.is_empty():
		return
	_hover = {"rect": rect, "lines": lines, "pos": pos, "grey": grey, "clock": clock}


## Caixa: "Vender 4 cestos" / espera com relógio cinza. Devolve true se não dá para usar agora.
func _hover_box(lines: PackedStringArray, clock: Dictionary, rect: Rect2) -> bool:
	lines.append(ScreenUtil.tr_key("ui.box"))
	if not bool(view.link.q("help_box_available", false)):
		lines.append(ScreenUtil.tr_key("card.box.auto"))
		return false
	if not view.link.is_awake():
		lines.append(ScreenUtil.tr_key("hover.box_asleep"))
		return true
	match String(_box.get("why", "off")):
		"ok":
			var n: int = int(_box.get("stock", 0))
			lines.append(ScreenUtil.tr_key("hover.box_sell1") if n == 1 else ScreenUtil.tr_key("hover.box_sell", {"n": n}))
			return false
		"cooldown":
			var left: float = float(_box.get("left", 0.0))
			lines.append(ScreenUtil.tr_key("card.box.wait", {"t": ClockText.of(left)}))
			clock["ratio"] = 1.0 - left / float(_box.get("total", 1.0))
			clock["text"] = ClockText.of(left)
			clock["pos"] = Vector2(rect.get_center().x, rect.position.y - 8.0)
			return true
		"empty":
			lines.append(ScreenUtil.tr_key("hover.box_empty"))
			return true
	return false


func _hover_instance(hit: Dictionary, rect: Rect2, lines: PackedStringArray, m: Vector2, clock: Dictionary) -> Vector2:
	var pos := Vector2(rect.get_center().x, rect.position.y + 6.0)
	var id: int = int(hit["id"])
	var item_name: String = ScreenUtil.tr_key("item.%s.name" % String(hit["item"]))
	var job: Dictionary = _job_of(id)
	if not job.is_empty():
		lines.append(ScreenUtil.tr_key("plot.build", {"item": item_name}))
		lines.append(ScreenUtil.tr_key("plot.build_eta", {"t": ClockText.of(float(job.get("eta_min", 0.0)))}))
		if bool(view.link.q("help_available", false)):
			lines.append(ScreenUtil.tr_key("plot.build_help"))
		return pos
	if view.is_generator(String(hit["item"])):
		lines.append(item_name)
		var ok: bool = view.link.power_ok()
		var g: Object = view.game
		if g != null and g.has_method("power_supply"):
			var gap: int = int(g.call("power_supply")) - int(g.call("power_demand"))
			lines.append(ScreenUtil.tr_key("card.gen.ok", {"n": gap}) if ok else ScreenUtil.tr_key("card.gen.lack", {"n": -gap}))
		return pos
	var best: Dictionary = {}
	var best_d: float = 1e9
	for p: Dictionary in _plots:
		if int(p["instance"]) != id:
			continue
		var d: float = view.plot_pos(p).distance_to(m)
		if d < best_d:
			best_d = d
			best = p
	if best.is_empty():
		lines.append(item_name)
		return pos
	var crop: String = ScreenUtil.tr_key("crop.%s.name" % String(best["crop"]))
	var eta: float = float(best.get("eta_min", 0.0))
	if bool(best["ready"]):
		lines.append(crop)
		lines.append(ScreenUtil.tr_key("plot.ready"))
	else:
		lines.append(ScreenUtil.tr_key("plot.line", {"crop": crop, "stage": ScreenUtil.tr_key("plot.stage.%d" % int(best["stage"]))}))
		lines.append(ScreenUtil.tr_key("plot.eta", {"t": ClockText.of(eta)}))
		clock["ratio"] = clampf(float(best["progress"]), 0.0, 1.0)
		clock["text"] = ClockText.of(eta)
		clock["pos"] = view.plot_pos(best) + Vector2(0, -16)
	if not view.link.is_awake():
		lines.append(ScreenUtil.tr_key("plot.asleep"))
	elif bool(view.link.q("help_plots_available", false)):
		lines.append(ScreenUtil.tr_key("plot.tend_help"))
	else:
		lines.append(ScreenUtil.tr_key("plot.auto"))
	return view.plot_pos(best)


func _job_of(instance_id: int) -> Dictionary:
	for j: Dictionary in _jobs:
		if int(j.get("instance", -1)) == instance_id:
			return j
	return {}


# ---------------------------------------------------------------- desenho

func _draw() -> void:
	var ink: Color = BunkerGeo.pal("ink")
	var font: Font = UiTheme.font()
	var fs: int = UiTheme.SIZE_SMALL
	# planta pronta: check verde em cima dela (enquanto cresce não mostra nada)
	var check: Texture2D = UiTheme.icon("check")
	for p: Dictionary in _plots:
		if bool(p["ready"]) and view.plot_shown(p) and check != null:
			draw_texture(check, (view.plot_pos(p) + Vector2(-4, -17)).round())
	# o relógio que fica sempre: a obra/escavação em curso (uma por vez)
	if not _jobs.is_empty():
		_draw_job_clock(_jobs[0], font, fs, ink)
	_draw_tutorial(ink)
	_draw_box_badge(font, fs, ink)
	_draw_hover(font, fs, ink)
	_draw_orders(font, fs, ink)
	for pp: Dictionary in _pops:
		var k: float = float(pp["t"]) / POP_SEC
		var c: Color = UiTheme.SIGNAL
		c.a = 1.0 - k * k
		var at: Vector2 = (pp["pos"] as Vector2) + Vector2(-14, -12 - 14 * k)
		var txt: String = String(pp.get("text", ""))
		if txt == "":
			txt = ScreenUtil.tr_key("plot.gain")
		draw_string_outline(font, at.round(), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(ink, c.a))
		draw_string(font, at.round(), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


func _draw_job_clock(j: Dictionary, font: Font, fs: int, ink: Color) -> void:
	var at := Vector2.ZERO
	if String(j.get("item", "")).begins_with("comodo"):
		at = view.dig_anchor()
	else:
		var o: BunkerObject = view.object_by_id(int(j.get("instance", -1)))
		if o == null:
			return
		var b: Rect2 = o.bounds()
		at = Vector2(b.get_center().x, maxf(BunkerGeo.wall_y(o.room) + 8.0, b.position.y - 8.0))
	_draw_clock(at, float(j["ratio"]), ClockText.of(float(j.get("eta_min", 0.0))), UiTheme.AMBER3, font, fs, ink)


## O relógio único: disco de 9 px que enche no sentido horário + contagem ao lado (centrado em `at`).
func _draw_clock(at: Vector2, ratio: float, text: String, tone: Color, font: Font, fs: int, ink: Color) -> void:
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if text != "" else 0.0
	var total: float = CLOCK_R * 2.0 + (3.0 + tw if text != "" else 0.0)
	var x0: float = clampf(at.x - total * 0.5, 1.0, maxf(1.0, view.strip_width() - total - 1.0))
	var c := Vector2(x0 + CLOCK_R, at.y).round()
	if text != "":
		var tb := Rect2(c.x + CLOCK_R + 1.0, c.y - 5.0, tw + 4.0, 10.0)
		draw_rect(tb, Color(ink, 0.8))
	draw_circle(c, CLOCK_R, ink)
	draw_circle(c, CLOCK_R - 1.0, UiTheme.DARK2)
	draw_arc(c, CLOCK_R - 1.0, 0.0, TAU, 20, Color(tone, 0.55), 1.0)   # aro: o relógio vazio também aparece
	ratio = clampf(ratio, 0.0, 1.0)
	if ratio > 0.01:
		var n: int = maxi(3, int(ratio * 28.0))
		var pts := PackedVector2Array([c])
		for i in n + 1:
			var a: float = -PI * 0.5 + TAU * ratio * float(i) / float(n)
			pts.append(c + Vector2(cos(a), sin(a)) * (CLOCK_R - 1.0))
		draw_colored_polygon(pts, tone)
	if text != "":
		var tp := Vector2(c.x + CLOCK_R + 3.0, c.y + 4.0).round()
		draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.PAPER)


## Selo de cestos em cima da caixa: só aparece (vermelho, pulsando) quando ela está cheia.
func _draw_box_badge(font: Font, fs: int, ink: Color) -> void:
	if not bool(_box.get("full", false)):
		return
	var b: Rect2 = view.rect_of({"kind": "box"})
	if b.size == Vector2.ZERO:
		return
	var label: String = str(int(_box["stock"]))
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(Vector2(b.position.x - 1.0, b.position.y - 13.0).round(), Vector2(tw + 14.0, 11.0).round())
	var lit: bool = fmod(_pulse, 1.0) < 0.6
	draw_rect(box.grow(1), ink)
	draw_rect(box, UiTheme.TOMATO if lit else UiTheme.RUST2)
	var ic: Texture2D = UiTheme.icon("cesto")
	if ic != null:
		draw_texture(ic, box.position + Vector2(2, 1.5))
	draw_string(font, box.position + Vector2(12, 8.5).round(), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.PAPER)


## Tutorial: contorno piscando e seta quicando no objeto do passo (a linha de texto fica na barra).
func _draw_tutorial(ink: Color) -> void:
	var r := Rect2()
	match view.tutorial_key:
		"tut.1", "tut.2":
			var best: Dictionary = {}
			for p: Dictionary in _plots:
				if view.plot_shown(p) and (best.is_empty() or float(p["progress"]) > float(best["progress"])):
					best = p
			if not best.is_empty():
				var o: BunkerObject = view.object_by_id(int(best["instance"]))
				r = o.bounds() if o != null else Rect2()
		"tut.3":
			r = view.rect_of({"kind": "box"})
	if r.size == Vector2.ZERO:
		return
	if fmod(_pulse, 0.9) < 0.6:
		draw_rect(r.grow(1), UiTheme.AMBER3, false, 1.0)
	var bob: float = 2.0 * absf(sin(_pulse * 4.0))
	var tip := Vector2(r.get_center().x, r.position.y - 3.0 - bob).round()
	draw_colored_polygon(PackedVector2Array([tip + Vector2(0, 2), tip + Vector2(-7, -8), tip + Vector2(7, -8)]), ink)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-5, -6), tip + Vector2(5, -6)]), UiTheme.AMBER4)


func _draw_hover(font: Font, fs: int, ink: Color) -> void:
	if _hover.is_empty():
		return
	var rect: Rect2 = _hover["rect"]
	var grey: bool = bool(_hover["grey"])
	draw_rect(rect.grow(1), UiTheme.CONC3 if grey else UiTheme.AMBER3, false, 1.0)
	var clock: Dictionary = _hover["clock"]
	if not clock.is_empty():
		_draw_clock(clock["pos"], float(clock["ratio"]), String(clock["text"]), UiTheme.CONC3 if grey else UiTheme.AMBER3, font, fs, ink)
	var lines: PackedStringArray = _hover["lines"]
	var w: float = 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var lh: float = font.get_height(fs)
	var box := Rect2(0, 0, w + 8, lh * lines.size() + 4)
	var tip_pos: Vector2 = _hover["pos"]
	box.position = Vector2(tip_pos.x - box.size.x * 0.5, rect.position.y - 4 - box.size.y)
	if not clock.is_empty():
		box.position.y -= 11.0
	box.position.x = clampf(box.position.x, 1.0, maxf(1.0, view.strip_width() - box.size.x - 1.0))
	if box.position.y < 1.0:
		box.position.y = rect.end.y + 4.0
	box.position = box.position.round()
	draw_rect(box, Color(ink, 0.92))
	draw_rect(box, UiTheme.CONC3 if grey else UiTheme.AMBER3, false, 1.0)
	for i in lines.size():
		var col2: Color = UiTheme.PAPER if i == 0 else UiTheme.AMBER3
		draw_string(font, box.position + Vector2(4, 2 + font.get_ascent(fs) + lh * i), lines[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col2)


## Marca das ordens na fila: uma plaquinha por alvo, com o número da primeira vez que ele passa ali
## (a plaquinha da ordem em andamento pulsa).
func _draw_orders(font: Font, fs: int, ink: Color) -> void:
	var seen: Dictionary = {}
	var n: int = 0
	for o: Dictionary in view.orders:
		n += 1
		var at: Variant = view.order_anchor(o)
		if at == null or seen.has(at):
			continue
		seen[at] = true
		var c: Vector2 = (at as Vector2).round()
		var lit: bool = n > 1 or fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.5
		var box := Rect2(c.x - 4, c.y - 4, 9, 10)
		draw_rect(box.grow(1), ink)
		draw_rect(box, UiTheme.AMBER3 if lit else UiTheme.AMBER2)
		var label: String = str(n)
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x + 0.5 - tw * 0.5, c.y + 4.0).round(), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
