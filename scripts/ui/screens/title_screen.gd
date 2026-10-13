class_name TitleScreen
extends Control
## Tela de título no tamanho da gaveta aberta (344×208): corte do bunker ao fundo,
## Continuar / Novo jogo (confirma se há save) / Opções / Sair.
## Chama Game.load_game()/new_game() e avisa o fluxo por sinais; Opções só emite o pedido.

signal game_started(is_new: bool)
signal options_requested()
signal quit_requested()

const SIZE := Vector2i(344, 208)
const STRIP_H: int = 88
## Cena viva do bunker (se existir, é instanciada ao fundo); senão usa a arte estática.
const BUNKER_SCENES: Array[String] = ["res://scenes/bunker/bunker.tscn", "res://scenes/bunker/bunker_view.tscn"]
const STATIC_ART: String = "res://assets/art/env/_preview_bunker_lit.png"
## Faixa de duas salas dentro da prévia (px da imagem, ampliada ×4).
const STATIC_REGION := Rect2i(0, 360, 1632, 352)

## false = não instancia a cena viva (testes e capturas determinísticas).
@export var use_live_bunker: bool = true

var _buttons: VBoxContainer
var _background: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(SIZE)
	ScreenUtil.connect_to("I18n", "locale_changed", _on_locale_changed)
	ScreenUtil.connect_to("Settings", "changed", _on_setting_changed)
	_build()


func _exit_tree() -> void:
	ScreenUtil.disconnect_from("I18n", "locale_changed", _on_locale_changed)
	ScreenUtil.disconnect_from("Settings", "changed", _on_setting_changed)


## Foco no primeiro botão (teclado/controle).
func focus_first() -> void:
	if _buttons != null and _buttons.get_child_count() > 0:
		(_buttons.get_child(0) as Control).grab_focus()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	theme = UiTheme.build()

	var sky := ColorRect.new()
	sky.color = UiTheme.DARK1
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sky)
	_add_stars()

	_background = _make_background()
	add_child(_background)

	# Painel do título (parte de cima, acima da faixa)
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = SIZE.y - STRIP_H + 4
	for side: String in ["left", "right"]:
		top.add_theme_constant_override("margin_" + side, 8)
	top.add_theme_constant_override("margin_top", 8)
	top.add_theme_constant_override("margin_bottom", 4)
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	top.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 1)
	row.add_child(left)
	var name_lbl: Label = ScreenUtil.label("title.name", "LabelTitle")
	name_lbl.name = "TitleName"
	left.add_child(name_lbl)
	var sub: Label = ScreenUtil.label("title.subtitle", "LabelSmall")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(sub)
	var info: String = _save_info()
	if info != "":
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left.add_child(spacer)
		var info_lbl := Label.new()
		info_lbl.name = "SaveInfo"
		info_lbl.text = info
		info_lbl.theme_type_variation = "LabelAmber"
		left.add_child(info_lbl)

	_buttons = VBoxContainer.new()
	_buttons.name = "Buttons"
	_buttons.custom_minimum_size = Vector2(96, 0)
	_buttons.add_theme_constant_override("separation", 2)
	row.add_child(_buttons)
	var has_save: bool = bool(ScreenUtil.call_on("Game", "has_save", [], false))
	if has_save:
		_add_button("Continue", "title.btn.continue", _on_continue)
	_add_button("New", "title.btn.new", _on_new)
	_add_button("Options", "title.btn.options", func() -> void: options_requested.emit())
	_add_button("Quit", "title.btn.quit", _on_quit)


func _add_button(node_name: String, key: String, cb: Callable) -> void:
	var b := Button.new()
	b.name = node_name
	b.text = ScreenUtil.tr_key(key)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	_buttons.add_child(b)


func _save_info() -> String:
	# Resumo opcional do save sem carregar (Game.save_summary() -> {day, antenna}), se existir.
	var s: Variant = ScreenUtil.call_on("Game", "save_summary", [], null)
	if s is Dictionary and (s as Dictionary).has("day"):
		var d: Dictionary = s
		return ScreenUtil.tr_key("title.save_info", {"day": int(d.get("day", 0)) + 1, "antenna": int(d.get("antenna", 1))})
	return ""


func _make_background() -> Control:
	var holder := Control.new()
	holder.name = "Background"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -STRIP_H
	if use_live_bunker:
		for path: String in BUNKER_SCENES:
			if ResourceLoader.exists(path):
				var ps: PackedScene = load(path) as PackedScene
				if ps != null:
					holder.add_child(ps.instantiate())
					return holder
	var tex: Texture2D = _static_strip()
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	return holder


static func _static_strip() -> Texture2D:
	if not ResourceLoader.exists(STATIC_ART):
		return null
	var src: Texture2D = load(STATIC_ART) as Texture2D
	if src == null:
		return null
	var img: Image = src.get_image()
	if img == null or img.get_width() < STATIC_REGION.end.x or img.get_height() < STATIC_REGION.end.y:
		return null
	img = img.get_region(STATIC_REGION)
	img.resize(STATIC_REGION.size.x / 4, STATIC_REGION.size.y / 4, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


func _add_stars() -> void:
	# Poucos pontos fixos no céu escuro (sem piscar).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 18:
		var s := ColorRect.new()
		s.size = Vector2.ONE
		s.position = Vector2(rng.randi_range(2, SIZE.x - 3), rng.randi_range(2, SIZE.y - STRIP_H - 4))
		s.color = UiTheme.CONC2 if i % 3 else UiTheme.CONC4
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)


func _on_continue() -> void:
	_unlock_sound()
	if bool(ScreenUtil.call_on("Game", "load_game", [], false)):
		game_started.emit(false)
	else:
		_start_new()


func _on_new() -> void:
	_unlock_sound()
	if bool(ScreenUtil.call_on("Game", "has_save", [], false)):
		ConfirmBox.ask(self, "title.new.title", "title.new.text", "title.new.btn", _start_new)
	else:
		_start_new()


func _start_new() -> void:
	ScreenUtil.call_on("Game", "new_game")
	game_started.emit(true)


func _on_quit() -> void:
	quit_requested.emit()
	if ScreenUtil.node("WindowService") != null and ScreenUtil.node("WindowService").has_method("quit_game"):
		ScreenUtil.call_on("WindowService", "quit_game")
	else:
		get_tree().quit()


func _unlock_sound() -> void:
	# Primeira interação libera o som (contrato 4.5).
	ScreenUtil.call_on("AudioManager", "unlock")


func _on_locale_changed(_code: String) -> void:
	call_deferred("_build")


func _on_setting_changed(key: String) -> void:
	if key == "text_size":
		call_deferred("_build")
