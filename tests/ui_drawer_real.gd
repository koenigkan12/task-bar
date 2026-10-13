extends SceneTree
## Gaveta contra o Game/Sim de verdade (autoload): compra com posicionamento, cultura,
## recusa de desmontar, requisitos traduzidos, diário real e resumo de volta.
## Rodar: godot --headless --path . --script res://tests/ui_drawer_real.gd

var _fail: int = 0
var _ok: int = 0
var g: Node
var d: Drawer


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		_ok += 1
	else:
		_fail += 1
		print("FALHOU: ", what)


func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


## Nenhum texto visível com chave crua ou placeholder sobrando.
func _raw_texts() -> Array[String]:
	var bad: Array[String] = []
	for n in d.find_children("*", "Label", true, false):
		var t: String = (n as Label).text
		if not (n as Label).is_visible_in_tree():
			continue
		if t.contains("{") or t.begins_with("missing.") or t.begins_with("drawer.") or t.begins_with("item.") or t.begins_with("ui."):
			bad.append(t)
	for n in d.find_children("*", "Button", true, false):
		var t2: String = (n as Button).text
		if (n as Button).is_visible_in_tree() and (t2.contains("{") or t2.begins_with("drawer.")):
			bad.append(t2)
	return bad


func _run() -> void:
	await _frames(2)
	root.get_node("/root/I18n").set_locale("pt_BR")
	g = root.get_node("/root/Game")
	g.save_path = "user://ui_drawer_real_test.json"
	g.sim.new_game(7, 9.0)
	g.in_game = false   # sem relógio de parede nem autosave durante o teste
	d = load("res://scenes/ui/drawer.tscn").instantiate()
	root.add_child(d)   # liga sozinha ao /root/Game
	await _frames(2)
	_check(d.has_game(), "gaveta ligada ao Game real")
	d.open("build")
	await _frames(2)
	_check(d.build_tab._catalog.size() > 10, "catálogo real (%d itens)" % d.build_tab._catalog.size())
	_check(_raw_texts().is_empty(), "sem chave crua na lista: %s" % str(_raw_texts()))

	# requisitos traduzidos (prateleira pede antena 3)
	d.build_tab.select_item("prateleira")
	await _frames(1)
	_check(_raw_texts().is_empty(), "requisitos traduzidos: %s" % str(_raw_texts()))
	d.build_tab.select_item(DrawerBuildTab.ANTENNA)
	await _frames(1)
	_check(_raw_texts().is_empty(), "antena traduzida: %s" % str(_raw_texts()))

	# juntar sucata e comprar um vaso escolhendo o lugar
	g.debug_advance_minutes(8 * 60)
	d.refresh(true)
	var before: int = g.instances().size()
	d.build_tab.select_item("vaso")
	await _frames(1)
	var e: Dictionary = d.build_tab._entry("vaso")
	_check(str(e.get("status", "")) == "available", "vaso disponível com %d de sucata (status %s)" % [g.sucata(), e.get("status", "")])
	d.build_tab.press_buy()
	_check(d.placement_mode() == "buy" and d.overlay().hints.size() > 0, "posições reais do vaso (%d)" % d.overlay().hints.size())
	var h: Dictionary = d.overlay().hints[0]
	d.overlay().pick(0)
	await _frames(1)
	var after: Array = g.instances()
	_check(after.size() == before + 1, "vaso comprado")
	var placed: Dictionary = after.back()
	_check(int(placed["room"]) == int(h["room"]) and int(placed["col"]) == int(h["col"]), "no lugar clicado")
	_check(d.toasts().current_text().contains("Vaso"), "aviso de obra: " + d.toasts().current_text())

	# objeto inicial: cultura automática e recusa de desmontar (vasos iniciais ficam)
	var first: int = int(after[0]["id"])
	d.select_instance(first)
	await _frames(1)
	_check(d.build_tab._detail_sig != "", "detalhe do objeto")
	d.build_tab.press_crop("")
	_check(str(g.crop_order(first)) == "", "cultura automática")
	d.toasts().clear_all()
	d.build_tab.press_demolish(false)
	d.build_tab.press_demolish(true)
	await _frames(1)
	_check(g.instances().size() == after.size(), "vaso inicial não sai")
	_check(not d.toasts().current_text().begins_with("drawer."), "motivo da recusa traduzido: " + d.toasts().current_text())
	print("  recusa: ", d.toasts().current_text())

	# rádio e estado
	d.show_tab("radio")
	await _frames(1)
	_check(d.radio_tab._list.get_child_count() > 0, "diário real com entradas")
	_check(_raw_texts().is_empty(), "diário traduzido: %s" % str(_raw_texts()))
	d.show_tab("state")
	await _frames(1)
	_check(_raw_texts().is_empty(), "estado traduzido: %s" % str(_raw_texts()))

	# resumo de volta no formato da Sim
	var summary: Dictionary = g.sim.catch_up(10 * 60.0)
	d.show_welcome(summary)
	await _frames(1)
	_check(d.welcome_visible(), "resumo de volta com dados reais %s" % str(summary.keys()))
	_check(_raw_texts().is_empty(), "resumo traduzido: %s" % str(_raw_texts()))

	print("ui_drawer_real: %d ok, %d falhas" % [_ok, _fail])
	d.free()
	g.delete_save()
	quit(1 if _fail > 0 else 0)
