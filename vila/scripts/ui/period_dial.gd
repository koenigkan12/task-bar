class_name PeriodDial
extends Control
## Relógio de período: um círculo que vai enchendo do começo ao fim do dia (ou da noite),
## com o sol ou a lua no meio. Reinicia na troca. O horário exato fica na dica do mouse.

const R := 6.0

var frac: float = 0.0
var night: bool = false
var sun: Texture2D
var moon: Texture2D


func _init() -> void:
	custom_minimum_size = Vector2(14, 14)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_state(f: float, is_night: bool) -> void:
	f = clampf(f, 0.0, 1.0)
	if absf(f - frac) < 0.002 and is_night == night:
		return
	frac = f
	night = is_night
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var fill := Color(0.45, 0.55, 0.95) if night else Color(1.0, 0.8, 0.42)
	draw_circle(c, R, Color(0.12, 0.1, 0.14))
	if frac > 0.0:
		# Fatia a partir do topo, no sentido do relógio.
		var pts := PackedVector2Array([c])
		var steps := maxi(2, int(ceil(frac * 32.0)))
		for i in steps + 1:
			var a := -PI / 2.0 + TAU * frac * float(i) / float(steps)
			pts.append(c + Vector2(cos(a), sin(a)) * R)
		draw_colored_polygon(pts, fill.darkened(0.35))
	draw_arc(c, R, 0.0, TAU, 32, fill, 1.0)
	var tex := moon if night else sun
	if tex != null:
		draw_texture(tex, (c - tex.get_size() / 2.0).round())
