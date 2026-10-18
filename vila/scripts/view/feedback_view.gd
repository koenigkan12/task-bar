class_name VilaFeedback
extends Node2D
## Retorno visual dos eventos do dia a dia (só desenho; nada aqui decide regra):
## obra pronta (brilho verde, ✓ e o prédio dá um pulinho), "+N" subindo de quem entregou no
## depósito, prédio parado mostrando o que falta (recurso riscado, raio riscado, caixa cheia),
## a torre subindo (a borda da área abre animada), a névoa vindo no fim da tarde, o entulho
## encolhendo enquanto catam e a contagem do mascate antes de ir embora.

const TILE := 16
const GREEN := Color8(169, 220, 140)
const AMBER := Color8(232, 168, 72)
const RED := Color8(214, 58, 52)
const DARK := Color(0.08, 0.05, 0.1, 0.9)
const POLLEN := Color8(222, 200, 92)

var sim: VilaSim
var world: WorldView
var _icons: Texture2D
var _layer: Node2D                      # camada clara (o escuro da noite não apaga)
var _t := 0.0
var _done: Array[Dictionary] = []       # {pos, t0, w}: obra pronta agora
var _pops: Array[Dictionary] = []       # {pos, t0, res, n}: "+N" subindo
var _ring := {}                         # torre subiu: {t0, r0, r1}
var _scale_acc := 0.0


func setup(s: VilaSim, w: WorldView, icons: Texture2D) -> void:
	sim = s
	world = w
	_icons = icons
	var gl := CanvasLayer.new()
	gl.layer = 1
	gl.follow_viewport_enabled = true
	add_child(gl)
	_layer = Node2D.new()
	_layer.draw.connect(_draw_layer)
	gl.add_child(_layer)
	sim.building_done.connect(_on_done)
	sim.harvested.connect(_on_harvest)
	sim.tower_up.connect(_on_tower)


func _bal(key: String, def: float) -> float:
	return float(sim.bal.get("feedback", {}).get(key, def))


# ================================================================ eventos
func _on_done(id: int) -> void:
	var b := sim.by_id(id)
	if b.is_empty() or sim.offline:
		return
	var fp := sim._fp(String(b["type"]))
	var c := Vector2i(b["cell"])
	_done.append({"pos": Vector2((c.x + fp.x / 2.0) * TILE, (c.y + fp.y) * TILE), "t0": _t, "w": float(fp.x * TILE), "id": id})
	# O prédio dá um pulinho de 1 px ao aparecer (o muro é desenhado à parte: só o brilho).
	var n: Dictionary = world._bnodes.get(id, {})
	if not n.is_empty():
		var spr: Sprite2D = n["sprite"]
		var tw := spr.create_tween()
		tw.tween_property(spr, "position:y", -1.0, 0.08)
		tw.tween_property(spr, "position:y", 0.0, 0.12)
	if AudioManager.SFX_NAMES.has("done"):
		AudioManager.play_sfx("done")


func _on_harvest(pid: int, res: String, n: int) -> void:
	var p := sim.person(pid)
	if p.is_empty() or sim.offline or n <= 0:
		return
	_pops.append({"pos": world._person_world(p) + Vector2(0, -14), "t0": _t, "res": res, "n": n})


func _on_tower(level: int) -> void:
	if sim.offline:
		return
	_ring = {"t0": _t, "r0": sim.open_radius(level - 1) if level > 1 else 0.0, "r1": sim.open_radius(level)}


# ================================================================ quadro a quadro
func _process(delta: float) -> void:
	if sim == null:
		return
	_t += delta
	_done = _done.filter(func(e: Dictionary) -> bool: return _t - float(e["t0"]) < 1.2)
	_pops = _pops.filter(func(e: Dictionary) -> bool: return _t - float(e["t0"]) < 1.4)
	if not _ring.is_empty() and _t - float(_ring["t0"]) > 3.0:
		_ring = {}
	_scale_acc += delta
	if _scale_acc >= 0.25:
		_scale_acc = 0.0
		_shrink_rubble()
	_layer.queue_redraw()


## Entulho encolhe conforme catam (8 de sucata no começo; cada viagem leva um pouco).
func _shrink_rubble() -> void:
	var full := float(sim.bal.get("rubble_amount", 8))
	for c in world._terrain_nodes:
		if sim.terrain_at(c) != VilaSim.T_RUBBLE:
			continue
		var spr: Sprite2D = world._terrain_nodes[c]
		var left := float(sim.rubble.get(c, full))
		var k := clampf(0.55 + 0.45 * left / maxf(1.0, full), 0.55, 1.0)
		if absf(spr.scale.y - k) > 0.01:
			spr.scale = Vector2(k, k)


func _icon(i: int, at: Vector2, col: Color = Color.WHITE) -> void:
	if _icons != null:
		_layer.draw_texture_rect_region(_icons, Rect2(at.round(), Vector2(8, 8)), Rect2(i * 8, 0, 8, 8), col)


## Ícone riscado (o que está faltando): fundo escuro, ícone, traço vermelho na diagonal.
func _crossed(i: int, at: Vector2, alpha: float) -> void:
	at = at.round()
	_layer.draw_rect(Rect2(at - Vector2(1, 1), Vector2(10, 10)), Color(DARK, 0.9 * alpha))
	_icon(i, at, Color(1, 1, 1, alpha))
	_layer.draw_line(at + Vector2(-0.5, 8.5), at + Vector2(8.5, -0.5), Color(RED, alpha), 1.5)


func _draw_layer() -> void:
	_draw_fog_band()
	_draw_ring()
	_draw_stalls()
	_draw_done()
	_draw_pops()
	_draw_merchant()


func _draw_done() -> void:
	for e in _done:
		var k := (_t - float(e["t0"])) / 1.2
		var base: Vector2 = e["pos"]
		var w := float(e["w"])
		# Faíscas verdes subindo do prédio e o ✓ que sobe e some.
		for i in 6:
			var x := base.x - w * 0.4 + w * 0.8 * (float(i) / 5.0)
			var y := base.y - 4.0 - k * (14.0 + (i % 3) * 5.0)
			_layer.draw_rect(Rect2(Vector2(x, y).round(), Vector2(1, 2)), Color(GREEN, 1.0 - k))
		var c := (base + Vector2(0, -24.0 - k * 10.0)).round()
		_layer.draw_circle(c, 6.0, Color(DARK, 0.9 * (1.0 - k)))
		_layer.draw_circle(c, 5.0, Color(GREEN, 1.0 - k))
		_layer.draw_line(c + Vector2(-3, 0), c + Vector2(-1, 2), Color(0.1, 0.18, 0.1, 1.0 - k), 1.5)
		_layer.draw_line(c + Vector2(-1, 2), c + Vector2(3, -2), Color(0.1, 0.18, 0.1, 1.0 - k), 1.5)


func _draw_pops() -> void:
	for e in _pops:
		var k := (_t - float(e["t0"])) / 1.4
		var at := (Vector2(e["pos"]) + Vector2(-6, -k * 10.0)).round()
		var txt := "+%d" % int(e["n"])
		var a := clampf(2.0 - 2.0 * k, 0.0, 1.0)
		var wdt := 9.0 + world._tiny_width(txt)
		_layer.draw_rect(Rect2(at + Vector2(-1, -1), Vector2(wdt + 2, 10)), Color(0.26, 0.2, 0.33, 0.85 * a))
		_icon(world._res_icon(String(e["res"])), at, Color(1, 1, 1, a))
		_tiny(at + Vector2(9, 2), txt, Color(GREEN, a))


## Prédio parado: o recurso que falta riscado, raio riscado sem energia, caixa cheia com o depósito lotado.
func _draw_stalls() -> void:
	var blink := 1.0 if int(_t * 2.0) % 2 == 0 else 0.45
	var pf := sim.power_frac()
	for b in sim.buildings:
		if not sim._working(b):
			continue
		var tp := String(b["type"])
		var d := sim.def(tp)
		var lv := sim.level_def(b)
		var marks: Array = []   # [ícone, tipo] tipo: x (riscado) ou full
		if d.has("power_use") and pf < 0.999:
			marks.append([17, "x"])
		var inp: Dictionary = lv.get("input", {})
		for r in inp:
			if float(sim.stock[r]) < float(inp[r]):
				marks.append([world._res_icon(String(r)), "x"])
		var res := String(d.get("res", ""))
		if res in VilaSim.RES and lv.has("slots") and float(sim.stock[res]) >= sim.cap(res) - 0.01:
			marks.append([world._res_icon(res), "full"])
		if marks.is_empty():
			continue
		var fp := sim._fp(tp)
		var top := Vector2((Vector2i(b["cell"]).x + fp.x / 2.0) * TILE, Vector2i(b["cell"]).y * TILE)
		var bn: Dictionary = world._bnodes.get(int(b["id"]), {})
		if not bn.is_empty() and (bn["sprite"] as Sprite2D).texture != null:
			var sp: Sprite2D = bn["sprite"]
			top.y = (Vector2i(b["cell"]).y + fp.y) * TILE - float(sp.texture.get_height() / sp.vframes)
		var x0 := top.x - marks.size() * 6.0 + 1.0
		for i in marks.size():
			var at := Vector2(x0 + i * 12.0, top.y - 12.0)
			if String(marks[i][1]) == "x":
				_crossed(int(marks[i][0]), at, blink)
			else:
				# Caixa cheia: o recurso dentro de uma moldura âmbar (não cabe mais nada).
				var a := at.round()
				_layer.draw_rect(Rect2(a - Vector2(1, 1), Vector2(10, 10)), DARK)
				_icon(int(marks[i][0]), a)
				_layer.draw_rect(Rect2(a - Vector2(1, 1), Vector2(10, 10)), AMBER, false, 1.0)


## Torre subiu: um anel tracejado sai da borda velha e abre até a nova; o chão novo brilha de leve.
func _draw_ring() -> void:
	if _ring.is_empty():
		return
	var k := clampf((_t - float(_ring["t0"])) / 2.2, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var c := sim.center() * TILE + Vector2(TILE, TILE) / 2.0
	var r := lerpf(float(_ring["r0"]), float(_ring["r1"]), e) * TILE
	var a := 1.0 if k < 0.8 else (1.0 - k) / 0.2
	var n := 72
	for i in n:
		if i % 2 == 1:
			continue
		var a0 := TAU * i / n + _t * 0.3
		var a1 := TAU * (i + 1) / n + _t * 0.3
		_layer.draw_line(c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r, Color(1.0, 0.92, 0.6, 0.9 * a), 2.0)
	_layer.draw_arc(c, r, 0.0, TAU, 96, Color(1.0, 0.92, 0.6, 0.18 * a), 8.0)


## Névoa avisada: uma faixa de pólen amarelo vem do oeste no fim da tarde, mais perto quanto mais
## perto da noite (o vento traz a névoa).
func _draw_fog_band() -> void:
	if not sim.fog_next or sim.is_night():
		return
	var warn := float(sim.bal["fog"].get("warn_h", 3.0))
	var to_night := fposmod(float(sim.bal["time"]["night_from_h"]) - sim.local_hour(), 24.0)
	if to_night > warn:
		return
	var k := 1.0 - to_night / warn
	var ws := world.world_size()
	var front := 40.0 + (ws.x * 0.4) * k
	# Atrás da frente, o pólen fica mais denso (a névoa já chegou ali).
	_layer.draw_rect(Rect2(Vector2(-400, -100), Vector2(front - 60.0 + 400.0, ws.y + 200)), Color(POLLEN, 0.10 + 0.10 * k))
	for i in 140:
		var h := float(i) * 37.13
		var y := fposmod(h * 13.7, ws.y + 100.0) - 50.0
		var x := front - fposmod(h * 5.3, 120.0) + sin(_t * 0.8 + h) * 6.0
		var rr := 5.0 + fposmod(h, 5.0)
		_layer.draw_circle(Vector2(x, y + sin(_t * 0.5 + h) * 4.0), rr, Color(POLLEN, 0.16 + 0.16 * k))
	for i in 24:
		var h2 := float(i) * 71.7
		var p := Vector2(front + fposmod(h2 * 3.1 + _t * 9.0, 40.0) - 20.0, fposmod(h2 * 9.3 + _t * 4.0, ws.y))
		_layer.draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(1.0, 0.95, 0.55, 0.7 * k))


## Mascate na praça: "!" em cima dele; nos últimos minutos, a contagem até ir embora.
func _draw_merchant() -> void:
	if not sim.merchant_here() or world._m_state != "here" or world._merchant_nodes.size() < 2:
		return
	var man: Sprite2D = world._merchant_nodes[1]
	var left := float(sim.merchant.get("until", sim.t)) - sim.t
	var bob := roundf(sin(_t * 4.0))
	var at := (man.position + Vector2(-3, -26 + bob)).round()
	var soon := left <= float(sim.bal["merchant"].get("warn_leave_s", 180.0))
	_layer.draw_rect(Rect2(at - Vector2(1, 1), Vector2(8, 10)), DARK)
	_layer.draw_rect(Rect2(at, Vector2(6, 8)), RED if soon else Color8(232, 200, 72))
	_layer.draw_rect(Rect2(at + Vector2(2, 1), Vector2(2, 4)), DARK)
	_layer.draw_rect(Rect2(at + Vector2(2, 6), Vector2(2, 1)), DARK)
	if soon and left > 0.0:
		var txt := VilaHud.fmt_clock(left)
		var w := world._tiny_width(txt)
		var tp := at + Vector2(9, 1)
		_layer.draw_rect(Rect2(tp - Vector2(1, 1), Vector2(w + 2, 7)), DARK)
		_tiny(tp, txt, Color(1.0, 0.75, 0.6))


func _tiny(at: Vector2, txt: String, col: Color) -> void:
	var x := at.x
	for ch in txt:
		var rows: Array = WorldView.TINY.get(ch, [])
		if rows.is_empty():
			x += 4.0
			continue
		for y in rows.size():
			var r := String(rows[y])
			for i in r.length():
				if r[i] == "1":
					_layer.draw_rect(Rect2(Vector2(x + i, at.y + y), Vector2.ONE), col)
		x += float(String(rows[0]).length() + 1)
