class_name DebugSpeed
extends Control
## MODO DE TESTE (remover antes do lançamento: apague esta pasta e a linha "DebugSpeed" em main.gd).
## F9 alterna a velocidade do tempo 1x -> 10x -> 60x -> 1x (selo "x10" no canto da faixa enquanto ativa).
## F10 pula 1 hora de uma vez. Nada disso é salvo: ao abrir o jogo a velocidade volta a 1x.

const SPEEDS: Array[float] = [1.0, 10.0, 60.0]
const SKIP_MIN: float = 60.0
const FLASH_S: float = 1.2

var _idx: int = 0
var _badge: Label
var _flash: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	theme = UiTheme.build()
	_badge = Label.new()
	_badge.theme_type_variation = "LabelSmall"
	_badge.add_theme_color_override("font_color", UiTheme.AMBER4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.INK, 0.85)
	sb.set_content_margin_all(1)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	_badge.add_theme_stylebox_override("normal", sb)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	add_child(_badge)
	_apply()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_apply()
	# o selo fica no canto de baixo da faixa (a janela cresce/diminui com a gaveta)
	var strip_h: float = float(BunkerGeo.H)
	_badge.position = Vector2(3, strip_h - _badge.size.y - 2)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_F9:
		_idx = (_idx + 1) % SPEEDS.size()
		_apply()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_F10:
		ScreenUtil.call_on("Game", "debug_skip", [SKIP_MIN])
		_badge.text = "+1h"
		_badge.visible = true
		_flash = FLASH_S
		get_viewport().set_input_as_handled()


func _apply() -> void:
	var x: float = SPEEDS[_idx]
	ScreenUtil.call_on("Game", "set_time_scale", [x])
	_badge.text = "x%d" % int(x)
	_badge.visible = x > 1.0
