class_name VilaFireflies
extends Node2D
## Vaga-lumes da noite: cada um vaga devagar pela vila (direção que muda aos poucos) e pisca com halo.
## Fica numa CanvasLayer própria para o escuro da noite não apagar a luz.

const COUNT := 60
const COL := Color(0.86, 1.0, 0.5)

var area: Rect2
var level: float = 0.0             # 0 dia .. 1 noite plena (some e aparece aos poucos)
var _p: Array[Vector2] = []
var _ang: Array[float] = []
var _ph: Array[float] = []
var _spd: Array[float] = []


func setup(size: Vector2) -> void:
	area = Rect2(Vector2.ZERO, size)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # luz soma na cena, brilha no escuro
	material = m
	for i in COUNT:
		_p.append(Vector2(randf() * size.x, randf() * size.y))
		_ang.append(randf() * TAU)
		_ph.append(randf() * TAU)
		_spd.append(randf_range(3.0, 7.0))


func _process(delta: float) -> void:
	visible = level > 0.01
	if not visible:
		return
	for i in COUNT:
		_ang[i] += randf_range(-2.0, 2.0) * delta
		_p[i] += Vector2.from_angle(_ang[i]) * _spd[i] * delta
		# Sai por um lado, volta pelo outro.
		_p[i] = Vector2(fposmod(_p[i].x, area.size.x), fposmod(_p[i].y, area.size.y))
		_ph[i] += delta * randf_range(1.5, 2.5)
	queue_redraw()


func _draw() -> void:
	for i in COUNT:
		var b := clampf(0.55 + 0.45 * sin(_ph[i]), 0.0, 1.0) * level
		if b < 0.05:
			continue
		var c := _p[i].round()
		draw_rect(Rect2(c - Vector2(2, 2), Vector2(6, 6)), Color(COL, 0.10 * b))
		draw_rect(Rect2(c - Vector2(1, 1), Vector2(4, 4)), Color(COL, 0.25 * b))
		draw_rect(Rect2(c, Vector2(2, 2)), Color(1.0, 1.0, 0.75, b))
