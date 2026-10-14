class_name ArtSprite
extends Node2D
## Um quadro de uma tira do manifesto, desenhado com a âncora na posição do nó.
## Anima pelos fps do manifesto quando `playing`. `reveal` < 1 mostra só a parte de baixo (obra).

signal finished()

var art: String = "":
	set(v):
		if v == art:
			return
		art = v
		frame = 0
		_t = 0.0
		queue_redraw()
var frame: int = 0:
	set(v):
		if v == frame:
			return
		frame = v
		queue_redraw()
var playing: bool = false:
	set(v):
		playing = v
		set_process(playing)
var flip: bool = false:
	set(v):
		flip = v
		scale.x = -1.0 if flip else 1.0
var fps_override: float = -1.0
var loop: bool = true
var reveal: float = 1.0:
	set(v):
		reveal = clampf(v, 0.0, 1.0)
		queue_redraw()
## Quadros usados na animação (vazio = todos).
var frame_list: Array[int] = []

var _t: float = 0.0
var _step: int = 0


func _init(art_name: String = "", start_frame: int = 0) -> void:
	art = art_name
	frame = start_frame
	set_process(false)


func play(art_name: String, from_frame: int = 0) -> void:
	art = art_name
	frame = from_frame
	_t = 0.0
	_step = 0
	playing = true


func current_fps() -> float:
	return fps_override if fps_override >= 0.0 else BunkerArt.fps(art)


func _process(delta: float) -> void:
	var f := current_fps()
	if f <= 0.0 or art == "":
		return
	_t += delta
	var step_len := 1.0 / f
	while _t >= step_len:
		_t -= step_len
		_step += 1
		var n := frame_list.size() if not frame_list.is_empty() else BunkerArt.frames(art)
		if _step >= n:
			if not loop:
				playing = false
				finished.emit()
				return
			_step = 0
		frame = frame_list[_step] if not frame_list.is_empty() else _step


func _draw() -> void:
	var tex := BunkerArt.texture(art)
	if tex == null:
		return
	var reg := BunkerArt.region(art, frame)
	var a := BunkerArt.anchor(art)
	if reveal >= 1.0:
		draw_texture_rect_region(tex, Rect2(-a, reg.size), reg)
		return
	var h := floorf(reg.size.y * reveal)
	if h <= 0.0:
		return
	var src := Rect2(reg.position + Vector2(0, reg.size.y - h), Vector2(reg.size.x, h))
	draw_texture_rect_region(tex, Rect2(-a + Vector2(0, reg.size.y - h), src.size), src)


## Caixa do sprite em coordenadas do pai.
func bounds() -> Rect2:
	var s := BunkerArt.frame_size(art)
	var a := BunkerArt.anchor(art)
	var x := position.x - a.x if not flip else position.x + a.x - s.x
	return Rect2(Vector2(x, position.y - a.y), s)
