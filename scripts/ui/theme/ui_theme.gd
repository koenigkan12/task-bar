class_name UiTheme
extends RefCounted
## Tema único da interface (pixel art 9-slice + fonte Jersey 15) e acesso aos ícones.
## Uso: `control.theme = UiTheme.build()`; `UiTheme.icon("hide")` (ou "icon_hide").
## Variações de tipo: Label "LabelSmall" (12), "LabelTitle" (15), "LabelAmber", "LabelMuted";
## Button "IconButton" (só ícone, sem moldura), "FlatButton" (texto sem moldura).

const FONT_PATH: String = "res://assets/fonts/Jersey15-Regular.ttf"
const ART_DIR: String = "res://assets/art/"
const MANIFEST_PATH: String = "res://assets/art/manifest_ui.json"

## Tamanhos base (px lógicos); o multiplicador text_size arredonda para inteiro.
const SIZE_SMALL: int = 12
const SIZE_NORMAL: int = 13
const SIZE_TITLE: int = 15

## Paleta (mesma de tools/art/palette.py). SIGNAL só em sinais de atenção.
const INK := Color("14110f")
const DARK1 := Color("2a2420")
const DARK2 := Color("3d352e")
const DARK3 := Color("554a40")
const CONC1 := Color("6e6359")
const CONC2 := Color("8c8174")
const CONC3 := Color("a99f90")
const CONC4 := Color("c9bfae")
const RUST2 := Color("8a4a2a")
const RUST3 := Color("b5683a")
const AMBER1 := Color("a8741c")
const AMBER2 := Color("e0a52e")
const AMBER3 := Color("f6d36b")
const AMBER4 := Color("fff0b8")
const LEAF2 := Color("4f7a37")
const PAPER := Color("e9e2d0")
const TOMATO := Color("b8402e")
const SIGNAL := Color("5dff8a")

static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
static var _themes: Dictionary = {}   # text_scale -> Theme


## Tema pronto. `text_scale` <= 0 lê Settings.text_size (1.0 se não houver Settings).
static func build(text_scale: float = -1.0) -> Theme:
	var s: float = text_scale if text_scale > 0.0 else _setting_text_scale()
	var key: String = "%.2f" % s
	if _themes.has(key):
		return _themes[key]
	var th: Theme = _make_theme(s)
	_themes[key] = th
	return th


## Tamanho de fonte inteiro para o multiplicador dado (1.0 / 1.25 / 1.5).
static func font_size(base: int, text_scale: float = -1.0) -> int:
	var s: float = text_scale if text_scale > 0.0 else _setting_text_scale()
	return maxi(base, roundi(base * s))


static func font() -> Font:
	return load(FONT_PATH) as Font


## Ícone 8×8 do manifest_ui ("hide" ou "icon_hide"). Ausente -> null (avisa).
static func icon(name: String) -> Texture2D:
	var key: String = name if name.begins_with("icon_") else "icon_" + name
	return texture(key)


## Qualquer entrada do manifest_ui (quadro 0) como Texture2D.
static func texture(key: String) -> Texture2D:
	if _textures.has(key):
		return _textures[key]
	var entry: Dictionary = _entry(key)
	if entry.is_empty():
		push_warning("UiTheme: '%s' não existe em manifest_ui.json" % key)
		return null
	var tex: Texture2D = load(ART_DIR + str(entry.get("file", ""))) as Texture2D
	if tex != null and int(entry.get("frames", 1)) > 1:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(0, 0, int(entry.get("frame_w", 8)), int(entry.get("frame_h", 8)))
		tex = at
	_textures[key] = tex
	return tex


## StyleBox 9-slice de uma entrada do manifesto com as margens dele.
static func nine(key: String, pad_h: float = -1.0, pad_v: float = -1.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture(key)
	var m: Array = _entry(key).get("margins", [4, 4, 4, 4])
	sb.texture_margin_left = float(m[0])
	sb.texture_margin_top = float(m[1])
	sb.texture_margin_right = float(m[2])
	sb.texture_margin_bottom = float(m[3])
	if pad_h >= 0.0:
		sb.content_margin_left = pad_h
		sb.content_margin_right = pad_h
	if pad_v >= 0.0:
		sb.content_margin_top = pad_v
		sb.content_margin_bottom = pad_v
	return sb


## Limpa os caches (quando text_size muda os temas são refeitos).
static func clear_cache() -> void:
	_themes.clear()


# ---- interno -------------------------------------------------------------

static func _make_theme(s: float) -> Theme:
	var th := Theme.new()
	var f: Font = font()
	var normal: int = font_size(SIZE_NORMAL, s)
	var small: int = font_size(SIZE_SMALL, s)
	var title: int = font_size(SIZE_TITLE, s)
	th.default_font = f
	th.default_font_size = normal

	# Painéis
	var panel: StyleBoxTexture = nine("panel_9s", 6.0, 5.0)
	th.set_stylebox("panel", "Panel", panel)
	th.set_stylebox("panel", "PanelContainer", panel)
	var popup: StyleBoxTexture = nine("panel_9s", 4.0, 3.0)
	th.set_stylebox("panel", "PopupPanel", popup)
	th.set_stylebox("panel", "PopupMenu", popup)
	th.set_stylebox("embedded_border", "Window", popup)
	th.set_stylebox("embedded_unfocused_border", "Window", popup)

	# Textos
	th.set_color("font_color", "Label", PAPER)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	th.set_constant("line_spacing", "Label", 0)
	_variation(th, "LabelSmall", "Label")
	th.set_font_size("font_size", "LabelSmall", small)
	th.set_color("font_color", "LabelSmall", CONC4)
	_variation(th, "LabelTitle", "Label")
	th.set_font_size("font_size", "LabelTitle", title)
	th.set_color("font_color", "LabelTitle", AMBER3)
	_variation(th, "LabelAmber", "Label")
	th.set_color("font_color", "LabelAmber", AMBER2)
	_variation(th, "LabelMuted", "Label")
	th.set_color("font_color", "LabelMuted", CONC2)
	th.set_color("default_color", "RichTextLabel", PAPER)
	th.set_constant("line_separation", "RichTextLabel", 0)

	# Botões (Button, OptionButton, CheckButton herdam)
	for t: String in ["Button", "OptionButton", "MenuButton"]:
		th.set_stylebox("normal", t, nine("button_9s_normal", 5.0, 1.0))
		th.set_stylebox("hover", t, nine("button_9s_hover", 5.0, 1.0))
		th.set_stylebox("pressed", t, nine("button_9s_pressed", 5.0, 1.0))
		th.set_stylebox("hover_pressed", t, nine("button_9s_pressed", 5.0, 1.0))
		th.set_stylebox("disabled", t, nine("button_9s_disabled", 5.0, 1.0))
		th.set_stylebox("focus", t, _focus_box())
		th.set_color("font_color", t, PAPER)
		th.set_color("font_hover_color", t, AMBER4)
		th.set_color("font_pressed_color", t, AMBER3)
		th.set_color("font_hover_pressed_color", t, AMBER3)
		th.set_color("font_focus_color", t, PAPER)
		th.set_color("font_disabled_color", t, CONC2)
		th.set_color("icon_normal_color", t, Color.WHITE)
		th.set_color("icon_disabled_color", t, Color(1, 1, 1, 0.45))
		th.set_constant("h_separation", t, 3)
	th.set_constant("arrow_margin", "OptionButton", 3)
	th.set_icon("arrow", "OptionButton", icon("arrow_down"))

	# Botão só com ícone (alça, som, recolher): sem moldura, realce no hover
	_variation(th, "IconButton", "Button")
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 2.0
	empty.content_margin_right = 2.0
	empty.content_margin_top = 2.0
	empty.content_margin_bottom = 2.0
	var hov := StyleBoxFlat.new()
	hov.bg_color = DARK3
	hov.content_margin_left = 2.0
	hov.content_margin_right = 2.0
	hov.content_margin_top = 2.0
	hov.content_margin_bottom = 2.0
	var prs: StyleBoxFlat = hov.duplicate()
	prs.bg_color = DARK1
	for st: String in ["normal", "disabled", "focus"]:
		th.set_stylebox(st, "IconButton", empty)
	th.set_stylebox("hover", "IconButton", hov)
	th.set_stylebox("pressed", "IconButton", prs)
	th.set_stylebox("hover_pressed", "IconButton", prs)

	# Botão de texto sem moldura (links discretos)
	_variation(th, "FlatButton", "Button")
	for st: String in ["normal", "disabled", "focus", "hover", "pressed", "hover_pressed"]:
		th.set_stylebox(st, "FlatButton", empty)
	th.set_color("font_color", "FlatButton", CONC4)
	th.set_color("font_hover_color", "FlatButton", AMBER3)

	# Liga/desliga: CheckButton desenhado como caixinha 8×8 com o check signal
	for t: String in ["CheckBox", "CheckButton"]:
		for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			th.set_stylebox(st, t, empty if st != "focus" else _focus_box())
		th.set_color("font_color", t, PAPER)
		th.set_color("font_hover_color", t, AMBER3)
		th.set_color("font_pressed_color", t, PAPER)
		th.set_color("font_hover_pressed_color", t, AMBER3)
		th.set_color("font_disabled_color", t, CONC2)
		th.set_icon("checked", t, _check_icon(true))
		th.set_icon("unchecked", t, _check_icon(false))
		th.set_icon("checked_disabled", t, _check_icon(true))
		th.set_icon("unchecked_disabled", t, _check_icon(false))
		th.set_constant("h_separation", t, 4)

	# Menu suspenso do OptionButton
	th.set_color("font_color", "PopupMenu", PAPER)
	th.set_color("font_hover_color", "PopupMenu", AMBER3)
	th.set_color("font_disabled_color", "PopupMenu", CONC2)
	var sel := StyleBoxFlat.new()
	sel.bg_color = DARK3
	th.set_stylebox("hover", "PopupMenu", sel)
	th.set_constant("v_separation", "PopupMenu", 1)
	th.set_constant("item_start_padding", "PopupMenu", 2)
	th.set_constant("item_end_padding", "PopupMenu", 2)
	th.set_icon("radio_checked", "PopupMenu", icon("check"))
	th.set_icon("radio_unchecked", "PopupMenu", _blank(8, 8))

	# Barras de progresso (calha e enchimento no mesmo retângulo)
	th.set_stylebox("background", "ProgressBar", nine("bar_back_9s", 0.0, 0.0))
	th.set_stylebox("fill", "ProgressBar", nine("bar_fill_9s", 0.0, 0.0))
	th.set_color("font_color", "ProgressBar", PAPER)
	th.set_font_size("font_size", "ProgressBar", small)

	# Slider (volume): calha = bar_back, preenchido = bar_fill, pegador = quadradinho amber
	var slider_bg: StyleBoxTexture = nine("bar_back_9s", 0.0, 3.0)
	var slider_fill: StyleBoxTexture = nine("bar_fill_9s", 0.0, 3.0)
	th.set_stylebox("slider", "HSlider", slider_bg)
	th.set_stylebox("grabber_area", "HSlider", slider_fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	th.set_icon("grabber", "HSlider", _grabber(AMBER3))
	th.set_icon("grabber_highlight", "HSlider", _grabber(AMBER4))
	th.set_icon("grabber_disabled", "HSlider", _grabber(CONC2))
	th.set_constant("center_grabber", "HSlider", 1)

	# Abas
	th.set_stylebox("tab_selected", "TabBar", nine("tab_active", 4.0, 1.0))
	th.set_stylebox("tab_unselected", "TabBar", nine("tab_normal", 4.0, 1.0))
	th.set_stylebox("tab_hovered", "TabBar", nine("tab_normal", 4.0, 1.0))
	th.set_stylebox("tab_disabled", "TabBar", nine("tab_normal", 4.0, 1.0))
	th.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	th.set_color("font_selected_color", "TabBar", AMBER3)
	th.set_color("font_unselected_color", "TabBar", CONC4)
	th.set_color("font_hovered_color", "TabBar", PAPER)
	th.set_constant("h_separation", "TabBar", 3)
	for st: String in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled", "tab_focus"]:
		th.set_stylebox(st, "TabContainer", th.get_stylebox(st, "TabBar"))
	th.set_stylebox("panel", "TabContainer", nine("panel_9s", 6.0, 5.0))
	th.set_color("font_selected_color", "TabContainer", AMBER3)
	th.set_color("font_unselected_color", "TabContainer", CONC4)
	th.set_color("font_hovered_color", "TabContainer", PAPER)

	# Rolagem fina
	var sc_bg := StyleBoxFlat.new()
	sc_bg.bg_color = DARK1
	sc_bg.content_margin_left = 1.0
	sc_bg.content_margin_right = 1.0
	var sc_gr := StyleBoxFlat.new()
	sc_gr.bg_color = CONC1
	sc_gr.content_margin_left = 1.0
	sc_gr.content_margin_right = 1.0
	var sc_hv: StyleBoxFlat = sc_gr.duplicate()
	sc_hv.bg_color = CONC3
	th.set_stylebox("scroll", "VScrollBar", sc_bg)
	th.set_stylebox("grabber", "VScrollBar", sc_gr)
	th.set_stylebox("grabber_highlight", "VScrollBar", sc_hv)
	th.set_stylebox("grabber_pressed", "VScrollBar", sc_hv)

	# Espaçamentos padrão dos contêineres
	th.set_constant("separation", "VBoxContainer", 2)
	th.set_constant("separation", "HBoxContainer", 3)
	th.set_constant("h_separation", "GridContainer", 4)
	th.set_constant("v_separation", "GridContainer", 2)

	# Tooltip
	th.set_stylebox("panel", "TooltipPanel", popup)
	th.set_color("font_color", "TooltipLabel", PAPER)
	th.set_font_size("font_size", "TooltipLabel", small)
	return th


static func _variation(th: Theme, name: String, base: String) -> void:
	th.set_type_variation(name, base)


static func _focus_box() -> StyleBox:
	# Foco do teclado: contorno amber de 1 px (navegação por Tab continua visível)
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = AMBER2
	sb.set_border_width_all(1)
	return sb


static func _check_icon(on: bool) -> Texture2D:
	var key: String = "_check_on" if on else "_check_off"
	if _textures.has(key):
		return _textures[key]
	var img := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 9:
		for j in 9:
			var edge: bool = i == 0 or j == 0 or i == 8 or j == 8
			img.set_pixel(i, j, INK if edge else DARK1)
	if on:
		# marca em "v" na cor signal (é um sinal de estado ligado)
		for p: Vector2i in [Vector2i(2, 4), Vector2i(3, 5), Vector2i(4, 6), Vector2i(5, 5), Vector2i(6, 4), Vector2i(6, 3), Vector2i(3, 4), Vector2i(4, 5), Vector2i(5, 4), Vector2i(6, 2)]:
			img.set_pixelv(p, SIGNAL)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


static func _grabber(c: Color) -> Texture2D:
	var key: String = "_grab_" + c.to_html()
	if _textures.has(key):
		return _textures[key]
	var img := Image.create(5, 9, false, Image.FORMAT_RGBA8)
	img.fill(INK)
	img.fill_rect(Rect2i(1, 1, 3, 7), c)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


static func _blank(w: int, h: int) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


static func _entry(key: String) -> Dictionary:
	if _manifest.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:
			_manifest = parsed
	var e: Variant = _manifest.get(key)
	return e if e is Dictionary else {}


static func _setting_text_scale() -> float:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var st: Node = (loop as SceneTree).root.get_node_or_null("/root/Settings")
		if st != null and st.has_method("get_value"):
			var v: Variant = st.call("get_value", "text_size", 1.0)
			if v is float or v is int:
				return clampf(float(v), 1.0, 2.0)
	return 1.0
