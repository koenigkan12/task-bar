class_name VilaWater
extends Node2D
## Vida na água em volta da ilha (só desenho): brilhos de onda, rajadas de vento riscando a água,
## um peixe pulando de vez em quando, e o farol do porto. O farol é o aviso de vaga: com cama livre
## a lâmpada fica acesa e o facho gira; sem cama, apagado.

const TILE := 16
const CREME := Color(0.8, 0.776, 0.729)
const LILAS := Color(0.647, 0.573, 0.647)
const LAMP := Vector2(17, 14)          # a lâmpada dentro do sprite do farol
const BEAM_LEN := 110.0
const BEAM_HALF := 0.13                # meia abertura do facho (radianos)
const BEAM_SPEED := 0.9                # voltas por… radianos por segundo

var sim: VilaSim
var _rng := RandomNumberGenerator.new()
var _glints: Array = []                # {p, t, life, w}
var _gusts: Array = []                 # {p, v, t, life, n}
var _fish: Dictionary = {}             # {a, b, t}
var _fish_wait := 4.0
var _gust_wait := 3.0
var _t := 0.0
var _farol: Sprite2D
var _beam: Node2D                      # na camada de cima: a noite não escurece o facho
var _beam_layer: CanvasLayer
var night_k := 0.0


func setup(s: VilaSim, farol_tex: Texture2D, objects: Node2D) -> void:
	sim = s
	_rng.seed = 7
	z_index = -6                        # em cima do chão, embaixo dos barcos e de tudo
	var fc: Array = sim.bal["map"].get("lighthouse", [])
	if farol_tex != null and fc.size() == 2:
		_farol = Sprite2D.new()
		_farol.texture = farol_tex
		_farol.hframes = 2
		_farol.centered = false
		_farol.offset = Vector2(0, -farol_tex.get_height())
		_farol.position = Vector2(float(fc[0]) * TILE, float(fc[1] + 4) * TILE - 2.0)
		objects.add_child(_farol)
		_beam_layer = CanvasLayer.new()
		_beam_layer.layer = 1
		_beam_layer.follow_viewport_enabled = true
		add_child(_beam_layer)
		_beam = Node2D.new()
		_beam.draw.connect(_draw_beam)
		_beam_layer.add_child(_beam)


func lit() -> bool:
	return sim != null and sim.beds_free() > 0


func lamp_pos() -> Vector2:
	return _farol.position + _farol.offset + LAMP if _farol != null else Vector2.ZERO


func _is_open_water(p: Vector2) -> bool:
	var c := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if sim.terrain_at(c + Vector2i(dx, dy)) != VilaSim.T_WATER:
				return false
	if _farol != null and p.distance_to(lamp_pos() + Vector2(0, 40)) < 30.0:
		return false
	return true


func _view_rect() -> Rect2:
	var inv := get_canvas_transform().affine_inverse()
	var vs := get_viewport_rect().size
	return Rect2(inv * Vector2.ZERO, inv.basis_xform(vs))


func _rand_water(r: Rect2) -> Vector2:
	for k in 12:
		var p := Vector2(_rng.randf_range(r.position.x, r.end.x), _rng.randf_range(r.position.y, r.end.y))
		if _is_open_water(p):
			return p.round()
	return Vector2.INF


func update_water(delta: float, nk: float) -> void:
	if sim == null:
		return
	night_k = nk
	_t += delta
	var vr := _view_rect()
	# Brilhos de onda: aparecem, abrem e somem.
	var want := int(vr.get_area() / 9000.0)
	if _glints.size() < want and _rng.randf() < delta * 14.0:
		var p := _rand_water(vr)
		if p != Vector2.INF:
			_glints.append({"p": p, "t": 0.0, "life": _rng.randf_range(1.2, 2.2), "w": _rng.randi_range(3, 6)})
	for g in _glints:
		g["t"] = float(g["t"]) + delta
	_glints = _glints.filter(func(g: Dictionary) -> bool: return float(g["t"]) < float(g["life"]))
	# Rajada: um bando de risquinhos passando rápido pela água.
	_gust_wait -= delta
	if _gust_wait <= 0.0:
		_gust_wait = _rng.randf_range(5.0, 11.0)
		var p := _rand_water(vr)
		if p != Vector2.INF:
			_gusts.append({"p": p, "v": Vector2(_rng.randf_range(45, 70), _rng.randf_range(-6, 6)), "t": 0.0, "life": 1.8, "n": _rng.randi_range(5, 8), "s": _rng.randi()})
	for g in _gusts:
		g["t"] = float(g["t"]) + delta
	_gusts = _gusts.filter(func(g: Dictionary) -> bool: return float(g["t"]) < float(g["life"]))
	# Peixe: pula num arco curto, com respingo na saída e na volta.
	_fish_wait -= delta
	if _fish.is_empty() and _fish_wait <= 0.0:
		_fish_wait = _rng.randf_range(6.0, 14.0)
		var a := _rand_water(vr.grow(-24))
		if a != Vector2.INF:
			var b := a + Vector2(_rng.randf_range(10, 16) * (1 if _rng.randf() < 0.5 else -1), 0)
			if _is_open_water(b):
				_fish = {"a": a, "b": b, "t": 0.0}
	if not _fish.is_empty():
		_fish["t"] = float(_fish["t"]) + delta
		if float(_fish["t"]) > 1.6:
			_fish = {}
	if _farol != null:
		_farol.frame = 0 if lit() else 1
		_beam.queue_redraw()
	queue_redraw()


func _draw() -> void:
	var a_day := 1.0 - night_k * 0.4
	for g in _glints:
		var k := float(g["t"]) / float(g["life"])
		var w := int(g["w"])
		var half := roundi(w * (0.5 + k * 0.5))
		var c := Color(CREME, sin(k * PI) * 0.9 * a_day)
		var p: Vector2 = g["p"]
		draw_rect(Rect2(p + Vector2(-half, 0), Vector2(half * 2, 1)), c)
		if k > 0.4:
			draw_rect(Rect2(p + Vector2(-half - 1, 1), Vector2(1, 1)), c)
			draw_rect(Rect2(p + Vector2(half, 1), Vector2(1, 1)), c)
	for g in _gusts:
		var k := float(g["t"]) / float(g["life"])
		var r := RandomNumberGenerator.new()
		r.seed = int(g["s"])
		var base: Vector2 = g["p"] + Vector2(g["v"]) * float(g["t"])
		for i in int(g["n"]):
			var o := Vector2(r.randf_range(-18, 18), r.randf_range(-10, 10))
			var ln := r.randi_range(4, 9)
			var c := Color(CREME, sin(k * PI) * 0.55 * a_day)
			draw_rect(Rect2((base + o).round(), Vector2(ln, 1)), c)
	if not _fish.is_empty():
		var t := float(_fish["t"])
		var a: Vector2 = _fish["a"]
		var b: Vector2 = _fish["b"]
		if t < 0.7:
			var k := t / 0.7
			var p := a.lerp(b, k) + Vector2(0, -sin(k * PI) * 9.0)
			var dir := signf(b.x - a.x)
			draw_rect(Rect2(p.round() + Vector2(-1, 0), Vector2(3, 2)), LILAS)
			draw_rect(Rect2(p.round() + Vector2(-2 * dir if dir < 0 else 2, -1), Vector2(1, 1)), CREME)
			draw_rect(Rect2(p.round() + Vector2(-2 if dir > 0 else 2, 1), Vector2(1, 1)), LILAS)
		for sp in [[a, 0.0], [b, 0.7]]:
			var st := t - float(sp[1])
			if st >= 0.0 and st < 0.9:
				var rr := 1.0 + st * 6.0
				draw_arc(Vector2(sp[0]) + Vector2(0, 1), rr, PI, TAU, 8, Color(CREME, (1.0 - st / 0.9) * 0.8), 1.0)


func _draw_beam() -> void:
	if _farol == null or not lit():
		return
	var o := lamp_pos()
	var strength := lerpf(0.16, 0.42, night_k)
	var warm := Color(0.98, 0.89, 0.6)
	var ang := _t * BEAM_SPEED
	for side in [0.0, PI]:
		var a: float = ang + float(side)
		var tip1 := o + Vector2.from_angle(a - BEAM_HALF) * BEAM_LEN
		var tip2 := o + Vector2.from_angle(a + BEAM_HALF) * BEAM_LEN
		_beam.draw_polygon(PackedVector2Array([o, tip1, tip2]),
				PackedColorArray([Color(warm, strength), Color(warm, 0.0), Color(warm, 0.0)]))
	var glow := 0.5 + 0.5 * sin(_t * 3.0)
	_beam.draw_circle(o, 3.0 + glow, Color(warm, strength + 0.25))
	_beam.draw_circle(o, 1.5, Color(1, 0.97, 0.85, 0.9))
