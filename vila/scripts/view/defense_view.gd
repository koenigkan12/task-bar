class_name VilaDefenseView
extends Node2D
## Desenho da defesa (só desenho; a regra está em VilaDefense): zumbis andando, muros ligados entre
## si pelo nível, tiros e explosões, barra de vida de quem apanha e o alerta de prédio avariado.
## Tiros, olhos dos zumbis e barras vão numa camada que o escuro da noite não apaga.

const TILE := 16
const D := Color8(67, 52, 85)
const CR := Color8(204, 198, 186)
const MC := Color8(193, 141, 117)
const ME := Color8(141, 98, 105)
const LI := Color8(102, 95, 146)
const LC := Color8(165, 146, 165)
const VM := Color8(201, 101, 91)
const Y := Color8(200, 171, 93)
const AC := Color8(124, 165, 197)

var sim: VilaSim
var _objects: Node2D
var _icons: Texture2D
var _ztex: Texture2D
var _btex: Texture2D
var _light: Texture2D
var _znodes: Dictionary = {}          # id do zumbi -> {root, sprite, light, age}
var _walls: Node2D                    # no chão, por baixo das pessoas
var _wall_key := ""
var _bright: Node2D
var _t := 0.0
var _night_k := 0.0
var _last_hit: Dictionary = {}   # id do prédio/muro -> quando levou o último golpe (a barra some 3 s depois)
var _falls: Array[Dictionary] = []   # {pos, t0, ruin}: prédio desabando agora (nuvem de poeira)
var _dust: Array[Dictionary] = []    # {pos, t0}: zumbi que caiu virando poeira


func setup(s: VilaSim, objects: Node2D, floor_node: Node2D, icons: Texture2D, ztex: Texture2D, btex: Texture2D, light: Texture2D) -> void:
	sim = s
	_objects = objects
	_icons = icons
	_ztex = ztex
	_btex = btex
	_light = light
	_walls = Node2D.new()
	_walls.draw.connect(_draw_walls)
	floor_node.add_child(_walls)
	var gl := CanvasLayer.new()
	gl.layer = 1
	gl.follow_viewport_enabled = true
	add_child(gl)
	_bright = Node2D.new()
	_bright.draw.connect(_draw_bright)
	gl.add_child(_bright)
	sim.building_fell.connect(_on_fell)


func _on_fell(id: int, ruin: bool) -> void:
	var b := sim.by_id(id)
	if b.is_empty():
		return
	var fp := sim._fp(String(b["type"]))
	var base := Vector2((Vector2i(b["cell"]).x + fp.x / 2.0) * TILE, (Vector2i(b["cell"]).y + fp.y) * TILE - 4)
	_falls.append({"pos": base, "t0": _t, "w": float(fp.x * TILE), "ruin": ruin})
	AudioManager.play_sfx("scrap", 2.0)


func update_defense(delta: float, night_k: float, anim_t: float) -> void:
	_t = anim_t
	_night_k = night_k
	for e in sim.defense.fx:
		if String(e["kind"]) == "hit":
			var hid := int(e.get("id", -1))
			var when := _t - float(e["t"])
			if when > float(_last_hit.get(hid, -99.0)) + 0.05:
				AudioManager.play_sfx("knock", -10.0)   # golpe seco a cada pancada
			_last_hit[hid] = maxf(float(_last_hit.get(hid, -99.0)), when)
	_fx_sounds()
	_falls = _falls.filter(func(f: Dictionary) -> bool: return _t - float(f["t0"]) < 1.6)
	_dust = _dust.filter(func(f: Dictionary) -> bool: return _t - float(f["t0"]) < 0.8)
	_sync_zombies(delta)
	var key := _wall_signature()
	if key != _wall_key:
		_wall_key = key
		_walls.queue_redraw()
	_bright.queue_redraw()


## Som de cada tiro, queda e mordida, uma vez por efeito (marca "snd" no próprio fx). O volume
## fica baixo e o AudioManager espaça repetições (vários tiros por segundo no ataque).
const FX_SFX := {"arrow": "shot_arrow", "ball": "shot_cannon", "zap": "shot_zap", "zdie": "zdie",
	"bite": "bite", "breach": "wall_fall"}


func _fx_sounds() -> void:
	var gun_at: Array = []
	for e in sim.defense.fx:
		if bool(e.get("snd", false)) or float(e["t"]) < 0.0:
			continue
		e["snd"] = true
		var k := String(e["kind"])
		if k == "muzzle" and bool(e.get("gun", false)):
			gun_at.append(e["a"])
			AudioManager.play_sfx("shot_gun")
		elif k == "arrow" and gun_at.has(e["a"]):
			continue   # a "flecha" da escotilha é o chumbo da espingarda: já tocou o tiro dela
		elif FX_SFX.has(k):
			AudioManager.play_sfx(String(FX_SFX[k]))


# ================================================================ zumbis
static func zworld(pos: Vector2) -> Vector2:
	return pos * TILE + Vector2(8, 13)


func _sync_zombies(delta: float) -> void:
	var seen := {}
	var all: Array[Dictionary] = []
	all.append_array(sim.defense.zombies)
	all.append_array(sim.defense.leaving)
	for z in all:
		var id: int = int(z["id"])
		seen[id] = true
		var n: Dictionary = _znodes.get(id, {})
		if n.is_empty():
			n = _make_zombie(z)
			_znodes[id] = n
		n["age"] = float(n["age"]) + delta
		var root: Node2D = n["root"]
		root.position = zworld(z["pos"]).round()
		var spr: Sprite2D = n["sprite"]
		spr.flip_h = float(z["facing"]) < 0.0
		var atk := int(z.get("atk", -1)) >= 0
		spr.frame = (int((_t + id * 0.31) * (3.0 if atk else 5.0)) % 4) if (atk or not (z["path"] as PackedVector2Array).is_empty()) else 0
		# Tomou tiro: pisca branco por um instante e recua 1 px.
		var zh := float(z.get("hp", 0.0))
		if z.has("hp") and zh < float(n.get("hp", zh)):
			n["flash"] = 0.07
		n["hp"] = zh
		n["flash"] = maxf(0.0, float(n.get("flash", 0.0)) - delta)
		var fl_on := float(n["flash"]) > 0.0
		spr.self_modulate = Color(5, 5, 5) if fl_on else Color.WHITE
		spr.position.x = -float(z["facing"]) if fl_on else 0.0
		var sink := float(z.get("sink", 0.0))
		if sink > 0.0:
			# Amanheceu e chegou na beira: afunda na água (desce e some).
			spr.position.y = roundf(sink * 7.0)
			root.modulate.a = clampf(1.0 - sink / 1.2, 0.0, 1.0)
		else:
			spr.position.y = 0.0
			# Saindo da água: sobe aos poucos.
			root.modulate.a = clampf(float(n["age"]) / 0.8, 0.0, 1.0)
		var l: PointLight2D = n["light"]
		l.energy = 0.55 * _night_k
		l.visible = l.energy > 0.02
	for id in _znodes.keys():
		if seen.has(id):
			continue
		var gone: Node2D = _znodes[id]["root"]
		_znodes.erase(id)
		var died := _died_at(gone.position)
		var tw := gone.create_tween()
		if died:
			# Tomba, fica um segundo no chão e vira poeira.
			tw.tween_property(gone, "rotation", PI / 2.0 * (1.0 if randf() < 0.5 else -1.0), 0.25).set_ease(Tween.EASE_IN)
			tw.tween_interval(1.0)
			tw.tween_callback(func() -> void: _dust.append({"pos": gone.position, "t0": _t}))
			tw.tween_property(gone, "modulate:a", 0.0, 0.3)
		tw.tween_callback(gone.queue_free)


func _died_at(px: Vector2) -> bool:
	for e in sim.defense.fx:
		if String(e["kind"]) == "zdie" and not bool(e.get("seen", false)) and zworld(e["a"]).distance_to(px) < 6.0:
			e["seen"] = true
			return true
	return false


func _make_zombie(z: Dictionary) -> Dictionary:
	var boss := String(z["kind"]) == "chefe"
	if boss:
		AudioManager.play_sfx("boss")   # chefe saiu da água
	var root := Node2D.new()
	_objects.add_child(root)
	var spr := Sprite2D.new()
	spr.texture = _btex if boss else _ztex
	spr.hframes = 4
	spr.offset = Vector2(0, -11 if boss else -7)
	if String(z["kind"]) == "horda":
		spr.modulate = Color(1.0, 0.86, 0.86)   # horda: um pouco mais avermelhado
	root.add_child(spr)
	var l := PointLight2D.new()
	l.texture = _light
	l.color = Color(0.7, 0.95, 0.6)
	l.texture_scale = 0.5 if not boss else 0.9
	l.position = Vector2(0, -6)
	l.energy = 0.0
	root.add_child(l)
	root.modulate.a = 0.0
	return {"root": root, "sprite": spr, "light": l, "age": 0.0}


# ================================================================ muros
func _wall_cells() -> Dictionary:
	var out := {}
	for b in sim.buildings:
		if String(b["type"]) == "muro" and int(b["id"]) != sim.lifted:
			out[Vector2i(b["cell"])] = b
	return out


func _wall_signature() -> String:
	var parts := PackedStringArray()
	for b in sim.buildings:
		if String(b["type"]) == "muro":
			var frac := sim.defense.hp(b) / maxf(1.0, sim.defense.max_hp(b))
			parts.append("%s%d%d%d" % [str(b["cell"]), int(b["level"]), int(frac * 4.0), 1 if int(b["id"]) == sim.lifted else 0])
	return ",".join(parts)


## Altura do muro (px) e as duas cores (frente, topo) por nível: arame, madeira, concreto, aço.
static func wall_look(level: int) -> Array:
	match level:
		1: return [6, ME, LC]
		2: return [9, ME, MC]
		3: return [8, LC, CR]
	return [10, LI, CR]


func _draw_walls() -> void:
	var cells := _wall_cells()
	for c in cells:
		var b: Dictionary = cells[c]
		var lv := int(b["level"])
		var look := wall_look(lv)
		var hgt: int = look[0]
		var front: Color = look[1]
		var top: Color = look[2]
		var frac := sim.defense.hp(b) / maxf(1.0, sim.defense.max_hp(b))
		var base := Vector2(c.x * TILE + 8, c.y * TILE + 12)   # pé do poste
		if frac <= 0.0:
			# Derrubado: rombo com entulho e um toco quebrado (dá para ver que ali está aberto).
			_walls.draw_rect(Rect2(base + Vector2(-7, -1), Vector2(14, 2)), Color(0.12, 0.09, 0.1, 0.55))
			for k in 4:
				var o := Vector2(-6 + k * 4, -2 - (k % 2))
				_walls.draw_rect(Rect2(base + o, Vector2(3, 2)), front.darkened(0.15))
			_walls.draw_rect(Rect2(base + Vector2(-1, -4), Vector2(2, 4)), front.darkened(0.3))
			_walls.draw_line(base + Vector2(-1, -4), base + Vector2(1, -5), top, 1.0)
			continue
		var right: bool = cells.has(c + Vector2i(1, 0))
		var down: bool = cells.has(c + Vector2i(0, 1))
		if right:
			_wall_span(base, base + Vector2(16, 0), lv, hgt, front, top)
		if down:
			_wall_vspan(base, lv, hgt, front, top)
		# Poste no meio da célula (arame: pau fino; resto: bloco).
		var pw := 2 if lv == 1 else 4
		_walls.draw_rect(Rect2(base + Vector2(-pw / 2.0, -hgt - 2), Vector2(pw, hgt + 2)), D if lv == 1 else front.darkened(0.15))
		_walls.draw_rect(Rect2(base + Vector2(-pw / 2.0, -hgt - 2), Vector2(pw, 1)), top)
		if frac < 0.75:
			# Rachado: risco escuro, mais quanto mais apanhou.
			_walls.draw_line(base + Vector2(-1, -hgt + 1), base + Vector2(1, -hgt * 0.4), D, 1.0)
			if frac < 0.4:
				_walls.draw_line(base + Vector2(3, -hgt + 2), base + Vector2(5, -2), D, 1.0)


func _wall_span(a: Vector2, z: Vector2, lv: int, hgt: int, front: Color, top: Color) -> void:
	if lv == 1:
		# Arame: dois fios com farpas.
		for yy in [-hgt + 1, -hgt / 2 + 1]:
			_walls.draw_line(a + Vector2(0, yy), z + Vector2(0, yy), top, 1.0)
			for x in range(3, 16, 5):
				_walls.draw_rect(Rect2(a + Vector2(x, yy - 1), Vector2(1, 1)), CR)
		return
	_walls.draw_rect(Rect2(a + Vector2(0, -hgt), Vector2(z.x - a.x, hgt)), front)
	_walls.draw_rect(Rect2(a + Vector2(0, -hgt), Vector2(z.x - a.x, 1)), top)
	_walls.draw_rect(Rect2(a + Vector2(0, -1), Vector2(z.x - a.x, 1)), D)
	match lv:
		2:
			for x in range(2, 16, 4):
				_walls.draw_rect(Rect2(a + Vector2(x, -hgt + 1), Vector2(1, hgt - 2)), front.darkened(0.2))
		3:
			_walls.draw_rect(Rect2(a + Vector2(0, -hgt / 2), Vector2(16, 1)), front.darkened(0.15))
			_walls.draw_rect(Rect2(a + Vector2(8, -hgt + 1), Vector2(1, hgt / 2 - 1)), front.darkened(0.15))
		4:
			for x in range(3, 16, 6):
				_walls.draw_rect(Rect2(a + Vector2(x, -hgt + 2), Vector2(1, 1)), CR)
				_walls.draw_rect(Rect2(a + Vector2(x, -3), Vector2(1, 1)), CR)


func _wall_vspan(a: Vector2, lv: int, hgt: int, front: Color, top: Color) -> void:
	# Indo para baixo (para perto da câmera): faixa estreita vista de cima.
	if lv == 1:
		_walls.draw_line(a + Vector2(0, -hgt + 1), a + Vector2(0, 16 - hgt + 1), top, 1.0)
		_walls.draw_line(a + Vector2(1, -hgt / 2 + 1), a + Vector2(1, 16 - hgt / 2 + 1), top, 1.0)
		# Farpas e um poste no meio do vão: a cerca de lado precisa parecer cerca, não um tracejado.
		for y in range(2, 16, 5):
			_walls.draw_rect(Rect2(a + Vector2(-1, -hgt + y), Vector2(3, 1)), CR)
		_walls.draw_rect(Rect2(a + Vector2(-1, 8 - hgt - 2), Vector2(2, hgt + 2)), D)
		return
	_walls.draw_rect(Rect2(a + Vector2(-2, -hgt), Vector2(4, 16)), top)
	_walls.draw_rect(Rect2(a + Vector2(-2, 16 - hgt), Vector2(4, hgt)), front)
	_walls.draw_rect(Rect2(a + Vector2(2, -hgt), Vector2(1, 16 + hgt)), front.darkened(0.25))


# ================================================================ camada clara (tiros, barras)
func _draw_bright() -> void:
	var df := sim.defense
	for e in df.fx:
		var t := float(e["t"])
		if t < 0.0:
			continue
		var k := t / maxf(0.01, float(e["life"]))
		var a := zworld(e["a"]) + Vector2(0, -6)
		var b := zworld(e["b"]) + Vector2(0, -6)
		match String(e["kind"]):
			"arrow":
				var p := a.lerp(b, k)
				var dir := (b - a).normalized()
				_bright.draw_line(p - dir * 4.0, p, CR, 1.0)
				_bright.draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1, 1)), Y)
			"ball":
				var p2 := a.lerp(b, k) + Vector2(0, -sin(k * PI) * 14.0)
				_bright.draw_circle(p2, 2.0, D)
				_bright.draw_circle(p2 + Vector2(-0.5, -0.5), 0.8, LC)
			"boom":
				var r := float(e.get("r", 1.0)) * TILE * (0.4 + 0.6 * k)
				_bright.draw_circle(b + Vector2(0, 4), r, Color(1.0, 0.75, 0.35, 0.45 * (1.0 - k)))
				_bright.draw_arc(b + Vector2(0, 4), r, 0.0, TAU, 20, Color(1.0, 0.9, 0.6, 0.8 * (1.0 - k)), 1.0)
			"hit":
				# pancada do zumbi: estrela laranja que abre e some
				var rr := 2.0 + 3.0 * k
				var hc := Color(1.0, 0.6, 0.3, 1.0 - k)
				for i in 4:
					var ang := PI / 4.0 + i * PI / 2.0
					_bright.draw_line(b + Vector2(cos(ang), sin(ang)) * rr * 0.4, b + Vector2(cos(ang), sin(ang)) * rr, hc, 1.0)
				_bright.draw_rect(Rect2(b.round() - Vector2(0.5, 0.5), Vector2(1, 1)), Color(1, 0.95, 0.8, 1.0 - k))
			"breach":
				# Muro caiu: poeira que abre e lascas voando (dá para ver onde a cerca rompeu).
				var c0 := zworld(e["a"]) + Vector2(0, -2)
				for i in 6:
					var ang2 := -PI + i * PI / 5.0
					var q2 := c0 + Vector2(cos(ang2), sin(ang2) * 0.6) * (3.0 + 9.0 * k) + Vector2(0, -sin(k * PI) * 5.0)
					_bright.draw_circle(q2, 2.5 + 2.0 * k, Color(0.62, 0.55, 0.5, 0.7 * (1.0 - k)))
				for i in 3:
					var q3 := c0 + Vector2((i - 1) * 5.0 * (0.5 + k), -12.0 * sin(k * PI) - 2.0)
					_bright.draw_rect(Rect2(q3.round(), Vector2(2, 1)), Color(0.85, 0.7, 0.5, 1.0 - k))
			"muzzle":
				# Clarão na boca da arma; a espingarda solta um leque de chumbo curto.
				var ma := a + Vector2(0, -2)
				var dirm := (b - a).normalized()
				_bright.draw_circle(ma, 3.0 if bool(e.get("gun", false)) else 2.0, Color(1.0, 0.92, 0.6, 1.0 - k))
				_bright.draw_circle(ma, 1.2, Color(1, 1, 1, 1.0 - k))
				if bool(e.get("gun", false)):
					for i in 3:
						var dv := dirm.rotated((i - 1) * 0.25)
						_bright.draw_line(ma + dv * 4.0, ma + dv * (7.0 + 6.0 * k), Color(1.0, 0.85, 0.5, 1.0 - k), 1.0)
			"splash":
				# Zumbi afundou na água: dois anéis abrindo.
				var sc := zworld(e["a"]) + Vector2(0, -1)
				for i in 2:
					var rk := 2.0 + (6.0 + 3.0 * i) * k
					_bright.draw_arc(sc, rk, 0.0, TAU, 14, Color(0.85, 0.93, 1.0, 0.8 * (1.0 - k)), 1.0)
			"zap":
				var pts := PackedVector2Array()
				for i in 6:
					var q := a.lerp(b, i / 5.0)
					if i > 0 and i < 5:
						q += Vector2(randf_range(-2, 2), randf_range(-2, 2))
					pts.append(q)
				_bright.draw_polyline(pts, Color(0.75, 0.95, 1.0, 1.0 - k), 1.0)
	# Prédio desabando: nuvem de poeira que abre pelos lados e sobe, com lascas voando.
	for f in _falls:
		var fk := (_t - float(f["t0"])) / 1.6
		var fw := float(f["w"])
		var fb: Vector2 = f["pos"]
		for i in 8:
			var side := -1.0 if i % 2 == 0 else 1.0
			var q := fb + Vector2(side * (fw * 0.15 + fw * 0.45 * fk) * (0.5 + (i % 4) * 0.2), -2.0 - fk * (6.0 + i * 1.5))
			_bright.draw_circle(q, 3.0 + 4.0 * fk, Color(0.66, 0.6, 0.55, 0.75 * (1.0 - fk)))
		for i in 5:
			var q2 := fb + Vector2((i - 2) * fw * 0.18 * (0.4 + fk), -18.0 * sin(minf(1.0, fk * 2.0) * PI) - 4.0)
			_bright.draw_rect(Rect2(q2.round(), Vector2(2, 2)), Color(0.5, 0.4, 0.38, 1.0 - fk))
	for f in _dust:
		var dk := (_t - float(f["t0"])) / 0.8
		for i in 4:
			var dq: Vector2 = f["pos"] + Vector2((i - 1.5) * 3.0 * (0.5 + dk), -2.0 - dk * 6.0)
			_bright.draw_circle(dq, 1.5 + 2.0 * dk, Color(0.6, 0.56, 0.5, 0.7 * (1.0 - dk)))
	# Olhos dos zumbis (de noite eles se veem pelo brilho) e vida de quem já apanhou.
	for z in df.zombies:
		var n: Dictionary = _znodes.get(int(z["id"]), {})
		if n.is_empty():
			continue
		var root: Node2D = n["root"]
		var boss := String(z["kind"]) == "chefe"
		var al := root.modulate.a
		if _night_k > 0.3:
			var fl := 1.0 if float(z["facing"]) >= 0.0 else -1.0
			var eye := root.position + Vector2((1.0 if not boss else 1.5) * fl, -11.0 if not boss else -17.0)
			_bright.draw_rect(Rect2(eye.round(), Vector2(1, 1)), Color(1.0, 0.4, 0.3, al * _night_k))
		if float(z["hp"]) < float(z["max"]):
			var w := 10.0 if not boss else 18.0
			var at := root.position + Vector2(-w / 2.0, -16.0 if not boss else -24.0)
			_bright.draw_rect(Rect2(at.round(), Vector2(w, 2)), Color(D, 0.85 * al))
			_bright.draw_rect(Rect2(at.round(), Vector2(w * float(z["hp"]) / float(z["max"]), 2)), Color(VM, al))
	# Prédios: barra de vida quando apanhou, alerta piscando quando avariou, tijolo quando virou ruína.
	for b in sim.buildings:
		var tp := String(b["type"])
		if tp == "muro":
			var wk := 0.0
			for e in df.fx:
				if String(e["kind"]) == "hit" and int(e.get("id", -1)) == int(b["id"]):
					wk = maxf(wk, 1.0 - float(e["t"]) / 0.25)
			if wk > 0.0:
				var wlook := wall_look(int(b["level"]))
				var hgt: int = wlook[0]
				var wb := Vector2(Vector2i(b["cell"]).x * TILE + 8, Vector2i(b["cell"]).y * TILE + 12)
				_bright.draw_rect(Rect2(wb + Vector2(-8, -hgt - 3), Vector2(16, hgt + 4)), Color(1.0, 0.25, 0.2, 0.75 * wk))
			var wh := df.hp(b)
			var wm := df.max_hp(b)
			if wh > 0.0 and wh < wm and _recent(int(b["id"])):
				var whit := _hit_now(int(b["id"]))
				var wsh := Vector2(roundf(sin(_t * 60.0)), 0) if whit else Vector2.ZERO
				var wat := (Vector2(Vector2i(b["cell"]).x * TILE + 2, Vector2i(b["cell"]).y * TILE - 4) + wsh).round()
				var wf := wh / wm
				_bright.draw_rect(Rect2(wat - Vector2(1, 1), Vector2(14, 4)), Color(0.08, 0.05, 0.1, 0.9))
				_bright.draw_rect(Rect2(wat, Vector2(12.0 * wf, 2)), VM if wf < 0.35 else (Y if wf < 0.7 else Color8(169, 196, 124)))
				_tiny_num(wat + Vector2(15, -2), "%d/%d" % [int(ceilf(wh)), int(wm)], CR)
			if wh <= 0.0 and _icons != null:
				# Muro no chão: selo vermelho pequeno com o martelo (âmbar em obra de conserto); clicar abre o conserto.
				var wfix := String(b["state"]) != "built"
				var wc := Vector2(Vector2i(b["cell"]).x * TILE + 8, Vector2i(b["cell"]).y * TILE - 2 - (0.0 if wfix else roundf(sin(_t * 3.0) * 0.6 + 0.4))).round()
				_bright.draw_circle(wc, 6.0, Color(0.08, 0.04, 0.06, 0.95))
				_bright.draw_circle(wc, 5.0, Color8(232, 168, 72) if wfix else Color8(214, 58, 52))
				_bright.draw_texture_rect_region(_icons, Rect2(wc - Vector2(4, 4), Vector2(8, 8)), Rect2(8 * 8, 0, 8, 8), Color(1, 1, 1))
			continue
		if not b.has("hp") and not bool(b.get("broken", false)):
			continue
		var fp := sim._fp(tp)
		var mid := Vector2((Vector2i(b["cell"]).x + fp.x / 2.0) * TILE, Vector2i(b["cell"]).y * TILE - 6)
		if bool(b.get("ruin", false)) or bool(b.get("broken", false)):
			var ruin := bool(b.get("ruin", false))
			var base := Vector2((Vector2i(b["cell"]).x + fp.x / 2.0) * TILE, (Vector2i(b["cell"]).y + fp.y) * TILE - 6)
			# Fumaça saindo do prédio quebrado (três baforadas subindo e sumindo).
			for i in 3:
				var ph := fposmod(_t * 0.5 + i / 3.0 + float(b["id"]) * 0.17, 1.0)
				var sp := base + Vector2(sin(ph * 5.0 + i) * 3.0 + (i - 1) * 4.0, -ph * 18.0 - (4.0 if ruin else 10.0))
				_bright.draw_circle(sp, 2.0 + ph * 2.5, Color(0.55, 0.5, 0.55, 0.45 * (1.0 - ph)))
			# Selo grande e vermelho (não pisca, só respira): martelo riscado = quebrado, conserte;
			# tijolo riscado = ruína, reconstrua. Em obra de conserto fica âmbar, sem o X.
			if _icons != null:
				var fixing := String(b["state"]) != "built"
				var col := Color8(232, 168, 72) if fixing else Color8(214, 58, 52)
				var pulse := 0.0 if fixing else roundf(sin(_t * 3.0) * 0.6 + 0.4)
				var c := (Vector2(mid.x, base.y - 24.0 - pulse)).round()   # logo acima do telhado
				_bright.draw_circle(c, 8.0, Color(0.08, 0.04, 0.06, 0.95))
				_bright.draw_circle(c, 7.0, col)
				_bright.draw_texture_rect_region(_icons, Rect2(c - Vector2(4, 4), Vector2(8, 8)), Rect2((25 if ruin else 8) * 8, 0, 8, 8), Color(1, 1, 1))
				if not fixing:
					# X branco no canto: "quebrado".
					var xc := c + Vector2(5, -5)
					_bright.draw_circle(xc, 3.5, Color(0.08, 0.04, 0.06, 0.95))
					_bright.draw_line(xc + Vector2(-2, -2), xc + Vector2(2, 2), Color.WHITE, 1.0)
					_bright.draw_line(xc + Vector2(-2, 2), xc + Vector2(2, -2), Color.WHITE, 1.0)
			continue
		var mh := df.max_hp(b)
		var h := df.hp(b)
		if h < mh and _recent(int(b["id"])):
			# Vida do prédio: escudo + barra (verde, amarela, vermelha). Treme quando apanha.
			var w2 := float(fp.x * TILE) * 0.6
			var hit := _hit_now(int(b["id"]))
			var shake := Vector2(roundf(sin(_t * 60.0)), 0) if hit else Vector2.ZERO
			var at2 := (mid - Vector2(w2 / 2.0 - 4.0, 0) + shake).round()
			var fr2 := h / mh
			_bright.draw_rect(Rect2(at2 - Vector2(1, 1), Vector2(w2 + 2, 5)), Color(0.08, 0.05, 0.1, 0.9))
			_bright.draw_rect(Rect2(at2, Vector2(w2, 3)), Color(D, 0.95))
			# Perto do fim a barra pisca (vai cair).
			var blink := fr2 < 0.25 and int(_t * 8.0) % 2 == 0
			_bright.draw_rect(Rect2(at2, Vector2(w2 * fr2, 3)), Color(1, 0.9, 0.85) if blink else (VM if fr2 < 0.35 else (Y if fr2 < 0.7 else Color8(169, 196, 124))))
			_tiny_num(at2 + Vector2(w2 + 3, -1), "%d/%d" % [int(ceilf(h)), int(mh)], CR)
			if hit:
				_bright.draw_rect(Rect2(at2 - Vector2(1, 1), Vector2(w2 + 2, 5)), Color(1.0, 0.5, 0.35, 0.9), false, 1.0)
			if _icons != null:
				_bright.draw_texture_rect_region(_icons, Rect2(at2 + Vector2(-10, -3), Vector2(8, 8)), Rect2(26 * 8, 0, 8, 8))



## Levou golpe nos últimos 3 s? (a barra de vida aparece no golpe e some depois, como no Clash)
func _recent(id: int) -> bool:
	return _t - float(_last_hit.get(id, -99.0)) < 3.0


## "84/120" com os algarismos de 3x5 px da vila, num fundo escuro (legível em cima do mapa).
func _tiny_num(at: Vector2, txt: String, col: Color) -> void:
	var w := 0.0
	for ch in txt:
		w += float(String(WorldView.TINY.get(ch, ["000"])[0]).length() + 1)
	at = at.round()
	_bright.draw_rect(Rect2(at - Vector2(1, 1), Vector2(w + 1, 7)), Color(0.05, 0.04, 0.06, 0.85))
	var x := at.x
	for ch in txt:
		var rows: Array = WorldView.TINY.get(ch, [])
		for y in rows.size():
			var r := String(rows[y])
			for i in r.length():
				if r[i] == "1":
					_bright.draw_rect(Rect2(Vector2(x + i, at.y + y), Vector2.ONE), col)
		x += float(String(rows[0]).length() + 1) if not rows.is_empty() else 4.0


## O prédio levou pancada agora há pouco?
func _hit_now(id: int) -> bool:
	for e in sim.defense.fx:
		if String(e["kind"]) == "hit" and int(e.get("id", -1)) == id:
			return true
	return false
