class_name NeedGauge
extends Control
## Medidor redondo de uma necessidade (estilo Don't Starve), em pixels: aro de metal, líquido que desce com o
## nível e o ícone da necessidade (maçã, gota, lua) no meio. O aro é o aviso: metal = bem, amarelo = precisa
## (abaixo de 50%), vermelho = perigo (abaixo de 10%).

const SIZE: int = 14

const GLYPHS: Dictionary = {
	"food": ["...#...", ".##.##.", "#######", "#######", "#######", ".#####.", "..#.#.."],
	"water": ["...#...", "...#...", "..###..", ".#####.", "#######", "#######", ".#####."],
	"sleep": ["..####.", ".###...", "###....", "###....", "###....", ".###...", "..####."],
}
const LIQUID: Dictionary = {"food": Color("e0852e"), "water": Color("4f9fe0"), "sleep": Color("9a78e0")}

var need: String = "food":
	set(v):
		need = v
		queue_redraw()
var level: float = 1.0:
	set(v):
		level = clampf(v, 0.0, 1.0)
		queue_redraw()
var state: String = "ok":
	set(v):
		state = v
		queue_redraw()
## Cor do líquido; vazio = a da necessidade.
var color: Color = Color(0, 0, 0, 0):
	set(v):
		color = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var r: float = SIZE * 0.5
	var liquid: Color = color if color.a > 0.0 else Color(LIQUID.get(need, UiTheme.AMBER2))
	var ring: Color = {"ok": UiTheme.CONC3, "warn": UiTheme.AMBER2, "bad": UiTheme.TOMATO}.get(state, UiTheme.CONC3)
	var top: int = int(roundf((SIZE - 2.0) * (1.0 - level))) + 1
	for y in SIZE:
		for x in SIZE:
			var d: float = Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if d > r:
				continue
			var c: Color
			if d > r - 1.0:
				c = ring
				if state == "ok":   # brilho de metal: claro em cima à esquerda, escuro embaixo à direita
					c = UiTheme.CONC4 if (x + y) < SIZE - 2 and y < r else (UiTheme.CONC1 if x + y > SIZE + 2 else ring)
			elif level > 0.0 and y >= top:
				c = liquid.lightened(0.35) if y == top else liquid
				if x > SIZE - 4:
					c = c.darkened(0.2)
			else:
				c = UiTheme.INK
			draw_rect(Rect2(x, y, 1, 1), c)
	var rows: Array = GLYPHS.get(need, GLYPHS["food"])
	var ox: int = (SIZE - 7) / 2 + (1 if need == "sleep" else 0)
	var oy: int = (SIZE - 7) / 2
	for gy in rows.size():
		var row: String = rows[gy]
		for gx in row.length():
			if row[gx] == "#":
				draw_rect(Rect2(ox + gx, oy + gy, 1, 1), UiTheme.PAPER)
