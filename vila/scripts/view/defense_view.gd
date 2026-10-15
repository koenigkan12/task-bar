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


func update_defense(delta: float, night_k: float, anim_t: float) -> void:
	_t = anim_t
	_night_k = night_k
	_sync_zombies(delta)
	var key := _wall_signature()
	if key != _wall_key:
		_wall_key = key
		_walls.queue_redraw()
	_bright.queue_redraw()


# ================================================================ zumbis
static func zworld(pos: Vector2) -> Vector2:
	return pos * TILE + Vector2(8, 13)


func _sync_zombies(delta: float) -> void:
	var seen := {}
	for z in sim.defense.zombies:
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
			# Tomba e some no chão.
			tw.tween_property(gone, "rotation", PI / 2.0 * (1.0 if randf() < 0.5 else -1.0), 0.3).set_ease(Tween.EASE_IN)
			tw.tween_interval(0.5)
			tw.tween_property(gone, "modulate:a", 0.0, 0.6)
		else:
			# Amanheceu: volta para a água.
			tw.tween_property(gone, "modulate:a", 0.0, 1.0)
		tw.tween_callback(gone.queue_free)


func _died_at(px: Vector2) -> bool:
	for e in sim.defense.fx:
		if String(e["kind"]) == "zdie" and not bool(e.get("seen", false)) and zworld(e["a"]).distance_to(px) < 6.0:
			e["seen"] = true
			return true
	return false


func _make_zombie(z: Dictionary) -> Dictionary:
	var boss := String(z["kind"]) == "chefe"
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
			# Derrubado: só entulho baixo no chão.
			for k in 3:
				var o := Vector2(-5 + k * 4, -1 - (k % 2))
				_walls.draw_rect(Rect2(base + o, Vector2(3, 2)), front.darkened(0.25))
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
			"zap":
				var pts := PackedVector2Array()
				for i in 6:
					var q := a.lerp(b, i / 5.0)
					if i > 0 and i < 5:
						q += Vector2(randf_range(-2, 2), randf_range(-2, 2))
					pts.append(q)
				_bright.draw_polyline(pts, Color(0.75, 0.95, 1.0, 1.0 - k), 1.0)
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
		if tp == "muro" or not b.has("hp") and not bool(b.get("broken", false)):
			continue
		var fp := sim._fp(tp)
		var mid := Vector2((Vector2i(b["cell"]).x + fp.x / 2.0) * TILE, Vector2i(b["cell"]).y * TILE - 6)
		if bool(b.get("ruin", false)) or bool(b.get("broken", false)):
			if int(_t * 2.0) % 2 == 0 and _icons != null:
				var fr := 25 if bool(b.get("ruin", false)) else 24   # ruína / avariado (icons.png)
				_bright.draw_texture_rect_region(_icons, Rect2((mid - Vector2(4, 8)).round(), Vector2(8, 8)), Rect2(fr * 8, 0, 8, 8))
			continue
		var mh := df.max_hp(b)
		var h := df.hp(b)
		if h < mh:
			var w2 := float(fp.x * TILE) * 0.6
			var at2 := mid - Vector2(w2 / 2.0, 0)
			_bright.draw_rect(Rect2(at2.round(), Vector2(w2, 2)), Color(D, 0.85))
			_bright.draw_rect(Rect2(at2.round(), Vector2(w2 * h / mh, 2)), VM if h / mh < 0.4 else Y)
