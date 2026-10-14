class_name BunkerGeo
extends RefCounted
## Geometria da faixa do bunker (CONTRATOS seção 3) e paleta para desenhos feitos por código.
## Salas são numeradas 1..3 como na API do Game; sala 1 começa em x = 8.

const H := 136              ## altura da faixa: superfície + andar de cima (A) + andar de baixo (B)
const SKY_H := 24
const GRASS_Y := 24
const ROOM_Y := 32          # topo do teto
const WALL_Y := 40          # topo da parede do fundo
const FEET_Y := 80          # linha dos pés / topo do chão
## Andar de baixo (B): mesma geometria do A deslocada. Entre os dois fica a laje (chão do A com 5 px +
## teto do B com 6 px).
const FLOOR_DY := 51
const ROOM_Y_B := ROOM_Y + FLOOR_DY     # topo do teto do B (o teto do B é cortado em 6 px)
const WALL_Y_B := WALL_Y + FLOOR_DY
const FEET_Y_B := FEET_Y + FLOOR_DY
const FLOOR_H := 5          ## altura visível do piso (tile de 8, cortado)
const SLAB_B := 6           ## altura visível do teto do B
const COL := 16
const COLS := 12
const PANTRY_W := 192       ## largura da despensa (andar B)
const MARGIN := 8
const DIVIDER_W := 8        ## parede grossa que fecha o andar à direita
const ZONE_WALL := 8        ## parede (com porta) entre dois cômodos do mesmo andar
const WIN_W := 344          ## largura da janela (a faixa): o bunker é mais largo e rola para os lados
const MIN_W := 344
const MAX_ROOMS := 3
const ANTENNA_X := 56
const PANEL_X := 88
const HATCH_X := 8
const PANTRY_X := 100       ## x onde ele fica diante das prateleiras da despensa

## Cores da paleta fixa (tools/art/palette.py). `signal` só em sinais de atenção.
const PAL := {
	"ink": Color("#14110f"), "dark1": Color("#2a2420"), "dark2": Color("#3d352e"), "dark3": Color("#554a40"),
	"conc1": Color("#6e6359"), "conc2": Color("#8c8174"), "conc3": Color("#a99f90"), "conc4": Color("#c9bfae"),
	"rust1": Color("#5a2e1f"), "rust2": Color("#8a4a2a"), "rust3": Color("#b5683a"), "rust4": Color("#d98c4f"),
	"amber1": Color("#a8741c"), "amber2": Color("#e0a52e"), "amber3": Color("#f6d36b"), "amber4": Color("#fff0b8"),
	"leaf1": Color("#2f4a2a"), "leaf2": Color("#4f7a37"), "leaf3": Color("#7fa650"), "leaf4": Color("#b2c978"),
	"skin1": Color("#a9704f"), "skin2": Color("#d9a37a"), "cloth1": Color("#3a4a5c"), "cloth2": Color("#6f8aa3"),
	"paper": Color("#e9e2d0"), "tomato": Color("#b8402e"), "bean": Color("#8a5a3c"), "signal": Color("#5dff8a"),
}

const BAYER := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


static func pal(name: String) -> Color:
	return PAL.get(name, Color.MAGENTA)


## Limiar de Bayer 4x4 em 0..1 (para degradês com dither).
static func bayer(x: int, y: int) -> float:
	return (float(BAYER[posmod(y, 4)][posmod(x, 4)]) + 0.5) / 16.0


## Andares: A (sala 1), B (despensa, fixa) e depois uma sala nova por andar, cavada PARA BAIXO:
## sala 2 no andar C, sala 3 no andar D. Todas começam em x = MARGIN e dividem o poço da escada (coluna 0).
static func room_floor(room: int) -> int:
	return 0 if room <= 1 else room


## Deslocamento vertical do andar da sala.
static func floor_dy(room: int) -> int:
	return room_floor(room) * FLOOR_DY


static func room_x0(_room: int) -> int:
	return MARGIN


## Cômodos (zonas) de um andar, da esquerda para a direita: [{id, fn, col0, cols, x0, x1, idx}] com x0..x1 o
## interior em px do mundo (sem as paredes entre eles). Vêm do balance.json (rooms.layout).
static func zones(room: int) -> Array[Dictionary]:
	Balance.ensure_loaded()
	var out: Array[Dictionary] = []
	var x: int = room_x0(room)
	var i: int = 0
	for z: Dictionary in Balance.room_zones(room):
		var w: int = int(z["cols"]) * COL
		out.append({"id": z["id"], "fn": z["fn"], "col0": z["col0"], "cols": z["cols"], "x0": x, "x1": x + w, "idx": i})
		x += w + ZONE_WALL
		i += 1
	return out


## Largura (px) do andar da sala: os cômodos mais as paredes entre eles.
static func room_width(room: int) -> int:
	var zs: Array[Dictionary] = zones(room)
	return 0 if zs.is_empty() else int(zs[zs.size() - 1]["x1"]) - room_x0(room)


## Cômodo que contém a coluna (índice em zones()), ou -1.
static func zone_index_of_col(room: int, col: int) -> int:
	for z: Dictionary in zones(room):
		if col >= int(z["col0"]) and col < int(z["col0"]) + int(z["cols"]):
			return int(z["idx"])
	return -1


## Largura do mundo (px): o andar mais largo (o de cima) mais a parede da direita.
static func strip_width(_n_rooms: int = 1) -> int:
	return room_x0(1) + room_width(1) + DIVIDER_W


## Altura da faixa com `n_rooms` salas (a despensa já conta no andar B).
static func height(n_rooms: int) -> int:
	return H + maxi(0, mini(n_rooms, MAX_ROOMS) - 1) * FLOOR_DY


## x esquerdo da coluna (conta as paredes entre os cômodos).
static func col_x(room: int, col: int) -> int:
	var zi: int = zone_index_of_col(room, col)
	return room_x0(room) + col * COL + maxi(0, zi) * ZONE_WALL


static func feet_y(room: int) -> int:
	return FEET_Y + floor_dy(room)


static func wall_y(room: int) -> int:
	return WALL_Y + floor_dy(room)


static func room_y(room: int) -> int:
	return ROOM_Y + floor_dy(room)


## Ponto dos pés (base-centro) de um bloco de colunas.
static func block_foot(room: int, col: int, cols: int) -> Vector2:
	return Vector2(col_x(room, col) + maxi(cols, 1) * COL * 0.5, feet_y(room))


## Retângulo interno (parede até o chão) de um bloco de colunas.
static func block_rect(room: int, col: int, cols: int) -> Rect2:
	return Rect2(col_x(room, col), wall_y(room), maxi(cols, 1) * COL, FEET_Y - WALL_Y)


static func room_rect(room: int) -> Rect2:
	return Rect2(room_x0(room), room_y(room), room_width(room), FLOOR_DY)


## Sala e coluna sob um ponto (dentro de um cômodo de uma sala existente), ou (-1, -1). A despensa não é sala.
static func room_col_at(p: Vector2, n_rooms: int) -> Vector2i:
	for r in range(1, n_rooms + 1):
		var y0 := room_y(r)
		var y1 := y0 + FLOOR_DY if r > 1 else ROOM_Y + FLOOR_DY + 1
		if p.y < y0 or p.y >= y1:
			continue
		for z: Dictionary in zones(r):
			if p.x >= float(z["x0"]) and p.x < float(z["x1"]):
				return Vector2i(r, int(z["col0"]) + int((p.x - float(z["x0"])) / COL))
	return Vector2i(-1, -1)


## Lâmpadas da faixa: [{pos, room, fn}] com room 0 = despensa. Uma por cômodo e uma na despensa.
static func lamps(n_rooms: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in range(1, n_rooms + 1):
		for z: Dictionary in zones(r):
			out.append({"pos": Vector2((float(z["x0"]) + float(z["x1"])) * 0.5, wall_y(r)), "room": r, "fn": String(z["fn"])})
		if r == 1:
			out.append({"pos": Vector2(col_x(1, 7) + 8, WALL_Y_B), "room": 0, "fn": "despensa"})
	return out


static func lamp_points(n_rooms: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for l in lamps(n_rooms):
		out.append(l["pos"])
	return out


## x esquerdo da parede da direita da sala.
static func divider_x(room: int) -> int:
	return room_x0(room) + room_width(room)
