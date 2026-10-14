class_name I18nRef
extends RefCounted
## Acesso ao autoload I18n pelo nó /root/I18n, sem o identificador global.
## Assim os scripts da gaveta compilam em --check-only e nos testes --script
## (lá os autoloads ainda não existem quando o script é compilado).
## Mesmas assinaturas de I18n.t / I18n.has_key; o tools/content/check_strings.py reconhece.

static func t(key: String, args: Dictionary = {}) -> String:
	var n: Node = node()
	return str(n.call("t", key, args)) if n != null else key


static func has_key(key: String) -> bool:
	var n: Node = node()
	return n != null and bool(n.call("has_key", key))


static func locale() -> String:
	var n: Node = node()
	return str(n.get("locale")) if n != null else ""


static func node() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/I18n")
	return null
