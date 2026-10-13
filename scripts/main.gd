class_name Main
extends Control
## Fluxo principal: título -> jogo (faixa + gaveta) -> final. Integra as peças de cada módulo.
## A janela é controlada pelo WindowService; aqui só se decide o tamanho lógico pedido.

const STRIP_H: int = 88
const DRAWER_H: int = 120
const DRAWER_MIN_W: int = 344
const DRAWER_SCENE: String = "res://scenes/ui/drawer.tscn"

var _title: TitleScreen
var _options: OptionsScreen
var _bunker: Node2D
var _handle: WindowHandle
var _drawer: Control
var _hints: HintLayer
var _ending: EndingScreen
var _drawer_open: bool = false
var _playing: bool = false


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
	if _drawer != null:
		_drawer.position = Vector2.ZERO
		_drawer.size = Vector2(size_l.x, DRAWER_H)
		_drawer.visible = _drawer_open


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


func _on_game_started(_is_new: bool) -> void:
	if _title != null:
		_title.queue_free()
		_title = null
	_playing = true
	_drawer_open = false
	var packed: PackedScene = load("res://scenes/bunker/bunker.tscn")
	_bunker = packed.instantiate()
	add_child(_bunker)
	_bunker.connect("arrival_cut", _on_arrival_cut)
	_bunker.connect("hatch_clicked", func() -> void: _toggle_drawer(true))
	_handle = WindowHandle.new()
	_handle.drawer_toggled.connect(_toggle_drawer)
	add_child(_handle)
	if ResourceLoader.exists(DRAWER_SCENE):
		_drawer = (load(DRAWER_SCENE) as PackedScene).instantiate()
		add_child(_drawer)
	_hints.enabled = true
	move_child(_hints, get_child_count() - 1)
	_relayout()


func _toggle_drawer(open: bool) -> void:
	_drawer_open = open
	if _handle != null:
		_handle.set_drawer_open(open)
	_relayout()


func _on_first_interaction() -> void:
	AudioManager.unlock()


# ---------------------------------------------------------------- final

func _on_arrival_started() -> void:
	# A cena do bunker conduz a cena; aqui só se segura a gaveta fechada.
	_toggle_drawer(false)


## Tela preta da cena do bunker: a janela cresce para caber o texto do final.
func _on_arrival_cut() -> void:
	_drawer_open = true
	_relayout()
	if _ending != null:
		return
	_ending = EndingScreen.new()
	_ending.finished.connect(_on_ending_finished)
	add_child(_ending)
	_ending.play_arrival()


func _on_ending_finished(kind: String) -> void:
	match kind:
		"arrival":
			_ending.show_next_day()
		_:
			_ending.queue_free()
			_ending = null
			_toggle_drawer(false)
