extends Node
# Teste visual da fonte do jogo (importada, sem suavizacao). Salva PNG do viewport em $OUT_PNG.
const FONT := "res://assets/fonts/Jersey15-Regular.ttf"

func _ready() -> void:
	var win := get_window()
	win.size = Vector2i(344, 208)
	win.content_scale_size = Vector2i(344, 208)
	var bg := ColorRect.new()
	bg.color = Color("3d352e")
	bg.size = Vector2(344, 208)
	add_child(bg)
	var f: Font = load(FONT)
	var lines: Array = [
		["Ação não é opção — vovó.", 15, "título"],
		["Ação não é opção — vovó.", 13, "normal"],
		["Ação não é opção — vovó.", 12, "pequeno"],
		["Sucata: 1.280  Cestos: 12/20  Antena 3", 13, ""],
		["0123456789 ÇÃÉÕÊÓÍÚ çãéõêóíú", 13, ""],
		["Dia 14 · 06:30 · +18 sucata/dia (energia 45/60)", 12, ""],
		["Você precisa de uma sala a mais. Cava a terra, constrói devagar.", 12, ""],
	]
	var y := 4
	for l in lines:
		var lab := Label.new()
		lab.text = l[0]
		lab.add_theme_font_override("font", f)
		lab.add_theme_font_size_override("font_size", l[1])
		lab.add_theme_color_override("font_color", Color("e9e2d0"))
		lab.position = Vector2(4, y)
		add_child(lab)
		y += l[1] + 5
	# faixa de 88 px (como a do jogo) com texto normal
	var strip := ColorRect.new()
	strip.color = Color("2a2420")
	strip.position = Vector2(0, 120)
	strip.size = Vector2(344, 88)
	add_child(strip)
	var s2 := Label.new()
	s2.text = "Sucata 128   Antena 2   dia 3"
	s2.add_theme_font_override("font", f)
	s2.add_theme_font_size_override("font_size", 13)
	s2.add_theme_color_override("font_color", Color("e0a52e"))
	s2.position = Vector2(6, 124)
	add_child(s2)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT_PNG"))
	get_tree().quit()
