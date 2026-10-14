class_name FloorIndicator
extends Control
## Mapinha do bunker no canto da faixa: um quadradinho por cômodo (cor da função), o retângulo claro é o que a
## janela mostra agora e o ponto é o Joaquim. Só aparece quando há o que rolar; clicar leva a vista até lá.

const SCALE: float = 0.1   # pixels do mapa por pixel do mundo
const PAD: int = 2

var view: BunkerView


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	visible = false
	set_process(true)


## Largura que o mapa ocupa (para a Main encostá-lo na borda direita).
static func map_width() -> int:
	return int(ceilf(float(BunkerGeo.strip_width(1)) * SCALE)) + PAD * 2


func _process(_delta: float) -> void:
	var show_it: bool = view != null and view.view_h > 0 and (view.max_scroll() > 0.0 or view.max_scroll_x() > 0.0)
	if show_it != visible:
		visible = show_it
	if visible:
		_fit()
		queue_redraw()


func _fit() -> void:
	custom_minimum_size = Vector2(map_width(), float(view.world_height()) * SCALE + PAD * 2)
	size = custom_minimum_size


## Cômodos que existem agora: [{rect (mundo), fn}], com a despensa.
func cells() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n: int = view.rooms_dug()
	for r in range(1, n + 1):
		for z: Dictionary in BunkerGeo.zones(r):
			out.append({"rect": Rect2(float(z["x0"]), float(BunkerGeo.room_y(r)), float(z["x1"]) - float(z["x0"]), float(BunkerGeo.FLOOR_DY)), "fn": String(z["fn"])})
		if r == 1:
			out.append({"rect": Rect2(float(BunkerGeo.room_x0(1)), float(BunkerGeo.ROOM_Y_B), float(BunkerGeo.PANTRY_W), float(BunkerGeo.FLOOR_DY)), "fn": "despensa"})
	return out


static func color_of(fn: String) -> Color:
	match fn:
		"horta":
			return BunkerGeo.pal("leaf2")
		"oficina":
			return BunkerGeo.pal("rust2")
		"quarto", "casa":
			return BunkerGeo.pal("amber1")
		"despensa":
			return BunkerGeo.pal("dark3")
	return BunkerGeo.pal("conc1")


func _draw() -> void:
	if view == null:
		return
	draw_rect(Rect2(0, 0, size.x, size.y), Color(UiTheme.INK, 0.72))
	for c: Dictionary in cells():
		var r: Rect2 = c["rect"]
		draw_rect(Rect2(Vector2(PAD, PAD) + r.position * SCALE, Vector2(maxf(1.0, r.size.x * SCALE - 1.0), maxf(1.0, r.size.y * SCALE - 1.0))), color_of(String(c["fn"])))
	var vr := Rect2(Vector2(PAD, PAD) + Vector2(view.scroll_x, view.scroll_y) * SCALE - Vector2(0.5, 0.5), Vector2(float(view.view_width), float(view.view_h)) * SCALE + Vector2(1.0, 1.0))
	draw_rect(vr, UiTheme.AMBER3, false, 1.0)
	var dot: Vector2 = Vector2(PAD, PAD) + (view.man.position + Vector2(0, -8)) * SCALE - Vector2(1.0, 1.0)
	draw_rect(Rect2(dot, Vector2(2, 2)), UiTheme.SIGNAL)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or view == null:
		return
	view.reveal_center((mb.position - Vector2(PAD, PAD)) / SCALE)
	accept_event()
