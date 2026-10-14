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
var _objects: Node2D
var _overlay: Node2D
var _modulate: CanvasModulate
var _terrain_cache: PackedByteArray = PackedByteArray()
var _terrain_nodes: Dictionary = {}     # célula -> Sprite2D (árvore, toco, entulho)
var _bnodes: Dictionary = {}            # id -> {root, sprite, overlay, bar, crops, lights, key}
var _pnodes: Dictionary = {}            # id -> {root, sprite, carry, zz}
var _tex: Dictionary = {}
var _lights: Array[Dictionary] = []     # {light, base, kind}
var _anim_t: float = 0.0
var _night_k: float = 0.0               # 0 = dia, 1 = noite fechada
var _sync_acc: float = 0.0


func setup(s: VilaSim) -> void:
	sim = s
	for c in get_children():
		c.queue_free()
	_terrain_nodes.clear()
	_bnodes.clear()
	_pnodes.clear()
	_lights.clear()
	_ground = TileMapLayer.new()
	_ground.tile_set = _make_tileset()
	add_child(_ground)
	_objects = Node2D.new()
	_objects.y_sort_enabled = true
	add_child(_objects)
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
	match tp:
		"torre":
			return "tower_%d" % mini(3, lvl if String(b["state"]) == "built" else lvl)
		"deposito", "horta":
			return "%s_%d" % [tp, mini(2, lvl)]
		"hatch", "gate":
			return tp
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
		var n := 4 if int(b["level"]) == 1 else 6
		for i in n:
			var c := Sprite2D.new()
			c.texture = tex("crop")
			c.hframes = 4
			c.centered = false
			var col := i % 2 if n == 4 else i % 3
			var row := i / 2 if n == 4 else i / 3
			var cw := 16.0 if n == 4 else 10.0
			c.position = Vector2(2 + col * (cw - 2) + (0 if n == 4 else 0), -30 + row * 12)
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
	return {"root": root, "sprite": spr, "overlay": ov, "crops": crops, "lights": lights, "key": ""}


func _light_specs(tp: String, level: int, st: String) -> Array:
	var warm := Color(1.0, 0.68, 0.32)
	var cyan := Color(0.45, 0.95, 0.9)
	var pink := Color(0.95, 0.55, 0.9)
	if st == "site":
		return []
	match tp:
		"fogueira":
			return [{"pos": Vector2(8, -8), "color": Color(1.0, 0.6, 0.25), "scale": 2.6, "energy": 1.1, "always": true}]
		"barraco":
			return [{"pos": Vector2(16, -14), "color": warm, "scale": 1.0, "energy": 0.9}]
		"casa":
			return [{"pos": Vector2(12, -16), "color": warm, "scale": 1.0, "energy": 0.8}, {"pos": Vector2(36, -16), "color": warm, "scale": 1.0, "energy": 0.8}]
		"deposito", "ferrovelho":
			return [{"pos": Vector2(20, -14), "color": warm, "scale": 0.9, "energy": 0.7}]
		"hatch":
			return [{"pos": Vector2(16, -18), "color": warm, "scale": 1.2, "energy": 0.8}]
		"gate":
			return [{"pos": Vector2(24, -24), "color": warm, "scale": 1.1, "energy": 0.9}]
		"poco":
			return [{"pos": Vector2(16, -14), "color": cyan, "scale": 0.6, "energy": 0.5}]
		"torre":
			var out := [{"pos": Vector2(16, -50), "color": cyan, "scale": 1.0 + 0.3 * level, "energy": 0.9, "always": true}]
			if level >= 2:
				out.append({"pos": Vector2(16, -30), "color": pink, "scale": 1.2, "energy": 0.7, "always": true})
			return out
	return []


func _update_building(b: Dictionary, node: Dictionary) -> void:
	var tp := String(b["type"])
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
		var col := 0
		if p["moving"]:
			col = 1 + int((_anim_t + float(id) * 0.37) * 8.0) % 4
		elif String(p["phase"]) in ["building", "working", "foraging"]:
			col = 1 + int((_anim_t + float(id) * 0.37) * 4.0) % 2   # mexendo no lugar
		spr.frame = row * 5 + col
		var carry: Sprite2D = node["carry"]
		var cr := String(p["carry_res"])
		carry.visible = cr != "" and String(p["phase"]) == "to_store"
		if carry.visible:
			carry.frame = VilaSim.RES.find(cr)
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
	spr.texture = tex("person_%d" % clampi(int(p["look"]), 0, 5))
	spr.hframes = 5
	spr.vframes = 3
	spr.offset = Vector2(0, -7)
	root.add_child(spr)
	var carry := Sprite2D.new()
	carry.texture = tex("icons")
	carry.hframes = 16
	carry.position = Vector2(0, -18)
	carry.visible = false
	root.add_child(carry)
	var alert := Sprite2D.new()
	alert.texture = tex("icons")
	alert.hframes = 16
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
	_overlay.queue_redraw()


## Cor do dia pela hora local: manhã fria, dia neutro levemente arroxeado, fim de tarde quente, noite azul.
func _update_light() -> void:
	var hr := sim.local_hour()
	var keys := [
		[0.0, Color(0.30, 0.30, 0.52)], [5.0, Color(0.32, 0.32, 0.55)], [6.5, Color(0.70, 0.62, 0.78)],
		[8.0, Color(0.96, 0.93, 1.0)], [17.0, Color(0.96, 0.93, 1.0)], [19.0, Color(0.92, 0.70, 0.66)],
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
		var l: PointLight2D = e["light"]
		if not is_instance_valid(l):
			continue
		var k := _night_k if not bool(e["always"]) else 0.25 + 0.75 * _night_k
		l.energy = float(e["base"]) * k * flick
	_lights = _lights.filter(func(e: Dictionary) -> bool: return is_instance_valid(e["light"]))


func _draw_overlay() -> void:
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
	# Fantasma de posicionamento
	if ghost_type != "" and ghost_cell.x >= 0:
		var fp2 := sim._fp(ghost_type)
		var ok := sim.can_place(ghost_type, ghost_cell)
		var t := tex("ghost_ok" if ok else "ghost_bad")
		var bt := tex(_btex_name({"type": ghost_type, "level": 1, "state": "built"}))
		for dy in fp2.y:
			for dx in fp2.x:
				var p := Vector2(ghost_cell + Vector2i(dx, dy)) * TILE
				if t != null:
					_overlay.draw_texture(t, p)
		if bt != null:
			var bottom := Vector2(ghost_cell.x * TILE, (ghost_cell.y + fp2.y) * TILE)
			var src := Rect2(0, 0, bt.get_width() / (4 if ghost_type == "fogueira" else 1), bt.get_height())
			_overlay.draw_texture_rect_region(bt, Rect2(bottom - Vector2(0, src.size.y), src.size), src, Color(1, 1, 1, 0.6))
		# porta: onde as pessoas vão parar
		var door := Vector2(ghost_cell + Vector2i(fp2.x / 2, fp2.y)) * TILE
		_overlay.draw_rect(Rect2(door + Vector2(5, 5), Vector2(6, 6)), Color(1, 1, 1, 0.35), false)
	elif hover_cell.x >= 0:
		var sel := tex("selecao")
		var bh := sim.building_at(hover_cell)
		if not bh.is_empty():
			var fp3 := sim._fp(String(bh["type"]))
			var r0 := Rect2(Vector2(Vector2i(bh["cell"])) * TILE, Vector2(fp3) * TILE)
			_draw_brackets(r0)
		elif sel != null:
			_overlay.draw_texture(sel, Vector2(hover_cell) * TILE, Color(1, 1, 1, 0.55))


func _draw_brackets(r: Rect2) -> void:
	var c := Color(1, 1, 1, 0.7)
	var l := 4.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		_overlay.draw_line(corner, corner + Vector2(l * sx, 0), c, 1.0)
		_overlay.draw_line(corner, corner + Vector2(0, l * sy), c, 1.0)
