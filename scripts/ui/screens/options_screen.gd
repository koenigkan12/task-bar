class_name OptionsScreen
extends Control
## Opções: idioma, áudio, volume, tamanho da janela, sempre por cima, economia de energia,
## tamanho do texto, reduzir piscadas, ícone na bandeja, resetar posição, apagar progresso.
## Grava em Settings e, quando o serviço existe, aplica na hora (WindowService/AudioManager/I18n).
## Serve no título (tela cheia 344×256) e dentro da gaveta (aba Opções): ocupa o retângulo do pai.

signal closed()
signal progress_erased()

## Na gaveta a aba já tem título e o botão Voltar não faz sentido.
@export var show_header: bool = true

const LOCALES: Array[String] = ["auto", "pt_BR", "en"]
const LOCALE_KEYS: Array[String] = ["opt.language.auto", "opt.language.pt", "opt.language.en"]
const AUDIO_MODES: Array[String] = ["silent", "ambient", "full"]
const SCALES: Array = ["auto", 1, 2, 3, 4]
const ENERGY: Array[String] = ["auto", "normal", "low"]
const TEXT_SIZES: Array[float] = [1.0, 1.25, 1.5]
const TEXT_KEYS: Array[String] = ["opt.text_size.normal", "opt.text_size.large", "opt.text_size.huge"]

var _scroll: ScrollContainer
var _first: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ScreenUtil.connect_to("I18n", "locale_changed", _on_locale_changed)
	ScreenUtil.connect_to("Settings", "changed", _on_setting_changed)
	_build()


func _exit_tree() -> void:
	ScreenUtil.disconnect_from("I18n", "locale_changed", _on_locale_changed)
	ScreenUtil.disconnect_from("Settings", "changed", _on_setting_changed)


func focus_first() -> void:
	if _first != null:
		_first.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if show_header and visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _build() -> void:
	var keep_scroll: int = _scroll.scroll_vertical if _scroll != null else 0
	for c in get_children():
		remove_child(c)
		c.queue_free()
	theme = UiTheme.build()
	_first = null

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)

	if show_header:
		var head := HBoxContainer.new()
		col.add_child(head)
		var t: Label = ScreenUtil.label("opt.title", "LabelTitle")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var back := Button.new()
		back.name = "Back"
		back.text = ScreenUtil.tr_key("ui.btn.back")
		back.pressed.connect(func() -> void: closed.emit())
		head.add_child(back)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("v_separation", 3)
	_scroll.add_child(grid)

	# Idioma
	var loc: String = str(ScreenUtil.setting("locale", "auto"))
	var li: int = maxi(0, LOCALES.find(_norm_locale(loc)))
	_row(grid, "opt.language", _options("Language", LOCALE_KEYS, li, _on_locale_picked))
	# Áudio
	var mode: String = str(ScreenUtil.setting("audio_mode", "ambient"))
	var ai: int = maxi(0, AUDIO_MODES.find(mode))
	_row(grid, "opt.audio", _options("Audio", ["opt.audio.silent", "opt.audio.ambient", "opt.audio.full"], ai, _on_audio_picked), "opt.audio.help")
	# Volume
	var vol := HSlider.new()
	vol.name = "Volume"
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(ScreenUtil.setting("master_volume", 0.8))
	vol.custom_minimum_size = Vector2(90, 12)
	vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol.value_changed.connect(_on_volume)
	_row(grid, "opt.volume", vol)
	# Tamanho da janela
	var sc: Variant = ScreenUtil.setting("ui_scale", "auto")
	var si: int = 0
	for i in SCALES.size():
		if str(SCALES[i]) == str(sc):
			si = i
	_row(grid, "opt.scale", _options("Scale", ["opt.scale.auto", "opt.scale.1", "opt.scale.2", "opt.scale.3", "opt.scale.4"], si, _on_scale_picked))
	# Sempre por cima
	_row(grid, "opt.on_top", _toggle("OnTop", bool(ScreenUtil.setting("always_on_top", false)), _on_top_toggled))
	# Economia de energia
	var en: String = str(ScreenUtil.setting("energy_mode", "auto"))
	_row(grid, "opt.energy", _options("Energy", ["opt.energy.auto", "opt.energy.normal", "opt.energy.low"], maxi(0, ENERGY.find(en)), _on_energy_picked), "opt.energy.help")
	# Tamanho do texto
	var ts: float = float(ScreenUtil.setting("text_size", 1.0))
	var ti: int = 0
	for i in TEXT_SIZES.size():
		if is_equal_approx(TEXT_SIZES[i], ts):
			ti = i
	_row(grid, "opt.text_size", _options("TextSize", TEXT_KEYS, ti, _on_text_size_picked))
	# Reduzir piscadas
	_row(grid, "opt.reduce_flicker", _toggle("ReduceFlicker", bool(ScreenUtil.setting("reduce_flicker", false)), _on_flicker_toggled), "opt.reduce_flicker.help")
	# Ícone na bandeja (só Windows/macOS têm bandeja)
	if OS.has_feature("windows") or OS.has_feature("macos"):
		_row(grid, "opt.tray", _toggle("Tray", bool(ScreenUtil.setting("tray_enabled", true)), _on_tray_toggled))
	# Resetar posição
	var reset := Button.new()
	reset.name = "ResetWindow"
	reset.text = ScreenUtil.tr_key("opt.reset_window.btn")
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(_on_reset_window)
	_row(grid, "opt.reset_window", reset)
	# Apagar progresso
	var erase := Button.new()
	erase.name = "Erase"
	erase.text = ScreenUtil.tr_key("opt.erase.btn")
	erase.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	erase.add_theme_color_override("font_color", UiTheme.RUST3)
	erase.pressed.connect(_on_erase)
	_row(grid, "opt.erase", erase, "opt.erase.help")

	if keep_scroll > 0:
		_scroll.set_deferred("scroll_vertical", keep_scroll)


func _row(grid: GridContainer, key: String, control: Control, help_key: String = "") -> void:
	var lab_box := VBoxContainer.new()
	lab_box.add_theme_constant_override("separation", 0)
	lab_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab_box.add_child(ScreenUtil.label(key))
	if help_key != "":
		var h: Label = ScreenUtil.label(help_key, "LabelMuted")
		h.add_theme_font_size_override("font_size", UiTheme.font_size(UiTheme.SIZE_SMALL))
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.custom_minimum_size = Vector2(150, 0)
		lab_box.add_child(h)
	grid.add_child(lab_box)
	control.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 96)
	grid.add_child(control)
	if _first == null:
		_first = control


func _options(node_name: String, keys: Array, selected: int, cb: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.name = node_name
	ob.fit_to_longest_item = true
	for i in keys.size():
		ob.add_item(ScreenUtil.tr_key(str(keys[i])), i)
	ob.select(selected)
	ob.item_selected.connect(cb)
	return ob


func _toggle(node_name: String, on: bool, cb: Callable) -> CheckButton:
	var cb_btn := CheckButton.new()
	cb_btn.name = node_name
	cb_btn.button_pressed = on
	cb_btn.text = ScreenUtil.tr_key("opt.on" if on else "opt.off")
	cb_btn.toggled.connect(func(v: bool) -> void:
		cb_btn.text = ScreenUtil.tr_key("opt.on" if v else "opt.off")
		cb.call(v))
	return cb_btn


static func _norm_locale(code: String) -> String:
	var c: String = code.to_lower()
	if c == "" or c == "auto":
		return "auto"
	return "pt_BR" if c.begins_with("pt") else "en"


# ---- aplicar -------------------------------------------------------------

func _on_locale_picked(i: int) -> void:
	var code: String = LOCALES[i]
	if ScreenUtil.node("I18n") != null and ScreenUtil.node("I18n").has_method("set_locale"):
		ScreenUtil.call_on("I18n", "set_locale", [code])   # grava em Settings também
	else:
		ScreenUtil.set_setting("locale", code)


func _on_audio_picked(i: int) -> void:
	var mode: String = AUDIO_MODES[i]
	ScreenUtil.set_setting("audio_mode", mode)
	ScreenUtil.call_on("AudioManager", "unlock")
	ScreenUtil.call_on("AudioManager", "set_mode", [mode])


func _on_volume(v: float) -> void:
	ScreenUtil.set_setting("master_volume", v)
	ScreenUtil.call_on("AudioManager", "set_master_volume", [v])


func _on_scale_picked(i: int) -> void:
	ScreenUtil.set_setting("ui_scale", SCALES[i])
	ScreenUtil.call_on("WindowService", "set_ui_scale", [SCALES[i]])


func _on_top_toggled(on: bool) -> void:
	ScreenUtil.set_setting("always_on_top", on)
	ScreenUtil.call_on("WindowService", "set_always_on_top", [on])


func _on_energy_picked(i: int) -> void:
	ScreenUtil.set_setting("energy_mode", ENERGY[i])


func _on_text_size_picked(i: int) -> void:
	ScreenUtil.set_setting("text_size", TEXT_SIZES[i])
	# Sem Settings real, refaz já; com Settings, _on_setting_changed refaz.
	if ScreenUtil.node("Settings") == null or not ScreenUtil.node("Settings").has_signal("changed"):
		call_deferred("_build")


func _on_flicker_toggled(on: bool) -> void:
	ScreenUtil.set_setting("reduce_flicker", on)


func _on_tray_toggled(on: bool) -> void:
	ScreenUtil.set_setting("tray_enabled", on)


func _on_reset_window() -> void:
	ScreenUtil.call_on("WindowService", "reset_position")


func _on_erase() -> void:
	ConfirmBox.ask(self, "title.delete.title", "title.delete.text", "title.delete.btn", _erase_now)


func _erase_now() -> void:
	ScreenUtil.call_on("Game", "delete_save")
	progress_erased.emit()


func _on_locale_changed(_code: String) -> void:
	call_deferred("_build")


func _on_setting_changed(key: String) -> void:
	if key == "text_size":
		call_deferred("_build")
