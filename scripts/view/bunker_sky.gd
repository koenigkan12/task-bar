class_name BunkerSky
extends Node2D
## Céu da superfície (y 0–24) pintado por código conforme a hora: degradê de paleta com dither,
## ruínas ao longe e estrelas de madrugada. Regenera só quando a hora muda de faixa (10 min).

## Quadros-chave: hora -> [topo, base, ruínas] (nomes da paleta).
const KEYS := [
	[0.0, "ink", "dark1", "dark1"],
	[4.5, "ink", "dark2", "dark1"],
	[5.6, "dark2", "rust2", "dark2"],
	[6.6, "cloth1", "rust3", "dark3"],
	[7.3, "cloth2", "rust4", "conc1"],
	[8.0, "cloth2", "conc4", "conc2"],
	[16.5, "cloth2", "conc4", "conc2"],
	[17.6, "cloth2", "rust4", "conc1"],
	[18.4, "cloth1", "rust3", "dark3"],
	[19.2, "dark2", "rust2", "dark3"],
	[20.5, "dark1", "dark2", "dark2"],
	[24.0, "ink", "dark1", "dark1"],
]

var _img: Image
var _tex: ImageTexture
var _width: int = 0
var _slot: int = -1
var _ruins: PackedInt32Array = PackedInt32Array()   # altura das ruínas por coluna (0 = nada)
var _ruin_alt: PackedByteArray = PackedByteArray()  # 1 = tom alternativo


func refresh(tod: float, width: int, force: bool = false) -> void:
	var slot := int(floor(fposmod(tod, 24.0) * 6.0))
	if not force and slot == _slot and width == _width:
		return
	if width != _width:
		_make_ruins(width)
	_width = width
	_slot = slot
	_paint(fposmod(tod, 24.0))
	queue_redraw()


func _make_ruins(width: int) -> void:
	_ruins.resize(width)
	_ruin_alt.resize(width)
	_ruins.fill(0)
	var r := RandomNumberGenerator.new()
	r.seed = 4
	var x := 0
	while x < width:
		var bw := r.randi_range(5, 14)
		var bh := r.randi_range(2, 8)
		var alt := 1 if r.randf() < 0.4 else 0
		for xx in range(x, mini(width, x + bw)):
			_ruins[xx] = bh
			_ruin_alt[xx] = alt
		x += bw + r.randi_range(0, 6)


static func _key_at(tod: float) -> Array:
	# devolve [chaveA, chaveB, t]
	for i in range(KEYS.size() - 1):
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if tod >= float(a[0]) and tod <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			var t := 0.0 if span <= 0.0 else (tod - float(a[0])) / span
			return [a, b, t]
	return [KEYS[0], KEYS[0], 0.0]


## Quão "noite" está (0..1), para as estrelas.
static func night_amount(tod: float) -> float:
	if tod < 4.5 or tod > 20.5:
		return 1.0
	if tod < 5.6:
		return 1.0 - (tod - 4.5) / 1.1
	if tod > 19.2:
		return (tod - 19.2) / 1.3
	return 0.0


func _paint(tod: float) -> void:
	var w := maxi(_width, 1)
	if _img == null or _img.get_width() != w:
		_img = Image.create(w, BunkerGeo.SKY_H, false, Image.FORMAT_RGBA8)
	var k := _key_at(tod)
	var a: Array = k[0]
	var b: Array = k[1]
	var t: float = k[2]
	var stars := night_amount(tod)
	for y in BunkerGeo.SKY_H:
		var gy := float(y) / float(BunkerGeo.SKY_H - 1) * 1.15 - 0.1
		for x in w:
			var thr := BunkerGeo.bayer(x, y)
			# dither no tempo usa a matriz deslocada para não coincidir com o vertical
			var use_b := t > BunkerGeo.bayer(x + 2, y + 1)
			var key: Array = b if use_b else a
			var c := BunkerGeo.pal(key[2] if gy > thr else key[1])
			var rh := _ruins[x] if x < _ruins.size() else 0
			if rh > 0 and y >= BunkerGeo.SKY_H - rh:
				# telhado partido: a primeira linha das ruínas alternativas fica no tom do céu
				var top_row := y == BunkerGeo.SKY_H - rh
				c = BunkerGeo.pal(key[3]) if not (top_row and _ruin_alt[x] == 1 and x % 2 == 0) else c
			elif stars > 0.0 and y < 14 and _is_star(x, y) and stars > BunkerGeo.bayer(x, y):
				c = BunkerGeo.pal("conc4" if (x + y) % 3 else "paper")
			_img.set_pixel(x, y, c)
	if _tex == null or _tex.get_width() != w:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)


static func _is_star(x: int, y: int) -> bool:
	var h := (x * 73856093) ^ (y * 19349663)
	return posmod(h, 97) == 0


func _draw() -> void:
	if _tex != null:
		draw_texture(_tex, Vector2.ZERO)
