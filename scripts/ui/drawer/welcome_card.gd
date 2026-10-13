class_name DrawerWelcomeCard
extends PanelContainer
## Resumo de "bem-vindo de volta" (Game.welcome_back): cobre o conteúdo da gaveta
## até o jogador seguir. Duas colunas curtas; o detalhe fica no Diário.

signal dismissed(go_radio: bool)

var _box: VBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.nine("panel_9s", 6.0, 3.0))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 1)
	add_child(_box)
	visible = false


func show_summary(s: Dictionary) -> void:
	DrawerUi.clear(_box)
	var hours: int = roundi(float(s.get("hours", 0)))
	var visits: int = int(s.get("visits", 0))
	var scrap: int = int(s.get("scrap", 0))
	var harvested: int = int(s.get("harvested", 0))
	var nights: int = int(s.get("nights", 0))
	var lines: Array = s.get("lines", []) if s.get("lines", []) is Array else []
	var head := HBoxContainer.new()
	var t: Label = DrawerUi.label(I18nRef.t("welcome.title"), "LabelTitle")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(DrawerUi.label(I18nRef.t("welcome.hours", {"hours": hours}), "LabelSmall"))
	_box.add_child(head)
	if visits == 0 and scrap == 0 and harvested == 0 and lines.is_empty():
		_box.add_child(DrawerUi.label(I18nRef.t("welcome.quiet"), "", true))
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 0)
		grid.add_child(DrawerUi.icon_text("sucata", I18nRef.t("welcome.scrap", {"scrap": scrap}), "LabelAmber"))
		grid.add_child(DrawerUi.icon_text("cesto", I18nRef.t("welcome.harvested", {"harvested": harvested}), "LabelSmall"))
		grid.add_child(DrawerUi.icon_text("porta", I18nRef.t("welcome.visits", {"visits": visits}), "LabelSmall"))
		grid.add_child(DrawerUi.icon_text("tempo", I18nRef.t("drawer.welcome.night_one") if nights == 1 else I18nRef.t("welcome.nights", {"nights": nights}), "LabelSmall"))
		for c in grid.get_children():
			(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_box.add_child(grid)
		if not lines.is_empty():
			var l: HBoxContainer = DrawerUi.icon_text("radio", I18nRef.t("welcome.lines", {"n": lines.size()}), "")
			(l.get_child(1) as Label).add_theme_color_override("font_color", UiTheme.SIGNAL)
			_box.add_child(l)
	if bool(s.get("capped", false)):
		_box.add_child(DrawerUi.label(I18nRef.t("welcome.capped", {"hours": hours}), "LabelMuted", true))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(sp)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	if not lines.is_empty():
		var r: Button = DrawerUi.button(I18nRef.t("drawer.welcome.radio"), "radio")
		r.name = "RadioButton"
		r.pressed.connect(func() -> void: _close(true))
		row.add_child(r)
	var go: Button = DrawerUi.button(I18nRef.t("welcome.btn"))
	go.name = "GoButton"
	go.pressed.connect(func() -> void: _close(false))
	row.add_child(go)
	_box.add_child(row)
	visible = true


func _close(go_radio: bool) -> void:
	visible = false
	dismissed.emit(go_radio)
