class_name PlotTip
extends Node2D
## Feedback do plantio: barrinha de crescimento sob cada planta, selo "pronta" e, ao passar o mouse,
## uma etiqueta com cultura, fase, % e tempo para colher. Também solta "+1 cesto" a cada colheita.
## Só lê `view.link.plots()`; não mexe na economia.

const BAR_W: int = 12
const POP_SEC: float = 1.4
const REFRESH_SEC: float = 0.2

var view: BunkerView

var _plots: Array = []
var _t: float = 0.0
var _pops: Array = []   # {pos: Vector2, t: float}
var _tip_lines: PackedStringArray = PackedStringArray()
var _tip_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	z_index = 9


func pop(pos: Vector2) -> void:
	_pops.append({"pos": pos, "t": 0.0})


func _process(delta: float) -> void:
	_t += delta
	if _t >= REFRESH_SEC:
		_t = 0.0
		_plots = view.link.plots()
	for i in range(_pops.size() - 1, -1, -1):
		_pops[i]["t"] = float(_pops[i]["t"]) + delta
		if float(_pops[i]["t"]) >= POP_SEC:
			_pops.remove_at(i)
	_update_tip()
	queue_redraw()


## Plantas da estrutura sob o mouse: a mais próxima do ponteiro vira a etiqueta.
func _update_tip() -> void:
	_tip_lines = PackedStringArray()
	if view == null or view.is_arrival_running():
		return
	var m: Vector2 = view.get_local_mouse_position()
	var hit: Dictionary = view.get_object_at(m)
	if String(hit.get("kind", "")) != "instance":
		return
	var best: Dictionary = {}
	var best_d: float = 1e9
	for p: Dictionary in _plots:
		if int(p["instance"]) != int(hit["id"]):
			continue
		var d: float = view.plot_pos(p).distance_to(m)
		if d < best_d:
			best_d = d
			best = p
	if best.is_empty():
		return
	var crop: String = ScreenUtil.tr_key("crop.%s.name" % String(best["crop"]))
	var pct: int = int(floorf(float(best["progress"]) * 100.0))
	if bool(best["ready"]):
		_tip_lines.append(crop)
		_tip_lines.append(ScreenUtil.tr_key("plot.ready"))
	else:
		_tip_lines.append(ScreenUtil.tr_key("plot.line", {"crop": crop,
				"stage": ScreenUtil.tr_key("plot.stage.%d" % int(best["stage"])), "pct": pct}))
		_tip_lines.append(ScreenUtil.tr_key("plot.eta", {"t": _fmt(float(best.get("eta_min", 0.0)))}))
	if not view.link.is_awake():
		_tip_lines.append(ScreenUtil.tr_key("plot.asleep"))
	_tip_pos = view.plot_pos(best)


func _fmt(minutes: float) -> String:
	var m: int = maxi(1, int(ceilf(minutes)))
	if m >= 60:
		return ScreenUtil.tr_key("plot.eta_h", {"h": m / 60, "m": m % 60})
	return ScreenUtil.tr_key("plot.eta_m", {"m": m})


func _draw() -> void:
	var ink: Color = BunkerGeo.pal("ink")
	for p: Dictionary in _plots:
		if not view.plot_shown(p):
			continue
		var pos: Vector2 = view.plot_pos(p).round()
		var x: float = pos.x - BAR_W * 0.5
		var y: float = pos.y + 2.0
		var prog: float = clampf(float(p["progress"]), 0.0, 1.0)
		draw_rect(Rect2(x - 1, y - 1, BAR_W + 2, 4), ink)
		var col: Color = UiTheme.SIGNAL if bool(p["ready"]) else UiTheme.AMBER3
		draw_rect(Rect2(x, y, floorf(BAR_W * prog), 2), col)
	var font: Font = UiTheme.font()
	var fs: int = UiTheme.SIZE_SMALL
	for pp: Dictionary in _pops:
		var k: float = float(pp["t"]) / POP_SEC
		var c: Color = UiTheme.SIGNAL
		c.a = 1.0 - k * k
		var at: Vector2 = (pp["pos"] as Vector2) + Vector2(-14, -12 - 14 * k)
		var txt: String = ScreenUtil.tr_key("plot.gain")
		draw_string_outline(font, at.round(), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(ink, c.a))
		draw_string(font, at.round(), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
	if _tip_lines.is_empty():
		return
	var w: float = 0.0
	for l in _tip_lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var lh: float = font.get_height(fs)
	var box := Rect2(0, 0, w + 8, lh * _tip_lines.size() + 4)
	box.position = Vector2(_tip_pos.x - box.size.x * 0.5, _tip_pos.y - 12 - box.size.y)
	box.position.x = clampf(box.position.x, 1.0, maxf(1.0, view.strip_width() - box.size.x - 1.0))
	box.position.y = maxf(box.position.y, 1.0)
	box.position = box.position.round()
	draw_rect(box, Color(ink, 0.92))
	draw_rect(box, UiTheme.AMBER3, false, 1.0)
	for i in _tip_lines.size():
		var col2: Color = UiTheme.PAPER if i == 0 else UiTheme.AMBER3
		draw_string(font, box.position + Vector2(4, 2 + font.get_ascent(fs) + lh * i), _tip_lines[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col2)
