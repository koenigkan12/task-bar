class_name RoomPlates
extends Node2D
## Placas de nome dos cômodos, penduradas no canto de cima de cada um ("Horta", "Oficina"...). Só leem a
## geometria e o nº de salas; podem ser desligadas nas Opções (Settings "room_plates").

const PLATE_Y := 2     # abaixo do teto de cada andar (px)
const PAD := 3

var view: BunkerView
var _rooms: int = -1
var _on: bool = true


func _ready() -> void:
	z_index = 5
	ScreenUtil.connect_to("I18n", "locale_changed", func(_c: String) -> void: queue_redraw())
	ScreenUtil.connect_to("Settings", "changed", func(_k: Variant = null, _v: Variant = null) -> void: _read_setting())
	_read_setting()


func _read_setting() -> void:
	var on: bool = bool(ScreenUtil.setting("room_plates", true))
	if on != _on:
		_on = on
		queue_redraw()


func is_on() -> bool:
	return _on


func refresh(rooms: int) -> void:
	if rooms != _rooms:
		_rooms = rooms
		queue_redraw()


## Placas que existem agora: [{text, pos}] (pos = canto de cima, à esquerda).
func plates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in range(1, _rooms + 1):
		for z: Dictionary in BunkerGeo.zones(r):
			var skip: float = float(BunkerGeo.COL) if int(z["col0"]) == 0 else 0.0   # o poço da escada fica à esquerda
			out.append({"text": ScreenUtil.tr_key("room." + String(z["id"])), "pos": Vector2(float(z["x0"]) + skip + PAD, float(BunkerGeo.wall_y(r) + PLATE_Y))})
		if r == 1:
			out.append({"text": ScreenUtil.tr_key("room.despensa"), "pos": Vector2(float(BunkerGeo.room_x0(1)) + PAD + 14.0, float(BunkerGeo.WALL_Y_B + PLATE_Y))})
	return out


func _draw() -> void:
	if not _on or _rooms < 1:
		return
	var font: Font = UiTheme.font()
	var size: int = UiTheme.SIZE_SMALL
	for p: Dictionary in plates():
		var text: String = String(p["text"])
		var at: Vector2 = p["pos"]
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var h: float = font.get_height(size)
		draw_rect(Rect2(at, Vector2(w + PAD * 2.0, h + 1.0)), Color(UiTheme.INK, 0.72))
		draw_string(font, at + Vector2(PAD, font.get_ascent(size) + 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, UiTheme.PAPER)
