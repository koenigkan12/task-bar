class_name BunkerAttention
extends RefCounted
## Sinais de atenção sem nag (CONTRATOS 10): no máximo UM pulsando por vez; pulsa PULSE_SEC
## segundos e para quando o mouse passa por cima; só volta com evento novo (borda de subida da
## condição, ou notify() explícito como uma fala nova do rádio).

const PULSE_SEC := 10.0
const KINDS: Array[String] = ["radio", "box", "power", "goal"]

var current: String = ""
var _left: float = 0.0
var _queue: Array[String] = []
var _cond: Dictionary = {}


## conds: tipo -> condição atual. Subida false -> true conta como evento novo.
func update_conditions(conds: Dictionary) -> void:
	for k: String in conds:
		var now := bool(conds[k])
		var was := bool(_cond.get(k, false))
		_cond[k] = now
		if now and not was:
			notify(k)
		elif not now:
			_queue.erase(k)
			if current == k:
				_stop()


func condition(k: String) -> bool:
	return bool(_cond.get(k, false))


## Evento novo para um tipo (só pulsa se a condição estiver de pé).
func notify(k: String) -> void:
	if not condition(k):
		return
	if current == k:
		_left = PULSE_SEC
		return
	if not _queue.has(k):
		_queue.append(k)
	if current == "":
		_next()


func tick(delta: float) -> void:
	if current != "":
		_left -= delta
		if _left <= 0.0:
			_stop()
	if current == "":
		_next()


## O mouse passou sobre o elemento do tipo k.
func hover(k: String) -> void:
	_queue.erase(k)
	if current == k:
		_stop()


func time_left() -> float:
	return _left if current != "" else 0.0


func _stop() -> void:
	current = ""
	_left = 0.0


func _next() -> void:
	while not _queue.is_empty():
		var k: String = _queue.pop_front()
		if condition(k):
			current = k
			_left = PULSE_SEC
			return
