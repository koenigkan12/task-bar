class_name FirstSteps
extends Node
## Primeiros passos guiados (o ciclo: ajudar a planta -> colher -> trocar cestos por sucata -> comprar).
## Cada passo avança pelo evento real de Game; a ordem das ações não importa (vale o primeiro passo pendente).
## Ativo em jogo novo; o progresso fica em Settings "tutorial" ({active, done: [passos]}).

signal changed()

const STEPS: Array[String] = ["help", "harvest", "sell", "buy"]

var active: bool = false
var _done: Array = []


func _ready() -> void:
	var t: Variant = ScreenUtil.setting("tutorial", {})
	if t is Dictionary:
		active = bool((t as Dictionary).get("active", false))
		_done = ((t as Dictionary).get("done", []) as Array).duplicate()
	ScreenUtil.connect_to("Game", "new_game_started", start)
	ScreenUtil.connect_to("Game", "helped", func(_i: int) -> void: _mark("help"))
	ScreenUtil.connect_to("Game", "plot_harvested", func(_p: int) -> void: _mark("harvest"))
	ScreenUtil.connect_to("Game", "visit_happened", func(info: Dictionary) -> void:
		if int(info.get("scrap", 0)) > 0:
			_mark("sell"))
	ScreenUtil.connect_to("Game", "item_placed", func(_i: int) -> void: _mark("buy"))


func start() -> void:
	active = true
	_done = []
	_save()
	changed.emit()


## Chave i18n do passo atual ("" = acabou).
func current_key() -> String:
	if not active:
		return ""
	for i in STEPS.size():
		if not _done.has(STEPS[i]):
			return "tut.%d" % (i + 1)
	return ""


func _mark(step: String) -> void:
	if not active or _done.has(step):
		return
	_done.append(step)
	if _done.size() >= STEPS.size():
		active = false
	_save()
	changed.emit()


func _save() -> void:
	ScreenUtil.set_setting("tutorial", {"active": active, "done": _done})
