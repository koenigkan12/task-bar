class_name DrawerStateTab
extends HBoxContainer
## Aba Estado: o que ele está fazendo, a caixa (sucata, estoque, trocas), energia e antena,
## e depois do contato a jornada da casa dela.

const BALANCE_PATH: String = "res://data/balance.json"

var drawer: Drawer
var _sig: String = ""
var _cols: Array[VBoxContainer] = []
static var _visits_table: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 6)
	for i in 3:
		var c := VBoxContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_stretch_ratio = 1.0
		c.add_theme_constant_override("separation", 1)
		add_child(c)
		_cols.append(c)


## Chave status.* do que ele está fazendo agora (mesma lógica da seção 9, em resumo).
static func doing_key(g: Node) -> String:
	if not bool(g.is_awake()) or bool(g.is_night()):
		return "status.sleeping"
	var jobs: Array = g.active_jobs()
	if not jobs.is_empty():
		return "status.digging" if str((jobs[0] as Dictionary).get("item", "")).begins_with("comodo") else "status.building"
	if bool(g.hungry()):
		return "status.hungry"
	if not bool(g.power_ok()):
		return "status.no_power"
	if float(g.busy()) >= 0.5:
		return "status.working"
	return "status.resting"


func refresh(force: bool = false) -> void:
	if not drawer.has_game():
		return
	var g: Node = drawer.game
	var st: Dictionary = g.stats()
	var sig: String = "%s|%d|%.1f|%.2f|%.2f|%d|%d|%d|%s|%s|%s" % [doing_key(g), int(g.sucata()), float(g.box_stock()), float(g.busy()), float(g.tod_hours()),
		int(g.power_supply()), int(g.power_demand()), int(g.antenna()), str(st), bool(g.contact_made()), I18nRef.locale()]
	if bool(g.contact_made()):
		sig += str(g.house_status()) + str(g.journey()) + str(g.arrived())
	if sig == _sig and not force:
		return
	_sig = sig
	for c in _cols:
		DrawerUi.clear(c)
	_col_him(g)
	_col_box(g, st)
	_col_power(g)


func _head(c: VBoxContainer, text: String) -> void:
	c.add_child(DrawerUi.label(text, "LabelMuted"))


func _bar(c: VBoxContainer, v: float) -> void:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = clampf(v, 0.0, 1.0)
	bar.custom_minimum_size = Vector2(0, 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(bar)


func _col_him(g: Node) -> void:
	var c: VBoxContainer = _cols[0]
	_head(c, I18nRef.t("ui.state.title"))
	var key: String = doing_key(g)
	var icon: String = {"status.sleeping": "tempo", "status.building": "hammer", "status.digging": "hammer",
		"status.hungry": "cesto", "status.no_power": "energia"}.get(key, "home")
	c.add_child(DrawerUi.icon_text(icon, I18nRef.t(key), ""))
	c.add_child(DrawerUi.label("%s · %s" % [I18nRef.t("ui.day", {"n": int(g.day_index()) + 1}), DrawerUi.clock(float(g.tod_hours()))], "LabelSmall"))
	var busy: float = float(g.busy())
	c.add_child(DrawerUi.label(I18nRef.t("status.busy", {"pct": roundi(busy * 100.0)}), "LabelSmall"))
	_bar(c, busy)


func _col_box(g: Node, st: Dictionary) -> void:
	var c: VBoxContainer = _cols[1]
	_head(c, I18nRef.t("ui.box"))
	var scrap: HBoxContainer = DrawerUi.icon_text("sucata", I18nRef.t("ui.scrap.value", {"n": int(g.sucata())}), "LabelAmber")
	c.add_child(scrap)
	var fill: float = float(g.box_fill())
	var box: HBoxContainer = DrawerUi.icon_text("cesto", I18nRef.t("drawer.box.stock", {"have": snappedf(float(g.box_stock()), 0.1), "cap": int(g.box_capacity())}), "LabelSmall")
	c.add_child(box)
	_bar(c, fill)
	if fill > 1.0:
		c.add_child(DrawerUi.colored(I18nRef.t("status.box_full"), UiTheme.RUST3))
	var visits: int = int(st.get("visits_per_day", _visits_for(int(g.antenna()))))
	c.add_child(DrawerUi.label(I18nRef.t("drawer.box.visits", {"n": visits}), "LabelSmall"))
	if st.has("harvested"):
		c.add_child(DrawerUi.label("%s: %d" % [I18nRef.t("ui.stats.harvested"), int(st["harvested"])], "LabelMuted"))


func _col_power(g: Node) -> void:
	var c: VBoxContainer = _cols[2]
	var ok: bool = bool(g.power_ok())
	_head(c, I18nRef.t("line.energia"))
	var p: HBoxContainer = DrawerUi.icon_text("energia", I18nRef.t("ui.power", {"have": int(g.power_supply()), "need": int(g.power_demand())}), "LabelSmall")
	if not ok:
		(p.get_child(1) as Label).add_theme_color_override("font_color", UiTheme.RUST3)
	c.add_child(p)
	var lvl: int = int(g.antenna())
	c.add_child(DrawerUi.icon_text("antena", I18nRef.t("ui.antenna", {"n": lvl}), "LabelSmall"))
	if not bool(g.contact_made()):
		c.add_child(DrawerUi.label(I18nRef.t("antenna.%d.name" % lvl), "LabelMuted", true))
		return
	# jornada da casa dela (pós-contato): ícones dos 6 itens + quanto falta
	_head(c, I18nRef.t("line.casa"))
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 1)
	var done: int = 0
	for h: Dictionary in g.house_status():
		var bought: bool = bool(h.get("bought", false))
		done += 1 if bought else 0
		var ic: TextureRect = DrawerUi.icon("check" if bought else "home")
		ic.modulate = Color.WHITE if bought else Color(1, 1, 1, 0.35)
		ic.tooltip_text = I18nRef.t("item.%s.name" % str(h.get("item", "")))
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		icons.add_child(ic)
	var j: Dictionary = g.journey()
	icons.add_child(DrawerUi.label(" %d/%d" % [int(j.get("items_done", done)), int(j.get("items_total", 6))], "LabelSmall"))
	c.add_child(icons)
	if bool(g.arrived()):
		c.add_child(DrawerUi.label(I18nRef.t("drawer.journey.home"), "LabelAmber", true))
	else:
		var left: int = int(j.get("days_left", 0))
		c.add_child(DrawerUi.label(I18nRef.t("drawer.journey.days", {"n": left}) if left > 0 else I18nRef.t("drawer.journey.soon"), "LabelAmber", true))


static func _visits_for(level: int) -> int:
	if _visits_table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BALANCE_PATH))
		if parsed is Dictionary and (parsed as Dictionary).get("visits_per_day") is Dictionary:
			_visits_table = (parsed as Dictionary)["visits_per_day"]
	return int(_visits_table.get(str(level), 0))
