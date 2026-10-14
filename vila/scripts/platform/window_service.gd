extends Node
## Autoload `WindowService`: controla a janela nativa (opaca, sem borda, cresce para cima).
## Contrato: docs/CONTRATOS.md, seção 4.4. Tudo é inofensivo em --headless e quando o
## DisplayServer não suporta uma função.
##
## A matemática de layout (escala, posição, validação por monitor, FPS) fica em funções
## ESTÁTICAS PURAS no começo do arquivo, testáveis sem janela:
##   const WS = preload("res://scripts/platform/window_service.gd")
##   WS.auto_scale(1080) ...

signal layout_changed(logical_size: Vector2i, scale: int)
signal hidden_changed(is_hidden: bool)
signal focus_changed(has_focus: bool)
## Primeiro clique/tecla/toque do jogador na sessão (libera o som, ver AudioManager.unlock).
signal first_interaction()

## Aba pequena do modo recolhido (pixels lógicos).
const COLLAPSED_SIZE: Vector2i = Vector2i(48, 16)
## Quanto da janela (em pixels de tela) precisa continuar visível num monitor.
const MIN_VISIBLE: Vector2i = Vector2i(96, 24)
const IDLE_SECONDS: float = 10.0
const FPS_ACTIVE: int = 30
const FPS_IDLE: int = 12
const FPS_BACKGROUND: int = 8
const FPS_SLEEP: int = 2
const FPS_DRAG: int = 60
const SYNC_INTERVAL_S: float = 1.0
const DRAG_START_PX: float = 3.0
## Janela mexida pelo próprio jogo: ignora a posição lida do SO por este tempo.
const APPLY_GRACE_MS: int = 600

const TRAY_SHOW: int = 1
const TRAY_COLLAPSE: int = 2
const TRAY_RESET: int = 3
const TRAY_TOP: int = 4
const TRAY_QUIT: int = 5

## Textos da bandeja enquanto o I18n ainda é stub (devolve a chave) ou não tem a chave.
const FALLBACK_EN: Dictionary = {
	"ui.tray_show": "Show",
	"ui.tray_collapse": "Collapse",
	"ui.tray_reset": "Reset position",
	"ui.tray_top": "Always on top",
	"ui.tray_quit": "Quit",
}


# ===========================================================================
# MATEMÁTICA PURA (estática)
# ===========================================================================

## Escala "auto": clamp(floor(altura_do_monitor / 360), 1, 4). Na vila (384×216 lógicos) dá 3× num monitor
## de 1080 px (1152×648) e 2× num de 768 px.
static func auto_scale(monitor_h: int) -> int:
	return clampi(int(floor(float(monitor_h) / 360.0)), 1, 4)


## Aceita "auto" | 1..4 (int ou float do JSON). Qualquer outra coisa vira "auto".
static func normalize_scale_setting(v: Variant) -> Variant:
	if v is String and v == "auto":
		return "auto"
	if (v is int or v is float) and float(v) == floor(float(v)) and int(v) >= 1 and int(v) <= 4:
		return int(v)
	return "auto"


## Reduz a escala até a janela caber na área útil (mínimo 1). Área sem tamanho = ignora.
static func fit_scale(scale: int, logical: Vector2i, usable_size: Vector2i) -> int:
	var s: int = clampi(scale, 1, 4)
	if usable_size.x <= 0 or usable_size.y <= 0:
		return s
	while s > 1 and (logical.x * s > usable_size.x or logical.y * s > usable_size.y):
		s -= 1
	return s


## Escala final: configuração ("auto"|1..4) + altura do monitor + área útil.
static func resolve_scale(setting: Variant, logical: Vector2i, monitor_h: int, usable_size: Vector2i) -> int:
	var norm: Variant = normalize_scale_setting(setting)
	var s: int = auto_scale(monitor_h) if norm is String else int(norm)
	return fit_scale(s, logical, usable_size)


## Retângulo da janela a partir do canto inferior esquerdo (âncora).
static func rect_from_anchor(anchor: Vector2i, size: Vector2i) -> Rect2i:
	return Rect2i(anchor.x, anchor.y - size.y, size.x, size.y)


## Novo tamanho mantendo a borda inferior e a esquerda (cresce para cima e para a direita).
static func resize_keep_bottom_left(old: Rect2i, new_size: Vector2i) -> Rect2i:
	return Rect2i(old.position.x, old.end.y - new_size.y, new_size.x, new_size.y)


## Empurra o retângulo para dentro de `bounds`. Se for maior que a área: alinha à esquerda e embaixo.
static func shift_into(rect: Rect2i, bounds: Rect2i) -> Rect2i:
	var r: Rect2i = rect
	if r.size.x <= bounds.size.x:
		r.position.x = clampi(r.position.x, bounds.position.x, bounds.end.x - r.size.x)
	else:
		r.position.x = bounds.position.x
	if r.size.y <= bounds.size.y:
		r.position.y = clampi(r.position.y, bounds.position.y, bounds.end.y - r.size.y)
	else:
		r.position.y = bounds.end.y - r.size.y
	return r


## Âncora padrão: canto inferior esquerdo da área útil.
static func default_anchor(usable: Rect2i) -> Vector2i:
	return Vector2i(usable.position.x, usable.end.y)


## Índice da área com maior sobreposição com `rect`; -1 se não cruza nenhuma.
static func find_screen(rect: Rect2i, areas: Array) -> int:
	var best: int = -1
	var best_area: int = 0
	for i in range(areas.size()):
		var inter: Rect2i = rect.intersection(areas[i])
		var a: int = inter.size.x * inter.size.y
		if inter.size.x > 0 and inter.size.y > 0 and a > best_area:
			best_area = a
			best = i
	return best


## Área mais próxima (pelo centro) quando nada cruza.
static func nearest_screen(rect: Rect2i, areas: Array) -> int:
	var best: int = 0
	var best_d: float = INF
	var c: Vector2 = Vector2(rect.position) + Vector2(rect.size) * 0.5
	for i in range(areas.size()):
		var ar: Rect2i = areas[i]
		var ac: Vector2 = Vector2(ar.position) + Vector2(ar.size) * 0.5
		var d: float = c.distance_squared_to(ac)
		if d < best_d:
			best_d = d
			best = i
	return best


## Valida um retângulo salvo. Devolve {ok, screen, reason} com reason em
## "", "no_screen" (não cruza nenhum monitor), "too_big" (maior que a área útil),
## "offscreen" (aparece menos que MIN_VISIBLE).
static func validate_rect(rect: Rect2i, areas: Array) -> Dictionary:
	var idx: int = find_screen(rect, areas)
	if idx < 0:
		return {"ok": false, "screen": -1, "reason": "no_screen"}
	var a: Rect2i = areas[idx]
	if rect.size.x > a.size.x or rect.size.y > a.size.y:
		return {"ok": false, "screen": idx, "reason": "too_big"}
	var ov: Vector2i = rect.intersection(a).size
	if ov.x < mini(rect.size.x, MIN_VISIBLE.x) or ov.y < mini(rect.size.y, MIN_VISIBLE.y):
		return {"ok": false, "screen": idx, "reason": "offscreen"}
	return {"ok": true, "screen": idx, "reason": ""}


## Durante o arrasto: deixa passar para outro monitor, mas sempre com MIN_VISIBLE à vista.
static func clamp_visible(rect: Rect2i, areas: Array) -> Rect2i:
	if areas.is_empty():
		return rect
	var idx: int = find_screen(rect, areas)
	if idx < 0:
		idx = nearest_screen(rect, areas)
	var a: Rect2i = areas[idx]
	var vx: int = mini(rect.size.x, MIN_VISIBLE.x)
	var vy: int = mini(rect.size.y, MIN_VISIBLE.y)
	var r: Rect2i = rect
	r.position.x = clampi(r.position.x, a.position.x - r.size.x + vx, a.end.x - vx)
	r.position.y = clampi(r.position.y, a.position.y - r.size.y + vy, a.end.y - vy)
	return r


## Posição da janela durante o arrasto manual.
static func drag_position(win_start: Vector2i, mouse_start: Vector2i, mouse_now: Vector2i) -> Vector2i:
	return win_start + (mouse_now - mouse_start)


## Identificador de monitor para o `window_pos` salvo (tamanho + origem na área virtual).
static func monitor_key(full: Rect2i) -> String:
	return "%dx%d@%d,%d" % [full.size.x, full.size.y, full.position.x, full.position.y]


## Posição salva: x = distância da esquerda da área útil; y = distância da base da área útil
## (0 = colada no rodapé). Independe do tamanho da janela, então vale com a gaveta aberta ou não.
static func pos_to_saved(anchor: Vector2i, usable: Rect2i) -> Dictionary:
	return {"x": anchor.x - usable.position.x, "y": usable.end.y - anchor.y}


static func anchor_from_saved(saved: Dictionary, usable: Rect2i) -> Vector2i:
	return Vector2i(usable.position.x + int(saved.get("x", 0)), usable.end.y - int(saved.get("y", 0)))


## Escolhe qual entrada de `window_pos` usar: a do último monitor (`_last`) se ele ainda existe,
## senão a do monitor principal. Devolve {screen, x, y} ou {} se não houver.
static func pick_saved(saved: Variant, fulls: Array, primary: int) -> Dictionary:
	if not (saved is Dictionary) or fulls.is_empty():
		return {}
	var order: Array[int] = []
	var last: Variant = saved.get("_last", "")
	if last is String:
		for i in range(fulls.size()):
			if monitor_key(fulls[i]) == last:
				order.append(i)
	if not order.has(primary):
		order.append(primary)
	for i in order:
		if i < 0 or i >= fulls.size():
			continue
		var e: Variant = saved.get(monitor_key(fulls[i]), null)
		if e is Dictionary and (e.get("x") is int or e.get("x") is float) and (e.get("y") is int or e.get("y") is float):
			return {"screen": i, "x": int(e["x"]), "y": int(e["y"])}
	return {}


## FPS-alvo do governador (Engine.max_fps).
## ativo/hover 30; ocioso (sem input 10 s) 12; sem foco e sem hover 8; recolhido ou modo baixo 2.
## Extras (desvios do contrato, para a interface não ficar travada): hover vence o modo baixo/recolhido
## (12), e arrastar usa 60.
static func fps_for(collapsed: bool, low: bool, focused: bool, hover: bool, idle_s: float, dragging: bool = false) -> int:
	if dragging:
		return FPS_DRAG
	if collapsed:
		return FPS_IDLE if hover else FPS_SLEEP
	if low:
		return FPS_IDLE if (hover or idle_s < IDLE_SECONDS) else FPS_SLEEP
	if hover:
		return FPS_ACTIVE
	if focused:
		return FPS_ACTIVE if idle_s < IDLE_SECONDS else FPS_IDLE
	return FPS_BACKGROUND


# ===========================================================================
# ESTADO
# ===========================================================================

var logical_size: Vector2i = Vector2i(344, 88)   ## tamanho lógico efetivo (faixa + gaveta, ou aba)
var ui_scale: int = 1                            ## escala inteira em uso

## Testes: monitores simulados [{full: Rect2i, usable: Rect2i}], monitor principal e mouse.
var screens_override: Array = []
var primary_override: int = 0
var mouse_override: Variant = null
## Arrasto nativo (DisplayServer.window_start_drag) em vez do manual. O manual é padrão porque
## sabemos exatamente quando termina e funciona igual em todos os sistemas; ligue depois de
## testar num Windows de verdade.
var use_native_drag: bool = false
## Testes: força criar a bandeja mesmo fora de Windows/macOS.
var tray_force: bool = false

var _native: bool = false            ## há janela real (não é --headless)
var _base_size: Vector2i = Vector2i(344, 88)
var _drawer_open: bool = false
var _drawer_h: int = 120
var _drawer_min_w: int = 344
var _collapsed: bool = false
var _anchor: Vector2i = Vector2i.ZERO      ## canto inferior esquerdo, em coordenadas globais
var _rect: Rect2i = Rect2i()               ## retângulo realmente aplicado
var _screen_idx: int = 0
var _applied_logical: Vector2i = Vector2i.ZERO
var _applied_scale: int = 0
var _last_apply_ms: int = 0

var _dragging: bool = false
## Tamanho escolhido puxando a borda (pixels de tela; zero = o padrão, base × escala).
var _user_px: Vector2i = Vector2i.ZERO
var _resizing: bool = false
var _rs_edges: int = 0                     ## 1 esquerda, 2 direita, 4 cima, 8 baixo
var _rs_mouse0: Vector2i = Vector2i.ZERO
var _rs_rect0: Rect2i = Rect2i()
const EDGE_PX: int = 6
var _native_drag: bool = false
var _drag_mouse0: Vector2i = Vector2i.ZERO
var _drag_win0: Vector2i = Vector2i.ZERO

var _has_focus: bool = true
var _hover: bool = false
var _last_activity_ms: int = 0
var _fps: int = 0
var _interacted: bool = false
var _sync_left: float = SYNC_INTERVAL_S
var _screen_sig: String = ""

var _settings: Node = null           ## autoload Settings (por nome, para o script compilar sem autoloads)
var _tab_layer: CanvasLayer = null
var _tab: Control = null
var _tray: Node = null
var _tray_menu: PopupMenu = null


func _ready() -> void:
	# Botões disparam ao apertar, não ao soltar. Clicar na janela vinda de outro programa faz o
	# sistema tirar e devolver o foco no meio do clique; o Godot então perde o "soltar" e o
	# primeiro clique não valia (tinha que clicar duas vezes).
	get_tree().node_added.connect(_on_node_added)
	if _settings == null:
		_settings = get_node_or_null("/root/Settings")
	_native = DisplayServer.get_name() != "headless"
	_last_activity_ms = Time.get_ticks_msec()
	_base_size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 344)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 88)))
	logical_size = _base_size

	var win: Window = get_window()
	if _native:
		win.borderless = true
		win.unresizable = true
		win.min_size = Vector2i(1, 1)   # a aba é minúscula (o padrão do Godot no X11 é 64x64)
		win.always_on_top = bool(_sget("always_on_top", false))
		_has_focus = DisplayServer.window_is_focused()
		# Sem vsync: quem manda no ritmo é o Engine.max_fps.
		if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if win != null:
		win.mouse_entered.connect(_on_mouse_entered)
		win.mouse_exited.connect(_on_mouse_exited)
		win.focus_entered.connect(_set_focus.bind(true))
		win.focus_exited.connect(_set_focus.bind(false))
		win.dpi_changed.connect(_on_dpi_changed)
	if _settings != null and _settings.has_signal("changed"):
		_settings.connect("changed", _on_setting_changed)

	var up: Variant = _sget("window_px", [])
	if up is Array and (up as Array).size() == 2:
		_user_px = Vector2i(int(up[0]), int(up[1]))
	_startup_layout()
	_build_tab()
	_setup_tray()
	_update_fps(true)


func _process(delta: float) -> void:
	if _dragging:
		_drag_step()
	if _resizing:
		_resize_step()
	_update_fps()
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = SYNC_INTERVAL_S
		_sync_with_system()


func _input(event: InputEvent) -> void:
	var is_press: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if is_press or event is InputEventMouseMotion:
		note_activity()
	_resize_input(event)
	if is_press and not _interacted:
		_interacted = true
		_sset("sound_unlocked", true)
		first_interaction.emit()
		var audio: Node = get_node_or_null("/root/AudioManager")
		if audio != null and audio.has_method("unlock"):
			audio.call_deferred("unlock")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_set_focus(true)
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_set_focus(false)
		NOTIFICATION_WM_CLOSE_REQUEST:
			_save_position()
			_sflush()
		NOTIFICATION_WM_DPI_CHANGE:
			_on_dpi_changed()


# ===========================================================================
# SETTINGS (acesso dinâmico: não depende de o autoload existir na hora de compilar)
# ===========================================================================

func _sget(key: String, default: Variant = null) -> Variant:
	if _settings != null:
		return _settings.call("get_value", key, default)
	return default


func _sset(key: String, value: Variant) -> void:
	if _settings != null:
		_settings.call("set_value", key, value)


func _sflush() -> void:
	if _settings != null and _settings.has_method("flush"):
		_settings.call("flush")


# ===========================================================================
# API PÚBLICA
# ===========================================================================

## Define o tamanho lógico da FAIXA fechada (a gaveta, se aberta, soma por cima).
## Mantém o canto inferior esquerdo; ajusta content_scale_size.
func set_logical_size(size: Vector2i) -> void:
	_base_size = Vector2i(maxi(size.x, 1), maxi(size.y, 1))
	_apply_layout()


## Abre/fecha a gaveta: a janela cresce PARA CIMA (altura = faixa + drawer_h; largura =
## max(largura da faixa, min_width)).
func set_drawer(open: bool, drawer_h: int = 120, min_width: int = 344) -> void:
	_drawer_open = open
	_drawer_h = maxi(drawer_h, 0)
	_drawer_min_w = maxi(min_width, 1)
	_apply_layout()


func is_drawer_open() -> bool:
	return _drawer_open


## Chamado no clique da alça. Arrasta até o botão esquerdo ser solto.
func start_drag() -> void:
	if _dragging:
		return
	if use_native_drag and _native and ClassDB.class_has_method("DisplayServer", "window_start_drag"):
		_native_drag = true
		DisplayServer.window_start_drag()
	else:
		_native_drag = false
		_drag_mouse0 = _mouse_global()
		_drag_win0 = _rect.position
	_dragging = true
	_update_fps(true)


func is_dragging() -> bool:
	return _dragging


func set_always_on_top(on: bool) -> void:
	_sset("always_on_top", on)
	_apply_top()


## "Esconder": vira uma aba pequena (48x16 lógicos) no canto inferior esquerdo; a simulação
## continua. Clicar na aba restaura.
func set_collapsed(on: bool) -> void:
	if on == _collapsed:
		return
	_collapsed = on
	if _dragging:
		_end_drag()
	if _tab_layer != null:
		_tab_layer.visible = on
	_apply_layout()
	_update_fps(true)
	hidden_changed.emit(on)
	_refresh_tray()


func is_collapsed() -> bool:
	return _collapsed


## Rodapé da área útil do monitor principal, canto esquerdo.
func reset_position() -> void:
	_user_px = Vector2i.ZERO
	_sset("window_px", [])
	var sc: Dictionary = _fetch_screens()
	_screen_idx = int(sc["primary"])
	_anchor = default_anchor(sc["usable"][_screen_idx])
	_apply_layout(true)
	_save_position()


## "auto" | 1 | 2 | 3 | 4
func set_ui_scale(mode: Variant) -> void:
	_sset("ui_scale", normalize_scale_setting(mode))
	_apply_layout()


## Qualquer input chama (já é chamado sozinho pelo _input deste autoload).
func note_activity() -> void:
	_last_activity_ms = Time.get_ticks_msec()
	_update_fps()


## Salva e sai.
func quit_game() -> void:
	_save_position()
	_sflush()
	var game: Node = get_node_or_null("/root/Game")
	if game != null and game.has_method("save_game"):
		var in_game: Variant = game.get("in_game")
		if in_game == null or in_game:
			game.call("save_game")
	get_tree().quit()


# Consultas úteis (testes e UI)

func idle_seconds() -> float:
	return float(Time.get_ticks_msec() - _last_activity_ms) / 1000.0


func current_fps() -> int:
	return _fps


func get_window_rect() -> Rect2i:
	return _rect


func is_hovered() -> bool:
	return _hover


func has_window_focus() -> bool:
	return _has_focus


## Texto do menu da bandeja: I18n se já estiver pronto, senão inglês.
func tr_tray(key: String) -> String:
	var i18n: Node = get_node_or_null("/root/I18n")
	if i18n != null and i18n.has_method("t"):
		var s: Variant = i18n.call("t", key)
		if s is String and s != "" and s != key:
			return s
	return String(FALLBACK_EN.get(key, key))


# ===========================================================================
# LAYOUT (usa as funções puras)
# ===========================================================================

func _target_logical() -> Vector2i:
	if _collapsed:
		return COLLAPSED_SIZE
	var b := _base_size
	if _user_px != Vector2i.ZERO:
		var s: int = maxi(ui_scale, 1)
		b = Vector2i(maxi(_base_size.x, _user_px.x / s), maxi(_base_size.y, _user_px.y / s))
	if _drawer_open:
		return Vector2i(maxi(b.x, _drawer_min_w), b.y + _drawer_h)
	return b


## Menor tamanho lógico (a escala é escolhida por ele; puxar a borda só mostra mais mundo).
func _min_logical() -> Vector2i:
	if _collapsed:
		return COLLAPSED_SIZE
	if _drawer_open:
		return Vector2i(maxi(_base_size.x, _drawer_min_w), _base_size.y + _drawer_h)
	return _base_size


func _fetch_screens() -> Dictionary:
	var fulls: Array = []
	var areas: Array = []
	var primary: int = 0
	if not screens_override.is_empty():
		for s in screens_override:
			fulls.append(s["full"])
			areas.append(s["usable"])
		primary = clampi(primary_override, 0, fulls.size() - 1)
		return {"full": fulls, "usable": areas, "primary": primary}
	if _native:
		var n: int = DisplayServer.get_screen_count()
		for i in range(n):
			var full: Rect2i = Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
			var usable: Rect2i = DisplayServer.screen_get_usable_rect(i)
			if usable.size.x <= 0 or usable.size.y <= 0:
				usable = full
			if full.size.x <= 0 or full.size.y <= 0:
				continue
			fulls.append(full)
			areas.append(usable)
		primary = clampi(DisplayServer.get_primary_screen(), 0, maxi(fulls.size() - 1, 0))
	if fulls.is_empty():
		# --headless (ou sistema sem monitor): um monitor 1920x1080 de mentira, com barra de 40 px.
		fulls.append(Rect2i(0, 0, 1920, 1080))
		areas.append(Rect2i(0, 0, 1920, 1040))
		primary = 0
	return {"full": fulls, "usable": areas, "primary": primary}


func _screens_signature(sc: Dictionary) -> String:
	var parts: PackedStringArray = []
	for i in range(sc["full"].size()):
		parts.append("%s/%s" % [str(sc["full"][i]), str(sc["usable"][i])])
	return "|".join(parts) + "#" + str(sc["primary"])


func _wants_reset() -> bool:
	return OS.get_cmdline_args().has("--reset-window") or OS.get_cmdline_user_args().has("--reset-window")


## Primeira posição: a salva (se válida) ou o rodapé do monitor principal.
func _startup_layout() -> void:
	var sc: Dictionary = _fetch_screens()
	_screen_sig = _screens_signature(sc)
	var areas: Array = sc["usable"]
	var idx: int = int(sc["primary"])
	var anchor: Vector2i = default_anchor(areas[idx])
	var must_save: bool = false
	if _wants_reset():
		must_save = true
	else:
		var pick: Dictionary = pick_saved(_sget("window_pos", {}), sc["full"], idx)
		if not pick.is_empty():
			var pidx: int = int(pick["screen"])
			var s: int = resolve_scale(_sget("ui_scale", "auto"), _min_logical(), (sc["full"][pidx] as Rect2i).size.y, (areas[pidx] as Rect2i).size)
			ui_scale = s
			var cand_anchor: Vector2i = anchor_from_saved(pick, areas[pidx])
			var v: Dictionary = validate_rect(rect_from_anchor(cand_anchor, _target_logical() * s), areas)
			if bool(v["ok"]):
				idx = int(v["screen"])
				anchor = cand_anchor
			else:
				must_save = true  # posição salva ruim: volta ao rodapé e regrava
	_screen_idx = idx
	_anchor = anchor
	_apply_layout(true)
	if must_save:
		_save_position()


## Calcula e aplica tamanho/posição a partir da âncora e do estado (faixa, gaveta, aba).
func _apply_layout(force: bool = false) -> void:
	var sc: Dictionary = _fetch_screens()
	var areas: Array = sc["usable"]
	var logical: Vector2i = _target_logical()
	var probe: Rect2i = rect_from_anchor(_anchor, logical * maxi(ui_scale, 1))
	var idx: int = find_screen(probe, areas)
	if idx < 0:
		idx = int(sc["primary"]) if _anchor == Vector2i.ZERO else nearest_screen(probe, areas)
	_screen_idx = idx
	var scale: int = resolve_scale(_sget("ui_scale", "auto"), _min_logical(), (sc["full"][idx] as Rect2i).size.y, (areas[idx] as Rect2i).size)
	ui_scale = scale
	logical = _target_logical()
	var usable_l: Vector2i = (areas[idx] as Rect2i).size / scale
	logical = Vector2i(mini(logical.x, maxi(usable_l.x, _min_logical().x)), mini(logical.y, maxi(usable_l.y, _min_logical().y)))
	var size: Vector2i = logical * scale
	var rect: Rect2i = shift_into(rect_from_anchor(_anchor, size), areas[idx])
	var layout_changed_now: bool = logical != _applied_logical or scale != _applied_scale
	if force or layout_changed_now or rect != _rect:
		_push_native(logical, size, rect.position)
	_rect = rect
	logical_size = logical
	ui_scale = scale
	_applied_logical = logical
	_applied_scale = scale
	if layout_changed_now:
		layout_changed.emit(logical, scale)


func _push_native(logical: Vector2i, size: Vector2i, pos: Vector2i) -> void:
	_last_apply_ms = Time.get_ticks_msec()
	if not _native:
		return
	var win: Window = get_window()
	win.content_scale_size = logical
	# Pela API do Window (não direto no DisplayServer): senão Window.size fica velho e a
	# escala de conteúdo é calculada com o tamanho errado.
	win.size = size
	win.position = pos


func _apply_top() -> void:
	if _native:
		get_window().always_on_top = bool(_sget("always_on_top", false))
	_refresh_tray()


# ===========================================================================
# ARRASTO
# ===========================================================================

func _mouse_global() -> Vector2i:
	if mouse_override != null:
		return mouse_override
	if _native:
		return DisplayServer.mouse_get_position()
	return Vector2i.ZERO


func _drag_step() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_drag()
		return
	if _native_drag:
		var p: Vector2i = DisplayServer.window_get_position()
		_rect.position = p
		_anchor = Vector2i(p.x, p.y + _rect.size.y)
		return
	var areas: Array = _fetch_screens()["usable"]
	var pos: Vector2i = drag_position(_drag_win0, _drag_mouse0, _mouse_global())
	var rect: Rect2i = clamp_visible(Rect2i(pos, _rect.size), areas)
	if rect.position != _rect.position:
		_rect = rect
		_anchor = Vector2i(rect.position.x, rect.end.y)
		if _native:
			_last_apply_ms = Time.get_ticks_msec()
			get_window().position = rect.position


## Soltou: assenta na tela onde ficou (inteira dentro da área útil), reavalia a escala e salva.
func _end_drag() -> void:
	_dragging = false
	_native_drag = false
	var sc: Dictionary = _fetch_screens()
	var areas: Array = sc["usable"]
	var idx: int = find_screen(_rect, areas)
	if idx < 0:
		idx = nearest_screen(_rect, areas)
	var settled: Rect2i = shift_into(_rect, areas[idx])
	_anchor = Vector2i(settled.position.x, settled.end.y)
	_apply_layout(true)
	_save_position()
	_update_fps(true)


# ===========================================================================
# REDIMENSIONAR PELA BORDA (a janela não tem moldura do sistema)
# ===========================================================================

func _edges_at(local: Vector2i) -> int:
	if _collapsed or _rect.size == Vector2i.ZERO:
		return 0
	var e := 0
	if local.x < EDGE_PX:
		e |= 1
	elif local.x >= _rect.size.x - EDGE_PX:
		e |= 2
	if local.y < EDGE_PX:
		e |= 4
	elif local.y >= _rect.size.y - EDGE_PX:
		e |= 8
	return e


func _edge_cursor(e: int) -> int:
	if e == 5 or e == 10:
		return Input.CURSOR_FDIAGSIZE
	if e == 6 or e == 9:
		return Input.CURSOR_BDIAGSIZE
	if e & 3:
		return Input.CURSOR_HSIZE
	if e & 12:
		return Input.CURSOR_VSIZE
	return Input.CURSOR_ARROW


func _resize_input(event: InputEvent) -> void:
	if not _native or _dragging:
		return
	var local: Vector2i = _mouse_global() - _rect.position
	var e := _edges_at(local)
	if event is InputEventMouseMotion and not _resizing:
		Input.set_default_cursor_shape(_edge_cursor(e) as Input.CursorShape)
	var mb := event as InputEventMouseButton
	# Em cima de um botão o clique é do botão, mesmo colado na borda (os ícones de cima e a barra
	# de baixo encostam na borda da janela).
	if mb != null and mb.pressed and e != 0 and get_viewport().gui_get_hovered_control() is BaseButton:
		return
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and e != 0:
		_resizing = true
		_rs_edges = e
		_rs_mouse0 = _mouse_global()
		_rs_rect0 = _rect
		get_viewport().set_input_as_handled()
		_update_fps(true)


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		(n as BaseButton).action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS


func is_resizing() -> bool:
	return _resizing


func _resize_step() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_resizing = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_user_px = _rect.size
		_sset("window_px", [_user_px.x, _user_px.y])
		_anchor = Vector2i(_rect.position.x, _rect.end.y)
		_apply_layout(true)
		_save_position()
		_update_fps(true)
		return
	var d: Vector2i = _mouse_global() - _rs_mouse0
	var r := _rs_rect0
	var mn: Vector2i = _min_logical() * maxi(ui_scale, 1)
	if _rs_edges & 1:
		var nx: int = mini(r.position.x + d.x, r.end.x - mn.x)
		r.size.x = r.end.x - nx
		r.position.x = nx
	if _rs_edges & 2:
		r.size.x = maxi(mn.x, r.size.x + d.x)
	if _rs_edges & 4:
		var ny: int = mini(r.position.y + d.y, r.end.y - mn.y)
		r.size.y = r.end.y - ny
		r.position.y = ny
	if _rs_edges & 8:
		r.size.y = maxi(mn.y, r.size.y + d.y)
	if r == _rect:
		return
	var s: int = maxi(ui_scale, 1)
	r.size = (r.size / s) * s
	_rect = r
	_last_apply_ms = Time.get_ticks_msec()
	var win: Window = get_window()
	win.content_scale_size = r.size / s
	win.size = r.size
	win.position = r.position
	logical_size = r.size / s
	_applied_logical = logical_size
	layout_changed.emit(logical_size, s)


## Volta ao tamanho padrão (Opções).
func reset_size() -> void:
	_user_px = Vector2i.ZERO
	_sset("window_px", [])
	_apply_layout(true)


# ===========================================================================
# POSIÇÃO SALVA / MONITORES
# ===========================================================================

func _persist_ok() -> bool:
	return _native or not screens_override.is_empty()


func _save_position() -> void:
	if not _persist_ok():
		return
	var sc: Dictionary = _fetch_screens()
	var idx: int = clampi(_screen_idx, 0, sc["full"].size() - 1)
	var d: Variant = _sget("window_pos", {})
	if not (d is Dictionary):
		d = {}
	var key: String = monitor_key(sc["full"][idx])
	d[key] = pos_to_saved(_anchor, sc["usable"][idx])
	d["_last"] = key
	_sset("window_pos", d)


## Roda a cada ~1 s: o SO mexeu na janela (Win+setas, mudou de monitor)? Monitores mudaram?
func _sync_with_system() -> void:
	if _dragging:
		return
	var sc: Dictionary = _fetch_screens()
	var sig: String = _screens_signature(sc)
	if sig != _screen_sig:
		_screen_sig = sig
		_revalidate(sc)
		return
	if not _native or Time.get_ticks_msec() - _last_apply_ms < APPLY_GRACE_MS:
		return
	var actual: Vector2i = DisplayServer.window_get_position()
	if actual != _rect.position:
		_rect.position = actual
		_anchor = Vector2i(actual.x, actual.y + _rect.size.y)
		var areas: Array = sc["usable"]
		var v: Dictionary = validate_rect(_rect, areas)
		if not bool(v["ok"]) and v["reason"] != "too_big":
			reset_position()
			return
		_apply_layout(true)  # pode ter mudado de monitor: escala de novo, e entra na área útil
		_save_position()


## Monitor ligado/desligado/reordenado: confere se a janela ainda está num lugar válido.
func _revalidate(sc: Dictionary) -> void:
	var v: Dictionary = validate_rect(_rect, sc["usable"])
	if bool(v["ok"]):
		_apply_layout(true)
	else:
		reset_position()


func _on_dpi_changed() -> void:
	call_deferred("_apply_layout", true)


# ===========================================================================
# FOCO, HOVER, FPS
# ===========================================================================

func _set_focus(f: bool) -> void:
	if f == _has_focus:
		return
	_has_focus = f
	if not f and _dragging and not _native_drag:
		_end_drag()
	_update_fps(true)
	focus_changed.emit(f)


func _on_mouse_entered() -> void:
	_hover = true
	_update_fps(true)


func _on_mouse_exited() -> void:
	_hover = false
	_update_fps(true)


func _update_fps(force: bool = false) -> void:
	var low: bool = String(_sget("energy_mode", "auto")) == "low"
	var f: int = fps_for(_collapsed, low, _has_focus, _hover or _dragging or _resizing, idle_seconds(), _dragging or _resizing)
	if f != _fps or force:
		_fps = f
		Engine.max_fps = f


func _on_setting_changed(key: String) -> void:
	match key:
		"ui_scale":
			_apply_layout()
		"always_on_top":
			_apply_top()
		"energy_mode":
			_update_fps(true)
		"tray_enabled":
			if bool(_sget("tray_enabled", true)):
				_setup_tray()
			else:
				_teardown_tray()


# ===========================================================================
# ABA (modo recolhido)
# ===========================================================================

## Controle simples desenhado por código (sem assets): clique restaura, arrastar move a janela.
class TabView extends Control:
	signal clicked()
	signal drag_requested()
	var _press_pos: Vector2 = Vector2.ZERO
	var _pressed: bool = false
	var _moved: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var s: Vector2 = size
		draw_rect(Rect2(Vector2.ZERO, s), Color("14110f"))
		var edge: Color = Color("6b563d")
		draw_rect(Rect2(0, 0, s.x, 1), edge)
		draw_rect(Rect2(0, s.y - 1, s.x, 1), edge)
		draw_rect(Rect2(0, 0, 1, s.y), edge)
		draw_rect(Rect2(s.x - 1, 0, 1, s.y), edge)
		draw_rect(Rect2(1, 1, s.x - 2, 2), Color("8a6a3a"))
		var c: Vector2 = s * 0.5 + Vector2(0, 1)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 3), c + Vector2(5, 3), c + Vector2(0, -3)]), Color("e0a840"))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = true
				_moved = false
				_press_pos = event.position
			else:
				if _pressed and not _moved:
					clicked.emit()
				_pressed = false
		elif event is InputEventMouseMotion and _pressed and not _moved:
			if event.position.distance_to(_press_pos) >= DRAG_START_PX:
				_moved = true
				drag_requested.emit()


func _build_tab() -> void:
	_tab_layer = CanvasLayer.new()
	_tab_layer.name = "CollapsedTab"
	_tab_layer.layer = 100
	_tab_layer.visible = _collapsed
	add_child(_tab_layer)
	var tab: TabView = TabView.new()
	tab.name = "Tab"
	_tab_layer.add_child(tab)
	tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tab.clicked.connect(func() -> void: set_collapsed(false))
	tab.drag_requested.connect(start_drag)
	_tab = tab


# ===========================================================================
# BANDEJA (só Windows e macOS)
# ===========================================================================

func _tray_supported() -> bool:
	if not ClassDB.class_exists("StatusIndicator"):
		return false
	if tray_force and _native:
		return true   # só para testes em Linux
	return _native and ["Windows", "macOS"].has(OS.get_name())


func _setup_tray() -> void:
	if _tray != null or not _tray_supported():
		return
	if not bool(_sget("tray_enabled", true)):
		return
	_tray_menu = PopupMenu.new()
	_tray_menu.name = "TrayMenu"
	_tray_menu.prefer_native_menu = true
	add_child(_tray_menu)
	_tray_menu.id_pressed.connect(_on_tray_menu)
	_tray = ClassDB.instantiate("StatusIndicator")
	_tray.name = "Tray"
	add_child(_tray)
	_tray.set("icon", _make_tray_icon())
	_tray.set("tooltip", String(ProjectSettings.get_setting("application/config/name", "Quantos Dias?")))
	_tray.set("menu", _tray.get_path_to(_tray_menu))
	_tray.connect("pressed", _on_tray_pressed)
	_refresh_tray()
	var i18n: Node = get_node_or_null("/root/I18n")
	if i18n != null and i18n.has_signal("locale_changed"):
		i18n.connect("locale_changed", func(_c: String) -> void: _refresh_tray())


func _teardown_tray() -> void:
	if _tray != null:
		_tray.queue_free()
		_tray = null
	if _tray_menu != null:
		_tray_menu.queue_free()
		_tray_menu = null


## Reescreve os itens (idioma mudou, estado de "sempre por cima" mudou).
func _refresh_tray() -> void:
	if _tray_menu == null:
		return
	_tray_menu.clear()
	_tray_menu.add_item(tr_tray("ui.tray_show"), TRAY_SHOW)
	_tray_menu.add_item(tr_tray("ui.tray_collapse"), TRAY_COLLAPSE)
	_tray_menu.add_separator()
	_tray_menu.add_item(tr_tray("ui.tray_reset"), TRAY_RESET)
	_tray_menu.add_check_item(tr_tray("ui.tray_top"), TRAY_TOP)
	_tray_menu.set_item_checked(_tray_menu.get_item_index(TRAY_TOP), bool(_sget("always_on_top", false)))
	_tray_menu.add_separator()
	_tray_menu.add_item(tr_tray("ui.tray_quit"), TRAY_QUIT)


func _on_tray_menu(id: int) -> void:
	match id:
		TRAY_SHOW:
			_bring_to_front()
		TRAY_COLLAPSE:
			set_collapsed(true)
		TRAY_RESET:
			reset_position()
		TRAY_TOP:
			set_always_on_top(not bool(_sget("always_on_top", false)))
		TRAY_QUIT:
			quit_game()


func _on_tray_pressed(button: int, _pos: Vector2i) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_bring_to_front()


## Restaura da aba, tira do minimizado e traz para a frente.
func _bring_to_front() -> void:
	set_collapsed(false)
	if _native:
		var win: Window = get_window()
		if win.mode == Window.MODE_MINIMIZED:
			win.mode = Window.MODE_WINDOWED
		DisplayServer.window_move_to_foreground()


func _make_tray_icon() -> ImageTexture:
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(2, 14):
		for x in range(1, 15):
			var edge: bool = x == 1 or x == 14 or y == 2 or y == 13
			img.set_pixel(x, y, Color("6b563d") if edge else Color("241c16"))
	for y in range(5, 11):
		for x in range(5, 11):
			img.set_pixel(x, y, Color("e0a840"))
	return ImageTexture.create_from_image(img)
