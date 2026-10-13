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
	var drawing_dig: bool = dig_room > n_rooms and dig_ratio > 0.0
	var floors: int = dig_room if (dig_room > n_rooms) else n_rooms   # a faixa já cresce quando a escavação começa
	var h: int = BunkerGeo.height(floors)
	var w := maxi(width, BunkerGeo.strip_width(n_rooms))
	# grama
	var gx := 0
	while gx < w:
		_tile("grass_%d" % GRASS_SEQ[(gx / 16) % GRASS_SEQ.size()], Vector2(gx, BunkerGeo.GRASS_Y))
		gx += 16
	# terra maciça em toda a banda; os cômodos pintam por cima
	var y := BunkerGeo.ROOM_Y
	while y < h:
		var x := 0
		while x < w:
			var hh := _hash(x / 16, y / 16)
			_tile("earth_%d" % (hh % 4), Vector2(x, y))
			if hh % 11 == 0:
				_tile("earth_deco_%d" % (hh % 3), Vector2(x, y))
			x += 16
		y += 16
	# despensa (andar B, fixo)
	_draw_pantry(w, h)
	# andar de cima e as salas cavadas para baixo
	for r in range(1, n_rooms + 1):
		_draw_room(r, BunkerGeo.room_width(r))
		_draw_wall(r)
	if drawing_dig:
		_draw_room(dig_room, int(floorf(BunkerGeo.room_width(dig_room) * dig_ratio / 16.0)) * 16)
	# poço da escada: do alçapão até o andar mais fundo
	var bottom: int = BunkerGeo.feet_y(floors) if floors > 1 else BunkerGeo.FEET_Y_B
	var ly := BunkerGeo.ROOM_Y
	while ly < bottom:
		var seg := mini(16, bottom - ly)
		if seg == 16:
			_tile("ladder", Vector2(BunkerGeo.col_x(1, 0), ly))
		else:
			_tile_part("ladder", Vector2(BunkerGeo.col_x(1, 0), ly), Rect2(0, 0, 16, seg))
		ly += 16


## Um andar com seus cômodos lado a lado: cada um com material de parede e de chão próprios e uma parede com
## porta entre eles. `open_w` = quanto do andar já está aberto (a escavação abre da esquerda para a direita).
## `dy` = deslocamento do andar da sala; salas 2+ têm o teto cortado como o da despensa (laje de 6 px).
func _draw_room(r: int, open_w: int) -> void:
	var x0 := BunkerGeo.room_x0(r)
	var zs: Array[Dictionary] = BunkerGeo.zones(r)
	for z: Dictionary in zs:
		var zx0: int = int(z["x0"]) - x0
		if zx0 >= open_w:
			break
		var zx1: int = int(z["x1"]) - x0
		_draw_zone(r, z, mini(zx1, open_w))
		if int(z["idx"]) < zs.size() - 1 and zx1 + BunkerGeo.ZONE_WALL <= open_w:
			_draw_zone_wall(r, x0 + zx1)


func _draw_zone(r: int, z: Dictionary, open_w: int) -> void:
	var zx0: int = int(z["x0"])
	var fn: String = String(z["fn"])
	var dy := BunkerGeo.floor_dy(r)
	var i := r - 1
	var wy := BunkerGeo.wall_y(r)
	var fy := BunkerGeo.feet_y(r)
	var col0: int = int(z["col0"])
	var cx := 0
	while cx < open_w:
		var c := col0 + cx / 16
		var x := zx0 + cx
		var cname := "ceiling_%d" % (1 if (c + i) % 3 == 0 else 0)
		if r == 1:
			_tile(cname, Vector2(x, BunkerGeo.ROOM_Y))
		else:
			_tile_part(cname, Vector2(x, BunkerGeo.room_y(r) + 2), Rect2(0, 2, 16, BunkerGeo.SLAB_B))
		_tile("wall_%d" % WALL_ROW[(c + i * 5) % 12], Vector2(x, wy))
		_tile("wall_%d" % WALL_ROW2[(c + i * 3) % 12], Vector2(x, wy + 16))
		_tile_part("wall_%d" % WALL_ROW3[(c + i * 7) % 12], Vector2(x, wy + 32), Rect2(0, 0, 16, 8))
		_tile_part("floor_%d" % (1 if (c + i) % 5 == 2 else 0), Vector2(x, fy), Rect2(0, 0, 16, BunkerGeo.FLOOR_H))
		cx += 16
	var x1 := zx0 + open_w
	match fn:
		"horta":
			BunkerDecor.tiles_wall(self, zx0, wy, x1, fy)
		"quarto", "casa":
			BunkerDecor.wood_panels(self, zx0, 62 + dy, x1, fy)
			BunkerDecor.plank_floor(self, zx0, fy, x1, BunkerGeo.FLOOR_H)
		_:
			_tint(Rect2(zx0, wy, open_w, 40), BunkerGeo.pal("amber2"), 0.07)
	_shade(Rect2(zx0, wy, open_w, 2), 0.35)
	_shade(Rect2(zx0, fy - 3, open_w, 3), 0.18)
	BunkerDecor.ceiling_runs(self, zx0, x1, wy + 1)
	if open_w >= int(z["x1"]) - zx0:
		_draw_zone_decor(r, z, dy)


## Enfeites de parede de cada cômodo (as placas de nome ficam no canto de cima, à esquerda: ver RoomPlates).
func _draw_zone_decor(r: int, z: Dictionary, dy: int) -> void:
	var zx: int = int(z["x0"])
	var fy := BunkerGeo.FEET_Y + dy
	match String(z["fn"]):
		"escotilha":
			BunkerDecor.wall_map(self, zx + 56, 46 + dy)
			BunkerDecor.calendar(self, zx + 80, 47 + dy)
		"oficina":
			BunkerDecor.pegboard(self, zx + 56, 46 + dy)
			BunkerDecor.tally(self, zx + 8, 62 + dy, 12)
		"horta":
			if r == 1:
				BunkerDecor.valve_pipe(self, zx + 3, BunkerGeo.WALL_Y + dy + 4, fy)
				BunkerDecor.growth_chart(self, zx + 70, 47 + dy)
				BunkerDecor.growth_chart(self, zx + 122, 49 + dy)
			else:
				BunkerDecor.valve_pipe(self, zx + 20, BunkerGeo.WALL_Y + dy + 4, fy)
				BunkerDecor.growth_chart(self, zx + 62, 47 + dy)
				BunkerDecor.growth_chart(self, zx + 100, 49 + dy)
		"quarto":
			BunkerDecor.picture(self, zx + 56, 46 + dy, 14, 11)
			BunkerDecor.calendar(self, zx + 90, 47 + dy)
			BunkerDecor.r(self, zx + 24, fy, 40, 1, BunkerGeo.pal("tomato"))
			BunkerDecor.r(self, zx + 24, fy + 1, 40, 1, BunkerGeo.pal("amber2"))
		"casa":
			BunkerDecor.picture(self, zx + 56, 46 + dy, 14, 11)
			BunkerDecor.picture(self, zx + 78, 48 + dy, 10, 13)
			BunkerDecor.calendar(self, zx + 100, 47 + dy)
			BunkerDecor.tally(self, zx + 24, 66 + dy, 23)
			BunkerDecor.r(self, zx + 36, fy, 56, 1, BunkerGeo.pal("tomato"))
			BunkerDecor.r(self, zx + 36, fy + 1, 56, 1, BunkerGeo.pal("amber2"))


## Parede (com porta de aço) entre dois cômodos do mesmo andar; piso e laje seguem por baixo e por cima.
func _draw_zone_wall(r: int, xd: int) -> void:
	var y0 := BunkerGeo.room_y(r) if r == 1 else BunkerGeo.room_y(r) + 2
	var fy := BunkerGeo.feet_y(r)
	BunkerDecor.wall_with_door(self, xd, y0, fy, true)
	_tile_part("floor_0", Vector2(xd, fy), Rect2(0, 0, 8, BunkerGeo.FLOOR_H))
	if r > 1:
		_tile_part("ceiling_0", Vector2(xd, BunkerGeo.room_y(r) + 2), Rect2(0, 2, 8, BunkerGeo.SLAB_B))


## Parede grossa de concreto fechando a sala à direita (os andares não se ligam de lado).
func _draw_wall(r: int) -> void:
	var xd := BunkerGeo.divider_x(r)
	var y0 := BunkerGeo.room_y(r) if r == 1 else BunkerGeo.room_y(r) + 2
	var fy := BunkerGeo.feet_y(r)
	BunkerDecor.wall_with_door(self, xd, y0, fy, false)
	_tile_part("floor_0", Vector2(xd, fy), Rect2(0, 0, 8, BunkerGeo.FLOOR_H))
	if r > 1:
		_tile_part("ceiling_0", Vector2(xd, BunkerGeo.room_y(r) + 2), Rect2(0, 2, 8, BunkerGeo.SLAB_B))


## Andar B: a despensa (estoque). Os cestos são desenhados à parte (PantryStock), conforme o estoque.
func _draw_pantry(w: int, _h: int) -> void:
	var x0 := BunkerGeo.room_x0(1)
	var x1 := x0 + BunkerGeo.PANTRY_W
	var ceil_y := BunkerGeo.FEET_Y + BunkerGeo.FLOOR_H
	_shade(Rect2(x0 - 1, ceil_y, BunkerGeo.PANTRY_W + 2, BunkerGeo.FLOOR_DY), 0.6)
	var cx := 0
	while cx < BunkerGeo.PANTRY_W:
		var c := cx / 16
		var x := x0 + cx
		_tile_part("ceiling_%d" % (1 if c % 3 == 1 else 0), Vector2(x, ceil_y), Rect2(0, 2, 16, BunkerGeo.SLAB_B))
		_tile("wall_%d" % WALL_ROW[(c + 3) % 12], Vector2(x, BunkerGeo.WALL_Y_B))
		_tile("wall_%d" % WALL_ROW2[(c + 4) % 12], Vector2(x, BunkerGeo.WALL_Y_B + 16))
		_tile_part("wall_%d" % WALL_ROW3[(c + 2) % 12], Vector2(x, BunkerGeo.WALL_Y_B + 32), Rect2(0, 0, 16, 8))
		_tile_part("floor_0", Vector2(x, BunkerGeo.FEET_Y_B), Rect2(0, 0, 16, BunkerGeo.FLOOR_H))
		cx += 16
	_tint(Rect2(x0, BunkerGeo.WALL_Y_B, BunkerGeo.PANTRY_W, 40), BunkerGeo.pal("ink"), 0.22)
	_shade(Rect2(x0, BunkerGeo.WALL_Y_B, BunkerGeo.PANTRY_W, 2), 0.35)
	var fy := BunkerGeo.FEET_Y_B
	BunkerDecor.ceiling_runs(self, x0, x1, BunkerGeo.WALL_Y_B + 1)
	# prateleiras: a da esquerda com latas (conserva), a do meio fica livre para os cestos; caixas e a cisterna
	_tile_part("prateleira", Vector2(x0 + 36, fy - 32), Rect2(0, 0, 32, 32))
	BunkerDecor.cans(self, x0 + 40, fy - 22, 7)
	BunkerDecor.cans(self, x0 + 40, fy - 6, 5)
	_tile_part("prateleira", Vector2(x0 + 76, fy - 32), Rect2(0, 0, 32, 32))
	BunkerDecor.crate(self, x0 + 118, fy)
	BunkerDecor.crate(self, x0 + 134, fy)
	BunkerDecor.crate(self, x0 + 126, fy - 11)
	BunkerDecor.crate(self, x0 + 150, fy, 12, 9)
	_tile_part("cisterna", Vector2(x0 + 160, fy - 32), Rect2(0, 0, 32, 32))
	BunkerDecor.wall_with_door(self, x1, ceil_y, fy, false)
	_tile_part("floor_0", Vector2(x1, fy), Rect2(0, 0, 8, BunkerGeo.FLOOR_H))
	_tile_part("ceiling_0", Vector2(x1, ceil_y), Rect2(0, 2, 8, BunkerGeo.SLAB_B))
	# cano velho enterrado sob o resto da terra
	var px0 := x1 + 8
	if px0 < w:
		draw_rect(Rect2(px0, fy - 8, w - px0, 1), BunkerGeo.pal("dark2"))
		draw_rect(Rect2(px0, fy - 7, w - px0, 1), BunkerGeo.pal("conc1"))
