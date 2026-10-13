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
const ROOM_W := 192
const ROOM_STEP := 200
const MARGIN := 8
const DIVIDER_W := 8
const MIN_W := 344
const MAX_ROOMS := 3
const ANTENNA_X := 56
const PANEL_X := 88
const HATCH_X := 8

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


static func room_x0(room: int) -> int:
	return MARGIN + (room - 1) * ROOM_STEP


static func strip_width(n_rooms: int) -> int:
	return MARGIN + n_rooms * ROOM_STEP


static func col_x(room: int, col: int) -> int:
	return room_x0(room) + col * COL


## Ponto dos pés (base-centro) de um bloco de colunas.
static func block_foot(room: int, col: int, cols: int) -> Vector2:
	return Vector2(col_x(room, col) + maxi(cols, 1) * COL * 0.5, FEET_Y)


## Retângulo interno (parede até o chão) de um bloco de colunas.
static func block_rect(room: int, col: int, cols: int) -> Rect2:
	return Rect2(col_x(room, col), WALL_Y, maxi(cols, 1) * COL, FEET_Y - WALL_Y)


static func room_rect(room: int) -> Rect2:
	return Rect2(room_x0(room), ROOM_Y, ROOM_W, H - ROOM_Y)


## Sala e coluna sob um ponto (dentro de uma sala existente), ou (-1, -1).
static func room_col_at(p: Vector2, n_rooms: int) -> Vector2i:
	if p.y < ROOM_Y or p.y >= H:
		return Vector2i(-1, -1)
	for r in range(1, n_rooms + 1):
		var x0 := room_x0(r)
		if p.x >= x0 and p.x < x0 + ROOM_W:
			return Vector2i(r, int((p.x - x0) / COL))
	return Vector2i(-1, -1)


## Centro (x) da lâmpada do teto da sala.
static func lamp_x(room: int) -> int:
	return col_x(room, 5 if room == 1 else 6) + 8


## Lâmpadas da faixa: uma por sala do andar de cima e as do andar de baixo (despensa; escavação
## quando existe a sala 2). Devolve a posição do topo (x central, y).
static func lamp_points(n_rooms: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for r in range(1, n_rooms + 1):
		out.append(Vector2(lamp_x(r), WALL_Y))
	out.append(Vector2(col_x(1, 7) + 8, WALL_Y_B))
	if n_rooms >= 2:
		out.append(Vector2(col_x(2, 6) + 8, WALL_Y_B + 6))
	return out


## x esquerdo da divisória à direita da sala.
static func divider_x(room: int) -> int:
	return room_x0(room) + ROOM_W
