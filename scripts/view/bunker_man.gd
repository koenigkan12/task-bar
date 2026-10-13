class_name BunkerMan
extends Node2D
## O homem (CONTRATOS 9). Visual representativo: a produção vem do Sim; aqui só se escolhe o que
## mostrar. Fila de passos ("walk" até um x, "act" = anima parado por um tempo) e uma decisão nova
## quando a fila acaba ou o modo muda (noite, obra, chegada).
## Sem a arte man_* importada, desenha um boneco provisório com as mesmas poses.

signal step_done(kind: String)

const SPEED := 20.0                 # px/s andando (padrão; o manifesto pode trazer speed_px_s)
const SLEEP_Y := -7.0               # deitado sobre o colchão da cama
const HUNGRY_SPEED := 0.6           # fator quando faminto (CONTRATOS 9.5)
const READY_PROGRESS := 0.95
const NOON_FROM := 11.5
const NOON_TO := 13.5

var view: Node                      # BunkerView (consultas de posição)
var link: GameLink
var cinematic: bool = false         # cena do final: o cérebro para de decidir
var anim: String = "man_idle"
var facing: int = 1                 # 1 direita, -1 esquerda
var mode: String = ""               # "night" | "build" | "day" | "arrival"
var activity: String = ""           # rótulo do que está fazendo (testes / depuração)
var carrying: bool = false

var _queue: Array[Dictionary] = []
var _cur: Dictionary = {}
var _act_left: float = 0.0
var _check_t: float = 0.0
var _ate_day: int = -1
var _rng := RandomNumberGenerator.new()
var _body: Node2D
var _sprite: ArtSprite
var _zzz: ArtSprite
var _bubble: Node2D
var _bubble_icon: String = ""
var _bubble_bob: bool = false
var _bob_t: float = 0.0
var _ph_frame: int = 0
var _ph_t: float = 0.0


func _init() -> void:
	_body = Node2D.new()
	add_child(_body)
	_sprite = ArtSprite.new()
	_body.add_child(_sprite)
	_body.draw.connect(_draw_placeholder)
	_zzz = ArtSprite.new("fx_zzz")
	_zzz.position = Vector2(4, -22)
	_zzz.visible = false
	add_child(_zzz)
	_bubble = Node2D.new()
	_bubble.position = Vector2(4, -26)
	_bubble.visible = false
	_bubble.z_index = 5
	_bubble.draw.connect(_draw_bubble)
	add_child(_bubble)
	position = Vector2(80, BunkerGeo.FEET_Y)


func seed_rng(s: int) -> void:
	_rng.seed = s


# ---------------- aparência ----------------

func play(a: String) -> void:
	anim = a
	var has_art := BunkerArt.has(a)
	_sprite.visible = has_art
	if has_art:
		_sprite.play(a)
		var f := BunkerArt.fps(a)
		if a in ["man_walk", "man_carry"] and link != null and link.hungry():
			f *= HUNGRY_SPEED
		_sprite.fps_override = f
	_zzz.visible = a == "man_sleep"
	_zzz.playing = _zzz.visible
	_body.queue_redraw()


func set_facing(dir: int) -> void:
	if dir != 0:
		facing = dir
		_body.scale.x = float(facing)


## Balão de pensamento (ícone de manifest_ui); "" esconde. bob = pulsando (sinal de atenção).
func set_bubble(icon: String, bob: bool = false) -> void:
	_bubble_icon = icon
	_bubble_bob = bob
	_bubble.visible = icon != ""
	_bubble.position.y = -26
	_bubble.queue_redraw()


func bubble_rect() -> Rect2:
	if not _bubble.visible:
		return Rect2()
	var a := BunkerArt.anchor("bubble_thought")
	return Rect2(position + _bubble.position - a, BunkerArt.frame_size("bubble_thought"))


func body_rect() -> Rect2:
	return Rect2(position + Vector2(-8, -26), Vector2(16, 26))


func _draw_bubble() -> void:
	var tex := BunkerArt.texture("bubble_thought")
	if tex == null:
		return
	var a := BunkerArt.anchor("bubble_thought")
	_bubble.draw_texture_rect_region(tex, Rect2(-a, BunkerArt.frame_size("bubble_thought")), BunkerArt.region("bubble_thought", 0))
	var it := BunkerArt.texture(_bubble_icon)
	if it != null:
		_bubble.draw_texture_rect_region(it, Rect2(-a + Vector2(8, 3), Vector2(8, 8)), BunkerArt.region(_bubble_icon, 0))


func _draw_placeholder() -> void:
	if _sprite.visible:
		return
	var skin := BunkerGeo.pal("skin2")
	var hair := BunkerGeo.pal("dark1")
	var shirt := BunkerGeo.pal("cloth1")
	var pants := BunkerGeo.pal("dark2")
	var boot := BunkerGeo.pal("ink")
	var f := _ph_frame
	var b := _body
	match anim:
		"man_sleep":
			b.draw_rect(Rect2(-10, -13, 16, 4), shirt)
			b.draw_rect(Rect2(6, -14, 5, 5), skin)
			b.draw_rect(Rect2(-14, -12, 4, 3), pants)
		"man_crouch":
			b.draw_rect(Rect2(-4, -4, 8, 4), pants)
			b.draw_rect(Rect2(-3, -12, 7, 8), shirt)
			b.draw_rect(Rect2(-1, -18, 6, 6), skin)
			b.draw_rect(Rect2(-1, -19, 6, 2), hair)
			b.draw_rect(Rect2(3, -6 + (f % 2), 3, 2), skin)
		"man_sit_read", "man_sit_listen", "man_nap", "man_pedal":
			var dip := 1 if anim == "man_nap" else 0
			b.draw_rect(Rect2(-3, -8, 8, 3), pants)
			b.draw_rect(Rect2(3, -8, 3, 8 if anim != "man_pedal" else 6 + (f % 2) * 2), pants)
			b.draw_rect(Rect2(-4, -17, 8, 9), shirt)
			b.draw_rect(Rect2(-3, -23 + dip, 6, 6), skin)
			b.draw_rect(Rect2(-3, -24 + dip, 6, 2), hair)
			if anim == "man_sit_read":
				b.draw_rect(Rect2(3, -15, 4, 3), BunkerGeo.pal("paper"))
		_:
			var leg := 0
			if anim in ["man_walk", "man_carry"]:
				leg = [0, 1, 0, -1][f % 4]
			b.draw_rect(Rect2(-3 + leg, -9, 3, 9), pants)
			b.draw_rect(Rect2(0 - leg, -9, 3, 9), pants)
			b.draw_rect(Rect2(-3 + leg, -1, 3, 1), boot)
			b.draw_rect(Rect2(0 - leg, -1, 3, 1), boot)
			b.draw_rect(Rect2(-4, -19, 8, 10), shirt)
			var hy := -25
			var hx := -3
			if anim == "man_look_up":
				hy -= 1
				hx -= 1
			b.draw_rect(Rect2(hx, hy, 6, 6), skin)
			b.draw_rect(Rect2(hx, hy - 1, 6, 2), hair)
			if anim == "man_look_up":
				b.draw_rect(Rect2(hx + 4, hy - 2, 2, 1), skin)
			match anim:
				"man_hammer", "man_dig":
					var up := f % 2 == 0
					b.draw_rect(Rect2(3, -17 if up else -13, 5, 2), skin)
					b.draw_rect(Rect2(7, -20 if up else -12, 2, 4), BunkerGeo.pal("conc2"))
				"man_carry":
					b.draw_rect(Rect2(3, -16, 6, 5), BunkerGeo.pal("rust3"))
				"man_water":
					b.draw_rect(Rect2(4, -12, 5, 4), BunkerGeo.pal("conc3"))
					if f % 2 == 0:
						b.draw_rect(Rect2(9, -9, 1, 2), BunkerGeo.pal("cloth2"))
				"man_write", "man_photo", "man_eat":
					b.draw_rect(Rect2(3, -15, 4, 3), BunkerGeo.pal("paper") if anim != "man_eat" else BunkerGeo.pal("conc3"))


# ---------------- ciclo ----------------

func _process(delta: float) -> void:
	_ph_t += delta
	if _ph_t >= 0.25:
		_ph_t = 0.0
		_ph_frame += 1
		if not _sprite.visible:
			_body.queue_redraw()
	if _bubble_bob:
		_bob_t += delta
		var y := -26.0 - (1.0 if fmod(_bob_t, 1.0) < 0.5 else 0.0)
		if _bubble.position.y != y:
			_bubble.position.y = y
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 1.0
		_check_mode()
	_run(delta)


func _run(delta: float) -> void:
	if _cur.is_empty():
		if _queue.is_empty():
			if cinematic:
				return
			decide()
			if _queue.is_empty():
				return
		_start(_queue.pop_front())
	match String(_cur.get("type", "")):
		"walk":
			var tx: float = _cur["x"]
			var sp := float(BunkerArt.info(anim).get("speed_px_s", SPEED))
			sp *= HUNGRY_SPEED if link != null and link.hungry() else 1.0
			var dx := tx - position.x
			if absf(dx) <= sp * delta:
				position.x = tx
				_finish()
			else:
				position.x += signf(dx) * sp * delta
		"act":
			_act_left -= delta
			if _act_left <= 0.0:
				_finish()


func _start(s: Dictionary) -> void:
	_cur = s
	match String(s.get("type", "")):
		"walk":
			var tx: float = s["x"]
			if absf(tx - position.x) < 0.5:
				_cur = {}
				return
			set_facing(1 if tx > position.x else -1)
			carrying = bool(s.get("carry", false))
			play("man_carry" if carrying else "man_walk")
		"act":
			if s.has("face"):
				set_facing(int(s["face"]))
			position.y = BunkerGeo.FEET_Y + float(s.get("y_off", 0.0))
			play(String(s.get("anim", "man_idle")))
			_act_left = float(s.get("time", 2.0))
			activity = String(s.get("label", activity))
			var cb: Callable = s.get("on_start", Callable())
			if cb.is_valid():
				cb.call()


func _finish() -> void:
	var s := _cur
	_cur = {}
	position.y = BunkerGeo.FEET_Y
	var cb: Callable = s.get("on_end", Callable())
	if cb.is_valid():
		cb.call()
	var done: Callable = s.get("on_finish", Callable())   # só quando o passo termina de verdade (não ao interromper)
	if done.is_valid():
		done.call()
	step_done.emit(String(s.get("type", "")))


## Para tudo (chama o on_end do passo atual, para não deixar a bicicleta girando).
func interrupt() -> void:
	if not _cur.is_empty():
		var cb: Callable = _cur.get("on_end", Callable())
		if cb.is_valid():
			cb.call()
	_cur = {}
	_queue.clear()
	position.y = BunkerGeo.FEET_Y
	carrying = false
	if view != null and view.has_method("release_orders"):
		view.release_orders()


func walk_to(x: float, carry: bool = false) -> void:
	_queue.append({"type": "walk", "x": x, "carry": carry})


func act(a: String, time: float, label: String, face: int = 0, extra: Dictionary = {}) -> void:
	var s := {"type": "act", "anim": a, "time": time, "label": label}
	if face != 0:
		s["face"] = face
	s.merge(extra)
	_queue.append(s)


func is_idle() -> bool:
	return _cur.is_empty() and _queue.is_empty()


# ---------------- cérebro ----------------

func _desired_mode() -> String:
	if cinematic:
		return "arrival"
	if link == null:
		return "day"
	if link.is_night() or not link.is_awake():
		return "night"
	if view != null and view.has_orders():
		return "order"
	if not link.active_jobs().is_empty():
		return "build"
	return "day"


func _check_mode() -> void:
	var m := _desired_mode()
	if m != mode:
		mode = m
		if (m == "night" or m == "arrival") and view != null:
			view.clear_orders()   # dormindo ou na cena do final ele não atende pedidos
		if m != "arrival":
			interrupt()


## Chegou uma ordem nova: o homem reavalia já (largar o que faz, ir até lá).
func order_added() -> void:
	_check_t = 0.0


func decide() -> void:
	if view == null or link == null:
		act("man_idle", 2.0, "idle")
		return
	mode = _desired_mode()
	match mode:
		"night":
			_plan_sleep()
		"build":
			_plan_build()
		"order":
			_plan_order()
		_:
			if _rng.randf() < maxf(link.busy(), 0.15) and _plan_work():
				return
			_plan_free()


func _plan_sleep() -> void:
	var bed: Variant = view.fixed_foot("bed")
	var x: float = bed.x if bed != null else position.x
	walk_to(x)
	act("man_sleep", 30.0, "sleep", 1, {"y_off": SLEEP_Y})


func _plan_build() -> void:
	var job: Dictionary = link.active_jobs()[0]
	var it := String(job.get("item", ""))
	if it.begins_with("comodo"):
		walk_to(view.dig_spot_x())
		act("man_dig", 6.0, "dig", 1, {"on_start": view.dig_fx})
		return
	var o: BunkerObject = view.object_by_id(int(job.get("instance", -1)))
	var tx: float = o.position.x - 12.0 if o != null else position.x
	if o != null and o.position.y < BunkerGeo.ROOM_Y:
		tx = view.fixed_foot("ladder").x + 4.0   # obra na superfície: martela ao pé da escada
	walk_to(tx)
	act("man_hammer", 6.0, "hammer", 1, {"on_start": func() -> void: view.build_fx(o)})


## Ordem do jogador: ele vai até o alvo, faz (martelar, regar/colher, levar à caixa) e só então a ajuda vale.
func _plan_order() -> void:
	var o: Dictionary = view.next_order()
	if o.is_empty():
		_plan_free()
		return
	var finish := func() -> void: view.finish_order(o)
	match String(o["kind"]):
		"hammer":
			var obj: BunkerObject = view.object_by_id(int(o["id"]))
			if obj == null:
				view.drop_order(o)
				return
			var tx: float = obj.position.x - 12.0
			if obj.position.y < BunkerGeo.ROOM_Y:
				tx = view.fixed_foot("ladder").x + 4.0
			walk_to(tx)
			act("man_hammer", 2.5, "hammer", 1, {"on_start": func() -> void: view.build_fx(obj), "on_finish": finish})
		"tend":
			var target: Dictionary = {}
			for p: Dictionary in link.plots():
				if int(p.get("instance", -1)) == int(o["id"]) and (target.is_empty() or float(p.get("progress", 0)) > float(target.get("progress", 0))):
					target = p
			if target.is_empty():
				view.drop_order(o)
				return
			walk_to(view.plot_pos(target).x - 9.0)
			if float(target.get("progress", 0)) >= READY_PROGRESS:
				act("man_crouch", 2.0, "harvest", 1, {"on_finish": finish})
			else:
				act("man_water", 2.5, "water", 1, {"on_finish": finish})
		_:
			var box: Variant = view.fixed_foot("hatch_box")
			walk_to((box.x if box != null else 32.0) + 10.0, true)
			act("man_idle", 1.2, "drop", -1, {"on_start": view.drop_fx, "on_finish": finish})


func _plan_work() -> bool:
	var opts: Array[String] = []
	var plots: Array = link.plots()
	var ready: Array = plots.filter(func(p: Dictionary) -> bool: return float(p.get("progress", 0)) >= READY_PROGRESS)
	if not ready.is_empty():
		opts.append("harvest")
	var tiers := link.line_tiers()
	if not plots.is_empty():
		var agua := String(tiers.get("agua", "lata"))
		if agua in ["", "lata"] or _rng.randf() < 0.25:
			opts.append("water")
	var bike: BunkerObject = view.find_item("bicicleta")
	if bike != null and not bike.building and String(tiers.get("energia", "bicicleta")) == "bicicleta":
		opts.append("pedal")
	if opts.is_empty():
		return false
	var pick: String = opts[_rng.randi() % opts.size()]
	match pick:
		"harvest":
			var p: Dictionary = ready[_rng.randi() % ready.size()]
			var pos: Vector2 = view.plot_pos(p)
			walk_to(pos.x - 8.0)
			act("man_crouch", 3.0, "harvest", 1)
			var box: Variant = view.fixed_foot("hatch_box")
			walk_to((box.x if box != null else 32.0) + 10.0, true)
			act("man_idle", 1.0, "drop", -1, {"on_start": view.drop_fx})
		"water":
			var p: Dictionary = plots[_rng.randi() % plots.size()]
			var pos: Vector2 = view.plot_pos(p)
			walk_to(pos.x - 9.0)
			act("man_water", 3.0, "water", 1)
		"pedal":
			walk_to(bike.position.x)
			# a bicicleta pode ser trocada (moinho) no meio do passo: procura de novo em vez de capturar
			act("man_pedal", 6.0, "pedal", 1, {
				"on_start": func() -> void: _set_bike_spin(true),
				"on_end": func() -> void: _set_bike_spin(false)})
	return true


func _set_bike_spin(on: bool) -> void:
	var b: BunkerObject = view.find_item("bicicleta")
	if b != null:
		b.sprite.playing = on


func _plan_free() -> void:
	var opts: Array[String] = ["idle", "wander"]
	var tod := link.tod_hours()
	if tod >= NOON_FROM and tod <= NOON_TO and _ate_day != link.day_index():
		_ate_day = link.day_index()
		var mesa: BunkerObject = view.find_item("mesinha")
		walk_to(mesa.position.x - 10.0 if mesa != null else position.x)
		act("man_eat", 5.0, "eat", 1)
		return
	for b: String in link.unlocked_behaviors():
		opts.append(b)
	if link.arrived():
		opts.append("sentar_junto")
	var pick: String = opts[_rng.randi() % opts.size()]
	var chair: BunkerObject = view.find_item("poltrona")
	match pick:
		"ler":
			if chair != null:
				walk_to(chair.position.x)
				act("man_sit_read", 10.0, "ler", 1)
			else:
				var shelf: BunkerObject = view.find_item("estante")
				walk_to(shelf.position.x + 12.0 if shelf != null else position.x)
				act("man_idle", 6.0, "ler", -1)
		"cochilar":
			if chair != null:
				walk_to(chair.position.x)
				act("man_nap", 10.0, "cochilar", 1)
		"ouvir_radio":
			if chair != null:
				walk_to(chair.position.x)
				act("man_sit_listen", 10.0, "ouvir_radio", -1 if chair.position.x > view.fixed_foot("radio_table").x else 1)
			else:
				walk_to(view.fixed_foot("radio_table").x + 12.0)
				act("man_idle", 6.0, "ouvir_radio", -1)
		"escrever":
			var desk: BunkerObject = view.find_item("mesinha")
			if desk != null:
				walk_to(desk.position.x - 10.0)
				act("man_write", 8.0, "escrever", 1)
		"olhar_foto":
			var ph: BunkerObject = view.find_item("foto_dela") if link.arrived() and view.find_item("foto_dela") != null else view.find_item("foto")
			if ph != null:
				walk_to(ph.position.x - 10.0)
				act("man_photo", 6.0, "olhar_foto", 1)
		"sentar_junto":
			# epílogo: o mesmo ritual, agora com a segunda caneca na mesa
			var desk: BunkerObject = view.find_item("mesinha")
			if chair != null:
				walk_to(chair.position.x)
				act("man_sit_listen", 12.0, "sentar_junto", 1)
			elif desk != null:
				walk_to(desk.position.x - 10.0)
				act("man_idle", 8.0, "sentar_junto", 1)
		"wander":
			walk_to(clampf(position.x + _rng.randf_range(-40.0, 40.0), view.walk_min_x(), view.walk_max_x()))
			act("man_idle", _rng.randf_range(1.5, 3.0), "idle")
		_:
			act("man_idle", _rng.randf_range(2.0, 4.0), "idle")
	if _queue.is_empty():
		act("man_idle", 2.0, "idle")
