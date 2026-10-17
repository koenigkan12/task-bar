class_name WorldView
extends Node2D
## Desenha a vila a partir da simulação: chão (TileMapLayer), árvores e entulho, prédios, pessoas,
## luz do dia/noite e o fantasma de posicionamento. Não decide nada: só lê `sim`.

const TILE := 16
const ART := "res://assets/art/"
const MARGEM := 192                     # ilha.png tem água desenhada além do mapa (tools/estilo_ilha.py)
const RUBBLE_FRAMES := 10              # rubble.png (tools/estilo_ilha.py): 8 de terra + 2 de beira d'água
const RUBBLE_SHORE := 2
const CREME := Color8(204, 198, 186)     # destaque de 1 px no hover (estilo da ilha)

var sim: VilaSim
var hover_cell: Vector2i = Vector2i(-1, -1)
var ghost_type: String = ""          # prédio sendo posicionado ("" = nenhum)
var ghost_cell: Vector2i = Vector2i(-1, -1)
var ghost_level: int = 1               # mover: o fantasma mostra o prédio no nível dele
var sel_building := -1                 # prédio com o cartão aberto: torre mostra o alcance
var show_arrivals := false             # tutorial: mostra por onde os zumbis chegam mesmo fora de hora

var _ground: Sprite2D
var _flora: VilaFlora                  # flores da mata que brilham de noite
var _water: VilaWater                  # ondas, vento, peixe e o farol do porto
var _boat: Sprite2D                     # bote no porto enquanto tem gente esperando para entrar
var ICON_FRAMES := 28                   # icons.png: ícones de 8 px (setup lê da largura)
var _defense: VilaDefenseView
var _objects: Node2D
var _floor: Node2D
var _fx: VilaFx
var _merchant_nodes: Array = []          # banca, mascate e barco enquanto o mercador está por aqui
var _overlay: Node2D
var _zone: Node2D
var _zone_level: int = -1
var build_grid := false                  # modo construção: grade nas casas da área da vila
var _grid_drawn := false
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
	# Chão, beira e água da ilha: uma imagem só (a forma da ilha não muda).
	_ground = Sprite2D.new()
	_ground.texture = tex("ilha")
	_ground.centered = false
	_ground.position = Vector2(-MARGEM, -MARGEM)
	_ground.z_index = -10
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
	_m_state = ""
	_m_seen = false
	var itex := tex("icons")
	if itex != null:
		ICON_FRAMES = itex.get_width() / 8
	_defense = VilaDefenseView.new()
	add_child(_defense)
	_defense.setup(sim, _objects, _floor, itex, tex("zumbi"), tex("zumbi_chefe"), tex("light"))
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
	_flora = VilaFlora.new()
	add_child(_flora)
	_flora.setup(sim, tex("flor_brilho"))
	_water = VilaWater.new()
	add_child(_water)
	_water.setup(sim, tex("farol"), _objects)
	_boat = Sprite2D.new()
	_boat.texture = tex("bote")
	_boat.centered = false
	_boat.visible = false
	_boat.z_index = -5
	add_child(_boat)
	_sync_terrain(true)
	_sync_buildings()
	_sync_people(0.0)


func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := ART + name + ".png"
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


## Versão "de dia" do sprite: janelas e lampiões (os dois laranjas acesos) viram vidro escuro.
## Sem nenhum pixel aceso, devolve a própria textura.
func tex_day(name: String) -> Texture2D:
	var key := name + "#dia"
	if _tex.has(key):
		return _tex[key]
	var t := tex(name)
	var out: Texture2D = t
	if t != null:
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		var lit := {Color8(240, 196, 104).to_rgba32(): Color8(67, 52, 85), Color8(250, 226, 150).to_rgba32(): Color8(102, 95, 146)}
		var changed := false
		var spots: Array[Vector2i] = []
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.99 and lit.has(Color(c, 1.0).to_rgba32()):
					img.set_pixel(x, y, lit[Color(c, 1.0).to_rgba32()])
					spots.append(Vector2i(x, y))
					changed = true
		# O brilho em volta da chama (vermelho-alaranjado colado nela) também apaga; senão, com a luz
		# forte do dia, o lampião parecia aceso.
		for sp in spots:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var q := sp + Vector2i(dx, dy)
					if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
						continue
					var g := img.get_pixel(q.x, q.y)
					if g.a > 0.99 and g.r > 0.43 and g.r - g.g > 0.2 and g.r - g.b > 0.3:
						img.set_pixel(q.x, q.y, Color8(67, 52, 85))
		if changed:
			out = ImageTexture.create_from_image(img)
	_tex[key] = out
	return out


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


## Prédio pelo desenho, não só pelo chão que ocupa: o telhado que passa da base também conta
## (antes o clique no alto do ferro-velho ou da serraria caía no vazio). O da frente ganha.
func building_at_px(world: Vector2) -> Dictionary:
	var best := {}
	var by := -1e9
	for b in sim.buildings:
		var n: Dictionary = _bnodes.get(int(b["id"]), {})
		if n.is_empty():
			continue
		var fp := sim._fp(String(b["type"]))
		var bottom := float(Vector2i(b["cell"]).y + fp.y) * TILE
		var h := float(fp.y) * TILE
		var sp: Sprite2D = n["sprite"]
		if sp.texture != null and sp.visible:
			h = maxf(h, float(sp.texture.get_height()))
		var r := Rect2(float(Vector2i(b["cell"]).x) * TILE, bottom - h, float(fp.x) * TILE, h)
		if r.has_point(world) and bottom > by:
			by = bottom
			best = b
	return best


## Marcador de onde o jogador mandou alguém (anel que abre e some) e, se não deu, o motivo ali do lado.
var _orders: Array[Dictionary] = []   # {pos, t, ok, text}
var selected := -1                     # pessoa selecionada (cartão aberto): anel nos pés


func order_mark(world: Vector2, ok: bool, text: String = "") -> void:
	_orders.append({"pos": world, "t": 0.0, "ok": ok, "text": text})


func _person_world(p: Dictionary) -> Vector2:
	return Vector2(p["pos"]) * TILE + Vector2(8, 13)


func building_screen_top(id: int) -> Vector2:
	var b := sim.by_id(id)
	if b.is_empty():
		return Vector2.ZERO
	return Vector2(b["cell"]) * TILE


# ================================================================ chão
func _hash(c: Vector2i) -> int:
	var hsh := (c.x * 73856093) ^ (c.y * 19349663) ^ 0x5bd1e995
	return absi(hsh)


func _sync_terrain(all: bool) -> void:
	var n := sim.terrain.size()
	var first := _terrain_cache.size() != n
	for i in n:
		if not all and not first and _terrain_cache[i] == sim.terrain[i]:
			continue
		var c := Vector2i(i % sim.w, i / sim.w)
		if _terrain_nodes.has(c):
			(_terrain_nodes[c] as Node).queue_free()
			_terrain_nodes.erase(c)
		var k: int = sim.terrain[i]
		var spr: Sprite2D = null
		match k:
			VilaSim.T_TREE:
				# Uma árvore por tile; a copa (34 px) passa do tile e encosta nas vizinhas, como mata.
				spr = _frame_sprite("tree", 4, _hash(c) % 4, 44)
				spr.offset.x = -9
				spr.offset.y += 2
				spr.material = _fx.tree_mat
				var sh := Sprite2D.new()
				sh.texture = tex("tree_sombra")
				sh.centered = false
				sh.position = Vector2(-5, -5)
				sh.z_index = -1   # no chão, embaixo de todas as copas
				spr.add_child(sh)
			VilaSim.T_RUBBLE:
				# Resto do mundo de antes: na beira do rio, o que a água trouxe (barco encalhado, boia).
				var shore := false
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if sim.terrain_at(c + d) == VilaSim.T_WATER:
						shore = true
				var fr := RUBBLE_FRAMES - RUBBLE_SHORE + _hash(c) % RUBBLE_SHORE if shore else _hash(c) % (RUBBLE_FRAMES - RUBBLE_SHORE)
				spr = _frame_sprite("rubble", RUBBLE_FRAMES, fr, 28)
				spr.offset = Vector2(-7, -25)
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
	var maxl := {"moradia": 4, "horta": 3, "poco": 3, "deposito": 3, "oficina": 3, "galinheiro": 3,
			"torre_arq": 3, "canhao": 3, "choque": 2, "muro": 4}
	# Estes têm o nível 1 sem número no nome do arquivo.
	var plain := {"serraria": 3, "ferrovelho": 3, "cozinha": 2, "estufa": 2}
	match tp:
		"torre":
			return "tower_%d" % mini(5, lvl)
		"moradia", "horta", "poco", "deposito", "oficina", "galinheiro", "torre_arq", "canhao", "choque", "muro":
			return "%s_%d" % [tp, mini(int(maxl[tp]), lvl)]
	if plain.has(tp) and lvl >= 2:
		return "%s_%d" % [tp, mini(int(plain[tp]), lvl)]
	return tp


func _sync_buildings() -> void:
	var seen := {}
	for b in sim.buildings:
		var id: int = int(b["id"])
		seen[id] = true
		var key := "%s|%s|%d|%d|%s" % [b["type"], b["state"], int(b["level"]), sim.tower, str(b["cell"])]
		var node: Dictionary = _bnodes.get(id, {})
		if node.is_empty() or String(node["key"]) != key:
			if not node.is_empty():
				(node["root"] as Node).queue_free()
			node = _make_building(b)
			node["key"] = key
			_bnodes[id] = node
		_update_building(b, node)
		(node["root"] as Node2D).modulate.a = 0.3 if id == sim.lifted else 1.0   # no ar: sendo movido
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
	var show_main := st != "site" and tp != "muro"   # muro: o VilaDefenseView desenha ligado aos vizinhos
	if tp == "fogueira":
		spr.texture = tex("fogueira")
		spr.hframes = 4
	else:
		spr.texture = tex(_btex_name(b))
	var tex_lit: Texture2D = spr.texture
	var tex_dia: Texture2D = spr.texture if tp == "fogueira" else tex_day(_btex_name(b))
	if spr.texture != null:
		# Peça mais larga ou mais estreita que a pegada fica centrada nela; o píer desce para a água.
		var fw := spr.texture.get_width() / spr.hframes
		spr.offset = Vector2(roundi((fp.x * TILE - fw) / 2.0), -spr.texture.get_height() + (12 if tp == "gate" else 0))
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
		# Lampião (fogo) ilumina pouco e treme; lâmpada elétrica ilumina mais longe e firme.
		var fire := bool(spec.get("fire", false))
		var elec_l := bool(spec.get("electric", false))
		l.texture_scale = float(spec["scale"]) * (1.4 if fire else (2.2 if elec_l else 1.8))
		l.position = spec["pos"]
		l.energy = 0.0
		root.add_child(l)
		lights.append(l)
		_lights.append({"light": l, "base": float(spec["energy"]) * (0.8 if fire else (1.2 if elec_l else 1.0)), "always": bool(spec.get("always", false)),
				"fire": fire, "electric": elec_l, "ph": randf() * TAU})
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
	# Sem trepadeira nos prédios: a vila está sendo construída e tem gente cuidando. A mata fica no
	# mapa (flores, árvores voltando), não em cima das casas.
	var vines: Node2D = null
	return {"root": root, "sprite": spr, "overlay": ov, "crops": crops, "lights": lights, "key": "", "warn": warn, "tex_lit": tex_lit, "tex_dia": tex_dia,
			"electric": sim.def(tp).has("power_use"), "vines": vines}


func _input_of(b: Dictionary) -> Dictionary:
	return sim.level_def(b).get("input", {})


func _light_specs(tp: String, level: int, st: String) -> Array:
	var warm := Color(1.0, 0.68, 0.32)
	var cyan := Color(0.45, 0.95, 0.9)
	var pink := Color(0.95, 0.55, 0.9)
	var elec := Color(0.86, 0.93, 1.0)   # lâmpada: branca e forte, só com energia
	if st == "site":
		return []
	match tp:
		"fogueira":
			return [{"pos": Vector2(8, -8), "color": Color(1.0, 0.6, 0.25), "scale": 2.6, "fire": true, "energy": 1.1, "always": true}]
		"moradia":
			return [{"pos": Vector2(16, -12 - 2 * level), "color": warm, "scale": 0.8 + 0.15 * level, "fire": true, "energy": 0.9}]
		"deposito":
			return [] if level < 2 else [{"pos": Vector2(16, -14), "color": warm, "scale": 0.9, "fire": true, "energy": 0.7}]
		"ferrovelho":
			return [{"pos": Vector2(20, -14), "color": warm, "scale": 0.9, "fire": true, "energy": 0.7}]
		"hatch":
			return [{"pos": Vector2(16, -18), "color": warm, "scale": 1.2, "fire": true, "energy": 0.8}]
		"gate":
			return [{"pos": Vector2(24, -24), "color": warm, "scale": 1.1, "fire": true, "energy": 0.9}]
		"poco":
			return [{"pos": Vector2(16, -14), "color": cyan, "scale": 0.6, "energy": 0.5}]
		"oficina":
			return [{"pos": Vector2(24, -16), "color": elec, "scale": 1.0, "electric": true, "energy": 0.9}]
		"gerador":
			return [{"pos": Vector2(15, -23), "color": Color(1.0, 0.3, 0.25), "scale": 0.4, "energy": 0.8, "always": true}]
		"cozinha":
			return [{"pos": Vector2(16, -14), "color": warm, "scale": 1.0, "fire": true, "energy": 0.9}]
		"estufa":
			return [{"pos": Vector2(24, -16), "color": pink, "scale": 1.3, "energy": 0.8, "always": true, "electric": true}]
		"galinheiro":
			return [{"pos": Vector2(16, -12), "color": warm, "scale": 0.6, "fire": true, "energy": 0.5}]
		"deco_lampiao":
			return [{"pos": Vector2(8, -19), "color": warm, "scale": 0.8, "fire": true, "energy": 0.9}]
		"praca":
			return [{"pos": Vector2(24, -26), "color": warm, "scale": 1.6, "fire": true, "energy": 0.8}]
		"holofote":
			return [{"pos": Vector2(8, -14), "color": Color(1.0, 0.95, 0.78), "scale": 3.2, "energy": 1.0, "electric": true},
					{"pos": Vector2(8, -20), "color": Color(1.0, 0.95, 0.78), "scale": 0.5, "energy": 1.2, "electric": true}]
		"choque":
			return [{"pos": Vector2(16, -40), "color": Color(0.6, 0.9, 1.0), "scale": 0.8, "energy": 0.9, "electric": true}]
		"mina":
			return [{"pos": Vector2(8, -10), "color": Color(1.0, 0.3, 0.25), "scale": 0.15, "energy": 0.6, "always": true}]
		"torre":
			var top := -50.0 if level <= 3 else (-76.0 if level == 4 else -94.0)
			var out := [{"pos": Vector2(16, top), "color": cyan, "scale": 1.0 + 0.3 * level, "energy": 0.9, "always": true}]
			if level >= 2:
				out.append({"pos": Vector2(16, -30), "color": pink, "scale": 1.2, "energy": 0.7, "always": true})
			return out
	return []


func _update_building(b: Dictionary, node: Dictionary) -> void:
	var tp := String(b["type"])
	var vn: Node2D = node.get("vines")
	if vn != null:
		vn.visible = sim.overgrown(b)
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
	# Avariado pelos zumbis: apagado; ruína: escuro e baixo (o alerta pisca na camada da defesa).
	var spm: Sprite2D = node["sprite"]
	if bool(b.get("ruin", false)):
		spm.modulate = Color(0.42, 0.36, 0.44)
	elif bool(b.get("broken", false)):
		spm.modulate = Color(0.78, 0.72, 0.78)
	else:
		spm.modulate = Color.WHITE
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
			var gone: Node2D = _pnodes[id]["root"]
			_pnodes.erase(id)
			if sim.died_ids.has(id):
				# Morreu: o boneco tomba de lado, fica um instante e some.
				sim.died_ids.erase(id)
				gone.visible = true
				var tw := gone.create_tween()
				tw.tween_property(gone, "rotation", PI / 2.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_interval(1.2)
				tw.tween_property(gone, "modulate:a", 0.0, 1.0)
				tw.tween_callback(gone.queue_free)
			else:
				gone.queue_free()


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
	for o in _orders:
		o["t"] = float(o["t"]) + delta
	_orders = _orders.filter(func(o: Dictionary) -> bool: return float(o["t"]) < (2.2 if String(o["text"]) != "" else 0.6))
	_sync_merchant(delta)
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
	_sync_boat()
	_update_light()
	_water.update_water(delta, _night_k)
	_flora.update_flora(delta, _night_k)
	_fx.update_fx(delta, sim, _night_k)
	_defense.update_defense(delta, _night_k, _anim_t)
	if _zone_level != sim.tower or _grid_drawn != build_grid:
		_zone_level = sim.tower
		_grid_drawn = build_grid
		_zone.queue_redraw()
	_overlay.queue_redraw()


## O bote só aparece encostado no píer quando tem gente esperando para entrar (ambientação: barcos no
## mapa são naufrágios; o único que navega é esse).
func _sync_boat() -> void:
	var gate := sim._first("gate")
	_boat.visible = not gate.is_empty() and not sim.gate_group.is_empty()
	if _boat.visible:
		var fp := sim._fp("gate")
		var base := Vector2(Vector2i(gate["cell"]).x + fp.x, Vector2i(gate["cell"]).y + fp.y) * TILE
		_boat.position = (base + Vector2(1, 2 + sin(_anim_t * 1.6))).round()


## Cor do dia pela hora do relógio: dia claro e quente, fim de tarde dourado, noite bem escura e azul
## (aí as luzes quentes da fogueira e das janelas se destacam). Acima de 1 clareia o chão.
func _update_light() -> void:
	# Pela hora que o relógio mostra (dia 6–18, noite 18–6): 16h ainda é dia claro.
	var hr := sim.display_hour()
	var night := Color(0.09, 0.10, 0.22)
	var day := Color(1.0, 1.0, 1.0)   # a paleta da ilha já é clara: de dia fica como foi desenhada
	var keys := [
		[0.0, night], [5.0, night], [5.6, Color(0.62, 0.55, 0.74)],
		[6.3, day], [16.6, day], [17.4, Color(1.05, 0.86, 0.72)],
		[18.0, Color(0.48, 0.38, 0.58)], [18.6, night], [24.0, night]]
	var col: Color = keys[0][1]
	for i in keys.size() - 1:
		var a: float = keys[i][0]
		var z: float = keys[i + 1][0]
		if hr >= a and hr <= z:
			col = (keys[i][1] as Color).lerp(keys[i + 1][1], (hr - a) / maxf(0.001, z - a))
			break
	_modulate.color = col
	_night_k = clampf(1.0 - (minf(col.v, 1.0) - 0.36) / 0.6, 0.0, 1.0)
	var pf := sim.power_frac()
	for e in _lights:
		var lo: Variant = e["light"]   # sem tipo: o prédio pode ter sido refeito e a luz liberada
		if not is_instance_valid(lo):
			continue
		var l := lo as PointLight2D
		var k := _night_k   # de dia nenhuma luz: a paleta da ilha lava fácil
		var ph: float = e["ph"]
		var m := 0.92 + 0.08 * sin(_anim_t * 11.0 + ph) * sin(_anim_t * 3.7 + ph)
		if bool(e["fire"]):
			m = 0.8 + 0.2 * sin(_anim_t * 13.0 + ph) * sin(_anim_t * 5.3 + ph * 2.0)
		elif bool(e["electric"]):
			m = pf   # sem energia, apaga
		l.energy = float(e["base"]) * 1.4 * k * m   # paleta clara: luz forte estoura
		l.visible = l.energy > 0.01   # de dia a luz apagada nem entra no desenho
	_lights = _lights.filter(func(e: Dictionary) -> bool: return is_instance_valid(e["light"]))
	# Janelas acendem ao anoitecer e apagam de manhã.
	var lit_on := _night_k > 0.45
	for id in _bnodes:
		var n: Dictionary = _bnodes[id]
		var want: Texture2D = n["tex_lit"] if lit_on and (not bool(n.get("electric", false)) or pf > 0.0) else n["tex_dia"]
		var sp: Sprite2D = n["sprite"]
		if want != null and sp.texture != want:
			sp.texture = want


## Área da vila: fora do alcance da torre o chão fica mais escuro, e a borda leva uma linha tracejada.
func _draw_zone() -> void:
	var shade := Color(0.16, 0.12, 0.24, 0.26)
	var edge := Color(0.95, 0.85, 0.6, 0.45)
	if build_grid:
		# Grade do modo construção: linha fina em cada casa da área (como a base do Clash).
		var gc := Color(1.0, 0.97, 0.88, 0.16)
		for y in sim.h:
			for x in sim.w:
				var gcell := Vector2i(x, y)
				if sim.in_zone(gcell) and sim.terrain_at(gcell) != VilaSim.T_WATER:
					var gp := Vector2(gcell) * TILE
					_zone.draw_line(gp + Vector2(0.5, 0.5), gp + Vector2(TILE - 0.5, 0.5), gc, 1.0)
					_zone.draw_line(gp + Vector2(0.5, 0.5), gp + Vector2(0.5, TILE - 0.5), gc, 1.0)
	for y in sim.h:
		for x in sim.w:
			var c := Vector2i(x, y)
			var p := Vector2(c) * TILE
			if sim.terrain_at(c) == VilaSim.T_WATER:
				continue
			if not sim.in_zone(c):
				_zone.draw_rect(Rect2(p, Vector2(TILE, TILE)), shade)
				continue
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if sim.in_zone(c + d) or sim.terrain_at(c + d) == VilaSim.T_WATER:
					continue
				var a := p + Vector2(maxi(d.x, 0), maxi(d.y, 0)) * TILE
				var along := Vector2(absi(d.y), absi(d.x))
				for k in 4:
					_zone.draw_line(a + along * (k * 4 + 0.5), a + along * (k * 4 + 2.5), edge, 1.0)


var _timer_font: Font


func _draw_orders() -> void:
	if _timer_font == null:
		_timer_font = load("res://assets/fonts/DotGothic16-Regular.ttf")
	for o in _orders:
		var t: float = o["t"]
		var col := Color(0.55, 0.95, 0.7) if bool(o["ok"]) else Color(1.0, 0.45, 0.4)
		if t < 0.6:
			var k := t / 0.6
			_overlay.draw_arc(o["pos"], 2.0 + 6.0 * k, 0.0, TAU, 16, Color(col, 1.0 - k), 1.0)
		var txt := String(o["text"])
		if txt != "":
			var a := clampf((2.2 - t) / 0.4, 0.0, 1.0)
			var wdt := _timer_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			var at := (Vector2(o["pos"]) + Vector2(6, -10)).round()
			_overlay.draw_rect(Rect2(at + Vector2(0, -7), Vector2(wdt + 4, 10)), Color(0.05, 0.04, 0.06, 0.85 * a))
			_overlay.draw_string(_timer_font, at + Vector2(2, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(col, a))


## Tempo restante (contagem regressiva, 2:35) logo à direita da barra. `left_mid` é o ponto do meio da
## borda esquerda do texto. No zoom de longe o texto cresce para continuar legível.
func _timer_text(left_mid: Vector2, sec: float, col: Color) -> void:
	if sec < 0.0:
		return
	var cam := get_viewport().get_camera_2d()
	var k := 1.0 / cam.zoom.x if cam != null and cam.zoom.x < 0.99 else 1.0
	var txt := VilaHud.fmt_clock(sec)
	var wdt := _tiny_width(txt)
	_overlay.draw_set_transform(left_mid.round(), 0.0, Vector2(k, k))
	_overlay.draw_rect(Rect2(Vector2(0, -4), Vector2(wdt + 2, 7)), Color(0.05, 0.04, 0.06, 0.8))
	_tiny_text(Vector2(1, -3), txt, col)
	_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Algarismos de 3x5 px desenhados à mão: o relógio das obras fica pequeno sem borrar (a fonte de 8 px
## era grande demais para ficar em cima de cada obra e de cada pessoa).
const TINY := {
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "011", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
	":": ["0", "1", "0", "1", "0"],
	"+": ["000", "010", "111", "010", "000"],
	"/": ["001", "001", "010", "100", "100"],
}


func _tiny_width(txt: String) -> float:
	var w := 0.0
	for ch in txt:
		w += float(String(TINY.get(ch, ["000"])[0]).length() + 1)
	return maxf(0.0, w - 1.0)


func _tiny_text(at: Vector2, txt: String, col: Color) -> void:
	var x := at.x
	for ch in txt:
		var rows: Array = TINY.get(ch, [])
		if rows.is_empty():
			x += 4.0
			continue
		for y in rows.size():
			var r := String(rows[y])
			for i in r.length():
				if r[i] == "1":
					_overlay.draw_rect(Rect2(Vector2(x + i, at.y + y), Vector2.ONE), col)
		x += float(String(rows[0]).length() + 1)


func _draw_overlay() -> void:
	_draw_orders()
	var sp := sim.person(selected) if selected >= 0 else {}
	if not sp.is_empty():
		var feet := _person_world(sp) + Vector2(0, 2)
		_overlay.draw_set_transform(feet, 0.0, Vector2(1.0, 0.5))
		_overlay.draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, Color(0.55, 0.95, 0.7, 0.75 + 0.25 * sin(_anim_t * 5.0)), 1.5)
		_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Recurso clicado na barra de cima: contorno piscando nos prédios que produzem e em quem está nele.
	if hl_res != "":
		var hc := Color(1.0, 0.85, 0.4, 0.55 + 0.45 * sin(_anim_t * 6.0))
		for b in sim.buildings:
			var bd := sim.def(String(b["type"]))
			if String(bd.get("res", "")) == hl_res or (hl_res == "energia" and bd.has("power_out")):
				var fp := sim._fp(String(b["type"]))
				_overlay.draw_rect(Rect2(Vector2(Vector2i(b["cell"])) * TILE - Vector2(1, 1), Vector2(fp) * TILE + Vector2(2, 2)), hc, false, 1.0)
			elif hl_res == "energia" and bd.has("power_use"):
				# Energia: quem gasta fica contornado em azul (o que o gerador liga).
				var fpu := sim._fp(String(b["type"]))
				_overlay.draw_rect(Rect2(Vector2(Vector2i(b["cell"])) * TILE - Vector2(1, 1), Vector2(fpu) * TILE + Vector2(2, 2)), Color(0.55, 0.85, 1.0, hc.a), false, 1.0)
		for p in sim.people:
			if String(p["job"].get("res", "")) == hl_res:
				_overlay.draw_arc(_person_world(p) + Vector2(0, -5), 7.0, 0.0, TAU, 16, hc, 1.0)
	# De noite, em cima de cada moradia: cama e quantos já estão dormindo nela / quantas camas tem.
	if sim.is_night() and not sim.work_tonight:
		var bic := tex("icons")
		for b in sim.buildings:
			if String(b["type"]) != "moradia" or String(b["state"]) == "site":
				continue
			var rs: Array = sim.residents(b)
			var inside := 0
			for p in rs:
				if p["asleep"]:
					inside += 1
			var txt := "%d/%d" % [inside, sim._beds_of(b)]
			var fpm := sim._fp("moradia")
			var wdt := 9.0 + _tiny_width(txt)
			var n: Dictionary = _bnodes.get(int(b["id"]), {})
			var top_y := -float(fpm.y * TILE)
			if not n.is_empty() and (n["sprite"] as Sprite2D).texture != null:
				top_y = -float((n["sprite"] as Sprite2D).texture.get_height())
			var at := (Vector2(Vector2i(b["cell"]).x * TILE + fpm.x * TILE / 2.0 - wdt / 2.0, (Vector2i(b["cell"]).y + fpm.y) * TILE + top_y - 9)).round()
			_overlay.draw_rect(Rect2(at + Vector2(-1, -1), Vector2(wdt + 2, 10)), Color(0.26, 0.2, 0.33, 0.85))
			if bic != null:
				_overlay.draw_texture_rect_region(bic, Rect2(at, Vector2(8, 8)), Rect2(5 * 8, 0, 8, 8))
			_tiny_text(at + Vector2(9, 2), txt, CREME if inside < rs.size() or rs.is_empty() else Color8(201, 171, 93))
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
		var bt := tex(_btex_name({"type": ghost_type, "level": ghost_level, "state": "built"}))
		for dy in fp2.y:
			for dx in fp2.x:
				var gc := ghost_cell + Vector2i(dx, dy)
				var t := t_ok if sim.cell_ok(gc, ghost_type) else t_bad
				if t != null:
					_overlay.draw_texture(t, Vector2(gc) * TILE)
		if bt != null:
			var bottom := Vector2(ghost_cell.x * TILE, (ghost_cell.y + fp2.y) * TILE)
			var src := Rect2(0, 0, bt.get_width() / (4 if ghost_type == "fogueira" else 1), bt.get_height())
			var gx := roundi((fp2.x * TILE - src.size.x) / 2.0)
			_overlay.draw_texture_rect_region(bt, Rect2(bottom + Vector2(gx, -src.size.y), src.size), src, Color(1, 1, 1, 0.6))
	_draw_defense_hints()
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
		if not bh.is_empty() and _bnodes.has(int(bh["id"])):
			var bn: Dictionary = _bnodes[int(bh["id"])]
			var bs: Sprite2D = bn["sprite"] if (bn["sprite"] as Sprite2D).visible else bn["overlay"]
			_draw_outline(bs)
		elif _terrain_nodes.has(hover_cell):
			_draw_outline(_terrain_nodes[hover_cell])
			_draw_yield(hover_cell)
		elif sel != null:
			_overlay.draw_texture(sel, Vector2(hover_cell) * TILE, Color(1, 1, 1, 0.55))


## Destaque do hover no estilo da ilha: 1 px creme em volta do desenho (não da pegada).
var _outlines: Dictionary = {}   # "textura|quadro" -> PackedVector2Array dos pixels de fora


func _draw_outline(spr: Sprite2D) -> void:
	if spr == null or spr.texture == null:
		return
	var key := "%d|%d" % [spr.texture.get_instance_id(), spr.frame]
	if not _outlines.has(key):
		var img := spr.texture.get_image()
		if img.is_compressed():
			img.decompress()
		var fw := img.get_width() / spr.hframes
		var fh := img.get_height() / spr.vframes
		var ox := (spr.frame % spr.hframes) * fw
		var oy := (spr.frame / spr.hframes) * fh
		var solid := func(x: int, y: int) -> bool:
			return x >= 0 and y >= 0 and x < fw and y < fh and img.get_pixel(ox + x, oy + y).a > 0.5
		var pts := PackedVector2Array()
		for y in range(-1, fh + 1):
			for x in range(-1, fw + 1):
				if solid.call(x, y):
					continue
				if solid.call(x + 1, y) or solid.call(x - 1, y) or solid.call(x, y + 1) or solid.call(x, y - 1):
					pts.append(Vector2(x, y))
		_outlines[key] = pts
	var off := spr.offset
	if spr.centered:
		off -= Vector2(spr.texture.get_width() / spr.hframes, spr.texture.get_height() / spr.vframes) / 2.0
	var at := _overlay.to_local(spr.to_global(off))
	for q: Vector2 in _outlines[key]:
		_overlay.draw_rect(Rect2(at + q, Vector2.ONE), CREME)


## Em cima da árvore ou do entulho debaixo do mouse: ícone do recurso e quanto rende (madeira +3,
## sucata +8), para saber sem abrir o cartão.
func _draw_yield(c: Vector2i) -> void:
	var k := sim.terrain_at(c)
	var res := ""
	var n := 0
	if k == VilaSim.T_TREE:
		res = "madeira"
		n = int(sim.bal["forage"]["madeira"]["yield"])
	elif k == VilaSim.T_RUBBLE:
		res = "sucata"
		n = int(sim.rubble.get(c, 0))
	if res == "" or n <= 0:
		return
	var icons := tex("icons")
	var txt := "+%d" % n
	var wdt := 9.0 + _tiny_width(txt)
	var spr: Sprite2D = _terrain_nodes[c]
	var top := _overlay.to_local(spr.to_global(spr.offset)).y
	var at := Vector2(c.x * TILE + TILE / 2.0 - wdt / 2.0, top - 10.0).round()
	# Perto da borda de cima a barra de recursos cobriria: vai para baixo da célula.
	var bar_y := (_overlay.get_canvas_transform().affine_inverse() * Vector2(0, 16)).y
	if at.y - 1.0 < bar_y:
		at.y = roundf((c.y + 1) * TILE + 2.0)
	_overlay.draw_rect(Rect2(at + Vector2(-1, -1), Vector2(wdt + 2, 10)), Color(0.26, 0.2, 0.33, 0.9))
	if icons != null:
		_overlay.draw_texture_rect_region(icons, Rect2(at, Vector2(8, 8)), Rect2(_res_icon(res) * 8, 0, 8, 8))
	_tiny_text(at + Vector2(9, 2), txt, CREME)


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


# ================================================================ mercador (vem de barco)
## O mascate chega de barco: o barco entra pelo mar até o píer, ele desce e anda até a praça, onde
## monta a banca. Quando vai embora faz o caminho de volta e o barco some no mar. Só desenho: para a
## simulação ele já está na praça desde que chegou (dá para clicar nele no caminho também).
const M_SAIL_S := 5.0           # barco entrando ou saindo
const M_WALK_TPS := 2.6         # passo do mascate (células por segundo)
var _m_state := ""              # "", sail_in, walk_in, here, walk_out, sail_out
var _m_t := 0.0
var _m_path: PackedVector2Array = PackedVector2Array()
var _m_seen := false            # primeiro quadro: se já estava aqui (jogo carregado), aparece pronto


func _m_dock() -> Vector2:
	var g := sim._first("gate")
	if g.is_empty():
		return Vector2.ZERO
	var fp := sim._fp("gate")
	return Vector2(Vector2i(g["cell"]).x * TILE - 30, (Vector2i(g["cell"]).y + fp.y) * TILE - 10)


func _m_stand() -> Vector2:
	var pr := sim._first("praca")
	return Vector2(Vector2i(pr["cell"])) * TILE + Vector2(30, 40)


func _m_route() -> PackedVector2Array:
	var g := sim._first("gate")
	var pr := sim._first("praca")
	var out := PackedVector2Array()
	if g.is_empty() or pr.is_empty():
		return out
	out.append(_m_dock() + Vector2(26, 20))   # desce do barco no píer
	out.append(Vector2(Vector2i(g["cell"])) * TILE + Vector2(16, 20))
	for c in sim._path(Vector2(sim._door(g)), sim._door(pr)):
		out.append(c * TILE + Vector2(8, 12))
	out.append(_m_stand())
	return out


func _m_make() -> void:
	if not _merchant_nodes.is_empty():
		return
	var stall := Sprite2D.new()
	stall.texture = tex("banca")
	stall.centered = false
	stall.offset = Vector2(0, -28)
	stall.visible = false
	_objects.add_child(stall)
	var man := Sprite2D.new()
	man.texture = tex("merchant")
	man.hframes = 5
	man.vframes = 3
	man.offset = Vector2(0, -7)
	man.visible = false
	_objects.add_child(man)
	var boat := Sprite2D.new()
	boat.texture = tex("barco_mascate")
	boat.hframes = 2
	boat.centered = false
	boat.z_index = -5
	boat.visible = false
	add_child(boat)
	_merchant_nodes = [stall, man, boat]


func _m_clear() -> void:
	for n in _merchant_nodes:
		(n as Node).queue_free()
	_merchant_nodes = []
	_m_state = ""


func _sync_merchant(delta: float) -> void:
	var here := sim.merchant_here() and not sim._first("praca").is_empty()
	if not _m_seen:
		_m_seen = true
		if here:
			_m_make()
			_m_state = "here"
	if here and _m_state in ["", "walk_out", "sail_out"]:
		_m_make()
		_m_state = "sail_in" if _m_state == "" else "walk_in"
		_m_t = 0.0
		_m_path = _m_route()
	elif not here and _m_state in ["sail_in", "walk_in", "here"]:
		_m_state = "walk_out" if _m_state != "sail_in" else "sail_out"
		_m_t = 0.0
		_m_path = _m_route()
		_m_path.reverse()
	if _m_state == "":
		return
	_m_t += delta
	var stall: Sprite2D = _merchant_nodes[0]
	var man: Sprite2D = _merchant_nodes[1]
	var boat: Sprite2D = _merchant_nodes[2]
	var dock := _m_dock()
	var away := dock + Vector2(-40, 150)
	boat.frame = int(_anim_t * 2.0) % 2
	var bob := Vector2(0, roundf(sin(_anim_t * 1.4)))
	match _m_state:
		"sail_in", "sail_out":
			var k := clampf(_m_t / M_SAIL_S, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			var from := away if _m_state == "sail_in" else dock
			var to := dock if _m_state == "sail_in" else away
			boat.visible = true
			boat.position = from.lerp(to, k).round() + bob
			man.visible = false
			stall.visible = false
			if _m_t >= M_SAIL_S:
				if _m_state == "sail_in":
					_m_state = "walk_in"
					_m_t = 0.0
				else:
					_m_clear()
					return
		"walk_in", "walk_out":
			boat.visible = true
			boat.position = dock.round() + bob
			stall.visible = _m_state == "walk_out"
			man.visible = true
			var done := _m_walk(man, delta)
			if done:
				if _m_state == "walk_in":
					_m_state = "here"
				else:
					_m_state = "sail_out"
				_m_t = 0.0
		"here":
			boat.visible = true
			boat.position = dock.round() + bob
			stall.visible = true
			man.visible = true
			man.position = _m_stand()
			man.frame = 0
	var base := Vector2(Vector2i(sim._first("praca").get("cell", Vector2i.ZERO))) * TILE
	stall.position = base + Vector2(9, 12 + 28)


## Anda o mascate pelo caminho guardado; devolve true quando chegou ao fim.
func _m_walk(man: Sprite2D, delta: float) -> bool:
	if _m_path.is_empty():
		return true
	var pos := man.position if man.position != Vector2.ZERO else _m_path[0]
	var dist := M_WALK_TPS * TILE * delta
	var dir := Vector2.DOWN
	while dist > 0.0 and not _m_path.is_empty():
		var tgt := _m_path[0]
		var d := pos.distance_to(tgt)
		if d <= dist:
			if d > 0.01:
				dir = (tgt - pos) / d
			pos = tgt
			dist -= d
			_m_path.remove_at(0)
		else:
			dir = (tgt - pos) / d
			pos += dir * dist
			dist = 0.0
	man.position = pos
	var row := 2 if absf(dir.x) > absf(dir.y) else (1 if dir.y < 0.0 else 0)
	man.flip_h = row == 2 and dir.x < 0.0
	man.frame = row * 5 + 1 + int(_anim_t * 8.0) % 4
	return _m_path.is_empty()


## Onde o mascate está (para clicar nele e abrir o cartão do mercador).
func merchant_rect() -> Rect2:
	if _merchant_nodes.size() < 2:
		return Rect2()
	var man: Sprite2D = _merchant_nodes[1]
	return Rect2(man.position + Vector2(-8, -18), Vector2(16, 20))


# ================================================================ alcance e chegada dos zumbis
const RANGE_COL := Color(1.0, 0.85, 0.45)
const ZOMBIE_COL := Color(0.95, 0.35, 0.3)


## Círculo de alcance (raio em casas) em volta do meio de um prédio de pegada fp posto em cell.
func _draw_range(cell: Vector2i, fp: Vector2i, r: float, col: Color, fill: float, dashed: bool = false) -> void:
	if r <= 0.0:
		return
	var c := (Vector2(cell) + Vector2(fp) / 2.0) * TILE
	var rr := r * TILE
	if fill > 0.0:
		_overlay.draw_circle(c, rr, Color(col, fill))
	if dashed:
		var n := 36
		for i in n:
			if i % 2 == 0:
				_overlay.draw_arc(c, rr, TAU * i / n, TAU * (i + 1) / n, 3, col, 1.0)
	else:
		_overlay.draw_arc(c, rr, 0.0, TAU, 64, col, 1.0)


func _draw_defense_hints() -> void:
	var df := sim.defense
	if df == null:
		return
	var placing_def := ghost_type != "" and df.range_of(ghost_type, ghost_level) > 0.0
	var sb := sim.by_id(sel_building) if sel_building >= 0 else {}
	var sel_def := not sb.is_empty() and df.range_of(String(sb["type"]), int(sb["level"])) > 0.0
	# Modo construção ou posicionando defesa: alcance de todas as defesas que já existem (fraco).
	if build_grid:
		for b in sim.buildings:
			var tp := String(b["type"])
			var rb := df.range_of(tp, int(b["level"]))
			if rb > 0.0 and int(b["id"]) != sel_building:
				_draw_range(Vector2i(b["cell"]), sim._fp(tp), rb, Color(RANGE_COL, 0.45), 0.05)
	if placing_def:
		_draw_range(ghost_cell, sim._fp(ghost_type), df.range_of(ghost_type, ghost_level), RANGE_COL, 0.14)
	if sel_def:
		var tp2 := String(sb["type"])
		var lv := int(sb["level"])
		var fp := sim._fp(tp2)
		_draw_range(Vector2i(sb["cell"]), fp, df.range_of(tp2, lv), RANGE_COL, 0.14)
		var nlv: Array = sim.def(tp2).get("levels", [])
		if lv < nlv.size():   # próximo nível: tracejado, para ver quanto a melhoria aumenta
			_draw_range(Vector2i(sb["cell"]), fp, df.range_of(tp2, lv + 1), Color(RANGE_COL, 0.8), 0.0, true)
	# Por onde os zumbis chegam: no dia da noite com zumbi, no modo construção, ao mexer em defesa
	# e no tutorial. Some quando eles já estão no mapa.
	var today := df.raid_day() == sim.day_number()
	var show := show_arrivals or build_grid or placing_def or sel_def \
			or (today and (not sim.is_night() or not df.pending.is_empty()))
	if not show or (sim.is_night() and df.pending.is_empty() and not df.zombies.is_empty()):
		return
	var pulse := 0.6 + 0.4 * sin(_anim_t * 4.0)
	for a in df.arrivals():
		var path: PackedVector2Array = a["path"]
		var from := Vector2(Vector2i(a["cell"])) * TILE + Vector2(8, 8)
		# trilha pontilhada andando na direção da vila
		var pts := PackedVector2Array([from])
		for q in path:
			pts.append(q * TILE + Vector2(8, 8))
		var off := fmod(_anim_t * 10.0, 8.0)
		var walked := 0.0
		for i in range(1, pts.size()):
			var a0 := pts[i - 1]
			var a1 := pts[i]
			var seg := a0.distance_to(a1)
			var d := fmod(8.0 - fmod(walked - off, 8.0), 8.0)
			while d < seg:
				var pp := a0.lerp(a1, d / seg)
				_overlay.draw_rect(Rect2(pp.round() - Vector2(2, 2), Vector2(4, 4)), Color(0.15, 0.05, 0.08, 0.6))
				_overlay.draw_rect(Rect2(pp.round() - Vector2(1, 1), Vector2(2, 2)), ZOMBIE_COL)
				d += 8.0
			walked += seg
		_overlay.draw_circle(from, 6.0, Color(ZOMBIE_COL, 0.25 * pulse))
		_overlay.draw_arc(from, 6.0, 0.0, TAU, 20, Color(ZOMBIE_COL, pulse), 1.0)
		var ic := tex("icons")
		if ic != null:
			_overlay.draw_texture_rect_region(ic, Rect2(from - Vector2(4, 16), Vector2(8, 8)), Rect2(23 * 8, 0, 8, 8))
		# Fora da tela: uma seta na beira apontando para lá.
		var xf := _overlay.get_global_transform_with_canvas()
		var inv := xf.affine_inverse()
		var vs := _overlay.get_viewport_rect().size
		var view := Rect2(inv * Vector2(0, 20), inv.basis_xform(vs - Vector2(0, 40)))
		if not view.has_point(from):
			var mid := view.get_center()
			var inner := view.grow(-10.0 / maxf(0.01, xf.get_scale().x))
			var dir := (from - mid).normalized()
			var k := 1e9
			if absf(dir.x) > 1e-4:
				k = minf(k, (inner.size.x / 2.0) / absf(dir.x))
			if absf(dir.y) > 1e-4:
				k = minf(k, (inner.size.y / 2.0) / absf(dir.y))
			var at := mid + dir * k
			var sc := 1.0 / maxf(0.01, xf.get_scale().x)
			var tip := at + dir * 8.0 * sc
			var side := Vector2(-dir.y, dir.x) * 5.0 * sc
			_overlay.draw_colored_polygon(PackedVector2Array([tip, at + side, at - side]), Color(ZOMBIE_COL, pulse))
			if ic != null:
				_overlay.draw_set_transform(at - dir * 6.0 * sc, 0.0, Vector2(sc, sc))
				_overlay.draw_texture_rect_region(ic, Rect2(Vector2(-4, -4), Vector2(8, 8)), Rect2(23 * 8, 0, 8, 8))
				_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
