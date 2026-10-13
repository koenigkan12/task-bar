class_name DrawerUi
extends RefCounted
## Fábricas pequenas de controles da gaveta (usam as variações do UiTheme).

## Label com variação do tema: "" (13), "LabelSmall" (12), "LabelTitle" (15), "LabelAmber", "LabelMuted".
static func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 20.0
	return l


## Label que ocupa o espaço que sobra e corta com reticências quando não cabe.
static func fill_label(text: String, variation: String = "") -> Label:
	var l: Label = label(text, variation)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Label pequena com cor própria (para os números em amber, avisos em ferrugem).
static func colored(text: String, color: Color, variation: String = "LabelSmall") -> Label:
	var l: Label = label(text, variation)
	l.add_theme_color_override("font_color", color)
	return l


## Ícone 8×8 sem esticar.
static func icon(name: String) -> TextureRect:
	var r := TextureRect.new()
	r.texture = UiTheme.icon(name)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.custom_minimum_size = Vector2(8, 8)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Linha "ícone + texto".
static func icon_text(icon_name: String, text: String, variation: String = "LabelSmall") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_name != "":
		h.add_child(icon(icon_name))
	h.add_child(label(text, variation))
	return h


## Botão com texto (e ícone opcional) da moldura padrão.
static func button(text: String, icon_name: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if icon_name != "":
		b.icon = UiTheme.icon(icon_name)
	return b


## Botão só de ícone (sem moldura); a dica aparece no hover.
static func icon_button(icon_name: String, tooltip: String = "") -> Button:
	var b := Button.new()
	b.icon = UiTheme.icon(icon_name)
	b.theme_type_variation = "IconButton"
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	return b


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Ícone de cada "pra quê?".
static func pra_que_icon(tag: String) -> String:
	return tag if tag in ["renda", "tempo", "espaco", "porta", "historia"] else "estrela"


## "{h}h{m}" a partir de horas decimais.
static func clock(tod: float) -> String:
	var total: int = int(floor(tod * 60.0 + 0.5)) % (24 * 60)
	return I18nRef.t("ui.clock", {"h": "%02d" % (total / 60), "m": "%02d" % (total % 60)})
