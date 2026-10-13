class_name BunkerObject
extends Node2D
## Um objeto da cena: instância comprada (instance_id >= 0) ou objeto fixo (fixed_id).
## Posição do nó = pés (base-centro). Em obra: silhueta escura, parte pronta revelada de baixo
## para cima, andaime e barrinha de progresso. Estruturas de plantio desenham as plantas.

## Itens pendurados na parede (pés acima da linha do chão).
const WALL_ITEMS := {"foto": 62, "foto_dela": 62}
## Itens da superfície (sem coluna): pés na grama, à direita do mastro da antena.
const SURFACE_ITEMS := {"painel": Vector2(88, 25)}

var instance_id: int = -1
var fixed_id: String = ""
var item: String = ""
var room: int = 1
var col: int = 0
var cols: int = 1
var building: bool = false
var build_ratio: float = 1.0

var sprite: ArtSprite
var _ghost: ArtSprite
var _crops: Dictionary = {}   # índice do plot -> ArtSprite
var _scaffold: Node2D


func _init(art_name: String = "") -> void:
	item = art_name
	_ghost = ArtSprite.new(art_name)
	_ghost.modulate = BunkerGeo.pal("dark2")
	_ghost.visible = false
	add_child(_ghost)
	sprite = ArtSprite.new(art_name)
	add_child(sprite)
	_scaffold = Node2D.new()
	_scaffold.draw.connect(_draw_scaffold)
	_scaffold.z_index = 2
	add_child(_scaffold)
	_auto_play()


func _auto_play() -> void:
	# Máquinas animam sozinhas; a bicicleta só quando ele pedala.
	var f := BunkerArt.fps(item)
	sprite.playing = f > 0.0 and item != "bicicleta" and not building


## Atualiza a partir de uma entrada de Game.instances().
func apply(d: Dictionary) -> void:
	instance_id = int(d.get("id", -1))
	room = int(d.get("room", 1))
	col = int(d.get("col", 0))
	cols = int(d.get("cols", 1))
	var b := String(d.get("state", "ready")) == "building"
	var r := float(d.get("build_ratio", 1.0))
	if b != building or not is_equal_approx(r, build_ratio):
		building = b
		build_ratio = r
		_ghost.visible = building
		sprite.reveal = build_ratio if building else 1.0
		_scaffold.queue_redraw()
		for c: ArtSprite in _crops.values():
			c.visible = not building
		_auto_play()
	position = foot_for(item, room, col, cols)


static func foot_for(it: String, rm: int, c: int, n: int) -> Vector2:
	if SURFACE_ITEMS.has(it):
		return SURFACE_ITEMS[it]
	var p := BunkerGeo.block_foot(rm, c, n)
	if WALL_ITEMS.has(it):
		p.y = WALL_ITEMS[it] + BunkerGeo.floor_dy(rm)
	return p


## Plantas: lista de entradas de Game.plots() desta instância.
func apply_plots(list: Array) -> void:
	var spots := BunkerArt.plots(item)
	var seen := {}
	var top_left := -BunkerArt.anchor(item)
	for p: Dictionary in list:
		var idx := int(p.get("index", 0))
		if idx >= spots.size():
			continue
		seen[idx] = true
		var art := "crop_" + String(p.get("crop", "batata"))
		var cs: ArtSprite = _crops.get(idx)
		if cs == null:
			cs = ArtSprite.new(art)
			cs.z_index = 1
			add_child(cs)
			_crops[idx] = cs
		cs.art = art
		cs.frame = clampi(int(p.get("stage", 0)), 0, 3)
		var spot: Array = spots[idx]
		cs.position = top_left + Vector2(float(spot[0]), float(spot[1]))
		cs.visible = not building and String(p.get("crop", "")) != ""
	for idx: int in _crops.keys():
		if not seen.has(idx):
			_crops[idx].queue_free()
			_crops.erase(idx)


func plot_world_pos(idx: int) -> Vector2:
	var cs: ArtSprite = _crops.get(idx)
	return position + (cs.position if cs != null else Vector2.ZERO)


func bounds() -> Rect2:
	var r := sprite.bounds()
	r.position += position
	return r


func _draw_scaffold() -> void:
	if not building:
		return
	var r := sprite.bounds()
	var x0 := r.position.x - 1
	var x1 := r.end.x
	var top := r.position.y - 2
	var pole := BunkerGeo.pal("rust2")
	var board := BunkerGeo.pal("conc3")
	_scaffold.draw_rect(Rect2(x0, top, 1, -top), pole)
	_scaffold.draw_rect(Rect2(x1, top, 1, -top), pole)
	var y := -6.0
	while y > top:
		_scaffold.draw_rect(Rect2(x0, y, x1 - x0 + 1, 1), board)
		y -= 10.0
	# barrinha de progresso acima do andaime
	var bw := maxf(8.0, x1 - x0 - 3.0)
	var bx := (x0 + x1 + 1 - bw) * 0.5
	_scaffold.draw_rect(Rect2(bx - 1, top - 4, bw + 2, 3), BunkerGeo.pal("ink"))
	_scaffold.draw_rect(Rect2(bx, top - 3, floorf(bw * build_ratio), 1), BunkerGeo.pal("amber2"))
