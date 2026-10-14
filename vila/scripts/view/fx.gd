class_name VilaFx
extends Node2D
## Efeitos do mapa, todos com CPUParticles2D (funciona no renderizador de compatibilidade):
## vento com rajadas (as árvores balançam pelo shader sway.gdshader), folhas caindo, poeira no chão,
## fumaça da fogueira e das chaminés, faíscas da oficina e do ferro-velho, vaga-lumes de noite.
## O WorldView chama attach() ao montar cada prédio e update_fx() a cada quadro.

const LEAF_COLORS: Array[Color] = [Color(0.86, 0.56, 0.28), Color(0.47, 0.62, 0.42), Color(0.7, 0.4, 0.25), Color(0.36, 0.52, 0.5)]

var wind: float = 0.5               # 0 calmo .. 1 rajada
var tree_mat: ShaderMaterial
var _wind_target: float = 0.5
var _wind_t: float = 0.0
var _leaves: CPUParticles2D
var _dust: CPUParticles2D
var _streaks: CPUParticles2D        # riscos de vento: só aparecem na rajada, pra o balanço ter motivo
var _flies: CPUParticles2D
var _fly_layer: CanvasLayer
var _smokes: Array = []             # {p: CPUParticles2D, base: Vector2}
var _sparks: Array = []             # {p: CPUParticles2D, b: id}


func setup(world_size: Vector2) -> void:
	tree_mat = ShaderMaterial.new()
	tree_mat.shader = load("res://assets/shaders/sway.gdshader")
	z_index = 40
	_leaves = _emitter(26, 7.0)
	_leaves.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_leaves.emission_rect_extents = world_size / 2.0
	_leaves.position = world_size / 2.0
	_leaves.direction = Vector2(1, 0.4)
	_leaves.spread = 30.0
	_leaves.initial_velocity_min = 4.0
	_leaves.initial_velocity_max = 10.0
	_leaves.scale_amount_min = 1.0
	_leaves.scale_amount_max = 2.0
	_leaves.color_ramp = _fade(Color.WHITE, 0.15, 0.8)
	_leaves.color_initial_ramp = _palette(LEAF_COLORS)
	_leaves.preprocess = 6.0
	add_child(_leaves)
	_dust = _emitter(10, 3.0)
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = world_size / 2.0
	_dust.position = world_size / 2.0
	_dust.direction = Vector2(1, 0)
	_dust.spread = 8.0
	_dust.initial_velocity_min = 14.0
	_dust.initial_velocity_max = 26.0
	_dust.scale_amount_min = 1.0
	_dust.scale_amount_max = 1.0
	_dust.color_ramp = _fade(Color(0.82, 0.7, 0.6, 0.55), 0.2, 0.6)
	add_child(_dust)
	_streaks = _emitter(24, 1.4)
	_streaks.texture = _line_tex(9)
	_streaks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_streaks.emission_rect_extents = world_size / 2.0
	_streaks.position = world_size / 2.0
	_streaks.direction = Vector2(1, 0)
	_streaks.spread = 3.0
	_streaks.gravity = Vector2.ZERO
	_streaks.initial_velocity_min = 45.0
	_streaks.initial_velocity_max = 70.0
	_streaks.color_ramp = _fade(Color(0.92, 0.9, 0.86, 0.6), 0.2, 0.7)
	_streaks.emitting = false
	add_child(_streaks)
	# Vaga-lumes numa camada própria: o escuro da noite (CanvasModulate) não apaga a luz deles.
	_fly_layer = CanvasLayer.new()
	_fly_layer.layer = 1
	_fly_layer.follow_viewport_enabled = true
	add_child(_fly_layer)
	_flies = _emitter(18, 5.0)
	_flies.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_flies.emission_rect_extents = world_size / 2.0
	_flies.position = world_size / 2.0
	_flies.gravity = Vector2(0, -1.5)
	_flies.spread = 180.0
	_flies.initial_velocity_min = 1.0
	_flies.initial_velocity_max = 4.0
	_flies.scale_amount_min = 1.0
	_flies.scale_amount_max = 1.0
	_flies.color_ramp = _pulse(Color(0.85, 1.0, 0.45))
	_flies.emitting = false
	_fly_layer.add_child(_flies)


func _emitter(amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.texture = null
	return p


func _line_tex(w: int) -> ImageTexture:
	var img := Image.create(w, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _fade(c: Color, fade_in: float, fade_out: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c, 0.0))
	g.set_color(1, Color(c, 0.0))
	g.add_point(fade_in, c)
	g.add_point(fade_out, c)
	return g


func _pulse(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c, 0.0))
	g.set_color(1, Color(c, 0.0))
	g.add_point(0.25, c)
	g.add_point(0.4, Color(c, 0.3))
	g.add_point(0.6, c)
	return g


func _palette(cols: Array[Color]) -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.set_color(0, cols[0])
	g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1):
		g.add_point(float(i) / float(cols.size() - 1), cols[i])
	return g


## Fumaça e faíscas de um prédio (root = canto de baixo à esquerda do prédio, h = altura do sprite).
func attach(root: Node2D, tp: String, level: int, h: int, id: int) -> void:
	var spots: Array = []   # [x, y a partir do topo do sprite]
	match tp:
		"fogueira":
			spots = [[8, h - 12]]
		"cozinha":
			spots = [[18, 0]]
		"gerador":
			spots = [[10, 1]]
		"oficina":
			if level >= 2:
				spots = [[9, 0]]
		"moradia":
			if level >= 3:
				spots = [[24, 2]]
	for sp in spots:
		var p := _emitter(10 if tp == "fogueira" else 6, 2.6)
		p.position = Vector2(float(sp[0]), -h + float(sp[1]))
		p.direction = Vector2(0, -1)
		p.spread = 12.0
		p.initial_velocity_min = 5.0
		p.initial_velocity_max = 9.0
		p.scale_amount_min = 1.0
		p.scale_amount_max = 2.0
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.6))
		curve.add_point(Vector2(1, 1.6))
		p.scale_amount_curve = curve
		p.color_ramp = _fade(Color(0.62, 0.58, 0.64, 0.5), 0.1, 0.5)
		root.add_child(p)
		_smokes.append({"p": p})
		if tp == "fogueira":
			var e := _emitter(5, 1.0)
			e.position = Vector2(8, -6)
			e.direction = Vector2(0, -1)
			e.spread = 25.0
			e.initial_velocity_min = 10.0
			e.initial_velocity_max = 18.0
			e.gravity = Vector2(0, 4)
			e.scale_amount_min = 1.0
			e.scale_amount_max = 1.0
			e.color_ramp = _fade(Color(1.0, 0.7, 0.3), 0.05, 0.5)
			root.add_child(e)
	if tp == "oficina" or tp == "ferrovelho":
		var s := _emitter(6, 0.5)
		s.position = Vector2(20 if tp == "oficina" else 24, -10)
		s.direction = Vector2(0, -1)
		s.spread = 70.0
		s.initial_velocity_min = 14.0
		s.initial_velocity_max = 26.0
		s.gravity = Vector2(0, 60)
		s.scale_amount_min = 1.0
		s.scale_amount_max = 1.0
		s.color_ramp = _fade(Color(1.0, 0.62, 0.28) if tp == "oficina" else Color(0.75, 0.42, 0.25), 0.02, 0.6)
		s.emitting = false
		root.add_child(s)
		_sparks.append({"p": s, "b": id})


## A cada quadro: rajadas de vento, folhas e poeira seguem o vento, vaga-lumes só de noite,
## faíscas só com alguém trabalhando.
func update_fx(delta: float, sim: VilaSim, night_k: float) -> void:
	_wind_t -= delta
	if _wind_t <= 0.0:
		_wind_t = randf_range(5.0, 14.0)
		# Quase sempre brisa; de vez em quando uma rajada curta (que aparece nos riscos de vento).
		var gust := randf() < 0.2
		_wind_target = randf_range(0.7, 1.0) if gust else randf_range(0.0, 0.35)
		if gust:
			_wind_t = randf_range(3.0, 5.0)
	wind = move_toward(wind, _wind_target, delta * 0.25)
	tree_mat.set_shader_parameter("wind", wind)
	_leaves.gravity = Vector2(6.0 + wind * 26.0, 7.0)
	_leaves.speed_scale = 0.7 + 0.6 * wind
	_dust.emitting = wind > 0.65 and night_k < 0.5
	_streaks.emitting = wind > 0.55
	_dust.gravity = Vector2(wind * 20.0, 0)
	_flies.emitting = night_k > 0.55
	# Prédio desmontado leva o nó junto: confere antes de pôr numa variável tipada (dava erro).
	_smokes = _smokes.filter(func(e: Dictionary) -> bool: return is_instance_valid(e["p"]))
	for e in _smokes:
		var p: CPUParticles2D = e["p"]
		p.gravity = Vector2(4.0 + wind * 18.0, -3.0)
	_sparks = _sparks.filter(func(e: Dictionary) -> bool: return is_instance_valid(e["p"]))
	for e in _sparks:
		var s: CPUParticles2D = e["p"]
		var b := sim.by_id(int(e["b"]))
		var busy := false
		if not b.is_empty():
			for pid in b["workers"]:
				if String(sim.person(int(pid)).get("phase", "")) == "working":
					busy = true
		s.emitting = busy
	_sparks = _sparks.filter(func(e: Dictionary) -> bool: return is_instance_valid(e["p"]))
