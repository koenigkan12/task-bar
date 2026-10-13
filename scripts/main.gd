class_name Main
extends Control
## Fluxo principal: título -> jogo (faixa + gaveta) -> final. Integra as peças de cada módulo.
## A janela é controlada pelo WindowService; aqui só se decide o tamanho lógico pedido.

const STRIP_H: int = BunkerGeo.H
const DRAWER_H: int = 120
const DRAWER_MIN_W: int = 344
const DRAWER_SCENE: String = "res://scenes/ui/drawer.tscn"

var _title: TitleScreen
var _options: OptionsScreen
var _bunker: Node2D
var _handle: WindowHandle
var _hud: StatusHud
var _drawer: Drawer
var _drawer_layer: CanvasLayer
var _hints: HintLayer
var _ending: EndingScreen
var _drawer_open: bool = false
var _playing: bool = false
var _in_ending: bool = false
var _ending_layer: CanvasLayer
var _intro: IntroScreen


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	Game.room_dug.connect(func(_r: int) -> void: _relayout())
	Game.game_loaded.connect(_relayout)
	Game.new_game_started.connect(_relayout)
	Game.arrival_started.connect(_on_arrival_started)
	WindowService.first_interaction.connect(_on_first_interaction)
	_show_title()


func _strip_width() -> int:
	return 8 + Game.rooms() * 200


## Tamanho lógico da janela inteira (faixa + gaveta se aberta).
func _window_size() -> Vector2i:
	var w: int = _strip_width()
	if _drawer_open or not _playing:
		return Vector2i(maxi(w, DRAWER_MIN_W), STRIP_H + DRAWER_H)
	return Vector2i(w, STRIP_H)


func _relayout() -> void:
	if not _playing:
		return
	WindowService.set_logical_size(Vector2i(_strip_width(), STRIP_H))
	WindowService.set_drawer(_drawer_open, DRAWER_H, DRAWER_MIN_W)
	var size_l: Vector2i = _window_size()
	if _bunker != null:
		_bunker.position = Vector2(0, size_l.y - STRIP_H)
		_bunker.call("set_view_width", size_l.x)
	if _handle != null:
		_handle.position = Vector2(size_l.x - 48, size_l.y - STRIP_H)
	if _hud != null:
		_hud.position = Vector2(2, size_l.y - STRIP_H + 2)


# ---------------------------------------------------------------- título

func _show_title() -> void:
	_playing = false
	_drawer_open = true
	WindowService.set_logical_size(Vector2i(DRAWER_MIN_W, STRIP_H))
	WindowService.set_drawer(true, DRAWER_H, DRAWER_MIN_W)
	_hints = HintLayer.new()
	_hints.enabled = false
	add_child(_hints)
	_title = TitleScreen.new()
	_title.game_started.connect(_on_game_started)
	_title.options_requested.connect(_on_options_requested)
	_title.quit_requested.connect(WindowService.quit_game)
	add_child(_title)
	_title.focus_first()


func _on_options_requested() -> void:
	if _options != null:
		return
	_options = OptionsScreen.new()
	_options.closed.connect(func() -> void:
		_options.queue_free()
		_options = null
		if _title != null:
			_title.focus_first())
	add_child(_options)


func _on_game_started(is_new: bool) -> void:
	if _title != null:
		_title.queue_free()
		_title = null
	_playing = true
	_drawer_open = false
	var packed: PackedScene = load("res://scenes/bunker/bunker.tscn")
	_bunker = packed.instantiate()
	add_child(_bunker)
	_bunker.connect("arrival_cut", _on_arrival_cut)
	_handle = WindowHandle.new()
	add_child(_handle)
	_drawer_layer = CanvasLayer.new()
	_drawer_layer.layer = 5
	add_child(_drawer_layer)
	_drawer = (load(DRAWER_SCENE) as PackedScene).instantiate() as Drawer
	_drawer_layer.add_child(_drawer)
	_drawer.open_changed.connect(_on_drawer_open_changed)
	_drawer.order_requested.connect(func(id: int) -> void:
		var why: String = _bunker.give_order("instance", id)
		if why != "":
			_order_refused(why))
	var opts := OptionsScreen.new()
	opts.show_header = false
	_drawer.add_tab("options", "tab.options", "gear", opts)
	_handle.drawer_toggled.connect(func(open: bool) -> void:
		if open:
			_drawer.open()
		else:
			_drawer.close())
	_bunker.connect("hatch_clicked", _on_box_clicked)   # a escotilha e a caixa fazem a mesma coisa
	_bunker.connect("radio_clicked", func() -> void: _drawer.open("radio"))
	_bunker.connect("box_clicked", _on_box_clicked)
	_bunker.connect("object_clicked", _on_object_clicked)
	_bunker.connect("order_done", _on_order_done)
	_hud = StatusHud.new()
	_hud.clicked.connect(func() -> void: _drawer.open("build"))
	add_child(_hud)
	if is_new:
		_hud.steps.start()
	_hints.enabled = not is_new
	move_child(_hints, get_child_count() - 1)
	_relayout()
	if is_new and not bool(Settings.get_value("intro_seen", false)):
		_show_intro()
	elif is_new:
		_hints.enabled = true


## Introdução do primeiro jogo: ocupa a área da gaveta, com a faixa rodando embaixo.
func _show_intro() -> void:
	_drawer_open = true
	_relayout()
	_intro = IntroScreen.new()
	_intro.finished.connect(func() -> void:
		Settings.set_value("intro_seen", true)
		_intro.get_parent().queue_free()
		_intro = null
		_drawer_open = false
		_hints.enabled = true
		_relayout())
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	layer.add_child(_intro)


## Com a gaveta fechada e a ajuda ligada (começo do jogo): clicar numa estrutura é um pedido para ele:
## vem martelar a obra ou cuidar das plantas. O efeito vale quando ele chega e faz (ver BunkerView.give_order).
func _on_object_clicked(id: int) -> void:
	if not _drawer.is_open() and bool(Game.help_available()):
		var why: String = _bunker.give_order("instance", id)
		if why == "" or _order_refused(why):
			return
	_drawer.select_instance(id)


## Clicar na caixa/escotilha manda ele levar os cestos (começo); depois só abre o estado.
func _on_box_clicked() -> void:
	if not _drawer.is_open() and bool(Game.help_box_available()):
		var why: String = _bunker.give_order("box")
		if why == "" or _order_refused(why):
			return
	_drawer.open("state")


## Avisa por que o pedido não foi aceito. Devolve false quando o clique deve seguir o caminho normal.
func _order_refused(why: String) -> bool:
	match why:
		"asleep":
			_drawer.toast("hud.order_asleep")
		"full":
			_drawer.toast("hud.order_full")
		"empty":
			_drawer.toast("hud.box_empty")
		"cooldown":
			_drawer.toast("hud.box_wait")
		_:
			return false
	return true


## O homem fez o pedido: o resultado da caixa vira aviso na tela.
func _on_order_done(kind: String, res: Dictionary) -> void:
	if kind != "box":
		return
	if bool(res.get("ok", false)):
		_drawer.toast("hud.box_sold", {"n": int(res.get("scrap", 0))})
	else:
		match String(res.get("reason", "")):
			"empty":
				_drawer.toast("hud.box_empty")
			"cooldown":
				_drawer.toast("hud.box_wait")


func _on_drawer_open_changed(open: bool) -> void:
	_drawer_open = open
	if _handle != null:
		_handle.set_drawer_open(open)
	_relayout()


## Abre/fecha o espaço da gaveta sem passar por ela (final do jogo).
func _toggle_drawer(open: bool) -> void:
	if _drawer != null and _drawer.is_open() != open and not _in_ending:
		if open:
			_drawer.open()
		else:
			_drawer.close()
		return
	_on_drawer_open_changed(open)


## Esc em jogo: com a gaveta aberta ela mesma fecha (ou cancela o posicionamento); com ela fechada,
## abre as opções (não há pausa: o jogo anda sozinho).
func _unhandled_input(event: InputEvent) -> void:
	if not _playing or _in_ending or _intro != null or _drawer == null:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and not _drawer.is_open():
		_drawer.open("options")
		get_viewport().set_input_as_handled()


func _on_first_interaction() -> void:
	AudioManager.unlock()


# ---------------------------------------------------------------- final

func _on_arrival_started() -> void:
	# A cena do bunker conduz a cena; aqui só se segura a gaveta fechada.
	if _drawer != null:
		_drawer.close()


## Tela preta da cena do bunker: a janela cresce para caber o texto do final.
func _on_arrival_cut() -> void:
	_in_ending = true
	_drawer_open = true
	_relayout()
	if _ending != null:
		return
	_ending = EndingScreen.new()
	_ending.finished.connect(_on_ending_finished)
	_ending_layer = CanvasLayer.new()
	_ending_layer.layer = 20
	add_child(_ending_layer)
	_ending_layer.add_child(_ending)
	_ending.play_arrival()


func _on_ending_finished(kind: String) -> void:
	match kind:
		"arrival":
			_ending.show_next_day()
		_:
			_ending_layer.queue_free()
			_ending_layer = null
			_ending = null
			_in_ending = false
			_toggle_drawer(false)
