class_name BunkerTerrain
extends Node2D
## Fundo fixo da faixa: grama, terra maciça (o que não foi escavado), salas (teto, parede, chão),
## divisórias com porta e a escada no poço. Redesenha só quando muda o nº de salas, a largura
## ou o avanço de uma escavação.

const GRASS_SEQ := [0, 1, 0, 2, 1, 0, 2, 0]
const WALL_ROW := [0, 0, 1, 0, 0, 2, 0, 3, 0, 0, 1, 0]
const WALL_ROW2 := [0, 2, 0, 1, 0, 0, 3, 0, 2, 0, 0, 1]
const WALL_ROW3 := [1, 0, 0, 2, 0, 0, 0, 3, 0, 1, 0, 0]

var n_rooms: int = 1
var width: int = BunkerGeo.MIN_W
## Escavação em andamento: sala nova e fração aberta (0..1). dig_room = 0 => nenhuma.
var dig_room: int = 0
var dig_ratio: float = 0.0


func setup(rooms: int, w: int, digging_room: int = 0, ratio: float = 0.0) -> void:
	var q := snappedf(ratio, 1.0 / 24.0)
	if rooms == n_rooms and w == width and digging_room == dig_room and is_equal_approx(q, dig_ratio):
		return
	n_rooms = rooms
	width = w
	dig_room = digging_room
	dig_ratio = q
	queue_redraw()


static func _hash(x: int, y: int) -> int:
	return absi((x * 374761393 + y * 668265263) ^ 0x5bd1e995) % 1009


func _tile(n: String, p: Vector2, frame: int = 0) -> void:
	var tex := BunkerArt.texture(n)
	if tex != null:
		draw_texture_rect_region(tex, Rect2(p, BunkerArt.frame_size(n)), BunkerArt.region(n, frame))


func _tile_part(n: String, p: Vector2, src: Rect2) -> void:
	var tex := BunkerArt.texture(n)
	if tex != null:
		draw_texture_rect_region(tex, Rect2(p, src.size), src)


func _shade(rect: Rect2, a: float) -> void:
	var c := BunkerGeo.pal("ink")
	c.a = a
	draw_rect(rect, c)


func _tint(rect: Rect2, col: Color, a: float) -> void:
	col.a = a
	draw_rect(rect, col)


func _draw() -> void:
	var w := maxi(width, BunkerGeo.strip_width(n_rooms))
	# grama
	var gx := 0
	while gx < w:
		_tile("grass_%d" % GRASS_SEQ[(gx / 16) % GRASS_SEQ.size()], Vector2(gx, BunkerGeo.GRASS_Y))
		gx += 16
	# terra maciça em toda a banda; os cômodos pintam por cima
	var y := BunkerGeo.ROOM_Y
	while y < BunkerGeo.H:
		var x := 0
		while x < w:
			var h := _hash(x / 16, y / 16)
			_tile("earth_%d" % (h % 4), Vector2(x, y))
			if h % 11 == 0:
				_tile("earth_deco_%d" % (h % 3), Vector2(x, y))
			x += 16
		y += 16
	# andar de baixo (despensa e escavação)
	_draw_floor_b(w)
	# andar de cima
	for r in range(1, n_rooms + 1):
		_draw_room(r, BunkerGeo.ROOM_W)
	if dig_room > n_rooms and dig_ratio > 0.0:
		_draw_room(dig_room, int(floorf(BunkerGeo.ROOM_W * dig_ratio / 16.0)) * 16)
	for r in range(1, n_rooms):
		_draw_divider(r)
	if dig_room > n_rooms and dig_ratio > 0.0:
		_draw_divider(dig_room - 1)
	# canos e fios ao longo do teto, atravessando os cômodos
	BunkerDecor.ceiling_runs(self, BunkerGeo.room_x0(1), BunkerGeo.room_x0(n_rooms) + BunkerGeo.ROOM_W, BunkerGeo.WALL_Y + 1)
	# poço da escada: do alçapão até o andar de baixo
	for ly in [32, 48, 64, 80, 96, 112]:
		_tile("ladder", Vector2(BunkerGeo.col_x(1, 0), ly))
	_tile_part("ladder", Vector2(BunkerGeo.col_x(1, 0), 128), Rect2(0, 0, 16, BunkerGeo.FEET_Y_B - 128))


func _draw_room(r: int, open_w: int) -> void:
	var x0 := BunkerGeo.room_x0(r)
	var i := r - 1
	var theme := (r - 1) % 3          # 0 oficina (entrada), 1 estufa, 2 quarto
	var cx := 0
	while cx < open_w:
		var c := cx / 16
		var x := x0 + cx
		_tile("ceiling_%d" % (1 if (c + i) % 3 == 0 else 0), Vector2(x, BunkerGeo.ROOM_Y))
		_tile("wall_%d" % WALL_ROW[(c + i * 5) % 12], Vector2(x, 40))
		_tile("wall_%d" % WALL_ROW2[(c + i * 3) % 12], Vector2(x, 56))
		_tile_part("wall_%d" % WALL_ROW3[(c + i * 7) % 12], Vector2(x, 72), Rect2(0, 0, 16, 8))
		_tile_part("floor_%d" % (1 if (c + i) % 5 == 2 else 0), Vector2(x, BunkerGeo.FEET_Y), Rect2(0, 0, 16, BunkerGeo.FLOOR_H))
		cx += 16
	var x1 := x0 + open_w
	match theme:
		0:
			_tint(Rect2(x0, 40, open_w, 40), BunkerGeo.pal("amber2"), 0.07)
		1:
			BunkerDecor.tiles_wall(self, x0, BunkerGeo.WALL_Y, x1, BunkerGeo.FEET_Y)
		2:
			BunkerDecor.wood_panels(self, x0, 62, x1, BunkerGeo.FEET_Y)
			BunkerDecor.plank_floor(self, x0, BunkerGeo.FEET_Y, x1, BunkerGeo.FLOOR_H)
	_shade(Rect2(x0, BunkerGeo.WALL_Y, open_w, 2), 0.35)
	_shade(Rect2(x0, BunkerGeo.FEET_Y - 3, open_w, 3), 0.18)
	if open_w >= BunkerGeo.ROOM_W:
		_draw_room_decor(r, theme, x0)


func _draw_room_decor(_r: int, theme: int, x0: int) -> void:
	match theme:
		0:
			BunkerDecor.wall_map(self, x0 + 50, 46)
			BunkerDecor.calendar(self, x0 + 84, 47)
			BunkerDecor.tally(self, x0 + 103, 50, 12)
			BunkerDecor.pegboard(self, x0 + 128, 46)
			# cantinho de dormir: lambri de madeira atrás da cama
			BunkerDecor.wood_panels(self, x0 + 160, 62, x0 + 192, BunkerGeo.FEET_Y)
			BunkerDecor.picture(self, x0 + 168, 46, 13, 10)
		1:
			BunkerDecor.valve_pipe(self, x0 + 3, BunkerGeo.WALL_Y + 4, BunkerGeo.FEET_Y)
			BunkerDecor.growth_chart(self, x0 + 66, 47)
			BunkerDecor.growth_chart(self, x0 + 130, 49)
		2:
			BunkerDecor.picture(self, x0 + 20, 46, 14, 11)
			BunkerDecor.picture(self, x0 + 42, 48, 10, 13)
			BunkerDecor.calendar(self, x0 + 88, 47)
			BunkerDecor.tally(self, x0 + 112, 50, 23)
			BunkerDecor.r(self, x0 + 52, BunkerGeo.FEET_Y, 60, 1, BunkerGeo.pal("tomato"))
			BunkerDecor.r(self, x0 + 52, BunkerGeo.FEET_Y + 1, 60, 1, BunkerGeo.pal("amber2"))


func _draw_divider(r: int) -> void:
	var xd := BunkerGeo.divider_x(r)
	BunkerDecor.wall_with_door(self, xd, BunkerGeo.ROOM_Y, BunkerGeo.FEET_Y)
	_tile_part("floor_0", Vector2(xd, BunkerGeo.FEET_Y), Rect2(0, 0, 8, BunkerGeo.FLOOR_H))


## Andar de baixo: despensa sob a sala 1 e, quando existe a sala 2, uma escavação em andamento
## (escoras de madeira). Sob o resto, terra com pedra, raiz e um cano velho.
func _draw_floor_b(w: int) -> void:
	var x0 := BunkerGeo.room_x0(1)
	var x1 := x0 + BunkerGeo.ROOM_W
	var ceil_y := BunkerGeo.FEET_Y + BunkerGeo.FLOOR_H
	# laje e cômodo da despensa
	_shade(Rect2(x0 - 1, ceil_y, BunkerGeo.ROOM_W + 2, BunkerGeo.H - ceil_y), 0.6)
	var cx := 0
	while cx < BunkerGeo.ROOM_W:
		var c := cx / 16
		var x := x0 + cx
		_tile_part("ceiling_%d" % (1 if c % 3 == 1 else 0), Vector2(x, ceil_y), Rect2(0, 2, 16, BunkerGeo.SLAB_B))
		_tile("wall_%d" % WALL_ROW[(c + 3) % 12], Vector2(x, BunkerGeo.WALL_Y_B))
		_tile("wall_%d" % WALL_ROW2[(c + 4) % 12], Vector2(x, BunkerGeo.WALL_Y_B + 16))
		_tile_part("wall_%d" % WALL_ROW3[(c + 2) % 12], Vector2(x, BunkerGeo.WALL_Y_B + 32), Rect2(0, 0, 16, 8))
		_tile_part("floor_0", Vector2(x, BunkerGeo.FEET_Y_B), Rect2(0, 0, 16, BunkerGeo.FLOOR_H))
		cx += 16
	_tint(Rect2(x0, BunkerGeo.WALL_Y_B, BunkerGeo.ROOM_W, 40), BunkerGeo.pal("ink"), 0.22)
	_shade(Rect2(x0, BunkerGeo.WALL_Y_B, BunkerGeo.ROOM_W, 2), 0.35)
	var fy := BunkerGeo.FEET_Y_B
	BunkerDecor.ceiling_runs(self, x0, x1, BunkerGeo.WALL_Y_B + 1)
	# prateleiras com latas, caixas etiquetadas e a cisterna
	_tile_part("prateleira", Vector2(x0 + 36, fy - 32), Rect2(0, 0, 32, 32))
	BunkerDecor.cans(self, x0 + 40, fy - 22, 7)
	BunkerDecor.cans(self, x0 + 40, fy - 6, 5)
	_tile_part("prateleira", Vector2(x0 + 76, fy - 32), Rect2(0, 0, 32, 32))
	BunkerDecor.cans(self, x0 + 80, fy - 22, 6)
	BunkerDecor.cans(self, x0 + 80, fy - 6, 7)
	BunkerDecor.crate(self, x0 + 118, fy)
	BunkerDecor.crate(self, x0 + 134, fy)
	BunkerDecor.crate(self, x0 + 126, fy - 11)
	BunkerDecor.crate(self, x0 + 150, fy, 12, 9)
	_tile_part("cisterna", Vector2(x0 + 160, fy - 32), Rect2(0, 0, 32, 32))
	# divisória (com porta) e a escavação sob a sala 2
	var xd := x1
	BunkerDecor.wall_with_door(self, xd, ceil_y, fy)
	_tile_part("floor_0", Vector2(xd, fy), Rect2(0, 0, 8, BunkerGeo.FLOOR_H))
	_tile_part("ceiling_0", Vector2(xd, ceil_y), Rect2(0, 2, 8, BunkerGeo.SLAB_B))
	var ex0 := BunkerGeo.room_x0(2)
	if n_rooms >= 2:
		var ew := BunkerGeo.ROOM_W
		_shade(Rect2(ex0, ceil_y - 2, ew, BunkerGeo.H - ceil_y + 2), 0.55)
		var xx := ex0
		while xx < ex0 + ew:
			_tile_part("earth_%d" % (_hash(xx / 16, 9) % 4), Vector2(xx, fy), Rect2(0, 0, 16, BunkerGeo.FLOOR_H))
			xx += 16
		for k in 70:
			var rx := ex0 + _hash(k, 3) % ew
			var ry := ceil_y + _hash(k, 7) % (BunkerGeo.WALL_Y_B - ceil_y)
			draw_rect(Rect2(rx, ry, 1, 1), BunkerGeo.pal("dark1") if k % 2 == 0 else BunkerGeo.pal("dark3"))
		BunkerDecor.beam(self, ex0, ex0 + ew, BunkerGeo.WALL_Y_B - 5)
		for px_ in [28, 82, 136]:
			BunkerDecor.prop(self, ex0 + px_, BunkerGeo.WALL_Y_B - 3, fy)
		_tile_part("scrap_pile", Vector2(ex0 + 44 - 8, fy - 16), Rect2(16, 0, 16, 16))
		_tile_part("scrap_pile", Vector2(ex0 + 112 - 8, fy - 16), Rect2(0, 0, 16, 16))
		BunkerDecor.shovel(self, ex0 + 92, fy)
	# cano velho enterrado sob o resto da terra
	var px0 := ex0 + (BunkerGeo.ROOM_W + 8 if n_rooms >= 2 else 0)
	if px0 < w:
		draw_rect(Rect2(px0, fy - 8, w - px0, 1), BunkerGeo.pal("dark2"))
		draw_rect(Rect2(px0, fy - 7, w - px0, 1), BunkerGeo.pal("conc1"))
