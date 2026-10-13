class_name DrawerPlacementOverlay
extends Control
## Camada transparente sobre a faixa do bunker enquanto a gaveta está aberta.
## Modo "place": desenha as posições válidas (placement_hints) e devolve a escolhida.
## Modo "select": realça os objetos sob o mouse e devolve o clicado (mover/desmontar/cultura).
## Geometria da seção 3 do contrato; a origem deste nó é o canto sup. esq. da faixa.

signal spot_picked(room: int, col: int)
signal instance_picked(instance_id: int)
signal cancelled()

## Geometria única da faixa: BunkerGeo (os andares são empilhados, a sala nova desce).
## Primeiro índice de sala da API (balance.json usa sala 1 para a primeira).
const ROOM_BASE: int = 1

var mode: String = ""          # "" | "place" | "select"
var cols: int = 1              # largura do bloco sendo posicionado
var hints: Array = []          # [{room,col}]
var targets: Array = []        # [{id,room,col,cols}]
var selected_id: int = -1
var _hover: int = -1
var _blink: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


static func block_rect(room: int, col: int, width_cols: int) -> Rect2:
	return BunkerGeo.block_rect(room, col, width_cols)


func show_hints(spots: Array, width_cols: int) -> void:
	mode = "place"
	hints = spots
	cols = width_cols
	_activate()


func show_targets(insts: Array, selected: int) -> void:
	mode = "select"
	targets = []
	for d: Dictionary in insts:
		if int(d.get("col", -1)) >= 0 and int(d.get("cols", 0)) > 0:
			targets.append(d)
	selected_id = selected
	_activate()


func clear() -> void:
	mode = ""
	hints = []
	targets = []
	_hover = -1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	queue_redraw()


func _activate() -> void:
	_hover = -1
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(mode == "place")
	queue_redraw()


func _rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if mode == "place":
		for h: Dictionary in hints:
			out.append(block_rect(int(h["room"]), int(h["col"]), cols))
	elif mode == "select":
		for t: Dictionary in targets:
			out.append(block_rect(int(t["room"]), int(t["col"]), int(t["cols"])))
	return out


func index_at(p: Vector2) -> int:
	var rs: Array[Rect2] = _rects()
	for i in rs.size():
		if rs[i].has_point(p):
			return i
	return -1


func _process(delta: float) -> void:
	_blink = fmod(_blink + delta, 1.2)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h: int = index_at((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			cancelled.emit()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			pick(index_at(mb.position))
		accept_event()


## Escolhe o alvo de índice i (também usado pelos testes).
func pick(i: int) -> void:
	if i < 0:
		return
	if mode == "place" and i < hints.size():
		spot_picked.emit(int(hints[i]["room"]), int(hints[i]["col"]))
	elif mode == "select" and i < targets.size():
		instance_picked.emit(int(targets[i]["id"]))


func _draw() -> void:
	var rs: Array[Rect2] = _rects()
	for i in rs.size():
		var r: Rect2 = rs[i]
		if mode == "place":
			# verde de sinal: é um convite a clicar (pulsa devagar)
			var a: float = 0.18 + 0.12 * absf(sin(_blink / 1.2 * PI))
			draw_rect(r, Color(UiTheme.SIGNAL, 0.45 if i == _hover else a))
			draw_rect(r.grow(-0.5), UiTheme.SIGNAL, false, 1.0)
		else:
			var is_sel: bool = int(targets[i]["id"]) == selected_id
			if is_sel:
				draw_rect(r.grow(-0.5), UiTheme.AMBER2, false, 1.0)
			elif i == _hover:
				draw_rect(r, Color(UiTheme.AMBER3, 0.15))
				draw_rect(r.grow(-0.5), UiTheme.CONC3, false, 1.0)
