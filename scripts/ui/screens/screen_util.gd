class_name ScreenUtil
extends RefCounted
## Acesso tolerante aos autoloads (Settings, Game, WindowService, AudioManager, I18n):
## enquanto um módulo é stub, as telas seguem funcionando sem erro.


static func node(name: String) -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/" + name)
	return null


## Chama `method` em um autoload se ele existir e tiver o método; senão devolve `fallback`.
static func call_on(name: String, method: String, args: Array = [], fallback: Variant = null) -> Variant:
	var n: Node = node(name)
	if n == null or not n.has_method(method):
		return fallback
	return n.callv(method, args)


static func setting(key: String, default: Variant = null) -> Variant:
	return call_on("Settings", "get_value", [key, default], default)


static func set_setting(key: String, value: Variant) -> void:
	call_on("Settings", "set_value", [key, value])


## Texto traduzido; sem I18n devolve a chave.
static func tr_key(key: String, args: Dictionary = {}) -> String:
	var i18n: Node = node("I18n")
	if i18n == null or not i18n.has_method("t"):
		return key
	return str(i18n.call("t", key, args))


## Liga `callable` a um sinal de autoload, se ele existir.
static func connect_to(name: String, signal_name: String, callable: Callable) -> void:
	var n: Node = node(name)
	if n != null and n.has_signal(signal_name) and not n.is_connected(signal_name, callable):
		n.connect(signal_name, callable)


static func disconnect_from(name: String, signal_name: String, callable: Callable) -> void:
	var n: Node = node(name)
	if n != null and n.has_signal(signal_name) and n.is_connected(signal_name, callable):
		n.disconnect(signal_name, callable)


## Botão de ícone 8×8 (variação IconButton) com dica traduzida.
static func icon_button(icon_name: String, tip_key: String = "") -> Button:
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.icon = UiTheme.icon(icon_name)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if tip_key != "":
		b.tooltip_text = tr_key(tip_key)
	return b


static func label(key: String, variation: String = "", args: Dictionary = {}) -> Label:
	var l := Label.new()
	l.text = tr_key(key, args)
	if variation != "":
		l.theme_type_variation = variation
	return l
