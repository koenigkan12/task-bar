class_name VilaFlora
extends Node2D
## Flores da Floração no chão perto da mata (só desenho). De noite elas brilham, numa camada que o
## escuro da noite não apaga, como os vaga-lumes. Somem onde vira prédio ou caminho de obra.

const TILE := 16
const GLOW_LILAS := Color(0.78, 0.66, 0.95)
const GLOW_CREME := Color(1.0, 0.95, 0.78)

var sim: VilaSim
var night_k := 0.0
var _tex: Texture2D
var _cells: Array = []                 # [Vector2i, frame]
var _acc := 99.0
var _t := 0.0
var _glow: Node2D


func setup(s: VilaSim, flower_tex: Texture2D) -> void:
	sim = s
	_tex = flower_tex
	z_index = -4
	var gl := CanvasLayer.new()
	gl.layer = 1
	gl.follow_viewport_enabled = true
	add_child(gl)
	_glow = Node2D.new()
	_glow.draw.connect(_draw_glow)
	gl.add_child(_glow)


static func _hash(c: Vector2i) -> int:
	return absi((c.x * 73856093) ^ (c.y * 19349663) ^ 0x5bd1e995) % 1000


func _rebuild() -> void:
	_cells.clear()
	var pct := int(sim.bal["map"].get("flowers_per_mil", 150))
	for y in sim.h:
		for x in sim.w:
			var c := Vector2i(x, y)
			var k := sim.terrain_at(c)
			if (k != VilaSim.T_GROUND and k != VilaSim.T_STUMP) or sim.occ[sim._i(c)] >= 0:
				continue
			var hs := _hash(c)
			if hs >= pct:
				continue
			var near_tree := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if sim.terrain_at(c + Vector2i(dx, dy)) == VilaSim.T_TREE:
						near_tree = true
			if near_tree:
				_cells.append([c, hs % 2])


func update_flora(delta: float, nk: float) -> void:
	if sim == null:
		return
	night_k = nk
	_t += delta
	_acc += delta
	if _acc >= 1.0:
		_acc = 0.0
		_rebuild()
		queue_redraw()
	_glow.queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	for e in _cells:
		var c: Vector2i = e[0]
		var hs := _hash(c)
		var at := Vector2(c) * TILE + Vector2(2 + hs % 8, 3 + (hs / 8) % 7)
		draw_texture_rect_region(_tex, Rect2(at, Vector2(7, 7)), Rect2(int(e[1]) * 7, 0, 7, 7))


func _draw_glow() -> void:
	var lv := clampf((night_k - 0.35) / 0.4, 0.0, 1.0)
	if lv <= 0.0:
		return
	for e in _cells:
		var c: Vector2i = e[0]
		var hs := _hash(c)
		var at := Vector2(c) * TILE + Vector2(2 + hs % 8, 3 + (hs / 8) % 7) + Vector2(3.5, 2.5)
		var pulse := 0.6 + 0.4 * sin(_t * 1.3 + float(hs))
		var col := GLOW_LILAS if int(e[1]) == 0 else GLOW_CREME
		_glow.draw_circle(at, 4.5, Color(col, 0.12 * lv * pulse))
		_glow.draw_circle(at, 2.5, Color(col, 0.25 * lv * pulse))
		_glow.draw_rect(Rect2(at.round() - Vector2(0.5, 0.5), Vector2(1, 1)), Color(col, 0.9 * lv))
