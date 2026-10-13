class_name BunkerDecor
extends RefCounted
## Enfeites do bunker desenhados por código com a paleta fixa (BunkerGeo.PAL): quadros, calendário,
## mapa, quadro de ferramentas, caixas, latas, canos e portas. Tudo estático: o BunkerTerrain chama
## estas funções dentro do próprio _draw (por isso recebem o CanvasItem `c`).


static func _p(n: String) -> Color:
	return BunkerGeo.pal(n)


static func r(c: CanvasItem, x: int, y: int, w: int, h: int, col: Color) -> void:
	c.draw_rect(Rect2(x, y, w, h), col)


static func hl(c: CanvasItem, x: int, y: int, n: int, col: Color) -> void:
	c.draw_rect(Rect2(x, y, n, 1), col)


static func vl(c: CanvasItem, x: int, y: int, n: int, col: Color) -> void:
	c.draw_rect(Rect2(x, y, 1, n), col)


static func px(c: CanvasItem, x: int, y: int, col: Color) -> void:
	c.draw_rect(Rect2(x, y, 1, 1), col)


## Contorno de 1 px por fora do retângulo (x, y, w, h).
static func frame(c: CanvasItem, x: int, y: int, w: int, h: int, col: Color) -> void:
	hl(c, x - 1, y - 1, w + 2, col)
	hl(c, x - 1, y + h, w + 2, col)
	vl(c, x - 1, y, h, col)
	vl(c, x + w, y, h, col)


# ---------------------------------------------------------------- paredes e piso

## Parede grossa de concreto entre cômodos (8 px), do teto ao piso, com porta de aço aberta.
static func wall_with_door(c: CanvasItem, x: int, y0: int, y1: int, door: bool = true) -> void:
	r(c, x, y0, 8, y1 - y0, _p("conc1"))
	vl(c, x, y0, y1 - y0, _p("conc3"))
	vl(c, x + 1, y0, y1 - y0, _p("conc2"))
	vl(c, x + 7, y0, y1 - y0, _p("dark3"))
	var yy := y0 + 3
	while yy < y1:
		px(c, x + 3, yy, _p("dark3"))
		px(c, x + 4, yy + 3, _p("conc2"))
		yy += 7
	if door:
		var top := y1 - 27
		r(c, x, top, 8, y1 - top, _p("ink"))                  # vão da porta (dá para passar)
		hl(c, x, top - 1, 8, _p("conc3"))                      # batente
		r(c, x + 5, top + 1, 3, y1 - top - 1, _p("conc2"))     # folha de aço, aberta para o lado
		vl(c, x + 6, top + 1, y1 - top - 1, _p("dark3"))
		px(c, x + 5, top + 13, _p("conc4"))
		px(c, x + 5, top + 14, _p("conc4"))


## Cano, fio e braçadeiras ao longo do teto (x0..x1, y = linha de cima do cano).
static func ceiling_runs(c: CanvasItem, x0: int, x1: int, y: int) -> void:
	hl(c, x0, y, x1 - x0, _p("conc2"))
	hl(c, x0, y + 1, x1 - x0, _p("dark3"))
	hl(c, x0, y + 3, x1 - x0, _p("ink"))
	var x := x0 + 8
	while x < x1 - 2:
		r(c, x, y - 1, 2, 5, _p("dark2"))
		x += 26


## Parede de azulejo claro (estufa): fiadas de 6 px com juntas alternadas.
static func tiles_wall(c: CanvasItem, x0: int, y0: int, x1: int, y1: int) -> void:
	r(c, x0, y0, x1 - x0, y1 - y0, _p("conc3"))
	var yy := y0
	var row := 0
	while yy < y1:
		hl(c, x0, yy, x1 - x0, _p("conc2"))
		var xx := x0 + (3 if row % 2 == 1 else 0)
		while xx < x1:
			vl(c, xx, yy, mini(6, y1 - yy), _p("conc2"))
			xx += 6
		yy += 6
		row += 1
	var tint := _p("leaf3")
	tint.a = 0.16
	r(c, x0, y0, x1 - x0, y1 - y0, tint)


## Lambri de madeira (metade de baixo da parede do quarto).
static func wood_panels(c: CanvasItem, x0: int, y0: int, x1: int, y1: int) -> void:
	r(c, x0, y0, x1 - x0, y1 - y0, _p("rust2"))
	var xx := x0
	while xx < x1:
		vl(c, xx, y0, y1 - y0, _p("rust1"))
		if xx + 1 < x1:
			vl(c, xx + 1, y0, y1 - y0, _p("rust3"))
		xx += 6
	hl(c, x0, y0, x1 - x0, _p("rust4"))
	hl(c, x0, y0 + 1, x1 - x0, _p("rust1"))


## Piso de tábua (quarto): h px de altura.
static func plank_floor(c: CanvasItem, x0: int, y: int, x1: int, h: int) -> void:
	r(c, x0, y, x1 - x0, h, _p("rust2"))
	hl(c, x0, y, x1 - x0, _p("rust3"))
	var xx := x0 + 5
	while xx < x1:
		vl(c, xx, y + 1, h - 1, _p("rust1"))
		xx += 13
	hl(c, x0, y + h - 1, x1 - x0, _p("rust1"))


# ---------------------------------------------------------------- quadros e papéis

static func calendar(c: CanvasItem, x: int, y: int) -> void:
	frame(c, x, y, 15, 17, _p("ink"))
	r(c, x, y, 15, 17, _p("conc4"))
	r(c, x, y, 15, 4, _p("tomato"))
	for rr in 4:
		for cc in 4:
			var cx := x + 1 + cc * 3 + (1 if cc > 1 else 0)
			var cy := y + 5 + rr * 3
			if rr < 3 or cc < 2:
				px(c, cx, cy, _p("tomato"))
				px(c, cx + 1, cy + 1, _p("tomato"))
			else:
				px(c, cx, cy, _p("conc2"))


## Tracinhos de dias contados (n riscos, de 5 em 5 com o corte).
static func tally(c: CanvasItem, x: int, y: int, n: int) -> void:
	for i in n:
		var g := i / 5
		var k := i % 5
		if k < 4:
			vl(c, x + g * 7 + k, y, 5, _p("conc4"))
		else:
			c.draw_line(Vector2(x + g * 7 + 0.5, y + 3.5), Vector2(x + g * 7 + 6.5, y + 1.5), _p("conc4"))


static func wall_map(c: CanvasItem, x: int, y: int) -> void:
	frame(c, x, y, 23, 15, _p("ink"))
	r(c, x, y, 23, 15, _p("paper"))
	for l in [[2, 3, 12, 5], [5, 9, 20, 7], [10, 2, 14, 12], [16, 4, 20, 11]]:
		c.draw_line(Vector2(x + l[0] + 0.5, y + l[1] + 0.5), Vector2(x + l[2] + 0.5, y + l[3] + 0.5), _p("conc2"))
	r(c, x + 13, y + 7, 6, 5, _p("leaf3"))
	c.draw_line(Vector2(x + 6.5, y + 4.5), Vector2(x + 15.5, y + 9.5), _p("tomato"))
	for pt in [[6, 4], [15, 9], [19, 3]]:
		px(c, x + pt[0], y + pt[1], _p("tomato"))


static func pegboard(c: CanvasItem, x: int, y: int) -> void:
	frame(c, x, y, 27, 15, _p("ink"))
	r(c, x, y, 27, 15, _p("rust3"))
	var yy := y + 2
	while yy < y + 14:
		var xx := x + 2
		while xx < x + 26:
			px(c, xx, yy, _p("rust2"))
			xx += 3
		yy += 3
	vl(c, x + 4, y + 3, 9, _p("conc3"))
	r(c, x + 2, y + 2, 6, 3, _p("conc2"))                      # martelo
	vl(c, x + 11, y + 3, 10, _p("conc4"))
	r(c, x + 10, y + 2, 4, 2, _p("conc4"))                     # chave
	vl(c, x + 17, y + 3, 8, _p("tomato"))
	px(c, x + 17, y + 11, _p("conc4"))                         # chave de fenda
	hl(c, x + 21, y + 3, 4, _p("conc3"))
	vl(c, x + 22, y + 4, 8, _p("rust2"))                       # serrote


## Moldura com paisagem (quadro de parede).
static func picture(c: CanvasItem, x: int, y: int, w: int, h: int) -> void:
	frame(c, x, y, w, h, _p("ink"))
	r(c, x, y, w, h, _p("amber2"))
	r(c, x + 2, y + 2, w - 4, h - 4, _p("cloth2"))
	r(c, x + 2, y + h - 5, w - 4, 3, _p("leaf2"))
	px(c, x + w - 5, y + 4, _p("amber4"))


## Prancheta com gráfico de crescimento (estufa).
static func growth_chart(c: CanvasItem, x: int, y: int) -> void:
	frame(c, x, y, 17, 13, _p("ink"))
	r(c, x, y, 17, 13, _p("paper"))
	hl(c, x + 1, y + 10, 15, _p("conc2"))
	vl(c, x + 1, y + 1, 10, _p("conc2"))
	var pts := [[3, 9], [6, 8], [8, 6], [11, 4], [14, 2]]
	for i in pts.size() - 1:
		c.draw_line(Vector2(x + pts[i][0] + 0.5, y + pts[i][1] + 0.5), Vector2(x + pts[i + 1][0] + 0.5, y + pts[i + 1][1] + 0.5), _p("leaf2"))
	px(c, x + 14, y + 2, _p("tomato"))


## Válvula num cano vertical (estufa).
static func valve_pipe(c: CanvasItem, x: int, y0: int, y1: int) -> void:
	r(c, x, y0, 3, y1 - y0, _p("conc2"))
	vl(c, x, y0, y1 - y0, _p("conc3"))
	vl(c, x + 2, y0, y1 - y0, _p("dark3"))
	var vy := (y0 + y1) / 2
	r(c, x - 2, vy - 1, 7, 2, _p("tomato"))
	px(c, x + 1, vy - 2, _p("dark3"))


# ---------------------------------------------------------------- despensa

static func crate(c: CanvasItem, x: int, yf: int, w: int = 14, h: int = 10) -> void:
	var y := yf - h
	frame(c, x, y, w + 1, h, _p("ink"))
	r(c, x, y, w + 1, h, _p("rust2"))
	hl(c, x, y, w, _p("rust4"))
	hl(c, x, yf - 2, w, _p("rust1"))
	c.draw_line(Vector2(x + 0.5, y + 0.5), Vector2(x + w - 0.5, yf - 1.5), _p("rust1"))
	r(c, x + w / 2 - 2, y + 3, 6, 3, _p("conc4"))              # etiqueta


static func cans(c: CanvasItem, x: int, y: int, n: int) -> void:
	var cols := [_p("tomato"), _p("cloth2"), _p("amber2"), _p("conc3")]
	for i in n:
		r(c, x + i * 4, y - 4, 3, 4, cols[i % 4])
		px(c, x + i * 4, y - 4, _p("conc4"))


## Poste de escora (madeira) entre o chão e o teto da escavação.
static func prop(c: CanvasItem, x: int, y0: int, y1: int) -> void:
	frame(c, x, y0, 4, y1 - y0, _p("ink"))
	r(c, x, y0, 4, y1 - y0, _p("rust2"))
	vl(c, x, y0, y1 - y0, _p("rust4"))
	vl(c, x + 3, y0, y1 - y0, _p("rust1"))


static func beam(c: CanvasItem, x0: int, x1: int, y: int) -> void:
	frame(c, x0, y, x1 - x0, 4, _p("ink"))
	r(c, x0, y, x1 - x0, 4, _p("rust2"))
	hl(c, x0, y, x1 - x0, _p("rust4"))
	hl(c, x0, y + 3, x1 - x0, _p("rust1"))


static func shovel(c: CanvasItem, x: int, yf: int) -> void:
	c.draw_line(Vector2(x + 6.5, yf - 17.5), Vector2(x + 0.5, yf - 1.5), _p("rust2"))
	r(c, x - 2, yf - 4, 6, 4, _p("conc3"))
