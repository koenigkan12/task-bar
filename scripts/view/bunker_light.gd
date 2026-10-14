class_name BunkerLight
extends Node2D
## Luz feita por código, em degraus com dither (cara de pixel art):
## - CONE: luz do relógio descendo pelo poço da escada (aditiva);
## - GLOW: halo da lâmpada do teto (aditivo);
## - SHADE: escurecimento multiplicativo da faixa (noite / lâmpada apagada).
## A cor e a força vêm de `tint` (aditivas: alpha = força).

enum Kind { CONE, GLOW, SHADE }

const CONE_ORIGIN := Vector2(0, 24)
const CONE_SIZE := Vector2i(52, 64)
const GLOW_SIZE := Vector2i(120, 48)

var kind: Kind = Kind.CONE
var tint: Color = Color(1, 1, 1, 1):
	set(v):
		tint = v
		queue_redraw()
## SHADE: largura coberta e cores (superfície y 0–32, salas y 32–88).
var width: int = 344:
	set(v):
		width = v
		queue_redraw()
var height: int = BunkerGeo.H:
	set(v):
		if v != height:
			height = v
			queue_redraw()
var surface_tint: Color = Color(1, 1, 1, 1):
	set(v):
		surface_tint = v
		queue_redraw()
## CONE: abertura extra (chegada: a escotilha aberta deixa entrar mais luz).
var wide: bool = false:
	set(v):
		if v != wide:
			wide = v
			_tex = null
			queue_redraw()

var _tex: ImageTexture


func _init(k: Kind = Kind.CONE) -> void:
	kind = k
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL if k == Kind.SHADE else CanvasItemMaterial.BLEND_MODE_ADD
	material = m


static func _step(v: float, x: int, y: int, levels: int = 3) -> float:
	var s := clampf(v, 0.0, 1.0) * levels
	var base := floorf(s)
	if s - base > BunkerGeo.bayer(x, y):
		base += 1.0
	return base / levels


func _make_cone() -> ImageTexture:
	var img := Image.create(CONE_SIZE.x, CONE_SIZE.y, false, Image.FORMAT_RGBA8)
	for y in CONE_SIZE.y:
		var wy := CONE_ORIGIN.y + y
		var d := clampf((wy - 24.0) / 56.0, 0.0, 1.0)
		var hw := (8.0 + d * (14.0 if wide else 9.0))
		var cx := 16.0 + d * (6.0 if wide else 3.0)
		for x in CONE_SIZE.x:
			var dist := absf(x + 0.5 - cx)
			var side := 1.0 - clampf((dist - hw * 0.55) / (hw * 0.45), 0.0, 1.0)
			var v := (1.0 - 0.5 * d) * side
			# poça no chão
			if wy >= 78:
				var pool := 1.0 - clampf(absf(x + 0.5 - (cx + 2.0)) / (hw + 6.0), 0.0, 1.0)
				v = maxf(v, pool * 0.7)
			var a := _step(v, x, y) * 0.6
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_glow() -> ImageTexture:
	var img := Image.create(GLOW_SIZE.x, GLOW_SIZE.y, false, Image.FORMAT_RGBA8)
	var c := Vector2(GLOW_SIZE.x * 0.5, 6.0)
	for y in GLOW_SIZE.y:
		for x in GLOW_SIZE.x:
			var dx := (x + 0.5 - c.x) / (GLOW_SIZE.x * 0.5)
			var dy := (y + 0.5 - c.y) / float(GLOW_SIZE.y - 6)
			var v := 1.0 - sqrt(dx * dx + dy * dy)
			img.set_pixel(x, y, Color(1, 1, 1, _step(v, x, y) * 0.4))
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	match kind:
		Kind.SHADE:
			draw_rect(Rect2(0, 0, width, BunkerGeo.ROOM_Y), surface_tint)
			draw_rect(Rect2(0, BunkerGeo.ROOM_Y, width, height - BunkerGeo.ROOM_Y), tint)
		Kind.CONE:
			if tint.a <= 0.01:
				return
			if _tex == null:
				_tex = _make_cone()
			draw_texture(_tex, CONE_ORIGIN, tint)
		Kind.GLOW:
			if tint.a <= 0.01:
				return
			if _tex == null:
				_tex = _make_glow()
			draw_texture(_tex, Vector2(-GLOW_SIZE.x * 0.5, 0), tint)
