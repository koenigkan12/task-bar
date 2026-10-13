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


func _draw() -> void:
	var w := maxi(width, BunkerGeo.strip_width(n_rooms))
	# grama
	var gx := 0
	while gx < w:
		_tile("grass_%d" % GRASS_SEQ[(gx / 16) % GRASS_SEQ.size()], Vector2(gx, BunkerGeo.GRASS_Y))
		gx += 16
	# terra maciça em toda a banda; as salas pintam por cima
	var y := BunkerGeo.ROOM_Y
	while y < BunkerGeo.H:
		var x := 0
		while x < w:
			var h := _hash(x / 16, y / 16)
			_tile("earth_%d" % (h % 4), Vector2(x, y))
			if h % 11 == 0 and not _in_room(x, y):
				_tile("earth_deco_%d" % (h % 3), Vector2(x, y))
			x += 16
		y += 16
	for r in range(1, n_rooms + 1):
		_draw_room(r, BunkerGeo.ROOM_W)
	if dig_room > n_rooms and dig_ratio > 0.0:
		_draw_room(dig_room, int(floorf(BunkerGeo.ROOM_W * dig_ratio / 16.0)) * 16)
	for r in range(1, n_rooms):
		_draw_divider(r)
	if dig_room > n_rooms and dig_ratio > 0.0:
		_draw_divider(dig_room - 1)
	# escada no poço (coluna 0 da sala 1), do teto ao chão
	for ly in [32, 48, 64]:
		_tile("ladder", Vector2(BunkerGeo.col_x(1, 0), ly))


func _in_room(x: int, y: int) -> bool:
	if y + 16 <= BunkerGeo.ROOM_Y:
		return false
	for r in range(1, n_rooms + 1):
		var x0 := BunkerGeo.room_x0(r) - 16
		if x >= x0 and x < x0 + BunkerGeo.ROOM_W + 32:
			return true
	return false


func _draw_room(r: int, open_w: int) -> void:
	var x0 := BunkerGeo.room_x0(r)
	var i := r - 1
	var cx := 0
	while cx < open_w:
		var c := cx / 16
		var x := x0 + cx
		_tile("ceiling_%d" % (1 if (c + i) % 3 == 0 else 0), Vector2(x, BunkerGeo.ROOM_Y))
		_tile("wall_%d" % WALL_ROW[(c + i * 5) % 12], Vector2(x, 40))
		_tile("wall_%d" % WALL_ROW2[(c + i * 3) % 12], Vector2(x, 56))
		_tile("wall_%d" % WALL_ROW3[(c + i * 7) % 12], Vector2(x, 72))
		_tile("floor_%d" % (1 if (c + i) % 5 == 2 else 0), Vector2(x, BunkerGeo.FEET_Y))
		cx += 16


func _draw_divider(r: int) -> void:
	var xd := BunkerGeo.divider_x(r)
	var wall := BunkerArt.texture("wall_0")
	if wall != null:
		for y in [48, 64]:
			draw_texture_rect_region(wall, Rect2(xd, y, 8, 16), Rect2(0, 0, 8, 16))
	_tile("divider", Vector2(xd, BunkerGeo.ROOM_Y))
