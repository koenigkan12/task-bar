class_name VilaHud
extends Control
## Interface da vila numa tela lógica de 384×216: barra de recursos em cima; embaixo, Construir,
## Torre, a meta e o zoom; selo do portão, cartões (prédio, torre, pessoa, portão), menu de construir e avisos.
## Todo texto passa por I18n.t() (CSV em data/i18n). Cor nunca é o único sinal: falta vem com ícone.

signal build_chosen(type: String)
signal zoom_step(dir: int)
signal quit_pressed
signal options_pressed
signal goal_pressed
signal res_clicked(res: String)
signal move_chosen(id: int)

const ART := "res://assets/art/"
## Tamanho lógico atual da tela (a janela pode ser puxada pela borda: 384×216 é o mínimo).
var W: float = 384.0
var H: float = 216.0
const ICON := {"comida": 0, "agua": 1, "madeira": 2, "sucata": 3, "pessoa": 4, "cama": 5, "relogio": 6,
		"torre": 7, "martelo": 8, "seta": 9, "cadeado": 10, "check": 11, "estrela": 12, "sol": 13, "lua": 14, "alerta": 15,
		"pecas": 16, "energia": 17, "radio": 18, "mercador": 19, "caderno": 20, "saude": 21, "mover": 22,
		"zumbi": 23, "avariado": 24, "ruina": 25, "escudo": 26, "espada": 27}
# Paleta da ilha (tools/estilo_ilha.py), um pouco mais clara onde é texto pequeno sobre o roxo.
const C_TEXT := Color("ccc6ba")    # creme
const C_MUTED := Color("a592a5")   # lilás
const C_WARN := Color("e07f68")    # vermelho da paleta, clareado
const C_GOOD := Color("a9c47c")    # verde da grama, clareado
const C_AMBER := Color("e6c46a")   # dourado
const RAR_COLOR := {"comum": Color(0.78, 0.74, 0.78), "rara": Color(0.45, 0.85, 1.0), "excelente": Color(1.0, 0.62, 0.95)}

var sim: VilaSim
var _font: Font
var _icons: Texture2D
var _res_labels: Dictionary = {}
var _res_chips: Dictionary = {}
var _power_chip: HBoxContainer
var _power_label: Label
var _radio_btn: Button
var _merchant_btn: Button
## Falas do rádio que chegaram com a vila aberta e ainda não foram lidas no caderno.
var radio_unread: int = 0
var _manage: PanelContainer
var _manage_btn: Button
var _manage_box: VBoxContainer
var _manage_acc: float = 0.0
var quiet: bool = false          # tutorial rodando: o rádio só anota, sem balão
var _res_warn: Dictionary = {}
var _people_label: Label
var _clock_label: Label
var _clock_icon: PeriodDial
var _goal_btn: Button
var _gate_btn: Button
var _card: PanelContainer
var _card_box: VBoxContainer
var _card_scroll: ScrollContainer
const BOTTOM_H := 16.0   # altura da barra de baixo
var _card_kind: String = ""
var _card_id: int = -1
var _toast: Label
var _raid_bar: PanelContainer      # placar do ataque no alto: contagem antes, vivos/mortos durante, resultado no fim
var _raid_label: Label
var _raid_icon: TextureRect
var _raid_event := ""              # "Barraca caiu!" (fica uns segundos no placar)
var _raid_event_t := 0.0
var _raid_result := ""             # "Noite sobrevivida!" (fica um tempo depois do fim)
var _raid_result_t := 0.0
var _toast_t: float = 0.0
var _tip: Label
var _night_btn: Button
var _box_for := ""                      # de qual cartão (tipo#id) é o conteúdo montado agora
var _welcome: Dictionary = {}          # resumo da última volta (o cartão de volta se refaz a partir dele)
var _z_seen: int = 0                    # zumbis no mapa no último refresh (avisa quando chegam)
var _raid_btn: Button                   # zumbis da próxima noite (ícone + número; a dica explica)
var _fog_warned := -1
var _refresh_acc: float = 0.0
var handle: WindowHandle
var build_btn: Button
var tower_btn: Button
var goal_btn: Button
## Botões do menu Construir por tipo (o tutorial aponta para eles).
var build_btns: Dictionary = {}
var _offscreen := false   # o cartão está sendo montado fora da tela (_rebuild_card)
## Tutorial: só este tipo fica liberado no menu Construir ("" = todos).
var tut_only: String = ""


## Controle cuja dica é montada na hora por `build` (Array de Controls) e se atualiza aberta.
class LiveTipChip extends HBoxContainer:
	var build: Callable
	var tip_theme: Theme

	func _make_custom_tooltip(_for_text: String) -> Object:
		return LiveTip.new(build, tip_theme)


class LiveTip extends VBoxContainer:
	var _build: Callable
	var _t := 0.0

	func _init(b: Callable, th: Theme) -> void:
		_build = b
		theme = th
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 1)
		_fill()

	func _process(delta: float) -> void:
		_t += delta
		if _t >= 0.5:
			_t = 0.0
			_fill()

	func _fill() -> void:
		for c in get_children():
			remove_child(c)
			c.queue_free()
		for c: Control in _build.call():
			add_child(c)


func setup(s: VilaSim) -> void:
	sim = s
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/fonts/DotGothic16-Regular.ttf")
	_icons = load(ART + "icons.png")
	theme = _make_theme()
	_build_top()
	_build_raid_bar()
	_build_bottom()
	_card = PanelContainer.new()
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	# O conteúdo fica num rolador: cartão alto demais rola em vez de sair da janela.
	_card_scroll = ScrollContainer.new()
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card.add_child(_card_scroll)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 2)
	_card_scroll.add_child(_card_box)
	_toast = Label.new()
	_toast.visible = false
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_stylebox_override("normal", _panel_box())
	_toast.position = Vector2(60, 20)
	_toast.size = Vector2(200, 14)
	add_child(_toast)
	_manage = PanelContainer.new()
	_manage.visible = false
	_manage.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_manage)
	var ms := ScrollContainer.new()
	ms.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_manage.add_child(ms)
	_manage_box = VBoxContainer.new()
	_manage_box.add_theme_constant_override("separation", 1)
	_manage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ms.add_child(_manage_box)
	_tip = Label.new()
	_tip.visible = false
	_tip.add_theme_stylebox_override("normal", _panel_box())
	_tip.add_theme_color_override("font_color", C_TEXT)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Por cima de tudo (tutorial, Opções): camada própria.
	_tip.theme = theme
	var tl := CanvasLayer.new()
	tl.layer = 50
	add_child(tl)
	tl.add_child(_tip)
	refresh()


# ================================================================ tema e peças
func _panel_box() -> StyleBox:
	var t: Texture2D = load(ART + "ui_panel.png")
	if t == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.09, 0.075, 0.1, 0.92)
		f.border_color = Color(0.36, 0.29, 0.37)
		f.set_border_width_all(1)
		f.set_content_margin_all(3)
		return f
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.set_texture_margin_all(4)
	sb.set_content_margin_all(3)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func _button_box(state: int) -> StyleBox:
	var t: Texture2D = load(ART + ("ui_button_off.png" if state == 3 else "ui_button.png"))
	var sb := StyleBoxTexture.new()
	sb.texture = t
	if state < 3:
		sb.region_rect = Rect2(state * 16, 0, 16, 16)
	sb.set_texture_margin_all(4)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = _font
	th.default_font_size = 8
	th.set_color("font_color", "Label", C_TEXT)
	th.set_color("font_color", "Button", C_TEXT)
	th.set_color("font_hover_color", "Button", Color("f2ead8"))
	th.set_color("font_pressed_color", "Button", Color("f2ead8"))
	th.set_color("font_disabled_color", "Button", C_MUTED)
	th.set_stylebox("panel", "PanelContainer", _panel_box())
	th.set_stylebox("normal", "Button", _button_box(0))
	th.set_stylebox("hover", "Button", _button_box(1))
	th.set_stylebox("pressed", "Button", _button_box(2))
	th.set_stylebox("disabled", "Button", _button_box(3))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_constant("h_separation", "Button", 2)
	th.set_constant("separation", "HBoxContainer", 2)
	th.set_constant("separation", "VBoxContainer", 1)
	return th


func icon(name: String) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = _icons
	a.region = Rect2(ICON.get(name, 15) * 8, 0, 8, 8)
	return a


func _icon_rect(name: String) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(name)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.custom_minimum_size = Vector2(8, 10)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _label(text: String, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrap(text: String, color: Color = C_TEXT, width: float = 138.0) -> Label:
	var l := _label(text, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


func _row(parts: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p in parts:
		h.add_child(p)
	return h


## Tempo longo (a viagem dela): dias e horas.
static func fmt_long(sec: float) -> String:
	if sec < 86400.0:
		return fmt_time(sec)
	return "%dd %dh" % [int(sec / 86400.0), int(fmod(sec, 86400.0) / 3600.0)]


static func fmt_time(sec: float) -> String:
	var s := int(ceil(sec))
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dmin" % int(ceil(s / 60.0))
	return "%dh%02d" % [s / 3600, (s % 3600) / 60]


## Contagem regressiva (2:35, 1:02:10): para o que está andando agora.
static func fmt_clock(sec: float) -> String:
	var s := int(ceil(maxf(sec, 0.0)))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


func fmt(key: String, args: Dictionary = {}) -> String:
	return I18n.t(key, args)


func bname(type: String, level: int = 1) -> String:
	var k := "B_%s_%d" % [type, level]
	return I18n.t(k) if I18n.has_key(k) else I18n.t("B_" + type)


func pname(p: Dictionary) -> String:
	var n := String(p.get("name", ""))
	return I18n.t("P_" + n.substr(1)) if n.begins_with("@") else n


## Custo em ícones; o que falta fica laranja com o ícone de alerta (cor + ícone).
func _cost_row(cost: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in VilaSim.RES:
		if not cost.has(r):
			continue
		var short := float(sim.stock[r]) + 1e-6 < float(cost[r])
		h.add_child(_icon_rect(r))
		h.add_child(_label(str(int(cost[r])), C_WARN if short else C_TEXT))
		if short:
			h.add_child(_icon_rect("alerta"))
	return h


# ================================================================ barra de cima e de baixo
func _build_raid_bar() -> void:
	_raid_bar = PanelContainer.new()
	_raid_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_raid_bar.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	_raid_bar.add_child(h)
	_raid_icon = _icon_rect("zumbi")
	h.add_child(_raid_icon)
	_raid_label = _label("")
	h.add_child(_raid_label)
	add_child(_raid_bar)


## Placar do ataque no alto da tela, onde o jogador olha: antes (quantos e em quanto tempo), durante
## (vivos de quantos, mortos, prédios caídos, o último que caiu) e no fim (o resultado da noite).
func _update_raid_bar(delta: float) -> void:
	_raid_event_t = maxf(0.0, _raid_event_t - delta)
	_raid_result_t = maxf(0.0, _raid_result_t - delta)
	var df := sim.defense
	var txt := ""
	var col := C_TEXT
	var ic := "zumbi"
	var rep: Dictionary = df.report
	var who := I18n.t("RAID_HORDE") if bool(rep.get("horde", false)) or bool(df.tonight.get("horde", false)) else I18n.t("RAID_ZOMBIES")
	if not df.zombies.is_empty() or (sim.is_night() and not df.pending.is_empty()):
		var came := int(rep.get("came", df.zombies.size() + df.pending.size()))
		var dead := int(rep.get("killed", 0))
		var alive := df.zombies.size() + df.pending.size()
		var fell := (rep.get("broke", []) as Array).size() + (rep.get("ruined", []) as Array).size()
		txt = fmt("RAID_BAR_LIVE", {"who": who, "a": alive, "n": came}) + " · " + fmt("RAID_DEAD1" if dead == 1 else "RAID_DEAD", {"k": dead})
		if fell > 0:
			txt += " · " + fmt("RAID_BAR_FELL1" if fell == 1 else "RAID_BAR_FELL", {"n": fell})
		if _raid_event_t > 0.0:
			txt += " · " + _raid_event
		col = C_WARN
		_raid_bar.tooltip_text = I18n.t("TIP_RAID_BAR_LIVE")
	elif _raid_result_t > 0.0 and not (_card.visible and _card_kind == "night"):   # o cartão da manhã já diz
		txt = _raid_result
		col = C_GOOD if _raid_result_good else C_AMBER
		ic = "check" if _raid_result_good else "lua"
		_raid_bar.tooltip_text = ""
	else:
		var rs := df.raid_soon()
		if not rs.is_empty():
			var dn: Array[String] = []
			for d in rs["dirs"]:
				dn.append(I18n.t("DIR_" + String(d)))
			txt = fmt("RAID_BAR_SOON1" if int(rs["n"]) == 1 else "RAID_BAR_SOON", {"who": who, "n": rs["n"], "t": fmt_clock(float(rs["left_s"])), "d": I18n.t("UI_AND_JOIN").join(dn)})
			col = C_AMBER
			_raid_bar.tooltip_text = I18n.t("TIP_RAID_BAR_SOON")
	_raid_bar.visible = txt != ""
	if not _raid_bar.visible:
		return
	_raid_label.text = txt
	_raid_label.add_theme_color_override("font_color", col)
	_raid_icon.texture = icon(ic)
	_raid_bar.size = Vector2.ZERO
	var ms := _raid_bar.get_minimum_size()
	_raid_bar.position = Vector2(roundf(W / 2.0 - ms.x / 2.0), 16)


var _raid_result_good := true


## Um prédio caiu agora: aparece no placar por uns segundos (e no aviso).
func on_building_fell(id: int, ruin: bool) -> void:
	var b := sim.by_id(id)
	if b.is_empty():
		return
	_raid_event = fmt("RAID_RUINED" if ruin else "RAID_FELL", {"b": bname(String(b["type"]))})
	_raid_event_t = 4.0


## A noite de ataque fechou (todos mortos ou amanheceu): o resultado fica no placar um tempo.
func on_raid_closed(rep: Dictionary) -> void:
	_raid_result_good = String(rep.get("result", "")) == "survived"
	if _raid_result_good:
		_raid_result = fmt("RAID_WON", {"k": int(rep.get("killed", 0)), "n": int(rep.get("came", 0))})
	else:
		_raid_result = fmt("RAID_FLED", {"n": int(rep.get("fled", 0)), "k": int(rep.get("killed", 0))})
	_raid_result_t = 20.0


func _build_top() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 14
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_bar_input)
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	bar.add_child(h)
	for r in VilaSim.RES:
		var chip := LiveTipChip.new()
		chip.add_theme_constant_override("separation", 1)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = I18n.t("RES_" + r)
		chip.tip_theme = theme
		chip.build = _res_tip_rows.bind(r)
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chip.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				chip.accept_event()
				show_res(r))
		chip.add_child(_icon_rect(r))
		var l := _label("0")
		chip.add_child(l)
		var warn := _icon_rect("alerta")
		warn.visible = false
		chip.add_child(warn)
		_res_labels[r] = l
		_res_warn[r] = warn
		_res_chips[r] = chip
		h.add_child(chip)
	_power_chip = HBoxContainer.new()
	_power_chip.add_theme_constant_override("separation", 1)
	_power_chip.mouse_filter = Control.MOUSE_FILTER_PASS
	_power_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_power_chip.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_power_chip.accept_event()
			show_res("energia"))
	_power_chip.add_child(_icon_rect("energia"))
	_power_label = _label("0")
	_power_chip.add_child(_power_label)
	_power_chip.visible = false
	h.add_child(_power_chip)
	var pi := _icon_rect("pessoa")
	_people_label = _label("1/1")
	for c: Control in [pi, _people_label]:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
		c.tooltip_text = I18n.t("TIP_PEOPLE")
		h.add_child(c)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	_clock_icon = PeriodDial.new()
	_clock_icon.sun = icon("sol")
	_clock_icon.moon = icon("lua")
	_clock_label = _label("")
	for c: Control in [_clock_icon, _clock_label]:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
		c.tooltip_text = I18n.t("TIP_CLOCK")
		h.add_child(c)
	_radio_btn = Button.new()
	_radio_btn.theme_type_variation = "FlatButton"
	_radio_btn.icon = icon("radio")
	_radio_btn.tooltip_text = I18n.t("UI_RADIO_LOG")
	_radio_btn.pressed.connect(func() -> void:
		if _card_kind == "radio":
			close_card()
		else:
			show_radio())
	h.add_child(_radio_btn)
	# Alça da janela: Opções, tela cheia, recolher e fechar.
	handle = WindowHandle.new()
	handle.show_drawer = false
	handle.drawer_toggled.connect(func(open: bool) -> void: set_manage(open))
	handle.quit_requested.connect(func() -> void: quit_pressed.emit())
	handle.options_requested.connect(func() -> void: options_pressed.emit())
	h.add_child(handle)


## Arrastar a barra de cima move a janela (ela não tem borda).
func _on_bar_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		WindowService.start_drag()


func _build_bottom() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -16
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	bar.add_child(h)
	var bb := Button.new()
	build_btn = bb
	bb.icon = icon("martelo")
	bb.text = I18n.t("UI_BUILD")
	bb.tooltip_text = I18n.t("TIP_BUILD")
	bb.pressed.connect(func() -> void:
		if _card_kind == "build":
			close_card()
		else:
			show_build_menu())
	h.add_child(bb)
	var tb := Button.new()
	tower_btn = tb
	tb.icon = icon("torre")
	tb.text = I18n.t("UI_TOWER_BTN")
	tb.tooltip_text = I18n.t("TIP_TOWER")
	tb.pressed.connect(func() -> void:
		if _card_kind == "tower":
			close_card()
		else:
			show_tower())
	h.add_child(tb)
	_goal_btn = Button.new()
	_goal_btn.icon = icon("estrela")
	_goal_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_goal_btn.clip_text = true
	_goal_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goal_btn.pressed.connect(func() -> void:
		goal_pressed.emit()
		_on_goal())
	goal_btn = _goal_btn
	h.add_child(_goal_btn)
	# Modo gestão (tudo num painel): fica aqui embaixo; em cima ficam Opções, tela cheia, recolher e fechar.
	_manage_btn = Button.new()
	_manage_btn.icon = icon("caderno")
	_manage_btn.tooltip_text = I18n.t("TIP_MANAGE_BTN")
	_manage_btn.pressed.connect(func() -> void: set_manage(not _manage.visible))
	h.add_child(_manage_btn)
	# De noite: botão para pôr todo mundo trabalhando só nesta noite (cansa; ver balance "night").
	_night_btn = Button.new()
	_night_btn.icon = icon("lua")
	_night_btn.visible = false
	_night_btn.pressed.connect(func() -> void:
		sim.set_work_tonight(not sim.work_tonight)
		toast(I18n.t("UI_NIGHT_ON_TOAST") if sim.work_tonight else I18n.t("UI_NIGHT_OFF_TOAST"))
		refresh())
	h.add_child(_night_btn)
	_raid_btn = Button.new()
	_raid_btn.icon = icon("zumbi")
	_raid_btn.theme_type_variation = "FlatButton"
	_raid_btn.visible = false
	_raid_btn.pressed.connect(show_build_menu)
	h.add_child(_raid_btn)
	var zm := Button.new()
	zm.text = "-"
	zm.custom_minimum_size = Vector2(14, 0)
	zm.tooltip_text = I18n.t("TIP_ZOOM")
	zm.pressed.connect(func() -> void: zoom_step.emit(-1))
	h.add_child(zm)
	var zp := Button.new()
	zp.text = "+"
	zp.custom_minimum_size = Vector2(14, 0)
	zp.tooltip_text = I18n.t("TIP_ZOOM")
	zp.pressed.connect(func() -> void: zoom_step.emit(1))
	h.add_child(zp)
	_gate_btn = Button.new()
	_gate_btn.icon = icon("pessoa")
	_gate_btn.position = Vector2(2, 17)
	_gate_btn.visible = false
	_gate_btn.tooltip_text = I18n.t("UI_GATE_TITLE")
	_merchant_btn = Button.new()
	_merchant_btn.icon = icon("mercador")
	_merchant_btn.text = I18n.t("UI_MERCHANT")
	_merchant_btn.position = Vector2(2, 33)
	_merchant_btn.visible = false
	_merchant_btn.tooltip_text = I18n.t("UI_MERCHANT_BADGE")
	_merchant_btn.pressed.connect(show_merchant)
	add_child(_merchant_btn)
	_gate_btn.pressed.connect(show_gate)
	add_child(_gate_btn)


func _goal_text() -> String:
	var g := sim.goal()
	var txt := _goal_text_of(g)
	# Gente doente trabalhando devagar: diz na meta, para ninguém achar que a vila parou à toa.
	var sick := sim.sick_count()
	if sick > 0 and String(g["kind"]) != "sick":
		txt += " · " + fmt("GOAL_SICK_TAIL", {"n": sick})
	return txt


func _goal_text_of(g: Dictionary) -> String:
	match String(g["kind"]):
		"raid_soon":
			var dn: Array[String] = []
			for d in g["dirs"]:
				dn.append(I18n.t("DIR_" + String(d)))
			return fmt("GOAL_raid_soon", {"n": g["n"], "d": I18n.t("UI_AND_JOIN").join(dn), "t": fmt_clock(float(g["left_s"]))})
		"raid":
			if String(g["type"]) == "":
				return fmt("GOAL_raid_come", {"n": g["n"]})
			return fmt("GOAL_raid" if bool(g["covered"]) else "GOAL_raid_open", {"n": g["n"], "b": bname(g["type"])})
		"sick":
			return fmt("GOAL_sick", {"n": g["n"]})
		"build":
			return fmt("GOAL_build", {"b": bname(g["type"])})
		"more":
			return fmt("GOAL_more", {"n": g["idle"], "b": bname(g["type"])})
		"short":
			return fmt("GOAL_short", {"r": I18n.t("RES_" + String(g["res"])), "b": bname(g["type"])})
		"improve":
			return fmt("GOAL_improve", {"b": bname(g["type"]), "r": I18n.t("RES_" + String(g["res"]))})
		"repair":
			return fmt("GOAL_repair", {"b": bname(g["type"])})
		"rebuild":
			return fmt("GOAL_rebuild", {"b": bname(g["type"])})
		"beds":
			return I18n.t("GOAL_beds")
		"space":
			return I18n.t("GOAL_space")
		"storage":
			return fmt("GOAL_storage", {"n": g["need"], "r": I18n.t("RES_" + String(g["res"])), "cap": g["cap"]})
		"tower_wait":
			return fmt("GOAL_tower_wait", {"n": g["level"]})
		"power":
			return I18n.t("GOAL_power")
		"journey":
			var left := float(g.get("left_s", -1.0))
			return I18n.t("GOAL_journey_soon") if left < 3600.0 else fmt("GOAL_journey", {"t": fmt_long(left)})
		"tower":
			var miss: Dictionary = g["missing"]
			if miss.is_empty():
				return fmt("GOAL_tower_ready", {"n": g["level"]})
			var parts: Array[String] = []
			for r in miss:
				parts.append("%d %s" % [miss[r], I18n.t("RES_" + r)])
			return fmt("GOAL_tower", {"n": g["level"]}) + " · " + fmt("UI_MISSING", {"list": ", ".join(parts)})
	return I18n.t("GOAL_done")


func _on_goal() -> void:
	var g := sim.goal()
	match String(g["kind"]):
		"raid_soon":
			build_tab = "defense"
			show_build_menu()
		"raid":
			if bool(g.get("covered", false)) and int(g["id"]) >= 0:
				show_building(int(g["id"]))
			else:
				build_tab = "defense"
				show_build_menu()
		"sick":
			for p in sim.people:
				if String(p["job"].get("kind", "")) == "rest":
					show_person(int(p["id"]))
					break
		"build", "more", "short":
			build_chosen.emit(String(g["type"]))
		"improve", "repair", "rebuild":
			show_building(int(g["id"]))
		"beds":
			show_building(int(sim._first("moradia").get("id", -1)))
		"space":
			toast(I18n.t("UI_CLEAR_TOWER"))
		"storage":
			var dep := sim._first("deposito")
			if dep.is_empty():
				build_chosen.emit("deposito")
			else:
				show_building(int(dep["id"]))
		"power":
			build_chosen.emit("painel" if sim.unlocked("painel") else "gerador")
		"journey":
			show_radio()
		"tower", "tower_wait", "done":
			show_tower()


# ================================================================ atualização
func _process(delta: float) -> void:
	var vs := get_viewport_rect().size
	W = vs.x
	H = vs.y
	if sim == null:
		return
	_update_raid_bar(delta)
	_refresh_acc += delta
	if _refresh_acc >= 0.2:
		_refresh_acc = 0.0
		refresh()
	if _toast.visible:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
			_show_next_toast()
		else:
			_place_toast()
	elif not _tq.is_empty():
		_show_next_toast()


## Explica de onde vêm os números de entra/sai (quem trabalha, quem come, noite).
func _flow_tip(r: String, fl: Dictionary) -> String:
	var lines: Array[String] = []
	if bool(fl.get("night", false)):
		lines.append(I18n.t("TIP_FLOW_NIGHT"))
	var w := int(fl.get("workers", 0))
	lines.append(fmt("TIP_FLOW_IN", {"n": "%.1f" % float(fl["prod"]), "w": w}) if w > 0 else fmt("TIP_FLOW_IN_NONE", {"n": "%.1f" % float(fl["prod"])}))
	if float(fl["use"]) > 0.0:
		lines.append(fmt("TIP_FLOW_OUT_" + ("eat" if r == "comida" or r == "agua" else "make"), {"n": "%.1f" % float(fl["use"]), "e": int(fl.get("eaters", 0))}))
	return "\n".join(lines)


## +entra, -sai, quantos trabalham nisso e a lua de noite (números do dia, apagados).
func _flow_stats(r: String, fl: Dictionary, per_min: bool) -> Array:
	var night := bool(fl.get("night", false))
	var tip := _flow_tip(r, fl)
	var suf := "/min" if per_min else ""
	var out: Array = [_stat("seta", "+%.1f%s" % [float(fl["prod"]), suf], tip, C_MUTED if night else C_GOOD)]
	if float(fl["use"]) > 0.0:
		var net := float(fl["prod"]) - float(fl["use"])
		out.append(_stat("alerta", "-%.1f%s" % [float(fl["use"]), suf], tip, C_MUTED if night else (C_WARN if net < 0.0 else C_TEXT)))
	out.append(_stat("pessoa", str(int(fl.get("workers", 0))), tip, C_MUTED if night else C_TEXT))
	if night:
		out.append(_stat("lua", "", tip, C_MUTED))
	return out


## Dica do recurso na barra de cima: estoque/limite e quanto entra e sai por minuto,
## o mesmo que o cartão mostra ao clicar. LiveTip remonta isto enquanto a dica está aberta.
func _res_tip_rows(r: String) -> Array:
	var v := int(floor(float(sim.stock[r])))
	var cap := int(sim.cap(r))
	var fl := sim.rate(r)
	var st: Array = [_label(I18n.t("RES_" + r).capitalize(), C_AMBER),
		_stat(r, "%d/%d" % [v, cap], "", C_AMBER if v >= cap else C_TEXT)]
	st.append_array(_flow_stats(r, fl, true))
	var row := _row(st)
	row.add_theme_constant_override("separation", 5)
	var out: Array = [row]
	if v >= cap:
		out.append(_label(I18n.t("UI_FULL"), C_AMBER))
	out.append(_wrap(_flow_tip(r, fl), C_TEXT, 160.0))
	out.append(_wrap(I18n.t("TIP_RES_CLICK"), C_MUTED, 160.0))
	return out


## Só troca a dica se o texto mudou (trocar fecha e reabre a dica com o mouse parado em cima).
func _set_tip(c: Control, text: String) -> void:
	if c.tooltip_text != text:
		c.tooltip_text = text


func refresh() -> void:
	for r in VilaSim.RES:
		var v := int(floor(float(sim.stock[r])))
		var cap := int(sim.cap(r))
		var l: Label = _res_labels[r]
		l.text = str(v)
		var low := v <= 2 and (r == "comida" or r == "agua")
		var full := v >= cap
		l.add_theme_color_override("font_color", C_WARN if low else (C_AMBER if full else C_TEXT))
		(_res_warn[r] as Control).visible = low
	(_res_chips["pecas"] as Control).visible = sim.tower >= 3 or float(sim.stock["pecas"]) > 0.0
	var pw := sim.power()
	_power_chip.visible = float(pw["out"]) > 0.0 or float(pw["use"]) > 0.0
	_power_label.text = "%d/%d" % [int(pw["out"]), int(pw["use"])]
	var pshort := float(pw["use"]) > float(pw["out"])
	_power_label.add_theme_color_override("font_color", C_WARN if pshort else C_TEXT)
	_set_tip(_power_chip, fmt("UI_POWER_LINE", {"out": int(pw["out"]), "use": int(pw["use"])}) + ((" · " + I18n.t("UI_POWER_LOW")) if pshort else "") + "\n" + _power_users_text())
	_radio_btn.text = str(radio_unread) if radio_unread > 0 else ""
	_merchant_btn.visible = sim.merchant_here()
	var lx := 154.0 if _manage.visible else 2.0
	_gate_btn.position.x = lx
	_merchant_btn.position = Vector2(lx, 33 if _gate_btn.visible else 17)
	_merchant_btn.size = Vector2.ZERO
	_people_label.text = "%d/%d" % [sim.people.size(), sim.beds_total()]
	var homeless := sim.people.size() - sim.beds_total()
	var sick := sim.sick_count()
	_people_label.add_theme_color_override("font_color", C_WARN if homeless > 0 or sick > 0 else C_TEXT)
	_people_label.tooltip_text = I18n.t("TIP_PEOPLE") + (("\n" + fmt("TIP_PEOPLE_OVER", {"n": homeless})) if homeless > 0 else "") \
			+ (("\n" + fmt("TIP_PEOPLE_SICK", {"n": sick})) if sick > 0 else "")
	var hr := sim.local_hour()
	# Círculo que enche durante o período (dia ou noite); o horário e quanto falta vão na dica.
	var nf: float = float(sim.bal["time"]["night_from_h"])
	var nt: float = float(sim.bal["time"]["night_to_h"])
	var is_n := sim.is_night()
	var p_start := nf if is_n else nt
	var p_len := fposmod(nt - nf, 24.0) if is_n else fposmod(nf - nt, 24.0)
	var into := fposmod(hr - p_start, 24.0)
	_clock_icon.set_state(into / p_len, is_n)
	_clock_label.text = "%s %02d:%02d" % [fmt("UI_DAY", {"n": sim.day_number()}), int(sim.display_hour()), int(fposmod(sim.display_hour() * 60.0, 60.0))]
	# Dica só em horas do jogo e fixa durante o período: texto que muda a cada atualização fazia
	# a dica fechar e abrir com o mouse parado em cima.
	var tb: Dictionary = sim.bal["time"]
	var ctip := fmt("TIP_CLOCK_NIGHT" if is_n else "TIP_CLOCK_DAY", {"h": "%02d:00" % int(tb.get("show_day_from_h", 6) if is_n else tb.get("show_night_from_h", 18))}) + "\n" + I18n.t("TIP_CLOCK")
	if _clock_icon.tooltip_text != ctip:
		_clock_icon.tooltip_text = ctip
		_clock_label.tooltip_text = ctip
	var gt := _goal_text()
	if _goal_btn.text != gt:
		_goal_btn.text = gt
		_goal_btn.tooltip_text = gt
	var nb: Dictionary = sim.bal["night"]
	_night_btn.visible = sim.is_night() or sim.work_tonight
	_night_btn.disabled = sim.fog_now
	_night_btn.text = I18n.t("UI_FOG") if sim.fog_now else (I18n.t("UI_NIGHT_ON") if sim.work_tonight else I18n.t("UI_NIGHT_OFF"))
	_night_btn.add_theme_color_override("font_color", C_WARN if sim.work_tonight else C_TEXT)
	if sim.fog_now:
		_set_tip(_night_btn, I18n.t("TIP_FOG"))
	else:
		_set_tip(_night_btn, fmt("TIP_NIGHT", {"pen": int(round(float(nb["tired_penalty"]) * 100.0)), "rest": int(nb["rest_nights_per_tired"])}))
	var nn := sim.defense.next_night()
	var zn := int(nn.get("n", 0)) + int(nn.get("boss", 0))
	_raid_btn.visible = zn > 0
	if zn > 0:
		_raid_btn.text = str(zn) if not sim.is_night() else "%d/%d" % [sim.defense.zombies.size() + sim.defense.pending.size(), zn]
		_raid_btn.add_theme_color_override("font_color", C_WARN if bool(nn["horde"]) or int(nn["boss"]) > 0 else C_TEXT)
		_set_tip(_raid_btn, _night_forecast_tip(nn))
	# Zumbis saíram da água: avisa uma vez por noite (antes eles apareciam sem nenhum aviso).
	var zon := sim.defense.zombies.size()
	if zon > 0 and _z_seen == 0 and not sim.offline:
		_raid_event = I18n.t("UI_RAID_ARRIVED")   # no próprio placar (como aviso solto ficava atrás dele)
		_raid_event_t = 4.0
	_z_seen = zon
	if not _notices.is_empty():
		_next_notice()
	# Aviso da névoa no fim da tarde (uma vez por dia): dá tempo de fazer cama para todo mundo.
	var to_night := fposmod(float(sim.bal["time"]["night_from_h"]) - sim.local_hour(), 24.0)
	if sim.fog_next and not sim.is_night() and to_night < float(sim.bal["fog"].get("warn_h", 3.0)) and _fog_warned != sim.day_number():
		_fog_warned = sim.day_number()
		toast(I18n.t("UI_FOG_WARN"))
	_gate_btn.visible = false   # a gente nova espera no bote do píer (sinal e seta no mapa), não aqui em cima
	_gate_btn.text = fmt("UI_GATE_BADGE", {"n": sim.gate_group.size()})
	_gate_btn.size = Vector2(10, 14)
	# Refazer o cartão troca os botões por novos: com o botão do mouse apertado, o clique
	# começava num botão e terminava em outro e se perdia. Espera soltar para refazer.
	# Com o mouse em cima do cartão ele também não é refeito: refazer muda o tamanho e a posição dos
	# botões (o X andava quando um texto mudava de largura) e o clique caía fora dele.
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var mp := get_viewport().get_mouse_position()
	var over_card := _card.visible and _card.get_global_rect().grow(3).has_point(mp)
	if _card.visible and not held and not over_card:
		_rebuild_card()
		# Texto que terminou de quebrar linha depois: ajusta o tamanho sem refazer nada.
		var inner := _card_box.get_combined_minimum_size()
		if _card_target(inner) != _card.size:
			_fit_card(inner)
	if _manage.visible:
		_manage.position = Vector2(2, 16)
		_manage.size = Vector2(150, H - 34)
		_manage_acc += 0.2
		if _manage_acc >= 0.6 and not held and not _manage.get_global_rect().grow(3).has_point(mp):
			_manage_acc = 0.0
			_rebuild_manage()


## Fila única de avisos no alto: um de cada vez, nunca um em cima do outro.
## prio: 0 perigo (passa na frente), 1 resultado/normal, 2 ambiente (rádio; some durante ataque).
const TOAST_DANGER := 0
const TOAST_NORMAL := 1
const TOAST_AMBIENT := 2
var _tq: Array[Dictionary] = []
var _toast_prio := TOAST_NORMAL


func toast(text: String, prio: int = TOAST_NORMAL, dur: float = 3.0) -> void:
	if sim != null and sim.offline:
		return   # alcançando o tempo fechado: o resumo vem no cartão de volta, não em avisos soltos
	if prio >= TOAST_AMBIENT and raid_on():
		return   # rádio e afins não aparecem no meio do ataque
	if (_toast.visible and _toast.text == text) or _tq.any(func(q: Dictionary) -> bool: return String(q["text"]) == text):
		return
	var item := {"text": text, "prio": prio, "dur": maxf(dur, 4.0 if prio == TOAST_DANGER else dur)}
	var at := _tq.size()
	for i in _tq.size():
		if int(_tq[i]["prio"]) > prio:
			at = i
			break
	_tq.insert(at, item)
	while _tq.size() > 4:   # fila curta: o mais velho de menor prioridade sai
		_tq.pop_back()
	if not _toast.visible:
		_show_next_toast()
	elif _toast_prio > prio:
		_toast_t = minf(_toast_t, 0.25)   # perigo chegou: o aviso de agora sai rápido


## Ataque acontecendo (ou contagem rodando): o alto da tela é do placar.
func raid_on() -> bool:
	var df := sim.defense
	return not df.zombies.is_empty() or (sim.is_night() and not df.pending.is_empty())


func _show_next_toast() -> void:
	if _tq.is_empty():
		return
	var item: Dictionary = _tq.pop_front()
	_toast_prio = int(item["prio"])
	_toast.text = String(item["text"])
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = float(item["dur"]) if _tq.is_empty() else minf(float(item["dur"]), 2.5)
	_toast.add_theme_color_override("font_color", C_WARN if _toast_prio == TOAST_DANGER else C_TEXT)
	_place_toast()


## Fica no espaço livre do alto (entre o painel da esquerda e o cartão aberto, abaixo do placar);
## se não couber ali, desce para cima da barra de baixo. Recalculado a cada quadro: o cartão e o
## placar abrem e fecham depois que o aviso já apareceu.
func _place_toast() -> void:
	_toast.autowrap_mode = TextServer.AUTOWRAP_OFF
	_toast.custom_minimum_size = Vector2.ZERO
	_toast.size = Vector2(0, 14)
	var maxw := minf(260.0, W - 20.0)
	if _toast.get_minimum_size().x > maxw:
		_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_toast.custom_minimum_size = Vector2(maxw, 0)
		_toast.size = Vector2.ZERO
	var x0 := 154.0 if _manage.visible else 0.0
	var x1 := _card.position.x if _card.visible else W
	var ts := _toast.get_minimum_size()
	var top := (_raid_bar.position.y + _raid_bar.size.y + 2.0) if _raid_bar.visible else 18.0
	if ts.x <= x1 - x0 - 4.0:
		_toast.position = Vector2(roundf(x0 + (x1 - x0) / 2.0 - ts.x / 2.0), top)
	else:
		_toast.position = Vector2(roundf(W / 2.0 - ts.x / 2.0), H - BOTTOM_H - ts.y - 2.0)


## above: em cima do cursor (no posicionamento o fantasma do prédio fica embaixo e à direita).
func show_tip(text: String, at: Vector2, above: bool = false) -> void:
	if text == "":
		_tip.visible = false
		return
	_tip.text = text
	_tip.visible = true
	_tip.custom_minimum_size = Vector2.ZERO
	_tip.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tip.size = Vector2.ZERO
	if _tip.get_minimum_size().x > 160.0:
		_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tip.custom_minimum_size = Vector2(160, 0)
	_tip.size = Vector2.ZERO
	var s := _tip.get_combined_minimum_size()
	var ty := at.y - s.y - 6.0 if above else at.y + 10.0
	_tip.position = Vector2(clampf(at.x + 8.0, 0.0, W - s.x), clampf(ty, 16.0, H - 18.0 - s.y))


func card_open() -> bool:
	return _card.visible


func close_card() -> void:
	_card.visible = false
	_card_kind = ""
	_next_notice()


# ================================================================ avisos que ficam
## Morte e relatório da noite não somem como um toast: abrem um cartão e esperam o Certo.
## Chegando vários (ou com outro cartão aberto, ou com o jogo calculando o tempo fora), entram na fila.
var _notices: Array[Dictionary] = []
var _notice: Dictionary = {}


func show_lost(nm: String, died: bool, why: String) -> void:
	_notices.append({"kind": "lost", "name": nm, "died": died, "why": why})
	_next_notice()


func show_night_report(rep: Dictionary) -> void:
	_notices.append({"kind": "night", "rep": rep.duplicate(true)})
	_next_notice()


func _next_notice() -> void:
	if _notices.is_empty() or sim == null or sim.offline or (_card.visible and _card_kind != "build"):
		return
	_notice = _notices.pop_front()
	_open(String(_notice["kind"]))


func _card_lost() -> void:
	_clear_card()
	var why := String(_notice.get("why", "recover"))
	_header("saude", fmt("UI_LOST_DIED" if bool(_notice.get("died", true)) else "UI_LOST_LEFT", {"name": String(_notice.get("name", ""))}))
	_card_box.add_child(_wrap_row("alerta", fmt("UI_LOST_WHY", {"why": I18n.t("SICKWHY_" + why)}), C_WARN))
	_card_box.add_child(_wrap_row("seta", I18n.t("LOST_TIP_" + why), C_MUTED))
	var ok := Button.new()
	ok.text = I18n.t("TUT_ok")
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(close_card)
	_card_box.add_child(ok)


## Relatório da noite (estilo fim de ataque do Clash): quantos vieram, quantos caíram, o que quebrou,
## quem foi mordido, e um botão para consertar tudo de uma vez.
func _card_night() -> void:
	_clear_card()
	var rep: Dictionary = _notice.get("rep", {})
	# O título é o resultado: ganhou a noite (todos derrubados) ou amanheceu com zumbi vivo.
	var won := String(rep.get("result", "survived")) == "survived"
	var title := fmt("RAID_WON", {"k": int(rep.get("killed", 0)), "n": int(rep.get("came", 0))}) if won \
			else fmt("RAID_FLED", {"n": int(rep.get("fled", 0)), "k": int(rep.get("killed", 0))})
	_header("check" if won else "lua", title, fmt("UI_NIGHT_REPORT", {"n": int(rep.get("day", 0))}))
	# Placar com rótulo: "6 vieram · 4 derrubados · 2 muros caíram" (o número sozinho não dizia o quê).
	var came := int(rep.get("came", 0))
	var kil := int(rep.get("killed", 0))
	var wd := int(rep.get("walls", 0)) - int(rep.get("walls_fixed", 0))
	var score: Array = [_stat("zumbi", fmt("NIGHT_CAME1" if came == 1 else "NIGHT_CAME", {"n": came}), I18n.t("TIP_NIGHT_CAME")),
			_stat("espada", fmt("NIGHT_KILLED1" if kil == 1 else "NIGHT_KILLED", {"n": kil}), I18n.t("TIP_NIGHT_KILLED"), C_GOOD)]
	if wd > 0:
		score.append(_stat("escudo", fmt("NIGHT_WALLS1" if wd == 1 else "NIGHT_WALLS", {"n": wd}), I18n.t("TIP_NIGHT_WALLS_DOWN"), C_WARN))
	_card_box.add_child(_stats(score))
	var names: Array[String] = []
	var ruins: Array[String] = []
	var to_fix: Array[int] = []
	for id in rep.get("broke", []):
		var b := sim.by_id(int(id))
		if b.is_empty():
			continue
		names.append(bname(String(b["type"])))
		if bool(b.get("broken", false)) and not bool(b.get("ruin", false)) and String(b["state"]) == "built":
			to_fix.append(int(id))
	for id in rep.get("ruined", []):
		var b := sim.by_id(int(id))
		if not b.is_empty():
			ruins.append(bname(String(b["type"])))
	# Muros que caíram e não voltaram de manhã (faltou recurso): o rombo continua aberto.
	var walls_down := int(rep.get("walls", 0)) - int(rep.get("walls_fixed", 0))
	if names.is_empty() and ruins.is_empty() and walls_down <= 0:
		_card_box.add_child(_wrap_row("check", I18n.t("UI_NIGHT_SAFE"), C_GOOD))
	if not names.is_empty():
		_card_box.add_child(_wrap_row("avariado", fmt("UI_NIGHT_BROKE", {"list": ", ".join(names)}), C_WARN))
	if not ruins.is_empty():
		_card_box.add_child(_wrap_row("ruina", fmt("UI_NIGHT_RUINED", {"list": ", ".join(ruins)}), C_WARN))
	var bit: Array[String] = []
	for pid in rep.get("bitten", []):
		var bp := sim.person(int(pid))
		if not bp.is_empty():
			bit.append(pname(bp))
	if not bit.is_empty():
		_card_box.add_child(_wrap_row("saude", fmt("UI_NIGHT_BITTEN", {"list": ", ".join(bit)}), C_WARN))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	if not to_fix.is_empty():
		var cost := {}
		for id in to_fix:
			var c: Dictionary = sim.defense.repair_cost(sim.by_id(id))
			for r in c:
				cost[r] = float(cost.get(r, 0.0)) + float(c[r])
		var fix := Button.new()
		fix.icon = icon("martelo")
		fix.text = I18n.t("UI_REPAIR_ALL")
		fix.disabled = not sim.can_afford(cost)
		fix.pressed.connect(func() -> void:
			for id in to_fix:
				sim.repair(id)
			close_card())
		row.add_child(_cost_row(cost))
		row.add_child(fix)
	var ok2 := Button.new()
	ok2.text = I18n.t("TUT_ok")
	ok2.pressed.connect(close_card)
	row.add_child(ok2)
	_card_box.add_child(row)


func mouse_over_ui(pos: Vector2) -> bool:
	for c in get_children():
		if c is Control and (c as Control).visible and (c as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			if (c as Control).get_global_rect().has_point(pos):
				return true
	if _gate_btn.visible and _gate_btn.get_global_rect().has_point(pos):
		return true
	return pos.y < 14 or pos.y > H - 16


# ================================================================ cartões
func _open(kind: String, id: int = -1) -> void:
	_card_kind = kind
	_card_id = id
	_card.visible = true
	_rebuild_card()


func show_building(id: int) -> void:
	var b := sim.by_id(id)
	if b.is_empty():
		return
	if String(b["type"]) == "torre":
		show_tower()
	elif String(b["type"]) == "gate":
		show_gate()
	elif String(b["type"]) == "praca" and String(b["state"]) == "built":
		show_merchant()
	else:
		_open("building", id)


func show_tower() -> void:
	_open("tower")


var _rubble_cell: Vector2i = Vector2i(-1, -1)


func show_rubble(cell: Vector2i) -> void:
	_rubble_cell = cell
	_open("rubble")


func _card_rubble() -> void:
	_clear_card()
	var tree := sim.terrain_at(_rubble_cell) == VilaSim.T_TREE
	if sim.terrain_at(_rubble_cell) != VilaSim.T_RUBBLE and not tree:
		close_card()
		return
	if tree:
		_header("madeira", I18n.t("B_arvore"), I18n.t("BD_arvore"))
		_card_box.add_child(_row([_icon_rect("madeira"), _label(fmt("UI_CUT_GIVES", {"n": int(sim.bal["forage"]["madeira"]["yield"])}))]))
	else:
		_header("sucata", I18n.t("B_entulho"), I18n.t("BD_entulho"))
		_card_box.add_child(_row([_icon_rect("sucata"), _label(fmt("UI_CLEAR_LEFT", {"n": int(sim.rubble.get(_rubble_cell, 0))}))]))
	var on := sim.marked.has(_rubble_cell)
	if on:
		_card_box.add_child(_row([_icon_rect("check"), _label(I18n.t("UI_CUT_MARKED" if tree else "UI_CLEAR_MARKED"), C_GOOD)]))
	var b := Button.new()
	if tree:
		b.text = I18n.t("UI_UNCUT" if on else "UI_CUT")
	else:
		b.text = I18n.t("UI_UNCLEAR" if on else "UI_CLEAR")
	b.icon = icon("martelo")
	b.pressed.connect(func() -> void:
		sim.toggle_mark(_rubble_cell)
		_rebuild_card())
	_card_box.add_child(b)
	if not tree:
		_card_box.add_child(_wrap(I18n.t("UI_CLEAR_TOWER"), C_MUTED))


func show_person(id: int) -> void:
	_open("person", id)


func show_gate() -> void:
	_open("gate")


func show_build_menu() -> void:
	_open("build")


## Cartão de um recurso: quanto tem, quanto cabe e quanto entra e sai por minuto.
func show_res(r: String) -> void:
	_open("res:" + r)
	res_clicked.emit(r)


## O que a energia liga: um item por tipo de prédio elétrico (quantos tem, quanto gasta) e, se ainda
## não tem nenhum, o nome do que vai ligar quando for construído.
func _power_users_rows() -> Array:
	var rows: Array = []
	var low := sim.power_frac() < 0.999
	for tp in sim.bal["build_order"]:
		var type := String(tp)
		var d := sim.def(type)
		if not d.has("power_use"):
			continue
		var n := 0
		for b in sim.buildings:
			if String(b["type"]) == type and String(b["state"]) != "site":
				n += 1
		var row: HBoxContainer
		if n > 0:
			row = _row([_label("%s ×%d" % [bname(type), n]), _stat("energia", "-%d" % (int(d["power_use"]) * n), fmt("UI_POWER_USE", {"n": int(d["power_use"]) * n}), C_WARN if low else C_TEXT)])
			row.tooltip_text = I18n.t("BD_" + type) + ("\n" + I18n.t("UI_POWER_LOW") if low else "")
		else:
			row = _row([_icon_rect("cadeado" if not sim.unlocked(type) else "seta"), _label(bname(type), C_MUTED)])
			row.tooltip_text = fmt("TIP_POWER_NOT_YET", {"b": bname(type)})
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		rows.append(row)
	return rows


func _power_users_text() -> String:
	var names: PackedStringArray = []
	for tp in sim.bal["build_order"]:
		if sim.def(String(tp)).has("power_use"):
			names.append(bname(String(tp)))
	return fmt("TIP_POWER_FEEDS", {"list": ", ".join(names)})


func _card_res() -> void:
	var r := _card_kind.trim_prefix("res:")
	_clear_card()
	if r == "energia":
		var pw := sim.power()
		_header("energia", I18n.t("UI_POWER"))
		# Sem linha de zero: só mostra o que entra e o que sai quando existe.
		var pst: Array = []
		var pline := fmt("UI_POWER_LINE", {"out": int(pw["out"]), "use": int(pw["use"])})
		if float(pw["out"]) > 0.0:
			pst.append(_stat("energia", "+%d" % int(pw["out"]), pline, C_GOOD))
		if float(pw["use"]) > 0.0:
			pst.append(_stat("alerta", "-%d" % int(pw["use"]), pline, C_WARN if float(pw["use"]) > float(pw["out"]) else C_TEXT))
		if not pst.is_empty():
			_card_box.add_child(_stats(pst))
		_card_box.add_child(_wrap(I18n.t("RD_energia"), C_MUTED))
		var gens := {}
		for b in sim.buildings:
			var gd := sim.def(String(b["type"]))
			if gd.has("power_out") and String(b["state"]) != "site":
				gens[String(b["type"])] = int(gens.get(String(b["type"]), 0)) + 1
		for tp in gens:
			_card_box.add_child(_row([_label("%s ×%d" % [bname(tp), gens[tp]]), _stat("energia", "+%d" % (int(sim.def(tp)["power_out"]) * int(gens[tp])), fmt("UI_POWER_OUT", {"n": sim.def(tp)["power_out"]}), C_GOOD)]))
		_card_box.add_child(_label(I18n.t("UI_POWER_FEEDS"), C_AMBER))
		for row in _power_users_rows():
			_card_box.add_child(row)
		return
	_header(r, I18n.t("RES_" + r))
	var v := int(floor(float(sim.stock[r])))
	var fl := sim.rate(r)
	var st: Array = [_stat(r, "%d/%d" % [v, int(sim.cap(r))], fmt("UI_RES_HAVE", {"n": v, "cap": int(sim.cap(r))}))]
	st.append_array(_flow_stats(r, fl, true))
	_card_box.add_child(_stats(st))
	if bool(fl.get("night", false)):
		_card_box.add_child(_wrap(I18n.t("TIP_FLOW_NIGHT"), C_MUTED))
	_card_box.add_child(_wrap(I18n.t("RD_" + r), C_MUTED))
	# De onde vem: cada prédio que produz (quantos e gente/vagas) e quem está catando à mão.
	# No mapa eles ficam contornados enquanto este cartão está aberto.
	var by_type := {}
	for b in sim.buildings:
		var tp := String(b["type"])
		if String(sim.def(tp).get("res", "")) != r or String(b["state"]) == "site":
			continue
		if not by_type.has(tp):
			by_type[tp] = [0, 0, 0]
		var e: Array = by_type[tp]
		e[0] += 1
		e[1] += (b["workers"] as Array).size()
		e[2] += int(sim.level_def(b).get("slots", 0))
	var foragers := 0
	for p in sim.people:
		if String(p["job"].get("kind", "")) == "forage" and String(p["job"].get("res", "")) == r:
			foragers += 1
	if by_type.is_empty() and foragers == 0:
		_card_box.add_child(_row([_icon_rect("alerta"), _label(I18n.t("UI_SRC_NONE"), C_WARN)]))
	for tp in by_type:
		var e: Array = by_type[tp]
		var row := _row([_label("%s ×%d" % [bname(tp), e[0]]), _stat("pessoa", "%d/%d" % [e[1], e[2]], fmt("UI_WORKERS", {"a": e[1], "b": e[2]}))])
		row.tooltip_text = I18n.t("BD_" + tp)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		_card_box.add_child(row)
	if foragers > 0:
		_card_box.add_child(_row([_label(I18n.t("UI_SRC_HAND")), _stat("pessoa", str(foragers), fmt("TIP_SRC_HAND", {"n": foragers}))]))


func show_welcome(summary: Dictionary) -> void:
	_welcome = summary
	radio_unread += int(summary.get("radio", 0))
	_card_kind = "welcome"
	_card.visible = true
	_clear_card()
	_card_welcome()
	_place_card()


## O cartão de volta é refeito como os outros (o refresh periódico apagava o conteúdo dele).
func _card_welcome() -> void:
	var summary := _welcome
	_header("relogio", fmt("UI_WELCOME_BACK", {"t": fmt_time(float(summary["seconds"]))}))
	var d: Dictionary = summary["delta"]
	for r in VilaSim.RES:
		var v: int = int(d.get(r, 0))
		if v != 0:
			_card_box.add_child(_row([_icon_rect(r), _label("%+d %s" % [v, I18n.t("RES_" + r)], C_GOOD if v > 0 else C_WARN)]))
	if int(summary.get("tower_up", 0)) > 0:
		_card_box.add_child(_row([_icon_rect("torre"), _label(fmt("UI_AWAY_TOWER", {"n": int(summary["tower"])}), C_AMBER)]))
	if int(summary.get("built", 0)) > 0:
		_card_box.add_child(_row([_icon_rect("martelo"), _label(fmt("UI_AWAY_BUILT", {"n": int(summary["built"])}))]))
	if int(summary.get("joined", 0)) > 0:
		_card_box.add_child(_row([_icon_rect("pessoa"), _label(fmt("UI_AWAY_JOINED", {"n": int(summary["joined"])}), C_GOOD)]))
	if int(summary.get("left", 0)) > 0:
		_card_box.add_child(_row([_icon_rect("saude"), _label(fmt("UI_AWAY_LEFT", {"n": int(summary["left"])}), C_WARN)]))
	if int(summary.get("sick", 0)) > 0:
		_card_box.add_child(_row([_icon_rect("saude"), _label(fmt("UI_AWAY_SICK", {"n": int(summary["sick"])}), C_WARN)]))
	if int(summary.get("fogs", 0)) > 0:
		_card_box.add_child(_row([_icon_rect("lua"), _label(fmt("UI_AWAY_FOG", {"n": int(summary["fogs"])}), C_MUTED)]))
	if int(summary.get("radio", 0)) > 0:
		_card_box.add_child(_row([_icon_rect("radio"), _label(fmt("UI_RADIO_NEW", {"n": summary["radio"]}))]))
	if bool(summary.get("group", false)):
		_card_box.add_child(_row([_icon_rect("pessoa"), _label(fmt("UI_GATE_BADGE", {"n": sim.gate_group.size()}))]))
	if int(summary.get("raids", 0)) > 0:
		var rr := _stats([_stat("zumbi", "x%d" % int(summary["raids"]), fmt("TIP_AWAY_RAIDS", {"n": summary["raids"]})),
				_stat("espada", str(int(summary.get("z_killed", 0))), fmt("TIP_AWAY_KILLED", {"n": summary.get("z_killed", 0)}), C_GOOD)])
		_card_box.add_child(rr)
		var lost: Dictionary = summary.get("lost", {})
		if not lost.is_empty():
			var lr: Array = [_icon_rect("zumbi")]
			for r in lost:
				lr.append(_stat(r, "-%d" % int(lost[r]), I18n.t("TIP_AWAY_LOOT"), C_WARN))
			_card_box.add_child(_row(lr))
	_box_lines()
	var ok := Button.new()
	ok.text = I18n.t("UI_OK")
	ok.pressed.connect(close_card)
	_card_box.add_child(ok)


func _clear_card() -> void:
	for c in _card_box.get_children():
		_card_box.remove_child(c)
		c.queue_free()


func _header(ic: String, title: String, sub: String = "") -> void:
	var h := _row([_icon_rect(ic), _label(title, C_AMBER)])
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var x := Button.new()
	x.text = "x"
	x.custom_minimum_size = Vector2(10, 10)
	x.pressed.connect(close_card)
	h.add_child(x)
	_card_box.add_child(h)
	if sub != "":
		_card_box.add_child(_wrap(sub, C_MUTED))


func _place_card() -> void:
	if _offscreen:
		return
	# Texto que quebra linha só sabe a altura depois de ter largura: confere por alguns quadros.
	var last := Vector2(-1, -1)
	for i in 3:
		await get_tree().process_frame
		if not is_instance_valid(_card) or not _card.visible:
			return
		var inner := _card_box.get_combined_minimum_size()
		if inner == last:
			return
		last = inner
		_fit_card(inner)


## Tamanho do conteúdo + borda do painel, sem passar da faixa entre a barra de cima e a de baixo.
func _card_target(inner: Vector2) -> Vector2:
	var pad := _card.get_theme_stylebox("panel").get_minimum_size()
	if _card_kind == "build":   # faixa do modo construção: largura toda (a fileira rola sozinha)
		return Vector2(W - 4.0, inner.y + pad.y)
	var avail := H - 17.0 - BOTTOM_H - 1.0
	var tall := inner.y + pad.y > avail
	var bar := _card_scroll.get_v_scroll_bar().get_combined_minimum_size().x + 1.0 if tall else 0.0
	return Vector2(minf(inner.x + pad.x + bar, W - 4.0), minf(inner.y + pad.y, avail))


func _fit_card(inner: Vector2) -> void:
	var pad := _card.get_theme_stylebox("panel").get_minimum_size()
	var s := _card_target(inner)
	_card_scroll.custom_minimum_size = s - pad
	if _card_kind == "build":
		_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_card.offset_right = -2.0
		_card.offset_left = -2.0 - s.x
		_card.offset_bottom = H - BOTTOM_H - 1.0
		_card.offset_top = H - BOTTOM_H - 1.0 - s.y
		return
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# Preso na direita: se o conteúdo ainda crescer, o cartão cresce para a esquerda, nunca para fora.
	_card.offset_right = -2.0
	_card.offset_left = -2.0 - s.x
	_card.offset_top = 17.0
	_card.offset_bottom = 17.0 + s.y


## Refaz o cartão fora da tela e só troca se mudou alguma coisa. Antes ele era refeito no lugar a
## cada 0,2 s: no quadro da troca os nós novos ainda não tinham tamanho e o cartão encolhia e
## crescia (piscava), às vezes cortando o último botão.
func _rebuild_card() -> void:
	if not _card.visible:
		return
	var old_box := _card_box
	var old_btns := build_btns.duplicate()
	var old_tabs := build_tab_btns.duplicate()
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 2)
	_offscreen = true
	_build_card_kind()
	_offscreen = false
	# Mesmo texto mas outro prédio (duas serrarias iguais): os botões antigos apontam para o prédio
	# anterior, então troca mesmo assim.
	var key := "%s#%d" % [_card_kind, _card_id]
	if _sig(_card_box) == _sig(old_box) and key == _box_for:
		_card_box.free()
		_card_box = old_box
		build_btns = old_btns
		build_tab_btns = old_tabs
		return
	_box_for = key
	_card_scroll.remove_child(old_box)
	old_box.queue_free()
	_card_scroll.add_child(_card_box)
	_place_card()


## Uma "impressão" do que o cartão mostra: textos, cores, ícones, botões travados, barras.
func _sig(n: Node) -> String:
	var parts: PackedStringArray = [n.get_class()]
	if n is Label:
		parts.append((n as Label).text)
	if n is Button:
		parts.append((n as Button).text + str((n as Button).disabled))
	if n is Control:
		var c := n as Control
		parts.append(c.tooltip_text + str(c.visible) + str(c.custom_minimum_size))
		if c.has_theme_color_override("font_color"):
			parts.append(str(c.get_theme_color("font_color")))
	if n is Range:
		parts.append(str(roundf((n as Range).value * 100.0)))
	if n is TextureRect and (n as TextureRect).texture != null:
		var tx: Texture2D = (n as TextureRect).texture
		# Os ícones são AtlasTexture novas a cada chamada: compara o recorte, não o objeto.
		parts.append(str((tx as AtlasTexture).region) + str((tx as AtlasTexture).atlas.get_instance_id()) if tx is AtlasTexture else str(tx.get_instance_id()))
	if n is CanvasItem:
		parts.append(str((n as CanvasItem).modulate))
	for ch in n.get_children():
		parts.append(_sig(ch))
	return "(" + "|".join(parts) + ")"


func _build_card_kind() -> void:
	match _card_kind:
		"building":
			_card_building()
		"tower":
			_card_tower()
		"person":
			_card_person()
		"gate":
			_card_gate()
		"build":
			_card_build()
		"rubble":
			_card_rubble()
		"radio":
			_card_radio()
		"merchant":
			_card_merchant()
		"welcome":
			_card_welcome()
		"lost":
			_card_lost()
		"night":
			_card_night()
		_:
			if _card_kind.begins_with("res:"):
				_card_res()


func _card_building() -> void:
	var b := sim.by_id(_card_id)
	if b.is_empty():
		close_card()
		return
	_clear_card()
	var tp := String(b["type"])
	var d := sim.def(tp)
	var title := bname(tp, int(b["level"]))
	if d.has("levels") and (d["levels"] as Array).size() > 1:
		title += " · " + fmt("UI_LEVEL", {"n": b["level"]})
	_header("martelo", title, I18n.t("BD_" + tp))
	var st := String(b["state"])
	if st != "built":
		_progress_lines(b)
		return
	var lv := sim.level_def(b)
	if _damage_lines(b):
		return
	if tp == "hatch":
		_box_lines()
	if d.has("defense") or tp == "muro" or tp == "mina":
		_card_box.add_child(_stats(_defense_stats(tp, lv, b)))
	if tp == "muro":
		_wall_upgrade_all(b)
	if lv.has("slots"):
		var ws: Array = b["workers"]
		var names: Array[String] = []
		for pid in ws:
			names.append(pname(sim.person(int(pid))))
		var rate := "%.1f" % (60.0 / float(lv["rate_s"]))
		_card_box.add_child(_stats([
			_stat("pessoa", "%d/%d" % [ws.size(), int(lv["slots"])], fmt("UI_WORKERS", {"a": ws.size(), "b": lv["slots"]})),
			_stat(String(d["res"]), rate + "/min", fmt("UI_RATE", {"n": rate, "r": I18n.t("RES_" + String(d["res"]))}))]))
		if not names.is_empty():
			_card_box.add_child(_wrap(", ".join(names), C_MUTED))
	if d.has("power_use"):
		var low := sim.power_frac() < 0.999
		var pw := sim.power()
		var ptip := fmt("UI_POWER_USE", {"n": d["power_use"]}) + ". " + fmt("UI_POWER_TOTAL", {"out": int(pw["out"]), "use": int(pw["use"])}) + ((". " + I18n.t("UI_POWER_LOW")) if low else "")
		_card_box.add_child(_stats([_stat("energia", "-%d" % int(d["power_use"]), ptip, C_WARN if low else C_TEXT)]))
	if d.has("power_out"):
		_card_box.add_child(_stats([_stat("energia", "+%d" % int(d["power_out"]), fmt("UI_POWER_OUT", {"n": d["power_out"]}), C_GOOD)]))
		_card_box.add_child(_label(I18n.t("UI_POWER_FEEDS"), C_AMBER))
		for row in _power_users_rows():
			_card_box.add_child(row)
	var inp: Dictionary = lv.get("input", {})
	for r in inp:
		var short := float(sim.stock[r]) < float(inp[r])
		_card_box.add_child(_stats([_stat(r, "-%d" % int(inp[r]), fmt("UI_NO_INPUT", {"r": I18n.t("RES_" + r)}) if short else fmt("UI_INPUT", {"n": inp[r], "r": I18n.t("RES_" + r)}), C_WARN if short else C_TEXT)]))
	var fb := float(lv.get("food_bonus", d.get("food_bonus", 0.0)))
	if fb > 0.0:
		_card_box.add_child(_stats([_stat("comida", "+%d%%" % int(round(fb * 100.0)), fmt("TIP_FOOD_BONUS", {"n": int(round(fb * 100.0))}))]))
	var beds := int(lv.get("beds", d.get("beds", 0)))
	if beds > 0:
		var rs: Array = sim.residents(b) if tp == "moradia" else []
		var names: Array = rs.map(func(q: Dictionary) -> String: return String(q["name"]))
		var btip := fmt("UI_BEDS", {"n": beds, "used": sim.people.size(), "total": sim.beds_total()})
		if tp == "moradia":
			btip += "\n" + (fmt("TIP_HOME_WHO", {"names": ", ".join(names)}) if not names.is_empty() else I18n.t("TIP_HOME_EMPTY"))
		_card_box.add_child(_stats([_stat("cama", "%d/%d" % [rs.size(), beds] if tp == "moradia" else str(beds), btip)]))
		if not names.is_empty():
			_card_box.add_child(_label(", ".join(names), C_MUTED))
	if tp == "hatch" or lv.has("cap"):
		# Um ícone por recurso com o quanto este prédio guarda (o bunker é a base; depósito soma).
		var add := tp != "hatch"
		var n := int(lv["cap"]) if add else int(sim.bal["storage"]["hatch_cap"])
		var ctip := fmt("UI_CAP_ADD", {"n": n, "list": _res_list(), "total": int(sim.cap("comida"))}) if add else fmt("UI_CAP", {"n": n, "list": _res_list()})
		var cs: Array = []
		for r in VilaSim.RES:
			cs.append(_stat(r, ("+%d" if add else "%d") % n, ctip))
		_card_box.add_child(_stats(cs))
	var nl: int = int(b["level"]) + 1
	var levels: Array = d.get("levels", [])
	if nl <= levels.size():
		var nd: Dictionary = levels[nl - 1]
		var need_t: int = int(nd.get("tower", d.get("tower", 1)))
		if sim.tower < need_t:
			_card_box.add_child(_row([_icon_rect("cadeado"), _label(fmt("UI_UPGRADE_TO", {"b": bname(tp, nl)}) + " · " + fmt("UI_LOCKED_TOWER", {"n": need_t}), C_MUTED)]))
		else:
			var gain: Array = [_stat("seta", bname(tp, nl), fmt("UI_UPGRADE_TO", {"b": bname(tp, nl)}), C_MUTED)]
			if d.has("defense") or tp == "muro":
				gain.append_array(_defense_stats(tp, nd, {}))
			elif nd.has("beds"):
				gain.append(_stat("cama", str(int(nd["beds"])), fmt("UI_GAIN_BEDS", {"n": nd["beds"]})))
			elif nd.has("cap"):
				gain.append(_stat("check", "+%d" % int(nd["cap"]), fmt("UI_GAIN_CAP", {"n": nd["cap"]})))
			elif nd.has("food_bonus"):
				gain.append(_stat("comida", "+%d%%" % int(round(float(nd["food_bonus"]) * 100.0)), fmt("TIP_FOOD_BONUS", {"n": int(round(float(nd["food_bonus"]) * 100.0))})))
			elif nd.has("rate_s"):
				var nr := "%.1f" % (60.0 / float(nd["rate_s"]))
				gain.append(_stat(String(d.get("res", "seta")), nr + "/min", fmt("UI_GAIN_RATE", {"n": nr})))
			var hg := _hp_gain(b, nl)
			if hg != null:
				gain.append(hg)
			_card_box.add_child(_stats(gain))
			if float(nd["time_s"]) > 0.0:
				_card_box.add_child(_row([_cost_row(nd["cost"]), _icon_rect("relogio"), _label(fmt_time(float(nd["time_s"])))]))
			else:
				_card_box.add_child(_cost_row(nd["cost"]))
			var up := Button.new()
			up.text = I18n.t("UI_UPGRADE")
			up.icon = icon("seta")
			up.disabled = not sim.can_afford(nd["cost"])
			up.pressed.connect(func() -> void:
				var r := sim.upgrade(_card_id)
				if not bool(r["ok"]):
					toast(I18n.t("UI_MISSING").format({"list": ""}))
				_rebuild_card())
			_card_box.add_child(up)
	# Mover e desmontar lado a lado, no pé do cartão.
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 2)
	if sim.can_move(b):
		var mv := Button.new()
		mv.icon = icon("mover")
		mv.theme_type_variation = "FlatButton"
		mv.tooltip_text = I18n.t("TIP_MOVE")
		var mid := int(b["id"])
		mv.pressed.connect(func() -> void: move_chosen.emit(mid))
		foot.add_child(mv)
	if String(b["state"]) == "built" and sim.demolish_leaves_homeless(b):
		var dn := Button.new()
		dn.text = I18n.t("UI_DEMOLISH")
		dn.theme_type_variation = "FlatButton"
		dn.disabled = true
		dn.tooltip_text = I18n.t("UI_DEMOLISH_NO_BEDS")
		foot.add_child(dn)
	elif sim.can_demolish(b):
		var dm := Button.new()
		dm.text = I18n.t("UI_DEMOLISH")
		dm.theme_type_variation = "FlatButton"
		dm.tooltip_text = I18n.t("UI_DEMOLISH_TEXT")
		var bid := int(b["id"])
		var nm := title
		dm.pressed.connect(func() -> void:
			ConfirmBox.ask(self, "UI_DEMOLISH_Q", "UI_DEMOLISH_TEXT", "UI_DEMOLISH", func() -> void:
				if bool(sim.demolish(bid)["ok"]):
					toast(fmt("UI_DEMOLISHED", {"b": nm}))
					close_card()))
		foot.add_child(dm)
	if foot.get_child_count() > 0:
		_card_box.add_child(foot)


## Ícone + número curto; a frase que explica vai na dica do mouse (regra da interface: ícone e número,
## texto só quando não der).
func _stat(ic: String, text: String, tip: String, col: Color = C_TEXT) -> HBoxContainer:
	var h := _row([_icon_rect(ic), _label(text, col)])
	h.add_theme_constant_override("separation", 1)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h


## Vários _stat lado a lado, quebrando linha se não couber.
func _stats(items: Array) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.custom_minimum_size = Vector2(138, 0)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in items:
		f.add_child(it)
	return f


## Ícone + texto que quebra linha (frases longas dos cartões).
func _wrap_row(ic: String, text: String, col: Color = C_TEXT) -> HBoxContainer:
	var w := _wrap(text, col, 130.0)
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ir := _icon_rect(ic)
	ir.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return _row([ir, w])


## "comida, água, madeira, sucata, peças"
func _res_list() -> String:
	var a: Array[String] = []
	for r in VilaSim.RES:
		a.append(I18n.t("RES_" + r))
	return ", ".join(a)


func _progress_lines(b: Dictionary) -> void:
	var left := sim.site_eta(b)
	var lbl := I18n.t("UI_BUILDING")
	if bool(b.get("repair", false)):
		lbl = I18n.t("UI_REPAIRING")
	elif bool(b.get("rebuild", false)):
		lbl = I18n.t("UI_REBUILDING")
	elif String(b["state"]) == "upgrade":
		lbl = I18n.t("UI_UPGRADING")
	_card_box.add_child(_row([_icon_rect("relogio"), _label("%s · %s" % [lbl, fmt_clock(left)])]))
	if int(b["builder"]) < 0:
		var why := sim.site_wait_reason()
		_card_box.add_child(_wrap_row("saude" if why == "sick" else ("lua" if why == "night" else "alerta"), I18n.t("UI_WAIT_" + why), C_WARN))
	else:
		var who: Array[String] = [pname(sim.person(int(b["builder"])))]
		for hid in b.get("helpers", []):
			who.append(pname(sim.person(int(hid))))
		_card_box.add_child(_row([_icon_rect("pessoa"), _label(", ".join(who))]))
	var c := Button.new()
	c.text = I18n.t("UI_CANCEL")
	c.pressed.connect(func() -> void:
		sim.cancel(int(b["id"]))
		close_card())
	_card_box.add_child(c)


func _card_tower() -> void:
	var b := sim.tower_building()
	_clear_card()
	_header("torre", bname("torre") + " · " + fmt("UI_LEVEL", {"n": sim.tower}))
	if String(b["state"]) != "built":
		_progress_lines(b)
		return
	if sim.tower >= sim.tower_max():
		var gl := sim.goal()
		if String(gl["kind"]) == "journey":
			_card_box.add_child(_wrap(I18n.t("UI_TOWER_ELA"), C_MUTED))
			_card_box.add_child(_row([_icon_rect("radio"), _label(_goal_text(), C_AMBER)]))
		else:
			_card_box.add_child(_wrap(I18n.t("GOAL_done"), C_GOOD))
		return
	var n := sim.tower + 1
	_card_box.add_child(_label(fmt("UI_TOWER_NEXT", {"n": n}), C_MUTED))
	var unl: Array = sim.bal["tower_unlocks"].get(str(n), [])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	for u in unl:
		var s := String(u)
		var txt: String
		if "@" in s:
			var parts := s.split("@")
			txt = bname(parts[0], int(parts[1]))
		else:
			txt = bname(s)
		var soon: bool = not sim.bal["buildings"].has(s.split("@")[0]) and not s in ["area", "estrada", "ela"]
		grid.add_child(_row([_icon_rect("cadeado" if soon else "seta"), _label(txt + ((" (" + I18n.t("UI_SOON") + ")") if soon else ""), C_MUTED if soon else C_TEXT)]))
	_card_box.add_child(grid)
	var nx := sim.tower_next()
	_card_box.add_child(_row([_cost_row(nx["cost"]), _icon_rect("relogio"), _label(fmt_time(float(nx["time_s"])))]))
	var up := Button.new()
	up.text = I18n.t("UI_TOWER_UP")
	up.icon = icon("seta")
	up.disabled = not sim.can_afford(nx["cost"])
	up.pressed.connect(func() -> void:
		sim.tower_upgrade()
		_rebuild_card())
	_card_box.add_child(up)


func _passive_lines(passives: Array, box: Container, width: float = 92.0) -> void:
	if passives.is_empty():
		box.add_child(_wrap(I18n.t("UI_NO_PASSIVES"), C_MUTED, width))
	for ps in passives:
		var rar := String(ps["rar"])
		var pct := int(round(float(sim.bal["rarity"][rar]["bonus"]) * 100.0))
		# raridade: cor E palavra (cor não é o único sinal)
		var txt := "%s %s: %s" % [I18n.t("PAS_" + String(ps["id"])), I18n.t("RAR_" + rar), fmt("PASD_" + String(ps["id"]), {"p": pct})]
		box.add_child(_wrap(txt, RAR_COLOR[rar], width))


## Ícone do que a habilidade rende: o recurso, o martelo para obra, a seta para andar.
func _passive_icon(id: String) -> String:
	var job := String(sim.bal["passives"].get(id, {}).get("job", ""))
	match job:
		"build":
			return "martelo"
		"walk":
			return "seta"
		"eat":
			return "comida"
		"guard":
			return "escudo"
	return job if ICON.has(job) else "estrela"


## Versão curta das habilidades: nome na cor da raridade e o número; a frase inteira vai na dica.
func _passive_short(passives: Array, box: Container) -> void:
	if passives.is_empty():
		box.add_child(_label(I18n.t("UI_NO_PASSIVES"), C_MUTED))
	for ps in passives:
		var rar := String(ps["rar"])
		var id := String(ps["id"])
		var pct := int(round(float(sim.bal["rarity"][rar]["bonus"]) * 100.0))
		var row := _row([_icon_rect(_passive_icon(id)), _label(I18n.t("PAS_" + id), RAR_COLOR[rar]), _label(("-%d%%" if id == "come_pouco" else "+%d%%") % pct, RAR_COLOR[rar])])
		row.tooltip_text = "%s %s: %s" % [I18n.t("PAS_" + id), I18n.t("RAR_" + rar), fmt("PASD_" + id, {"p": pct})]
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(row)


func _card_person() -> void:
	var p := sim.person(_card_id)
	if p.is_empty():
		close_card()
		return
	_clear_card()
	var story := String(p["story"])
	var bio := I18n.t("PB_" + story) if story != "" else (I18n.t("BIO_%d" % int(p["bio"])) if int(p["bio"]) >= 0 else "")
	_header("pessoa", pname(p), "\"" + bio + "\"" if bio != "" else "")
	_card_box.add_child(_row([_icon_rect("relogio"), _label(_doing_text(p))]))
	var wy := sim.why(p)
	if wy != "":
		var jr := String(p["job"].get("res", ""))
		_card_box.add_child(_label(fmt("WHY_" + wy, {"r": I18n.t("RES_" + jr) if jr != "" else ""}), C_MUTED))
	# Cansaço: cada noite virada tira 10% até descansar 2 noites por ela. Com o sono em dia não mostra nada.
	var tired := int(p.get("tired", 0))
	if tired > 0:
		var pct := int(round((sim.rest_mult(p) - 1.0) * 100.0))
		var stip := fmt("TIP_TIRED", {"t": tired, "n": -pct,
				"left": tired * int(sim.bal["night"]["rest_nights_per_tired"]) - int(floor(float(p.get("rest", 0.0))))})
		_card_box.add_child(_stats([_stat("lua", "%+d%%" % pct, stip, C_WARN)]))
	var em := float(p.get("eat_mult", 1.0))
	if em > 1.0:
		_card_box.add_child(_stats([_stat("comida", "+%d%%" % int(round((em - 1.0) * 100.0)), fmt("TIP_EATS_MORE", {"n": int(round((em - 1.0) * 100.0))}), C_WARN)]))
	# Saúde: só aparece quando não está bem (fraca, doente, grave).
	var hs := sim.health_state(p)
	if hs != "ok":
		var hv := int(ceil(float(p["health"])))
		_card_box.add_child(_stats([_stat("saude", "%d" % hv, fmt("TIP_HEALTH_" + hs, {"h": hv}), C_AMBER if hs == "weak" else C_WARN)]))
		var sw := sim.sick_why(p)
		_card_box.add_child(_wrap_row("saude", fmt("UI_SICK_LINE", {"why": I18n.t("SICKWHY_" + sw), "cure": I18n.t("CURE_" + sw)}), C_WARN if hs != "weak" else C_AMBER))
	if p["hungry"]:
		_card_box.add_child(_row([_icon_rect("comida"), _icon_rect("alerta"), _label(I18n.t("UI_HUNGRY"), C_WARN)]))
	if p["thirsty"]:
		_card_box.add_child(_row([_icon_rect("agua"), _icon_rect("alerta"), _label(I18n.t("UI_THIRSTY"), C_WARN)]))
	var box := VBoxContainer.new()
	_passive_lines(p["passives"], box, 138.0)
	_card_box.add_child(box)
	var hint := _row([_icon_rect("seta"), _label(I18n.t("UI_ORDER_HINT"), C_MUTED)])
	hint.tooltip_text = I18n.t("TIP_ORDER_HINT")
	hint.mouse_filter = Control.MOUSE_FILTER_PASS
	_card_box.add_child(hint)


func _doing_text(p: Dictionary) -> String:
	var d := sim.doing(p)
	var parts := d.split(":")
	match parts[0]:
		"build":
			return fmt("DO_build", {"b": bname(parts[1])})
		"work":
			return fmt("DO_work", {"b": bname(parts[1])})
		"carry":
			return I18n.t("DO_carry")
		"forage":
			return I18n.t("DO_forage_" + parts[1])
		"sleep":
			return I18n.t("DO_sleep")
		"to_bed":
			return I18n.t("DO_to_bed")
		"rest":
			return I18n.t("DO_rest")
		"guard":
			return I18n.t("DO_guard")
		"move":
			return I18n.t("DO_move")
	return I18n.t("DO_idle")


func _card_gate() -> void:
	_clear_card()
	if sim.gate_group.is_empty():
		close_card()
		return
	var free := sim.beds_free()
	_header("pessoa", I18n.t("UI_GATE_TITLE"))
	var top := _row([_label(fmt("UI_GATE_PICK" if free == 1 else "UI_GATE_PICK_N", {"n": free}) if free > 0 else "", C_MUTED)])
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var none := Button.new()
	none.text = I18n.t("UI_GATE_NONE")
	none.pressed.connect(func() -> void:
		sim.choose(-1)
		close_card())
	top.add_child(none)
	_card_box.add_child(top)
	if free <= 0:
		_card_box.add_child(_row([_icon_rect("cama"), _icon_rect("alerta"), _label(I18n.t("UI_GATE_NOBED"), C_WARN)]))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 3)
	for i in sim.gate_group.size():
		var c: Dictionary = sim.gate_group[i]
		var pc := PanelContainer.new()
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(84, 0)
		pc.add_child(v)
		# A fala vai na dica (rosto, nome e coluna); no cartão ficam só ícones e números curtos.
		var bio := "\"" + I18n.t("BIO_%d" % int(c["bio"])) + "\""
		pc.tooltip_text = bio
		var face := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = load(ART + "person_%d.png" % int(c["look"]))
		at.region = Rect2(0, 0, 16, 16)
		face.texture = at
		face.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		face.custom_minimum_size = Vector2(16, 16)
		var tags: Array[Control] = [face, _label(String(c["name"]), C_AMBER)]
		for ps in c["passives"]:
			tags.append(_icon_rect(_passive_icon(String(ps["id"]))))
		var nr := _row(tags)
		nr.tooltip_text = bio
		nr.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(nr)
		v.add_child(HSeparator.new())
		_passive_short(c["passives"], v)
		var br: Dictionary = c.get("brings", {})
		for r in br:
			var brow := _row([_icon_rect(r), _label("+%d" % int(br[r]), C_GOOD)])
			brow.tooltip_text = fmt("UI_BRINGS", {"n": br[r], "r": I18n.t("RES_" + r)})
			brow.mouse_filter = Control.MOUSE_FILTER_PASS
			v.add_child(brow)
		var em := float(c.get("eat_mult", 1.0))
		if em > 1.0:
			v.add_child(_stat("comida", "+%d%%" % int(round((em - 1.0) * 100.0)), fmt("TIP_EATS_MORE", {"n": int(round((em - 1.0) * 100.0))}), C_WARN))
		# Empurra o botão para o fundo: os três "Escolher" ficam na mesma linha.
		var fill := Control.new()
		fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(fill)
		var pick := Button.new()
		pick.text = I18n.t("UI_CHOOSE")
		pick.disabled = free <= 0
		var idx := i
		pick.pressed.connect(func() -> void:
			var nm := String(c["name"])
			sim.choose(idx)
			toast(fmt("UI_JOINED", {"name": nm}))
			close_card())
		v.add_child(pick)
		cols.add_child(pc)
	_card_box.add_child(cols)
	var ap := CheckBox.new()
	ap.text = I18n.t("UI_AUTO_PICK")
	ap.tooltip_text = I18n.t("TIP_AUTO_PICK")
	ap.button_pressed = sim.auto_pick
	ap.toggled.connect(func(on: bool) -> void:
		sim.auto_pick = on
		if on and free > 0:
			var nm := String(sim.gate_group[sim.best_pick()]["name"])
			sim.choose(sim.best_pick())
			toast(fmt("UI_JOINED", {"name": nm}))
			close_card())
	_card_box.add_child(ap)


var build_tab := "base"   # aba do modo construção: base, defense, deco
var build_tab_btns: Dictionary = {}   # aba -> botão (o tutorial aponta para a de defesa)


## Modo construção (estilo Clash): faixa embaixo com um cartão por prédio, em abas. Clicar num
## cartão põe o fantasma no mapa; com o modo aberto, clicar num prédio do mapa pega ele para mover.
func _card_build() -> void:
	_clear_card()
	build_btns.clear()
	build_tab_btns.clear()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	head.add_child(_icon_rect("martelo"))
	for tab in [["base", "UI_TAB_BASE"], ["defense", "UI_DEFENSE"], ["deco", "UI_DECO"]]:
		var key := String(tab[0])
		if key != "base" and _tab_types(key).filter(func(t: String) -> bool: return sim.unlocked(t)).is_empty():
			continue
		var tb := Button.new()
		tb.text = I18n.t(String(tab[1]))
		tb.theme_type_variation = "FlatButton" if build_tab != key else ""
		tb.toggle_mode = false
		build_tab_btns[key] = tb
		tb.pressed.connect(func() -> void:
			build_tab = key
			_rebuild_card())
		head.add_child(tb)
	if build_tab == "defense":
		var nn := sim.defense.next_night()
		if int(nn.get("n", 0)) > 0:
			head.add_child(_stat("zumbi", str(int(nn["n"])), _night_forecast_tip(nn), C_WARN if bool(nn.get("horde", false)) else C_MUTED))
	var hint := _label(I18n.t("UI_BUILD_MOVE_HINT"), C_MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.clip_text = true
	head.add_child(hint)
	var x := Button.new()
	x.text = "x"
	x.custom_minimum_size = Vector2(10, 10)
	x.tooltip_text = I18n.t("TIP_BUILD_EXIT")
	x.pressed.connect(close_card)
	head.add_child(x)
	_card_box.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var locked: Array[String] = []
	for type in _tab_types(build_tab):
		if sim.unlocked(type):
			row.add_child(_build_tile(type))
		else:
			locked.append(type)
	for type in locked:
		row.add_child(_build_tile(type))
	# Só a fileira rola de lado (a roda do mouse também); o cabeçalho com o X fica parado.
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var wide := row.get_combined_minimum_size().x > W - 12.0
	sc.custom_minimum_size = Vector2(W - 12.0, 50.0 + (8.0 if wide else 0.0))
	sc.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			var bi := (ev as InputEventMouseButton).button_index
			if bi == MOUSE_BUTTON_WHEEL_UP or bi == MOUSE_BUTTON_WHEEL_DOWN:
				sc.scroll_horizontal += -40 if bi == MOUSE_BUTTON_WHEEL_UP else 40
				sc.accept_event())
	sc.add_child(row)
	_card_box.add_child(sc)


func _tab_types(tab: String) -> Array[String]:
	var key: String = {"base": "build_order", "defense": "defense_order", "deco": "deco_order"}[tab]
	var out: Array[String] = []
	for t in sim.bal.get(key, []):
		out.append(String(t))
	return out


## Figura do prédio no nível 1 (a mesma do mapa).
func _type_tex(type: String) -> Texture2D:
	for n in [type + "_1", type]:
		if ResourceLoader.exists(ART + n + ".png"):
			var t: Texture2D = load(ART + n + ".png")
			if type == "fogueira":
				var at := AtlasTexture.new()
				at.atlas = t
				at.region = Rect2(0, 0, t.get_width() / 4.0, t.get_height())
				return at
			return t
	return null


## Um cartão da faixa: figura, nome, custo (ou o cadeado com o nível da torre).
func _build_tile(type: String) -> Button:
	var d := sim.def(type)
	var lv: Dictionary = d["levels"][0]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(58, 50)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 2
	box.offset_right = -2
	box.offset_top = 2
	box.offset_bottom = -1
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)
	var pic := TextureRect.new()
	pic.texture = _type_tex(type)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(0, 24)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic)
	var nm := _label(bname(type))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(nm)
	var tip := bname(type) + ": " + I18n.t("BD_" + type)
	if not sim.unlocked(type):
		pic.modulate = Color(0.25, 0.22, 0.3)
		var need: int = int(d.get("tower", 1))
		var lk := _row([_icon_rect("cadeado"), _label(fmt("UI_LOCKED_TOWER", {"n": need}), C_MUTED)])
		lk.alignment = BoxContainer.ALIGNMENT_CENTER
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lk)
		btn.disabled = true
		btn.tooltip_text = fmt("UI_LOCKED_TOWER", {"n": need}) + "\n" + tip
		return btn
	var full := sim.at_limit(type)
	var no_spot := not full and not sim.has_spot(type)
	var free := type == "mina" and sim.mine_credits > 0   # minas do mascate: saem de graça
	var cost_ok := free or sim.can_afford(lv["cost"])
	btn.disabled = full or no_spot or not cost_ok or (tut_only != "" and tut_only != type)
	var foot: Control
	if full:
		foot = _label("%d/%d" % [sim._count_any(type), sim.limit(type)], C_WARN)
		tip = _limit_tip(type) + "\n" + tip
	elif free:
		foot = _stat("check", "x%d" % sim.mine_credits, fmt("TIP_FREE_MINES", {"n": sim.mine_credits}), C_GOOD)
	else:
		foot = _cost_row(lv["cost"])
	if no_spot:
		tip = _no_spot_tip() + "\n" + tip
	if d.has("defense"):
		tip += "\n" + _defense_tip(type, lv)
	if sim.limit(type) >= 0 and not full:
		tip += "\n" + _limit_tip(type) + " (%d/%d)" % [sim._count_any(type), sim.limit(type)]
	if float(lv["time_s"]) > 0.0:
		tip += "\n" + fmt_time(float(lv["time_s"]))
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if foot is BoxContainer:
		(foot as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	else:
		(foot as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(foot)
	if btn.disabled:
		pic.modulate = Color(1, 1, 1, 0.45)
	btn.tooltip_text = tip
	build_btns[type] = btn
	btn.pressed.connect(func() -> void:
		build_chosen.emit(type))
	return btn


# ================================================================ defesa
## Caixa do turno: o que rendeu com o jogo fechado e não coube no depósito, com o botão de coletar.
func _box_lines() -> void:
	if sim.box.is_empty():
		return
	var items: Array = []
	for r in VilaSim.RES:
		if sim.box.has(r) and float(sim.box[r]) >= 1.0:
			items.append(_stat(r, "+%d" % int(sim.box[r]), I18n.t("TIP_BOX")))
	if items.is_empty():
		return
	var cb := Button.new()
	cb.text = I18n.t("UI_COLLECT")
	cb.icon = icon("check")
	cb.tooltip_text = I18n.t("TIP_BOX")
	cb.pressed.connect(func() -> void:
		var got := sim.collect_box()
		if got.is_empty():
			toast(I18n.t("UI_BOX_FULL"))
		elif sim.box.is_empty():
			cb.disabled = true   # cartão de boas-vindas não se refaz sozinho
		refresh()
		_rebuild_card())
	_card_box.add_child(_label(I18n.t("UI_BOX"), C_AMBER))
	_card_box.add_child(_stats(items))
	_card_box.add_child(cb)


## Avariado ou em ruína: a linha que diz e o botão de consertar/reconstruir com o custo. Devolve true
## quando o resto do cartão não vale (ruína não produz nem sobe de nível).
func _damage_lines(b: Dictionary) -> bool:
	var bid := int(b["id"])
	if bool(b.get("ruin", false)):
		_card_box.add_child(_wrap_row("ruina", I18n.t("UI_RUIN"), C_WARN))
		var cost: Dictionary = sim.defense.rebuild_cost(b)
		var rb := Button.new()
		rb.text = I18n.t("UI_REBUILD")
		rb.icon = icon("martelo")
		rb.disabled = not sim.can_afford(cost)
		rb.tooltip_text = I18n.t("TIP_REBUILD")
		rb.pressed.connect(func() -> void:
			if not bool(sim.rebuild(bid)["ok"]):
				toast(I18n.t("UI_NO_MONEY"))
			_rebuild_card())
		_card_box.add_child(_row([rb, _cost_row(cost)]))
		return true
	var mh := sim.defense.max_hp(b)
	var h := sim.defense.hp(b)
	if h >= mh:
		if _has_hp(b):
			_card_box.add_child(_stats([_hp_stat(b)]))
		return false
	var broken := bool(b.get("broken", false))
	if broken:
		_card_box.add_child(_wrap_row("avariado", I18n.t("UI_BROKEN"), C_WARN))
	else:
		_card_box.add_child(_stats([_hp_stat(b)]))
	var rc: Dictionary = sim.defense.repair_cost(b)
	var fx := Button.new()
	fx.text = I18n.t("UI_REPAIR")
	fx.icon = icon("avariado")
	fx.disabled = not sim.can_afford(rc)
	fx.tooltip_text = I18n.t("TIP_REPAIR_WALL") if String(b["type"]) == "muro" else I18n.t("TIP_REPAIR")
	fx.pressed.connect(func() -> void:
		if not bool(sim.repair(bid)["ok"]):
			toast(I18n.t("UI_NO_MONEY"))
		_rebuild_card())
	_card_box.add_child(_row([fx, _cost_row(rc)]))
	if String(b["type"]) == "muro":
		_wall_repair_all()
	return broken   # avariado não produz nem sobe de nível até consertar


## Prédio que zumbi derruba (casas, produção, defesas) ou muro: tem vida para mostrar.
func _has_hp(b: Dictionary) -> bool:
	return String(b["type"]) == "muro" or sim.defense.attackable(b)


## 🛡 120/120, como o 17/18 das pessoas. Vermelho quando apanhou. A frase vai na dica.
func _hp_stat(b: Dictionary) -> Control:
	var mh := int(sim.defense.max_hp(b))
	var h := int(ceilf(sim.defense.hp(b)))
	var tip := fmt("TIP_HP_WALL_N", {"h": h, "m": mh}) if String(b["type"]) == "muro" else fmt("TIP_HP_N", {"h": h, "m": mh})
	return _stat("escudo", "%d/%d" % [h, mh], tip, C_WARN if h < mh else C_TEXT)


## Quanto a vida sobe no próximo nível (🛡 +60), com "120 → 180" na dica.
func _hp_gain(b: Dictionary, nl: int) -> Control:
	if not _has_hp(b):
		return null
	var nb := b.duplicate()
	nb["level"] = nl
	var a := int(sim.defense.max_hp(b))
	var z := int(sim.defense.max_hp(nb))
	if z <= a:
		return null
	return _stat("escudo", "+%d" % (z - a), fmt("TIP_GAIN_HP", {"a": a, "b": z}), C_GOOD)


## Números da defesa (dano, alcance, intervalo); a vida fica no 🛡 h/máx do cartão. As frases que
## explicam ficam na dica.
func _defense_stats(tp: String, lv: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	var kind := String(sim.def(tp).get("defense", ""))
	if kind == "light":
		out.append(_stat("espada", "+%d%%" % int(round(float(lv.get("buff", 0.0)) * 100.0)), fmt("TIP_DEF_LIGHT", {"n": int(round(float(lv.get("buff", 0.0)) * 100.0)), "r": lv.get("radius", 0)})))
		out.append(_stat("mover", "%.0f" % float(lv.get("radius", 0)), fmt("TIP_DEF_RANGE", {"n": lv.get("radius", 0)})))
	elif lv.has("dmg"):
		var dtip := fmt("TIP_DEF_DMG", {"n": lv["dmg"]})
		if lv.has("splash"):
			dtip += "\n" + fmt("TIP_DEF_SPLASH", {"n": lv["splash"]})
		if lv.has("chain"):
			dtip += "\n" + fmt("TIP_DEF_CHAIN", {"n": lv["chain"]})
		out.append(_stat("espada", str(int(lv["dmg"])), dtip))
		if lv.has("range"):
			out.append(_stat("mover", "%.1f" % float(lv["range"]), fmt("TIP_DEF_RANGE", {"n": lv["range"]})))
		if lv.has("rate_s"):
			out.append(_stat("relogio", "%.1fs" % float(lv["rate_s"]), fmt("TIP_DEF_RATE", {"n": lv["rate_s"]})))
	if not b.is_empty() and int(b.get("guard", -1)) >= 0:
		var gp := sim.person(int(b["guard"]))
		if not gp.is_empty():
			out.append(_stat("pessoa", pname(gp), fmt("TIP_GUARD", {"n": int(round((sim.defense._rate_mult(b) - 1.0) * 100.0))}), C_GOOD))
	return out


## Muro: sobe todos os do mesmo nível de uma vez (como no Clash), pagando por todos.
func _wall_upgrade_all(b: Dictionary) -> void:
	var lvl := int(b["level"])
	var n := 0
	for o in sim.buildings:
		if String(o["type"]) == "muro" and int(o["level"]) == lvl:
			n += 1
	var nd := sim.level_def(b, lvl + 1)
	if n < 2 or nd.is_empty() or not sim.unlocked("muro", lvl + 1):
		return
	var all := {}
	for r in nd["cost"]:
		all[r] = float(nd["cost"][r]) * n
	var ub := Button.new()
	ub.text = fmt("UI_WALLS_ALL", {"n": n})
	ub.icon = icon("seta")
	ub.disabled = not sim.can_afford(all)
	ub.tooltip_text = fmt("TIP_WALLS_ALL", {"n": n, "b": bname("muro", lvl + 1)})
	ub.pressed.connect(func() -> void:
		var r := sim.upgrade_walls(lvl)
		if bool(r["ok"]):
			toast(fmt("UI_WALLS_DONE", {"n": r["n"], "b": bname("muro", lvl + 1)}))
		else:
			toast(I18n.t("UI_NO_MONEY"))
		_rebuild_card())
	_card_box.add_child(_row([ub, _cost_row(all)]))


## Muro: conserta todos os que têm estrago de uma vez, pagando por todos (como o "subir todos").
func _wall_repair_all() -> void:
	var wf := sim.walls_to_fix()
	var n: int = (wf["ids"] as Array).size()
	if n < 2:
		return
	var rb := Button.new()
	rb.text = fmt("UI_WALLS_FIX_ALL", {"n": n})
	rb.icon = icon("martelo")
	rb.disabled = not sim.can_afford(wf["cost"])
	rb.tooltip_text = fmt("TIP_WALLS_FIX_ALL", {"n": n})
	rb.pressed.connect(func() -> void:
		var r := sim.repair_all_walls()
		if bool(r["ok"]):
			toast(fmt("UI_WALLS_FIXED", {"n": r["n"]}))
		else:
			toast(I18n.t("UI_NO_MONEY"))
		_rebuild_card())
	_card_box.add_child(_row([rb, _cost_row(wf["cost"])]))


## Dica do menu de obras para uma defesa: os números em frase.
func _defense_tip(type: String, lv: Dictionary) -> String:
	var parts: PackedStringArray = []
	if lv.has("dmg"):
		parts.append(fmt("TIP_DEF_DMG", {"n": lv["dmg"]}))
	if lv.has("range"):
		parts.append(fmt("TIP_DEF_RANGE", {"n": lv["range"]}))
	if lv.has("hp"):
		parts.append(I18n.t("TIP_HP_WALL") if type == "muro" else I18n.t("TIP_HP"))
	if type == "mina" and sim.mine_credits > 0:
		parts.append(fmt("TIP_FREE_MINES", {"n": sim.mine_credits}))
	return "\n".join(parts)


## "Esta noite: 2 zumbis" + horda/chefe + o que vem amanhã.
func _night_forecast_tip(nn: Dictionary) -> String:
	var t := fmt("TIP_RAID_TONIGHT" if sim.is_night() or sim.local_hour() >= 12.0 else "TIP_RAID_NEXT", {"n": nn["n"]})
	if bool(nn.get("horde", false)):
		t += "\n" + I18n.t("TIP_RAID_HORDE")
	if int(nn.get("boss", 0)) > 0:
		t += "\n" + fmt("TIP_RAID_BOSS", {"n": nn["boss"]})
	var tomorrow := sim.defense.forecast(int(nn["day"]) + 1)
	if bool(tomorrow["horde"]) and not bool(nn.get("horde", false)):
		t += "\n" + I18n.t("TIP_RAID_HORDE_TOMORROW")
	t += "\n" + I18n.t("TIP_RAID_HOW")
	return t


func _no_spot_tip() -> String:
	if sim.tower < sim.tower_max():
		return fmt("TIP_NO_SPOT_TOWER", {"t": sim.tower + 1})
	return I18n.t("TIP_NO_SPOT")


## Por que o prédio tem limite e quando libera mais.
func _limit_tip(type: String) -> String:
	var l: Variant = sim.def(type).get("limit", -1)
	if l is Dictionary and sim.tower < sim.tower_max():
		return fmt("TIP_LIMIT_TOWER", {"n": sim.limit(type), "t": sim.tower + 1})
	if l is Dictionary:
		return fmt("TIP_LIMIT_MAX", {"n": sim.limit(type)})
	return I18n.t("TIP_LIMIT_ONE")


# ================================================================ rádio
## Uma fala nova chegou com a vila aberta: balão curto em cima e conta no botão do rádio.
func on_radio(line: Dictionary) -> void:
	radio_unread += 1
	if quiet or String(line.get("kind", "")) == "reaction":
		return
	# Chiado não é notícia: só fala nova vira aviso (e nunca no meio do ataque).
	if String(line.get("speaker", "ruido")) == "ruido":
		return
	var who := I18n.t("speaker." + String(line.get("speaker", "ruido")))
	toast(who + ": " + I18n.t(String(line["text_key"])), TOAST_AMBIENT, 7.0)


func show_radio() -> void:
	radio_unread = 0
	_open("radio")


func _card_radio() -> void:
	_clear_card()
	_header("caderno", I18n.t("UI_RADIO_LOG"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(170, minf(130.0, H - 60.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	scroll.add_child(col)
	var heard: Array = sim.radio_heard
	if heard.is_empty():
		col.add_child(_wrap(I18n.t("UI_RADIO_EMPTY"), C_MUTED, 160))
	# Mais nova em cima.
	for i in range(heard.size() - 1, maxi(-1, heard.size() - 41), -1):
		var l := sim.line(String(heard[i]))
		if l.is_empty():
			continue
		col.add_child(_label(I18n.t("speaker." + String(l["speaker"])), C_AMBER))
		col.add_child(_wrap(I18n.t(String(l["text_key"])), C_TEXT, 160))
	_card_box.add_child(scroll)


# ================================================================ mercador
func show_merchant() -> void:
	_open("merchant")


func _card_merchant() -> void:
	_clear_card()
	_header("mercador", I18n.t("UI_MERCHANT"))
	if not sim.merchant_here():
		var md: Dictionary = sim.bal["merchant"]
		if sim._count("praca") == 0:
			_card_box.add_child(_wrap(I18n.t("UI_MERCHANT_NEED"), C_MUTED))
		else:
			var hs: Array[String] = []
			for hr in md["hours"]:
				hs.append("%02d:%02d" % [int(hr), int(fmod(float(hr), 1.0) * 60.0)])
			_card_box.add_child(_wrap(fmt("UI_MERCHANT_AWAY", {"h": ", ".join(hs)}), C_MUTED))
		_auto_sell_box()
		return
	var m: Dictionary = sim.merchant
	_card_box.add_child(_row([_icon_rect("relogio"), _label(fmt("UI_MERCHANT_LEAVES", {"t": fmt_time(float(m["until"]) - sim.t)}), C_MUTED)]))
	# Vender: um lote de cada coisa que ele compra.
	_card_box.add_child(_label(I18n.t("UI_SELL"), C_AMBER))
	var lot: int = int(sim.bal["merchant"]["lot"])
	for r in m["prices"]:
		var b := Button.new()
		b.icon = icon(String(r))
		b.text = fmt("UI_SELL_LOT", {"n": lot, "r": I18n.t("RES_" + String(r)), "p": sim.lot_price(String(r))})
		b.disabled = float(sim.stock[r]) < lot
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var rr := String(r)
		b.pressed.connect(func() -> void:
			var res := sim.sell_lot(rr)
			if not bool(res["ok"]):
				toast(I18n.t("UI_FULL"))
			_rebuild_card())
		_card_box.add_child(b)
	# Comprar: as 3 ofertas desta visita.
	_card_box.add_child(_label(I18n.t("UI_BUY"), C_AMBER))
	var offers: Array = m["offers"]
	for i in offers.size():
		var id := String(offers[i])
		var o := sim.offer_def(id)
		var row := HBoxContainer.new()
		var b := Button.new()
		b.text = I18n.t("OF_" + id)
		b.tooltip_text = I18n.t("OFD_" + id)
		var sold := (m["bought"] as Array).has(i)
		var need_group := bool(o.get("needs_group", false)) and sim.gate_group.is_empty()
		b.disabled = sold or need_group or not sim.can_afford(o["cost"])
		if sold:
			b.text += " · " + I18n.t("UI_SOLD")
		elif need_group:
			b.tooltip_text += " " + I18n.t("UI_NEEDS_GROUP")
		var ii := i
		b.pressed.connect(func() -> void:
			sim.buy_offer(ii)
			_rebuild_card())
		row.add_child(b)
		row.add_child(_cost_row(o["cost"]))
		_card_box.add_child(row)
	var rq: Dictionary = m["request"]
	if not rq.is_empty():
		var rb := Button.new()
		rb.icon = icon(String(rq["res"]))
		rb.text = fmt("UI_REQUEST", {"n": rq["n"], "r": I18n.t("RES_" + String(rq["res"])), "p": rq["pay"]})
		rb.tooltip_text = I18n.t("UI_DELIVER")
		rb.disabled = float(sim.stock[String(rq["res"])]) < float(rq["n"])
		rb.pressed.connect(func() -> void:
			sim.fulfill_request()
			_rebuild_card())
		_card_box.add_child(rb)
	_auto_sell_box()


func _auto_sell_box() -> void:
	var cb := CheckBox.new()
	cb.text = I18n.t("UI_AUTO_SELL")
	cb.button_pressed = sim.auto_sell
	cb.toggled.connect(func(on: bool) -> void: sim.auto_sell = on)
	_card_box.add_child(cb)


# ================================================================ modo gestão
## Painel à esquerda (a alça da janela abre e fecha): o balanço de cada recurso por minuto, energia,
## as obras na fila e o que cada pessoa está fazendo. Com a janela maior, sobra mundo do lado.
func set_manage(open: bool) -> void:
	_manage.visible = open
	if _manage_btn != null:
		_manage_btn.modulate = C_AMBER if open else Color.WHITE
	if handle != null and handle.drawer_open != open:
		handle.set_drawer_open(open)
	if open:
		_manage_acc = 1.0
		refresh()


func manage_open() -> bool:
	return _manage.visible


func _rebuild_manage() -> void:
	for c in _manage_box.get_children():
		_manage_box.remove_child(c)
		c.queue_free()
	var b := _manage_box
	b.add_child(_label(I18n.t("UI_MANAGE_RES"), C_AMBER))
	for r in VilaSim.RES:
		if r == "pecas" and sim.tower < 3 and float(sim.stock[r]) <= 0.0:
			continue
		var fl := sim.rate(r)
		var row := _row([_icon_rect(r), _label("%d/%d" % [int(sim.stock[r]), int(sim.cap(r))])])
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)
		for c: Control in _flow_stats(r, fl, false):
			row.add_child(c)
		row.add_theme_constant_override("separation", 3)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.tooltip_text = _flow_tip(r, fl)
		b.add_child(row)
	var pw := sim.power()
	if float(pw["out"]) > 0.0 or float(pw["use"]) > 0.0:
		var short := float(pw["use"]) > float(pw["out"])
		b.add_child(_row([_icon_rect("energia"), _label(fmt("UI_POWER_LINE", {"out": int(pw["out"]), "use": int(pw["use"])}), C_WARN if short else C_TEXT)]))
	b.add_child(_label(I18n.t("UI_MANAGE_SITES"), C_AMBER))
	var any := false
	for bd in sim.buildings:
		var st := String(bd["state"])
		if st == "built":
			continue
		any = true
		var who := I18n.t("UI_WAIT_" + sim.site_wait_reason()) if int(bd["builder"]) < 0 else pname(sim.person(int(bd["builder"])))
		var btn := Button.new()
		btn.theme_type_variation = "FlatButton"
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.custom_minimum_size = Vector2(140, 0)
		btn.icon = icon("martelo")
		btn.text = "%s · %s" % [bname(String(bd["type"]), int(bd["level"]) + (1 if st == "upgrade" and not bool(bd.get("repair", false)) and not bool(bd.get("rebuild", false)) else 0)), fmt_time(float(bd["total"]) - float(bd["progress"]))]
		btn.tooltip_text = who
		var id := int(bd["id"])
		btn.pressed.connect(func() -> void: show_building(id))
		b.add_child(btn)
	if not any:
		b.add_child(_label(I18n.t("UI_MANAGE_NONE"), C_MUTED))
	b.add_child(_label(I18n.t("UI_MANAGE_PEOPLE") + " %d/%d" % [sim.people.size(), sim.beds_total()], C_AMBER))
	if true:   # o porto recebe gente desde a antena 1
		var ap := CheckBox.new()
		ap.text = I18n.t("UI_AUTO_PICK")
		ap.tooltip_text = I18n.t("TIP_AUTO_PICK")
		ap.button_pressed = sim.auto_pick
		ap.toggled.connect(func(on: bool) -> void: sim.auto_pick = on)
		b.add_child(ap)
	for p in sim.people:
		var pb := Button.new()
		pb.theme_type_variation = "FlatButton"
		pb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pb.clip_text = true
		pb.custom_minimum_size = Vector2(140, 0)
		var warn := bool(p["hungry"]) or bool(p["thirsty"])
		pb.icon = icon("alerta" if warn else "pessoa")
		pb.text = pname(p) + " · " + _doing_text(p)
		pb.tooltip_text = pb.text
		var pid := int(p["id"])
		pb.pressed.connect(func() -> void: show_person(pid))
		b.add_child(pb)
