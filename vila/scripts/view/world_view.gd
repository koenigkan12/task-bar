class_name WorldView
extends Node2D
## Desenha a vila a partir da simulação: chão (TileMapLayer), árvores e entulho, prédios, pessoas,
## luz do dia/noite e o fantasma de posicionamento. Não decide nada: só lê `sim`.

const TILE := 16
const ART := "res://assets/art/"

var sim: VilaSim
var hover_cell: Vector2i = Vector2i(-1, -1)
var ghost_type: String = ""          # prédio sendo posicionado ("" = nenhum)
var ghost_cell: Vector2i = Vector2i(-1, -1)

var _ground: TileMapLayer
const ICON_FRAMES := 21                 # icons.png: 21 ícones de 8 px
var _objects: Node2D
var _floor: Node2D
var _fx: VilaFx
var _merchant_nodes: Array = []          # carroça e mascate na praça enquanto o mercador está lá
var _overlay: Node2D
var _zone: Node2D
var _zone_level: int = -1
var _modulate: CanvasModulate
var _terrain_cache: PackedByteArray = PackedByteArray()
var _terrain_nodes: Dictionary = {}     # célula -> Sprite2D (árvore, toco, entulho)
var _bnodes: Dictionary = {}            # id -> {root, sprite, overlay, bar, crops, lights, key}
var _pnodes: Dictionary = {}            # id -> {root, sprite, carry, zz}
var _tex: Dictionary = {}
var _lights: Array[Dictionary] = []     # {light, base, kind}
var _anim_t: float = 0.0
var hl_res: String = ""                  # recurso clicado na barra de cima: contorna quem produz
var _night_k: float = 0.0               # 0 = dia, 1 = noite fechada
var _sync_acc: float = 0.0


func setup(s: VilaSim) -> void:
	sim = s
	for c in get_children():
		remove_child(c)   # fora da árvore já: não desenha mais com o estado novo
		c.queue_free()
	_terrain_nodes.clear()
	_bnodes.clear()
	_pnodes.clear()
	_lights.clear()
	_ground = TileMapLayer.new()
	_ground.tile_set = _make_tileset()
	add_child(_ground)
	_zone = Node2D.new()
	_zone.draw.connect(_draw_zone)
	add_child(_zone)
	_zone_level = -1
	_floor = Node2D.new()      # prédios que são chão (a praça): por baixo das pessoas
	add_child(_floor)
	_objects = Node2D.new()
	_objects.y_sort_enabled = true
	add_child(_objects)
	_merchant_nodes = []
	_fx = VilaFx.new()
	add_child(_fx)
	_fx.setup(world_size())
	_overlay = Node2D.new()
	_overlay.z_index = 50
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_modulate = CanvasModulate.new()
	add_child(_modulate)
	_terrain_cache = PackedByteArray()
	_paint_ground()
	_sync_terrain(true)
	_sync_buildings()
	_sync_people(0.0)


func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := ART + name + ".png"
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


func world_size() -> Vector2:
	return Vector2(sim.w * TILE, sim.h * TILE)


func cell_at(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / TILE), floori(world.y / TILE))


func person_at(world: Vector2) -> int:
	var best := -1
	var bd := 9.0 * 9.0
	for p in sim.people:
		if p["asleep"]:
			continue
		var wp := _person_world(p) + Vector2(0, -6)
		var d := wp.distance_squared_to(world)
		if d < bd:
			bd = d
			best = int(p["id"])
	return best


func _person_world(p: Dictionary) -> Vector2:
	return Vector2(p["pos"]) * TILE + Vector2(8, 13)


func building_screen_top(id: int) -> Vector2:
	var b := sim.by_id(id)
	if b.is_empty():
		return Vector2.ZERO
	return Vector2(b["cell"]) * TILE


# ================================================================ chão
func _make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src := TileSetAtlasSource.new()
	src.texture = tex("ground")
	src.texture_region_size = Vector2i(TILE, TILE)
	for y in 2:
		for x in 8:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)
	return ts


func _hash(c: Vector2i) -> int:
	var hsh := (c.x * 73856093) ^ (c.y * 19349663) ^ 0x5bd1e995
	return absi(hsh)


func _paint_ground() -> void:
	for y in sim.h:
		for x in sim.w:
			_paint_cell(Vector2i(x, y))


func _paint_cell(c: Vector2i) -> void:
	var k := sim.terrain_at(c)
	var hh := _hash(c)
	var at: Vector2i
	if k == VilaSim.T_ROAD:
		at = Vector2i(hh % 4, 1)
	else:
		var r := hh % 100
		if r < 70:
			at = Vector2i(hh % 4, 0)
		elif r < 78:
			at = Vector2i(4, 0)
		elif r < 86:
			at = Vector2i(5, 0) if r % 2 == 0 else Vector2i(5 + (hh >> 4) % 3, 1)
		elif r < 97:
			at = Vector2i(6, 0)
		else:
			at = Vector2i(7, 0)
	if sim.occ[c.y * sim.w + c.x] >= 0:
		at = Vector2i(4, 1)
	_ground.set_cell(c, 0, at)


func _sync_terrain(all: bool) -> void:
	var n := sim.terrain.size()
	var first := _terrain_cache.size() != n
	for i in n:
		if not all and not first and _terrain_cache[i] == sim.terrain[i]:
			continue
		var c := Vector2i(i % sim.w, i / sim.w)
		_paint_cell(c)
		if _terrain_nodes.has(c):
			(_terrain_nodes[c] as Node).queue_free()
			_terrain_nodes.erase(c)
		var k: int = sim.terrain[i]
		var spr: Sprite2D = null
		match k:
			VilaSim.T_TREE:
				spr = _frame_sprite("tree", 4, _hash(c) % 4, 32)
				spr.material = _fx.tree_mat
			VilaSim.T_RUBBLE:
				spr = _frame_sprite("rubble", 3, _hash(c) % 3, 16)
			VilaSim.T_STUMP:
				spr = _frame_sprite("stump", 1, 0, 16)
		if spr != null:
			spr.position = Vector2(c.x * TILE, (c.y + 1) * TILE)
			_objects.add_child(spr)
			_terrain_nodes[c] = spr
	_terrain_cache = sim.terrain.duplicate()


func _frame_sprite(name: String, frames: int, frame: int, height: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(name)
	s.centered = false
	s.hframes = frames
	s.frame = frame
	s.offset = Vector2(0, -height)
	return s


# ================================================================ prédios
func _btex_name(b: Dictionary) -> String:
	var tp := String(b["type"])
	var lvl: int = int(b["level"])
	var maxl := {"moradia": 4, "horta": 3, "poco": 2, "deposito": 3, "oficina": 2, "galinheiro": 2}
	match tp:
		"torre":
			return "tower_%d" % mini(5, lvl)
		"moradia", "horta", "poco", "deposito", "oficina", "galinheiro":
			return "%s_%d" % [tp, mini(int(maxl[tp]), lvl)]
	return tp


func _sync_buildings() -> void:
	var seen := {}
	for b in sim.buildings:
		var id: int = int(b["id"])
		seen[id] = true
		var key := "%s|%s|%d|%d" % [b["type"], b["state"], int(b["level"]), sim.tower]
		var node: Dictionary = _bnodes.get(id, {})
		if node.is_empty() or String(node["key"]) != key:
			if not node.is_empty():
				(node["root"] as Node).queue_free()
			node = _make_building(b)
			node["key"] = key
			_bnodes[id] = node
			# chão por baixo vira terreno limpo
			var fp := sim._fp(String(b["type"]))
			for dy in fp.y:
				for dx in fp.x:
					_paint_cell(Vector2i(b["cell"]) + Vector2i(dx, dy))
		_update_building(b, node)
	for id in _bnodes.keys():
		if not seen.has(id):
			(_bnodes[id]["root"] as Node).queue_free()
			_bnodes.erase(id)


func _make_building(b: Dictionary) -> Dictionary:
	var tp := String(b["type"])
	var fp := sim._fp(tp)
	var root := Node2D.new()
	root.position = Vector2(Vector2i(b["cell"]).x * TILE, (Vector2i(b["cell"]).y + fp.y) * TILE)
	if bool(sim.def(tp).get("open", false)):
		_floor.add_child(root)
	else:
		_objects.add_child(root)
	var st := String(b["state"])
	var spr := Sprite2D.new()
	spr.centered = false
	var show_main := st != "site"
	if tp == "fogueira":
		spr.texture = tex("fogueira")
		spr.hframes = 4
	else:
		spr.texture = tex(_btex_name(b))
	if spr.texture != null:
		spr.offset = Vector2(0, -spr.texture.get_height())
	spr.visible = show_main
	root.add_child(spr)
	if st == "built" and spr.texture != null:
		_fx.attach(root, tp, int(b["level"]), spr.texture.get_height(), int(b["id"]))
	var ov: Sprite2D = null
	if st != "built":
		ov = Sprite2D.new()
		ov.centered = false
		ov.texture = tex("obra_%d" % clampi(fp.x, 2, 3))
		if ov.texture != null:
			ov.offset = Vector2(0, -ov.texture.get_height())
		if st == "upgrade":
			ov.modulate = Color(1, 1, 1, 0.85)
		root.add_child(ov)
	var crops: Array[Sprite2D] = []
	if tp == "horta" and st == "built":
		var n := 4 if int(b["level"]) < 3 else 6
		for i in n:
			var c := Sprite2D.new()
			c.texture = tex("crop")
			c.hframes = 4
			c.centered = false
			var col := i % 2 if n == 4 else i % 3
			var row := i / 2 if n == 4 else i / 3
			var cw := 16.0 if n == 4 else 10.0
			c.position = Vector2(1 + col * 14, -31 + row * 12) if n == 4 else Vector2(2 + col * (cw - 2), -30 + row * 12)
			root.add_child(c)
			crops.append(c)
	var lights: Array[PointLight2D] = []
	for spec in _light_specs(tp, int(b["level"]), st):
		var l := PointLight2D.new()
		l.texture = tex("light")
		l.color = spec["color"]
		l.texture_scale = float(spec["scale"])
		l.position = spec["pos"]
		l.energy = 0.0
		root.add_child(l)
		lights.append(l)
		_lights.append({"light": l, "base": float(spec["energy"]), "always": bool(spec.get("always", false))})
	# Prédio elétrico ou que gasta insumo: alerta em cima quando falta energia ou sucata.
	var warn: Sprite2D = null
	var d := sim.def(tp)
	if st == "built" and (d.has("power_use") or _input_of(b).size() > 0):
		warn = Sprite2D.new()
		warn.texture = tex("icons")
		warn.hframes = ICON_FRAMES
		warn.frame = 17 if d.has("power_use") else 15
		warn.position = Vector2(fp.x * TILE / 2.0, -fp.y * TILE - 10)
		warn.visible = false
		root.add_child(warn)
	return {"root": root, "sprite": spr, "overlay": ov, "crops": crops, "lights": lights, "key": "", "warn": warn}


func _input_of(b: Dictionary) -> Dictionary:
	return sim.level_def(b).get("input", {})


func _light_specs(tp: String, level: int, st: String) -> Array:
	var warm := Color(1.0, 0.68, 0.32)
	var cyan := Color(0.45, 0.95, 0.9)
	var pink := Color(0.95, 0.55, 0.9)
	if st == "site":
		return []
	match tp:
		"fogueira":
			return [{"pos": Vector2(8, -8), "color": Color(1.0, 0.6, 0.25), "scale": 2.6, "energy": 1.1, "always": true}]
		"moradia":
			return [{"pos": Vector2(16, -12 - 2 * level), "color": warm, "scale": 0.8 + 0.15 * level, "energy": 0.9}]
		"deposito":
			return [] if level < 2 else [{"pos": Vector2(16, -14), "color": warm, "scale": 0.9, "energy": 0.7}]
		"ferrovelho":
			return [{"pos": Vector2(20, -14), "color": warm, "scale": 0.9, "energy": 0.7}]
		"hatch":
			return [{"pos": Vector2(16, -18), "color": warm, "scale": 1.2, "energy": 0.8}]
		"gate":
			return [{"pos": Vector2(24, -24), "color": warm, "scale": 1.1, "energy": 0.9}]
		"poco":
			return [{"pos": Vector2(16, -14), "color": cyan, "scale": 0.6, "energy": 0.5}]
		"oficina":
			return [{"pos": Vector2(24, -16), "color": warm, "scale": 1.0, "energy": 0.8}]
		"gerador":
			return [{"pos": Vector2(15, -23), "color": Color(1.0, 0.3, 0.25), "scale": 0.4, "energy": 0.8, "always": true}]
		"cozinha":
			return [{"pos": Vector2(16, -14), "color": warm, "scale": 1.0, "energy": 0.9}]
		"estufa":
			return [{"pos": Vector2(24, -16), "color": pink, "scale": 1.3, "energy": 0.8, "always": true}]
		"galinheiro":
			return [{"pos": Vector2(16, -12), "color": warm, "scale": 0.6, "energy": 0.5}]
		"praca":
			return [{"pos": Vector2(24, -26), "color": warm, "scale": 1.6, "energy": 0.8}]
		"torre":
			var top := -50.0 if level <= 3 else (-76.0 if level == 4 else -94.0)
			var out := [{"pos": Vector2(16, top), "color": cyan, "scale": 1.0 + 0.3 * level, "energy": 0.9, "always": true}]
			if level >= 2:
				out.append({"pos": Vector2(16, -30), "color": pink, "scale": 1.2, "energy": 0.7, "always": true})
			return out
	return []


func _update_building(b: Dictionary, node: Dictionary) -> void:
	var tp := String(b["type"])
	var warn: Sprite2D = node.get("warn")
	if warn != null:
		var bad := false
		if sim.def(tp).has("power_use") and sim.power_frac() < 0.999:
			bad = true
		var inp := _input_of(b)
		for r in inp:
			if float(sim.stock[r]) < float(inp[r]):
				bad = true
		warn.visible = bad and int(_anim_t * 2.0) % 2 == 0
	if tp == "fogueira":
		(node["sprite"] as Sprite2D).frame = int(_anim_t * 8.0) % 4
	var crops: Array = node["crops"]
	if not crops.is_empty():
		var stage := 0
		var ws: Array = b["workers"]
		if not ws.is_empty():
			var p := sim.person(int(ws[0]))
			if not p.is_empty() and String(p["carry_res"]) == "comida":
				stage = clampi(int(float(p["carry"]) / float(sim.bal["people"]["carry"]) * 4.0), 0, 3)
			elif not p.is_empty():
				stage = 1
		for i in crops.size():
			(crops[i] as Sprite2D).frame = clampi(stage - (i % 2), 0, 3)


# ================================================================ pessoas
func _sync_people(delta: float) -> void:
	var seen := {}
	for p in sim.people:
		var id: int = int(p["id"])
		seen[id] = true
		var node: Dictionary = _pnodes.get(id, {})
		if node.is_empty():
			node = _make_person(p)
			_pnodes[id] = node
		var root: Node2D = node["root"]
		root.position = _person_world(p)
		var spr: Sprite2D = node["sprite"]
		root.visible = not p["asleep"]
		var f: Vector2 = p["facing"]
		var row := 0
		if absf(f.x) > absf(f.y):
			row = 2
			spr.flip_h = f.x < 0.0
		else:
			row = 1 if f.y < 0.0 else 0
			spr.flip_h = false
		# Cansaço (noites viradas): cor mais apagada e passo mais lento.
		var tired := int(p.get("tired", 0))
		spr.modulate = Color.WHITE if tired <= 0 else Color(1, 1, 1).lerp(Color(0.62, 0.64, 0.82), clampf(tired / 3.0, 0.25, 1.0))
		var col := 0
		if p["moving"]:
			col = 1 + int((_anim_t + float(id) * 0.37) * 8.0 * minf(1.0, sim.rest_mult(p))) % 4
		elif String(p["phase"]) in ["building", "working", "foraging"]:
			col = 1 + int((_anim_t + float(id) * 0.37) * 4.0) % 2   # mexendo no lugar
		spr.frame = row * 5 + col
		var carry: Sprite2D = node["carry"]
		var cr := String(p["carry_res"])
		carry.visible = cr != "" and String(p["phase"]) == "to_store"
		if carry.visible:
			carry.frame = 16 if cr == "pecas" else VilaSim.RES.find(cr)
		var alert: Sprite2D = node["alert"]
		alert.visible = p["hungry"] or p["thirsty"]
	for id in _pnodes.keys():
		if not seen.has(id):
			(_pnodes[id]["root"] as Node).queue_free()
			_pnodes.erase(id)


func _make_person(p: Dictionary) -> Dictionary:
	var root := Node2D.new()
	_objects.add_child(root)
	var spr := Sprite2D.new()
	spr.texture = tex("person_%d" % clampi(int(p["look"]), 0, 6))
	spr.hframes = 5
	spr.vframes = 3
	spr.offset = Vector2(0, -7)
	root.add_child(spr)
	var carry := Sprite2D.new()
	carry.texture = tex("icons")
	carry.hframes = ICON_FRAMES
	carry.position = Vector2(0, -18)
	carry.visible = false
	root.add_child(carry)
	var alert := Sprite2D.new()
	alert.texture = tex("icons")
	alert.hframes = ICON_FRAMES
	alert.frame = 15
	alert.position = Vector2(6, -18)
	alert.visible = false
	root.add_child(alert)
	return {"root": root, "sprite": spr, "carry": carry, "alert": alert}


# ================================================================ quadro a quadro
func _process(delta: float) -> void:
	if sim == null:
		return
	_anim_t += delta
	_sync_merchant()
	_sync_acc += delta
	if _sync_acc >= 0.25:
		_sync_acc = 0.0
		_sync_terrain(false)
		_sync_buildings()
	else:
		for b in sim.buildings:
			var node: Dictionary = _bnodes.get(int(b["id"]), {})
			if not node.is_empty():
				_update_building(b, node)
	_sync_people(delta)
	_update_light()
	_fx.update_fx(delta, sim, _night_k)
	if _zone_level != sim.tower:
		_zone_level = sim.tower
		_zone.queue_redraw()
	_overlay.queue_redraw()


## Cor do dia pela hora local: manhã fria, dia neutro levemente arroxeado, fim de tarde quente, noite azul.
func _update_light() -> void:
	var hr := sim.local_hour()
	var keys := [
		[0.0, Color(0.30, 0.30, 0.52)], [4.0, Color(0.32, 0.32, 0.55)], [5.2, Color(0.70, 0.62, 0.78)],
		[6.5, Color(0.96, 0.93, 1.0)], [17.0, Color(0.96, 0.93, 1.0)], [19.0, Color(0.92, 0.70, 0.66)],
		[20.5, Color(0.55, 0.45, 0.66)], [22.0, Color(0.32, 0.32, 0.55)], [24.0, Color(0.30, 0.30, 0.52)]]
	var col: Color = keys[0][1]
	for i in keys.size() - 1:
		var a: float = keys[i][0]
		var z: float = keys[i + 1][0]
		if hr >= a and hr <= z:
			col = (keys[i][1] as Color).lerp(keys[i + 1][1], (hr - a) / maxf(0.001, z - a))
			break
	_modulate.color = col
	_night_k = clampf(1.0 - (col.v - 0.5) / 0.46, 0.0, 1.0)
	var flick := 0.92 + 0.08 * sin(_anim_t * 11.0) * sin(_anim_t * 3.7)
	for e in _lights:
		var lo: Variant = e["light"]   # sem tipo: o prédio pode ter sido refeito e a luz liberada
		if not is_instance_valid(lo):
			continue
		var l := lo as PointLight2D
		var k := _night_k if not bool(e["always"]) else 0.25 + 0.75 * _night_k
		l.energy = float(e["base"]) * k * flick
	_lights = _lights.filter(func(e: Dictionary) -> bool: return is_instance_valid(e["light"]))


## Área da vila: fora do alcance da torre o chão fica mais escuro, e a borda leva uma linha tracejada.
func _draw_zone() -> void:
	var shade := Color(0.03, 0.02, 0.05, 0.32)
	var edge := Color(0.95, 0.85, 0.6, 0.45)
	for y in sim.h:
		for x in sim.w:
			var c := Vector2i(x, y)
			var p := Vector2(c) * TILE
			if not sim.in_zone(c):
				_zone.draw_rect(Rect2(p, Vector2(TILE, TILE)), shade)
				continue
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if sim.in_zone(c + d):
					continue
				var a := p + Vector2(maxi(d.x, 0), maxi(d.y, 0)) * TILE
				var along := Vector2(absi(d.y), absi(d.x))
				for k in 4:
					_zone.draw_line(a + along * (k * 4 + 0.5), a + along * (k * 4 + 2.5), edge, 1.0)


var _timer_font: Font


## Tempo restante (contagem regressiva, 2:35) logo à direita da barra. `left_mid` é o ponto do meio da
## borda esquerda do texto. No zoom de longe o texto cresce para continuar legível.
func _timer_text(left_mid: Vector2, sec: float, col: Color) -> void:
	if sec < 0.0:
		return
	if _timer_font == null:
		_timer_font = load("res://assets/fonts/DotGothic16-Regular.ttf")
	var cam := get_viewport().get_camera_2d()
	var k := 1.0 / cam.zoom.x if cam != null and cam.zoom.x < 0.99 else 1.0
	var txt := VilaHud.fmt_clock(sec)
	var sz := 8
	var wdt := _timer_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_overlay.draw_set_transform(left_mid.round(), 0.0, Vector2(k, k))
	_overlay.draw_rect(Rect2(Vector2(0, -4), Vector2(wdt + 2, 8)), Color(0.05, 0.04, 0.06, 0.8))
	_overlay.draw_string(_timer_font, Vector2(1, 3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
	_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_overlay() -> void:
	# Recurso clicado na barra de cima: contorno piscando nos prédios que produzem e em quem está nele.
	if hl_res != "":
		var hc := Color(1.0, 0.85, 0.4, 0.55 + 0.45 * sin(_anim_t * 6.0))
		for b in sim.buildings:
			var bd := sim.def(String(b["type"]))
			if String(bd.get("res", "")) == hl_res or (hl_res == "energia" and bd.has("power_out")):
				var fp := sim._fp(String(b["type"]))
				_overlay.draw_rect(Rect2(Vector2(Vector2i(b["cell"])) * TILE - Vector2(1, 1), Vector2(fp) * TILE + Vector2(2, 2)), hc, false, 1.0)
		for p in sim.people:
			if String(p["job"].get("res", "")) == hl_res:
				_overlay.draw_arc(_person_world(p) + Vector2(0, -5), 7.0, 0.0, TAU, 16, hc, 1.0)
	# Barras de obra
	for b in sim.buildings:
		if String(b["state"]) == "built":
			continue
		var fp := sim._fp(String(b["type"]))
		var top := Vector2(Vector2i(b["cell"])) * TILE + Vector2(0, -6)
		var wpx := float(fp.x * TILE) - 4.0
		var r := clampf(float(b["progress"]) / maxf(0.001, float(b["total"])), 0.0, 1.0)
		_overlay.draw_rect(Rect2(top + Vector2(2, 0), Vector2(wpx, 4)), Color(0.05, 0.04, 0.06, 0.9))
		_overlay.draw_rect(Rect2(top + Vector2(3, 1), Vector2((wpx - 2.0) * r, 2)), Color(1.0, 0.75, 0.3) if int(b["builder"]) >= 0 else Color(0.55, 0.5, 0.55))
		_timer_text(top + Vector2(3.0 + wpx, 2), sim.site_eta(b), Color(1.0, 0.85, 0.55) if int(b["builder"]) >= 0 else Color(0.7, 0.66, 0.7))
	# Barrinha em cima de quem está trabalhando: quanto falta para levar a carga (ou derrubar a árvore,
	# ou terminar a obra), com o ícone do que está fazendo.
	var icons := tex("icons")
	var carry_max: float = float(sim.bal["people"]["carry"])
	for p in sim.people:
		if p["asleep"]:
			continue
		var ph := String(p["phase"])
		var job: Dictionary = p["job"]
		var frac := -1.0
		var ic := -1
		match ph:
			"working":
				var wb := sim.by_id(int(job.get("b", -1)))
				frac = float(p["carry"]) / (sim.work_trip(wb) if not wb.is_empty() else carry_max)
				ic = _res_icon(String(job.get("res", "")))
			"foraging":
				var fd: Dictionary = sim.bal["forage"].get(String(job.get("res", "")), {})
				frac = float(p["work_t"]) / maxf(0.001, float(fd.get("work_s", 1.0)))
				ic = _res_icon(String(job.get("res", "")))
			"building":
				var bb := sim.by_id(int(job.get("b", -1)))
				if not bb.is_empty():
					frac = float(bb["progress"]) / maxf(0.001, float(bb["total"]))
				ic = 8
		if frac < 0.0:
			continue
		var at := _person_world(p) + Vector2(-6, -24)
		_overlay.draw_rect(Rect2(at, Vector2(12, 3)), Color(0.05, 0.04, 0.06, 0.85))
		_overlay.draw_rect(Rect2(at + Vector2(1, 1), Vector2(10.0 * clampf(frac, 0.0, 1.0), 1)), Color(0.55, 0.95, 0.7))
		if icons != null and ic >= 0:
			_overlay.draw_texture_rect_region(icons, Rect2(at + Vector2(13, -3), Vector2(8, 8)), Rect2(ic * 8, 0, 8, 8))
		# A obra já mostra o tempo dela em cima; aqui só carga e coleta.
		if ph != "building":
			_timer_text(at + Vector2(22 if ic >= 0 else 13, 1), sim.eta(p), Color(0.75, 1.0, 0.8))
	# Cansado: um "z" pequeno subindo do lado da cabeça.
	if _timer_font == null:
		_timer_font = load("res://assets/fonts/DotGothic16-Regular.ttf")
	for p in sim.people:
		if p["asleep"] or int(p.get("tired", 0)) <= 0:
			continue
		var ph2 := fposmod(_anim_t * 0.6 + float(p["id"]) * 0.31, 1.0)
		var zp := _person_world(p) + Vector2(-9, -16 - ph2 * 5.0)
		_overlay.draw_string(_timer_font, zp.round(), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.75, 0.8, 1.0, 1.0 - ph2))
	# Obra esperando alguém livre: ampulheta (relógio) piscando em cima.
	for b in sim.buildings:
		if String(b["state"]) != "built" and int(b["builder"]) < 0 and icons != null and int(_anim_t * 2.0) % 2 == 0:
			var fpw := sim._fp(String(b["type"]))
			var pos := Vector2(Vector2i(b["cell"])) * TILE + Vector2(fpw.x * TILE / 2.0 - 4.0, -24)
			_overlay.draw_texture_rect_region(icons, Rect2(pos, Vector2(8, 8)), Rect2(6 * 8, 0, 8, 8))
	# Fantasma de posicionamento
	if ghost_type != "" and ghost_cell.x >= 0:
		var fp2 := sim._fp(ghost_type)
		# Cada célula com a sua cor: só a que bloqueia fica vermelha.
		var t_ok := tex("ghost_ok")
		var t_bad := tex("ghost_bad")
		var bt := tex(_btex_name({"type": ghost_type, "level": 1, "state": "built"}))
		for dy in fp2.y:
			for dx in fp2.x:
				var gc := ghost_cell + Vector2i(dx, dy)
				var t := t_ok if sim.cell_ok(gc) else t_bad
				if t != null:
					_overlay.draw_texture(t, Vector2(gc) * TILE)
		if bt != null:
			var bottom := Vector2(ghost_cell.x * TILE, (ghost_cell.y + fp2.y) * TILE)
			var src := Rect2(0, 0, bt.get_width() / (4 if ghost_type == "fogueira" else 1), bt.get_height())
			_overlay.draw_texture_rect_region(bt, Rect2(bottom - Vector2(0, src.size.y), src.size), src, Color(1, 1, 1, 0.6))
		# porta: onde as pessoas vão parar
		var dc := sim.door_for(ghost_type, ghost_cell)
		if dc.x >= 0:
			_overlay.draw_rect(Rect2(Vector2(dc) * TILE + Vector2(5, 5), Vector2(6, 6)), Color(1, 1, 1, 0.35), false)
		else:
			# todo cercado: contorno vermelho em volta, ninguém conseguiria chegar
			_overlay.draw_rect(Rect2(Vector2(ghost_cell) * TILE - Vector2(1, 1), Vector2(fp2) * TILE + Vector2(2, 2)), Color(1, 0.3, 0.3, 0.9), false)
	# Entulho marcado para limpar: colchetes âmbar e um martelo
	var mk := tex("icons")
	for c in sim.marked:
		var r1 := Rect2(Vector2(c) * TILE, Vector2(TILE, TILE))
		_draw_brackets(r1, Color(1.0, 0.75, 0.3, 0.9))
		if mk != null:
			var mi := 2 if sim.terrain_at(c) == VilaSim.T_TREE else 8   # madeira na árvore, martelo no entulho
			_overlay.draw_texture_rect_region(mk, Rect2(r1.position + Vector2(4, -6), Vector2(8, 8)), Rect2(mi * 8, 0, 8, 8))
	if ghost_type == "" and hover_cell.x >= 0:
		var sel := tex("selecao")
		var bh := sim.building_at(hover_cell)
		if not bh.is_empty():
			var fp3 := sim._fp(String(bh["type"]))
			var r0 := Rect2(Vector2(Vector2i(bh["cell"])) * TILE, Vector2(fp3) * TILE)
			_draw_brackets(r0)
		elif sel != null:
			_overlay.draw_texture(sel, Vector2(hover_cell) * TILE, Color(1, 1, 1, 0.55))


func _res_icon(res: String) -> int:
	if res == "pecas":
		return 16
	return VilaSim.RES.find(res)


func _draw_brackets(r: Rect2, c: Color = Color(1, 1, 1, 0.7)) -> void:
	var l := 4.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		_overlay.draw_line(corner, corner + Vector2(l * sx, 0), c, 1.0)
		_overlay.draw_line(corner, corner + Vector2(0, l * sy), c, 1.0)


# ================================================================ mercador na praça
func _sync_merchant() -> void:
	var here := sim.merchant_here()
	if here == not _merchant_nodes.is_empty():
		return
	for n in _merchant_nodes:
		(n as Node).queue_free()
	_merchant_nodes = []
	if not here:
		return
	var pr := sim._first("praca")
	if pr.is_empty():
		return
	var base := Vector2(Vector2i(pr["cell"])) * TILE
	var cart := Sprite2D.new()
	cart.texture = tex("carroca")
	cart.centered = false
	cart.position = base + Vector2(10, 12 + 24)
	cart.offset = Vector2(0, -24)
	_objects.add_child(cart)
	var man := Sprite2D.new()
	man.texture = tex("merchant")
	man.hframes = 5
	man.vframes = 3
	man.offset = Vector2(0, -7)
	man.position = base + Vector2(30, 40)
	_objects.add_child(man)
	_merchant_nodes = [cart, man]


## Onde o mascate está (para clicar nele e abrir o cartão do mercador).
func merchant_rect() -> Rect2:
	if _merchant_nodes.size() < 2:
		return Rect2()
	var man: Sprite2D = _merchant_nodes[1]
	return Rect2(man.position + Vector2(-8, -18), Vector2(16, 20))
