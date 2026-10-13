class_name NeedGauge
extends Control
## Medidor redondo de uma necessidade (estilo Don't Starve), em pixels: o líquido sobe e desce com o nível,
## o aro mostra o estado (metal = bem, âmbar = precisa, vermelho = perigo).

const SIZE: int = 14

var level: float = 1.0:
	set(v):
		level = clampf(v, 0.0, 1.0)
		queue_redraw()
var state: String = "ok":
	set(v):
		state = v
		queue_redraw()
var color: Color = UiTheme.AMBER2:
	set(v):
		color = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func _draw() -> void:
	var r: float = SIZE * 0.5
	var ring: Color = {"ok": UiTheme.CONC2, "warn": UiTheme.AMBER2, "bad": UiTheme.TOMATO}.get(state, UiTheme.CONC2)
	var top: float = SIZE * (1.0 - level)
	for y in SIZE:
		for x in SIZE:
			var d: float = Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if d > r:
				continue
			var c: Color
			if d > r - 1.0:
				c = ring
			elif y + 0.5 >= top and level > 0.0:
				c = color
			else:
				c = UiTheme.DARK1
			draw_rect(Rect2(x, y, 1, 1), c)
	# brilho no vidro
	draw_rect(Rect2(3, 3, 1, 1), Color(1, 1, 1, 0.45))
