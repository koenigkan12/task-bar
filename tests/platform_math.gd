extends SceneTree
## Testes headless da matemática PURA de WindowService (escala, posição, monitores, FPS).
## godot --headless --path . --script res://tests/platform_math.gd

const WS = preload("res://scripts/platform/window_service.gd")

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FALHOU: ", what)


func eq(a: Variant, b: Variant, what: String) -> void:
	checks += 1
	if a != b:
		fails += 1
		print("  FALHOU: %s (obtido %s, esperado %s)" % [what, str(a), str(b)])


func _initialize() -> void:
	# --- escala automática: clamp(floor(h/540), 1, 4)
	eq(WS.auto_scale(480), 1, "auto 480")
	eq(WS.auto_scale(539), 1, "auto 539")
	eq(WS.auto_scale(540), 1, "auto 540")
	eq(WS.auto_scale(768), 1, "auto 768")
	eq(WS.auto_scale(1079), 1, "auto 1079")
	eq(WS.auto_scale(1080), 2, "auto 1080")
	eq(WS.auto_scale(1440), 2, "auto 1440")
	eq(WS.auto_scale(1620), 3, "auto 1620")
	eq(WS.auto_scale(2160), 4, "auto 2160 (4K)")
	eq(WS.auto_scale(4320), 4, "auto 8K limitado a 4")
	eq(WS.auto_scale(0), 1, "auto 0")

	# --- configuração de escala
	eq(WS.normalize_scale_setting("auto"), "auto", "norm auto")
	eq(WS.normalize_scale_setting(2), 2, "norm 2")
	eq(WS.normalize_scale_setting(3.0), 3, "norm 3.0 (JSON)")
	eq(WS.normalize_scale_setting(5), "auto", "norm 5")
	eq(WS.normalize_scale_setting(0), "auto", "norm 0")
	eq(WS.normalize_scale_setting(2.5), "auto", "norm 2.5")
	eq(WS.normalize_scale_setting("xyz"), "auto", "norm lixo")
	eq(WS.normalize_scale_setting(null), "auto", "norm null")

	# --- caber na área útil
	eq(WS.fit_scale(4, Vector2i(344, 208), Vector2i(1920, 1040)), 4, "cabe x4")
	eq(WS.fit_scale(4, Vector2i(344, 208), Vector2i(1280, 680)), 3, "x4 não cabe em 680 de altura (832) -> 3 (624)")
	eq(WS.fit_scale(4, Vector2i(608, 208), Vector2i(1280, 680)), 2, "608 largo: x3=1824 > 1280 -> 2")
	eq(WS.fit_scale(3, Vector2i(608, 208), Vector2i(500, 400)), 1, "mínimo 1")
	eq(WS.fit_scale(2, Vector2i(344, 88), Vector2i.ZERO), 2, "área desconhecida: não mexe")
	eq(WS.resolve_scale("auto", Vector2i(344, 88), 1080, Vector2i(1920, 1040)), 2, "resolve auto 1080p")
	eq(WS.resolve_scale("auto", Vector2i(344, 208), 2160, Vector2i(3840, 2100)), 4, "resolve auto 4K")
	eq(WS.resolve_scale(3, Vector2i(344, 88), 1080, Vector2i(1920, 1040)), 3, "resolve fixo 3")
	eq(WS.resolve_scale(4, Vector2i(344, 208), 720, Vector2i(1280, 680)), 3, "fixo 4 reduz para caber")
	eq(WS.resolve_scale("auto", Vector2i(344, 88), 768, Vector2i(1366, 728)), 1, "resolve auto 768")

	# --- crescer mantendo a base e a esquerda
	var r0: Rect2i = Rect2i(100, 952, 688, 176)   # faixa x2 colada em y=1128? (qualquer base)
	var r1: Rect2i = WS.resize_keep_bottom_left(r0, Vector2i(688, 416))
	eq(r1.position.x, 100, "mantém esquerda")
	eq(r1.end.y, r0.end.y, "mantém borda inferior")
	eq(r1.size, Vector2i(688, 416), "novo tamanho")
	eq(r1.position.y, r0.end.y - 416, "cresce para cima")
	var r2: Rect2i = WS.resize_keep_bottom_left(r1, r0.size)
	eq(r2, r0, "voltar ao tamanho = retângulo original")
	eq(WS.rect_from_anchor(Vector2i(0, 1040), Vector2i(688, 176)), Rect2i(0, 864, 688, 176), "rect_from_anchor")

	# --- empurrar para dentro da área
	var usable: Rect2i = Rect2i(0, 0, 1920, 1040)
	eq(WS.shift_into(Rect2i(0, -100, 688, 416), usable), Rect2i(0, 0, 688, 416), "gaveta no topo desce")
	eq(WS.shift_into(Rect2i(1500, 900, 688, 176), usable), Rect2i(1232, 864, 688, 176), "estoura à direita e embaixo")
	eq(WS.shift_into(Rect2i(-50, 500, 100, 50), usable), Rect2i(0, 500, 100, 50), "estoura à esquerda")
	eq(WS.shift_into(Rect2i(30, 40, 100, 50), usable), Rect2i(30, 40, 100, 50), "já dentro: não mexe")
	eq(WS.shift_into(Rect2i(30, 40, 3000, 50), usable).position.x, 0, "maior que a área: alinha à esquerda")
	eq(WS.shift_into(Rect2i(30, 40, 100, 2000), usable).end.y, 1040, "mais alta que a área: alinha embaixo")
	eq(WS.default_anchor(Rect2i(1920, 0, 1920, 1040)), Vector2i(1920, 1040), "âncora padrão")

	# --- monitores simulados: principal + um à direita menor + um acima
	var areas: Array = [Rect2i(0, 0, 1920, 1040), Rect2i(1920, 100, 1280, 700), Rect2i(0, -720, 1280, 720)]
	eq(WS.find_screen(Rect2i(10, 900, 688, 176), areas), 0, "find: principal")
	eq(WS.find_screen(Rect2i(2000, 700, 688, 176), areas), 1, "find: direita")
	eq(WS.find_screen(Rect2i(1500, 500, 688, 176), areas), 0, "find: cruza duas, mais área no 0")
	eq(WS.find_screen(Rect2i(2000, 500, 688, 176), areas), 1, "find: cruza duas, mais área no 1")
	eq(WS.find_screen(Rect2i(5000, 5000, 100, 100), areas), -1, "find: nenhum")
	eq(WS.find_screen(Rect2i(10, -300, 344, 88), areas), 2, "find: monitor de cima")
	eq(WS.nearest_screen(Rect2i(5000, 500, 100, 100), areas), 1, "nearest")

	# --- validação de posição salva
	var v: Dictionary = WS.validate_rect(Rect2i(0, 864, 688, 176), areas)
	ok(v["ok"] and v["screen"] == 0, "válida no principal")
	v = WS.validate_rect(Rect2i(9000, 9000, 688, 176), areas)
	ok(not v["ok"] and v["reason"] == "no_screen", "fora de todos os monitores -> reset (no_screen)")
	v = WS.validate_rect(Rect2i(1900, 700, 688, 176), areas)
	ok(v["ok"], "cruza dois monitores: válida")
	v = WS.validate_rect(Rect2i(1900, 1030, 688, 176), areas)
	ok(not v["ok"] and v["reason"] == "offscreen", "só 10 px visíveis embaixo: offscreen")
	v = WS.validate_rect(Rect2i(0, 0, 2400, 176), [Rect2i(0, 0, 1920, 1040)])
	ok(not v["ok"] and v["reason"] == "too_big", "maior que a área útil: too_big")
	v = WS.validate_rect(Rect2i(0, 0, 100, 1200), [Rect2i(0, 0, 1920, 1040)])
	ok(not v["ok"] and v["reason"] == "too_big", "mais alta que a área útil: too_big")
	v = WS.validate_rect(Rect2i(-600, 864, 688, 176), areas)
	ok(not v["ok"] and v["reason"] == "offscreen", "88 px à vista: offscreen (<96)")
	v = WS.validate_rect(Rect2i(-500, 864, 688, 176), areas)
	ok(v["ok"], "188 px à vista: ok")
	# monitor sumiu: a posição salva no 2º monitor não cruza mais o principal sozinho
	var only_main: Array = [areas[0]]
	v = WS.validate_rect(Rect2i(2100, 600, 688, 176), only_main)
	ok(not v["ok"] and v["reason"] == "no_screen", "monitor desconectado -> reset")

	# --- arrastar
	eq(WS.drag_position(Vector2i(100, 200), Vector2i(500, 500), Vector2i(530, 480)), Vector2i(130, 180), "drag_position")
	var c1: Rect2i = WS.clamp_visible(Rect2i(-5000, 400, 688, 176), areas)
	eq(c1.position.x, 0 - 688 + 96, "clamp esquerda: sobram 96 px")
	var c2: Rect2i = WS.clamp_visible(Rect2i(3400, 400, 688, 176), areas)
	ok(c2.position.x <= 3200 - 96, "clamp direita")
	var c3: Rect2i = WS.clamp_visible(Rect2i(100, 5000, 688, 176), areas)
	ok(c3.position.y <= 1040 - 24, "clamp embaixo: ao menos 24 px à vista")
	eq(WS.clamp_visible(Rect2i(100, 100, 688, 176), areas), Rect2i(100, 100, 688, 176), "clamp: dentro não muda")
	eq(WS.clamp_visible(Rect2i(100, 100, 48, 16), areas), Rect2i(100, 100, 48, 16), "clamp: aba pequena")
	var tiny: Rect2i = WS.clamp_visible(Rect2i(-100, 100, 48, 16), areas)
	ok(tiny.position.x >= -48 + 48, "aba: precisa ficar inteira (48 px)")

	# --- chave de monitor e posição salva
	eq(WS.monitor_key(Rect2i(0, 0, 1920, 1080)), "1920x1080@0,0", "monitor_key")
	eq(WS.monitor_key(Rect2i(1920, -100, 2560, 1440)), "2560x1440@1920,-100", "monitor_key 2")
	var anchor: Vector2i = Vector2i(1920 + 40, 800)
	var area2: Rect2i = Rect2i(1920, 100, 1280, 700)
	var sv: Dictionary = WS.pos_to_saved(anchor, area2)
	eq(sv, {"x": 40, "y": 0}, "pos_to_saved (colado no rodapé)")
	eq(WS.anchor_from_saved(sv, area2), anchor, "ida e volta")
	# a posição salva é relativa: se a barra de tarefas mudar de altura, continua colada no rodapé
	eq(WS.anchor_from_saved(sv, Rect2i(1920, 100, 1280, 650)), Vector2i(1960, 750), "área útil mudou: segue o rodapé")

	# --- escolher a entrada salva
	var fulls: Array = [Rect2i(0, 0, 1920, 1080), Rect2i(1920, 100, 1280, 720)]
	var saved: Dictionary = {"_last": "1280x720@1920,100", "1280x720@1920,100": {"x": 10.0, "y": 5.0}, "1920x1080@0,0": {"x": 3, "y": 0}}
	var pk: Dictionary = WS.pick_saved(saved, fulls, 0)
	eq(pk, {"screen": 1, "x": 10, "y": 5}, "pick: usa o último monitor")
	saved["_last"] = "800x600@0,0"   # monitor que não existe mais
	pk = WS.pick_saved(saved, fulls, 0)
	eq(pk, {"screen": 0, "x": 3, "y": 0}, "pick: último sumiu -> principal")
	eq(WS.pick_saved({}, fulls, 0), {}, "pick: vazio")
	eq(WS.pick_saved("lixo", fulls, 0), {}, "pick: não é dicionário")
	eq(WS.pick_saved({"1920x1080@0,0": {"x": "a", "y": 0}}, fulls, 0), {}, "pick: x inválido")
	eq(WS.pick_saved({"_last": 5, "1920x1080@0,0": {"x": 1, "y": 2}}, fulls, 0), {"screen": 0, "x": 1, "y": 2}, "pick: _last inválido")

	# --- governador de FPS: (collapsed, low, focused, hover, idle_s, dragging)
	eq(WS.fps_for(false, false, true, true, 0.0), 30, "ativo+hover 30")
	eq(WS.fps_for(false, false, true, false, 2.0), 30, "foco+input recente 30")
	eq(WS.fps_for(false, false, true, false, 10.0), 12, "ocioso (10 s) 12")
	eq(WS.fps_for(false, false, true, false, 600.0), 12, "ocioso 12")
	eq(WS.fps_for(false, false, true, true, 600.0), 30, "hover parado 30")
	eq(WS.fps_for(false, false, false, false, 0.0), 8, "sem foco e sem hover 8")
	eq(WS.fps_for(false, false, false, true, 0.0), 30, "sem foco mas com hover 30")
	eq(WS.fps_for(true, false, true, false, 0.0), 2, "recolhido 2")
	eq(WS.fps_for(true, false, true, true, 0.0), 12, "recolhido+hover 12 (desvio)")
	eq(WS.fps_for(false, true, true, false, 600.0), 2, "modo baixo ocioso 2")
	eq(WS.fps_for(false, true, true, true, 0.0), 12, "modo baixo ativo 12 (desvio)")
	eq(WS.fps_for(false, false, true, true, 0.0, true), 60, "arrastando 60 (desvio)")

	print("platform_math: %d verificações, %d falhas" % [checks, fails])
	quit(1 if fails > 0 else 0)
