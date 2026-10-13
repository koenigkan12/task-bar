class_name DrawerRadioTab
extends VBoxContainer
## Aba Rádio: Diário (mais nova no topo, novas marcadas), estação do bunker e "marcar lidas".
## As falas ficam marcadas como novas enquanto a aba está aberta; a gaveta chama
## mark_read() quando o jogador sai da aba ou fecha a gaveta.

var drawer: Drawer
var _sig: String = ""
var _scroll: ScrollContainer
var _list: VBoxContainer
var _unread: Label
var _station_btn: Button
var _next_btn: Button
var _read_btn: Button


func _init() -> void:
	add_theme_constant_override("separation", 1)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 3)
	add_child(top)
	_station_btn = DrawerUi.button(I18nRef.t("drawer.station"), "radio")
	_station_btn.toggle_mode = true
	_station_btn.toggled.connect(_on_station_toggled)
	top.add_child(_station_btn)
	_next_btn = DrawerUi.icon_button("arrow_up")
	_next_btn.icon = DrawerBuildTab._rotated_arrow(false)
	_next_btn.pressed.connect(_on_station_next)
	top.add_child(_next_btn)
	_unread = DrawerUi.colored("", UiTheme.SIGNAL, "")
	_unread.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unread.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_unread)
	_read_btn = DrawerUi.button(I18nRef.t("ui.btn.mark_read"), "check")
	_read_btn.pressed.connect(mark_read)
	top.add_child(_read_btn)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	_scroll.add_child(_list)


func refresh(force: bool = false) -> void:
	if not drawer.has_game():
		return
	var g: Node = drawer.game
	var entries: Array = g.diary()
	var unread: int = int(g.unread_count())
	var station: bool = _audio_call("is_station_on", false)
	var sig: String = "%s|%d|%s|%s" % [str(entries), unread, station, I18nRef.locale()]
	if sig == _sig and not force:
		return
	_sig = sig
	_station_btn.text = I18nRef.t("drawer.station")
	_station_btn.tooltip_text = I18nRef.t("drawer.station.help")
	_station_btn.set_pressed_no_signal(station)
	_station_btn.disabled = not _has_audio("set_station")
	_next_btn.tooltip_text = I18nRef.t("drawer.station.next")
	_next_btn.disabled = not station
	_read_btn.text = I18nRef.t("ui.btn.mark_read")
	_read_btn.disabled = unread == 0
	_unread.text = "" if unread == 0 else (I18nRef.t("diary.unread.one") if unread == 1 else I18nRef.t("diary.unread.other", {"n": unread}))
	DrawerUi.clear(_list)
	if entries.is_empty():
		_list.add_child(DrawerUi.label(I18nRef.t("ui.radio.empty"), "LabelMuted", true))
		return
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("at_min", 0)) > float(b.get("at_min", 0)))
	for e: Dictionary in entries:
		_list.add_child(_entry_view(e))


func mark_read() -> void:
	if drawer.has_game() and int(drawer.game.unread_count()) > 0:
		drawer.game.mark_diary_read()
	refresh(true)


func _entry_view(e: Dictionary) -> Control:
	var kind: String = str(e.get("kind", "radio"))
	var unread: bool = not bool(e.get("read", true))
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	# barrinha à esquerda: verde se é nova, escura se já lida
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(2, 0)
	bar.color = UiTheme.SIGNAL if unread else UiTheme.DARK3
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	box.add_child(col)
	# cabeçalho: Dia N · 12h30 · quem falou (ou o tipo da entrada)
	var head: PackedStringArray = PackedStringArray()
	head.append(I18nRef.t("diary.day", {"day": int(e.get("day", 0)) + 1}))
	head.append(DrawerUi.clock(float(e.get("tod", 0.0))))
	var speaker: String = str(e.get("speaker", ""))
	if kind in ["radio", "her"] and speaker != "":
		head.append(I18nRef.t("speaker." + speaker))
	else:
		head.append(I18nRef.t("diary.kind." + kind))
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 3)
	hrow.add_child(DrawerUi.icon(_kind_icon(kind)))
	var hl: Label = DrawerUi.fill_label(" · ".join(head), "LabelSmall")
	hrow.add_child(hl)
	if bool(e.get("while_away", false)) and kind != "away":
		hrow.add_child(DrawerUi.label(I18nRef.t("drawer.diary.away_tag"), "LabelMuted"))
	col.add_child(hrow)
	var args: Variant = e.get("args", {})
	var body: Label = DrawerUi.label(I18nRef.t(str(e.get("key", "")), args if args is Dictionary else {}), "", true)
	if kind == "her":
		body.theme_type_variation = "LabelAmber"
	elif kind == "away":
		body.theme_type_variation = "LabelSmall"
	col.add_child(body)
	if str(e.get("cue", "")) == "voice_her":
		col.add_child(DrawerUi.label(I18nRef.t("diary.caption.voice_her"), "LabelMuted"))
	return box


static func _kind_icon(kind: String) -> String:
	match kind:
		"her":
			return "estrela"
		"note":
			return "book"
		"away":
			return "tempo"
		"system":
			return "gear"
	return "radio"


func _has_audio(method: String) -> bool:
	var a: Node = drawer.audio()
	return a != null and a.has_method(method)


func _audio_call(method: String, fallback: Variant) -> Variant:
	if not _has_audio(method):
		return fallback
	return drawer.audio().call(method)


func _on_station_toggled(on: bool) -> void:
	if _has_audio("set_station"):
		drawer.audio().call("set_station", on)
	refresh(true)


func _on_station_next() -> void:
	if _has_audio("station_next"):
		drawer.audio().call("station_next")
	refresh(true)
