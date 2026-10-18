class_name VilaBoat
extends Node2D
## Um barco que se comporta como barco (bote de gente e barco do mascate):
## - só anda de proa; a única ré é a curta para desencostar do píer (um comprimento);
## - vira fazendo curva, com a proa na tangente do caminho;
## - desenho próprio para cada uma das 8 direções (tools/barcos_8dir.py), nada de girar sprite;
## - chega desacelerando e sai acelerando;
## - atraca paralelo à frente do píer, do lado da água;
## - remo no ritmo do que anda (parado quando atracado), barqueiro na popa de costas para a proa;
## - esteira saindo da popa quando anda e ondinhas em volta quando parado.
## Só desenho: quem decide quando chega e quando vai é a WorldView (a partir da simulação).

signal gone   # terminou de sair (já longe, fora da cena)

const K := 0.72                     # o mesmo encolhimento do eixo y usado para gerar os desenhos
const IN_S := 6.5                   # duração da chegada (entra desacelerando)
const BACK_S := 1.8                 # ré curta para desencostar
const OUT_S := 6.5                  # da curva até sumir (sai acelerando)
const WATER_HI := Color(0.86, 0.93, 1.0)

var kind := "bote"                  # bote | mascate
var length := 26.0                  # comprimento do casco (px)
var beam := 10.0
var zg := 3.0                       # altura da borda
var state := ""                     # "", in, here, back, out
var passengers := 0                 # cabeças no bote (só o de gente)
var rower := true

var dock := Vector2.ZERO            # meio do casco quando atracado (na linha d'água)
var pos := Vector2.ZERO             # meio do casco agora
var heading := 0.0                  # para onde a proa aponta (rad, tela, y para baixo)
var speed := 0.0                    # px/s (negativo = ré)
var _t := 0.0
var _anim := 0.0
var _stroke := 0.0                  # fase da remada, anda com a distância percorrida
var _path := PackedVector2Array()
var _cum := PackedFloat32Array()
var _back_from := Vector2.ZERO
var _back_to := Vector2.ZERO
var _spr: Sprite2D
var _top: Node2D                    # tripulação, desenhada por cima do casco
var _wake: Node2D                   # esteira e ondinhas, no nível da água (embaixo de tudo em terra)
var _anchor := Vector2.ZERO         # onde fica o meio do casco dentro do quadro


func setup(k: String, tex: Texture2D) -> void:
	kind = k
	if kind == "mascate":
		length = 46.0
		beam = 18.0
		zg = 5.0
		rower = false
		_anchor = Vector2(32, 56)
	else:
		_anchor = Vector2(18, 15)
	_wake = Node2D.new()
	_wake.z_as_relative = false
	_wake.z_index = -5
	_wake.draw.connect(_draw_wake)
	add_child(_wake)
	_spr = Sprite2D.new()
	_spr.texture = tex
	_spr.hframes = 8
	_spr.centered = false
	_spr.offset = -_anchor
	add_child(_spr)
	_top = Node2D.new()
	_top.draw.connect(_draw_top)
	add_child(_top)
	visible = false


## Direção desenhada (0 = leste, 2 = sul, 4 = oeste, 6 = norte).
func dir_index() -> int:
	return posmod(roundi(heading / (PI / 4.0)), 8)


# ---------------------------------------------------------------- rotas
## Chegada: vem de longe pelo mar (sudoeste), faz uma curva suave e encosta de proa para o leste,
## rente à frente do píer.
func sail_in(at: Vector2) -> void:
	dock = at
	var p0 := dock + Vector2(-300, 96)
	var p1 := p0 + Vector2(150, 0)
	var p2 := dock + Vector2(-110, 0)
	_set_path(_bezier(p0, p1, p2, dock, 48))
	state = "in"
	_t = 0.0
	pos = p0
	heading = 0.0
	visible = true


## Já atracado (o jogo abriu com ele lá).
func moor(at: Vector2) -> void:
	dock = at
	pos = dock
	heading = 0.0
	speed = 0.0
	state = "here"
	visible = true


## Saída: ré de um comprimento para desencostar, curva para o lado do mar e segue de proa.
func sail_out() -> void:
	if state == "" or state == "back" or state == "out":
		return
	if state == "in":   # desistiu no caminho: dá meia-volta dali mesmo (curva, nunca ré)
		_start_out(pos, heading)
		return
	_back_from = pos
	_back_to = pos - Vector2(cos(heading), sin(heading)) * (length + 4.0)
	state = "back"
	_t = 0.0


func _start_out(from: Vector2, h: float) -> void:
	var r := maxf(length * 1.4, 34.0)
	var f := Vector2(cos(h), sin(h))
	var right := Vector2(-f.y, f.x)   # vira para o lado de fora (o mar fica ao sul do píer)
	var c := from + right * r
	var pts := PackedVector2Array()
	var a0 := (from - c).angle()
	for i in 25:
		pts.append(c + Vector2.from_angle(a0 + PI * float(i) / 24.0) * r)
	var end_dir := -f
	pts.append(pts[pts.size() - 1] + end_dir * 320.0)
	_set_path(pts)
	state = "out"
	_t = 0.0


func _bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var u := 1.0 - t
		out.append(a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t)
	return out


func _set_path(pts: PackedVector2Array) -> void:
	_path = pts
	_cum = PackedFloat32Array()
	var s := 0.0
	_cum.append(0.0)
	for i in range(1, pts.size()):
		s += pts[i].distance_to(pts[i - 1])
		_cum.append(s)


func _total() -> float:
	return _cum[_cum.size() - 1] if not _cum.is_empty() else 0.0


func _at(s: float) -> Vector2:
	s = clampf(s, 0.0, _total())
	for i in range(1, _cum.size()):
		if _cum[i] >= s:
			var seg := _cum[i] - _cum[i - 1]
			var k := 0.0 if seg <= 0.0 else (s - _cum[i - 1]) / seg
			return _path[i - 1].lerp(_path[i], k)
	return _path[_path.size() - 1]


func _tangent(s: float) -> float:
	var a := _at(s - 3.0)
	var b := _at(s + 3.0)
	return (b - a).angle() if a.distance_squared_to(b) > 0.01 else heading


# ---------------------------------------------------------------- movimento
func step(delta: float) -> void:
	_anim += delta
	if state == "":
		return
	_t += delta
	var before := pos
	match state:
		"in":
			var k := clampf(_t / IN_S, 0.0, 1.0)
			var e := 1.0 - (1.0 - k) * (1.0 - k)   # chega desacelerando
			var s := _total() * e
			pos = _at(s)
			heading = _tangent(minf(s, _total() - 3.0))
			if k >= 1.0:
				pos = dock
				heading = 0.0
				state = "here"
		"here":
			pos = dock
		"back":
			var k := clampf(_t / BACK_S, 0.0, 1.0)
			pos = _back_from.lerp(_back_to, k * k * (3.0 - 2.0 * k))   # ré devagar, só o comprimento
			if k >= 1.0:
				_start_out(pos, heading)
		"out":
			var k := clampf(_t / OUT_S, 0.0, 1.0)
			var s := _total() * k * k   # sai acelerando
			pos = _at(s)
			heading = _tangent(maxf(s, 3.0))
			if k >= 1.0:
				state = ""
				visible = false
				gone.emit()
				return
	var mv := pos - before
	var fwd := mv.dot(Vector2(cos(heading), sin(heading)))
	speed = lerpf(speed, fwd / maxf(delta, 1e-3), 0.3)
	_stroke += absf(fwd) / (5.0 if kind == "bote" else 9.0)
	_place()


func _place() -> void:
	var bob := roundf(sin(_anim * 1.6)) if absf(speed) < 4.0 else 0.0
	position = pos.round()
	_spr.frame = dir_index()
	_spr.position = Vector2(0, bob)
	_top.position = Vector2(0, bob)
	_wake.queue_redraw()
	_top.queue_redraw()


## Retângulo de clique (em coordenadas do mundo), cobrindo o casco e as cabeças.
func rect() -> Rect2:
	if state == "":
		return Rect2()
	var h := 26.0 if kind == "bote" else 60.0
	var w := length + 10.0
	return Rect2(pos + Vector2(-w / 2.0, -h + 6.0), Vector2(w, h + 4.0))


## Ponto de um lugar do barco (u para a proa, v para estibordo, z para cima) na tela, relativo ao meio.
func _p(u: float, v: float, z: float) -> Vector2:
	var a := float(dir_index()) * PI / 4.0
	var f := Vector2(cos(a), sin(a))
	var r := Vector2(-f.y, f.x)
	var w := f * u + r * v
	return Vector2(w.x, w.y * K - z)


# ---------------------------------------------------------------- desenho
## Embaixo do casco: esteira (andando) ou ondinhas (parado).
func _draw_wake() -> void:
	if state == "":
		return
	var a := heading
	var f := Vector2(cos(a), sin(a))
	var r := Vector2(-f.y, f.x)
	var sq := func(w: Vector2) -> Vector2: return Vector2(w.x, w.y * K)
	var v := absf(speed)
	if v > 3.0:
		# Duas linhas claras abrindo para trás da popa, mais compridas quanto mais rápido.
		var stern := -f * (length / 2.0 - 1.0)
		var ln := clampf(v * 0.9, 8.0, 34.0) * (1.0 if speed > 0.0 else 0.4)
		for sg in [-1.0, 1.0]:
			var p0: Vector2 = sq.call(stern + r * sg * (beam * 0.3))
			for i in 5:
				var k0 := float(i) / 5.0
				var k1 := (float(i) + 0.6) / 5.0
				var pa: Vector2 = p0 + sq.call(-f * ln * k0 + r * sg * ln * 0.35 * k0)
				var pb: Vector2 = p0 + sq.call(-f * ln * k1 + r * sg * ln * 0.35 * k1)
				_wake.draw_line(pa.round(), pb.round(), Color(WATER_HI, 0.75 * (1.0 - k0)), 1.0)
		if speed < 0.0:   # ré: a água sai pela proa
			var bow: Vector2 = sq.call(f * (length / 2.0))
			_wake.draw_line((bow + Vector2(-2, 1)).round(), (bow + Vector2(2, 1)).round(), Color(WATER_HI, 0.6), 1.0)
	else:
		# Parado: dois risquinhos de onda que vão e voltam dos lados do casco.
		var ph := sin(_anim * 2.0)
		for sg in [-1.0, 1.0]:
			var side: Vector2 = sq.call(r * sg * (beam / 2.0 + 2.0 + ph))
			var c := side + Vector2(0, 2)
			_wake.draw_line((c - Vector2(3, 0)).round(), (c + Vector2(2, 0)).round(), Color(WATER_HI, 0.45), 1.0)
		var tip: Vector2 = sq.call(f * (length / 2.0 + 2.0 + ph)) + Vector2(0, 2)
		_wake.draw_line((tip - Vector2(1, 0)).round(), (tip + Vector2(1, 0)).round(), Color(WATER_HI, 0.4), 1.0)


## Em cima do casco: remos, barqueiro de costas para a proa e quem veio no barco.
func _draw_top() -> void:
	if state == "" or kind != "bote":
		return
	var skin := Color8(226, 186, 150)
	var shirt := Color8(92, 74, 96)
	var hat := Color8(150, 112, 70)
	var oar := Color8(150, 112, 70)
	var moving := absf(speed) > 3.0
	var seat_u := -length / 2.0 + 7.0      # o barqueiro senta no banco de trás
	var lock_u := seat_u + 3.0             # toletes logo à frente dele
	var ph := _stroke if moving else 0.0
	# Remada: a pá vai para trás pela água (puxando) e volta por cima, para a proa.
	var sweep := sin(ph)
	var lift := 1.0 if cos(ph) > 0.0 else 0.0
	var rowing := moving and speed > 0.0
	for sg in [-1.0, 1.0]:
		var lock := _p(lock_u, sg * (beam / 2.0 - 0.5), zg)
		var tip_u := lock_u + (sweep * 4.0 if moving else -2.0) * (1.0 if rowing else -1.0)
		var tip := _p(tip_u, sg * (beam / 2.0 + 4.5), (1.0 + lift * 2.0) if moving else 1.0)
		_top.draw_line(lock.round(), tip.round(), oar, 1.0)
		_top.draw_rect(Rect2(tip.round() - Vector2(1, 0), Vector2(2, 1)), oar)
	# Barqueiro: corpo e cabeça; o cabelo/chapéu fica do lado da proa (ele olha para a popa).
	var body := _p(seat_u, 0.0, zg + 1.0).round()
	_top.draw_rect(Rect2(body + Vector2(-2, -3), Vector2(4, 4)), shirt)
	var head := _p(seat_u, 0.0, zg + 5.0).round()
	_top.draw_rect(Rect2(head + Vector2(-1, -2), Vector2(3, 3)), skin)
	var back := _p(1.2, 0.0, 0.0)          # para que lado fica a nuca (a proa)
	var bx := signf(back.x) if absf(back.x) > 0.3 else 0.0
	var by := signf(back.y) if absf(back.y) > 0.3 else 0.0
	_top.draw_rect(Rect2(head + Vector2(-2, -3), Vector2(5, 1)), hat)
	if bx != 0.0:
		_top.draw_rect(Rect2(head + Vector2(-1 if bx < 0.0 else 1, -2) + Vector2(bx, 0), Vector2(1, 2)), hat)
	elif by < 0.0:
		_top.draw_rect(Rect2(head + Vector2(-1, -2), Vector2(3, 2)), hat)   # de costas para a câmera: só cabelo
	# Passageiros sentados no meio e na frente.
	var n := mini(3, passengers)
	for i in n:
		var u := 1.0 + float(i) * 4.5
		var v := (-1.5 if i % 2 == 0 else 1.5) if n > 1 else 0.0
		var hp := _p(u, v, zg + 4.0).round()
		_top.draw_rect(Rect2(hp + Vector2(-1, 1), Vector2(3, 2)), Color8(120, 140, 170))
		_top.draw_rect(Rect2(hp + Vector2(-1, -2), Vector2(3, 3)), skin)
