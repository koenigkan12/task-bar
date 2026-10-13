extends SceneTree
## Capturas da gaveta em estados fixos (344×208 lógicos) com o Game falso.
## Rodar (precisa de vídeo): xvfb-run -a -s "-screen 0 1280x720x24" godot --path . \
##   --rendering-driver opengl3 --script res://tests/ui_drawer_shot.gd -- <pasta_de_saida>
## Fundo da faixa: assets/art/env/_preview_bunker_lit.png (prévia do ambiente, 2 salas, ×4).

const W: int = 344
const H: int = 208
var out_dir: String = "user://"
var g: Node
var d: Drawer
var i18n: Node


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0].trim_suffix("/") + "/"
	_run.call_deferred()


func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(4)
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("captura: ", out_dir + name + ".png ", img.get_size())


func _run() -> void:
	root.size = Vector2i(W * 2, H * 2)
	root.content_scale_size = Vector2i(W, H)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	i18n = root.get_node("/root/I18n")
	i18n.set_locale("pt_BR")
	var bg := ColorRect.new()
	bg.color = UiTheme.DARK1
	bg.size = Vector2(W, H)
	root.add_child(bg)
	var strip := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/art/env/_preview_bunker_lit.png")
	at.region = Rect2(0, 360, 1632, 352)
	strip.texture = at
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.size = Vector2(408, 88)
	strip.position = Vector2(0, Drawer.DRAWER_H)
	strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(strip)
	g = load("res://tests/ui_drawer_fake_game.gd").new()
	root.add_child(g)
	d = load("res://scenes/ui/drawer.tscn").instantiate()
	d.bind_game(g)
	root.add_child(d)
	await _frames(2)

	d.open("build")
	d.build_tab.select_item("canteiro")
	await _shot("drawer_build")
	d.build_tab.select_item("gotejador")
	await _shot("drawer_build_locked")
	d.build_tab.select_item("vaso")
	d.build_tab.press_buy()
	await _shot("drawer_place")
	d.cancel_placement()
	d.select_instance(3)
	await _shot("drawer_instance")
	d.build_tab.select_item(DrawerBuildTab.ANTENNA)
	await _shot("drawer_antenna")
	d.show_tab("radio")
	await _shot("drawer_radio")
	g.contact = true
	d.show_tab("build")
	await _shot("drawer_build2")
	g.welcome_back.emit({"hours": 9, "visits": 3, "scrap": 42, "harvested": 6, "nights": 1, "lines": ["l2_arrival", "l2_p1"], "capped": false})
	await _shot("drawer_welcome")
	i18n.set_locale("en")
	d.show_tab("build")
	d.build_tab.select_item("calha")
	await _shot("drawer_build_en")
	i18n.set_locale("pt_BR")
	d.close()
	strip.position = Vector2(0, 0)
	d.toast("toast.item_done", {"item": "Gotejador"}, "check")
	await create_timer(0.8).timeout
	await _shot("drawer_closed_toast")
	# Sim de verdade (autoload Game), depois de meio dia de jogo
	strip.position = Vector2(0, Drawer.DRAWER_H)
	var real: Node = root.get_node("/root/Game")
	real.save_path = "user://ui_drawer_shot.json"
	real.sim.new_game(7, 9.0)
	real.debug_advance_minutes(8 * 60)
	d.bind_game(real)
	d.toasts().clear_all()
	d.open("build")
	d.build_tab.select_item("prateleira")
	await _shot("drawer_real_build")
	d.select_instance(int(real.instances()[0]["id"]))
	await _shot("drawer_real_instance")
	d.show_tab("radio")
	await _shot("drawer_real_radio")
	d.free()
	quit()
