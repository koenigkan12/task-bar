class_name BunkerView
extends Node2D
## Corte do bunker (faixa de 88 px). Só lê o estado do Game e reage aos sinais dele; nada aqui
## mexe na economia. Coordenadas lógicas da CONTRATOS seção 3; a origem do nó é o canto superior
## esquerdo da faixa (quem instancia posiciona em y = altura_da_janela - 88).
##
## Para a UI:
##   get_object_at(pos) -> Dictionary  {kind: "hatch"|"radio"|"box"|"instance"|"antenna"|"fixed"|"room",
##                                      id, item, room, col}  ({} = nada)
##   room_col_at(pos) -> Vector2i      sala (1..3) e coluna sob o ponto, ou (-1, -1)
##   column_rect(room, col, cols) -> Rect2   retângulo de um bloco (para o fantasma de posicionamento)
##   strip_width() -> int              largura lógica usada (≥ W(n))
##   set_view_width(w)                 largura da janela (terra maciça preenche o resto)
##   sinais object_clicked(instance_id), radio_clicked, box_clicked, hatch_clicked,
##          arrival_cut (a tela está preta e o Game já recebeu finish_arrival), arrival_scene_finished

signal object_clicked(instance_id: int)
## Uma ordem do jogador foi cumprida pelo homem: kind "hammer"|"tend"|"box", result = resposta do Game.
signal order_done(kind: String, result: Dictionary)
signal radio_clicked()
signal box_clicked()
signal hatch_clicked()
signal arrival_cut()
signal arrival_scene_finished()

const SYNC_SEC := 0.25
const VISIT_OPEN_SEC := 1.6
const GOAL_ICONS := {
	"plantio": "icon_crop_batata", "agua": "icon_tempo", "energia": "icon_energia",
	"transporte": "icon_cesto", "decor": "icon_historia", "casa": "icon_home", "escavacao": "icon_espaco",
}

## Objeto do Game (autoload por padrão). Defina antes de entrar na árvore, ou use set_game().
var game: Object
var link: GameLink
var view_width: int = 0
## Velocidade da cena do final (testes podem acelerar).
var cinematic_speed: float = 1.0

var man: BunkerMan
## Ordens dadas por clique (o homem vai até o alvo e faz): {kind: "hammer"|"tend"|"box", id, taken}.
var orders: Array[Dictionary] = []
const MAX_ORDERS := 4
var attention := BunkerAttention.new()

var _sky: BunkerSky
var _terrain: BunkerTerrain
var _surface: Node2D
var _objects: Node2D
var _fx: Node2D
var _tip: PlotTip
var _shade: BunkerLight
var _lights: Node2D
var _cone: BunkerLight
var _overlay: Node2D
var _fade: Node2D
var _fade_alpha: float = 0.0

var _antenna: ArtSprite
var _hatch: ArtSprite
var _scrap: ArtSprite
var _radio_glow: ArtSprite
var _lamps: Array[ArtSprite] = []
var _glows: Array[BunkerLight] = []
var _fixed: Dictionary = {}        # fixed_id -> BunkerObject
var _inst: Dictionary = {}         # instance_id -> BunkerObject
var _caneca: ArtSprite

var _rooms: int = 1
var _sync_t: float = 0.0
var _hatch_open_t: float = 0.0
var _pulse_t: float = 0.0
var _amb_t: float = 6.0
var _arrival_running: bool = false
var _arrival_light: bool = false
var _goal_cache: String = ""
var _goal_icon: String = "icon_estrela"
var _reduce_flicker: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if game == null:
		game = get_node_or_null("/root/Game")
	link = GameLink.new(game)
	BunkerArt.ensure()
	_build_layers()
	_connect_game()
	if view_width <= 0:
		view_width = int(get_viewport_rect().size.x)
	get_viewport().size_changed.connect(_on_viewport_resized)
	full_refresh()


func set_game(g: Object) -> void:
	game = g
	if is_inside_tree():
		link = GameLink.new(g)
		man.link = link
		_connect_game()
		full_refresh()


func set_view_width(w: int) -> void:
	view_width = w
	_sync()


func strip_width() -> int:
	return maxi(view_width, BunkerGeo.strip_width(_rooms + (1 if _dig_job().size() > 0 else 0)))


func _on_viewport_resized() -> void:
	var w := int(get_viewport_rect().size.x)
	if w > view_width:
		set_view_width(w)


# ---------------- montagem ----------------

func _build_layers() -> void:
	_sky = BunkerSky.new()
	add_child(_sky)
	_terrain = BunkerTerrain.new()
	add_child(_terrain)
	_surface = Node2D.new()
	add_child(_surface)
	_antenna = ArtSprite.new("antenna_1")
	_antenna.position = Vector2(BunkerGeo.ANTENNA_X, BunkerGeo.GRASS_Y)
	_surface.add_child(_antenna)
	_hatch = ArtSprite.new("hatch")
	_hatch.position = Vector2(BunkerGeo.HATCH_X, BunkerGeo.ROOM_Y)
	_surface.add_child(_hatch)
	_objects = Node2D.new()
	add_child(_objects)
	_scrap = ArtSprite.new("scrap_pile")
	_scrap.position = Vector2(BunkerGeo.col_x(1, 1) - 2, BunkerGeo.FEET_Y)
	_scrap.visible = false
	_objects.add_child(_scrap)
	man = BunkerMan.new()
	man.view = self
	man.link = link
	man.z_index = 3
	add_child(man)
	_fx = Node2D.new()
	_fx.z_index = 4
	add_child(_fx)
	_tip = PlotTip.new()
	_tip.view = self
	add_child(_tip)
	_shade = BunkerLight.new(BunkerLight.Kind.SHADE)
	_shade.z_index = 6
	add_child(_shade)
	_lights = Node2D.new()
	_lights.z_index = 7
	add_child(_lights)
	_cone = BunkerLight.new(BunkerLight.Kind.CONE)
	_lights.add_child(_cone)
	_overlay = Node2D.new()
	_overlay.z_index = 8
	add_child(_overlay)
	_radio_glow = ArtSprite.new("radio_glow")
	_radio_glow.visible = false
	_overlay.add_child(_radio_glow)
	_fade = Node2D.new()
	_fade.z_index = 20
	_fade.draw.connect(func() -> void:
		if _fade_alpha > 0.0:
			var c := BunkerGeo.pal("ink")
			c.a = _fade_alpha
			_fade.draw_rect(Rect2(0, 0, strip_width(), BunkerGeo.H), c))
	add_child(_fade)


func _connect_game() -> void:
	link.connect_signal("item_placed", func(_id: int) -> void: _sync())
	link.connect_signal("item_finished", _on_item_finished)
	link.connect_signal("item_removed", func(_id: int) -> void: _sync())
	link.connect_signal("room_dug", _on_room_dug)
	link.connect_signal("antenna_changed", func(_l: int) -> void: _sync())
	link.connect_signal("radio_line", _on_radio_line)
	link.connect_signal("visit_happened", _on_visit)
	link.connect_signal("plot_harvested", _on_plot_harvested)
	link.connect_signal("helped", _on_helped)
	link.connect_signal("box_state_changed", func(_f: float, _o: bool) -> void: _sync())
	link.connect_signal("state_changed", func() -> void: _sync_t = 0.0)
	link.connect_signal("arrival_started", play_arrival)
	link.connect_signal("arrival_finished", func() -> void: _sync())
	link.connect_signal("new_game_started", full_refresh)
	link.connect_signal("game_loaded", full_refresh)
	# volta de ausência (offline / suspensão): o catch-up não emite sinais finos, então relê tudo
	link.connect_signal("welcome_back", func(_s: Dictionary) -> void: full_refresh())


## Refaz tudo (novo jogo / carregado).
func full_refresh() -> void:
	for o: BunkerObject in _inst.values():
		o.queue_free()
	_inst.clear()
	for o: BunkerObject in _fixed.values():
		o.queue_free()
	_fixed.clear()
	_caneca = null
	man.interrupt()
	_sync(true)
	var bed: Variant = fixed_foot("bed")
	if link.is_awake():
		man.position.x = BunkerGeo.col_x(1, 7)
	elif bed != null:
		man.position.x = bed.x


# ---------------- sincronia com o estado ----------------

func _process(delta: float) -> void:
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = SYNC_SEC
		_sync()
	attention.tick(delta)
	_update_pulses(delta)
	_check_hover()
	if _hatch_open_t > 0.0:
		_hatch_open_t -= delta
		if _hatch_open_t <= 0.0 and not _arrival_light:
			_hatch.frame = 0
	_ambient_fx(delta)


func _dig_job() -> Dictionary:
	for j: Dictionary in link.active_jobs():
		if String(j.get("item", "")).begins_with("comodo"):
			return j
	return {}


func _sync(force: bool = false) -> void:
	if link == null:
		return
	_rooms = link.rooms()
	var dig := _dig_job()
	var w := strip_width()
	_terrain.setup(_rooms, w, _rooms + 1 if not dig.is_empty() else 0, float(dig.get("ratio", 0.0)))
	var tod := link.tod_hours()
	_sky.refresh(tod, w, force)
	_shade.width = w
	_sync_fixed()
	_sync_instances()
	_sync_surface()
	_sync_lamps()
	_sync_light(tod)
	attention.update_conditions({
		"radio": link.unread_count() > 0,
		"box": link.box_fill() > 1.0,
		"power": not link.power_ok(),
		"goal": link.goal_ready(),
	})
	_sync_goal_icon()
	_reduce_flicker = _read_reduce_flicker()
	_fade.queue_redraw()


func _sync_fixed() -> void:
	var seen := {}
	for r in range(1, _rooms + 1):
		for f: Dictionary in link.fixed_objects(r):
			var id := String(f.get("id", ""))
			if id == "ladder" or not BunkerArt.has(id):
				continue
			seen[id] = true
			var o: BunkerObject = _fixed.get(id)
			if o == null:
				o = BunkerObject.new(id)
				o.fixed_id = id
				_objects.add_child(o)
				_fixed[id] = o
			o.apply({"id": -1, "room": r, "col": int(f.get("col", 0)), "cols": int(f.get("cols", 1))})
	for id: String in _fixed.keys():
		if not seen.has(id):
			_fixed[id].queue_free()
			_fixed.erase(id)
	var box: BunkerObject = _fixed.get("hatch_box")
	if box != null and attention.current != "box":
		box.sprite.frame = _box_frame(link.box_fill())
	var radio: BunkerObject = _fixed.get("radio_table")
	if radio != null:
		var on := link.is_awake()
		radio.sprite.frame_list = [1, 2]
		radio.sprite.fps_override = 2.0
		radio.sprite.playing = on
		if not on:
			radio.sprite.frame = 0
		_radio_glow.position = radio.position
	_scrap.visible = link.sucata() > 0
	var s := link.sucata()
	_scrap.frame = 0 if s < 40 else (1 if s < 150 else 2)


static func _box_frame(fill: float) -> int:
	if fill > 1.0:
		return 3
	if fill > 0.5:
		return 2
	if fill > 0.01:
		return 1
	return 0


func _sync_instances() -> void:
	var seen := {}
	var by_inst := {}
	for p: Dictionary in link.plots():
		var k := int(p.get("instance", -1))
		if not by_inst.has(k):
			by_inst[k] = []
		by_inst[k].append(p)
	for d: Dictionary in link.instances():
		var it := String(d.get("item", ""))
		if not BunkerArt.has(it):
			continue   # lata, balde, segunda_caneca (overlay), escavação...
		var id := int(d.get("id", -1))
		seen[id] = true
		var o: BunkerObject = _inst.get(id)
		if o == null or o.item != it:
			if o != null:
				o.queue_free()
			o = BunkerObject.new(it)
			if BunkerObject.WALL_ITEMS.has(it):
				o.z_index = -1
			(_surface if BunkerObject.SURFACE_ITEMS.has(it) else _objects).add_child(o)
			_inst[id] = o
		o.apply(d)
		o.apply_plots(by_inst.get(id, []))
	for id: int in _inst.keys():
		if not seen.has(id):
			_inst[id].queue_free()
			_inst.erase(id)
	# caneca na mesinha: 1 caneca; 2 no epílogo (CONTRATOS 9)
	var desk := find_item("mesinha")
	if desk == null:
		if _caneca != null:
			_caneca.queue_free()
			_caneca = null
	else:
		if _caneca == null or _caneca.get_parent() != desk:
			_caneca = ArtSprite.new("caneca")
			_caneca.z_index = 1
			desk.add_child(_caneca)
			var pos: Array = BunkerArt.info("caneca").get("overlay_pos", [8, 0])
			_caneca.position = -BunkerArt.anchor("mesinha") + Vector2(float(pos[0]), float(pos[1])) + BunkerArt.anchor("caneca")
		_caneca.visible = not desk.building
		_caneca.frame = 1 if link.arrived() else 0


func _sync_surface() -> void:
	_antenna.art = "antenna_%d" % link.antenna()
	if _arrival_light:
		_hatch.frame = 1


func _sync_lamps() -> void:
	var pts := BunkerGeo.lamp_points(_rooms)
	while _lamps.size() < pts.size():
		var lamp := ArtSprite.new("lamp", 1)
		_overlay.add_child(lamp)
		_lamps.append(lamp)
		var g := BunkerLight.new(BunkerLight.Kind.GLOW)
		_lights.add_child(g)
		_glows.append(g)
	while _lamps.size() > pts.size():
		_lamps.pop_back().queue_free()
		_glows.pop_back().queue_free()
	for k in pts.size():
		_lamps[k].position = pts[k]
		_glows[k].position = pts[k] + Vector2(0, 2)


func _lamp_on() -> bool:
	return link.is_awake() or _arrival_running


static func daylight(tod: float) -> float:
	return smoothstep(5.5, 8.0, tod) * (1.0 - smoothstep(17.5, 20.0, tod))


func _sync_light(tod: float) -> void:
	var day := daylight(tod)
	var on := _lamp_on()
	# luz do relógio no poço: dia claro, crepúsculo quente, noite quase nada (luar)
	var c: Color
	if _arrival_light:
		c = BunkerGeo.pal("amber4")
		c.a = 1.0
	elif day > 0.02:
		c = BunkerGeo.pal("amber3").lerp(BunkerGeo.pal("amber4"), day)
		c.a = 0.15 + 0.75 * day
	else:
		c = BunkerGeo.pal("cloth2")
		c.a = 0.12
	_cone.wide = _arrival_light
	_cone.tint = c
	var s := lerpf(0.55, 1.0, day)
	_shade.surface_tint = Color(s, s, lerpf(0.72, 1.0, day))
	if on:
		var k := lerpf(0.9, 1.0, day)
		_shade.tint = Color(k, k, k)
	else:
		_shade.tint = Color(0.42, 0.42, 0.56)
	for i in _lamps.size():
		var lamp_frame := 1 if on else 0
		if attention.current != "power":
			_lamps[i].frame = lamp_frame
		# a estufa (sala 2) tem luz de cultivo, mais esverdeada
		var g := BunkerGeo.pal("leaf4") if (i == 1 and _rooms >= 2) else BunkerGeo.pal("amber2")
		g.a = (0.85 if _lamps[i].frame == 1 else (0.35 if _lamps[i].frame == 2 else 0.0)) if on else 0.0
		_glows[i].tint = g


func _sync_goal_icon() -> void:
	var goal := link.pinned_goal()
	if goal == _goal_cache:
		return
	_goal_cache = goal
	_goal_icon = "icon_estrela"
	if goal.begins_with("comodo"):
		_goal_icon = "icon_espaco"
	elif goal.begins_with("antena") or goal.begins_with("antenna"):
		_goal_icon = "icon_antena"
	else:
		for e: Dictionary in link.catalog():
			if String(e.get("item", "")) == goal:
				_goal_icon = GOAL_ICONS.get(String(e.get("line", "")), "icon_estrela")
				break


# ---------------- sinais de atenção ----------------

func _read_reduce_flicker() -> bool:
	var s := get_node_or_null("/root/Settings")
	if s != null and s.has_method("get_value"):
		return bool(s.call("get_value", "reduce_flicker", false))
	return false


func _update_pulses(delta: float) -> void:
	_pulse_t += delta
	var period := 1.0 if _reduce_flicker else 0.5
	var phase := int(_pulse_t / period) % 2 == 0
	var cur := attention.current
	_radio_glow.visible = cur == "radio"
	if cur == "radio":
		_radio_glow.frame = 0 if phase else 1
	var box: BunkerObject = _fixed.get("hatch_box")
	if box != null and cur == "box":
		box.sprite.frame = 3 if phase else 2
	if cur == "power" and _lamp_on():
		for i in _lamps.size():
			_lamps[i].frame = 1 if phase else 2
	if _arrival_running or man.anim == "man_sleep":
		man.set_bubble("")
	elif cur == "goal":
		if man._bubble_icon != _goal_icon or not man._bubble_bob:
			man.set_bubble(_goal_icon, true)
	elif link.hungry():
		if man._bubble_icon != "icon_cesto" or man._bubble_bob:
			man.set_bubble("icon_cesto", false)
	elif man._bubble_icon != "":
		man.set_bubble("")


## Retângulo do elemento que sinaliza o tipo k (para o hover).
func attention_rect(k: String) -> Rect2:
	match k:
		"radio":
			var r: BunkerObject = _fixed.get("radio_table")
			return r.bounds() if r != null else Rect2()
		"box":
			var b: BunkerObject = _fixed.get("hatch_box")
			return b.bounds() if b != null else Rect2()
		"power":
			var rr := Rect2()
			for l in _lamps:
				var lb := l.bounds().grow(4)
				rr = lb if rr.size == Vector2.ZERO else rr.merge(lb)
			return rr
		"goal":
			return man.bubble_rect().merge(man.body_rect())
	return Rect2()


func _check_hover() -> void:
	if attention.current == "":
		return
	var p := get_local_mouse_position()
	if attention_rect(attention.current).has_point(p):
		attention.hover(attention.current)


# ---------------- reações a eventos ----------------

func _on_item_finished(instance_id: int, _item_id: String) -> void:
	_sync()
	var o: BunkerObject = _inst.get(instance_id)
	if o != null:
		var b := o.bounds()
		spawn_fx("fx_spark", Vector2(b.get_center().x, b.position.y + 4))
		spawn_fx("fx_dust", Vector2(b.position.x + 2, BunkerGeo.FEET_Y))
		spawn_fx("fx_dust", Vector2(b.end.x - 2, BunkerGeo.FEET_Y))


func _on_room_dug(room: int) -> void:
	_sync()
	spawn_fx("fx_dust", Vector2(BunkerGeo.room_x0(room) + 8, BunkerGeo.FEET_Y))
	spawn_fx("fx_dust", Vector2(BunkerGeo.room_x0(room) + 40, BunkerGeo.FEET_Y))


func _on_radio_line(_line: Dictionary) -> void:
	_sync()
	attention.notify("radio")


func _on_visit(_info: Dictionary) -> void:
	_hatch.frame = 1
	_hatch_open_t = VISIT_OPEN_SEC
	var box: Variant = fixed_foot("hatch_box")
	if box != null:
		spawn_fx("fx_scrap_pop", box + Vector2(0, -14))
	spawn_fx("fx_dust", Vector2(BunkerGeo.HATCH_X + 16, BunkerGeo.ROOM_Y))
	_sync()


func _on_helped(instance_id: int) -> void:
	var o: BunkerObject = _inst.get(instance_id)
	if o != null:
		spawn_fx("fx_spark", o.bounds().get_center() + Vector2(0, -6))


func _on_plot_harvested(plot_id: int) -> void:
	for p: Dictionary in link.plots():
		if int(p.get("id", -1)) == plot_id:
			spawn_fx("fx_dust", plot_pos(p))
			_tip.pop(plot_pos(p))
			return


## Partícula de uma volta (ou `loops` voltas) de um fx_* do manifesto.
func spawn_fx(art: String, pos: Vector2, loops: int = 1) -> ArtSprite:
	if not BunkerArt.has(art):
		return null
	var s := ArtSprite.new(art)
	s.position = pos.round()
	s.loop = loops > 1
	_fx.add_child(s)
	s.play(art)
	if loops > 1:
		get_tree().create_timer(loops * BunkerArt.frames(art) / maxf(BunkerArt.fps(art), 1.0)).timeout.connect(s.queue_free)
	else:
		s.finished.connect(s.queue_free)
	return s


func build_fx(o: BunkerObject) -> void:
	if o != null and is_instance_valid(o):
		spawn_fx("fx_dust", Vector2(o.bounds().position.x + _rng.randf_range(0, o.bounds().size.x), BunkerGeo.FEET_Y), 3)


## Clique do jogador = ordem para o homem. kind "instance" (obra -> martelar, estrutura -> cuidar) ou "box".
## Devolve "" se aceitou; senão o motivo: asleep | full | off | none | empty | cooldown.
func give_order(kind: String, id: int = 0) -> String:
	if not link.is_awake() or link.is_night():
		return "asleep"
	if orders.size() >= MAX_ORDERS:
		return "full"
	var order: Dictionary = {"kind": kind, "id": id, "taken": false}
	if kind == "box":
		var why: String = String(link.q("help_box_check", "off"))
		if why != "ok":
			return why
		for o: Dictionary in orders:
			if String(o["kind"]) == "box":
				return "full"
	else:
		var obj: BunkerObject = _inst.get(id)
		if obj == null:
			return "none"
		if obj.building:
			if not bool(link.q("help_available", false)):
				return "off"
			order["kind"] = "hammer"
		else:
			if not bool(link.q("help_plots_available", false)):
				return "off"
			var has_plot := false
			for p: Dictionary in link.plots():
				if int(p.get("instance", -1)) == id:
					has_plot = true
			if not has_plot:
				return "none"
			order["kind"] = "tend"
	orders.append(order)
	man.order_added()
	return ""


func has_orders() -> bool:
	return not orders.is_empty()


## Próxima ordem ainda não assumida (marca como assumida), ou {}.
func next_order() -> Dictionary:
	for o: Dictionary in orders:
		if not bool(o["taken"]):
			o["taken"] = true
			return o
	return {}


## O homem desistiu no meio (ex.: mudou o modo): as ordens assumidas voltam para a fila.
func release_orders() -> void:
	for o: Dictionary in orders:
		o["taken"] = false


func clear_orders() -> void:
	orders.clear()


func drop_order(o: Dictionary) -> void:
	orders.erase(o)


## O homem chegou e fez: tira da fila e aplica a ajuda na Sim.
func finish_order(o: Dictionary) -> void:
	if not orders.has(o):
		return
	orders.erase(o)
	var res: Dictionary = {}
	if String(o["kind"]) == "box":
		res = link.q("help_box", {"ok": false, "reason": "off"}) as Dictionary
	else:
		res = link.q("help_instance", {"ok": false, "reason": "off"}, [int(o["id"])]) as Dictionary
	order_done.emit(String(o["kind"]), res)


## Onde pôr a marca da ordem (canto de cima do alvo), ou null.
func order_anchor(o: Dictionary) -> Variant:
	var r := Rect2()
	if String(o["kind"]) == "box":
		var box: BunkerObject = _fixed.get("hatch_box")
		if box == null:
			return null
		r = box.bounds()
	else:
		var obj: BunkerObject = _inst.get(int(o["id"]))
		if obj == null:
			return null
		r = obj.bounds()
	return Vector2(r.end.x - 3.0, r.position.y + 3.0)


func dig_fx() -> void:
	spawn_fx("fx_dust", Vector2(dig_spot_x() + 8, BunkerGeo.FEET_Y), 4)


func drop_fx() -> void:
	var box: Variant = fixed_foot("hatch_box")
	if box != null:
		spawn_fx("fx_dust", box)


func _ambient_fx(delta: float) -> void:
	_amb_t -= delta
	if _amb_t > 0.0:
		return
	_amb_t = _rng.randf_range(7.0, 14.0)
	# goteira na sala 2 (umidade) e vapor da caneca de manhã no epílogo
	if _rooms >= 2:
		spawn_fx("fx_drip", Vector2(BunkerGeo.col_x(2, 8) + 6, BunkerGeo.WALL_Y))
	var tod := link.tod_hours()
	if _caneca != null and _caneca.visible and link.arrived() and tod >= 6.0 and tod <= 10.0:
		spawn_fx("fx_steam", _caneca.get_parent().position + _caneca.position + Vector2(0, -6), 2)


# ---------------- consultas para o homem e para a UI ----------------

func fixed_foot(id: String) -> Variant:
	if id == "ladder":
		return BunkerGeo.block_foot(1, 0, 1)
	var o: BunkerObject = _fixed.get(id)
	return o.position if o != null else null


func object_by_id(instance_id: int) -> BunkerObject:
	return _inst.get(instance_id)


## Primeira instância pronta do item (ou em obra, se não houver pronta).
func find_item(item: String) -> BunkerObject:
	var fallback: BunkerObject = null
	for o: BunkerObject in _inst.values():
		if o.item == item:
			if not o.building:
				return o
			fallback = o
	return fallback


func is_arrival_running() -> bool:
	return _arrival_running


## A planta só aparece (barra, etiqueta) quando a estrutura está pronta.
func plot_shown(p: Dictionary) -> bool:
	var o: BunkerObject = _inst.get(int(p.get("instance", -1)))
	return o != null and not o.building


func plot_pos(p: Dictionary) -> Vector2:
	var o: BunkerObject = _inst.get(int(p.get("instance", -1)))
	if o == null:
		return man.position
	return o.plot_world_pos(int(p.get("index", 0)))


func dig_spot_x() -> float:
	var j := _dig_job()
	if not j.is_empty():
		var open := BunkerGeo.ROOM_W * float(j.get("ratio", 0.0))
		if open >= 16.0:
			return BunkerGeo.room_x0(_rooms + 1) + open - 10.0
	return BunkerGeo.room_x0(_rooms) + BunkerGeo.ROOM_W - 10.0


func walk_min_x() -> float:
	return BunkerGeo.col_x(1, 0) + 8.0


func walk_max_x() -> float:
	return BunkerGeo.room_x0(_rooms) + BunkerGeo.ROOM_W - 8.0


func room_col_at(pos: Vector2) -> Vector2i:
	return BunkerGeo.room_col_at(pos, _rooms)


func column_rect(room: int, col: int, cols: int) -> Rect2:
	return BunkerGeo.block_rect(room, col, cols)


func get_object_at(pos: Vector2) -> Dictionary:
	if Rect2(BunkerGeo.HATCH_X, BunkerGeo.ROOM_Y - 16, 32, 16).has_point(pos):
		return {"kind": "hatch"}
	var radio: BunkerObject = _fixed.get("radio_table")
	if radio != null and radio.bounds().has_point(pos):
		return {"kind": "radio", "room": radio.room, "col": radio.col}
	var box: BunkerObject = _fixed.get("hatch_box")
	if box != null and box.bounds().has_point(pos):
		return {"kind": "box", "room": box.room, "col": box.col}
	# instâncias: as de cima primeiro (filhos desenhados por último)
	var best: BunkerObject = null
	for o: BunkerObject in _inst.values():
		if o.bounds().has_point(pos):
			if best == null or (o.z_index >= best.z_index and o.get_index() > best.get_index()):
				best = o
	if best != null:
		return {"kind": "instance", "id": best.instance_id, "item": best.item, "room": best.room, "col": best.col}
	if _antenna.bounds().has_point(pos):
		return {"kind": "antenna"}
	for id: String in _fixed:
		var f: BunkerObject = _fixed[id]
		if f.bounds().has_point(pos):
			return {"kind": "fixed", "id": id, "room": f.room, "col": f.col}
	var rc := room_col_at(pos)
	if rc.x > 0:
		return {"kind": "room", "room": rc.x, "col": rc.y}
	return {}


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or _arrival_running:
		return
	var hit := get_object_at(get_local_mouse_position())
	match String(hit.get("kind", "")):
		"hatch":
			hatch_clicked.emit()
		"radio":
			attention.hover("radio")
			radio_clicked.emit()
		"box":
			attention.hover("box")
			box_clicked.emit()
		"instance":
			object_clicked.emit(int(hit["id"]))
		_:
			return
	get_viewport().set_input_as_handled()


# ---------------- cena do final ----------------

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec / maxf(cinematic_speed, 0.01)).timeout


func _tween_fade(to: float, sec: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void:
		_fade_alpha = a
		_fade.queue_redraw(), _fade_alpha, to, sec / maxf(cinematic_speed, 0.01))
	await tw.finished


## A escotilha abre, a luz desce pelo poço, ele olha para cima; corte; Game.finish_arrival().
func play_arrival() -> void:
	if _arrival_running:
		return
	_arrival_running = true
	man.interrupt()
	man.cinematic = true
	man.mode = "arrival"
	man.set_bubble("")
	var lx := BunkerGeo.col_x(1, 2) + 2.0   # na borda do facho, olhando para a escotilha
	man.walk_to(lx)
	var waited := 0.0
	while absf(man.position.x - lx) > 0.5 and waited < 20.0:
		await _wait(0.1)
		waited += 0.1
	man.interrupt()
	man.act("man_look_up", 3600.0, "look_up", -1)
	await _wait(0.6)
	_arrival_light = true
	_hatch.frame = 1
	spawn_fx("fx_dust", Vector2(BunkerGeo.HATCH_X + 16, BunkerGeo.ROOM_Y))
	_sync()
	await _wait(3.5)
	await _tween_fade(1.0, 0.8)
	await _wait(1.0)
	link.finish_arrival()
	arrival_cut.emit()
	_arrival_light = false
	_hatch.frame = 0
	man.interrupt()
	man.cinematic = false
	man.mode = ""
	_sync(true)
	await _tween_fade(0.0, 1.5)
	_arrival_running = false
	arrival_scene_finished.emit()


func arrival_running() -> bool:
	return _arrival_running
