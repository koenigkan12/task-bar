extends SceneTree
# Capturas das telas para olhar (precisa de render: xvfb-run + --rendering-driver opengl3).
# OUT_DIR=<pasta> godot --path . --rendering-driver opengl3 --script res://tests/ui_screens_shot.gd

const Fakes = preload("res://tests/ui_screens_fakes.gd")

var f: Dictionary
var out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	out_dir = OS.get_environment("OUT_DIR")
	if out_dir == "":
		out_dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	f = Fakes.install(self)
	f["Game"].saved = true
	var lang: String = OS.get_environment("LANG_CODE")
	root.get_node("I18n").call("set_locale", lang if lang != "" else "pt_BR")
	await _shot_scene("title", Vector2i(344, 208), func(h: Control) -> void:
		var t: TitleScreen = (load("res://scenes/ui/title.tscn") as PackedScene).instantiate()
		t.use_live_bunker = false
		h.add_child(t))
	await _shot_scene("title_confirm", Vector2i(344, 208), func(h: Control) -> void:
		var t: TitleScreen = (load("res://scenes/ui/title.tscn") as PackedScene).instantiate()
		t.use_live_bunker = false
		h.add_child(t)
		(t.find_child("New", true, false) as Button).pressed.emit())
	await _shot_scene("options", Vector2i(344, 208), func(h: Control) -> void:
		h.add_child((load("res://scenes/ui/options.tscn") as PackedScene).instantiate()))
	await _shot_scene("options_scrolled", Vector2i(344, 208), func(h: Control) -> void:
		var o: Control = (load("res://scenes/ui/options.tscn") as PackedScene).instantiate()
		h.add_child(o)
		await process_frame
		(o.find_child("*", true, false) as Node)
		var sc: ScrollContainer = _first_of(o, ScrollContainer)
		sc.scroll_vertical = 999)
	await _shot_scene("strip_handle_hint", Vector2i(344, 88), func(h: Control) -> void:
		h.add_child(_strip_bg())
		h.add_child((load("res://scenes/ui/handle.tscn") as PackedScene).instantiate())
		var hl := HintLayer.new()
		h.add_child(hl)
		await process_frame
		hl.show_hint("hide", true)
		await process_frame)
	await _shot_scene("tab_collapsed", Vector2i(48, 16), func(h: Control) -> void:
		h.add_child(_strip_bg())
		var hd: WindowHandle = (load("res://scenes/ui/handle.tscn") as PackedScene).instantiate()
		h.add_child(hd)
		await process_frame
		hd.set_collapsed(true)
		f["Game"].unread = 1
		hd.notify_attention()
		hd._pulse_left = 0.0
		hd._update_light())
	await _shot_scene("ending_arrival_page", Vector2i(344, 88), func(h: Control) -> void:
		h.add_child(_strip_bg())
		var e: EndingScreen = (load("res://scenes/ui/ending.tscn") as PackedScene).instantiate()
		h.add_child(e)
		await process_frame
		e.play_arrival()
		e._next_page()
		e._next_page())
	await _shot_scene("ending_arrival_end", Vector2i(344, 88), func(h: Control) -> void:
		h.add_child(_strip_bg())
		var e: EndingScreen = (load("res://scenes/ui/ending.tscn") as PackedScene).instantiate()
		h.add_child(e)
		await process_frame
		e.play_arrival()
		e.skip_to_end())
	await _shot_scene("ending_next_day", Vector2i(344, 88), func(h: Control) -> void:
		h.add_child(_strip_bg())
		var e: EndingScreen = (load("res://scenes/ui/ending.tscn") as PackedScene).instantiate()
		h.add_child(e)
		await process_frame
		e.show_next_day())
	await _shot_scene("ending_demo", Vector2i(344, 88), func(h: Control) -> void:
		h.add_child(_strip_bg())
		var e: EndingScreen = (load("res://scenes/ui/ending.tscn") as PackedScene).instantiate()
		h.add_child(e)
		await process_frame
		e.show_demo_end())
	quit()


func _shot_scene(name: String, sz: Vector2i, setup: Callable) -> void:
	root.size = sz
	root.content_scale_size = sz
	var host := Control.new()
	host.size = Vector2(sz)
	host.clip_contents = true
	root.add_child(host)
	await setup.call(host)
	for i in 50:   # deixa as transições (0,6 s) terminarem
		await process_frame
	await create_timer(0.8).timeout
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name, " ", img.get_size())
	host.queue_free()
	await process_frame


func _strip_bg() -> Control:
	var tr := TextureRect.new()
	tr.texture = TitleScreen._static_strip()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _first_of(n: Node, klass: Variant) -> Node:
	for c in n.get_children():
		if is_instance_of(c, klass):
			return c
		var r: Node = _first_of(c, klass)
		if r != null:
			return r
	return null
