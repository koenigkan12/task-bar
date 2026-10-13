extends SceneTree
## Teste lógico da gaveta com um Game falso (tests/ui_drawer_fake_game.gd).
## Rodar: godot --headless --path . --script res://tests/ui_drawer_test.gd

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


func _find(node: Node, name: String) -> Node:
	return node.find_child(name, true, false)


func _called(kind: String) -> Array:
	var out: Array = []
	for c: Array in g.calls:
		if c[0] == kind:
			out.append(c)
	return out


func _run() -> void:
	await _frames(2)
	root.get_node("/root/I18n").set_locale("pt_BR")
	g = load("res://tests/ui_drawer_fake_game.gd").new()
	root.add_child(g)
	d = load("res://scenes/ui/drawer.tscn").instantiate()
	d.bind_game(g)
	root.add_child(d)
	await _frames(2)

	_check(not d.is_open(), "começa fechada")
	_check(not (d.get_node("Panel") as Control).visible, "painel escondido")
	d.open("build")
	await _frames(2)
	_check(d.is_open() and d.current_tab() == "build", "abre na aba Construir")
	_check(d.overlay().mode == "select", "faixa em modo de escolher objeto")

	# catálogo
	var rows: int = 0
	for c in d.build_tab.find_children("*", "Button", true, false):
		if (c as Button).theme_type_variation == "FlatButton":
			rows += 1
	_check(rows >= 11, "lista do catálogo + antena (%d)" % rows)
	for i in DrawerBuildTab.FILTERS.size() + 1:
		d.build_tab.cycle_filter(1)
		_check(DrawerBuildTab.FILTERS[d.build_tab._filter] != "casa", "filtro 'casa' escondido antes do contato")
	d.build_tab.set_filter("")

	# comprar com posicionamento
	d.build_tab.select_item("vaso")
	var buy: Button = _find(d, "BuyButton")
	_check(buy != null and not buy.disabled, "comprar vaso habilitado")
	_check(buy != null and buy.text == "Comprar 6", "texto do botão com custo")
	d.build_tab.press_buy()
	_check(d.placement_mode() == "buy" and d.overlay().mode == "place", "entra no modo de posicionar")
	_check(d.overlay().hints.size() == 3, "mostra as 3 posições")
	_check(_find(d, "CancelButton") != null, "botão cancelar no detalhe")
	var r: Rect2 = DrawerPlacementOverlay.block_rect(2, 4, 1)
	_check(r.position == Vector2(8 + 64, 40 + 102) and r.size == Vector2(16, 40), "geometria da coluna (sala 2 desce um andar, col 4)")
	_check(d.overlay().index_at(r.get_center()) == 1, "clique cai na posição certa")
	d.overlay().pick(1)
	await _frames(1)
	_check(_called("buy").size() == 1 and _called("buy")[0] == ["buy", "vaso", 2, 4], "compra na sala 2, coluna 4")
	_check(d.placement_mode() == "", "sai do modo de posicionar")
	_check(d.toasts().current_text().contains("Vaso"), "aviso de obra: " + d.toasts().current_text())

	# sem dinheiro: botão desabilitado, fixar objetivo
	d.build_tab.select_item("gotejador")
	buy = _find(d, "BuyButton")
	_check(buy != null and buy.disabled, "gotejador sem sucata: desabilitado")
	var pin: Button = _find(d, "PinButton")
	_check(pin != null, "botão fixar objetivo")
	d.build_tab.press_pin()
	_check(g.pinned == "gotejador", "objetivo fixado")
	d.build_tab.press_pin()
	_check(g.pinned == "", "objetivo limpo")

	# antena
	d.build_tab.select_item(DrawerBuildTab.ANTENNA)
	var ab: Button = _find(d, "AntennaButton")
	_check(ab != null and ab.disabled, "antena: requisitos faltando, botão desabilitado")

	# objeto na faixa: cultura, mover, desmontar
	d.select_instance(1)
	await _frames(1)
	_check(_find(d, "MoveButton") != null and _find(d, "DemolishButton") != null, "mover/desmontar")
	d.build_tab.press_crop("feijao")
	_check(_called("crop") == [["crop", 1, "feijao"]], "troca a cultura do vaso")
	d.build_tab.press_move()
	_check(d.placement_mode() == "move", "modo mover")
	d.overlay().pick(0)
	await _frames(1)
	_check(_called("move") == [["move", 1, 1, 5]], "move para sala 1, coluna 5")
	d.toasts().clear_all()
	d.build_tab.press_demolish(false)
	_check(_find(d, "ConfirmYes") != null, "pede confirmação ao desmontar")
	d.build_tab.press_demolish(true)
	await _frames(1)
	_check(_called("demolish") == [["demolish", 1]], "desmonta")
	_check(d.toasts().current_text().contains("desmontado"), "aviso de desmontado: " + d.toasts().current_text())
	_check(d.build_tab.selected_instance() == -1, "seleção some depois de desmontar")
	d.select_instance(4)
	d.toasts().clear_all()
	d.build_tab.press_demolish(true)
	_check(d.toasts().current_text() == "Esse só se troca por um melhor.", "recusa traduzida: " + d.toasts().current_text())
	d.select_instance(2)
	d.build_tab.press_crop("")
	_check(g.crop_order(2) == "" and _called("crop").back() == ["crop", 2, ""], "cultura automática")
	_check(DrawerBuildTab.missing_text("missing.item", {"item": "mesinha"}) == "Precisa de Mesinha", "requisito com item: " + DrawerBuildTab.missing_text("missing.item", {"item": "mesinha"}))

	# rádio
	d.show_tab("radio")
	await _frames(1)
	_check(d.radio_tab._unread.text == "3 falas novas", "contador de novas: " + d.radio_tab._unread.text)
	_check(d.radio_tab._list.get_child_count() == 4, "4 entradas no diário")
	_check(_called("read").is_empty(), "não marca lido só de abrir")
	d.show_tab("build")
	_check(_called("read").size() == 1, "marca lido ao sair da aba")
	_check(InfoCard.doing_key(g) == "status.building", "estado: em obra (há obras ativas)")

	# bem-vindo de volta
	d.close()
	g.welcome_back.emit({"hours": 9, "visits": 3, "scrap": 42, "harvested": 6, "nights": 1, "lines": ["l2_arrival"], "capped": false})
	await _frames(1)
	_check(d.is_open() and d.welcome_visible(), "resumo abre a gaveta")
	(_find(d, "RadioButton") as Button).pressed.emit()
	_check(d.current_tab() == "radio" and not d.welcome_visible(), "resumo leva ao rádio")

	# 4ª aba e limite
	d.add_tab("options", "tab.options", "gear", Control.new())
	_check(d._tab_ids.size() == 3, "3ª aba aceita")
	d.add_tab("more", "tab.options", "gear", Control.new())
	_check(d._tab_ids.size() == 4, "4ª aba aceita")
	var extra := Control.new()
	d.add_tab("extra", "tab.options", "gear", extra)
	_check(d._tab_ids.size() == 4, "5ª aba recusada")
	extra.free()

	# idioma
	root.get_node("/root/I18n").set_locale("en")
	await _frames(1)
	_check((_find(d, "Tab_build") as Button).text == "Build", "abas trocam de idioma")
	root.get_node("/root/I18n").set_locale("pt_BR")

	d.toggle()
	_check(not d.is_open(), "toggle fecha")
	print("ui_drawer_test: %d ok, %d falhas" % [_ok, _fail])
	d.free()
	g.free()
	quit(1 if _fail > 0 else 0)
