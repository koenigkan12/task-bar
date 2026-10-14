extends RefCounted
## Dublês de Settings, Game, WindowService e AudioManager só para os testes de telas.
## install(tree) troca os autoloads (stubs) por estes; I18n continua o real.


class FakeSettings extends Node:
	signal changed(key: String)
	var data: Dictionary = {}

	func get_value(key: String, default: Variant = null) -> Variant:
		return data.get(key, default)

	func set_value(key: String, value: Variant) -> void:
		if data.get(key) == value:
			return
		data[key] = value
		changed.emit(key)


class FakeGame extends Node:
	signal state_changed()
	signal radio_line(line: Dictionary)
	signal box_state_changed(fill: float, overflow: bool)
	signal welcome_back(summary: Dictionary)
	signal new_game_started()
	signal house_item_bought(item_id: String)
	signal antenna_changed(level: int)
	signal item_finished(instance_id: int, item_id: String)
	var saved: bool = false
	var calls: Array[String] = []
	var unread: int = 0
	var fill: float = 0.3
	var power: bool = true
	var goal: bool = false

	func has_save() -> bool:
		return saved

	func save_summary() -> Dictionary:
		return {"day": 6, "antenna": 3}

	func load_game() -> bool:
		calls.append("load_game")
		return saved

	func new_game() -> void:
		calls.append("new_game")
		saved = true
		new_game_started.emit()

	func delete_save() -> void:
		calls.append("delete_save")
		saved = false

	func unread_count() -> int:
		return unread

	func goal_ready() -> bool:
		return goal

	func box_fill() -> float:
		return fill

	func power_ok() -> bool:
		return power


class FakeWindow extends Node:
	signal hidden_changed(is_hidden: bool)
	var calls: Array = []
	var collapsed: bool = false

	func set_collapsed(on: bool) -> void:
		calls.append(["set_collapsed", on])
		collapsed = on
		hidden_changed.emit(on)

	func is_collapsed() -> bool:
		return collapsed

	func start_drag() -> void:
		calls.append(["start_drag"])

	func set_ui_scale(mode: Variant) -> void:
		calls.append(["set_ui_scale", mode])

	func set_always_on_top(on: bool) -> void:
		calls.append(["set_always_on_top", on])

	func reset_position() -> void:
		calls.append(["reset_position"])

	func quit_game() -> void:
		calls.append(["quit_game"])


class FakeAudio extends Node:
	var calls: Array = []

	func unlock() -> void:
		calls.append(["unlock"])

	func set_mode(mode: String) -> void:
		calls.append(["set_mode", mode])

	func set_master_volume(v: float) -> void:
		calls.append(["set_master_volume", v])


static func install(tree: SceneTree) -> Dictionary:
	var out: Dictionary = {}
	var fakes: Dictionary = {
		"Settings": FakeSettings.new(),
		"Game": FakeGame.new(),
		"WindowService": FakeWindow.new(),
		"AudioManager": FakeAudio.new(),
	}
	for n: String in fakes:
		var old: Node = tree.root.get_node_or_null(n)
		if old != null:
			tree.root.remove_child(old)
			old.free()
		var f: Node = fakes[n]
		f.name = n
		tree.root.add_child(f)
		out[n] = f
	return out
