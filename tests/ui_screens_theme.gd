extends SceneTree
# Teste do UiTheme: tema monta, ícones carregam, tamanhos de texto arredondam para inteiro.
# godot --headless --path . --script res://tests/ui_screens_theme.gd

var _fails: int = 0


func _initialize() -> void:
	var th: Theme = UiTheme.build(1.0)
	_ok(th != null, "build() devolve Theme")
	_ok(th.default_font != null, "fonte padrão")
	_ok(th.default_font_size == 11, "tamanho normal 11")
	_ok(th.get_stylebox("normal", "Button") is StyleBoxTexture, "botão 9-slice")
	_ok(th.get_font_size("font_size", "LabelTitle") == 12, "título 12")
	_ok(th.get_font_size("font_size", "LabelSmall") == 11, "pequeno 11")
	_ok(UiTheme.build(1.0) == th, "cache por escala")
	var big: Theme = UiTheme.build(1.5)
	_ok(big.default_font_size == 17 and big.get_font_size("font_size", "LabelSmall") == 17, "texto 1.5x inteiro")
	_ok(UiTheme.build(1.25).default_font_size == 14, "texto 1.25x inteiro")
	for n: String in ["hide", "show", "icon_grab", "speaker_on", "speaker_off", "gear", "home", "close"]:
		var tex: Texture2D = UiTheme.icon(n)
		_ok(tex != null and tex.get_width() == 8, "ícone " + n)
	var sb: StyleBoxTexture = UiTheme.nine("panel_9s")
	_ok(sb.texture_margin_left == 5.0, "margens do manifesto")
	print("ui_screens_theme: %s" % ("OK" if _fails == 0 else "%d falhas" % _fails))
	quit(1 if _fails > 0 else 0)


func _ok(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		push_error("FALHOU: " + what)
