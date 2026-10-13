class_name PantryStock
extends Node2D
## O estoque visível: os cestos colhidos nas prateleiras e caixas da despensa (andar B). É a "mochila"
## do bunker: quanto mais cheio o estoque em relação à capacidade, mais cestos aparecem; acima da
## capacidade eles vão para o chão. Só lê o estado (link.box_stock / box_fill).

const SHELF_X := 80          # relativo a room_x0(1): prateleira do meio, duas tábuas de 4 cestos
const BOARDS := [22, 6]      # altura das tábuas acima do chão da despensa
const CRATE_TOPS := [[120, 10], [136, 10], [128, 21]]   # [x, altura acima do chão]
const FLOOR_X := [100, 108, 144, 152]                    # cestos soltos (acima da capacidade)
const REFRESH_SEC := 0.3

var view: BunkerView
var _t: float = 0.0
var _slots: int = -1
var _floor: int = -1


func _ready() -> void:
	z_index = 1


func shown_slots() -> int:
	return maxi(0, _slots)


func _process(delta: float) -> void:
	_t += delta
	if _t < REFRESH_SEC:
		return
	_t = 0.0
	if view == null or view.link == null:
		return
	var stock: int = view.link.box_stock()
	var fill: float = view.link.box_fill()
	var total: int = 8 + CRATE_TOPS.size()
	var n: int = 0
	if stock > 0:
		n = clampi(ceili(minf(fill, 1.0) * float(total)), 1, total)
	var extra: int = clampi(int((fill - 1.0) * 8.0) + (1 if fill > 1.0 else 0), 0, FLOOR_X.size()) if fill > 1.0 else 0
	if n != _slots or extra != _floor:
		_slots = n
		_floor = extra
		queue_redraw()


func _draw() -> void:
	if _slots <= 0:
		return
	var x0: int = BunkerGeo.room_x0(1)
	var fy: int = BunkerGeo.FEET_Y_B
	var i := 0
	for b: int in BOARDS:
		for k in 4:
			if i >= _slots:
				return
			BunkerDecor.basket(self, x0 + SHELF_X + 1 + k * 6, fy - b)
			i += 1
	for ct: Array in CRATE_TOPS:
		if i >= _slots:
			break
		BunkerDecor.basket(self, x0 + int(ct[0]) + 2, fy - int(ct[1]))
		i += 1
	for k in _floor:
		BunkerDecor.basket(self, x0 + int(FLOOR_X[k]), fy)
