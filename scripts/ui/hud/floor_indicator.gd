class_name FloorIndicator
extends Control
## Minimapa vertical minúsculo no canto da faixa: uma célula por andar, o retângulo claro é o que a janela
## mostra agora e o ponto é o Joaquim. Só aparece quando há o que rolar; clicar numa célula leva a vista até lá.

const CELL_W: int = 6
const SCALE: float = 0.125   # pixels do indicador por pixel do mundo
const PAD: int = 2
const W: int = CELL_W + PAD * 2

var view: BunkerView


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	visible = false
	set_process(true)


func _process(_delta: float) -> void:
	var show_it: bool = view != null and view.view_h > 0 and view.max_scroll() > 0.0
	if show_it != visible:
		visible = show_it
	if visible:
		_fit()
		queue_redraw()


func _fit() -> void:
	var h: float = float(view.world_height()) * SCALE
	custom_minimum_size = Vector2(CELL_W + PAD * 2, h + PAD * 2)
	size = custom_minimum_size


## Linhas (no mundo) onde cada andar começa: a superfície e o andar A, depois um por andar de baixo.
func floor_tops() -> Array[float]:
	var out: Array[float] = [0.0]
	var n: int = int(round(float(view.world_height() - BunkerGeo.H) / float(BunkerGeo.FLOOR_DY))) + 1   # andares abaixo do A
	for i in n:
		out.append(float(BunkerGeo.ROOM_Y_B + i * BunkerGeo.FLOOR_DY - 6))
	return out


func _draw() -> void:
	if view == null:
		return
	var wh: float = float(view.world_height())
	draw_rect(Rect2(0, 0, size.x, size.y), Color(UiTheme.INK, 0.7))
	var tops: Array[float] = floor_tops()
	for i in tops.size():
		var y0: float = tops[i] * SCALE
		var y1: float = (tops[i + 1] if i + 1 < tops.size() else wh) * SCALE
		draw_rect(Rect2(PAD, PAD + y0, CELL_W, maxf(1.0, y1 - y0 - 1.0)), Color(UiTheme.CONC1, 0.9))
	var vr := Rect2(PAD - 1, PAD + view.scroll_y * SCALE - 0.5, CELL_W + 2, float(view.view_h) * SCALE + 1.0)
	draw_rect(vr, UiTheme.AMBER3, false, 1.0)
	var dot_y: float = clampf(PAD + view.man.position.y * SCALE - 1.0, PAD, size.y - PAD - 2.0)
	draw_rect(Rect2(PAD + CELL_W * 0.5 - 1.0, dot_y, 2, 2), UiTheme.SIGNAL)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or view == null:
		return
	var wy: float = (mb.position.y - PAD) / SCALE
	view.reveal_center(wy)
	accept_event()
